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
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            // Vạch màu mảnh thay cho ô vuông có nền: trạng thái vẫn nhận ra
            // ngay mà không chiếm chỗ của nội dung.
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              ticket.direction == WeighDirection.nhap ? Icons.south_west : Icons.north_east,
              color: color,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cấp 1: biển số — thứ người ta tìm khi lướt danh sách.
                  Text(
                    ticket.plateNo,
                    style: AppTheme.number(16, weight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Cấp 2: hàng và khách — đọc khi đã dừng lại ở dòng này.
                  Text(
                    [
                      ticket.goodsName.isEmpty ? '—' : ticket.goodsName,
                      ticket.customerName.isEmpty ? '—' : ticket.customerName,
                      if (showStation) ticket.stationCode,
                    ].join('  ·  '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSoft,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Cấp 3: số phiếu, hai lần cân, giờ — chỉ cần khi đối chiếu.
                  Text(
                    '${ticket.ticketNo}  ·  '
                    '${formatWeight(ticket.firstWeight)} → '
                    '${ticket.secondWeight == null ? "chờ cân" : formatWeight(ticket.secondWeight)}'
                    '  ·  ${formatDateTime(ticket.createdAt)}',
                    style: AppTheme.meta.copyWith(fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (done) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(formatWeight(ticket.netWeight),
                          style: AppTheme.number(19, color: AppTheme.text)),
                      const SizedBox(width: 3),
                      const Text('kg',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text('TP ${formatWeight(ticket.productWeight)} kg',
                      style: AppTheme.meta.copyWith(fontSize: 11)),
                ] else
                  StatusPill(label: ticket.status.label, color: color, compact: true),
              ],
            ),
            if (onPrint != null && done)
              IconButton(
                tooltip: 'In phiếu cân',
                icon: const Icon(Icons.print_outlined, size: 20),
                onPressed: onPrint,
              )
            else
              const SizedBox(width: AppTheme.gapSm),
          ],
        ),
      ),
    );
  }
}
