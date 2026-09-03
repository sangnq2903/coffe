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

  Crew createCrew(Map<String, Object?> body, {required String stationCode}) {
    final name = asString(body['name']).trim();
    if (name.isEmpty) throw BusinessException('Chưa nhập tên đoàn.');

    return _repo.upsertCrew(Crew.create(
      name: name,
      stationCode: stationCode,
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

    final phase = existing == null
        ? WagePhase.create(
            crewId: crewId,
            name: name,
            fromDate: from,
            toDate: to,
            sortOrder: asInt(body['sort_order']),
          )
        : existing.copyWith(
            name: name,
            fromDate: from,
            toDate: to,
            sortOrder: asInt(body['sort_order'], fallback: existing.sortOrder),
          );
    return _repo.upsertPhase(phase);
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
            bandId: bandId,
            joinDate: asTimeOrNull(body['join_date']) ?? DateTime.now(),
            note: asStringOrNull(body['note']),
          )
        : existing.copyWith(
            name: name,
            phone: asStringOrNull(body['phone']),
            bandId: bandId,
            joinDate: asTimeOrNull(body['join_date']),
            note: asStringOrNull(body['note']),
          );
    return _repo.upsertWorker(worker);
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
