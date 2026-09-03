import '../../ids.dart';
import '../../json_utils.dart';

/// Một **giai đoạn lương** trong mùa — đầu mùa hoặc mùa rộ.
///
/// Mốc chuyển giai đoạn khai bằng ngày, nên một tháng vắt qua hai giai đoạn vẫn
/// tính đúng: mỗi ngày chấm công tự tra xem thuộc giai đoạn nào.
class WagePhase {
  const WagePhase({
    required this.id,
    required this.crewId,
    required this.name,
    required this.fromDate,
    this.toDate,
    this.sortOrder = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WagePhase.create({
    required String crewId,
    required String name,
    required DateTime fromDate,
    DateTime? toDate,
    int sortOrder = 0,
  }) =>
      WagePhase(
        id: newUuid(),
        crewId: crewId,
        name: name,
        fromDate: dateOnly(fromDate),
        toDate: toDate == null ? null : dateOnly(toDate),
        sortOrder: sortOrder,
        updatedAt: DateTime.now(),
      );

  factory WagePhase.fromJson(Map<String, Object?> json) => WagePhase(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        name: asString(json['name']),
        fromDate: asTime(json['from_date']),
        toDate: asTimeOrNull(json['to_date']),
        sortOrder: asInt(json['sort_order']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Bỏ phần giờ phút để so sánh ngày không bị lệch vì mốc thời gian.
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  final String id;
  final String crewId;
  final String name;
  final DateTime fromDate;

  /// Bỏ trống nghĩa là giai đoạn còn kéo dài, chưa chốt ngày kết thúc.
  final DateTime? toDate;
  final int sortOrder;
  final DateTime updatedAt;
  final bool deleted;

  bool contains(DateTime date) {
    final day = dateOnly(date);
    if (day.isBefore(fromDate)) return false;
    final end = toDate;
    return end == null || !day.isAfter(end);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'name': name,
        'from_date': timeToMillis(fromDate),
        'to_date': timeToMillisOrNull(toDate),
        'sort_order': sortOrder,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  WagePhase copyWith({
    String? name,
    DateTime? fromDate,
    DateTime? toDate,
    int? sortOrder,
    bool? deleted,
  }) =>
      WagePhase(
        id: id,
        crewId: crewId,
        name: name ?? this.name,
        fromDate: fromDate == null ? this.fromDate : dateOnly(fromDate),
        toDate: toDate == null ? this.toDate : dateOnly(toDate),
        sortOrder: sortOrder ?? this.sortOrder,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}

/// Một **mức lương** dùng chung, ví dụ "Thợ chính", "Thợ phụ".
///
/// Nhiều người hưởng cùng một mức. Khi mùa rộ đổi giá, sửa một dòng là cả nhóm
/// cập nhật theo — thay vì sửa tay từng người rồi sót một người là lương sai.
class WageBand {
  const WageBand({
    required this.id,
    required this.crewId,
    required this.name,
    this.sortOrder = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WageBand.create({
    required String crewId,
    required String name,
    int sortOrder = 0,
  }) =>
      WageBand(
        id: newUuid(),
        crewId: crewId,
        name: name,
        sortOrder: sortOrder,
        updatedAt: DateTime.now(),
      );

  factory WageBand.fromJson(Map<String, Object?> json) => WageBand(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        name: asString(json['name']),
        sortOrder: asInt(json['sort_order']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;
  final String crewId;
  final String name;
  final int sortOrder;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'name': name,
        'sort_order': sortOrder,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  WageBand copyWith({String? name, int? sortOrder, bool? deleted}) => WageBand(
        id: id,
        crewId: crewId,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}

/// Tiền lương **một tháng** của một mức lương trong một giai đoạn.
///
/// Đặt riêng cho một người thì [workerId] có giá trị và [bandId] để trống —
/// người đó không bị ảnh hưởng khi sửa bảng mức chung.
class WageRate {
  const WageRate({
    required this.id,
    required this.crewId,
    required this.phaseId,
    this.bandId,
    this.workerId,
    required this.monthlyAmount,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WageRate.forBand({
    required String crewId,
    required String phaseId,
    required String bandId,
    required double monthlyAmount,
  }) =>
      WageRate(
        id: newUuid(),
        crewId: crewId,
        phaseId: phaseId,
        bandId: bandId,
        monthlyAmount: monthlyAmount,
        updatedAt: DateTime.now(),
      );

  factory WageRate.forWorker({
    required String crewId,
    required String phaseId,
    required String workerId,
    required double monthlyAmount,
  }) =>
      WageRate(
        id: newUuid(),
        crewId: crewId,
        phaseId: phaseId,
        workerId: workerId,
        monthlyAmount: monthlyAmount,
        updatedAt: DateTime.now(),
      );

  factory WageRate.fromJson(Map<String, Object?> json) => WageRate(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        phaseId: asString(json['phase_id']),
        bandId: asStringOrNull(json['band_id']),
        workerId: asStringOrNull(json['worker_id']),
        monthlyAmount: asDouble(json['monthly_amount']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;
  final String crewId;
  final String phaseId;

  /// Giá của một mức lương dùng chung.
  final String? bandId;

  /// Giá đặt riêng cho một người, đè lên mức chung.
  final String? workerId;

  /// Tiền lương một tháng (đồng).
  final double monthlyAmount;
  final DateTime updatedAt;
  final bool deleted;

  bool get isOverride => workerId != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'phase_id': phaseId,
        'band_id': bandId,
        'worker_id': workerId,
        'monthly_amount': monthlyAmount,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  WageRate copyWith({double? monthlyAmount, bool? deleted}) => WageRate(
        id: id,
        crewId: crewId,
        phaseId: phaseId,
        bandId: bandId,
        workerId: workerId,
        monthlyAmount: monthlyAmount ?? this.monthlyAmount,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
