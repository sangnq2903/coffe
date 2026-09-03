import 'dart:math';

/// Sinh UUID v4 bằng [Random.secure] — dùng làm khoá chính cho mọi bản ghi.
///
/// Khoá chính là UUID (không phải auto-increment) để trạm cân có thể tạo phiếu
/// khi mất kết nối rồi đẩy lên máy chủ trung tâm mà không đụng ID với kho khác.
String newUuid() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
