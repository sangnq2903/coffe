import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/payroll_repository.dart';
import '../service/payroll_service.dart';

/// Các đường dẫn API của module chấm công.
///
/// Đăng ký thẳng vào [Router] của máy chủ chính nên đường dẫn vẫn phẳng, chỉ
/// tách file để phần cân xe và phần chấm công không dồn vào một chỗ.
///
/// Khác với phần cân xe, các đường dẫn ở đây **không giới hạn theo kho**: đoàn
/// thuộc về công ty và người trong đoàn chuyển kho qua lại, nên bảng lương phải
/// cộng được xuyên kho. Vẫn bắt đăng nhập như mọi đường dẫn khác.
class PayrollRouter {
  PayrollRouter({
    required this.repo,
    required this.service,
    required this.json,
    required this.error,
    required this.guard,
    required this.body,
    required this.user,
  });

  final PayrollRepository repo;
  final PayrollService service;

  // Các tiện ích dùng chung, nhận từ router chính để hai bên trả lời giống nhau.
  final Response Function(Object? data) json;
  final Response Function(String message, int status) error;
  final Response Function(Response Function()) guard;
  final Future<Map<String, Object?>> Function(Request) body;

  /// Tài khoản đang đăng nhập — chỉ dùng để ghi ai chấm công, không phân quyền.
  final AppUser Function(Request) user;

  void attach(Router router) {
    // ------------------------------------------------------------------ đoàn
    router.get('/api/doan', (Request request) => guard(() {
          final list = repo.crews(
            includeClosed: request.url.queryParameters['all'] != '0',
          );
          return json(list.map((e) => e.toJson()).toList());
        }));

    router.post('/api/doan', (Request request) async {
      final data = await body(request);
      return guard(() => json(service.createCrew(data).toJson()));
    });

    router.get('/api/doan/<id>', (Request request, String id) => guard(() {
          final crew = _crewOr404(id);
          if (crew == null) return error('Không tìm thấy đoàn.', 404);
          return json(crew.toJson());
        }));

    router.post('/api/doan/<id>', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.updateCrew(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          repo.softDelete('doan', id);
          return json({'ok': true});
        }));

    // --------------------------------------------------------- bảng mức lương
    router.get('/api/doan/<id>/bang-luong', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          return json(service.wageTable(id));
        }));

    router.post('/api/doan/<id>/giai-doan', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.savePhase(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>/giai-doan/<phaseId>',
        (Request request, String id, String phaseId) => guard(() {
              if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
              repo.softDelete('giai_doan_luong', phaseId);
              return json({'ok': true});
            }));

    router.post('/api/doan/<id>/muc-luong', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveBand(id, data).toJson());
      });
    });

    router.delete('/api/doan/<id>/muc-luong/<bandId>',
        (Request request, String id, String bandId) => guard(() {
              if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
              service.deleteBand(id, bandId);
              return json({'ok': true});
            }));

    router.post('/api/doan/<id>/gia-luong', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveRate(id, data).toJson());
      });
    });

    // ------------------------------------------------------------- nhân viên
    router.get('/api/doan/<id>/nhan-vien', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          final q = request.url.queryParameters;
          final list = repo.workers(
            id,
            status: q['status'] == null ? null : WorkerStatus.parse(q['status']),
            query: q['q'],
            stationCode: q['kho'],
          );
          return json(list.map((e) => e.toJson()).toList());
        }));

    router.post('/api/doan/<id>/nhan-vien', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveWorker(id, data).toJson());
      });
    });

    // Chuyển một hoặc nhiều người sang kho khác, có hiệu lực từ bây giờ.
    // Những ngày đã chấm công vẫn giữ kho ghi lúc đó.
    router.post('/api/doan/<id>/chuyen-kho', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        final ids = (data['worker_ids'] as List?)?.map((e) => e.toString()).toList() ??
            [if (asStringOrNull(data['worker_id']) != null) asString(data['worker_id'])];
        final moved = service.transferWorkers(
          crewId: id,
          workerIds: ids,
          stationCode: asString(data['station_code']),
        );
        return json(moved.map((e) => e.toJson()).toList());
      });
    });

    // -------------------------------------------------------------- sổ tiền
    router.get('/api/doan/<id>/tien', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          final q = request.url.queryParameters;
          final now = DateTime.now();
          return json(service.crewMoney(
            id,
            month: DateTime(
              asInt(q['year'], fallback: now.year),
              asInt(q['month'], fallback: now.month),
            ),
          ));
        }));

    router.get('/api/doan/<id>/nhan-vien/<workerId>/tien',
        (Request request, String id, String workerId) => guard(() {
              if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
              return json(service.moneySheet(id, workerId));
            }));

    // Thử một lần ứng trước khi ghi, để màn hình cảnh báo ngay lúc đang nhập.
    router.post('/api/doan/<id>/so-tien/kiem-tra', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.previewAdvance(
          crewId: id,
          workerId: asString(data['worker_id']),
          amount: asDouble(data['amount']),
          date: asTimeOrNull(data['date']),
          ignoreEntryId: asStringOrNull(data['id']),
        ));
      });
    });

    router.post('/api/doan/<id>/so-tien', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.saveEntry(id, data, createdBy: user(request).username));
      });
    });

    router.delete('/api/doan/<id>/so-tien/<entryId>',
        (Request request, String id, String entryId) => guard(() {
              if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
              return json(service.deleteEntry(id, entryId));
            }));

    // ------------------------------------------- báo cáo và quyết toán mùa
    router.get('/api/doan/<id>/bao-cao/thang', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          final q = request.url.queryParameters;
          final now = DateTime.now();
          return json(service.monthReport(
            id,
            asInt(q['year'], fallback: now.year),
            asInt(q['month'], fallback: now.month),
          ));
        }));

    router.get('/api/doan/<id>/bao-cao/mua', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          return json(service.seasonReport(id));
        }));

    // Chốt mùa chỉ đóng đoàn để mở cửa cho quyết toán, không tự trả tiền.
    router.post('/api/doan/<id>/chot-mua', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        return json(service.closeSeason(id, endDate: asTimeOrNull(data['end_date'])));
      });
    });

    router.post('/api/doan/<id>/mo-lai-mua',
        (Request request, String id) => guard(() {
              if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
              return json(service.reopenSeason(id));
            }));

    router.post('/api/doan/<id>/quyet-toan', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        // Không truyền danh sách nghĩa là quyết toán cho cả đoàn.
        final ids = (data['worker_ids'] as List?)?.map((e) => e.toString()).toList();
        return json(service.settleSeason(
          crewId: id,
          workerIds: ids,
          date: asTimeOrNull(data['date']),
          createdBy: user(request).username,
        ));
      });
    });

    router.post('/api/nhan-vien/<workerId>/nghi-lam',
        (Request request, String workerId) async {
      final data = await body(request);
      return guard(() => json(service
          .stopWorker(workerId, leaveDate: asTimeOrNull(data['leave_date']))
          .toJson()));
    });

    // ------------------------------------------------------------ chấm công
    router.get('/api/doan/<id>/cham-cong', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          final ngay = asTimeOrNull(request.url.queryParameters['date']) ?? DateTime.now();
          return json(service.daySheet(id, ngay));
        }));

    router.post('/api/doan/<id>/cham-cong', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        final ngay = asTimeOrNull(data['date']);
        if (ngay == null) return error('Chưa chọn ngày chấm công.', 400);

        // Nhận `{id: có đi làm}`. Giá trị đi qua JSON nên có thể là bool, số
        // hay chuỗi — quy hết về bool để client viết kiểu nào cũng chạy.
        final raw = data['marks'];
        if (raw is! Map) return error('Thiếu danh sách chấm công.', 400);
        final marks = {
          for (final e in raw.entries) e.key.toString(): asBool(e.value),
        };
        if (marks.isEmpty) return error('Chưa chấm cho ai cả.', 400);

        // `{id: số giờ nghỉ}` — chỉ cho người đi làm nhưng không đủ ca.
        final rawHours = data['hours_off'];
        final hoursOff = rawHours is! Map
            ? const <String, double>{}
            : {for (final e in rawHours.entries) e.key.toString(): asDouble(e.value)};

        return json(service.markDay(
          crewId: id,
          date: ngay,
          marks: marks,
          hoursOff: hoursOff,
          note: asStringOrNull(data['note']),
          createdBy: user(request).username,
        ));
      });
    });

    router.get('/api/doan/<id>/cham-cong/thang', (Request request, String id) => guard(() {
          if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
          final q = request.url.queryParameters;
          final now = DateTime.now();
          return json(service.monthSheet(
            id,
            asInt(q['year'], fallback: now.year),
            asInt(q['month'], fallback: now.month),
          ));
        }));

    // Nút tính lại quá khứ. Bình thường ngày đã chấm giữ nguyên mức lương lúc
    // chấm, nên phải bấm riêng mới đổi.
    router.post('/api/doan/<id>/cham-cong/tinh-lai', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        if (_crewOr404(id) == null) return error('Không tìm thấy đoàn.', 404);
        final now = DateTime.now();
        return json(service.recalcMonth(
          crewId: id,
          year: asInt(data['year'], fallback: now.year),
          month: asInt(data['month'], fallback: now.month),
        ));
      });
    });

    router.post('/api/nhan-vien/<workerId>/lam-lai',
        (Request request, String workerId) =>
            guard(() => json(service.resumeWorker(workerId).toJson())));
  }

  Crew? _crewOr404(String id) {
    final crew = repo.crewById(id);
    return crew == null || crew.deleted ? null : crew;
  }
}
