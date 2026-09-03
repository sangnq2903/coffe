import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/payroll_repository.dart';
import '../service/payroll_service.dart';

/// Các đường dẫn API của module chấm công.
///
/// Đăng ký thẳng vào [Router] của máy chủ chính nên đường dẫn vẫn phẳng, chỉ
/// tách file để phần cân xe và phần chấm công không dồn vào một chỗ.
class PayrollRouter {
  PayrollRouter({
    required this.repo,
    required this.service,
    required this.json,
    required this.error,
    required this.guard,
    required this.body,
    required this.user,
    required this.scope,
    required this.requireStation,
  });

  final PayrollRepository repo;
  final PayrollService service;

  // Các tiện ích dùng chung, nhận từ router chính để hai bên trả lời giống nhau.
  final Response Function(Object? data) json;
  final Response Function(String message, int status) error;
  final Response Function(Response Function()) guard;
  final Future<Map<String, Object?>> Function(Request) body;
  final AppUser Function(Request) user;
  final List<String>? Function(Request) scope;
  final void Function(Request, String?) requireStation;

  void attach(Router router) {
    // ------------------------------------------------------------------ đoàn
    router.get('/api/doan', (Request request) => guard(() {
          final list = repo.crews(
            allowedStations: scope(request),
            includeClosed: request.url.queryParameters['all'] != '0',
          );
          return json(list.map((e) => e.toJson()).toList());
        }));

    router.post('/api/doan', (Request request) async {
      final data = await body(request);
      return guard(() {
        final station = asString(data['station_code']).toUpperCase();
        if (station.isEmpty) return error('Chưa chọn kho cho đoàn.', 400);
        requireStation(request, station);
        return json(service.createCrew(data, stationCode: station).toJson());
      });
    });

    router.get('/api/doan/<id>', (Request request, String id) => guard(() {
          final crew = _crewOr404(request, id);
          if (crew == null) return error('Không tìm thấy đoàn.', 404);
          return json(crew.toJson());
        }));

    router.post('/api/doan/<id>', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.updateCrew(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>', (Request request, String id) => guard(() {
          if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
          repo.softDelete('doan', id);
          return json({'ok': true});
        }));

    // --------------------------------------------------------- bảng mức lương
    router.get('/api/doan/<id>/bang-luong', (Request request, String id) => guard(() {
          if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
          return json(service.wageTable(id));
        }));

    router.post('/api/doan/<id>/giai-doan', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.savePhase(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>/giai-doan/<phaseId>',
        (Request request, String id, String phaseId) => guard(() {
              if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
              repo.softDelete('giai_doan_luong', phaseId);
              return json({'ok': true});
            }));

    router.post('/api/doan/<id>/muc-luong', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveBand(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>/muc-luong/<bandId>',
        (Request request, String id, String bandId) => guard(() {
              if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
              service.deleteBand(id, bandId);
              return json({'ok': true});
            }));

    router.post('/api/doan/<id>/gia-luong', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveRate(id, data).toJson());
      });
    });

    // ------------------------------------------------------------- nhân viên
    router.get('/api/doan/<id>/nhan-vien', (Request request, String id) => guard(() {
          if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
          final q = request.url.queryParameters;
          final list = repo.workers(
            id,
            status: q['status'] == null ? null : WorkerStatus.parse(q['status']),
            query: q['q'],
          );
          return json(list.map((e) => e.toJson()).toList());
        }));

    router.post('/api/doan/<id>/nhan-vien', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(request, id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveWorker(id, data).toJson());
      });
    });

    router.post('/api/nhan-vien/<workerId>/nghi-lam',
        (Request request, String workerId) async {
      final data = await body(request);
      return guard(() {
        _requireWorkerStation(request, workerId);
        return json(service
            .stopWorker(workerId, leaveDate: asTimeOrNull(data['leave_date']))
            .toJson());
      });
    });

    router.post('/api/nhan-vien/<workerId>/lam-lai',
        (Request request, String workerId) => guard(() {
              _requireWorkerStation(request, workerId);
              return json(service.resumeWorker(workerId).toJson());
            }));
  }

  /// Đoàn nếu tài khoản được xem, `null` nếu không có.
  ///
  /// Kiểm quyền theo kho của đoàn — không kiểm ở đây thì biết id là xem được
  /// dữ liệu kho khác.
  Crew? _crewOr404(Request request, String id) {
    final crew = repo.crewById(id);
    if (crew == null || crew.deleted) return null;
    requireStation(request, crew.stationCode);
    return crew;
  }

  void _requireWorkerStation(Request request, String workerId) {
    final worker = repo.workerById(workerId);
    if (worker == null) return; // để lớp nghiệp vụ báo "không tìm thấy"
    final crew = repo.crewById(worker.crewId);
    requireStation(request, crew?.stationCode);
  }
}
