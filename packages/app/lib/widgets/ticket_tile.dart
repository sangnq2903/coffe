import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';

/// Màu quy ước cho trạng thái phiếu, dùng thống nhất ở mọi màn hình.
Color ticketStatusColor(TicketStatus status) => switch (status) {
      TicketStatus.hoanThanh => AppTheme.stable,
      TicketStatus.choLan2 => AppTheme.unstable,
      TicketStatus.huy => AppTheme.offline,
    };

/// Một dòng phiếu cân trong danh sách.
///
/// Cùng một dòng dùng cho cả danh sách dưới màn hình cân lẫn màn hình tra cứu,
/// để nhân viên không phải học hai cách đọc khác nhau cho cùng một dữ liệu.
class TicketTile extends StatelessWidget {
  const TicketTile({
    super.key,
    required this.ticket,
    this.onTap,
    this.onPrint,
    this.showStation = false,
  });

  final WeighTicket ticket;
  final VoidCallback? onTap;
  final VoidCallback? onPrint;

  /// Hiện mã kho — chỉ cần khi đang xem gộp dữ liệu nhiều kho.
  final bool showStation;

  @override
  Widget build(BuildContext context) {
    final color = ticketStatusColor(ticket.status);
    final done = ticket.status == TicketStatus.hoanThanh;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                ticket.direction == WeighDirection.nhap
                    ? Icons.south_west
                    : Icons.north_east,
                color: color,
                size: 19,
              ),
            ),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ticket.plateNo,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTheme.gapSm),
                      Text(
                        ticket.ticketNo,
                        style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      ticket.goodsName.isEmpty ? '—' : ticket.goodsName,
                      ticket.customerName.isEmpty ? '—' : ticket.customerName,
                      if (showStation) ticket.stationCode,
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'L1 ${formatWeight(ticket.firstWeight)}'
                    '  →  L2 ${ticket.secondWeight == null ? "chờ cân" : formatWeight(ticket.secondWeight)}'
                    '   •   ${formatDateTime(ticket.createdAt)}',
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  done ? '${formatWeight(ticket.netWeight)} kg' : '—',
                  style: AppTheme.digits(18, color: color),
                ),
                const SizedBox(height: 2),
                if (done)
                  Text(
                    'TP ${formatWeight(ticket.productWeight)} kg',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  )
                else
                  StatusPill(label: ticket.status.label, color: color, compact: true),
              ],
            ),
            if (onPrint != null && done) ...[
              const SizedBox(width: AppTheme.gapXs),
              IconButton(
                tooltip: 'In phiếu cân',
                icon: const Icon(Icons.print_outlined),
                onPressed: onPrint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
