import '../json_utils.dart';

/// Một số cân đọc được từ cổng COM của đầu cân.
///
/// Đây là dữ liệu realtime, không lưu vào cơ sở dữ liệu — chỉ đẩy qua WebSocket
/// để màn hình hiển thị số cân nhảy liên tục.
class ScaleReading {
  const ScaleReading({
    required this.stationCode,
    required this.weight,
    required this.unit,
    required this.stable,
    required this.at,
    this.raw,
    this.connected = true,
    this.error,
  });

  factory ScaleReading.fromJson(Map<String, Object?> json) => ScaleReading(
        stationCode: asString(json['station_code']),
        weight: asDouble(json['weight']),
        unit: asString(json['unit'], fallback: 'kg'),
        stable: asBool(json['stable']),
        at: asTime(json['at']),
        raw: asStringOrNull(json['raw']),
        connected: asBool(json['connected'], fallback: true),
        error: asStringOrNull(json['error']),
      );

  /// Trạng thái khi chưa mở được cổng COM hoặc mất kết nối tới trạm.
  factory ScaleReading.disconnected(String stationCode, {String? error}) =>
      ScaleReading(
        stationCode: stationCode,
        weight: 0,
        unit: 'kg',
        stable: false,
        at: DateTime.now(),
        connected: false,
        error: error,
      );

  final String stationCode;
  final double weight;
  final String unit;

  /// Đầu cân báo số đã đứng yên (ST) — chỉ nên chốt phiếu khi cờ này bật.
  final bool stable;
  final DateTime at;

  /// Khung dữ liệu thô từ COM, giữ lại để chẩn đoán khi đấu nối sai giao thức.
  final String? raw;
  final bool connected;
  final String? error;

  Map<String, Object?> toJson() => {
        'station_code': stationCode,
        'weight': weight,
        'unit': unit,
        'stable': stable,
        'at': timeToMillis(at),
        'raw': raw,
        'connected': connected,
        'error': error,
      };
}
