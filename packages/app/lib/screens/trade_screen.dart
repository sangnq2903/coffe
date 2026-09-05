import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

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

  TradePage _page = const TradePage();
  List<GoodsType> _goods = const [];
  List<Customer> _customers = const [];
  bool _loading = false;
  String? _error;

  ApiClient? get _client => context.read<ServerConnection>().client;

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
      final page = await client.trades(
        from: _from,
        to: _to,
        kind: _kind,
        hasInvoice: _invoice.value,
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
    final s = _page.summary;
    return Column(
      children: [
        _toolbar(),
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
          child: ListView(
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
                        message: _search.text.trim().isNotEmpty || _kind != null ||
                                _invoice != _InvoiceFilter.tatCa
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
          ),
        ),
      ],
    );
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
                      hintText: 'Tìm mặt hàng, đối tác, số hoá đơn, ghi chú',
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
      text: (widget.trade?.quantity ?? 0) > 0 ? formatDecimal(widget.trade!.quantity) : '');
  late final _unitPrice = TextEditingController(
      text: (widget.trade?.unitPrice ?? 0) > 0 ? formatDecimal(widget.trade!.unitPrice) : '');
  late final _amount = TextEditingController(
      text: widget.trade == null ? '' : formatDecimal(widget.trade!.amount));
  late final _invoiceNo = TextEditingController(text: widget.trade?.invoiceNo ?? '');
  late final _note = TextEditingController(text: widget.trade?.note ?? '');

  /// Nhân khối lượng với đơn giá điền sẵn vào ô tiền.
  ///
  /// Vẫn cho sửa lại: bớt giá cho khách hay mua khoản không có khối lượng thì
  /// không nhân ra được.
  void _autoAmount() {
    final kl = parseNumber(_quantity.text) ?? 0;
    final gia = parseNumber(_unitPrice.text) ?? 0;
    if (kl > 0 && gia > 0) {
      _amount.text = formatDecimal(kl * gia);
    }
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
    final lech = nhanRa != null && (nhanRa - tien).abs() > 1;

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
                        onChanged: (_) => _autoAmount(),
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
                        onChanged: (_) => _autoAmount(),
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
                        : 'Tự điền khi nhập khối lượng và đơn giá; sửa lại được',
                    helperStyle: lech
                        ? const TextStyle(
                            color: AppTheme.accent, fontWeight: FontWeight.w600)
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
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
