import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart';

/// Giữ số cân realtime cho toàn app.
///
/// Đây là phần đáp ứng yêu cầu "màn hình hiển thị số cân nhận từ cổng COM,
/// nhảy liên tục mỗi khi có thay đổi": controller mở WebSocket tới server của
/// trạm cân và phát lại mọi khung nhận được cho giao diện vẽ.
class LiveWeightController extends ChangeNotifier {
  ScaleReading? _reading;
  LiveScaleClient? _live;
  StreamSubscription<ScaleReading>? _subscription;
  Uri? _currentUri;
  String _stationCode = '';

  ScaleReading? get reading => _reading;

  double get weight => _reading?.weight ?? 0;

  bool get connected => _reading?.connected ?? false;

  bool get stable => _reading?.stable ?? false;

  /// Chỉ cho phép chốt số khi đầu cân đang nối và số đã đứng yên — chốt lúc
  /// số còn nhảy là nguồn gốc của mọi phiếu sai khối lượng.
  bool get canCapture => connected && stable && weight > 0;

  String? get errorMessage => _reading?.error;

  /// Mở (hoặc chuyển sang) luồng số cân của một trạm.
  void connectTo(Uri? wsUri, String stationCode) {
    if (wsUri == null) {
      disconnect();
      return;
    }
    if (_currentUri == wsUri && _stationCode == stationCode && _live != null) {
      return;
    }
    disconnect();
    _currentUri = wsUri;
    _stationCode = stationCode;
    final live = LiveScaleClient(wsUrl: wsUri, stationCode: stationCode);
    _live = live;
    _subscription = live.readings.listen((reading) {
      _reading = reading;
      notifyListeners();
    });
    live.start();
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _live?.dispose();
    _live = null;
    _currentUri = null;
    _reading = null;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
