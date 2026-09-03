import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';

/// Nơi tập trung số cân realtime của mọi trạm.
///
/// Ở máy trạm chỉ có một nguồn (đầu cân nối cổng COM của chính máy đó). Ở máy
/// chủ trung tâm có nhiều nguồn — mỗi trạm đẩy về một luồng — nên cần gom lại
/// một chỗ rồi phát tiếp cho các client đang xem.
class ReadingBroker {
  final _controller = StreamController<ScaleReading>.broadcast();
  final Map<String, ScaleReading> _latest = {};

  /// Toàn bộ số cân của mọi trạm.
  Stream<ScaleReading> get all => _controller.stream;

  /// Số cân của riêng một trạm — dùng cho WebSocket `/ws/scale?station=...`.
  Stream<ScaleReading> forStation(String stationCode) =>
      _controller.stream.where((r) => r.stationCode == stationCode);

  ScaleReading? latestFor(String stationCode) => _latest[stationCode];

  Map<String, ScaleReading> get snapshot => Map.unmodifiable(_latest);

  void publish(ScaleReading reading) {
    _latest[reading.stationCode] = reading;
    if (!_controller.isClosed) _controller.add(reading);
  }

  /// Khi trạm rớt kết nối, phải chủ động báo mất tín hiệu; nếu không màn hình ở
  /// trung tâm sẽ đứng ở số cân cuối cùng và bị hiểu nhầm là số thật.
  void markStationOffline(String stationCode) {
    final last = _latest[stationCode];
    if (last != null && !last.connected) return;
    publish(ScaleReading.disconnected(
      stationCode,
      error: 'Trạm cân đã ngắt kết nối tới máy chủ',
    ));
  }

  Future<void> dispose() => _controller.close();
}
