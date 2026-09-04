import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/live_weight_controller.dart';

/// Bảng số cân realtime — thành phần trung tâm của màn hình cân.
///
/// Số nằm **giữa bảng** và chiếm gần hết bề ngang: đây là thứ duy nhất người
/// đứng xa bàn cân cần đọc được. Trước đây số bị đẩy sang phải để nhường chỗ
/// cho một dòng nhãn, thành ra hai phần ba bảng là khoảng trống đen.
///
/// Vạch màu trên đỉnh bảng cho biết có được phép chốt số hay chưa — nhìn thấy
/// từ xa, không cần đọc chữ.
class WeightDisplay extends StatelessWidget {
  const WeightDisplay({
    super.key,
    required this.stationName,
    this.compact = false,
    this.onTapStation,
  });

  final String stationName;
  final bool compact;

  /// Bấm vào tên trạm để đổi sang kho khác.
  final VoidCallback? onTapStation;

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveWeightController>();
    final reading = live.reading;
    final connected = live.connected;

    final statusColor = !connected
        ? AppTheme.offline
        : live.stable
            ? AppTheme.stable
            : AppTheme.unstable;
    final statusLabel = !connected
        ? 'MẤT KẾT NỐI'
        : live.stable
            ? 'SỐ ĐÃ ỔN ĐỊNH'
            : 'ĐANG DAO ĐỘNG';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Số to hết mức mà vẫn đủ chỗ cho đơn vị; trần 168 để trên màn hình
        // rộng nó không phình thành vô lý.
        final digitSize = (compact ? width / 4.6 : width / 5.2).clamp(52.0, 168.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.panel,
              border: Border.all(color: AppTheme.panelEdge),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Vạch trạng thái: đọc được từ xa mà không tốn một dòng chữ.
                Container(height: 3, color: statusColor),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 18,
                    compact ? 10 : 12,
                    compact ? 12 : 18,
                    compact ? 10 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(child: _stationChip()),
                          const Spacer(),
                          _StatusChip(
                            color: statusColor,
                            label: statusLabel,
                            pulsing: !connected,
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 4 : 8),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                connected ? formatWeight(live.weight) : '––––',
                                style: AppTheme.digits(
                                  digitSize,
                                  color: connected ? Colors.white : Colors.white24,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: EdgeInsets.only(bottom: digitSize * 0.06),
                                child: Text(
                                  reading?.unit ?? 'kg',
                                  style: TextStyle(
                                    color: connected ? statusColor : Colors.white24,
                                    fontSize: (digitSize / 3.4).clamp(18.0, 44.0),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 4),
                      Center(
                        child: Text(
                          'SỐ CÂN HIỆN TẠI',
                          style: AppTheme.sectionLabel.copyWith(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 12),
                      _footer(live, reading, connected),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _footer(LiveWeightController live, ScaleReading? reading, bool connected) => Row(
        children: [
          Icon(
            connected ? Icons.podcasts : Icons.link_off,
            size: 14,
            color: connected ? Colors.white38 : AppTheme.offline,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              live.errorMessage ?? 'Cập nhật lúc ${formatTime(reading?.at)}',
              style: TextStyle(
                color: live.errorMessage != null
                    ? AppTheme.offline.withValues(alpha: 0.95)
                    : Colors.white38,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          // Chuỗi thô từ cổng COM: chỗ duy nhất để đối chiếu khi đấu đầu cân
          // mới mà số hiện ra không đúng.
          if (reading?.raw != null && !compact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                reading!.raw!.trim(),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      );

  Widget _stationChip() {
    final label = stationName.isEmpty ? 'Chưa chọn trạm cân' : stationName;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warehouse_outlined, size: 15, color: Colors.white54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTapStation != null) ...[
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 16, color: Colors.white38),
        ],
      ],
    );

    if (onTapStation == null) return content;
    return InkWell(
      onTap: onTapStation,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(padding: const EdgeInsets.all(4), child: content),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.color, required this.label, this.pulsing = false});

  final Color color;
  final String label;

  /// Chấm nhấp nháy khi mất kết nối để không bị bỏ qua trong lúc bận việc.
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing) _Pulse(child: dot) else dot,
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.25, end: 1).animate(_controller),
        child: widget.child,
      );
}
