import 'package:canxe_shared/canxe_shared.dart';

import '../db/payroll_repository.dart';
import 'ticket_service.dart' show BusinessException;

/// Nghiệp vụ quản lý đoàn, giai đoạn lương, bảng mức lương và nhân viên.
///
/// Tách khỏi router để cùng một bộ quy tắc dùng được cho cả API lẫn các luồng
/// khác, và để kiểm thử được mà không cần dựng máy chủ.
class PayrollService {
  PayrollService(this._repo);

  final PayrollRepository _repo;

  // ==================================================================== đoàn

  Crew createCrew(Map<String, Object?> body) {
    final name = asString(body['name']).trim();
    if (name.isEmpty) throw BusinessException('Chưa nhập tên đoàn.');

    return _repo.upsertCrew(Crew.create(
      name: name,
      season: asString(body['season']).trim(),
      startDate: asTimeOrNull(body['start_date']),
      endDate: asTimeOrNull(body['end_date']),
      note: asStringOrNull(body['note']),
    ));
  }

  Crew updateCrew(String id, Map<String, Object?> body) {
    final crew = _requireCrew(id);
    final name = asString(body['name'], fallback: crew.name).trim();
    if (name.isEmpty) throw BusinessException('Tên đoàn không được để trống.');

    return _repo.upsertCrew(crew.copyWith(
      name: name,
      season: asString(body['season'], fallback: crew.season),
      startDate: asTimeOrNull(body['start_date']),
      endDate: asTimeOrNull(body['end_date']),
      status: body.containsKey('status') ? CrewStatus.parse(body['status']) : null,
      note: asStringOrNull(body['note']),
    ));
  }

  // ========================================================= giai đoạn lương

  WagePhase savePhase(String crewId, Map<String, Object?> body) {
    _requireCrew(crewId);

    final name = asString(body['name']).trim();
    if (name.isEmpty) throw BusinessException('Chưa nhập tên giai đoạn.');

    final from = asTimeOrNull(body['from_date']);
    if (from == null) throw BusinessException('Chưa chọn ngày bắt đầu giai đoạn.');
    final to = asTimeOrNull(body['to_date']);
    if (to != null && to.isBefore(from)) {
      throw BusinessException('Ngày kết thúc phải sau ngày bắt đầu.');
    }

    final id = asStringOrNull(body['id']);
    final existing = id == null ? null : _repo.phaseById(id);

    _assertNoOverlap(
      crewId: crewId,
      from: WagePhase.dateOnly(from),
      to: to == null ? null : WagePhase.dateOnly(to),
      ignoreId: existing?.id,
    );

    final workStart = asString(body['work_start'],
            fallback: existing?.workStart ?? WagePhase.defaultWorkStart)
        .trim();
    final workEnd = asString(body['work_end'],
            fallback: existing?.workEnd ?? WagePhase.defaultWorkEnd)
        .trim();
    final breakHours = asDoubleOrNull(body['break_hours']) ??
        existing?.breakHours ??
        WagePhase.defaultBreakHours;
    _assertWorkHours(workStart: workStart, workEnd: workEnd, breakHours: breakHours);

    final phase = existing == null
        ? WagePhase.create(
            crewId: crewId,
            name: name,
            fromDate: from,
            toDate: to,
            sortOrder: asInt(body['sort_order']),
            workStart: workStart,
            workEnd: workEnd,
            breakHours: breakHours,
          )
        : existing.copyWith(
            name: name,
            fromDate: from,
            toDate: to,
            sortOrder: asInt(body['sort_order'], fallback: existing.sortOrder),
            workStart: workStart,
            workEnd: workEnd,
            breakHours: breakHours,
          );
    return _repo.upsertPhase(phase);
  }

  /// Giờ làm phải ra được một số giờ chuẩn dương.
  ///
  /// Giờ chuẩn là mẫu số khi ai đó nghỉ vài giờ; khai sai thì chấm công vẫn
  /// chạy nhưng tiền lệch, nên chặn ngay lúc khai.
  void _assertWorkHours({
    required String workStart,
    required String workEnd,
    required double breakHours,
  }) {
    final start = WagePhase.parseClock(workStart);
    final end = WagePhase.parseClock(workEnd);
    if (start == null || end == null) {
      throw BusinessException('Giờ vào ca và giờ tan ca phải ghi dạng HH:mm, ví dụ 07:00.');
    }
    if (end <= start) throw BusinessException('Giờ tan ca phải sau giờ vào ca.');
    if (breakHours < 0) throw BusinessException('Giờ nghỉ giữa ca không được âm.');
    if (end - start - breakHours <= 0) {
      throw BusinessException(
        'Giờ nghỉ giữa ca ($breakHours giờ) bằng hoặc vượt cả ca làm '
        '(${end - start} giờ). Kiểm lại giờ vào, giờ về và giờ nghỉ.',
      );
    }
  }

  /// Hai giai đoạn không được phủ lên cùng một ngày.
  ///
  /// Nếu chồng nhau thì một ngày chấm công tra ra hai mức lương khác nhau, và
  /// kết quả phụ thuộc vào thứ tự đọc trong cơ sở dữ liệu — sai lặng lẽ, không
  /// ai phát hiện cho tới lúc trả lương.
  void _assertNoOverlap({
    required String crewId,
    required DateTime from,
    required DateTime? to,
    String? ignoreId,
  }) {
    for (final other in _repo.phases(crewId)) {
      if (other.id == ignoreId) continue;

      final otherEnd = other.toDate;
      final startsAfterOther = otherEnd != null && from.isAfter(otherEnd);
      final endsBeforeOther = to != null && to.isBefore(other.fromDate);
      if (startsAfterOther || endsBeforeOther) continue;

      throw BusinessException(
        'Khoảng ngày này trùng với giai đoạn "${other.name}" '
        '(${_day(other.fromDate)} – ${otherEnd == null ? 'chưa chốt' : _day(otherEnd)}). '
        'Hai giai đoạn không được phủ lên cùng một ngày.',
      );
    }
  }

  // ============================================================== mức lương

  WageBand saveBand(String crewId, Map<String, Object?> body) {
    _requireCrew(crewId);
    final name = asString(body['name']).trim();
    if (name.isEmpty) throw BusinessException('Chưa nhập tên mức lương.');

    final id = asStringOrNull(body['id']);
    final existing = id == null ? null : _repo.bandById(id);
    final band = existing == null
        ? WageBand.create(crewId: crewId, name: name, sortOrder: asInt(body['sort_order']))
        : existing.copyWith(
            name: name,
            sortOrder: asInt(body['sort_order'], fallback: existing.sortOrder),
          );
    return _repo.upsertBand(band);
  }

  /// Xoá một mức lương, chặn nếu còn người đang hưởng.
  void deleteBand(String crewId, String bandId) {
    final dangHuong = _repo
        .workers(crewId)
        .where((w) => w.bandId == bandId)
        .map((w) => w.name)
        .toList();
    if (dangHuong.isNotEmpty) {
      throw BusinessException(
        'Còn ${dangHuong.length} người đang hưởng mức này '
        '(${dangHuong.take(3).join(", ")}${dangHuong.length > 3 ? '...' : ''}). '
        'Chuyển họ sang mức khác trước đã.',
      );
    }
    _repo.softDelete('muc_luong', bandId);
  }

  // =============================================================== giá lương

  WageRate saveRate(String crewId, Map<String, Object?> body) {
    _requireCrew(crewId);

    final phaseId = asString(body['phase_id']);
    if (_repo.phaseById(phaseId) == null) {
      throw BusinessException('Không tìm thấy giai đoạn lương.');
    }

    final amount = asDoubleOrNull(body['monthly_amount']);
    if (amount == null || amount < 0) {
      throw BusinessException('Lương tháng phải là số không âm.');
    }

    final bandId = asStringOrNull(body['band_id']);
    final workerId = asStringOrNull(body['worker_id']);
    if ((bandId == null) == (workerId == null)) {
      throw BusinessException(
        'Giá lương phải gắn với một mức lương HOẶC một người, không được cả hai '
        'và cũng không được để trống.',
      );
    }

    // Mỗi cặp (giai đoạn, mức) hay (giai đoạn, người) chỉ có một giá. Không tra
    // lại trước khi ghi thì mỗi lần sửa lại đẻ thêm một dòng, và lúc tính lương
    // lấy trúng dòng nào là hên xui.
    final existing = _repo.rates(crewId).where((r) =>
        r.phaseId == phaseId && r.bandId == bandId && r.workerId == workerId);

    final rate = existing.isNotEmpty
        ? existing.first.copyWith(monthlyAmount: amount)
        : (bandId != null
            ? WageRate.forBand(
                crewId: crewId, phaseId: phaseId, bandId: bandId, monthlyAmount: amount)
            : WageRate.forWorker(
                crewId: crewId, phaseId: phaseId, workerId: workerId!, monthlyAmount: amount));
    return _repo.upsertRate(rate);
  }

  // ============================================================== nhân viên

  Worker saveWorker(String crewId, Map<String, Object?> body) {
    _requireCrew(crewId);

    final name = asString(body['name']).trim();
    if (name.isEmpty) throw BusinessException('Chưa nhập tên nhân viên.');

    final bandId = asStringOrNull(body['band_id']);
    if (bandId != null && _repo.bandById(bandId)?.crewId != crewId) {
      throw BusinessException('Mức lương này không thuộc đoàn hiện tại.');
    }

    final id = asStringOrNull(body['id']);
    final existing = id == null ? null : _repo.workerById(id);
    if (existing != null && existing.crewId != crewId) {
      throw BusinessException('Nhân viên này thuộc đoàn khác.');
    }

    final worker = existing == null
        ? Worker.create(
            crewId: crewId,
            name: name,
            phone: asStringOrNull(body['phone']),
            stationCode: asStringOrNull(body['station_code']),
            bandId: bandId,
            joinDate: asTimeOrNull(body['join_date']) ?? DateTime.now(),
            note: asStringOrNull(body['note']),
          )
        : existing.copyWith(
            name: name,
            phone: asStringOrNull(body['phone']),
            stationCode: asStringOrNull(body['station_code']),
            bandId: bandId,
            joinDate: asTimeOrNull(body['join_date']),
            note: asStringOrNull(body['note']),
          );
    return _repo.upsertWorker(worker);
  }

  /// Chuyển một hoặc nhiều người sang kho khác, có hiệu lực từ bây giờ.
  ///
  /// Chỉ đổi kho **hiện tại** của họ. Những ngày đã chấm công vẫn giữ kho ghi
  /// lúc đó, nên chuyển qua chuyển lại bao nhiêu lần cũng không làm sai số liệu
  /// tháng trước — và cộng ra được tiền công mà từng kho đã gánh.
  List<Worker> transferWorkers({
    required String crewId,
    required List<String> workerIds,
    required String stationCode,
  }) {
    _requireCrew(crewId);
    final kho = stationCode.trim().toUpperCase();
    if (kho.isEmpty) throw BusinessException('Chưa chọn kho để chuyển sang.');
    if (workerIds.isEmpty) throw BusinessException('Chưa chọn người nào để chuyển.');

    final result = <Worker>[];
    for (final id in workerIds) {
      final worker = _repo.workerById(id);
      if (worker == null || worker.deleted) {
        throw BusinessException('Không tìm thấy nhân viên trong danh sách chuyển.');
      }
      if (worker.crewId != crewId) {
        throw BusinessException('Nhân viên "${worker.name}" không thuộc đoàn này.');
      }
      result.add(_repo.upsertWorker(worker.copyWith(stationCode: kho)));
    }
    return result;
  }

  /// Cho một người nghỉ làm.
  ///
  /// Không xoá mà đổi trạng thái: lịch sử chấm công và công nợ phải giữ nguyên
  /// để còn quyết toán cuối mùa.
  Worker stopWorker(String workerId, {DateTime? leaveDate}) {
    final worker = _repo.workerById(workerId);
    if (worker == null || worker.deleted) {
      throw BusinessException('Không tìm thấy nhân viên.');
    }
    return _repo.upsertWorker(worker.copyWith(
      status: WorkerStatus.daNghi,
      leaveDate: leaveDate ?? DateTime.now(),
    ));
  }

  Worker resumeWorker(String workerId) {
    final worker = _repo.workerById(workerId);
    if (worker == null || worker.deleted) {
      throw BusinessException('Không tìm thấy nhân viên.');
    }
    return _repo.upsertWorker(worker.copyWith(status: WorkerStatus.dangLam));
  }

  // ============================================================== chấm công

  /// Bảng chấm công của **một ngày**.
  ///
  /// Trả về cả người chưa chấm (`present == null`) để màn hình phân biệt được
  /// "hôm nay nghỉ" với "hôm nay chưa ai chấm" — hai chuyện khác nhau hoàn toàn
  /// khi đối chiếu cuối mùa.
  Map<String, Object?> daySheet(String crewId, DateTime date) {
    _requireCrew(crewId);
    final day = WagePhase.dateOnly(date);
    final phase = _repo.phaseForDate(crewId, day);
    final marked = {
      for (final a in _repo.attendances(crewId: crewId, from: day, to: day)) a.workerId: a
    };

    final rows = <Map<String, Object?>>[];
    final missingRate = <Map<String, Object?>>[];

    for (final worker in _repo.workers(crewId)) {
      final existing = marked[worker.id];
      // Người đã chấm ngày đó thì luôn hiện, kể cả nay đã nghỉ hoặc mới vào
      // sau — giấu đi thì mất dấu bản ghi đã có.
      if (existing == null && !_worksOn(worker, day)) continue;

      // Ngày đã chấm giữ nguyên mức lương lúc chấm; ngày chưa chấm mới tra
      // bảng giá hiện tại. Sửa bảng giá không được làm đổi lương đã tính.
      final amount = existing?.monthlyAmount ??
          (phase == null
              ? null
              : _repo.monthlyAmountFor(
                  crewId: crewId, phaseId: phase.id, worker: worker));

      if (existing == null && amount == null) {
        missingRate.add({'worker_id': worker.id, 'name': worker.name});
      }

      rows.add({
        'worker_id': worker.id,
        'name': worker.name,
        'station_code': existing?.stationCode ?? worker.stationCode,
        'band_id': worker.bandId,
        'status': worker.status.value,
        'attendance_id': existing?.id,
        'present': existing?.present,
        'monthly_amount': amount,
        'days_in_month': existing?.daysInMonth ?? Attendance.daysInMonthOf(day),
        'hours_off': existing?.hoursOff ?? 0,
        'standard_hours': existing?.standardHours ?? phase?.standardHours,
        'work_unit': existing?.workUnit,
        'note': existing?.note,
      });
    }

    return {
      'date': timeToMillis(day),
      'days_in_month': Attendance.daysInMonthOf(day),
      'standard_hours': phase?.standardHours,
      'phase': phase?.toJson(),
      'rows': rows,
      'present_count': rows.where((r) => r['present'] == true).length,
      'marked_count': rows.where((r) => r['present'] != null).length,
      'missing_rate': missingRate,
    };
  }

  /// Người này có nằm trong đoàn vào [day] hay không.
  ///
  /// Vào làm ngày 15 thì không được hiện ở ngày 3, và nghỉ từ ngày 20 thì
  /// không được hiện ở ngày 25 — nếu không thì rất dễ chấm công cho người
  /// chưa vào hoặc đã nghỉ.
  static bool _worksOn(Worker worker, DateTime day) {
    final join = worker.joinDate;
    if (join != null && WagePhase.dateOnly(join).isAfter(day)) return false;
    final leave = worker.leaveDate;
    if (leave != null && WagePhase.dateOnly(leave).isBefore(day)) return false;
    return worker.isWorking || leave != null;
  }

  /// Chấm công cho một ngày.
  ///
  /// [marks] là `{id nhân viên: có đi làm}`. Ghi cả người nghỉ (`false`) chứ
  /// không chỉ người đi làm, để phân biệt với ngày chưa chấm.
  ///
  /// [hoursOff] là `{id nhân viên: số giờ nghỉ trong ngày}` cho người đi làm
  /// nhưng không đủ ca. Không gửi thì giữ nguyên số giờ đã ghi; chấm là nghỉ
  /// cả ngày thì giờ nghỉ tự về 0.
  Map<String, Object?> markDay({
    required String crewId,
    required DateTime date,
    required Map<String, bool> marks,
    Map<String, double> hoursOff = const {},
    String? note,
    String? createdBy,
  }) {
    _requireCrew(crewId);
    final day = WagePhase.dateOnly(date);

    final phase = _repo.phaseForDate(crewId, day);
    if (phase == null) {
      throw BusinessException(
        'Ngày ${_day(day)} chưa thuộc giai đoạn lương nào. Khai giai đoạn ở tab '
        '"Cấu hình lương" trước đã, không thì không tra ra lương của ngày này.',
      );
    }

    // Người chưa khai giá thì bỏ qua chứ không chặn cả ngày: một người mới vào
    // chưa gán mức lương không được làm cả đoàn không chấm công được. Nhưng
    // phải trả tên họ về để màn hình cảnh báo, kẻo mất công mà không ai biết.
    final skipped = <Map<String, Object?>>[];

    for (final entry in marks.entries) {
      final worker = _repo.workerById(entry.key);
      if (worker == null || worker.deleted) {
        throw BusinessException('Không tìm thấy nhân viên trong danh sách chấm công.');
      }
      if (worker.crewId != crewId) {
        throw BusinessException('Nhân viên "${worker.name}" không thuộc đoàn này.');
      }

      final existing = _repo.attendanceOn(worker.id, day);
      final gioNghi = hoursOff[worker.id];
      if (gioNghi != null && entry.value) {
        _assertHoursOff(gioNghi, existing?.standardHours ?? phase.standardHours, worker);
      }

      if (existing != null) {
        // Sửa lại ngày đã chấm thì giữ nguyên mức lương và giờ chuẩn đã chốt.
        _repo.upsertAttendance(existing.copyWith(
          present: entry.value,
          hoursOff: gioNghi,
          note: note,
        ));
        continue;
      }

      final amount = _repo.monthlyAmountFor(
        crewId: crewId,
        phaseId: phase.id,
        worker: worker,
      );
      if (amount == null) {
        skipped.add({
          'worker_id': worker.id,
          'name': worker.name,
          'reason': worker.bandId == null
              ? 'chưa gán mức lương'
              : 'mức lương chưa khai giá cho giai đoạn "${phase.name}"',
        });
        continue;
      }

      _repo.upsertAttendance(Attendance.create(
        crewId: crewId,
        workerId: worker.id,
        date: day,
        present: entry.value,
        phaseId: phase.id,
        stationCode: worker.stationCode,
        monthlyAmount: amount,
        hoursOff: gioNghi ?? 0,
        standardHours: phase.standardHours,
        note: note,
        createdBy: createdBy,
      ));
    }

    return {
      ...daySheet(crewId, day),
      'skipped': skipped,
    };
  }

  /// Giờ nghỉ phải nằm trong ca; nghỉ hết ca thì phải chấm là nghỉ cả ngày.
  void _assertHoursOff(double hoursOff, double standardHours, Worker worker) {
    if (hoursOff < 0) {
      throw BusinessException('Giờ nghỉ của "${worker.name}" không được âm.');
    }
    if (hoursOff >= standardHours) {
      throw BusinessException(
        'Giờ nghỉ của "${worker.name}" ($hoursOff giờ) bằng hoặc vượt giờ chuẩn '
        'của ngày ($standardHours giờ). Nghỉ cả ngày thì chấm là nghỉ.',
      );
    }
  }

  /// Bảng chấm công cả tháng: mỗi người một dòng, mỗi ngày một ô.
  Map<String, Object?> monthSheet(String crewId, int year, int month) {
    _requireCrew(crewId);
    if (month < 1 || month > 12) {
      throw BusinessException('Tháng phải từ 1 tới 12.');
    }

    final first = DateTime(year, month, 1);
    final days = Attendance.daysInMonthOf(first);
    final last = DateTime(year, month, days);
    final all = _repo.attendances(crewId: crewId, from: first, to: last);
    final bandNames = {for (final b in _repo.bands(crewId)) b.id: b.name};

    final rows = <Map<String, Object?>>[];
    var totalDays = 0;
    var totalUnits = 0.0;
    var totalWage = 0.0;

    for (final worker in _repo.workers(crewId)) {
      final mine = all.where((a) => a.workerId == worker.id).toList();
      // Người không có ngày nào trong tháng và cũng không thuộc đoàn tháng đó
      // thì không cần chiếm một dòng.
      if (mine.isEmpty && !_worksOn(worker, first) && !_worksOn(worker, last)) {
        continue;
      }

      final present = mine.where((a) => a.present).map((a) => a.date.day).toList()..sort();
      final absent = mine.where((a) => !a.present).map((a) => a.date.day).toList()..sort();
      final wage = PayrollCalculator.wageEarnedInMonth(mine);
      final units = PayrollCalculator.workUnitsInMonth(mine);

      totalDays += present.length;
      totalUnits += units;
      totalWage += wage;

      rows.add({
        'worker_id': worker.id,
        'name': worker.name,
        'station_code': worker.stationCode,
        'band_name': worker.bandId == null ? null : bandNames[worker.bandId],
        'status': worker.status.value,
        'present_days': present,
        'absent_days': absent,
        // Ngày đi làm nhưng nghỉ vài giờ: ghi số giờ làm thực để bảng tháng
        // hiện "6,5" thay vì dấu ✓ — nhìn vào là biết ngày đó thiếu.
        'partial_days': {
          for (final a in mine)
            if (a.present && a.hoursOff > 0) '${a.date.day}': a.hoursWorked,
        },
        'days_worked': present.length,
        'work_units': units,
        'wage_earned': wage,
      });
    }

    return {
      'year': year,
      'month': month,
      'days_in_month': days,
      'rows': rows,
      'total_days_worked': totalDays,
      'total_work_units': totalUnits,
      'total_wage': PayrollCalculator.roundMoney(totalWage),
    };
  }

  /// Tính lại mức lương đã chốt của một tháng theo bảng giá hiện tại.
  ///
  /// Bình thường ngày đã chấm giữ nguyên mức lương lúc chấm. Hàm này là cái nút
  /// riêng để cố ý tính lại quá khứ — ví dụ khai sai giá rồi mới phát hiện.
  /// Trả về đúng những ngày thực sự đổi số, để biết mình vừa sửa cái gì.
  Map<String, Object?> recalcMonth({
    required String crewId,
    required int year,
    required int month,
  }) {
    _requireCrew(crewId);
    if (month < 1 || month > 12) {
      throw BusinessException('Tháng phải từ 1 tới 12.');
    }

    final first = DateTime(year, month, 1);
    final last = DateTime(year, month, Attendance.daysInMonthOf(first));
    final workers = {for (final w in _repo.workers(crewId)) w.id: w};

    final changed = <Map<String, Object?>>[];
    for (final record in _repo.attendances(crewId: crewId, from: first, to: last)) {
      final worker = workers[record.workerId];
      final phase = _repo.phaseForDate(crewId, record.date);
      if (worker == null || phase == null) continue;

      final amount = _repo.monthlyAmountFor(
        crewId: crewId,
        phaseId: phase.id,
        worker: worker,
      );
      if (amount == null) continue;
      final hours = phase.standardHours;
      if (amount == record.monthlyAmount && hours == record.standardHours) continue;

      _repo.upsertAttendance(record.copyWith(
        monthlyAmount: amount,
        standardHours: hours,
        phaseId: phase.id,
      ));
      changed.add({
        'worker_id': worker.id,
        'name': worker.name,
        'date': timeToMillis(record.date),
        'from': record.monthlyAmount,
        'to': amount,
        'hours_from': record.standardHours,
        'hours_to': hours,
      });
    }

    return {'changed': changed, 'count': changed.length};
  }

  /// Bảng giá đầy đủ của một đoàn, dựng sẵn cho màn hình cấu hình.
  Map<String, Object?> wageTable(String crewId) {
    _requireCrew(crewId);
    final phases = _repo.phases(crewId);
    final bands = _repo.bands(crewId);
    final rates = _repo.rates(crewId);

    return {
      'phases': phases.map((e) => e.toJson()).toList(),
      'bands': bands.map((e) => e.toJson()).toList(),
      'rates': rates.map((e) => e.toJson()).toList(),
      // Ô nào chưa khai giá thì màn hình phải chỉ ra được, chứ để trống thì tới
      // lúc chấm công mới phát hiện là không tra ra lương.
      'missing': [
        for (final band in bands)
          for (final phase in phases)
            if (!rates.any((r) => r.bandId == band.id && r.phaseId == phase.id))
              {'band_id': band.id, 'band_name': band.name, 'phase_id': phase.id, 'phase_name': phase.name},
      ],
    };
  }

  // ================================================================ sổ tiền

  /// Sổ tiền của một người: từng tháng, công nợ cả mùa và danh sách khoản.
  ///
  /// Dựng sẵn cả trần ứng của từng tháng để màn hình không phải tự tính lại —
  /// tính hai nơi là sớm muộn lệch nhau.
  Map<String, Object?> moneySheet(String crewId, String workerId) {
    _requireCrew(crewId);
    final worker = _requireWorker(crewId, workerId);

    final attendances = _repo.attendances(crewId: crewId, workerId: workerId);
    final entries = _repo.entries(crewId: crewId, workerId: workerId);

    // Tháng nào có chấm công hoặc có khoản tiền thì hiện, kể cả tháng chỉ ứng
    // mà chưa chấm ngày nào — nếu không thì khoản đó biến mất khỏi màn hình.
    final months = <String>{
      ...attendances.where((a) => !a.deleted).map((a) => a.monthKey),
      ...entries.map((e) => e.monthKey),
    }.toList()
      ..sort();

    final balance = PayrollCalculator.balance(
      attendances: attendances,
      entries: entries,
    );

    return {
      'worker': worker.toJson(),
      'months': [
        for (final key in months)
          _monthJson(PayrollCalculator.monthly(
            monthKey: key,
            attendances: attendances,
            entries: entries,
          )),
      ],
      'balance': _balanceJson(balance),
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  /// Bảng tiền của cả đoàn, dùng cho danh sách và cảnh báo.
  Map<String, Object?> crewMoney(String crewId, {DateTime? month}) {
    _requireCrew(crewId);
    final moc = month ?? DateTime.now();
    final monthKey = '${moc.year}-${moc.month.toString().padLeft(2, '0')}';

    final rows = <Map<String, Object?>>[];
    var tongThuNhap = 0.0;
    var tongUng = 0.0;
    var tongTra = 0.0;
    var soAm = 0;

    for (final worker in _repo.workers(crewId)) {
      final attendances = _repo.attendances(crewId: crewId, workerId: worker.id);
      final entries = _repo.entries(crewId: crewId, workerId: worker.id);
      if (attendances.isEmpty && entries.isEmpty && !worker.isWorking) continue;

      final balance = PayrollCalculator.balance(
        attendances: attendances,
        entries: entries,
      );
      final thisMonth = PayrollCalculator.monthly(
        monthKey: monthKey,
        attendances: attendances,
        entries: entries,
      );

      tongThuNhap += balance.totalEarned;
      tongUng += balance.totalAdvanced;
      tongTra += balance.totalPaid;
      if (balance.isNegative) soAm++;

      rows.add({
        'worker_id': worker.id,
        'name': worker.name,
        'station_code': worker.stationCode,
        'status': worker.status.value,
        'balance': _balanceJson(balance),
        'this_month': _monthJson(thisMonth),
      });
    }

    return {
      'month_key': monthKey,
      'rows': rows,
      'total_earned': PayrollCalculator.roundMoney(tongThuNhap),
      'total_advanced': PayrollCalculator.roundMoney(tongUng),
      'total_paid': PayrollCalculator.roundMoney(tongTra),
      'total_balance': PayrollCalculator.roundMoney(tongThuNhap - tongUng - tongTra),
      // Số người đã nhận vượt công đã làm — phải đếm ra, không được im lặng.
      'negative_count': soAm,
    };
  }

  /// Thử một lần ứng trước khi ghi, để màn hình cảnh báo ngay lúc đang nhập.
  ///
  /// [ignoreEntryId] là khoản đang sửa: không loại nó ra thì tiền cũ bị đếm hai
  /// lần, sửa 1 triệu thành 1,1 triệu lại báo vượt trần.
  Map<String, Object?> previewAdvance({
    required String crewId,
    required String workerId,
    required double amount,
    DateTime? date,
    String? ignoreEntryId,
  }) {
    _requireCrew(crewId);
    _requireWorker(crewId, workerId);

    final moc = date ?? DateTime.now();
    final check = _checkAdvance(
      crewId: crewId,
      workerId: workerId,
      amount: amount,
      date: moc,
      ignoreEntryId: ignoreEntryId,
    );

    return {
      'requested': check.requested,
      'allowed': check.allowed,
      'cap': check.cap,
      'advanced_before': check.advancedBefore,
      'income': check.income,
      'exceeds_cap': check.exceedsCap,
      'excess': check.excess,
      'warning': check.warning,
      // Gợi ý số tròn để đưa tiền mặt cho gọn.
      'suggested': PayrollCalculator.roundAdvanceDown(check.allowed),
    };
  }

  AdvanceCheck _checkAdvance({
    required String crewId,
    required String workerId,
    required double amount,
    required DateTime date,
    String? ignoreEntryId,
  }) {
    final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final entries = _repo
        .entries(crewId: crewId, workerId: workerId)
        .where((e) => e.id != ignoreEntryId);

    return PayrollCalculator.checkAdvance(
      month: PayrollCalculator.monthly(
        monthKey: monthKey,
        attendances: _repo.attendances(crewId: crewId, workerId: workerId),
        entries: entries,
      ),
      requested: amount,
    );
  }

  /// Ghi một khoản tiền: ứng lương, tăng ca, phụ cấp, trừ tiền hay thanh toán.
  ///
  /// Riêng ứng lương bị trần 50% thu nhập của **chính tháng đó** chặn lại. Vượt
  /// trần vẫn cho ghi nhưng **bắt nhập lý do** — chủ quyết định phá luật thì
  /// phải để lại vết, vì đây là chỗ dễ thất thoát nhất.
  Map<String, Object?> saveEntry(String crewId, Map<String, Object?> body,
      {String? createdBy}) {
    _requireCrew(crewId);
    final workerId = asString(body['worker_id']);
    final worker = _requireWorker(crewId, workerId);

    final type = PayrollEntryType.parse(body['type']);
    final amount = asDoubleOrNull(body['amount']);
    if (amount == null || amount <= 0) {
      throw BusinessException('Số tiền phải lớn hơn 0.');
    }

    final date = asTimeOrNull(body['date']) ?? DateTime.now();
    final id = asStringOrNull(body['id']);
    final existing = id == null ? null : _repo.entryById(id);
    if (existing != null && existing.workerId != workerId) {
      throw BusinessException('Khoản này thuộc người khác.');
    }
    if (existing != null && existing.type != type) {
      throw BusinessException(
        'Không đổi được loại khoản đã ghi. Xoá khoản cũ rồi ghi khoản mới.',
      );
    }

    var reason = asStringOrNull(body['over_cap_reason'])?.trim();
    if (reason != null && reason.isEmpty) reason = null;

    if (type == PayrollEntryType.ungLuong) {
      final check = _checkAdvance(
        crewId: crewId,
        workerId: workerId,
        amount: amount,
        date: date,
        ignoreEntryId: existing?.id,
      );
      if (check.exceedsCap && reason == null) {
        throw BusinessException(
          '${check.warning} Muốn ứng vượt thì phải nhập lý do để lưu vào sổ.',
        );
      }
      // Không vượt trần thì đừng giữ lý do cũ, kẻo sổ đầy cảnh báo giả.
      if (!check.exceedsCap) reason = null;
    } else if (reason != null) {
      throw BusinessException('Chỉ khoản ứng lương mới có lý do vượt trần.');
    }

    if (type == PayrollEntryType.thanhToan) {
      final crew = _requireCrew(crewId);
      if (crew.status != CrewStatus.daHoanThanh) {
        throw BusinessException(
          'Trong mùa chỉ ứng lương; quyết toán một lần vào cuối mùa. '
          'Đóng đoàn "${crew.name}" trước rồi mới thanh toán.',
        );
      }
    }

    final entry = existing == null
        ? PayrollEntry.create(
            crewId: crewId,
            workerId: workerId,
            type: type,
            amount: amount,
            date: date,
            note: asStringOrNull(body['note']),
            overCapReason: reason,
            createdBy: createdBy,
          )
        : existing.copyWith(
            amount: amount,
            date: date,
            note: asStringOrNull(body['note']),
            overCapReason: reason,
          );

    final saved = _repo.upsertEntry(entry);
    return {
      'entry': saved.toJson(),
      'worker_name': worker.name,
      ...moneySheet(crewId, workerId),
    };
  }

  Map<String, Object?> deleteEntry(String crewId, String entryId) {
    _requireCrew(crewId);
    final entry = _repo.entryById(entryId);
    if (entry == null || entry.deleted) {
      throw BusinessException('Không tìm thấy khoản tiền.');
    }
    if (entry.crewId != crewId) {
      throw BusinessException('Khoản này không thuộc đoàn hiện tại.');
    }
    _repo.softDelete('so_tien', entryId);
    return moneySheet(crewId, entry.workerId);
  }

  // ============================================================== báo cáo

  /// Bảng lương một tháng của cả đoàn — bảng để đối chiếu và trả tiền.
  ///
  /// Kèm phần chia theo kho: mỗi ngày chấm công đã ghi kho tại thời điểm đó,
  /// nên cộng ra được tiền công mà từng kho phải gánh dù người chuyển kho qua
  /// lại giữa mùa.
  Map<String, Object?> monthReport(String crewId, int year, int month) {
    final crew = _requireCrew(crewId);
    if (month < 1 || month > 12) {
      throw BusinessException('Tháng phải từ 1 tới 12.');
    }
    final monthKey = '$year-${month.toString().padLeft(2, '0')}';

    final rows = <Map<String, Object?>>[];
    final theoKho = <String, double>{};
    var tongCong = 0.0;
    var tongLuong = 0.0;
    var tongTangCa = 0.0;
    var tongPhuCap = 0.0;
    var tongTruTien = 0.0;
    var tongThuNhap = 0.0;
    var tongUng = 0.0;

    for (final worker in _repo.workers(crewId)) {
      final attendances = _repo.attendances(crewId: crewId, workerId: worker.id);
      final entries = _repo.entries(crewId: crewId, workerId: worker.id);
      final m = PayrollCalculator.monthly(
        monthKey: monthKey,
        attendances: attendances,
        entries: entries,
      );
      // Người không có công cũng không có khoản nào trong tháng thì bỏ khỏi
      // bảng, chứ để dòng toàn số 0 chỉ làm bảng dài ra.
      if (m.workUnits == 0 && m.overtime == 0 && m.allowance == 0 &&
          m.deduction == 0 && m.advanced == 0) {
        continue;
      }

      final ofMonth =
          attendances.where((a) => !a.deleted && a.monthKey == monthKey).toList();
      final phanKho = _splitByStation(ofMonth, m.wageEarned);
      phanKho.forEach((kho, tien) => theoKho[kho] = (theoKho[kho] ?? 0) + tien);

      tongCong += m.workUnits;
      tongLuong += m.wageEarned;
      tongTangCa += m.overtime;
      tongPhuCap += m.allowance;
      tongTruTien += m.deduction;
      tongThuNhap += m.income;
      tongUng += m.advanced;

      rows.add({
        'worker_id': worker.id,
        'name': worker.name,
        'station_code': worker.stationCode,
        'status': worker.status.value,
        ..._monthJson(m),
        'by_station': phanKho,
        // Còn lại của riêng tháng này, không tính nợ dồn các tháng khác.
        'remaining': PayrollCalculator.roundMoney(m.income - m.advanced),
      });
    }

    return {
      'crew_name': crew.name,
      'month_key': monthKey,
      'year': year,
      'month': month,
      'days_in_month': Attendance.daysInMonthOf(DateTime(year, month, 1)),
      'rows': rows,
      'by_station': {
        for (final e in theoKho.entries) e.key: PayrollCalculator.roundMoney(e.value),
      },
      'total_work_units': tongCong,
      'total_wage': PayrollCalculator.roundMoney(tongLuong),
      'total_overtime': PayrollCalculator.roundMoney(tongTangCa),
      'total_allowance': PayrollCalculator.roundMoney(tongPhuCap),
      'total_deduction': PayrollCalculator.roundMoney(tongTruTien),
      'total_income': PayrollCalculator.roundMoney(tongThuNhap),
      'total_advanced': PayrollCalculator.roundMoney(tongUng),
      'total_remaining': PayrollCalculator.roundMoney(tongThuNhap - tongUng),
    };
  }

  /// Chia tiền lương của một tháng cho các kho theo số công làm ở từng kho.
  ///
  /// Chia theo tỷ lệ công thay vì cộng tiền từng ngày: lương tháng chia cho số
  /// ngày ra số lẻ vô hạn, cộng dồn từng ngày thì tổng các kho không khớp tổng
  /// lương của người đó — mà bảng nào cũng phải khớp mới đối chiếu được.
  Map<String, double> _splitByStation(List<Attendance> ofMonth, double wage) {
    final units = <String, double>{};
    var total = 0.0;
    for (final a in ofMonth) {
      final unit = a.workUnit;
      if (unit <= 0) continue;
      final kho = a.stationCode ?? '(chưa gán kho)';
      units[kho] = (units[kho] ?? 0) + unit;
      total += unit;
    }
    if (total <= 0) return const {};
    return {
      for (final e in units.entries)
        e.key: PayrollCalculator.roundMoney(wage * e.value / total),
    };
  }

  /// Báo cáo cả mùa: mỗi người một dòng, gộp mọi tháng.
  Map<String, Object?> seasonReport(String crewId) {
    final crew = _requireCrew(crewId);

    final rows = <Map<String, Object?>>[];
    final theoKho = <String, double>{};
    final thangs = <String>{};
    var tongCong = 0.0;
    var tongThuNhap = 0.0;
    var tongUng = 0.0;
    var tongTra = 0.0;
    var soAm = 0;
    var soChuaTra = 0;

    for (final worker in _repo.workers(crewId)) {
      final attendances = _repo.attendances(crewId: crewId, workerId: worker.id);
      final entries = _repo.entries(crewId: crewId, workerId: worker.id);
      if (attendances.isEmpty && entries.isEmpty) continue;

      final months = <String>{
        ...attendances.where((a) => !a.deleted).map((a) => a.monthKey),
        ...entries.map((e) => e.monthKey),
      };
      thangs.addAll(months);

      var cong = 0.0;
      var luong = 0.0;
      for (final key in months) {
        final m = PayrollCalculator.monthly(
          monthKey: key,
          attendances: attendances,
          entries: entries,
        );
        cong += m.workUnits;
        luong += m.wageEarned;

        final ofMonth =
            attendances.where((a) => !a.deleted && a.monthKey == key).toList();
        _splitByStation(ofMonth, m.wageEarned)
            .forEach((kho, tien) => theoKho[kho] = (theoKho[kho] ?? 0) + tien);
      }

      final balance = PayrollCalculator.balance(
        attendances: attendances,
        entries: entries,
      );
      double sum(PayrollEntryType type) => entries
          .where((e) => e.type == type)
          .fold<double>(0, (t, e) => t + e.amount);

      tongCong += cong;
      tongThuNhap += balance.totalEarned;
      tongUng += balance.totalAdvanced;
      tongTra += balance.totalPaid;
      if (balance.isNegative) soAm++;
      if (balance.balance > 0) soChuaTra++;

      rows.add({
        'worker_id': worker.id,
        'name': worker.name,
        'station_code': worker.stationCode,
        'status': worker.status.value,
        'months': months.length,
        'work_units': cong,
        'wage_earned': PayrollCalculator.roundMoney(luong),
        'overtime': sum(PayrollEntryType.tangCa),
        'allowance': sum(PayrollEntryType.phuCap),
        'deduction': sum(PayrollEntryType.truTien),
        'balance': _balanceJson(balance),
        'settled': sum(PayrollEntryType.thanhToan) > 0,
      });
    }

    final sortedMonths = thangs.toList()..sort();
    return {
      'crew_name': crew.name,
      'crew_status': crew.status.value,
      'season': crew.season,
      'months': sortedMonths,
      'rows': rows,
      'by_station': {
        for (final e in theoKho.entries) e.key: PayrollCalculator.roundMoney(e.value),
      },
      'total_work_units': tongCong,
      'total_earned': PayrollCalculator.roundMoney(tongThuNhap),
      'total_advanced': PayrollCalculator.roundMoney(tongUng),
      'total_paid': PayrollCalculator.roundMoney(tongTra),
      'total_balance': PayrollCalculator.roundMoney(tongThuNhap - tongUng - tongTra),
      'negative_count': soAm,
      // Còn bao nhiêu người chưa nhận hết — đây là con số để biết mùa đã xong
      // hay chưa, chứ không phải trạng thái của đoàn.
      'unpaid_count': soChuaTra,
    };
  }

  // ========================================================= quyết toán mùa

  /// Chốt mùa: đóng đoàn lại để chuyển sang bước quyết toán.
  ///
  /// Không tự trả tiền — chỉ mở cửa cho việc thanh toán, vì trong mùa thì chỉ
  /// được ứng. Trả về những gì còn lại phải trả để biết còn nợ ai bao nhiêu.
  Map<String, Object?> closeSeason(String crewId, {DateTime? endDate}) {
    final crew = _requireCrew(crewId);
    if (crew.status == CrewStatus.daHoanThanh) {
      throw BusinessException('Đoàn "${crew.name}" đã chốt mùa rồi.');
    }
    _repo.upsertCrew(crew.copyWith(
      status: CrewStatus.daHoanThanh,
      endDate: endDate ?? DateTime.now(),
    ));
    return seasonReport(crewId);
  }

  /// Mở lại mùa đã chốt, cho trường hợp chốt sớm do bấm nhầm.
  Map<String, Object?> reopenSeason(String crewId) {
    final crew = _requireCrew(crewId);
    if (crew.status != CrewStatus.daHoanThanh) {
      throw BusinessException('Đoàn "${crew.name}" đang diễn ra, không cần mở lại.');
    }
    _repo.upsertCrew(crew.copyWith(status: CrewStatus.dangDienRa));
    return seasonReport(crewId);
  }

  /// Quyết toán: trả hết phần còn lại cho những người được chọn.
  ///
  /// Ghi đúng số còn phải trả của từng người, không nhận số tự nhập — quyết
  /// toán là phép trừ, gõ tay chỉ thêm chỗ sai. Ai số dư không dương thì bỏ
  /// qua kèm lý do chứ không ghi khoản 0 đồng.
  Map<String, Object?> settleSeason({
    required String crewId,
    List<String>? workerIds,
    DateTime? date,
    String? createdBy,
  }) {
    final crew = _requireCrew(crewId);
    if (crew.status != CrewStatus.daHoanThanh) {
      throw BusinessException(
        'Trong mùa chỉ ứng lương; quyết toán một lần vào cuối mùa. '
        'Bấm "Chốt mùa" cho đoàn "${crew.name}" trước đã.',
      );
    }

    // Quyết toán cả đoàn thì chỉ xét người có công hoặc có khoản tiền — người
    // chưa từng đi làm mà cũng báo "đã nhận đủ" chỉ làm loãng danh sách bỏ qua.
    // Còn chỉ định thẳng ai thì cứ xét người đó và nói rõ vì sao bỏ qua.
    final targets = workerIds == null || workerIds.isEmpty
        ? _repo
            .workers(crewId)
            .where((w) =>
                _repo.attendances(crewId: crewId, workerId: w.id).isNotEmpty ||
                _repo.entries(crewId: crewId, workerId: w.id).isNotEmpty)
            .map((w) => w.id)
            .toList()
        : workerIds;

    final paid = <Map<String, Object?>>[];
    final skipped = <Map<String, Object?>>[];
    var tong = 0.0;

    for (final id in targets) {
      final worker = _requireWorker(crewId, id);
      final entries = _repo.entries(crewId: crewId, workerId: id);
      final balance = PayrollCalculator.balance(
        attendances: _repo.attendances(crewId: crewId, workerId: id),
        entries: entries,
      );

      if (balance.balance <= 0) {
        skipped.add({
          'worker_id': id,
          'name': worker.name,
          'balance': balance.balance,
          'reason': balance.isNegative
              ? 'đã nhận vượt ${PayrollCalculator.money(balance.balance.abs())}, '
                  'phải thu lại chứ không trả thêm'
              : 'đã nhận đủ, không còn gì để trả',
        });
        continue;
      }

      final entry = _repo.upsertEntry(PayrollEntry.create(
        crewId: crewId,
        workerId: id,
        type: PayrollEntryType.thanhToan,
        amount: balance.balance,
        date: date ?? DateTime.now(),
        note: 'Quyết toán cuối mùa',
        createdBy: createdBy,
      ));
      tong += entry.amount;
      paid.add({
        'worker_id': id,
        'name': worker.name,
        'amount': entry.amount,
        'entry_id': entry.id,
      });
    }

    return {
      'paid': paid,
      'skipped': skipped,
      'paid_count': paid.length,
      'total_paid': PayrollCalculator.roundMoney(tong),
      'report': seasonReport(crewId),
    };
  }

  Map<String, Object?> _monthJson(MonthlyPayroll m) => {
        'month_key': m.monthKey,
        'days_worked': m.daysWorked,
        'work_units': m.workUnits,
        'wage_earned': m.wageEarned,
        'overtime': m.overtime,
        'allowance': m.allowance,
        'deduction': m.deduction,
        'income': m.income,
        'advance_cap': m.advanceCap,
        'advanced': m.advanced,
        'remaining_advance': m.remainingAdvance,
        'over_cap': m.overCap,
      };

  Map<String, Object?> _balanceJson(WorkerBalance b) => {
        'total_earned': b.totalEarned,
        'total_advanced': b.totalAdvanced,
        'total_paid': b.totalPaid,
        'total_received': b.totalReceived,
        'balance': b.balance,
        'is_negative': b.isNegative,
      };

  Worker _requireWorker(String crewId, String workerId) {
    final worker = _repo.workerById(workerId);
    if (worker == null || worker.deleted) {
      throw BusinessException('Không tìm thấy nhân viên.');
    }
    if (worker.crewId != crewId) {
      throw BusinessException('Nhân viên "${worker.name}" không thuộc đoàn này.');
    }
    return worker;
  }

  Crew _requireCrew(String id) {
    final crew = _repo.crewById(id);
    if (crew == null || crew.deleted) {
      throw BusinessException('Không tìm thấy đoàn.');
    }
    return crew;
  }

  static String _day(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
