import '../../ids.dart';
import '../../json_utils.dart';
import 'wage.dart';

/// Một ngày chấm công của một người.
///
/// Lương tính theo tháng, còn chấm công ghi theo ngày — bản ghi này chỉ trả lời
/// "hôm đó người này có đi làm không". Không có nghỉ phép có lý do: nghỉ ngày
/// nào là mất công ngày đó.
///
/// Ngoài "có đi làm không", một ngày còn ghi **số giờ nghỉ** trong ngày. Công
/// của ngày = (giờ chuẩn − giờ nghỉ) ÷ giờ chuẩn; nghỉ 2 giờ trong ca 8,5 giờ
/// thì hưởng 6,5/8,5 ngày công.
///
/// Mỗi bản ghi **lưu kèm mức lương tháng, số ngày của tháng và giờ chuẩn tại
/// thời điểm chấm**. Nhờ vậy sửa bảng mức lương hay giờ làm hôm nay không làm
/// lương tháng trước tự nhảy — lương đã trả rồi mà con số trong máy đổi thì
/// không ai đối chiếu nổi.
class Attendance {
  const Attendance({
    required this.id,
    required this.crewId,
    required this.workerId,
    required this.date,
    this.present = true,
    this.phaseId,
    this.stationCode,
    required this.monthlyAmount,
    required this.daysInMonth,
    this.hoursOff = 0,
    this.standardHours = WagePhase.defaultStandardHours,
    this.note,
    this.createdBy,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Attendance.create({
    required String crewId,
    required String workerId,
    required DateTime date,
    required double monthlyAmount,
    String? phaseId,
    String? stationCode,
    bool present = true,
    double hoursOff = 0,
    double standardHours = WagePhase.defaultStandardHours,
    String? note,
    String? createdBy,
  }) {
    final day = WagePhase.dateOnly(date);
    return Attendance(
      id: newUuid(),
      crewId: crewId,
      workerId: workerId,
      date: day,
      present: present,
      phaseId: phaseId,
      stationCode: stationCode?.toUpperCase(),
      monthlyAmount: monthlyAmount,
      daysInMonth: daysInMonthOf(day),
      hoursOff: present ? hoursOff : 0,
      standardHours: standardHours,
      note: note,
      createdBy: createdBy,
      updatedAt: DateTime.now(),
    );
  }

  factory Attendance.fromJson(Map<String, Object?> json) => Attendance(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        workerId: asString(json['worker_id']),
        date: asTime(json['date']),
        present: asBool(json['present'], fallback: true),
        phaseId: asStringOrNull(json['phase_id']),
        stationCode: asStringOrNull(json['station_code']),
        monthlyAmount: asDouble(json['monthly_amount']),
        daysInMonth: asInt(json['days_in_month'], fallback: 30),
        hoursOff: asDouble(json['hours_off']),
        standardHours: asDouble(json['standard_hours'],
            fallback: WagePhase.defaultStandardHours),
        note: asStringOrNull(json['note']),
        createdBy: asStringOrNull(json['created_by']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Số ngày của tháng chứa [date] — 28, 29, 30 hoặc 31.
  ///
  /// Đây là mẫu số quy lương tháng ra từng ngày, theo đúng luật đã chốt: ngày
  /// công của tháng bằng số ngày của tháng, kể cả chủ nhật.
  static int daysInMonthOf(DateTime date) =>
      DateTime(date.year, date.month + 1, 0).day;

  final String id;
  final String crewId;
  final String workerId;
  final DateTime date;

  /// Có đi làm hay không. Ghi cả ngày nghỉ để phân biệt với ngày chưa chấm.
  final bool present;

  /// Giai đoạn lương của ngày đó, giữ lại để tra cứu và đối chiếu.
  final String? phaseId;

  /// Kho người đó làm việc **trong ngày này**.
  ///
  /// Chép lại từ kho hiện tại của người đó lúc chấm công. Nhờ vậy chuyển kho
  /// hôm nay không làm đổi số liệu tháng trước, và sau này cộng ra được tiền
  /// công mà từng kho phải gánh.
  final String? stationCode;

  /// Lương tháng áp dụng tại thời điểm chấm (đồng).
  final double monthlyAmount;

  /// Số ngày của tháng tại thời điểm chấm.
  final int daysInMonth;

  /// Số giờ nghỉ trong ngày (đi trễ, về sớm, ra ngoài). Nghỉ cả ngày thì
  /// dùng [present] chứ không ghi ở đây.
  final double hoursOff;

  /// Giờ chuẩn của một ngày công tại thời điểm chấm — mẫu số cho [hoursOff].
  final double standardHours;

  final String? note;
  final String? createdBy;
  final DateTime updatedAt;
  final bool deleted;

  /// Khoá gộp theo tháng, dạng `2026-09`.
  String get monthKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// Số giờ làm thực trong ngày.
  double get hoursWorked {
    if (!present) return 0;
    final left = standardHours - hoursOff;
    return left < 0 ? 0 : left;
  }

  /// Phần công của ngày: 1 là đủ ngày, 0 là nghỉ, ở giữa là nghỉ vài giờ.
  double get workUnit {
    if (!present || standardHours <= 0) return 0;
    final unit = hoursWorked / standardHours;
    return unit > 1 ? 1 : unit;
  }

  /// Đủ ngày, không nghỉ giờ nào.
  bool get isFullDay => present && hoursOff <= 0;

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'worker_id': workerId,
        'date': timeToMillis(date),
        'present': present ? 1 : 0,
        'phase_id': phaseId,
        'station_code': stationCode,
        'monthly_amount': monthlyAmount,
        'days_in_month': daysInMonth,
        'hours_off': hoursOff,
        'standard_hours': standardHours,
        'note': note,
        'created_by': createdBy,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Attendance copyWith({
    bool? present,
    String? phaseId,
    String? stationCode,
    double? monthlyAmount,
    double? hoursOff,
    double? standardHours,
    String? note,
    bool? deleted,
  }) {
    final nowPresent = present ?? this.present;
    return Attendance(
        id: id,
        crewId: crewId,
        workerId: workerId,
        date: date,
        present: nowPresent,
        phaseId: phaseId ?? this.phaseId,
        stationCode: stationCode?.toUpperCase() ?? this.stationCode,
        monthlyAmount: monthlyAmount ?? this.monthlyAmount,
        daysInMonth: daysInMonth,
        // Đổi thành nghỉ cả ngày thì số giờ nghỉ cũ không còn nghĩa.
        hoursOff: nowPresent ? (hoursOff ?? this.hoursOff) : 0,
        standardHours: standardHours ?? this.standardHours,
        note: note ?? this.note,
        createdBy: createdBy,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
  }
}
