import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Ba ô ràng buộc nhau bởi phép nhân: khối lượng × đơn giá = thành tiền.
enum TradeField { khoiLuong, donGia, thanhTien }

/// Tính ô [target] từ hai ô còn lại. `null` nghĩa là chưa đủ dữ kiện.
///
/// Kết quả **luôn tròn số**: tiền Việt không có phần lẻ dưới đồng, và chia
/// ngược ra khối lượng hay đơn giá thì hầu như lần nào cũng ra số lẻ vô hạn
/// (5.243.000 chia 1.500 ra 3.495,333…) — không ai ghi vào sổ như vậy.
///
/// Làm tròn khiến ba ô lệch nhau vài trăm đồng; ô thành tiền có dòng báo lệch
/// bao nhiêu so với phép nhân để người dùng tự chỉnh nếu cần.
double? computeTradeField({
  required TradeField target,
  required double? quantity,
  required double? unitPrice,
  required double? amount,
}) {
  bool co(double? v) => v != null && v > 0;

  return switch (target) {
    TradeField.thanhTien => co(quantity) && co(unitPrice)
        ? (quantity! * unitPrice!).roundToDouble()
        : null,
    TradeField.donGia =>
      co(amount) && co(quantity) ? (amount! / quantity!).roundToDouble() : null,
    TradeField.khoiLuong =>
      co(amount) && co(unitPrice) ? (amount! / unitPrice!).roundToDouble() : null,
  };
}

/// Viết một con số vào ô nhập — **không có dấu phân cách hàng nghìn**.
///
/// Ô nhập phải giữ số trần. Điền sẵn "5.243.000" rồi người dùng gõ thêm một
/// chữ số là thành "5.243.0001", và luật đọc số hiểu dấu chấm cuối cùng có 4
/// chữ số đứng sau là dấu thập phân — ra 5.243 thay vì hơn năm triệu. Dấu chấm
/// chỉ dùng lúc **hiện ra** ở danh sách và ô tổng, không dùng trong ô nhập.
String soVaoO(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// Nhóm giao dịch đang xem, theo tình trạng hoá đơn.
enum _InvoiceFilter {
  tatCa('Tất cả', null),
  coHoaDon('Có hoá đơn', true),
  khongHoaDon('Không hoá đơn', false);

  const _InvoiceFilter(this.label, this.value);

  final String label;
  final bool? value;
}

/// **Sổ mua bán** — chỉ tài khoản chủ thấy.
///
/// Ghi từng lần nhập và xuất hàng kèm tiền, và đánh dấu lần nào có xuất hoá
/// đơn. Sổ này tách hẳn khỏi phiếu cân: ghi được cả thứ không qua bàn cân (mua
/// phân bón, tiền dầu) và tự khai khối lượng.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key});

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  final _search = TextEditingController();

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _InvoiceFilter _invoice = _InvoiceFilter.tatCa;
  TradeKind? _kind;
  String? _goodsFilter;
  String? _partnerFilter;

  /// Đang xem trang tổng quan hay sổ giao dịch theo tháng.
  bool _tongQuan = true;

  TradePage _page = const TradePage();
  TradeStock _stock = const TradeStock();
  List<GoodsType> _goods = const [];
  List<Customer> _customers = const [];
  bool _loading = false;
  String? _error;

  ApiClient? get _client => context.read<ServerConnection>().client;

  /// Có đang lọc gì không — để phân biệt "không khớp bộ lọc" với "tháng này
  /// chưa ghi gì", hai chuyện dẫn tới hai việc phải làm khác hẳn nhau.
  bool get _dangLoc =>
      _search.text.trim().isNotEmpty ||
      _kind != null ||
      _invoice != _InvoiceFilter.tatCa ||
      _goodsFilter != null ||
      _partnerFilter != null;

  DateTime get _from => DateTime(_month.year, _month.month, 1);
  DateTime get _to => DateTime(_month.year, _month.month + 1, 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_tongQuan) {
        // Tồn kho cộng dồn cả sổ, không truyền khoảng ngày.
        final ton = await client.tradeStock();
        if (mounted) setState(() => _stock = ton);
        if (_goods.isEmpty) _goods = await client.goodsTypes();
        if (_customers.isEmpty) _customers = await client.customers();
        return;
      }
      final page = await client.trades(
        from: _from,
        to: _to,
        kind: _kind,
        hasInvoice: _invoice.value,
        goodsTypeId: _goodsFilter,
        partnerId: _partnerFilter,
        query: _search.text.trim(),
      );
      // Danh mục chỉ cần tải một lần, dùng cho hộp thoại thêm giao dịch.
      if (_goods.isEmpty) _goods = await client.goodsTypes();
      if (_customers.isEmpty) _customers = await client.customers();
      if (mounted) setState(() => _page = page);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shiftMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  Future<void> _edit([Trade? trade]) async {
    final result = await showDialog<Trade>(
      context: context,
      builder: (context) => _TradeDialog(
        trade: trade,
        goods: _goods,
        customers: _customers,
        defaultDate: _from.isBefore(DateTime.now()) && _to.isAfter(DateTime.now())
            ? DateTime.now()
            : _from,
      ),
    );
    if (result == null || !mounted) return;

    final client = _client;
    if (client == null) return;
    try {
      await client.saveTrade(
        id: trade?.id,
        date: result.date,
        kind: result.kind,
        goodsTypeId: result.goodsTypeId,
        goodsName: result.goodsName,
        partnerId: result.partnerId,
        partnerName: result.partnerName,
        quantity: result.quantity,
        unit: result.unit,
        unitPrice: result.unitPrice,
        amount: result.amount,
        hasInvoice: result.hasInvoice,
        invoiceNo: result.invoiceNo,
        note: result.note,
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Tải file Excel về máy để gửi kế toán.
  ///
  /// Mở thẳng địa chỉ thay vì tải bằng mã rồi tự lưu: máy chủ đã gắn
  /// `Content-Disposition: attachment` nên trình duyệt tự tải, không phải nhồi
  /// cả file vào bộ nhớ của trang.
  ///
  /// Xuất **đúng phần đang lọc**: lọc "chưa có hoá đơn" rồi bấm xuất là ra đúng
  /// danh sách cần đối chiếu, chứ không phải cả sổ.
  Future<void> _xuatExcel() async {
    final client = _client;
    if (client == null) return;

    final uri = _tongQuan
        ? client.downloadUri('/api/giao-dich/tong-quan/xuat-excel')
        : client.downloadUri('/api/giao-dich/xuat-excel', {
            'from': timeToMillis(_from).toString(),
            'to': timeToMillis(_to).toString(),
            if (_kind != null) 'kind': _kind!.value,
            if (_invoice.value != null) 'hoa_don': _invoice.value! ? '1' : '0',
            if (_goodsFilter != null) 'goods_type_id': _goodsFilter!,
            if (_partnerFilter != null) 'partner_id': _partnerFilter!,
            if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
          });

    final xong = await launchUrl(uri, webOnlyWindowName: '_self');
    if (!xong && mounted) {
      setState(() => _error = 'Không mở được đường dẫn tải file: $uri');
    }
  }

  Future<void> _delete(Trade trade) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá giao dịch này?'),
        content: Text(
          '${trade.kind.label} ${trade.goodsName.isEmpty ? "" : "${trade.goodsName} "}'
          '— ${formatMoney(trade.amount)} đ ngày ${formatDate(trade.date)}.\n'
          'Xoá rồi sẽ không còn trong số tổng của kỳ.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.offline),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _client!.deleteTrade(trade.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, 0),
          child: Row(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text('Tổng quan'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.list_alt, size: 18),
                    label: Text('Sổ theo tháng'),
                  ),
                ],
                selected: {_tongQuan},
                showSelectedIcon: false,
                onSelectionChanged: (c) {
                  setState(() => _tongQuan = c.first);
                  _load();
                },
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _xuatExcel,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Xuất Excel'),
              ),
              const SizedBox(width: AppTheme.gapSm),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Ghi giao dịch'),
              ),
              const SizedBox(width: AppTheme.gapXs),
              IconButton(
                tooltip: 'Làm mới',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
        ),
        if (!_tongQuan) _toolbar(),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
            child: NoticeBar(
              icon: Icons.error_outline,
              color: AppTheme.offline,
              text: _error!,
            ),
          ),
        Expanded(
          child: _tongQuan ? _trangTongQuan() : _soTheoThang(),
        ),
      ],
    );
  }

  Widget _soTheoThang() {
    final s = _page.summary;
    return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
            children: [
              _summaryTiles(s),
              const SizedBox(height: AppTheme.gapMd),
              SectionCard(
                title: 'Giao dịch (${_page.items.length})',
                subtitle: 'Tháng ${_month.month}/${_month.year}',
                icon: Icons.swap_horiz,
                padded: false,
                child: _page.items.isEmpty
                    ? EmptyHint(
                        icon: Icons.receipt_long_outlined,
                        message: _dangLoc
                            ? 'Không có giao dịch nào khớp bộ lọc.'
                            : 'Tháng này chưa ghi giao dịch nào.',
                        action: FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add),
                          label: const Text('Ghi giao dịch'),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < _page.items.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _row(_page.items[i]),
                          ],
                        ],
                      ),
              ),
            ],
    );
  }

  /// Trang tổng quan: tồn kho cộng dồn cả sổ, không cắt theo tháng.
  Widget _trangTongQuan() {
    final s = _stock.summary;
    final lines = _stock.lines;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapLg),
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Tồn kho theo sổ',
                value: formatWeight(s.quantityBalance),
                unit: 'kg',
                icon: Icons.inventory_2_outlined,
                tone: s.quantityBalance < 0 ? AppTheme.offline : AppTheme.primary,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Đã nhập',
                value: formatWeight(s.quantityIn),
                unit: 'kg',
                icon: Icons.south_west,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Đã xuất',
                value: formatWeight(s.quantityOut),
                unit: 'kg',
                icon: Icons.north_east,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gapSm),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Tiền mua vào',
                value: formatMoney(s.amountIn),
                unit: 'đ',
                icon: Icons.arrow_downward,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Tiền bán ra',
                value: formatMoney(s.amountOut),
                unit: 'đ',
                icon: Icons.arrow_upward,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Bán trừ mua',
                value: formatMoney(s.amountBalance),
                unit: 'đ',
                icon: Icons.account_balance_wallet_outlined,
                tone: s.amountBalance < 0 ? AppTheme.accent : AppTheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gapMd),
        if (s.amountBalance < 0)
          Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
            child: NoticeBar(
              icon: Icons.info_outline,
              color: AppTheme.accent,
              text: 'Tiền bán ra đang ít hơn tiền mua vào '
                  '${formatMoney(-s.amountBalance)} đ. Bình thường khi còn ôm hàng '
                  'chưa bán — đối chiếu với cột tồn bên dưới.',
            ),
          ),
        SectionCard(
          title: 'Tồn theo mặt hàng (${lines.length})',
          subtitle: _khoangThoiGian(),
          icon: Icons.table_rows,
          padded: false,
          child: lines.isEmpty
              ? const EmptyHint(
                  icon: Icons.inventory_2_outlined,
                  message: 'Sổ chưa có giao dịch nào.',
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: _bangRong(context)),
                    child: DataTable(
                      columnSpacing: 18,
                      horizontalMargin: 14,
                      columns: const [
                        DataColumn(label: Text('Mặt hàng')),
                        DataColumn(label: Text('Nhập'), numeric: true),
                        DataColumn(label: Text('Xuất'), numeric: true),
                        DataColumn(label: Text('Tồn'), numeric: true),
                        DataColumn(label: Text('Giá vốn TB'), numeric: true),
                        DataColumn(label: Text('Tiền mua'), numeric: true),
                        DataColumn(label: Text('Tiền bán'), numeric: true),
                      ],
                      rows: [
                        for (final d in lines) _dongTon(d),
                        DataRow(
                          color: WidgetStateProperty.all(AppTheme.surfaceAlt),
                          cells: [
                            const DataCell(Text('TỔNG',
                                style: TextStyle(fontWeight: FontWeight.w800))),
                            _oSo(s.quantityIn, dam: true),
                            _oSo(s.quantityOut, dam: true),
                            _oSo(s.quantityBalance, dam: true),
                            const DataCell(Text('')),
                            _oSo(s.amountIn, dam: true),
                            _oSo(s.amountOut, dam: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppTheme.gapSm),
        const Text(
          'Tồn = nhập − xuất, cộng dồn từ giao dịch đầu tiên tới nay chứ không cắt '
          'theo tháng. Đây là con số của sổ mua bán, không phải số cân thực tế '
          'trong kho.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
        ),
      ],
    );
  }

  String _khoangThoiGian() {
    final dau = _stock.firstDate;
    final cuoi = _stock.lastDate;
    if (dau == null || cuoi == null) return 'Chưa có giao dịch';
    return 'Từ ${formatDate(dau)} đến ${formatDate(cuoi)}';
  }

  DataRow _dongTon(StockLine d) {
    final het = d.quantityBalance <= 0 && d.quantityIn > 0;
    return DataRow(cells: [
      DataCell(Row(
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: het ? AppTheme.lineStrong : AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(d.goodsName, overflow: TextOverflow.ellipsis),
          ),
        ],
      )),
      _oSo(d.quantityIn),
      _oSo(d.quantityOut),
      DataCell(Text(
        formatWeight(d.quantityBalance),
        style: AppTheme.number(
          14,
          color: d.quantityBalance < 0 ? AppTheme.offline : AppTheme.text,
        ),
      )),
      DataCell(Text(
        d.averageCost == null ? '—' : formatMoney(d.averageCost),
        style: AppTheme.number(13.5, weight: FontWeight.w600, color: AppTheme.textSoft),
      )),
      _oSo(d.amountIn),
      _oSo(d.amountOut),
    ]);
  }

  DataCell _oSo(double v, {bool dam = false}) => DataCell(Text(
        formatMoney(v),
        style: AppTheme.number(dam ? 14 : 13.5,
            weight: dam ? FontWeight.w800 : FontWeight.w600),
      ));

  /// Bề rộng tối thiểu để bảng trải hết khung nội dung thay vì co lại.
  double _bangRong(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final trong =
        (w >= AppTheme.wideBreakpoint ? w - 97 : w).clamp(0.0, AppTheme.contentMaxWidth);
    return (trong - AppTheme.gapMd * 2 - 2).clamp(320.0, double.infinity);
  }

  Widget _toolbar() => Padding(
        padding: const EdgeInsets.all(AppTheme.gapMd),
        child: Column(
          children: [
            Row(
              children: [
                _StepButton(
                  tooltip: 'Tháng trước',
                  icon: Icons.chevron_left,
                  onTap: () => _shiftMonth(-1),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 140),
                  alignment: Alignment.center,
                  child: Text(
                    'Tháng ${_month.month}/${_month.year}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                _StepButton(
                  tooltip: 'Tháng sau',
                  icon: Icons.chevron_right,
                  onTap: () => _shiftMonth(1),
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: 'Tìm mặt hàng, đối tác, số hoá đơn — gõ không dấu cũng ra',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => _load(),
                  ),
                ),
                const SizedBox(width: AppTheme.gapSm),
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Ghi giao dịch'),
                ),
                const SizedBox(width: AppTheme.gapXs),
                IconButton(
                  tooltip: 'Làm mới',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.gapSm),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _LocTheoDanhMuc(
                          nhan: 'Loại hàng',
                          icon: Icons.inventory_2_outlined,
                          chon: _goodsFilter,
                          muc: [for (final g in _goods) (id: g.id, ten: g.name)],
                          onChanged: (v) {
                            setState(() => _goodsFilter = v);
                            _load();
                          },
                        ),
                        const SizedBox(width: AppTheme.gapSm),
                        _LocTheoDanhMuc(
                          nhan: 'Đối tác',
                          icon: Icons.person_outline,
                          chon: _partnerFilter,
                          muc: [for (final c in _customers) (id: c.id, ten: c.name)],
                          onChanged: (v) {
                            setState(() => _partnerFilter = v);
                            _load();
                          },
                        ),
                        const SizedBox(width: AppTheme.gapSm),
                        SegmentedButton<_InvoiceFilter>(
                          segments: [
                            for (final f in _InvoiceFilter.values)
                              ButtonSegment(value: f, label: Text(f.label)),
                          ],
                          selected: {_invoice},
                          showSelectedIcon: false,
                          onSelectionChanged: (chon) {
                            setState(() => _invoice = chon.first);
                            _load();
                          },
                        ),
                        const SizedBox(width: AppTheme.gapSm),
                        SegmentedButton<TradeKind?>(
                          segments: const [
                            ButtonSegment(value: null, label: Text('Nhập & xuất')),
                            ButtonSegment(value: TradeKind.muaVao, label: Text('Nhập')),
                            ButtonSegment(value: TradeKind.banRa, label: Text('Xuất')),
                          ],
                          selected: {_kind},
                          showSelectedIcon: false,
                          onSelectionChanged: (chon) {
                            setState(() => _kind = chon.first);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _summaryTiles(TradeSummary s) => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'KL nhập',
                  value: formatWeight(s.quantityIn),
                  unit: 'kg',
                  icon: Icons.south_west,
                  tone: AppTheme.primary,
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: StatTile(
                  label: 'KL xuất',
                  value: formatWeight(s.quantityOut),
                  unit: 'kg',
                  icon: Icons.north_east,
                  tone: AppTheme.accent,
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: StatTile(
                  label: 'Còn lại theo sổ',
                  value: formatWeight(s.quantityBalance),
                  unit: 'kg',
                  icon: Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.gapSm),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Tiền mua vào',
                  value: formatMoney(s.amountIn),
                  unit: 'đ',
                  icon: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: StatTile(
                  label: 'Tiền bán ra',
                  value: formatMoney(s.amountOut),
                  unit: 'đ',
                  icon: Icons.arrow_upward,
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: StatTile(
                  label: 'Có hoá đơn',
                  value: formatMoney(s.amountInvoiced),
                  unit: 'đ',
                  icon: Icons.verified_outlined,
                  tone: AppTheme.primary,
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: StatTile(
                  label: 'Không hoá đơn',
                  value: formatMoney(s.amountNotInvoiced),
                  unit: 'đ',
                  icon: Icons.help_outline,
                  tone: AppTheme.accent,
                ),
              ),
            ],
          ),
        ],
      );

  Widget _row(Trade t) {
    final nhap = t.kind == TradeKind.muaVao;
    final mau = nhap ? AppTheme.primary : AppTheme.accent;
    return InkWell(
      onTap: () => _edit(t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 40,
              decoration:
                  BoxDecoration(color: mau, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 12),
            Icon(nhap ? Icons.south_west : Icons.north_east, size: 18, color: mau),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.goodsName.isEmpty ? t.kind.label : t.goodsName,
                    style: AppTheme.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      formatDate(t.date),
                      if (t.partnerName.isNotEmpty) t.partnerName,
                      if (t.quantity > 0)
                        '${formatWeight(t.quantity)} ${t.unit}'
                            '${t.unitPrice > 0 ? " × ${formatMoney(t.unitPrice)} đ" : ""}',
                    ].join('  ·  '),
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSoft, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (t.note != null && t.note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(t.note!,
                        style: AppTheme.meta.copyWith(fontSize: 11.5),
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(formatMoney(t.amount), style: AppTheme.number(17, color: mau)),
                    const SizedBox(width: 3),
                    const Text('đ',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 3),
                StatusPill(
                  label: t.hasInvoice
                      ? (t.invoiceNo == null || t.invoiceNo!.isEmpty
                          ? 'Có hoá đơn'
                          : t.invoiceNo!)
                      : 'Không hoá đơn',
                  color: t.hasInvoice ? AppTheme.primary : AppTheme.textMuted,
                  compact: true,
                  icon: t.hasInvoice ? Icons.verified_outlined : null,
                ),
              ],
            ),
            IconButton(
              tooltip: 'Xoá giao dịch',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _delete(t),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ô lọc theo một mục trong danh mục (loại hàng, đối tác).
///
/// Lọc ở máy chủ chứ không lọc sau khi đã tải về, để con số tổng phía trên vẫn
/// tính đúng trên phần đang xem.
class _LocTheoDanhMuc extends StatelessWidget {
  const _LocTheoDanhMuc({
    required this.nhan,
    required this.icon,
    required this.chon,
    required this.muc,
    required this.onChanged,
  });

  final String nhan;
  final IconData icon;
  final String? chon;
  final List<({String id, String ten})> muc;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final dangChon = muc.any((m) => m.id == chon);
    return Container(
      height: AppTheme.minTouch,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: dangChon ? AppTheme.primarySoft : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: dangChon ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.lineStrong,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: dangChon ? chon : null,
          isDense: true,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          icon: const Icon(Icons.expand_more, size: 18),
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(nhan, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSoft)),
            ],
          ),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: dangChon ? AppTheme.primary : AppTheme.text,
          ),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('$nhan: tất cả')),
            for (final m in muc) DropdownMenuItem<String?>(value: m.id, child: Text(m.ten)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Nút mũi tên lùi/tới một tháng, cỡ chạm được bằng ngón cái.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.tooltip, required this.icon, required this.onTap});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            width: AppTheme.minTouch,
            height: AppTheme.minTouch,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.lineStrong),
            ),
            child: Icon(icon, size: 22, color: AppTheme.textSoft),
          ),
        ),
      );
}

/// Hộp thoại ghi một giao dịch.
class _TradeDialog extends StatefulWidget {
  const _TradeDialog({
    this.trade,
    required this.goods,
    required this.customers,
    required this.defaultDate,
  });

  final Trade? trade;
  final List<GoodsType> goods;
  final List<Customer> customers;
  final DateTime defaultDate;

  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  final _formKey = GlobalKey<FormState>();

  late TradeKind _kind = widget.trade?.kind ?? TradeKind.muaVao;
  late DateTime _date = widget.trade?.date ?? widget.defaultDate;
  late String? _goodsId = widget.trade?.goodsTypeId;
  late String? _partnerId = widget.trade?.partnerId;
  late bool _hasInvoice = widget.trade?.hasInvoice ?? false;

  late final _goodsName = TextEditingController(text: widget.trade?.goodsName ?? '');
  late final _partnerName = TextEditingController(text: widget.trade?.partnerName ?? '');
  late final _quantity = TextEditingController(
      text: (widget.trade?.quantity ?? 0) > 0 ? soVaoO(widget.trade!.quantity) : '');
  late final _unitPrice = TextEditingController(
      text: (widget.trade?.unitPrice ?? 0) > 0 ? soVaoO(widget.trade!.unitPrice) : '');
  late final _amount = TextEditingController(
      text: widget.trade == null ? '' : soVaoO(widget.trade!.amount));

  /// Hai ô người dùng gõ gần đây nhất; ô còn lại là ô được tính.
  ///
  /// Nhớ theo người gõ chứ không theo ô nào đang trống, nếu không thì đang gõ
  /// dở ô này máy lại đổi sang tính ô khác: gõ "5243000" vào thành tiền, mấy
  /// phím đầu khối lượng còn trống nên nó tính khối lượng từ số dở dang
  /// (52 ÷ 1500 = 0,03), gõ tiếp thì cả ba ô đã có số, nó quay sang tính đơn
  /// giá và bỏ mặc khối lượng đứng ở 0,03.
  ///
  /// Mở sẵn giao dịch cũ thì coi như vừa gõ khối lượng và đơn giá, nên sửa một
  /// trong hai ô đó là thành tiền tính lại ngay.
  final List<TradeField> _daGo = [TradeField.khoiLuong, TradeField.donGia];
  late final _invoiceNo = TextEditingController(text: widget.trade?.invoiceNo ?? '');
  late final _note = TextEditingController(text: widget.trade?.note ?? '');

  /// Gõ xong một ô thì tính lại ô còn lại — xem [computeTradeField].
  void _tinhLai(TradeField vuaGo) {
    // Ô vừa gõ luôn nằm trong hai ô "người dùng nhập"; ô bị đẩy ra là ô tính.
    _daGo
      ..remove(vuaGo)
      ..add(vuaGo);
    if (_daGo.length > 2) _daGo.removeAt(0);

    final can = TradeField.values.firstWhere((f) => !_daGo.contains(f));
    final giaTri = computeTradeField(
      target: can,
      quantity: parseNumber(_quantity.text),
      unitPrice: parseNumber(_unitPrice.text),
      amount: parseNumber(_amount.text),
    );
    if (giaTri == null) {
      setState(() {});
      return;
    }

    final o = switch (can) {
      TradeField.khoiLuong => _quantity,
      TradeField.donGia => _unitPrice,
      TradeField.thanhTien => _amount,
    };
    // Chỉ ghi khi số thực sự đổi: gán thẳng vào controller sẽ đẩy con trỏ về
    // đầu dòng, đang gõ dở mà nhảy con trỏ thì không nhập nổi.
    final text = soVaoO(giaTri);
    if (o.text != text) o.text = text;
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _goodsName,
      _partnerName,
      _quantity,
      _unitPrice,
      _amount,
      _invoiceNo,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kl = parseNumber(_quantity.text) ?? 0;
    final gia = parseNumber(_unitPrice.text) ?? 0;
    final tien = parseNumber(_amount.text) ?? 0;
    final nhanRa = kl > 0 && gia > 0 ? kl * gia : null;
    // Nới theo tỷ lệ chứ không phải một đồng: đơn giá suy ngược từ thành tiền
    // bị làm tròn khi hiện ra, nhân lại luôn lệch vài đồng — báo động vì mấy
    // đồng đó thì lần nào cũng kêu, thành ra không ai đọc nữa.
    final lech = nhanRa != null && (nhanRa - tien).abs() > tien.abs() * 0.0001 + 1;

    return AlertDialog(
      title: Text(widget.trade == null ? 'Ghi giao dịch' : 'Sửa giao dịch'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<TradeKind>(
                  segments: const [
                    ButtonSegment(
                      value: TradeKind.muaVao,
                      icon: Icon(Icons.south_west, size: 18),
                      label: Text('Mua vào'),
                    ),
                    ButtonSegment(
                      value: TradeKind.banRa,
                      icon: Icon(Icons.north_east, size: 18),
                      label: Text('Bán ra'),
                    ),
                  ],
                  selected: {_kind},
                  showSelectedIcon: false,
                  onSelectionChanged: (c) => setState(() => _kind = c.first),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(DateTime.now().year - 3),
                      lastDate: DateTime(DateTime.now().year + 1),
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Ngày: ${formatDate(_date)}'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: widget.goods.any((g) => g.id == _goodsId) ? _goodsId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Mặt hàng trong danh mục'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— tự nhập bên dưới —')),
                    for (final g in widget.goods)
                      DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: (v) => setState(() => _goodsId = v),
                ),
                if (_goodsId == null) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _goodsName,
                    decoration: const InputDecoration(
                      labelText: 'Tên mặt hàng',
                      helperText: 'Thứ mua bán một lần, không đáng lập danh mục',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value:
                      widget.customers.any((c) => c.id == _partnerId) ? _partnerId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Đối tác trong danh mục'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— tự nhập bên dưới —')),
                    for (final c in widget.customers)
                      DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _partnerId = v),
                ),
                if (_partnerId == null) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _partnerName,
                    decoration: const InputDecoration(labelText: 'Tên đối tác'),
                  ),
                ],
                const Divider(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantity,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Khối lượng', suffixText: 'kg'),
                        onChanged: (_) => _tinhLai(TradeField.khoiLuong),
                      ),
                    ),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: TextFormField(
                        controller: _unitPrice,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Đơn giá', suffixText: 'đ/kg'),
                        onChanged: (_) => _tinhLai(TradeField.donGia),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Thành tiền *',
                    suffixText: 'đ',
                    helperText: lech
                        ? 'Khác với ${formatMoney(nhanRa)} đ nhân ra từ khối lượng × đơn giá'
                        : 'Nhập 2 trong 3 ô, ô còn lại tự tính ra số tròn.',
                    helperStyle: lech
                        ? const TextStyle(
                            color: AppTheme.accent, fontWeight: FontWeight.w600)
                        : null,
                  ),
                  onChanged: (_) => _tinhLai(TradeField.thanhTien),
                  validator: (v) {
                    final n = parseNumber(v);
                    if (n == null || n < 0) return 'Nhập số tiền';
                    return null;
                  },
                ),
                const Divider(height: 28),
                SwitchListTile(
                  value: _hasInvoice,
                  onChanged: (v) => setState(() => _hasInvoice = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Có xuất hoá đơn'),
                  subtitle: const Text(
                    'Để tra được hàng nào đã ra hoá đơn, hàng nào chưa',
                    style: AppTheme.meta,
                  ),
                ),
                if (_hasInvoice) ...[
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _invoiceNo,
                    decoration: const InputDecoration(labelText: 'Số hoá đơn'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              Trade.create(
                date: _date,
                kind: _kind,
                goodsTypeId: _goodsId,
                goodsName: _goodsId == null ? _goodsName.text.trim() : '',
                partnerId: _partnerId,
                partnerName: _partnerId == null ? _partnerName.text.trim() : '',
                quantity: parseNumber(_quantity.text) ?? 0,
                unitPrice: parseNumber(_unitPrice.text) ?? 0,
                amount: parseNumber(_amount.text) ?? 0,
                hasInvoice: _hasInvoice,
                invoiceNo: _hasInvoice ? _invoiceNo.text.trim() : null,
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
