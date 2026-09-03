import 'dart:io';

/// Ghi nhật ký của máy chủ ra màn hình và (tuỳ chọn) ra file.
///
/// Khi chạy dưới dạng tác vụ Windows thì không có cửa sổ nào để xem, nên file
/// log là chỗ duy nhất biết được đầu cân có mở được cổng COM hay không. Máy ở
/// kho chạy liên tục nhiều tháng nên log phải tự cắt, không được để đầy ổ.
abstract final class AppLog {
  static IOSink? _sink;
  static String? _path;

  /// Ngưỡng cắt log. Vượt quá thì đổi tên thành `<tên>.cu` và mở file mới.
  static const int maxBytes = 5 * 1024 * 1024;

  static String? get path => _path;

  static void init(String? filePath) {
    if (filePath == null || filePath.trim().isEmpty) return;
    final file = File(filePath);
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        final old = File('$filePath.cu');
        if (old.existsSync()) old.deleteSync();
        file.renameSync('$filePath.cu');
      }
      _sink = File(filePath).openWrite(mode: FileMode.append);
      _path = filePath;
      write('===== khởi động lúc ${DateTime.now()} =====');
    } catch (e) {
      stderr.writeln('Không mở được file log "$filePath": $e');
    }
  }

  static void write(String message) {
    stdout.writeln(message);
    _sink?.writeln(message);
  }

  static void error(String message) {
    stderr.writeln(message);
    _sink?.writeln('[LỖI] $message');
  }

  static Future<void> close() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    await sink.flush();
    await sink.close();
  }
}
