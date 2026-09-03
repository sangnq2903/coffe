import '../ids.dart';
import '../json_utils.dart';

/// Thông tin xe vào cân.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.plateNo,
    this.customerId,
    this.driverName,
    this.driverPhone,
    this.tareWeight,
    this.note,
    this.active = true,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Vehicle.create({
    required String plateNo,
    String? customerId,
    String? driverName,
    String? driverPhone,
    double? tareWeight,
    String? note,
  }) =>
      Vehicle(
        id: newUuid(),
        plateNo: normalizePlate(plateNo),
        customerId: customerId,
        driverName: driverName,
        driverPhone: driverPhone,
        tareWeight: tareWeight,
        note: note,
        updatedAt: DateTime.now(),
      );

  factory Vehicle.fromJson(Map<String, Object?> json) => Vehicle(
        id: asString(json['id']),
        plateNo: asString(json['plate_no']),
        customerId: asStringOrNull(json['customer_id']),
        driverName: asStringOrNull(json['driver_name']),
        driverPhone: asStringOrNull(json['driver_phone']),
        tareWeight: asDoubleOrNull(json['tare_weight']),
        note: asStringOrNull(json['note']),
        active: asBool(json['active'], fallback: true),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Chuẩn hoá biển số về chữ HOA, bỏ khoảng trắng và dấu chấm để so khớp và
  /// chống tạo trùng ("51C-123.45" và "51c 12345" là một xe).
  static String normalizePlate(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[\s.]'), '');

  final String id;
  final String plateNo;

  /// Chủ xe mặc định — chỉ để gợi ý khi lập phiếu, không ràng buộc.
  final String? customerId;
  final String? driverName;
  final String? driverPhone;

  /// Khối lượng bì đăng ký (kg), dùng để cảnh báo khi cân lệch bất thường.
  final double? tareWeight;
  final String? note;
  final bool active;
  final DateTime updatedAt;
  final bool deleted;

  String get searchText => '$plateNo ${driverName ?? ''}'.toLowerCase();

  Map<String, Object?> toJson() => {
        'id': id,
        'plate_no': plateNo,
        'customer_id': customerId,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'tare_weight': tareWeight,
        'note': note,
        'active': active ? 1 : 0,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Vehicle copyWith({
    String? plateNo,
    String? customerId,
    String? driverName,
    String? driverPhone,
    double? tareWeight,
    String? note,
    bool? active,
    bool? deleted,
  }) =>
      Vehicle(
        id: id,
        plateNo: plateNo == null ? this.plateNo : normalizePlate(plateNo),
        customerId: customerId ?? this.customerId,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        tareWeight: tareWeight ?? this.tareWeight,
        note: note ?? this.note,
        active: active ?? this.active,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
