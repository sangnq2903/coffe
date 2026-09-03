import '../json_utils.dart';

/// Một trạm cân = một kho. Máy chủ trung tâm giữ danh sách này để app biết có
/// những trạm nào và địa chỉ Tailscale để nối trực tiếp lấy số cân realtime.
class Station {
  const Station({
    required this.code,
    required this.name,
    this.warehouseName,
    this.address,
    this.baseUrl,
    this.online = false,
    this.lastSeenAt,
    this.scaleConnected = false,
    this.scalePort,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Station.fromJson(Map<String, Object?> json) => Station(
        code: asString(json['code']),
        name: asString(json['name']),
        warehouseName: asStringOrNull(json['warehouse_name']),
        address: asStringOrNull(json['address']),
        baseUrl: asStringOrNull(json['base_url']),
        online: asBool(json['online']),
        lastSeenAt: asTimeOrNull(json['last_seen_at']),
        scaleConnected: asBool(json['scale_connected']),
        scalePort: asStringOrNull(json['scale_port']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Mã trạm, duy nhất toàn hệ thống (ví dụ `KHO01`). Dùng làm tiền tố số phiếu.
  final String code;
  final String name;
  final String? warehouseName;
  final String? address;

  /// Địa chỉ HTTP của máy trạm trên mạng Tailscale, ví dụ `http://100.x.y.z:8080`.
  final String? baseUrl;

  /// Trạm đang giữ kết nối uplink tới máy chủ trung tâm hay không.
  final bool online;
  final DateTime? lastSeenAt;

  /// Cổng COM của đầu cân đang mở được hay không.
  final bool scaleConnected;
  final String? scalePort;
  final DateTime updatedAt;
  final bool deleted;

  /// Trạm này có đầu cân hay không.
  ///
  /// Máy chủ trung tâm cũng nằm trong bảng trạm (để hiện trong danh sách kho)
  /// nhưng không có bàn cân, nên không được chọn làm nguồn số cân realtime.
  bool get hasScale => scalePort != null && scalePort!.isNotEmpty;

  String get displayName => warehouseName == null || warehouseName!.isEmpty
      ? name
      : '$name — $warehouseName';

  Map<String, Object?> toJson() => {
        'code': code,
        'name': name,
        'warehouse_name': warehouseName,
        'address': address,
        'base_url': baseUrl,
        'online': online ? 1 : 0,
        'last_seen_at': timeToMillisOrNull(lastSeenAt),
        'scale_connected': scaleConnected ? 1 : 0,
        'scale_port': scalePort,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Station copyWith({
    String? name,
    String? warehouseName,
    String? address,
    String? baseUrl,
    bool? online,
    DateTime? lastSeenAt,
    bool? scaleConnected,
    String? scalePort,
    bool? deleted,
  }) =>
      Station(
        code: code,
        name: name ?? this.name,
        warehouseName: warehouseName ?? this.warehouseName,
        address: address ?? this.address,
        baseUrl: baseUrl ?? this.baseUrl,
        online: online ?? this.online,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        scaleConnected: scaleConnected ?? this.scaleConnected,
        scalePort: scalePort ?? this.scalePort,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
