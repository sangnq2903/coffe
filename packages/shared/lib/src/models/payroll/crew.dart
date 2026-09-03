import '../../ids.dart';
import '../../json_utils.dart';

/// Trạng thái một đoàn/mùa vụ.
enum CrewStatus {
  dangDienRa('dang_dien_ra', 'Đang diễn ra'),
  daHoanThanh('da_hoan_thanh', 'Đã hoàn thành');

  const CrewStatus(this.value, this.label);

  final String value;
  final String label;

  static CrewStatus parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => CrewStatus.dangDienRa,
      );
}

/// Một **đoàn** — tương ứng một mùa vụ.
///
/// Đoàn thuộc về công ty chứ không thuộc kho nào: người trong đoàn chuyển qua
/// lại giữa các kho tuỳ thời điểm, nên kho là thuộc tính của **từng người**
/// (xem [Worker.stationCode]) chứ không của cả đoàn.
///
/// Trong đoàn có hai giai đoạn lương (đầu mùa, mùa rộ) dùng chung danh sách
/// người. Tiền chỉ quyết toán một lần vào cuối mùa; trong mùa chỉ được ứng.
class Crew {
  const Crew({
    required this.id,
    required this.name,
    this.season = '',
    this.startDate,
    this.endDate,
    this.status = CrewStatus.dangDienRa,
    this.note,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Crew.create({
    required String name,
    String season = '',
    DateTime? startDate,
    DateTime? endDate,
    String? note,
  }) =>
      Crew(
        id: newUuid(),
        name: name,
        season: season,
        startDate: startDate,
        endDate: endDate,
        note: note,
        updatedAt: DateTime.now(),
      );

  factory Crew.fromJson(Map<String, Object?> json) => Crew(
        id: asString(json['id']),
        name: asString(json['name']),
        season: asString(json['season']),
        startDate: asTimeOrNull(json['start_date']),
        endDate: asTimeOrNull(json['end_date']),
        status: CrewStatus.parse(json['status']),
        note: asStringOrNull(json['note']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;
  final String name;

  /// Nhãn niên vụ, ví dụ `2025-2026`.
  final String season;
  final DateTime? startDate;
  final DateTime? endDate;
  final CrewStatus status;
  final String? note;
  final DateTime updatedAt;
  final bool deleted;

  String get displayName => season.isEmpty ? name : '$name $season';

  bool get isOpen => status == CrewStatus.dangDienRa;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'season': season,
        'start_date': timeToMillisOrNull(startDate),
        'end_date': timeToMillisOrNull(endDate),
        'status': status.value,
        'note': note,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Crew copyWith({
    String? name,
    String? season,
    DateTime? startDate,
    DateTime? endDate,
    CrewStatus? status,
    String? note,
    bool? deleted,
  }) =>
      Crew(
        id: id,
        name: name ?? this.name,
        season: season ?? this.season,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        status: status ?? this.status,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
