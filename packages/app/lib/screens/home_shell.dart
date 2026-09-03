import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/server_connection.dart';
import '../state/live_weight_controller.dart';
import '../widgets/station_picker.dart';
import 'catalog_screen.dart';
import 'settings_screen.dart';
import 'tickets_screen.dart';
import 'weigh_screen.dart';

/// Khung điều hướng chính. Màn hình rộng dùng thanh dọc bên trái, màn hình hẹp
/// (điện thoại) dùng thanh dưới đáy.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.scale, label: 'Cân xe'),
    (icon: Icons.receipt_long, label: 'Phiếu cân'),
    (icon: Icons.folder_shared, label: 'Danh mục'),
    (icon: Icons.settings, label: 'Cài đặt'),
  ];

  /// Mở lại luồng số cân mỗi khi người dùng đổi server hoặc đổi trạm.
  ///
  /// Gọi sau khi khung hình đã dựng xong: `connectTo` thay đổi controller, làm
  /// vậy ngay trong `build` sẽ gây lỗi "setState during build".
  void _syncLiveWeight(ServerConnection conn) {
    final live = context.read<LiveWeightController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      live.connectTo(conn.scaleWsUri(), conn.stationCode);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    _syncLiveWeight(conn);
    const pages = [WeighScreen(), TicketsScreen(), CatalogScreen(), SettingsScreen()];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                const Icon(Icons.scale, size: 22),
                const SizedBox(width: AppTheme.gapSm),
                const Text('CÂN XE'),
                if (conn.station != null && wide) ...[
                  const SizedBox(width: 14),
                  _StationButton(label: conn.station!.displayName),
                ],
              ],
            ),
            actions: const [_ConnectionIndicator(), SizedBox(width: 16)],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      labelType: NavigationRailLabelType.all,
                      backgroundColor: Colors.white,
                      indicatorColor: AppTheme.primary.withValues(alpha: 0.12),
                      selectedIconTheme: const IconThemeData(color: AppTheme.primary),
                      selectedLabelTextStyle: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                      unselectedLabelTextStyle: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12.5,
                      ),
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: _destinations
                          .map((d) => NavigationRailDestination(
                                icon: Icon(d.icon),
                                label: Text(d.label),
                              ))
                          .toList(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: pages[_index]),
                  ],
                )
              : pages[_index],
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: _destinations
                      .map((d) => NavigationDestination(
                            icon: Icon(d.icon),
                            label: d.label,
                          ))
                      .toList(),
                ),
        );
      },
    );
  }
}

/// Tên kho trên thanh tiêu đề, bấm vào để chuyển sang kho khác.
class _StationButton extends StatelessWidget {
  const _StationButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showStationPicker(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warehouse, size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more, size: 17, color: Colors.white54),
            ],
          ),
        ),
      );
}

/// Đèn báo tình trạng: nối được server và đầu cân hay chưa.
class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator();

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    final live = context.watch<LiveWeightController>();

    final (color, label) = switch ((conn.isConnected, live.connected)) {
      (false, _) => (AppTheme.offline, 'Mất máy chủ'),
      (true, false) => (AppTheme.unstable, 'Chưa có đầu cân'),
      (true, true) => (AppTheme.stable, 'Sẵn sàng'),
    };

    return Tooltip(
      message: conn.error ?? live.errorMessage ?? 'Máy chủ: ${conn.baseUrl}',
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
