import '../ids.dart';
import '../json_utils.dart';

/// Vai trò tài khoản.
enum UserRole {
  /// Thấy và làm được mọi thứ ở mọi kho.
  tong('tong', 'Quản lý tổng'),

  /// Chỉ thấy dữ liệu của những kho được gán.
  tram('tram', 'Nhân viên trạm cân');

  const UserRole(this.value, this.label);

  final String value;
  final String label;

  static UserRole parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => UserRole.tram,
      );
}

/// Tài khoản đăng nhập.
///
/// Chuỗi băm mật khẩu **mặc định không đi kèm** khi chuyển thành JSON. Chỉ luồng
/// đồng bộ giữa máy chủ mới bật cờ kèm theo, để máy trạm kiểm được mật khẩu tại
/// chỗ khi mất mạng. Trả chuỗi băm về trình duyệt là tự dâng cơ sở dữ liệu mật
/// khẩu cho bất kỳ ai mở được màn hình mạng.
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.stationScope = const [],
    this.active = true,
    this.machineAccount = false,
    this.isOwner = false,
    this.passwordHash,
    this.salt,
    this.iterations = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  factory AppUser.create({
    required String username,
    required String fullName,
    required UserRole role,
    List<String> stationScope = const [],
    bool machineAccount = false,
    bool isOwner = false,
    required String passwordHash,
    required String salt,
    required int iterations,
  }) =>
      AppUser(
        id: newUuid(),
        username: username.trim().toLowerCase(),
        fullName: fullName,
        role: role,
        stationScope: stationScope,
        machineAccount: machineAccount,
        isOwner: isOwner,
        passwordHash: passwordHash,
        salt: salt,
        iterations: iterations,
        updatedAt: DateTime.now(),
      );

  factory AppUser.fromJson(Map<String, Object?> json) => AppUser(
        id: asString(json['id']),
        username: asString(json['username']),
        fullName: asString(json['full_name']),
        role: UserRole.parse(json['role']),
        stationScope: _parseScope(json['station_scope']),
        active: asBool(json['active'], fallback: true),
        machineAccount: asBool(json['machine_account']),
        isOwner: asBool(json['is_owner']),
        passwordHash: asStringOrNull(json['password_hash']),
        salt: asStringOrNull(json['salt']),
        iterations: asInt(json['iterations']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Phạm vi kho lưu thành chuỗi ngăn cách bằng dấu phẩy thay vì bảng riêng.
  ///
  /// Toàn bộ cơ chế đồng bộ của hệ thống làm việc theo dòng; thêm một bảng nối
  /// sẽ phải dựng thêm cả luồng đồng bộ cho nó, trong khi số kho chỉ vài cái.
  static List<String> _parseScope(Object? raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().toUpperCase()).where((e) => e.isNotEmpty).toList();
    }
    final text = asString(raw);
    if (text.isEmpty) return const [];
    return text
        .split(',')
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  final String id;

  /// Tên đăng nhập, luôn viết thường để không phân biệt hoa thường khi đăng nhập.
  final String username;
  final String fullName;
  final UserRole role;

  /// Danh sách mã kho được phép. Bỏ trống + vai trò tổng nghĩa là mọi kho.
  final List<String> stationScope;
  final bool active;

  /// Tài khoản do máy trạm dùng để đồng bộ, ẩn khỏi danh sách người dùng.
  final bool machineAccount;

  /// Tài khoản **chủ** — tài khoản lập đầu tiên lúc cài máy chủ.
  ///
  /// Chỉ chủ mới thấy sổ mua bán. Cờ này không cấp thêm cho ai được: đặt đúng
  /// một lần khi lập tài khoản đầu tiên, để không ai tự nâng quyền cho mình
  /// bằng cách sửa vai trò.
  final bool isOwner;

  final String? passwordHash;
  final String? salt;
  final int iterations;

  final DateTime updatedAt;
  final bool deleted;

  bool get isAdmin => role == UserRole.tong;

  /// Xem được toàn bộ kho hay không.
  bool get seesAllStations => role == UserRole.tong;

  /// Có được đụng vào dữ liệu của kho này không.
  ///
  /// Viết hoa cả hai vế khi so: mã kho có thể được nhập tay, đọc từ JSON hay
  /// dựng thẳng trong code, không thể tin là chỗ nào cũng đã chuẩn hoá sẵn.
  /// So khớp trượt ở đây nghĩa là người có quyền lại bị chặn.
  bool canAccessStation(String? stationCode) {
    if (seesAllStations) return true;
    if (stationCode == null || stationCode.isEmpty) return false;
    final wanted = stationCode.trim().toUpperCase();
    return stationScope.any((e) => e.trim().toUpperCase() == wanted);
  }

  String get displayName => fullName.isEmpty ? username : fullName;

  Map<String, Object?> toJson({bool includeSecret = false}) => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'role': role.value,
        'station_scope': stationScope.join(','),
        'active': active ? 1 : 0,
        'machine_account': machineAccount ? 1 : 0,
        'is_owner': isOwner ? 1 : 0,
        if (includeSecret) 'password_hash': passwordHash,
        if (includeSecret) 'salt': salt,
        if (includeSecret) 'iterations': iterations,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  AppUser copyWith({
    String? username,
    String? fullName,
    UserRole? role,
    List<String>? stationScope,
    bool? active,
    String? passwordHash,
    String? salt,
    int? iterations,
    bool? deleted,
  }) =>
      AppUser(
        id: id,
        username: username?.trim().toLowerCase() ?? this.username,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        stationScope: stationScope ?? this.stationScope,
        active: active ?? this.active,
        machineAccount: machineAccount,
        isOwner: isOwner,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        iterations: iterations ?? this.iterations,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
