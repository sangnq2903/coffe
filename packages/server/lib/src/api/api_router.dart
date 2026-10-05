import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_service.dart';
import '../backup/auto_backup.dart';
import '../backup/data_transfer.dart';
import '../config.dart';
import '../db/repository.dart';
import '../printer/printer_lookup.dart';
import '../scale/scale_service.dart';
import '../scale/win32_serial.dart';
import '../service/payroll_service.dart';
import '../service/ticket_service.dart';
import '../service/trade_service.dart';
import 'change_broker.dart';
import 'payroll_router.dart';
import 'trade_router.dart';
import '../sync/sync_worker.dart';
import 'reading_broker.dart';

const String appVersion = '0.1.0';

/// Toàn bộ REST API và WebSocket của server.
class ApiRouter {
  ApiRouter({
    required this.config,
    required this.repo,
    required this.broker,
    required this.tickets,
    required this.payroll,
    required this.trades,
    required this.auth,
    required this.duLieu,
    required this.tuDong,
    required this.changes,
    this.scale,
    this.sync,
  });

  final ServerConfig config;
  final Repository repo;
  final ReadingBroker broker;
  final TicketService tickets;
  final PayrollService payroll;
  final TradeService trades;
  final AuthService auth;

  /// Xuất và nhập cơ sở dữ liệu.
  final DataTransferService duLieu;

  /// Tự động sao lưu ra thư mục trên ổ đĩa của máy chủ.
  final AutoBackupService tuDong;

  /// Phát tín hiệu "dữ liệu vừa đổi" cho mọi máy đang mở app.
  final ChangeBroker changes;

  /// Chỉ có ở vai trò trạm cân.
  final ScaleService? scale;

  /// Chỉ có ở vai trò trạm cân.
  final SyncWorker? sync;

  Handler get handler {
    final router = Router();

    // ----------------------------------------------------------- đăng nhập
    router.get('/api/auth/status', (Request request) => _json({
          'can_tao_tai_khoan_chu': auth.needsSetup,
          'role': config.role.value,
          'station_code': config.effectiveStationCode,
          'station_name': config.stationName,
          'version': appVersion,
        }));

    router.post('/api/auth/setup', (Request request) async {
      final body = await _body(request);
      return _guard(() {
        final user = auth.createFirstAdmin(
          username: asString(body['username']),
          fullName: asString(body['full_name']),
          password: asString(body['password']),
        );
        return _json({'token': auth.issueToken(user), 'user': user.toJson()});
      });
    });

    router.post('/api/auth/login', (Request request) async {
      final body = await _body(request);
      return _guard(() {
        final user = auth.authenticate(
          asString(body['username']),
          asString(body['password']),
        );
        return _json({'token': auth.issueToken(user), 'user': user.toJson()});
      });
    });

    router.get('/api/auth/me', (Request request) => _json(_user(request).toJson()));

    router.post('/api/auth/doi-mat-khau', (Request request) async {
      final body = await _body(request);
      return _guard(() {
        auth.changePassword(
          user: _user(request),
          oldPassword: asString(body['mat_khau_cu']),
          newPassword: asString(body['mat_khau_moi']),
        );
        return _json({'ok': true});
      });
    });

    // ------------------------------------------------------ quản lý tài khoản
    router.get('/api/users', (Request request) => _guard(() {
          _requireAdmin(request);
          return _json(repo
              .users(includeInactive: request.url.queryParameters['all'] == '1')
              .map((e) => e.toJson())
              .toList());
        }));

    router.post('/api/users', (Request request) async {
      final body = await _body(request);
      return _guard(() {
        _requireAdmin(request);
        final user = auth.createUser(
          username: asString(body['username']),
          fullName: asString(body['full_name']),
          password: asString(body['password']),
          role: UserRole.parse(body['role']),
          stationScope: AppUser.fromJson({
            'station_scope': body['station_scope'],
            'updated_at': 0,
          }).stationScope,
          machineAccount: asBool(body['machine_account']),
        );
        return _json(user.toJson());
      });
    });

    router.post('/api/users/<id>/mat-khau', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() {
        _requireAdmin(request);
        final target = repo.userById(id);
        if (target == null) return _error('Không tìm thấy tài khoản.', 404);
        auth.resetPassword(target: target, newPassword: asString(body['mat_khau_moi']));
        return _json({'ok': true});
      });
    });

    router.delete('/api/users/<id>', (Request request, String id) => _guard(() {
          _requireAdmin(request);
          // Không cho tự khoá chính mình rồi không ai vào được nữa.
          if (_user(request).id == id) {
            return _error('Không thể xoá chính tài khoản đang đăng nhập.', 400);
          }
          repo.softDeleteUser(id);
          return _json({'ok': true});
        }));

    // ------------------------------------------------------------- hệ thống
    router.get('/api/health', (Request request) => _json({
          'role': config.role.value,
          'station_code': config.effectiveStationCode,
          'station_name': config.stationName,
          'version': appVersion,
          'scale_connected': scale?.connected ?? false,
          'scale_port': config.scale.simulate ? 'GIẢ LẬP' : config.scale.port,
          'time': timeToMillis(DateTime.now()),
        }));

    router.get('/api/stations', (Request request) {
      final user = _user(request);
      var list = repo.stations().where((s) => user.canAccessStation(s.code)).toList();
      if (list.isEmpty && config.isStation && user.canAccessStation(config.effectiveStationCode)) {
        // Trạm chạy độc lập vẫn phải tự khai mình cho app thấy.
        list = [_selfStation()];
      }
      return _json(list.map((e) => e.toJson()).toList());
    });

    router.get('/api/sync/status', (Request request) => _json(_syncStatus().toJson()));

    router.post('/api/sync/now', (Request request) async {
      final worker = sync;
      if (worker == null) {
        return _error('Máy chủ trung tâm không cần đồng bộ lên đâu cả.', 400);
      }
      await worker.syncOnce();
      return _json(_syncStatus().toJson());
    });

    // ------------------------------------------------------------- máy in
    router.get('/api/printer/mac-dinh', (Request request) async {
      final name = await defaultPrinterName();
      return _json({'name': name, 'available': name != null});
    });

    // ------------------------------------------------------------ đầu cân
    router.get('/api/scale/ports', (Request request) async =>
        _json({'ports': await listSerialPorts()}));

    router.get('/api/scale/current', (Request request) {
      final stationCode =
          request.url.queryParameters['station'] ?? config.effectiveStationCode;
      return _guard(() {
        _requireStation(request, stationCode);
        final reading = broker.latestFor(stationCode) ??
            ScaleReading.disconnected(stationCode, error: 'Chưa có tín hiệu từ trạm này');
        return _json(reading.toJson());
      });
    });

    router.get('/api/scale/readings', (Request request) {
      final user = _user(request);
      return _json(broker.snapshot.values
          .where((r) => user.canAccessStation(r.stationCode))
          .map((e) => e.toJson())
          .toList());
    });

    // --------------------------------------------------------- khách hàng
    router.get('/api/customers', (Request request) {
      final q = request.url.queryParameters;
      return _json(repo
          .customers(query: q['q'], includeInactive: q['all'] == '1')
          .map((e) => e.toJson())
          .toList());
    });

    router.post('/api/customers', (Request request) async {
      final body = await _body(request);
      final name = asString(body['name']).trim();
      if (name.isEmpty) return _error('Tên khách hàng không được để trống.', 400);
      final id = asStringOrNull(body['id']);
      final existing = id == null ? null : repo.customerById(id);
      final customer = existing == null
          ? Customer.create(
              name: name,
              code: asString(body['code']),
              phone: asStringOrNull(body['phone']),
              address: asStringOrNull(body['address']),
              taxCode: asStringOrNull(body['tax_code']),
              note: asStringOrNull(body['note']),
            )
          : existing.copyWith(
              name: name,
              code: asString(body['code'], fallback: existing.code),
              phone: asStringOrNull(body['phone']),
              address: asStringOrNull(body['address']),
              taxCode: asStringOrNull(body['tax_code']),
              note: asStringOrNull(body['note']),
              active: asBool(body['active'], fallback: existing.active),
            );
      return _json(repo.upsertCustomer(customer).toJson());
    });

    router.delete('/api/customers/<id>', (Request request, String id) {
      repo.softDeleteCustomer(id);
      return _json({'ok': true});
    });

    // ----------------------------------------------------------------- xe
    router.get('/api/vehicles', (Request request) {
      final q = request.url.queryParameters;
      return _json(repo
          .vehicles(query: q['q'], includeInactive: q['all'] == '1')
          .map((e) => e.toJson())
          .toList());
    });

    router.post('/api/vehicles', (Request request) async {
      final body = await _body(request);
      final plate = asString(body['plate_no']).trim();
      if (plate.isEmpty) return _error('Biển số xe không được để trống.', 400);
      final id = asStringOrNull(body['id']);
      final existing = id == null ? null : repo.vehicleById(id);
      if (existing == null) {
        final duplicate = repo.vehicleByPlate(plate);
        if (duplicate != null) {
          return _error('Biển số ${duplicate.plateNo} đã có trong danh mục.', 400);
        }
      }
      final vehicle = existing == null
          ? Vehicle.create(
              plateNo: plate,
              customerId: asStringOrNull(body['customer_id']),
              driverName: asStringOrNull(body['driver_name']),
              driverPhone: asStringOrNull(body['driver_phone']),
              tareWeight: asDoubleOrNull(body['tare_weight']),
              note: asStringOrNull(body['note']),
            )
          : existing.copyWith(
              plateNo: plate,
              customerId: asStringOrNull(body['customer_id']),
              driverName: asStringOrNull(body['driver_name']),
              driverPhone: asStringOrNull(body['driver_phone']),
              tareWeight: asDoubleOrNull(body['tare_weight']),
              note: asStringOrNull(body['note']),
              active: asBool(body['active'], fallback: existing.active),
            );
      return _json(repo.upsertVehicle(vehicle).toJson());
    });

    router.delete('/api/vehicles/<id>', (Request request, String id) {
      repo.softDeleteVehicle(id);
      return _json({'ok': true});
    });

    // ---------------------------------------------------------- loại hàng
    router.get('/api/goods-types', (Request request) => _json(repo
        .goodsTypes(includeInactive: request.url.queryParameters['all'] == '1')
        .map((e) => e.toJson())
        .toList()));

    router.post('/api/goods-types', (Request request) async {
      final body = await _body(request);
      final name = asString(body['name']).trim();
      if (name.isEmpty) return _error('Tên loại hàng không được để trống.', 400);
      final ratio = asDouble(body['default_yield_ratio'], fallback: 100);
      if (ratio < 0 || ratio > 100) {
        return _error('Tỷ lệ thành phẩm mặc định phải trong khoảng 0–100%.', 400);
      }
      final id = asStringOrNull(body['id']);
      final existing = id == null ? null : repo.goodsTypeById(id);

      // Định mức chi phí đ/kg: không gửi thì giữ nguyên, gửi thì thay cả bảng.
      final chiPhi = body.containsKey('cost_items')
          ? CostItem.listFromJson(body['cost_items'])
          : existing?.costItems ?? const <CostItem>[];
      for (final c in chiPhi) {
        if (c.perKg < 0) {
          return _error('Khoản chi "${c.name}" không được âm.', 400);
        }
      }

      final goods = existing == null
          ? GoodsType.create(
              code: asString(body['code'], fallback: name.toUpperCase()),
              name: name,
              unit: asString(body['unit'], fallback: 'kg'),
              defaultYieldRatio: ratio,
              costItems: chiPhi,
              sortOrder: asInt(body['sort_order']),
            )
          : existing.copyWith(
              code: asString(body['code'], fallback: existing.code),
              name: name,
              unit: asString(body['unit'], fallback: existing.unit),
              defaultYieldRatio: ratio,
              costItems: chiPhi,
              sortOrder: asInt(body['sort_order'], fallback: existing.sortOrder),
              active: asBool(body['active'], fallback: existing.active),
            );
      return _json(repo.upsertGoodsType(goods).toJson());
    });

    router.delete('/api/goods-types/<id>', (Request request, String id) {
      repo.softDeleteGoodsType(id);
      return _json({'ok': true});
    });

    // ----------------------------------------------------------- phiếu cân
    router.get('/api/tickets', (Request request) {
      final q = request.url.queryParameters;
      return _guard(() {
        if (q['station'] != null) _requireStation(request, q['station']);
        return _json(repo
            .tickets(
              stationCode: q['station'],
              allowedStations: _scope(request),
              status: q['status'] == null ? null : TicketStatus.parse(q['status']),
              query: q['q'],
              from: asTimeOrNull(q['from']),
              to: asTimeOrNull(q['to']),
              limit: asInt(q['limit'], fallback: 200),
              offset: asInt(q['offset']),
            )
            .map((e) => e.toJson())
            .toList());
      });
    });

    router.get('/api/tickets/pending-by-plate', (Request request) {
      final plate = request.url.queryParameters['plate'] ?? '';
      if (plate.isEmpty) return _error('Thiếu tham số plate.', 400);
      final station = request.url.queryParameters['station'];
      return _guard(() {
        _requireStation(request, station ?? config.effectiveStationCode);
        final ticket = repo.pendingTicketForPlate(plate, stationCode: station);
        return _json(ticket?.toJson() ?? <String, Object?>{});
      });
    });

    router.post('/api/tickets', (Request request) async {
      final body = await _body(request);
      return _guard(() {
        final station = asString(body['station_code'], fallback: config.effectiveStationCode);
        _requireStation(request, station);
        // Người lập phiếu lấy từ tài khoản đang đăng nhập, không nhận từ client:
        // để trống hay gõ tên người khác đều không được nữa.
        body['created_by'] = _user(request).displayName;
        return _json(tickets.create(body).toJson());
      });
    });

    router.get('/api/tickets/<id>', (Request request, String id) => _guard(() {
          final ticket = repo.ticketById(id);
          if (ticket == null) return _error('Không tìm thấy phiếu cân.', 404);
          _requireStation(request, ticket.stationCode);
          return _json(ticket.toJson());
        }));

    router.post('/api/tickets/<id>', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() {
        _requireTicketStation(request, id);
        return _json(tickets.update(id, body).toJson());
      });
    });

    router.post('/api/tickets/<id>/second-weigh', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() {
        _requireTicketStation(request, id);
        return _json(tickets.completeSecondWeigh(id, body).toJson());
      });
    });

    router.post('/api/tickets/<id>/cancel', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() {
        _requireTicketStation(request, id);
        return _json(tickets.cancel(id, reason: asStringOrNull(body['reason'])).toJson());
      });
    });

    router.delete('/api/tickets/<id>', (Request request, String id) => _guard(() {
          _requireTicketStation(request, id);
          repo.softDeleteTicket(id);
          return _json({'ok': true});
        }));

    // ------------------------------------------------------------ đồng bộ
    router.get('/api/sync/pull', (Request request) {
      final q = request.url.queryParameters;
      final payload = repo.changesSince(
        asTimeOrNull(q['since']),
        stationCode: q['station'],
        allowedStations: _scope(request),
      );
      return _json(payload.toJson());
    });

    router.post('/api/sync/push', (Request request) async {
      final body = await _body(request);
      final payload = SyncPayload.fromJson(body);
      return _guard(() {
        // Trạm chỉ được đẩy lên phiếu của kho mình. Không kiểm ở đây thì một máy
        // trạm bị chiếm quyền có thể ghi đè phiếu cân của kho khác.
        for (final ticket in payload.tickets) {
          _requireStation(request, ticket.stationCode);
        }
        // Dữ liệu đến từ trạm khác không được đánh dấu "cần đẩy tiếp", tránh vòng
        // lặp đồng bộ vô tận giữa hai máy.
        final applied = repo.applyPayload(payload, markDirty: false);
        return _json({
          'applied': applied,
          'server_time': timeToMillis(DateTime.now()),
        });
      });
    });

    // ---------------------------------------------------------- WebSocket
    // Module chấm công đăng ký đường dẫn của nó vào cùng router này.
    PayrollRouter(
      repo: repo.payroll,
      service: payroll,
      json: _json,
      error: _error,
      guard: _guard,
      body: _body,
      user: _user,
    ).attach(router);

    TradeRouter(
      service: trades,
      json: _json,
      error: _error,
      guard: _guard,
      body: _body,
      user: _user,
    ).attach(router);

    // ------------------------------------------------------ xuất/nhập dữ liệu
    //
    // Chỉ tài khoản chủ. File xuất ra là **toàn bộ** cơ sở dữ liệu — lương từng
    // người, sổ mua bán, giá vốn, và cả chuỗi băm mật khẩu của mọi tài khoản.
    // Quyền tải nó về phải bằng quyền xem thứ nặng nhất bên trong, chứ không
    // phải quyền của người quản lý một kho.
    router.get('/api/du-lieu/tom-tat', (Request request) {
      final chan = _chanKhongPhaiChu(request);
      return chan ?? _guard(() => _json(duLieu.tomTat().toJson()));
    });

    router.get('/api/du-lieu/xuat', (Request request) {
      final chan = _chanKhongPhaiChu(request);
      if (chan != null) return chan;
      return _guard(() {
        final kq = duLieu.xuat(matKhau: _matKhau(request));
        return Response.ok(
          kq.duLieu,
          headers: {
            'content-type': 'application/octet-stream',
            'content-disposition': 'attachment; filename="${kq.tenFile}"',
            'content-length': '${kq.duLieu.length}',
            // Tên file có dấu thời gian nên không đụng nhau, nhưng vẫn cấm
            // cache: bản xuất là ảnh chụp một thời điểm, dùng lại bản cũ trong
            // cache là cầm nhầm dữ liệu của hôm trước mà không biết.
            'cache-control': 'no-store',
          },
        );
      });
    });

    router.post('/api/du-lieu/xem-truoc', (Request request) async {
      final chan = _chanKhongPhaiChu(request);
      if (chan != null) return chan;
      final bytes = await _bytes(request);
      return _guard(() => _json(
            duLieu.xemTruoc(bytes, matKhau: _matKhau(request)).toJson(),
          ));
    });

    router.post('/api/du-lieu/nhap', (Request request) async {
      final chan = _chanKhongPhaiChu(request);
      if (chan != null) return chan;
      final bytes = await _bytes(request);
      return _guard(() => _json(
            duLieu.nhap(bytes, matKhau: _matKhau(request)).toJson(),
          ));
    });

    // Tự động sao lưu: thiết lập nằm trên máy chủ vì đường dẫn là thư mục
    // trên ổ đĩa của chính máy đó, không phải của cái máy đang mở trình duyệt.
    router.get('/api/du-lieu/tu-dong', (Request request) {
      final chan = _chanKhongPhaiChu(request);
      return chan ??
          _guard(() => _json({
                ...tuDong.caiDat.toJson(),
                ...tuDong.state.toJson(),
              }));
    });

    router.post('/api/du-lieu/tu-dong', (Request request) async {
      final chan = _chanKhongPhaiChu(request);
      if (chan != null) return chan;
      final body = await _body(request);
      return _guard(() {
        final moi = tuDong.luuCaiDat(body);
        return _json({...moi.toJson(), ...tuDong.state.toJson()});
      });
    });

    router.post('/api/du-lieu/tu-dong/chay', (Request request) async {
      final chan = _chanKhongPhaiChu(request);
      if (chan != null) return chan;
      try {
        final ten = await tuDong.chayNgay();
        // Trả về đủ cả thiết lập lẫn tình trạng, giống hai cửa kia. Thiếu phần
        // thiết lập thì màn hình đọc `bat` ra rỗng và hiện thành "đang tắt"
        // ngay sau khi vừa chụp xong.
        return _json({
          'ok': true,
          'ten': ten,
          ...tuDong.caiDat.toJson(),
          ...tuDong.state.toJson(),
        });
      } on BusinessException catch (e) {
        return _error(e.message, 400);
      } catch (e) {
        return _error('Sao lưu hỏng: $e', 500);
      }
    });

    router.get('/ws/thay-doi', _changeSocketHandler());
    router.get('/ws/scale', _scaleSocketHandler());
    if (config.isCentral) {
      router.get('/ws/station', _stationUplinkHandler());
    }

    // Lưới đỡ cuối cùng. `_guard` chỉ bọc được phần đồng bộ của mỗi tuyến, mà
    // việc đọc thân yêu cầu lại nằm trước đó và là bất đồng bộ — lỗi ném từ đấy
    // rơi thẳng ra ngoài và biến một yêu cầu gửi sai thành "Internal Server
    // Error". Bọc ở đây thì mọi tuyến, kể cả tuyến viết sau này, đều trả về mã
    // đúng mà không phải nhớ tự bọc.
    return (Request request) async {
      try {
        return await router.call(request);
      } on BusinessException catch (e) {
        return _error(e.message, 400);
      } on AuthException catch (e) {
        return _error(e.message, e.statusCode);
      }
    };
  }

  Station _selfStation() => Station(
        code: config.effectiveStationCode,
        name: config.stationName.isEmpty ? config.effectiveStationCode : config.stationName,
        warehouseName: config.warehouseName,
        address: config.address,
        baseUrl: config.publicBaseUrl,
        online: true,
        lastSeenAt: DateTime.now(),
        scaleConnected: scale?.connected ?? false,
        scalePort: config.scale.simulate ? 'GIẢ LẬP' : config.scale.port,
        updatedAt: DateTime.now(),
      );

  SyncStatus _syncStatus() => sync?.status ??
      SyncStatus(
        online: true,
        pendingPush: repo.pendingPushCount(),
        lastSyncAt: DateTime.now(),
      );

  /// `/ws/scale?station=KHO01` — luồng số cân realtime cho màn hình hiển thị.
  ///
  /// Máy chủ trung tâm giữ luồng của nhiều kho cùng lúc, nên bắt buộc phải lọc
  /// theo mã trạm; gửi tất cả sang một client sẽ làm màn hình nhảy số của kho
  /// khác.
  /// `/ws/thay-doi` — máy chủ báo về tên bảng vừa đổi để app tự tải lại.
  ///
  /// Chỉ gửi tên bảng, không gửi dữ liệu: app nhận được thì gọi lại đúng cửa
  /// API cũ, nơi luật phân quyền đã có sẵn và chỉ có một bản.
  Handler _changeSocketHandler() => (Request request) {
        // Người không phải chủ thì bỏ sổ mua bán ra khỏi tín hiệu: họ không mở
        // được màn hình đó, báo cho họ chỉ tổ bắt tải lại vô ích — và cũng là
        // để lộ rằng ai đó đang ghi sổ.
        final laChu = _user(request).isOwner;
        return webSocketHandler(
          (WebSocketChannel socket, _) => _bindChangeSocket(socket, laChu),
        )(request);
      };

  void _bindChangeSocket(WebSocketChannel socket, bool laChu) {
    final sub = changes.thayDoi.listen((bang) {
      final loc = laChu ? bang : bang.where((b) => b != 'giao_dich').toSet();
      if (loc.isEmpty) return;
      try {
        socket.sink.add(jsonEncode({
          'bang': loc.toList()..sort(),
          'luc': timeToMillis(DateTime.now()),
        }));
      } catch (_) {
        // Ống đã đóng; phần bên dưới sẽ dọn.
      }
    });

    socket.stream.listen(
      (_) {},
      onDone: sub.cancel,
      onError: (_) => sub.cancel(),
      cancelOnError: true,
    );
  }

  Handler _scaleSocketHandler() => (Request request) {
        final requested = request.url.queryParameters['station']?.toUpperCase();
        final stationCode = (requested == null || requested.isEmpty)
            ? config.effectiveStationCode
            : requested;
        if (!_user(request).canAccessStation(stationCode)) {
          return _error('Khong co quyen xem so can cua kho', 403);
        }
        return webSocketHandler(
          (WebSocketChannel socket, _) => _bindScaleSocket(socket, stationCode),
        )(request);
      };

  void _bindScaleSocket(WebSocketChannel socket, String stationCode) {
    StreamSubscription<ScaleReading>? sub;

    void send(ScaleReading reading) {
      try {
        socket.sink.add(jsonEncode(reading.toJson()));
      } catch (_) {
        sub?.cancel();
      }
    }

    // Client mở màn hình phải thấy số ngay, không phải chờ khung kế tiếp.
    send(broker.latestFor(stationCode) ??
        ScaleReading.disconnected(stationCode, error: 'Đang chờ tín hiệu đầu cân'));
    sub = broker.forStation(stationCode).listen(send);

    socket.stream.listen(
      (_) {},
      onDone: () => sub?.cancel(),
      onError: (_) => sub?.cancel(),
      cancelOnError: true,
    );
  }

  /// `/ws/station` — trạm cân kết nối vào máy chủ trung tâm để đẩy số cân
  /// realtime lên, nhờ đó máy ở văn phòng cũng xem được bàn cân của mọi kho.
  Handler _stationUplinkHandler() => webSocketHandler((WebSocketChannel socket, _) {
        String? stationCode;
        socket.stream.listen(
          (message) {
            try {
              final decoded = jsonDecode('$message');
              if (decoded is! Map) return;
              final map = decoded.cast<String, Object?>();
              switch (map['type']) {
                case 'register':
                  final station = Station.fromJson(map).copyWith(
                    online: true,
                    lastSeenAt: DateTime.now(),
                  );
                  stationCode = station.code;
                  repo.upsertStation(station);
                case 'reading':
                  final reading = ScaleReading.fromJson(map);
                  stationCode ??= reading.stationCode;
                  broker.publish(reading);
                case 'ping':
                  final code = stationCode;
                  if (code != null) {
                    final station = repo.stationByCode(code);
                    if (station != null) {
                      repo.upsertStation(
                          station.copyWith(online: true, lastSeenAt: DateTime.now()));
                    }
                  }
                  socket.sink.add(jsonEncode({'type': 'pong'}));
              }
            } catch (_) {
              // Bỏ qua gói hỏng, giữ kết nối để trạm không phải nối lại.
            }
          },
          onDone: () => _onStationGone(stationCode),
          onError: (_) => _onStationGone(stationCode),
          cancelOnError: true,
        );
      });

  void _onStationGone(String? stationCode) {
    if (stationCode == null) return;
    repo.markStationOffline(stationCode);
    broker.markStationOffline(stationCode);
  }

  /// Tài khoản của lời gọi hiện tại. Middleware đã gắn sẵn nên tới đây luôn có.
  static AppUser _user(Request request) => request.context['user']! as AppUser;

  /// Danh sách kho tài khoản được xem; `null` nghĩa là không giới hạn.
  static List<String>? _scope(Request request) {
    final user = _user(request);
    return user.seesAllStations ? null : user.stationScope;
  }

  /// Chỉ tài khoản quản lý tổng mới qua được.
  static void _requireAdmin(Request request) {
    if (!_user(request).isAdmin) {
      throw AuthException.forbidden('Chức năng này chỉ dành cho tài khoản quản lý tổng.');
    }
  }

  /// Chặn khi phiếu cân được thao tác không thuộc kho của tài khoản.
  void _requireTicketStation(Request request, String ticketId) {
    final ticket = repo.ticketById(ticketId);
    if (ticket == null) return; // để lớp nghiệp vụ báo "không tìm thấy phiếu"
    _requireStation(request, ticket.stationCode);
  }

  /// Chặn khi tài khoản với tay sang kho không thuộc phạm vi của mình.
  static void _requireStation(Request request, String? stationCode) {
    if (!_user(request).canAccessStation(stationCode)) {
      throw AuthException.forbidden(
        'Tài khoản của bạn không có quyền với kho "${stationCode ?? ''}".',
      );
    }
  }

  // ------------------------------------------------------------------ tiện ích

  /// Chặn mọi tài khoản không phải chủ. `null` nghĩa là được đi tiếp.
  Response? _chanKhongPhaiChu(Request request) => _user(request).isOwner
      ? null
      : _error('Xuất và nhập dữ liệu chỉ dành cho tài khoản chủ.', 403);

  /// Mật khẩu đi trong tiêu đề, mã hoá base64.
  ///
  /// Không đặt trong địa chỉ vì địa chỉ bị ghi nguyên vào nhật ký máy chủ. Và
  /// phải base64 vì tiêu đề HTTP chỉ chở được ký tự Latin — mật khẩu tiếng Việt
  /// có dấu mà nhét thẳng vào là hỏng ngay ở tầng mạng.
  static String? _matKhau(Request request) {
    final raw = request.headers['x-mat-khau'];
    if (raw == null || raw.isEmpty) return null;
    try {
      return utf8.decode(base64.decode(raw));
    } catch (_) {
      throw BusinessException('Ô mật khẩu gửi lên bị hỏng, thử nhập lại.');
    }
  }

  static Future<List<int>> _bytes(Request request) async {
    final bb = BytesBuilder(copy: false);
    await for (final phan in request.read()) {
      bb.add(phan);
    }
    if (bb.isEmpty) throw BusinessException('Chưa chọn file để nhập.');
    return bb.takeBytes();
  }

  static Future<Map<String, Object?>> _body(Request request) async {
    // Đọc và phân tích trong cùng một khối bắt lỗi. Thân yêu cầu hỏng — sai mã
    // ký tự, hay JSON viết thiếu — là lỗi của bên gửi, mà để rơi tự do thì nó
    // thành "Internal Server Error": người dùng tưởng máy chủ sập, còn người
    // sửa thì đi tìm nhầm chỗ.
    final String text;
    try {
      text = await request.readAsString();
    } on FormatException {
      throw BusinessException(
        'Nội dung gửi lên không phải chữ UTF-8 hợp lệ. Nếu gọi bằng dòng lệnh '
        'thì phải ghi rõ mã UTF-8 cho phần thân yêu cầu.',
      );
    }
    if (text.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded.cast<String, Object?>() : {};
    } on FormatException catch (e) {
      throw BusinessException('Nội dung gửi lên không phải JSON hợp lệ: ${e.message}');
    }
  }

  static Response _json(Object? data, {int status = 200}) => Response(
        status,
        body: jsonEncode(data),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static Response _error(String message, int status) =>
      _json({'error': message}, status: status);

  /// Chuyển lỗi nghiệp vụ thành HTTP 400 với thông điệp hiển thị được cho người
  /// dùng, thay vì trả 500 kèm stack trace.
  static Response _guard(Response Function() body) {
    try {
      return body();
    } on BusinessException catch (e) {
      return _error(e.message, 400);
    } on AuthException catch (e) {
      return _error(e.message, e.statusCode);
    }
  }
}

/// Cho phép app Flutter chạy ở cổng khác (chế độ phát triển) gọi được API.
Middleware corsMiddleware() => (Handler inner) => (Request request) async {
      const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
        'Access-Control-Max-Age': '86400',
      };
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };

/// Những đường dẫn ai cũng gọi được khi chưa đăng nhập.
///
/// Giữ danh sách này càng ngắn càng tốt: mỗi mục ở đây là một cánh cửa mở ra
/// Internet nội bộ mà không hỏi giấy tờ gì.
const Set<String> _publicApiPaths = {
  'api/health',
  'api/auth/status',
  'api/auth/setup',
  'api/auth/login',
};

/// Bắt buộc đăng nhập cho mọi lời gọi API và WebSocket.
///
/// File tĩnh của bản web vẫn để mở — nếu chặn cả chúng thì trình duyệt không
/// tải nổi chính màn hình đăng nhập.
Middleware authMiddleware(AuthService auth) => (Handler inner) => (Request request) async {
      final path = request.url.path;
      final needsAuth = path.startsWith('api/') || path.startsWith('ws/');
      if (!needsAuth || _publicApiPaths.contains(path)) {
        return inner(request);
      }

      final user = auth.userFromToken(_extractToken(request));
      if (user == null) {
        return Response(
          401,
          body: jsonEncode({'error': 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn.'}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }

      // Lưới an toàn: nếu chỗ nào đó trong router quên bọc kiểm quyền, lỗi vẫn
      // ra đúng mã 403 kèm thông báo đọc được, thay vì thành lỗi 500 trông như
      // máy chủ sập — vừa khó lần ra, vừa làm người dùng tưởng hệ thống hỏng.
      try {
        return await inner(request.change(context: {'user': user}));
      } on AuthException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.message}),
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    };

/// Lấy phiếu phiên từ tiêu đề Authorization, hoặc từ địa chỉ với WebSocket.
///
/// Trình duyệt không cho gắn tiêu đề vào kết nối WebSocket, nên đường đó buộc
/// phải truyền qua địa chỉ. Bù lại, phần ghi nhật ký đã được che chuỗi này.
String? _extractToken(Request request) {
  final header = request.headers['authorization'];
  if (header != null && header.toLowerCase().startsWith('bearer ')) {
    return header.substring(7).trim();
  }
  return request.url.queryParameters['token'];
}
