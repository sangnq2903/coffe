import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../core/ticket_printer.dart';
import '../widgets/ticket_tile.dart';

/// Mở phiếu cân dạng chi tiết, hiện ngay sau khi chốt cân lần 2 để nhân viên
/// đối chiếu với tài xế và in trước khi xe rời kho.
Future<void> showTicketDetailSheet(BuildContext context, WeighTicket ticket) {
  return showModalBottomSheet<void>(
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

  WeighTicket get _ticket => widget.ticket;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
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
              onPressed: () => Navigator.pop(context),
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
