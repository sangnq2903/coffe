import 'dart:async';
import 'dart:convert';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../db/repository.dart';
import '../scale/scale_service.dart';
import '../scale/win32_serial.dart';
import '../service/ticket_service.dart';
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
    this.scale,
    this.sync,
  });

  final ServerConfig config;
  final Repository repo;
  final ReadingBroker broker;
  final TicketService tickets;

  /// Chỉ có ở vai trò trạm cân.
  final ScaleService? scale;

  /// Chỉ có ở vai trò trạm cân.
  final SyncWorker? sync;

  Handler get handler {
    final router = Router();

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
      final list = repo.stations();
      if (list.isEmpty && config.isStation) {
        // Trạm chạy độc lập vẫn phải tự khai mình cho app thấy.
        return _json([_selfStation().toJson()]);
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

    // ------------------------------------------------------------ đầu cân
    router.get('/api/scale/ports', (Request request) async =>
        _json({'ports': await listSerialPorts()}));

    router.get('/api/scale/current', (Request request) {
      final stationCode =
          request.url.queryParameters['station'] ?? config.effectiveStationCode;
      final reading = broker.latestFor(stationCode) ??
          ScaleReading.disconnected(stationCode, error: 'Chưa có tín hiệu từ trạm này');
      return _json(reading.toJson());
    });

    router.get('/api/scale/readings', (Request request) =>
        _json(broker.snapshot.values.map((e) => e.toJson()).toList()));

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
      final goods = existing == null
          ? GoodsType.create(
              code: asString(body['code'], fallback: name.toUpperCase()),
              name: name,
              unit: asString(body['unit'], fallback: 'kg'),
              defaultYieldRatio: ratio,
              sortOrder: asInt(body['sort_order']),
            )
          : existing.copyWith(
              code: asString(body['code'], fallback: existing.code),
              name: name,
              unit: asString(body['unit'], fallback: existing.unit),
              defaultYieldRatio: ratio,
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
      return _json(repo
          .tickets(
            stationCode: q['station'],
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

    router.get('/api/tickets/pending-by-plate', (Request request) {
      final plate = request.url.queryParameters['plate'] ?? '';
      if (plate.isEmpty) return _error('Thiếu tham số plate.', 400);
      final ticket = repo.pendingTicketForPlate(
        plate,
        stationCode: request.url.queryParameters['station'],
      );
      return _json(ticket?.toJson() ?? <String, Object?>{});
    });

    router.post('/api/tickets', (Request request) async {
      final body = await _body(request);
      return _guard(() => _json(tickets.create(body).toJson()));
    });

    router.get('/api/tickets/<id>', (Request request, String id) {
      final ticket = repo.ticketById(id);
      if (ticket == null) return _error('Không tìm thấy phiếu cân.', 404);
      return _json(ticket.toJson());
    });

    router.post('/api/tickets/<id>', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() => _json(tickets.update(id, body).toJson()));
    });

    router.post('/api/tickets/<id>/second-weigh', (Request request, String id) async {
      final body = await _body(request);
      return _guard(() => _json(tickets.completeSecondWeigh(id, body).toJson()));
    });

    router.post('/api/tickets/<id>/cancel', (Request request, String id) async {
      final body = await _body(request);
      return _guard(
          () => _json(tickets.cancel(id, reason: asStringOrNull(body['reason'])).toJson()));
    });

    router.delete('/api/tickets/<id>', (Request request, String id) {
      repo.softDeleteTicket(id);
      return _json({'ok': true});
    });

    // ------------------------------------------------------------ đồng bộ
    router.get('/api/sync/pull', (Request request) {
      final q = request.url.queryParameters;
      final payload = repo.changesSince(
        asTimeOrNull(q['since']),
        stationCode: q['station'],
      );
      return _json(payload.toJson());
    });

    router.post('/api/sync/push', (Request request) async {
      final body = await _body(request);
      final payload = SyncPayload.fromJson(body);
      // Dữ liệu đến từ trạm khác không được đánh dấu "cần đẩy tiếp", tránh vòng
      // lặp đồng bộ vô tận giữa hai máy.
      final applied = repo.applyPayload(payload, markDirty: false);
      return _json({
        'applied': applied,
        'server_time': timeToMillis(DateTime.now()),
      });
    });

    // ---------------------------------------------------------- WebSocket
    router.get('/ws/scale', _scaleSocketHandler());
    if (config.isCentral) {
      router.get('/ws/station', _stationUplinkHandler());
    }

    return router.call;
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
  Handler _scaleSocketHandler() => (Request request) {
        final requested = request.url.queryParameters['station']?.toUpperCase();
        final stationCode = (requested == null || requested.isEmpty)
            ? config.effectiveStationCode
            : requested;
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

  // ------------------------------------------------------------------ tiện ích

  static Future<Map<String, Object?>> _body(Request request) async {
    final text = await request.readAsString();
    if (text.trim().isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : {};
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
