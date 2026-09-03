/// Lỗi trả về từ API, đã kèm thông điệp tiếng Việt để hiển thị thẳng cho người
/// dùng ở trạm cân.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}
