import '../ids.dart';
import '../json_utils.dart';

/// Thông tin khách hàng (chủ hàng).
class Customer {
  const Customer({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.address,
    this.taxCode,
    this.note,
    this.active = true,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Customer.create({
    required String name,
    String code = '',
    String? phone,
    String? address,
    String? taxCode,
    String? note,
  }) =>
      Customer(
        id: newUuid(),
        code: code,
        name: name,
        phone: phone,
        address: address,
        taxCode: taxCode,
        note: note,
        updatedAt: DateTime.now(),
      );

  factory Customer.fromJson(Map<String, Object?> json) => Customer(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        phone: asStringOrNull(json['phone']),
        address: asStringOrNull(json['address']),
        taxCode: asStringOrNull(json['tax_code']),
        note: asStringOrNull(json['note']),
        active: asBool(json['active'], fallback: true),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;

  /// Mã khách hàng do người dùng đặt (có thể bỏ trống).
  final String code;
  final String name;
  final String? phone;
  final String? address;
  final String? taxCode;
  final String? note;
  final bool active;
  final DateTime updatedAt;
  final bool deleted;

  /// Chuỗi dùng để tìm kiếm nhanh trong danh sách chọn khách hàng.
  String get searchText => '$code $name ${phone ?? ''}'.toLowerCase();

  String get displayName => code.isEmpty ? name : '[$code] $name';

  Map<String, Object?> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'phone': phone,
        'address': address,
        'tax_code': taxCode,
        'note': note,
        'active': active ? 1 : 0,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Customer copyWith({
    String? code,
    String? name,
    String? phone,
    String? address,
    String? taxCode,
    String? note,
    bool? active,
    bool? deleted,
  }) =>
      Customer(
        id: id,
        code: code ?? this.code,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        taxCode: taxCode ?? this.taxCode,
        note: note ?? this.note,
        active: active ?? this.active,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
