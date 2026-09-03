import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Hộp thoại chọn kho/trạm cân đang theo dõi.
///
/// Chỉ những trạm có đầu cân mới chọn được: máy chủ trung tâm cũng nằm trong
/// danh sách kho nhưng không có bàn cân, chọn nhầm là màn hình đứng ở "mất kết
/// nối" dù hệ thống vẫn chạy đúng.
Future<void> showStationPicker(BuildContext context) async {
  final conn = context.read<ServerConnection>();
  await conn.refreshCatalogs();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) {
      final connection = context.watch<ServerConnection>();
      final stations = connection.scaleStations;
      final current = connection.stationCode;

      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warehouse, size: 20),
            SizedBox(width: AppTheme.gapSm),
            Text('Chọn trạm cân'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: 460,
          child: stations.isEmpty
              ? const EmptyHint(
                  icon: Icons.scale_outlined,
                  message: 'Chưa có trạm cân nào kết nối lên máy chủ.\n'
                      'Kiểm tra máy ở kho đã bật phần mềm và đã khai báo cổng COM chưa.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: stations.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _StationRow(station: stations[index], selected: stations[index].code == current),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      );
    },
  );
}

class _StationRow extends StatelessWidget {
  const _StationRow({required this.station, required this.selected});

  final Station station;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = station.online ? AppTheme.stable : AppTheme.textMuted;
    return ListTile(
      selected: selected,
      selectedTileColor: AppTheme.primary.withValues(alpha: 0.06),
      leading: Icon(Icons.circle, size: 12, color: color),
      title: Text(station.displayName),
      subtitle: Text(
        [
          'Mã ${station.code}',
          'đầu cân ${station.scalePort}',
          if (station.lastSeenAt != null) 'thấy lúc ${formatTime(station.lastSeenAt)}',
        ].join(' • '),
      ),
      trailing: selected ? const Icon(Icons.check_circle, color: AppTheme.primary) : null,
      onTap: () {
        context.read<ServerConnection>().settings.setStationCode(station.code);
        Navigator.pop(context);
      },
    );
  }
}
