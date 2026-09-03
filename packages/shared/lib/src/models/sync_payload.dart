import '../json_utils.dart';
import 'app_user.dart';
import 'customer.dart';
import 'goods_type.dart';
import 'vehicle.dart';
import 'weigh_ticket.dart';

/// Gói dữ liệu trao đổi hai chiều giữa trạm cân và máy chủ trung tâm.
///
/// Đồng bộ theo mốc thời gian: mỗi bên gửi các bản ghi có `updated_at` lớn hơn
/// mốc lần đồng bộ trước, bên nhận ghi đè theo nguyên tắc bản mới nhất thắng.
class SyncPayload {
  const SyncPayload({
    this.users = const [],
    this.customers = const [],
    this.vehicles = const [],
    this.goodsTypes = const [],
    this.tickets = const [],
    this.serverTime,
  });

  factory SyncPayload.fromJson(Map<String, Object?> json) => SyncPayload(
        users: asMapList(json['users']).map(AppUser.fromJson).toList(),
        customers:
            asMapList(json['customers']).map(Customer.fromJson).toList(),
        vehicles: asMapList(json['vehicles']).map(Vehicle.fromJson).toList(),
        goodsTypes:
            asMapList(json['goods_types']).map(GoodsType.fromJson).toList(),
        tickets: asMapList(json['tickets']).map(WeighTicket.fromJson).toList(),
        serverTime: asTimeOrNull(json['server_time']),
      );

  /// Tài khoản đăng nhập, kèm chuỗi băm mật khẩu.
  ///
  /// Máy trạm phải giữ được bản sao để nhân viên đăng nhập khi đứt mạng — nếu
  /// mỗi lần đăng nhập đều phải hỏi máy chủ trung tâm thì mất mạng là cả kho
  /// đứng bánh.
  final List<AppUser> users;
  final List<Customer> customers;
  final List<Vehicle> vehicles;
  final List<GoodsType> goodsTypes;
  final List<WeighTicket> tickets;

  /// Giờ máy chủ tại thời điểm trả kết quả — trạm lưu lại làm mốc `since` cho
  /// lần kéo tiếp theo, tránh lệch đồng hồ giữa các máy làm sót bản ghi.
  final DateTime? serverTime;

  bool get isEmpty =>
      users.isEmpty &&
      customers.isEmpty &&
      vehicles.isEmpty &&
      goodsTypes.isEmpty &&
      tickets.isEmpty;

  int get totalRecords =>
      users.length +
      customers.length +
      vehicles.length +
      goodsTypes.length +
      tickets.length;

  Map<String, Object?> toJson() => {
        'users': users.map((e) => e.toJson(includeSecret: true)).toList(),
        'customers': customers.map((e) => e.toJson()).toList(),
        'vehicles': vehicles.map((e) => e.toJson()).toList(),
        'goods_types': goodsTypes.map((e) => e.toJson()).toList(),
        'tickets': tickets.map((e) => e.toJson()).toList(),
        'server_time': timeToMillisOrNull(serverTime),
      };
}

/// Tình trạng đồng bộ của một trạm, hiển thị trên thanh trạng thái của app.
class SyncStatus {
  const SyncStatus({
    required this.online,
    required this.pendingPush,
    this.lastSyncAt,
    this.lastError,
  });

  factory SyncStatus.fromJson(Map<String, Object?> json) => SyncStatus(
        online: asBool(json['online']),
        pendingPush: asInt(json['pending_push']),
        lastSyncAt: asTimeOrNull(json['last_sync_at']),
        lastError: asStringOrNull(json['last_error']),
      );

  final bool online;

  /// Số bản ghi còn nằm lại ở trạm chưa đẩy được lên máy chủ trung tâm.
  final int pendingPush;
  final DateTime? lastSyncAt;
  final String? lastError;

  Map<String, Object?> toJson() => {
        'online': online,
        'pending_push': pendingPush,
        'last_sync_at': timeToMillisOrNull(lastSyncAt),
        'last_error': lastError,
      };
}
