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

/// Một **đoàn** — tương ứng một mùa vụ tại một kho.
///
/// Mỗi mùa lập một đoàn mới với danh sách người riêng; một người chỉ thuộc một
/// đoàn. Trong đoàn có hai giai đoạn lương (đầu mùa, mùa rộ) dùng chung danh
/// sách người đó.
///
/// Tiền chỉ quyết toán một lần vào cuối mùa; trong mùa công nhân chỉ được ứng.
class Crew {
  const Crew({
    required this.id,
    required this.name,
    required this.stationCode,
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
    required String stationCode,
    String season = '',
    DateTime? startDate,
    DateTime? endDate,
    String? note,
  }) =>
      Crew(
        id: newUuid(),
        name: name,
        stationCode: stationCode.toUpperCase(),
        season: season,
        startDate: startDate,
        endDate: endDate,
        note: note,
        updatedAt: DateTime.now(),
      );

  factory Crew.fromJson(Map<String, Object?> json) => Crew(
        id: asString(json['id']),
        name: asString(json['name']),
        stationCode: asString(json['station_code']),
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

  /// Kho mà đoàn này thuộc về — quyết định ai được xem, giống phiếu cân.
  final String stationCode;

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
        'station_code': stationCode,
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
        stationCode: stationCode,
        season: season ?? this.season,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        status: status ?? this.status,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
