import '../ids.dart';
import '../json_utils.dart';

/// Chiều hàng: nhập kho (mua vào) hay xuất kho (bán ra).
enum WeighDirection {
  nhap('nhap', 'Nhập kho'),
  xuat('xuat', 'Xuất kho');

  const WeighDirection(this.value, this.label);

  final String value;
  final String label;

  static WeighDirection parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => WeighDirection.nhap,
      );
}

/// Trạng thái phiếu cân.
enum TicketStatus {
  choLan2('cho_lan_2', 'Chờ cân lần 2'),
  hoanThanh('hoan_thanh', 'Hoàn thành'),
  huy('huy', 'Đã huỷ');

  const TicketStatus(this.value, this.label);

  final String value;
  final String label;

  static TicketStatus parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => TicketStatus.choLan2,
      );
}

/// Phiếu cân xe — bản ghi trung tâm của tính năng.
///
/// Tên khách hàng / biển số / tên loại hàng được lưu kèm dạng "snapshot" ngay
/// trên phiếu: phiếu đã in phải giữ nguyên nội dung kể cả khi danh mục bị sửa
/// hoặc xoá sau đó.
class WeighTicket {
  const WeighTicket({
    required this.id,
    required this.ticketNo,
    required this.stationCode,
    required this.direction,
    required this.status,
    this.customerId,
    required this.customerName,
    this.vehicleId,
    required this.plateNo,
    this.driverName,
    this.goodsTypeId,
    required this.goodsName,
    required this.yieldRatio,
    this.firstWeight,
    this.firstWeightAt,
    this.secondWeight,
    this.secondWeightAt,
    this.note,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WeighTicket.create({
    required String ticketNo,
    required String stationCode,
    WeighDirection direction = WeighDirection.nhap,
    String? customerId,
    String customerName = '',
    String? vehicleId,
    String plateNo = '',
    String? driverName,
    String? goodsTypeId,
    String goodsName = '',
    double yieldRatio = 100,
    double? firstWeight,
    DateTime? firstWeightAt,
    String? note,
    String? createdBy,
  }) {
    final now = DateTime.now();
    return WeighTicket(
      id: newUuid(),
      ticketNo: ticketNo,
      stationCode: stationCode,
      direction: direction,
      status: TicketStatus.choLan2,
      customerId: customerId,
      customerName: customerName,
      vehicleId: vehicleId,
      plateNo: plateNo,
      driverName: driverName,
      goodsTypeId: goodsTypeId,
      goodsName: goodsName,
      yieldRatio: yieldRatio,
      firstWeight: firstWeight,
      firstWeightAt: firstWeight == null ? null : (firstWeightAt ?? now),
      note: note,
      createdBy: createdBy,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory WeighTicket.fromJson(Map<String, Object?> json) => WeighTicket(
        id: asString(json['id']),
        ticketNo: asString(json['ticket_no']),
        stationCode: asString(json['station_code']),
        direction: WeighDirection.parse(json['direction']),
        status: TicketStatus.parse(json['status']),
        customerId: asStringOrNull(json['customer_id']),
        customerName: asString(json['customer_name']),
        vehicleId: asStringOrNull(json['vehicle_id']),
        plateNo: asString(json['plate_no']),
        driverName: asStringOrNull(json['driver_name']),
        goodsTypeId: asStringOrNull(json['goods_type_id']),
        goodsName: asString(json['goods_name']),
        yieldRatio: asDouble(json['yield_ratio'], fallback: 100),
        firstWeight: asDoubleOrNull(json['first_weight']),
        firstWeightAt: asTimeOrNull(json['first_weight_at']),
        secondWeight: asDoubleOrNull(json['second_weight']),
        secondWeightAt: asTimeOrNull(json['second_weight_at']),
        note: asStringOrNull(json['note']),
        createdBy: asStringOrNull(json['created_by']),
        createdAt: asTime(json['created_at']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;

  /// Số phiếu hiển thị cho người dùng, dạng `KHO01-260903-0007`.
  final String ticketNo;

  /// Trạm cân đã lập phiếu — dùng để tách dữ liệu theo kho trên máy chủ.
  final String stationCode;
  final WeighDirection direction;
  final TicketStatus status;

  final String? customerId;
  final String customerName;

  final String? vehicleId;
  final String plateNo;
  final String? driverName;

  final String? goodsTypeId;
  final String goodsName;

  /// Tỷ lệ thành phẩm (%).
  final double yieldRatio;

  /// Cân lần 1 (kg).
  final double? firstWeight;
  final DateTime? firstWeightAt;

  /// Cân lần 2 (kg).
  final double? secondWeight;
  final DateTime? secondWeightAt;

  final String? note;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  /// KL hàng (kg) = chênh lệch giữa hai lần cân.
  ///
  /// Lấy trị tuyệt đối để đúng cho cả nhập (lần 1 nặng hơn) lẫn xuất (lần 2
  /// nặng hơn), không phụ thuộc thứ tự vào/ra trạm của xe.
  double get netWeight {
    final a = firstWeight;
    final b = secondWeight;
    if (a == null || b == null) return 0;
    return (a - b).abs();
  }

  /// KL thành phẩm quy đổi (kg) = KL hàng × tỷ lệ thành phẩm.
  double get productWeight => netWeight * yieldRatio / 100;

  /// KL tổng (xe + hàng) và KL bì (xe không) suy ra từ hai lần cân.
  double? get grossWeight => _minMax(max: true);

  double? get tareWeight => _minMax(max: false);

  double? _minMax({required bool max}) {
    final a = firstWeight;
    final b = secondWeight;
    if (a == null || b == null) return null;
    return max ? (a > b ? a : b) : (a < b ? a : b);
  }

  bool get isComplete => status == TicketStatus.hoanThanh;

  bool get waitingSecondWeigh => status == TicketStatus.choLan2;

  Map<String, Object?> toJson() => {
        'id': id,
        'ticket_no': ticketNo,
        'station_code': stationCode,
        'direction': direction.value,
        'status': status.value,
        'customer_id': customerId,
        'customer_name': customerName,
        'vehicle_id': vehicleId,
        'plate_no': plateNo,
        'driver_name': driverName,
        'goods_type_id': goodsTypeId,
        'goods_name': goodsName,
        'yield_ratio': yieldRatio,
        'first_weight': firstWeight,
        'first_weight_at': timeToMillisOrNull(firstWeightAt),
        'second_weight': secondWeight,
        'second_weight_at': timeToMillisOrNull(secondWeightAt),
        'net_weight': netWeight,
        'product_weight': productWeight,
        'note': note,
        'created_by': createdBy,
        'created_at': timeToMillis(createdAt),
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  WeighTicket copyWith({
    String? ticketNo,
    WeighDirection? direction,
    TicketStatus? status,
    String? customerId,
    String? customerName,
    String? vehicleId,
    String? plateNo,
    String? driverName,
    String? goodsTypeId,
    String? goodsName,
    double? yieldRatio,
    double? firstWeight,
    DateTime? firstWeightAt,
    double? secondWeight,
    DateTime? secondWeightAt,
    String? note,
    String? createdBy,
    bool? deleted,
    DateTime? updatedAt,
  }) =>
      WeighTicket(
        id: id,
        ticketNo: ticketNo ?? this.ticketNo,
        stationCode: stationCode,
        direction: direction ?? this.direction,
        status: status ?? this.status,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        vehicleId: vehicleId ?? this.vehicleId,
        plateNo: plateNo ?? this.plateNo,
        driverName: driverName ?? this.driverName,
        goodsTypeId: goodsTypeId ?? this.goodsTypeId,
        goodsName: goodsName ?? this.goodsName,
        yieldRatio: yieldRatio ?? this.yieldRatio,
        firstWeight: firstWeight ?? this.firstWeight,
        firstWeightAt: firstWeightAt ?? this.firstWeightAt,
        secondWeight: secondWeight ?? this.secondWeight,
        secondWeightAt: secondWeightAt ?? this.secondWeightAt,
        note: note ?? this.note,
        createdBy: createdBy ?? this.createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
