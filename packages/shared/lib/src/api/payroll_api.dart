import '../json_utils.dart';
import '../models/payroll/crew.dart';
import '../models/payroll/wage.dart';
import '../models/payroll/worker.dart';
import 'api_client.dart';

/// Bảng lương của một đoàn, dựng sẵn cho màn hình cấu hình.
class WageTable {
  const WageTable({
    this.phases = const [],
    this.bands = const [],
    this.rates = const [],
    this.missing = const [],
  });

  factory WageTable.fromJson(Map<String, Object?> json) => WageTable(
        phases: asMapList(json['phases']).map(WagePhase.fromJson).toList(),
        bands: asMapList(json['bands']).map(WageBand.fromJson).toList(),
        rates: asMapList(json['rates']).map(WageRate.fromJson).toList(),
        missing: asMapList(json['missing'])
            .map((e) => MissingRate(
                  bandId: asString(e['band_id']),
                  bandName: asString(e['band_name']),
                  phaseId: asString(e['phase_id']),
                  phaseName: asString(e['phase_name']),
                ))
            .toList(),
      );

  final List<WagePhase> phases;
  final List<WageBand> bands;
  final List<WageRate> rates;

  /// Những ô chưa khai giá — phải chỉ ra được, chứ để trống thì tới lúc chấm
  /// công mới phát hiện là không tra ra lương.
  final List<MissingRate> missing;

  /// Giá của một ô trong bảng, `null` nếu chưa khai.
  double? amountFor(String bandId, String phaseId) {
    for (final rate in rates) {
      if (rate.bandId == bandId && rate.phaseId == phaseId) return rate.monthlyAmount;
    }
    return null;
  }

  bool get isComplete => missing.isEmpty && phases.isNotEmpty && bands.isNotEmpty;
}

/// Một ô trống trong bảng lương.
class MissingRate {
  const MissingRate({
    required this.bandId,
    required this.bandName,
    required this.phaseId,
    required this.phaseName,
  });

  final String bandId;
  final String bandName;
  final String phaseId;
  final String phaseName;
}

/// Các lời gọi API của module chấm công.
extension PayrollApi on ApiClient {
  // ------------------------------------------------------------------- đoàn

  Future<List<Crew>> crews({bool includeClosed = true}) async =>
      (await getList('/api/doan', {if (!includeClosed) 'all': '0'}))
          .map(Crew.fromJson)
          .toList();

  Future<Crew> crew(String id) async =>
      Crew.fromJson(await getMap('/api/doan/$id'));

  Future<Crew> saveCrew({
    String? id,
    required String name,
    String season = '',
    DateTime? startDate,
    DateTime? endDate,
    String? note,
  }) async =>
      Crew.fromJson(await postMap(id == null ? '/api/doan' : '/api/doan/$id', {
        'name': name,
        'season': season,
        'start_date': timeToMillisOrNull(startDate),
        'end_date': timeToMillisOrNull(endDate),
        'note': note,
      }));

  Future<Crew> closeCrew(String id) async => Crew.fromJson(
      await postMap('/api/doan/$id', {'status': CrewStatus.daHoanThanh.value}));

  Future<void> deleteCrew(String id) => deletePath('/api/doan/$id');

  // ------------------------------------------------------------ bảng lương

  Future<WageTable> wageTable(String crewId) async =>
      WageTable.fromJson(await getMap('/api/doan/$crewId/bang-luong'));

  Future<WagePhase> savePhase({
    required String crewId,
    String? id,
    required String name,
    required DateTime fromDate,
    DateTime? toDate,
    int sortOrder = 0,
  }) async =>
      WagePhase.fromJson(await postMap('/api/doan/$crewId/giai-doan', {
        if (id != null) 'id': id,
        'name': name,
        'from_date': timeToMillis(fromDate),
        'to_date': timeToMillisOrNull(toDate),
        'sort_order': sortOrder,
      }));

  Future<void> deletePhase(String crewId, String phaseId) =>
      deletePath('/api/doan/$crewId/giai-doan/$phaseId');

  Future<WageBand> saveBand({
    required String crewId,
    String? id,
    required String name,
    int sortOrder = 0,
  }) async =>
      WageBand.fromJson(await postMap('/api/doan/$crewId/muc-luong', {
        if (id != null) 'id': id,
        'name': name,
        'sort_order': sortOrder,
      }));

  Future<void> deleteBand(String crewId, String bandId) =>
      deletePath('/api/doan/$crewId/muc-luong/$bandId');

  Future<WageRate> saveRate({
    required String crewId,
    required String phaseId,
    String? bandId,
    String? workerId,
    required double monthlyAmount,
  }) async =>
      WageRate.fromJson(await postMap('/api/doan/$crewId/gia-luong', {
        'phase_id': phaseId,
        if (bandId != null) 'band_id': bandId,
        if (workerId != null) 'worker_id': workerId,
        'monthly_amount': monthlyAmount,
      }));

  // -------------------------------------------------------------- nhân viên

  Future<List<Worker>> workers(String crewId,
          {WorkerStatus? status, String? query, String? stationCode}) async =>
      (await getList('/api/doan/$crewId/nhan-vien', {
        if (status != null) 'status': status.value,
        if (query != null && query.isNotEmpty) 'q': query,
        if (stationCode != null && stationCode.isNotEmpty) 'kho': stationCode,
      }))
          .map(Worker.fromJson)
          .toList();

  Future<Worker> saveWorker({
    required String crewId,
    String? id,
    required String name,
    String? phone,
    String? stationCode,
    String? bandId,
    DateTime? joinDate,
    String? note,
  }) async =>
      Worker.fromJson(await postMap('/api/doan/$crewId/nhan-vien', {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'station_code': stationCode,
        'band_id': bandId,
        'join_date': timeToMillisOrNull(joinDate),
        'note': note,
      }));

  /// Chuyển người sang kho khác, có hiệu lực từ bây giờ.
  ///
  /// Những ngày đã chấm công vẫn giữ kho ghi lúc đó, nên chuyển qua chuyển lại
  /// bao nhiêu lần cũng không làm sai số liệu tháng trước.
  Future<List<Worker>> transferWorkers({
    required String crewId,
    required List<String> workerIds,
    required String stationCode,
  }) async =>
      (await postList('/api/doan/$crewId/chuyen-kho', {
        'worker_ids': workerIds,
        'station_code': stationCode,
      }))
          .map(Worker.fromJson)
          .toList();

  Future<Worker> stopWorker(String workerId, {DateTime? leaveDate}) async =>
      Worker.fromJson(await postMap('/api/nhan-vien/$workerId/nghi-lam', {
        'leave_date': timeToMillisOrNull(leaveDate),
      }));

  Future<Worker> resumeWorker(String workerId) async =>
      Worker.fromJson(await postMap('/api/nhan-vien/$workerId/lam-lai', const {}));
}
