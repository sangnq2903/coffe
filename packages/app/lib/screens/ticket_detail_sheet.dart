import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../core/ticket_printer.dart';
import '../state/server_connection.dart';
import '../widgets/ticket_tile.dart';

/// Mở phiếu cân dạng chi tiết, hiện ngay sau khi chốt cân lần 2 để nhân viên
/// đối chiếu với tài xế và in trước khi xe rời kho.
///
/// Trả về `true` nếu phiếu bị sửa, huỷ hay xoá — bên gọi tải lại danh sách.
Future<bool> showTicketDetailSheet(BuildContext context, WeighTicket ticket) async {
  final doi = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          TicketDetailView(ticket: ticket, scrollController: scrollController),
    ),
  );
  return doi ?? false;
}

class TicketDetailView extends StatefulWidget {
  const TicketDetailView({super.key, required this.ticket, this.scrollController});

  final WeighTicket ticket;
  final ScrollController? scrollController;

  @override
  State<TicketDetailView> createState() => _TicketDetailViewState();
}

class _TicketDetailViewState extends State<TicketDetailView> {
  bool _busy = false;
  String? _error;

  /// Bản phiếu đang hiện. Sửa xong thì thay tại chỗ để người dùng thấy ngay,
  /// không phải đóng ra mở lại.
  late WeighTicket _hienTai = widget.ticket;

  /// Đã đụng vào phiếu hay chưa — bên gọi dựa vào đây để tải lại danh sách.
  bool _daDoi = false;

  WeighTicket get _ticket => _hienTai;

  ApiClient? get _client => context.read<ServerConnection>().client;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _daDoi = true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không thực hiện được: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = ticketStatusColor(_ticket.status);
    final done = _ticket.status == TicketStatus.hoanThanh;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PHIẾU CÂN XE', style: AppTheme.sectionLabel),
                        const SizedBox(height: 2),
                        Text(
                          _ticket.ticketNo,
                          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_ticket.direction.label}  •  Kho ${_ticket.stationCode}  •  '
                          '${formatDateTime(_ticket.createdAt)}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(label: _ticket.status.label, color: color),
                  _menu(),
                ],
              ),
              const SizedBox(height: AppTheme.gapLg),

              _totals(),
              const SizedBox(height: AppTheme.gapMd),

              _group('Xe & khách hàng', [
                _row('Biển số xe', _ticket.plateNo, strong: true),
                _row('Tài xế', _ticket.driverName ?? '—'),
                _row('Khách hàng',
                    _ticket.customerName.isEmpty ? '—' : _ticket.customerName),
              ]),
              const SizedBox(height: AppTheme.gapMd),

              _group('Hàng hoá', [
                _row('Loại hàng', _ticket.goodsName.isEmpty ? '—' : _ticket.goodsName),
                _row('Tỷ lệ thành phẩm', formatPercent(_ticket.yieldRatio)),
              ]),
              const SizedBox(height: AppTheme.gapMd),

              _group('Khối lượng', [
                _row('Cân lần 1', '${formatWeight(_ticket.firstWeight)} kg',
                    sub: formatDateTime(_ticket.firstWeightAt)),
                _row('Cân lần 2', '${formatWeight(_ticket.secondWeight)} kg',
                    sub: formatDateTime(_ticket.secondWeightAt)),
                _row('KL tổng (xe + hàng)', '${formatWeight(_ticket.grossWeight)} kg'),
                _row('KL bì (xe không)', '${formatWeight(_ticket.tareWeight)} kg'),
              ]),

              if ((_ticket.note ?? '').isNotEmpty) ...[
                const SizedBox(height: AppTheme.gapMd),
                _group('Ghi chú', [Text(_ticket.note!)]),
              ],

              const SizedBox(height: AppTheme.gapMd),
              Text(
                'Người lập: ${(_ticket.createdBy ?? '').isEmpty ? '—' : _ticket.createdBy}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppTheme.gapMd),
                Text(_error!, style: const TextStyle(color: AppTheme.offline)),
              ],
            ],
          ),
        ),
        _actionBar(done),
      ],
    );
  }

  /// Ba việc sửa chữa một phiếu, gom vào một nút cho gọn thanh tiêu đề.
  Widget _menu() => PopupMenuButton<String>(
        tooltip: 'Sửa, huỷ hoặc xoá phiếu',
        enabled: !_busy,
        onSelected: (v) => switch (v) {
          'sua' => _sua(),
          'huy' => _huy(),
          'xoa' => _xoa(),
          _ => null,
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'sua',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.edit_outlined),
              title: Text('Sửa phiếu'),
            ),
          ),
          if (_ticket.status != TicketStatus.huy)
            const PopupMenuItem(
              value: 'huy',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.block_outlined, color: AppTheme.unstable),
                title: Text('Huỷ phiếu'),
                subtitle: Text('Vẫn giữ trong sổ để tra lại'),
              ),
            ),
          const PopupMenuItem(
            value: 'xoa',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline, color: AppTheme.offline),
              title: Text('Xoá hẳn'),
              subtitle: Text('Biến mất khỏi danh sách'),
            ),
          ),
        ],
      );

  Future<void> _sua() async {
    final ketQua = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _TicketEditDialog(ticket: _ticket),
    );
    if (ketQua == null || !mounted) return;
    await _run(() async {
      final moi = await _client!.updateTicket(_ticket.id, ketQua);
      if (mounted) setState(() => _hienTai = moi);
    });
  }

  Future<void> _huy() async {
    final lyDo = await _hoiLyDo();
    if (lyDo == null || !mounted) return;
    await _run(() async {
      final moi = await _client!.cancelTicket(_ticket.id, reason: lyDo);
      if (mounted) setState(() => _hienTai = moi);
    });
  }

  /// Hỏi lý do huỷ. Bắt buộc nhập: huỷ phiếu mà không ai biết vì sao thì tháng
  /// sau đối chiếu không giải thích được với khách.
  Future<String?> _hoiLyDo() {
    final o = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Huỷ phiếu ${_ticket.ticketNo}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Phiếu vẫn nằm trong sổ với trạng thái đã huỷ, và không tính vào '
              'số tổng. Lý do được ghi vào phần ghi chú.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: AppTheme.gapMd),
            TextField(
              controller: o,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Lý do huỷ *',
                hintText: 'VD: xe quay đầu không giao hàng',
              ),
              onSubmitted: (v) =>
                  v.trim().isEmpty ? null : Navigator.pop(context, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Không huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.unstable),
            onPressed: () {
              final v = o.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Huỷ phiếu'),
          ),
        ],
      ),
    );
  }

  Future<void> _xoa() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá hẳn phiếu ${_ticket.ticketNo}?'),
        content: Text(
          'Xe ${_ticket.plateNo}'
          '${_ticket.goodsName.isEmpty ? '' : ' • ${_ticket.goodsName}'}'
          '${_ticket.status == TicketStatus.hoanThanh ? ' • ${formatWeight(_ticket.netWeight)} kg' : ''}.\n\n'
          'Phiếu sẽ biến mất khỏi mọi danh sách và số tổng. Nếu chỉ muốn đánh dấu '
          'là không dùng nữa thì chọn "Huỷ phiếu" — phiếu vẫn còn để tra lại.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.offline),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá hẳn'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _run(() async {
      await _client!.deleteTicket(_ticket.id);
      _daDoi = true;
      if (mounted) Navigator.pop(context, true);
    });
  }

  Widget _actionBar(bool done) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy || !done ? null : () => _run(() => TicketPrinter.print(_ticket)),
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print),
                label: const Text('IN PHIẾU CÂN'),
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !done ? null : () => _run(() => TicketPrinter.share(_ticket)),
                icon: Icon(kIsWeb ? Icons.download : Icons.ios_share, size: 19),
                label: Text(kIsWeb ? 'Tải PDF' : 'Chia sẻ'),
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, _daDoi),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );

  Widget _totals() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.panelEdge, AppTheme.panel],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: _bigValue('KHỐI LƯỢNG HÀNG',
                  '${formatWeight(_ticket.netWeight)} kg', Colors.white, 30),
            ),
            Container(width: 1, height: 46, color: Colors.white24),
            Expanded(
              child: _bigValue('KL THÀNH PHẨM',
                  '${formatWeight(_ticket.productWeight)} kg', AppTheme.stable, 24),
            ),
          ],
        ),
      );

  Widget _bigValue(String label, String value, Color color, double size) => Column(
        children: [
          Text(label, style: AppTheme.sectionLabel.copyWith(color: Colors.white38)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppTheme.digits(size, color: color)),
          ),
        ],
      );

  Widget _group(String title, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: AppTheme.sectionLabel),
            const SizedBox(height: AppTheme.gapSm),
            ...children,
          ],
        ),
      );

  Widget _row(String label, String value, {String? sub, bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 155,
              child: Text(label,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: strong ? 16 : 14,
                    ),
                  ),
                  if (sub != null && sub != '—')
                    Text(sub,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Hộp thoại sửa một phiếu cân đã lập.
///
/// Sửa được cả biển số vì gõ sai biển là lỗi hay gặp nhất, và cả hai số cân —
/// đầu cân đọc sai hay nhân viên bấm nhầm thì phải chữa lại được. Máy chủ tính
/// lại KL hàng và KL thành phẩm, không nhận số tính sẵn từ đây.
class _TicketEditDialog extends StatefulWidget {
  const _TicketEditDialog({required this.ticket});

  final WeighTicket ticket;

  @override
  State<_TicketEditDialog> createState() => _TicketEditDialogState();
}

class _TicketEditDialogState extends State<_TicketEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _plate = TextEditingController(text: widget.ticket.plateNo);
  late final _driver = TextEditingController(text: widget.ticket.driverName ?? '');
  late final _customer = TextEditingController(text: widget.ticket.customerName);
  late final _goods = TextEditingController(text: widget.ticket.goodsName);
  late final _ratio =
      TextEditingController(text: formatDecimal(widget.ticket.yieldRatio));
  late final _first = TextEditingController(text: formatDecimal(widget.ticket.firstWeight));
  late final _second = TextEditingController(
      text: widget.ticket.secondWeight == null
          ? ''
          : formatDecimal(widget.ticket.secondWeight!));
  late final _note = TextEditingController(text: widget.ticket.note ?? '');

  late WeighDirection _direction = widget.ticket.direction;

  @override
  void dispose() {
    for (final o in [_plate, _driver, _customer, _goods, _ratio, _first, _second, _note]) {
      o.dispose();
    }
    super.dispose();
  }

  /// Xem trước KL hàng sau khi sửa, để thấy ngay số mình vừa gõ ra bao nhiêu.
  double? get _klHang {
    final l1 = parseNumber(_first.text);
    final l2 = parseNumber(_second.text);
    if (l1 == null || l2 == null) return null;
    return (l1 - l2).abs();
  }

  @override
  Widget build(BuildContext context) {
    final klHang = _klHang;
    final tyLe = parseNumber(_ratio.text);

    return AlertDialog(
      title: Text('Sửa phiếu ${widget.ticket.ticketNo}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<WeighDirection>(
                  segments: const [
                    ButtonSegment(
                      value: WeighDirection.nhap,
                      icon: Icon(Icons.south_west, size: 18),
                      label: Text('Nhập kho'),
                    ),
                    ButtonSegment(
                      value: WeighDirection.xuat,
                      icon: Icon(Icons.north_east, size: 18),
                      label: Text('Xuất kho'),
                    ),
                  ],
                  selected: {_direction},
                  showSelectedIcon: false,
                  onSelectionChanged: (c) => setState(() => _direction = c.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Biển số xe *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nhập biển số' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _driver,
                  decoration: const InputDecoration(labelText: 'Tài xế'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customer,
                  decoration: const InputDecoration(labelText: 'Khách hàng'),
                ),
                const Divider(height: 28),
                TextFormField(
                  controller: _goods,
                  decoration: const InputDecoration(labelText: 'Loại hàng'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ratio,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tỷ lệ thành phẩm', suffixText: '%'),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = parseNumber(v);
                    if (n == null) return 'Nhập tỷ lệ';
                    if (n < 0 || n > 100) return '0 – 100';
                    return null;
                  },
                ),
                const Divider(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _first,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Cân lần 1 *', suffixText: 'kg'),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = parseNumber(v);
                          if (n == null || n <= 0) return 'Phải lớn hơn 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: TextFormField(
                        controller: _second,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Cân lần 2',
                          suffixText: 'kg',
                          helperText: 'Để trống là chưa cân',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = parseNumber(v);
                          if (n == null || n < 0) return 'Số không hợp lệ';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.gapSm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('KL hàng sau khi sửa',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                      Text(
                        klHang == null ? 'chưa đủ số' : '${formatWeight(klHang)} kg',
                        style: AppTheme.number(16, color: AppTheme.primary),
                      ),
                      if (klHang != null && tyLe != null && tyLe != 100) ...[
                        const SizedBox(width: 10),
                        Text('TP ${formatWeight(klHang * tyLe / 100)} kg',
                            style: AppTheme.meta),
                      ],
                    ],
                  ),
                ),
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
            final l2 = parseNumber(_second.text);
            Navigator.pop(context, <String, Object?>{
              'direction': _direction.value,
              'plate_no': _plate.text.trim(),
              'driver_name': _driver.text.trim(),
              'customer_name': _customer.text.trim(),
              'goods_name': _goods.text.trim(),
              'yield_ratio': parseNumber(_ratio.text),
              'first_weight': parseNumber(_first.text),
              if (l2 != null) 'second_weight': l2,
              'note': _note.text.trim(),
            });
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
