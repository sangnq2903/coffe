import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';

import '../config.dart';
import '../db/repository.dart';

/// Đồng bộ dữ liệu hai chiều giữa trạm cân và máy chủ trung tâm.
///
/// Trạm cân vẫn cân và lưu được khi đứt mạng Tailscale; worker này chỉ có
/// nhiệm vụ dồn phần chênh lệch lên trung tâm khi mạng thông trở lại, và kéo
/// danh mục dùng chung của các kho khác về.
class SyncWorker {
  SyncWorker({
    required this.config,
    required this.repo,
    ApiClient? client,
  }) : _client = client ??
            ApiClient(baseUrl: config.centralUri ?? Uri.parse('http://127.0.0.1'));

  static const _pullMarkKey = 'central_pull_mark';

  final ServerConfig config;
  final Repository repo;
  final ApiClient _client;

  Timer? _timer;
  bool _busy = false;
  bool _online = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  SyncStatus get status => SyncStatus(
        online: _online,
        pendingPush: repo.pendingPushCount(),
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );

  void start() {
    if (config.centralUri == null) return;
    // Chạy ngay một lần để dữ liệu tồn từ lần chạy trước được đẩy đi sớm.
    unawaited(syncOnce());
    _timer = Timer.periodic(
      Duration(seconds: config.syncIntervalSeconds.clamp(5, 3600)),
      (_) => unawaited(syncOnce()),
    );
  }

  /// Một vòng đồng bộ: đẩy thay đổi cục bộ lên, rồi kéo thay đổi từ trung tâm về.
  Future<void> syncOnce() async {
    if (_busy || config.centralUri == null) return;
    _busy = true;
    try {
      await _push();
      await _pull();
      _online = true;
      _lastError = null;
      _lastSyncAt = DateTime.now();
    } on ApiException catch (e) {
      _online = false;
      _lastError = e.message;
    } catch (e) {
      _online = false;
      _lastError = '$e';
    } finally {
      _busy = false;
    }
  }

  Future<void> _push() async {
    // Đẩy theo lô: một trạm mất mạng cả ngày có thể tồn hàng nghìn bản ghi,
    // gửi một cục sẽ vượt giới hạn body và timeout.
    while (true) {
      final payload = repo.dirtyChanges(limit: 200);
      if (payload.isEmpty) break;
      await _client.syncPush(payload);
      repo.clearDirty(payload);
      if (payload.totalRecords < 200) break;
    }
  }

  Future<void> _pull() async {
    final since = repo.syncMark(_pullMarkKey);
    final payload = await _client.syncPull(since);
    if (!payload.isEmpty) {
      repo.applyPayload(payload, markDirty: false);
    }
    // Dùng giờ do máy chủ trung tâm trả về làm mốc, vì đồng hồ hai máy có thể
    // lệch nhau vài giây và sẽ làm sót bản ghi ở lần kéo sau.
    final mark = payload.serverTime ?? DateTime.now();
    repo.setSyncMark(_pullMarkKey, mark);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _client.close();
  }
}
