import 'package:canxe_shared/canxe_shared.dart';

import '../db/repository.dart';
import '../logging.dart';

/// Lỗi đăng nhập / phân quyền, kèm mã HTTP tương ứng.
class AuthException implements Exception {
  AuthException(this.message, this.statusCode);

  AuthException.unauthorized(this.message) : statusCode = 401;

  AuthException.forbidden(this.message) : statusCode = 403;

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

/// Quản lý tài khoản và phiên đăng nhập.
class AuthService {
  /// [iterations] chỉ để kiểm thử hạ xuống cho chạy nhanh. Khi chạy thật luôn
  /// dùng giá trị mặc định — hạ số vòng là làm yếu hẳn lớp bảo vệ mật khẩu.
  AuthService(this._repo, {this.iterations = PasswordHasher.defaultIterations});

  static const _secretKey = 'auth_secret';

  final Repository _repo;
  final int iterations;
  String? _cachedSecret;

  /// Khoá ký phiên của riêng máy chủ này.
  ///
  /// Sinh ngẫu nhiên lần chạy đầu và cất trong cơ sở dữ liệu — không nằm trong
  /// mã nguồn, nên đưa mã lên GitHub công khai cũng không ai ký được phiếu giả.
  /// Mỗi máy chủ một khoá riêng: phiếu cấp ở máy nào chỉ dùng ở máy đó.
  String get secret {
    final cached = _cachedSecret;
    if (cached != null) return cached;

    var stored = _repo.state(_secretKey);
    if (stored == null || stored.isEmpty) {
      stored = SessionToken.newSecret();
      _repo.setState(_secretKey, stored);
      AppLog.write('[đăng nhập] đã sinh khoá ký phiên mới cho máy chủ này');
    }
    _cachedSecret = stored;
    return stored;
  }

  /// Chưa có tài khoản người thật nào — app sẽ hiện màn hình tạo tài khoản chủ.
  bool get needsSetup => _repo.humanUserCount() == 0;

  /// Tạo tài khoản quản lý tổng đầu tiên.
  ///
  /// Chỉ chạy được khi hệ thống chưa có tài khoản người thật nào. Nếu không
  /// chặn, bất kỳ ai gọi được đường dẫn này cũng tự tạo cho mình quyền tổng.
  AppUser createFirstAdmin({
    required String username,
    required String fullName,
    required String password,
  }) {
    if (!needsSetup) {
      throw AuthException.forbidden(
        'Hệ thống đã có tài khoản. Hãy đăng nhập rồi thêm người dùng trong phần quản lý.',
      );
    }
    return createUser(
      username: username,
      fullName: fullName,
      password: password,
      role: UserRole.tong,
    );
  }

  AppUser createUser({
    required String username,
    required String fullName,
    required String password,
    required UserRole role,
    List<String> stationScope = const [],
    bool machineAccount = false,
  }) {
    final name = username.trim().toLowerCase();
    _validateUsername(name);
    _validatePassword(password);

    if (_repo.userByUsername(name) != null) {
      throw AuthException('Tên đăng nhập "$name" đã có người dùng.', 400);
    }
    if (role == UserRole.tram && stationScope.isEmpty) {
      throw AuthException('Tài khoản trạm cân phải được gán ít nhất một kho.', 400);
    }

    final salt = PasswordHasher.newSalt();
    return _repo.upsertUser(AppUser.create(
      username: name,
      fullName: fullName.trim(),
      role: role,
      stationScope: stationScope,
      machineAccount: machineAccount,
      passwordHash: PasswordHasher.hash(password, salt, iterations: iterations),
      salt: salt,
      iterations: iterations,
    ));
  }

  /// Kiểm tên đăng nhập và mật khẩu, trả về tài khoản nếu đúng.
  AppUser authenticate(String username, String password) {
    final user = _repo.userByUsername(username);

    // Cùng một thông báo cho "sai tên" và "sai mật khẩu": tách ra là vô tình
    // cho biết tên đăng nhập nào có thật để kẻ dò tập trung vào đó.
    const message = 'Tên đăng nhập hoặc mật khẩu không đúng.';
    if (user == null || !user.active) {
      throw AuthException.unauthorized(message);
    }
    final ok = PasswordHasher.verify(
      password: password,
      salt: user.salt ?? '',
      expectedHash: user.passwordHash ?? '',
      iterations: user.iterations,
    );
    if (!ok) throw AuthException.unauthorized(message);
    return user;
  }

  String issueToken(AppUser user) => SessionToken.create(userId: user.id, secret: secret);

  /// Đọc phiếu phiên, trả về tài khoản còn hiệu lực hoặc `null`.
  AppUser? userFromToken(String? token) {
    final claims = SessionToken.verify(token, secret);
    if (claims == null) return null;
    final user = _repo.userById(claims.userId);
    if (user == null || user.deleted || !user.active) return null;
    return user;
  }

  void changePassword({
    required AppUser user,
    required String oldPassword,
    required String newPassword,
  }) {
    authenticate(user.username, oldPassword);
    _validatePassword(newPassword);

    final salt = PasswordHasher.newSalt();
    _repo.upsertUser(user.copyWith(
      salt: salt,
      passwordHash: PasswordHasher.hash(newPassword, salt, iterations: iterations),
      iterations: iterations,
    ));
  }

  /// Đặt lại mật khẩu cho người khác — chỉ tài khoản tổng được làm.
  void resetPassword({required AppUser target, required String newPassword}) {
    _validatePassword(newPassword);
    final salt = PasswordHasher.newSalt();
    _repo.upsertUser(target.copyWith(
      salt: salt,
      passwordHash: PasswordHasher.hash(newPassword, salt, iterations: iterations),
      iterations: iterations,
    ));
  }

  static void _validateUsername(String username) {
    if (username.length < 3) {
      throw AuthException('Tên đăng nhập phải từ 3 ký tự trở lên.', 400);
    }
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(username)) {
      throw AuthException(
        'Tên đăng nhập chỉ được dùng chữ thường, số và các ký tự . _ -',
        400,
      );
    }
  }

  static void _validatePassword(String password) {
    if (password.length < 6) {
      throw AuthException('Mật khẩu phải từ 6 ký tự trở lên.', 400);
    }
  }
}
