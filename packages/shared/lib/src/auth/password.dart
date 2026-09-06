import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Băm và kiểm mật khẩu bằng PBKDF2-HMAC-SHA256.
///
/// Không bao giờ lưu mật khẩu dạng chữ. Mỗi người một chuỗi muối riêng, nên hai
/// người đặt trùng mật khẩu vẫn ra hai chuỗi băm khác nhau — kẻ lấy được cơ sở
/// dữ liệu không thể tra bảng sẵn để dò ngược.
///
/// Số vòng lặp được lưu kèm từng bản ghi: sau này máy mạnh lên, tăng số vòng
/// cho người mới mà mật khẩu cũ vẫn kiểm được bình thường.
abstract final class PasswordHasher {
  /// Số vòng mặc định cho tài khoản mới.
  static const int defaultIterations = 120000;

  static const int _saltLength = 16;
  static const int _keyLength = 32;

  static final Random _random = Random.secure();

  /// Sinh chuỗi muối ngẫu nhiên, mã hoá base64.
  static String newSalt() {
    final bytes = List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Băm mật khẩu, trả về chuỗi base64.
  static String hash(String password, String salt, {int iterations = defaultIterations}) {
    final derived = _pbkdf2(
      utf8.encode(password),
      base64Url.decode(salt),
      iterations,
      _keyLength,
    );
    return base64Url.encode(derived);
  }

  /// Sinh khoá mã hoá từ một câu mật khẩu.
  ///
  /// Dùng chung lò PBKDF2 với việc băm mật khẩu đăng nhập vì bài toán giống
  /// nhau: biến một câu người nhớ được thành chuỗi byte khó dò. Khác ở chỗ trả
  /// về byte thô để đưa thẳng vào thuật toán mã hoá, và cho chọn độ dài — bản
  /// sao lưu cần 64 byte để tách làm hai khoá riêng (một để mã hoá, một để ký).
  static Uint8List deriveKey(
    String passphrase,
    List<int> salt, {
    required int iterations,
    int length = 32,
  }) =>
      _pbkdf2(utf8.encode(passphrase), salt, iterations, length);

  /// Kiểm mật khẩu người dùng nhập với chuỗi băm đã lưu.
  static bool verify({
    required String password,
    required String salt,
    required String expectedHash,
    required int iterations,
  }) {
    if (salt.isEmpty || expectedHash.isEmpty) return false;
    try {
      final actual = hash(password, salt, iterations: iterations);
      return _constantTimeEquals(actual, expectedHash);
    } catch (_) {
      return false;
    }
  }

  /// So sánh không phụ thuộc nội dung.
  ///
  /// So bằng `==` sẽ dừng ngay ở ký tự đầu khác nhau; đo thời gian phản hồi
  /// nhiều lần có thể dò ra dần từng ký tự của chuỗi băm đúng.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final output = <int>[];
    var block = 1;

    while (output.length < keyLength) {
      final blockIndex = Uint8List(4)..buffer.asByteData().setUint32(0, block, Endian.big);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final f = List<int>.from(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < f.length; j++) {
          f[j] ^= u[j];
        }
      }
      output.addAll(f);
      block++;
    }
    return Uint8List.fromList(output.sublist(0, keyLength));
  }
}
