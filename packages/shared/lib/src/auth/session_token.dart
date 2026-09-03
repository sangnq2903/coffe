import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Nội dung đọc được từ một phiếu phiên hợp lệ.
class SessionClaims {
  const SessionClaims({
    required this.userId,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String userId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// Tạo và kiểm phiếu phiên đăng nhập, ký bằng HMAC-SHA256.
///
/// Phiếu tự mang chữ ký nên máy chủ kiểm được ngay mà không phải tra cơ sở dữ
/// liệu — quan trọng với máy trạm ở kho, vốn phải làm việc cả khi đứt mạng.
///
/// Khoá ký sinh ngẫu nhiên riêng cho từng máy chủ và không nằm trong mã nguồn.
/// Nếu khoá lộ, bất kỳ ai cũng tự ký được phiếu và vào thẳng hệ thống.
abstract final class SessionToken {
  static const Duration defaultLifetime = Duration(days: 30);

  static final Random _random = Random.secure();

  /// Sinh khoá ký mới cho một máy chủ.
  static String newSecret() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String create({
    required String userId,
    required String secret,
    Duration lifetime = defaultLifetime,
    DateTime? now,
  }) {
    final issued = now ?? DateTime.now();
    final payload = jsonEncode({
      'uid': userId,
      'iat': issued.toUtc().millisecondsSinceEpoch,
      'exp': issued.add(lifetime).toUtc().millisecondsSinceEpoch,
    });
    final body = base64Url.encode(utf8.encode(payload));
    return '$body.${_sign(body, secret)}';
  }

  /// Trả về `null` khi phiếu sai chữ ký, hỏng định dạng hoặc đã hết hạn.
  static SessionClaims? verify(String? token, String secret) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 2) return null;

    if (!_constantTimeEquals(_sign(parts[0], secret), parts[1])) return null;

    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(parts[0])));
      if (decoded is! Map) return null;

      final userId = decoded['uid']?.toString();
      final issuedMs = decoded['iat'];
      final expiresMs = decoded['exp'];
      if (userId == null || userId.isEmpty || issuedMs is! int || expiresMs is! int) {
        return null;
      }

      final claims = SessionClaims(
        userId: userId,
        issuedAt: DateTime.fromMillisecondsSinceEpoch(issuedMs, isUtc: true).toLocal(),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresMs, isUtc: true).toLocal(),
      );
      return claims.expired ? null : claims;
    } catch (_) {
      return null;
    }
  }

  static String _sign(String body, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return base64Url.encode(hmac.convert(utf8.encode(body)).bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
