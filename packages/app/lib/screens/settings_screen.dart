import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Cài đặt kết nối của thiết bị và tình trạng hệ thống.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _serverController;
  late final TextEditingController _operatorController;
  SyncStatus? _syncStatus;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettings>();
    _serverController = TextEditingController(text: settings.serverUrl);
    _operatorController = TextEditingController(text: settings.operatorName);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSyncStatus());
  }

  @override
  void dispose() {
    _serverController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _loadSyncStatus() async {
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    try {
      final status = await client.syncStatus();
      if (mounted) setState(() => _syncStatus = status);
    } on ApiException {
      // Không có thông tin đồng bộ thì phần đó chỉ đơn giản là không hiện.
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final settings = context.read<AppSettings>();
    final conn = context.read<ServerConnection>();
    await settings.setServerUrl(_serverController.text);
    await settings.setOperatorName(_operatorController.text);
    await conn.connect();
    await _loadSyncStatus();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _syncNow() async {
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    setState(() => _busy = true);
    try {
      final status = await client.syncNow();
      if (mounted) setState(() => _syncStatus = status);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    final settings = context.watch<AppSettings>();
    final info = conn.serverInfo;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          title: 'Kết nối máy chủ',
          children: [
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ máy chủ',
                hintText: 'http://100.76.81.118:9080',
                helperText: 'Để trống khi mở app từ chính máy chủ (bản web).',
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _operatorController,
              decoration: const InputDecoration(
                labelText: 'Tên người cân',
                helperText: 'Ghi vào phiếu để biết ai lập',
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _apply,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: const Text('Áp dụng & kết nối lại'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Đang dùng: ${conn.baseUrl}',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (conn.error != null) ...[
              const SizedBox(height: 8),
              Text(conn.error!, style: const TextStyle(color: AppTheme.offline)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _card(
          title: 'Trạm cân đang theo dõi',
          children: [
            // Chỉ liệt kê trạm có đầu cân: máy chủ trung tâm cũng nằm trong
            // bảng trạm nhưng không có bàn cân, chọn nhầm là màn hình đứng ở
            // "mất kết nối" dù hệ thống vẫn chạy đúng.
            DropdownButtonFormField<String>(
              value: conn.scaleStations.any((s) => s.code == settings.stationCode)
                  ? settings.stationCode
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Chọn trạm cân / kho',
                helperText: 'Số cân realtime sẽ lấy từ trạm này',
                prefixIcon: Icon(Icons.scale),
              ),
              items: conn.scaleStations
                  .map((s) => DropdownMenuItem(
                        value: s.code,
                        child: Text('${s.name} (${s.code})'),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) settings.setStationCode(value);
              },
            ),
            if (conn.scaleStations.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppTheme.gapSm),
                child: Text(
                  'Chưa có trạm cân nào kết nối lên máy chủ. Kiểm tra máy ở kho đã bật '
                  'phần mềm và khai báo cổng COM chưa.',
                  style: TextStyle(color: AppTheme.offline, fontSize: 12.5),
                ),
              ),
            const SizedBox(height: 12),
            ...conn.stations.map(_stationTile),
          ],
        ),
        const SizedBox(height: 16),
        if (info != null)
          _card(
            title: 'Máy chủ đang kết nối',
            children: [
              _infoRow('Vai trò',
                  info.isCentral ? 'Máy chủ trung tâm' : 'Máy trạm cân'),
              _infoRow('Mã trạm', info.stationCode),
              _infoRow('Phiên bản', info.version),
              _infoRow('Cổng đầu cân', info.scalePort ?? '—'),
              _infoRow('Đầu cân', info.scaleConnected ? 'Đang kết nối' : 'Chưa kết nối'),
            ],
          ),
        const SizedBox(height: 16),
        if (_syncStatus != null)
          _card(
            title: 'Đồng bộ với máy chủ trung tâm',
            children: [
              _infoRow('Trạng thái',
                  _syncStatus!.online ? 'Đang kết nối' : 'Mất kết nối'),
              _infoRow('Bản ghi chờ đẩy lên', '${_syncStatus!.pendingPush}'),
              _infoRow('Lần đồng bộ gần nhất', formatDateTime(_syncStatus!.lastSyncAt)),
              if (_syncStatus!.lastError != null)
                _infoRow('Lỗi gần nhất', _syncStatus!.lastError!),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _syncNow,
                icon: const Icon(Icons.sync),
                label: const Text('Đồng bộ ngay'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _stationTile(Station station) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          Icons.circle,
          size: 12,
          color: station.online ? AppTheme.stable : Colors.grey,
        ),
        title: Text('${station.name} (${station.code})'),
        subtitle: Text(
          [
            station.baseUrl ?? 'chưa khai địa chỉ',
            if (station.scalePort != null && station.scalePort!.isNotEmpty)
              'đầu cân ${station.scalePort}',
            if (station.lastSeenAt != null) 'thấy lúc ${formatTime(station.lastSeenAt)}',
          ].join(' • '),
        ),
      );

  Widget _card({required String title, required List<Widget> children}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 190,
              child: Text(label, style: const TextStyle(color: Colors.black54)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
