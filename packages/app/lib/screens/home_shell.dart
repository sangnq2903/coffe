import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/server_connection.dart';
import '../state/live_weight_controller.dart';
import '../widgets/station_picker.dart';
import 'account_screen.dart';
import 'catalog_screen.dart';
import 'payroll/crews_screen.dart';
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
    (icon: Icons.scale_outlined, active: Icons.scale, label: 'Cân xe'),
    (icon: Icons.receipt_long_outlined, active: Icons.receipt_long, label: 'Phiếu cân'),
    (icon: Icons.fact_check_outlined, active: Icons.fact_check, label: 'Chấm công'),
    (icon: Icons.folder_open_outlined, active: Icons.folder_shared, label: 'Danh mục'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Cài đặt'),
    (icon: Icons.person_outline, active: Icons.account_circle, label: 'Cá nhân'),
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
    const pages = [
      WeighScreen(),
      TicketsScreen(),
      CrewsScreen(),
      CatalogScreen(),
      SettingsScreen(),
      AccountScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AppTheme.wideBreakpoint;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: wide ? 14 : 16,
            title: Row(
              children: [
                const _Logo(),
                if (conn.station != null) ...[
                  const SizedBox(width: 12),
                  Flexible(child: _StationButton(label: conn.station!.displayName)),
                ],
              ],
            ),
            actions: [
              if (conn.currentUser != null && wide) ...[
                _UserChip(name: conn.currentUser!.displayName),
                const SizedBox(width: 4),
              ],
              const _ConnectionIndicator(),
              const SizedBox(width: 12),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    _Rail(
                      index: _index,
                      onSelected: (i) => setState(() => _index = i),
                    ),
                    const VerticalDivider(width: 1),
                    // Chặn bề rộng cột nội dung: trên màn hình 1440px mà để
                    // trải hết thì một dòng danh sách có tên ở mép trái, nút ở
                    // mép phải, cách nhau cả gang tay.
                    Expanded(
                      child: PageBody(
                        padding: EdgeInsets.zero,
                        child: pages[_index],
                      ),
                    ),
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
                            selectedIcon: Icon(d.active),
                            label: d.label,
                          ))
                      .toList(),
                ),
        );
      },
    );
  }
}

/// Thanh điều hướng dọc.
///
/// Tự dựng thay vì dùng [NavigationRail] để nhãn đủ rộng mà đọc được: rail mặc
/// định bó chữ vào 72px nên "Chấm công" bị xuống dòng hoặc co lại còn 9px.
class _Rail extends StatelessWidget {
  const _Rail({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        color: AppTheme.surface,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.gapSm),
              for (var i = 0; i < _HomeShellState._destinations.length; i++)
                _RailItem(
                  destination: _HomeShellState._destinations[i],
                  selected: i == index,
                  onTap: () => onSelected(i),
                ),
            ],
          ),
        ),
      );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ({IconData icon, IconData active, String label}) destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Column(
            children: [
              Icon(selected ? destination.active : destination.icon, size: 22, color: color),
              const SizedBox(height: 5),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dấu hiệu nhận diện ở góc trái thanh tiêu đề.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: const Icon(Icons.scale, size: 16, color: Colors.white),
          ),
          const SizedBox(width: AppTheme.gapSm),
          const Text('CÂN XE', style: TextStyle(letterSpacing: 0.4)),
        ],
      );
}

/// Tên kho trên thanh tiêu đề, bấm vào để chuyển sang kho khác.
class _StationButton extends StatelessWidget {
  const _StationButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showStationPicker(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warehouse_outlined, size: 15, color: AppTheme.textSoft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.text,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, size: 17, color: AppTheme.textMuted),
            ],
          ),
        ),
      );
}

/// Tên người đang đăng nhập trên thanh tiêu đề.
class _UserChip extends StatelessWidget {
  const _UserChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSoft,
            ),
          ),
        ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
