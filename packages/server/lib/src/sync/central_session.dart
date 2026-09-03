import 'package:canxe_shared/canxe_shared.dart';

import '../config.dart';
import '../logging.dart';

/// Phiên đăng nhập của máy trạm lên máy chủ trung tâm.
///
/// Dùng chung cho cả luồng đồng bộ dữ liệu và kênh đẩy số cân realtime, để cả
/// hai xài một phiếu phiên thay vì mỗi bên tự đăng nhập một kiểu.
class CentralSession {
  CentralSession({required this.config, ApiClient? client})
      : client = client ??
            ApiClient(baseUrl: config.centralUri ?? Uri.parse('http://127.0.0.1'));

  final ServerConfig config;
  final ApiClient client;

  String? lastError;

  bool get configured =>
      config.centralUri != null &&
      (config.centralUsername ?? '').isNotEmpty &&
      (config.centralPassword ?? '').isNotEmpty;

  String? get token => client.authToken;

  /// Đăng nhập nếu chưa có phiếu phiên còn dùng được.
  Future<bool> ensureLoggedIn() async {
    if (client.hasToken) return true;
    if (!configured) {
      lastError = 'Chưa khai báo central.username / central.password trong cấu hình trạm.';
      return false;
    }
    try {
      final result = await client.login(config.centralUsername!, config.centralPassword!);
      client.authToken = result.token;
      lastError = null;
      AppLog.write('[đồng bộ] đã đăng nhập lên trung tâm với tài khoản '
          '"${result.user.username}"');
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      AppLog.error('[đồng bộ] không đăng nhập được lên trung tâm: ${e.message}');
      return false;
    }
  }

  /// Bỏ phiếu phiên hiện tại để lần sau đăng nhập lại.
  ///
  /// Gọi khi trung tâm trả về 401: phiếu có thể đã hết hạn, hoặc máy chủ trung
  /// tâm được cài lại và sinh khoá ký mới.
  void invalidate() => client.authToken = null;

  void close() => client.close();
}
