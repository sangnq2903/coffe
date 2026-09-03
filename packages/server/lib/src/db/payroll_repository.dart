import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Truy cập dữ liệu của module chấm công.
///
/// Tách khỏi [Repository] của phần cân xe cho mỗi file một việc — hai phần dùng
/// chung cơ sở dữ liệu nhưng nghiệp vụ không dính nhau.
class PayrollRepository {
  PayrollRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  /// Các bảng của module này, dùng cho đồng bộ và đếm bản ghi chờ đẩy.
  static const List<String> tables = [
    'doan',
    'giai_doan_luong',
    'muc_luong',
    'gia_luong',
    'nhan_vien',
    'cham_cong',
    'so_tien',
  ];

  // ==================================================================== đoàn

  /// Danh sách đoàn.
  ///
  /// Không giới hạn theo kho: đoàn thuộc về công ty, người trong đoàn chuyển
  /// qua lại giữa các kho nên không có chuyện "đoàn của kho nào".
  List<Crew> crews({bool includeClosed = true}) {
    final where = includeClosed ? 'deleted = 0' : "deleted = 0 AND status = 'dang_dien_ra'";
    return _db
        .select('SELECT * FROM doan WHERE $where ORDER BY season DESC, name')
        .map((r) => Crew.fromJson(r))
        .toList();
  }

  Crew? crewById(String id) => _one('doan', id, Crew.fromJson);

  Crew upsertCrew(Crew crew, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO doan (id, name, station_code, season, start_date, end_date, status, note,
        updated_at, deleted, dirty)
      -- Cột station_code giữ lại cho dữ liệu cũ đọc được (nó NOT NULL) nhưng
      -- không còn ý nghĩa: kho giờ là thuộc tính của từng người trong đoàn.
      VALUES (?, ?, '', ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        season = excluded.season, start_date = excluded.start_date,
        end_date = excluded.end_date, status = excluded.status, note = excluded.note,
        updated_at = excluded.updated_at, deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= doan.updated_at
    ''', [
      crew.id,
      crew.name,
      crew.season,
      timeToMillisOrNull(crew.startDate),
      timeToMillisOrNull(crew.endDate),
      crew.status.value,
      crew.note,
      timeToMillis(crew.updatedAt),
      crew.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return crewById(crew.id) ?? crew;
  }

  // ======================================================== giai đoạn lương

  List<WagePhase> phases(String crewId) => _db
      .select(
        'SELECT * FROM giai_doan_luong WHERE crew_id = ? AND deleted = 0 '
        'ORDER BY sort_order, from_date',
        [crewId],
      )
      .map((r) => WagePhase.fromJson(r))
      .toList();

  WagePhase? phaseById(String id) => _one('giai_doan_luong', id, WagePhase.fromJson);

  WagePhase upsertPhase(WagePhase phase, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO giai_doan_luong (id, crew_id, name, from_date, to_date, sort_order,
        updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name, from_date = excluded.from_date, to_date = excluded.to_date,
        sort_order = excluded.sort_order, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= giai_doan_luong.updated_at
    ''', [
      phase.id,
      phase.crewId,
      phase.name,
      timeToMillis(phase.fromDate),
      timeToMillisOrNull(phase.toDate),
      phase.sortOrder,
      timeToMillis(phase.updatedAt),
      phase.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return phaseById(phase.id) ?? phase;
  }

  /// Giai đoạn chứa một ngày cụ thể.
  WagePhase? phaseForDate(String crewId, DateTime date) {
    for (final phase in phases(crewId)) {
      if (phase.contains(date)) return phase;
    }
    return null;
  }

  // ============================================================= mức lương

  List<WageBand> bands(String crewId) => _db
      .select(
        'SELECT * FROM muc_luong WHERE crew_id = ? AND deleted = 0 ORDER BY sort_order, name',
        [crewId],
      )
      .map((r) => WageBand.fromJson(r))
      .toList();

  WageBand? bandById(String id) => _one('muc_luong', id, WageBand.fromJson);

  WageBand upsertBand(WageBand band, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO muc_luong (id, crew_id, name, sort_order, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name, sort_order = excluded.sort_order,
        updated_at = excluded.updated_at, deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= muc_luong.updated_at
    ''', [
      band.id,
      band.crewId,
      band.name,
      band.sortOrder,
      timeToMillis(band.updatedAt),
      band.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return bandById(band.id) ?? band;
  }

  // ============================================================= giá lương

  List<WageRate> rates(String crewId) => _db
      .select('SELECT * FROM gia_luong WHERE crew_id = ? AND deleted = 0', [crewId])
      .map((r) => WageRate.fromJson(r))
      .toList();

  WageRate? rateById(String id) => _one('gia_luong', id, WageRate.fromJson);

  WageRate upsertRate(WageRate rate, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO gia_luong (id, crew_id, phase_id, band_id, worker_id, monthly_amount,
        updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        phase_id = excluded.phase_id, band_id = excluded.band_id,
        worker_id = excluded.worker_id, monthly_amount = excluded.monthly_amount,
        updated_at = excluded.updated_at, deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= gia_luong.updated_at
    ''', [
      rate.id,
      rate.crewId,
      rate.phaseId,
      rate.bandId,
      rate.workerId,
      rate.monthlyAmount,
      timeToMillis(rate.updatedAt),
      rate.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return rateById(rate.id) ?? rate;
  }

  /// Lương tháng áp dụng cho một người trong một giai đoạn.
  ///
  /// Giá đặt riêng cho người đó luôn thắng giá của mức chung — đó chính là ý
  /// nghĩa của "đặt riêng": sửa bảng mức chung không đụng tới người này.
  double? monthlyAmountFor({
    required String crewId,
    required String phaseId,
    required Worker worker,
  }) {
    final rows = _db.select(
      'SELECT * FROM gia_luong WHERE crew_id = ? AND phase_id = ? AND worker_id = ? '
      'AND deleted = 0 LIMIT 1',
      [crewId, phaseId, worker.id],
    );
    if (rows.isNotEmpty) return WageRate.fromJson(rows.first).monthlyAmount;

    final bandId = worker.bandId;
    if (bandId == null) return null;
    final byBand = _db.select(
      'SELECT * FROM gia_luong WHERE crew_id = ? AND phase_id = ? AND band_id = ? '
      'AND deleted = 0 LIMIT 1',
      [crewId, phaseId, bandId],
    );
    return byBand.isEmpty ? null : WageRate.fromJson(byBand.first).monthlyAmount;
  }

  // ============================================================== nhân viên

  List<Worker> workers(
    String crewId, {
    WorkerStatus? status,
    String? query,
    String? stationCode,
  }) {
    final where = <String>['crew_id = ?', 'deleted = 0'];
    final args = <Object?>[crewId];
    if (status != null) {
      where.add('status = ?');
      args.add(status.value);
    }
    if (stationCode != null && stationCode.isNotEmpty) {
      where.add('station_code = ?');
      args.add(stationCode.toUpperCase());
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(lower(name) LIKE ?1 OR lower(ifnull(phone, "")) LIKE ?1)');
      args.add('%${query.trim().toLowerCase()}%');
    }
    return _db
        .select(
          'SELECT * FROM nhan_vien WHERE ${where.join(" AND ")} ORDER BY name COLLATE NOCASE',
          args,
        )
        .map((r) => Worker.fromJson(r))
        .toList();
  }

  Worker? workerById(String id) => _one('nhan_vien', id, Worker.fromJson);

  Worker upsertWorker(Worker worker, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO nhan_vien (id, crew_id, name, phone, station_code, band_id, join_date,
        leave_date, status, note, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name, phone = excluded.phone,
        station_code = excluded.station_code, band_id = excluded.band_id,
        join_date = excluded.join_date, leave_date = excluded.leave_date,
        status = excluded.status, note = excluded.note, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= nhan_vien.updated_at
    ''', [
      worker.id,
      worker.crewId,
      worker.name,
      worker.phone,
      worker.stationCode,
      worker.bandId,
      timeToMillisOrNull(worker.joinDate),
      timeToMillisOrNull(worker.leaveDate),
      worker.status.value,
      worker.note,
      timeToMillis(worker.updatedAt),
      worker.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return workerById(worker.id) ?? worker;
  }

  // =============================================================== chấm công

  List<Attendance> attendances({
    String? crewId,
    String? workerId,
    DateTime? from,
    DateTime? to,
  }) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (crewId != null) {
      where.add('crew_id = ?');
      args.add(crewId);
    }
    if (workerId != null) {
      where.add('worker_id = ?');
      args.add(workerId);
    }
    if (from != null) {
      where.add('date >= ?');
      args.add(timeToMillis(WagePhase.dateOnly(from)));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(timeToMillis(WagePhase.dateOnly(to)));
    }
    return _db
        .select('SELECT * FROM cham_cong WHERE ${where.join(" AND ")} ORDER BY date', args)
        .map((r) => Attendance.fromJson(r))
        .toList();
  }

  Attendance? attendanceById(String id) => _one('cham_cong', id, Attendance.fromJson);

  /// Bản ghi chấm công của một người trong một ngày, nếu đã có.
  Attendance? attendanceOn(String workerId, DateTime date) {
    final rows = _db.select(
      'SELECT * FROM cham_cong WHERE worker_id = ? AND date = ? AND deleted = 0 LIMIT 1',
      [workerId, timeToMillis(WagePhase.dateOnly(date))],
    );
    return rows.isEmpty ? null : Attendance.fromJson(rows.first);
  }

  Attendance upsertAttendance(Attendance record, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO cham_cong (id, crew_id, worker_id, date, present, phase_id, station_code,
        monthly_amount, days_in_month, note, created_by, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        present = excluded.present, phase_id = excluded.phase_id,
        station_code = excluded.station_code,
        monthly_amount = excluded.monthly_amount, days_in_month = excluded.days_in_month,
        note = excluded.note, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= cham_cong.updated_at
    ''', [
      record.id,
      record.crewId,
      record.workerId,
      timeToMillis(record.date),
      record.present ? 1 : 0,
      record.phaseId,
      record.stationCode,
      record.monthlyAmount,
      record.daysInMonth,
      record.note,
      record.createdBy,
      timeToMillis(record.updatedAt),
      record.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return attendanceById(record.id) ?? record;
  }

  // ================================================================ sổ tiền

  List<PayrollEntry> entries({
    String? crewId,
    String? workerId,
    PayrollEntryType? type,
    DateTime? from,
    DateTime? to,
  }) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (crewId != null) {
      where.add('crew_id = ?');
      args.add(crewId);
    }
    if (workerId != null) {
      where.add('worker_id = ?');
      args.add(workerId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.value);
    }
    if (from != null) {
      where.add('date >= ?');
      args.add(timeToMillis(from));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(timeToMillis(to));
    }
    return _db
        .select('SELECT * FROM so_tien WHERE ${where.join(" AND ")} ORDER BY date DESC', args)
        .map((r) => PayrollEntry.fromJson(r))
        .toList();
  }

  PayrollEntry? entryById(String id) => _one('so_tien', id, PayrollEntry.fromJson);

  PayrollEntry upsertEntry(PayrollEntry entry, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO so_tien (id, crew_id, worker_id, type, amount, date, note,
        over_cap_reason, created_by, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        type = excluded.type, amount = excluded.amount, date = excluded.date,
        note = excluded.note, over_cap_reason = excluded.over_cap_reason,
        updated_at = excluded.updated_at, deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= so_tien.updated_at
    ''', [
      entry.id,
      entry.crewId,
      entry.workerId,
      entry.type.value,
      entry.amount,
      timeToMillis(entry.date),
      entry.note,
      entry.overCapReason,
      entry.createdBy,
      timeToMillis(entry.updatedAt),
      entry.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return entryById(entry.id) ?? entry;
  }

  // ================================================================ đồng bộ

  /// Lấy thay đổi sau mốc [since].
  ///
  /// Không giới hạn theo kho. Đoàn thuộc về công ty và người chuyển kho qua
  /// lại, nên không cắt được dữ liệu chấm công theo kho — nghĩa là máy trạm nào
  /// cũng giữ bản sao dữ liệu lương của cả công ty. Đây là đánh đổi có chủ ý:
  /// bảng lương của một người phải cộng được xuyên kho.
  PayrollSyncData changesSince(DateTime? since, {int limit = 500}) {
    final ms = timeToMillis(since ?? DateTime.fromMillisecondsSinceEpoch(0));

    List<T> load<T>(String table, T Function(Map<String, Object?>) parse) => _db
        .select(
          'SELECT * FROM $table WHERE updated_at > ? ORDER BY updated_at LIMIT ?',
          [ms, limit],
        )
        .map((r) => parse(r))
        .toList();

    return PayrollSyncData(
      crews: load('doan', Crew.fromJson),
      phases: load('giai_doan_luong', WagePhase.fromJson),
      bands: load('muc_luong', WageBand.fromJson),
      rates: load('gia_luong', WageRate.fromJson),
      workers: load('nhan_vien', Worker.fromJson),
      attendances: load('cham_cong', Attendance.fromJson),
      entries: load('so_tien', PayrollEntry.fromJson),
    );
  }

  /// Bản ghi do máy này tạo/sửa mà chưa đẩy lên trung tâm.
  PayrollSyncData dirtyChanges({int limit = 300}) {
    List<T> load<T>(String table, T Function(Map<String, Object?>) parse) => _db
        .select('SELECT * FROM $table WHERE dirty = 1 ORDER BY updated_at LIMIT ?', [limit])
        .map((r) => parse(r))
        .toList();

    return PayrollSyncData(
      crews: load('doan', Crew.fromJson),
      phases: load('giai_doan_luong', WagePhase.fromJson),
      bands: load('muc_luong', WageBand.fromJson),
      rates: load('gia_luong', WageRate.fromJson),
      workers: load('nhan_vien', Worker.fromJson),
      attendances: load('cham_cong', Attendance.fromJson),
      entries: load('so_tien', PayrollEntry.fromJson),
    );
  }

  int applyPayload(PayrollSyncData data, {bool markDirty = false}) {
    var applied = 0;
    for (final e in data.crews) {
      upsertCrew(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.phases) {
      upsertPhase(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.bands) {
      upsertBand(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.rates) {
      upsertRate(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.workers) {
      upsertWorker(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.attendances) {
      upsertAttendance(e, dirty: markDirty);
      applied++;
    }
    for (final e in data.entries) {
      upsertEntry(e, dirty: markDirty);
      applied++;
    }
    return applied;
  }

  void clearDirty(PayrollSyncData data) {
    void clear(String table, Iterable<String> ids) {
      for (final id in ids) {
        _db.execute('UPDATE $table SET dirty = 0 WHERE id = ?', [id]);
      }
    }

    clear('doan', data.crews.map((e) => e.id));
    clear('giai_doan_luong', data.phases.map((e) => e.id));
    clear('muc_luong', data.bands.map((e) => e.id));
    clear('gia_luong', data.rates.map((e) => e.id));
    clear('nhan_vien', data.workers.map((e) => e.id));
    clear('cham_cong', data.attendances.map((e) => e.id));
    clear('so_tien', data.entries.map((e) => e.id));
  }

  int pendingPushCount() {
    var total = 0;
    for (final table in tables) {
      total += _db.select('SELECT COUNT(*) AS c FROM $table WHERE dirty = 1').first['c'] as int;
    }
    return total;
  }

  void softDelete(String table, String id) {
    _db.execute(
      'UPDATE $table SET deleted = 1, dirty = 1, updated_at = ? WHERE id = ?',
      [timeToMillis(DateTime.now()), id],
    );
  }

  // ================================================================= nội bộ

  T? _one<T>(String table, String id, T Function(Map<String, Object?>) parse) {
    final rows = _db.select('SELECT * FROM $table WHERE id = ?', [id]);
    return rows.isEmpty ? null : parse(rows.first);
  }
}
