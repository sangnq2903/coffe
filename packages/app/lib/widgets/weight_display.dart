import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/live_weight_controller.dart';

/// Bảng số cân realtime — thành phần trung tâm của màn hình cân.
///
/// Cỡ chữ tự co theo bề ngang để đọc được từ xa trên máy đặt ở bàn cân, đồng
/// thời vẫn vừa màn hình điện thoại. Viền và nhãn đổi màu theo trạng thái để
/// nhìn một cái là biết có được phép chốt số hay chưa.
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
        final digitSize = (compact ? width / 5.6 : width / 6.4).clamp(46.0, 150.0);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 26,
            vertical: compact ? 14 : 20,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.panelEdge, AppTheme.panel],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radius + 2),
            border: Border.all(color: statusColor.withValues(alpha: 0.55), width: 2),
            boxShadow: AppTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(child: _stationChip()),
                  const Spacer(),
                  _StatusChip(color: statusColor, label: statusLabel, pulsing: !connected),
                ],
              ),
              SizedBox(height: compact ? 6 : 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!compact)
                    Expanded(
                      child: Text(
                        'SỐ CÂN HIỆN TẠI',
                        style: AppTheme.sectionLabel.copyWith(color: Colors.white38),
                      ),
                    ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            connected ? formatWeight(live.weight) : '– – – –',
                            style: AppTheme.digits(
                              digitSize,
                              color: connected ? Colors.white : Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: EdgeInsets.only(bottom: digitSize * 0.08),
                            child: Text(
                              reading?.unit ?? 'kg',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: (digitSize / 3.2).clamp(18.0, 42.0),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 12),
              Row(
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
                  // Chuỗi thô từ cổng COM: chỗ duy nhất để đối chiếu khi đấu đầu
                  // cân mới mà số hiện ra không đúng.
                  if (reading?.raw != null && !compact)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stationChip() {
    final label = stationName.isEmpty ? 'Chưa chọn trạm cân' : stationName;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warehouse, size: 15, color: Colors.white54),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTapStation != null) ...[
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16, color: Colors.white38),
        ],
      ],
    );

    if (onTapStation == null) return content;
    return InkWell(
      onTap: onTapStation,
      borderRadius: BorderRadius.circular(8),
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
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing)
            _Pulse(child: dot)
          else
            dot,
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
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
