import '../../ids.dart';
import '../../json_utils.dart';

/// Trạng thái làm việc của một người trong đoàn.
enum WorkerStatus {
  dangLam('dang_lam', 'Đang làm việc'),
  daNghi('da_nghi', 'Đã nghỉ làm');

  const WorkerStatus(this.value, this.label);

  final String value;
  final String label;

  static WorkerStatus parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => WorkerStatus.dangLam,
      );
}

/// Một người trong đoàn.
///
/// Người đã nghỉ không bị xoá mà chuyển trạng thái: lịch sử chấm công và công
/// nợ của họ phải giữ nguyên để còn quyết toán cuối mùa.
class Worker {
  const Worker({
    required this.id,
    required this.crewId,
    required this.name,
    this.phone,
    this.stationCode,
    this.bandId,
    this.joinDate,
    this.leaveDate,
    this.status = WorkerStatus.dangLam,
    this.note,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Worker.create({
    required String crewId,
    required String name,
    String? phone,
    String? stationCode,
    String? bandId,
    DateTime? joinDate,
    String? note,
  }) =>
      Worker(
        id: newUuid(),
        crewId: crewId,
        name: name.trim(),
        phone: phone,
        stationCode: stationCode?.toUpperCase(),
        bandId: bandId,
        joinDate: joinDate,
        note: note,
        updatedAt: DateTime.now(),
      );

  factory Worker.fromJson(Map<String, Object?> json) => Worker(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        name: asString(json['name']),
        phone: asStringOrNull(json['phone']),
        stationCode: asStringOrNull(json['station_code']),
        bandId: asStringOrNull(json['band_id']),
        joinDate: asTimeOrNull(json['join_date']),
        leaveDate: asTimeOrNull(json['leave_date']),
        status: WorkerStatus.parse(json['status']),
        note: asStringOrNull(json['note']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;
  final String crewId;
  final String name;
  final String? phone;

  /// Kho người này **đang** làm.
  ///
  /// Người trong đoàn chuyển qua lại giữa các kho, nên đây là trạng thái hiện
  /// tại chứ không phải nơi cố định. Lịch sử nằm ở từng ngày chấm công, mỗi
  /// ngày ghi kèm kho tại thời điểm đó — chuyển kho hôm nay không làm đổi số
  /// liệu tháng trước.
  final String? stationCode;

  /// Mức lương đang hưởng. Bỏ trống nghĩa là người này có giá đặt riêng.
  final String? bandId;
  final DateTime? joinDate;
  final DateTime? leaveDate;
  final WorkerStatus status;
  final String? note;
  final DateTime updatedAt;
  final bool deleted;

  bool get isWorking => status == WorkerStatus.dangLam;

  String get searchText => '$name ${phone ?? ''}'.toLowerCase();

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'name': name,
        'phone': phone,
        'station_code': stationCode,
        'band_id': bandId,
        'join_date': timeToMillisOrNull(joinDate),
        'leave_date': timeToMillisOrNull(leaveDate),
        'status': status.value,
        'note': note,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Worker copyWith({
    String? name,
    String? phone,
    String? stationCode,
    String? bandId,
    DateTime? joinDate,
    DateTime? leaveDate,
    WorkerStatus? status,
    String? note,
    bool? deleted,
  }) =>
      Worker(
        id: id,
        crewId: crewId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        stationCode: stationCode?.toUpperCase() ?? this.stationCode,
        bandId: bandId ?? this.bandId,
        joinDate: joinDate ?? this.joinDate,
        leaveDate: leaveDate ?? this.leaveDate,
        status: status ?? this.status,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
