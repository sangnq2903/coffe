/// Các hàm đọc JSON an toàn: dữ liệu đi qua HTTP/SQLite nên kiểu luôn có thể
/// khác kỳ vọng (int thay cho double, chuỗi rỗng thay cho null...).
String asString(Object? v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}

String? asStringOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

double asDouble(Object? v, {double fallback = 0}) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.')) ?? fallback;
}

double? asDoubleOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.'));
}

int asInt(Object? v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

bool asBool(Object? v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

/// Thời điểm được truyền dưới dạng epoch milliseconds (UTC) để tránh mọi
/// nhập nhằng múi giờ giữa các máy trong hệ thống.
DateTime asTime(Object? v) =>
    DateTime.fromMillisecondsSinceEpoch(asInt(v), isUtc: true).toLocal();

DateTime? asTimeOrNull(Object? v) {
  if (v == null) return null;
  final ms = asInt(v, fallback: -1);
  if (ms < 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
}

int timeToMillis(DateTime? v) => (v ?? DateTime.now()).toUtc().millisecondsSinceEpoch;

int? timeToMillisOrNull(DateTime? v) => v?.toUtc().millisecondsSinceEpoch;

List<Map<String, Object?>> asMapList(Object? v) {
  if (v is! List) return const [];
  return v.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
}
