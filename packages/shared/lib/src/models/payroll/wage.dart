import '../../ids.dart';
import '../../json_utils.dart';

/// Một **giai đoạn lương** trong mùa — đầu mùa hoặc mùa rộ.
///
/// Mốc chuyển giai đoạn khai bằng ngày, nên một tháng vắt qua hai giai đoạn vẫn
/// tính đúng: mỗi ngày chấm công tự tra xem thuộc giai đoạn nào.
///
/// Giai đoạn cũng khai **giờ làm trong ngày**: đầu mùa 7h–17h nghỉ trưa 1,5 giờ
/// là 8,5 giờ chuẩn; mùa rộ 7h–22h nghỉ trưa và tối 3 giờ là 12 giờ chuẩn. Ai
/// nghỉ vài giờ trong ngày thì công của ngày đó tính theo tỷ lệ trên giờ chuẩn.
class WagePhase {
  const WagePhase({
    required this.id,
    required this.crewId,
    required this.name,
    required this.fromDate,
    this.toDate,
    this.sortOrder = 0,
    this.workStart = defaultWorkStart,
    this.workEnd = defaultWorkEnd,
    this.breakHours = defaultBreakHours,
    required this.updatedAt,
    this.deleted = false,
  });

  factory WagePhase.create({
    required String crewId,
    required String name,
    required DateTime fromDate,
    DateTime? toDate,
    int sortOrder = 0,
    String workStart = defaultWorkStart,
    String workEnd = defaultWorkEnd,
    double breakHours = defaultBreakHours,
  }) =>
      WagePhase(
        id: newUuid(),
        crewId: crewId,
        name: name,
        fromDate: dateOnly(fromDate),
        toDate: toDate == null ? null : dateOnly(toDate),
        sortOrder: sortOrder,
        workStart: workStart,
        workEnd: workEnd,
        breakHours: breakHours,
        updatedAt: DateTime.now(),
      );

  factory WagePhase.fromJson(Map<String, Object?> json) => WagePhase(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        name: asString(json['name']),
        fromDate: asTime(json['from_date']),
        toDate: asTimeOrNull(json['to_date']),
        sortOrder: asInt(json['sort_order']),
        workStart: asString(json['work_start'], fallback: defaultWorkStart),
        workEnd: asString(json['work_end'], fallback: defaultWorkEnd),
        breakHours: asDouble(json['break_hours'], fallback: defaultBreakHours),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Giờ làm mặc định — ca đầu mùa: 7h sáng tới 5h chiều, nghỉ trưa 1,5 giờ.
  static const String defaultWorkStart = '07:00';
  static const String defaultWorkEnd = '17:00';
  static const double defaultBreakHours = 1.5;

  /// Giờ chuẩn của ca mặc định, dùng khi ngày chấm công không ghi kèm.
  static const double defaultStandardHours = 8.5;

  /// Bỏ phần giờ phút để so sánh ngày không bị lệch vì mốc thời gian.
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Đọc `HH:mm` ra số giờ, ví dụ `17:30` → 17,5. `null` nếu không đúng dạng.
  static double? parseClock(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(raw);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h + min / 60;
  }

  /// Số giờ chuẩn của một ngày: từ giờ vào tới giờ về, trừ giờ nghỉ.
  ///
  /// Đây là mẫu số khi ai đó nghỉ vài giờ trong ngày. Khai sai giờ thì chấm
  /// công vẫn chạy nhưng tiền lệch, nên phía máy chủ kiểm kỹ trước khi lưu.
  static double standardHoursOf({
    required String workStart,
    required String workEnd,
    required double breakHours,
  }) {
    final start = parseClock(workStart);
    final end = parseClock(workEnd);
    if (start == null || end == null) return defaultStandardHours;
    final hours = end - start - breakHours;
    return hours > 0 ? hours : defaultStandardHours;
  }

  final String id;
  final String crewId;
  final String name;
  final DateTime fromDate;

  /// Bỏ trống nghĩa là giai đoạn còn kéo dài, chưa chốt ngày kết thúc.
  final DateTime? toDate;
  final int sortOrder;

  /// Giờ vào ca và giờ tan ca trong ngày, dạng `HH:mm`.
  final String workStart;
  final String workEnd;

  /// Tổng giờ nghỉ giữa ca (nghỉ trưa, nghỉ tối) trong một ngày.
  final double breakHours;

  final DateTime updatedAt;
  final bool deleted;

  /// Số giờ chuẩn của một ngày công trong giai đoạn này.
  double get standardHours =>
      standardHoursOf(workStart: workStart, workEnd: workEnd, breakHours: breakHours);

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
        'work_start': workStart,
        'work_end': workEnd,
        'break_hours': breakHours,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  WagePhase copyWith({
    String? name,
    DateTime? fromDate,
    DateTime? toDate,
    int? sortOrder,
    String? workStart,
    String? workEnd,
    double? breakHours,
    bool? deleted,
  }) =>
      WagePhase(
        id: id,
        crewId: crewId,
        name: name ?? this.name,
        fromDate: fromDate == null ? this.fromDate : dateOnly(fromDate),
        toDate: toDate == null ? this.toDate : dateOnly(toDate),
        sortOrder: sortOrder ?? this.sortOrder,
        workStart: workStart ?? this.workStart,
        workEnd: workEnd ?? this.workEnd,
        breakHours: breakHours ?? this.breakHours,
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
