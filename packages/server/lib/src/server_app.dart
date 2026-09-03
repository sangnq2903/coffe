import 'dart:async';
import 'dart:io';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'api/api_router.dart';
import 'api/reading_broker.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/repository.dart';
import 'logging.dart';
import 'scale/scale_service.dart';
import 'service/ticket_service.dart';
import 'sync/station_uplink.dart';
import 'sync/sync_worker.dart';

/// Lắp ráp và chạy toàn bộ server theo vai trò trong cấu hình.
class ServerApp {
  ServerApp(this.config);

  final ServerConfig config;

  late final AppDatabase _database;
  late final Repository _repo;
  late final ReadingBroker _broker;
  late final TicketService _ticketService;
  ScaleService? _scale;
  SyncWorker? _sync;
  StationUplink? _uplink;
  HttpServer? _httpServer;
  StreamSubscription<ScaleReading>? _scaleSub;

  Future<void> start() async {
    final errors = config.validate();
    if (errors.isNotEmpty) {
      throw StateError('Cấu hình chưa hợp lệ:\n- ${errors.join("\n- ")}');
    }

    _database = AppDatabase.open(config.resolvedDatabasePath);
    _repo = Repository(_database);
    _repo.seedGoodsTypesIfEmpty();
    _broker = ReadingBroker();
    _ticketService = TicketService(_repo, defaultStationCode: config.effectiveStationCode);

    _registerSelf();

    if (config.isStation) {
      await _startStationParts();
    }

    final router = ApiRouter(
      config: config,
      repo: _repo,
      broker: _broker,
      tickets: _ticketService,
      scale: _scale,
      sync: _sync,
    );

    final handler = Pipeline()
        .addMiddleware(logRequests(logger: _logRequest))
        .addMiddleware(corsMiddleware())
        .addHandler(Cascade().add(router.handler).add(_webHandler()).handler);

    _httpServer = await shelf_io.serve(handler, config.host, config.port, shared: true);
    _printBanner();
  }

  Future<void> _startStationParts() async {
    final scale = ScaleService(
      config: config.scale,
      stationCode: config.effectiveStationCode,
    );
    _scale = scale;
    _scaleSub = scale.readings.listen(_broker.publish);
    await scale.start();

    // Trạng thái ban đầu để client mở màn hình là thấy ngay, không phải chờ
    // khung đầu tiên từ đầu cân.
    _broker.publish(scale.current);

    _sync = SyncWorker(config: config, repo: _repo)..start();
    _uplink = StationUplink(config: config, readings: scale.readings)..start();
  }

  /// Ghi chính máy này vào bảng trạm để màn hình chọn trạm luôn có ít nhất một
  /// lựa chọn, kể cả khi chưa trạm nào kết nối lên.
  void _registerSelf() {
    if (config.isCentral && config.stationCode.isEmpty) return;
    _repo.upsertStation(Station(
      code: config.effectiveStationCode,
      name: config.stationName.isEmpty ? config.effectiveStationCode : config.stationName,
      warehouseName: config.warehouseName,
      address: config.address,
      baseUrl: config.publicBaseUrl,
      online: true,
      lastSeenAt: DateTime.now(),
      scalePort: config.scale.simulate ? 'GIẢ LẬP' : config.scale.port,
      updatedAt: DateTime.now(),
    ));
  }

  /// Phục vụ bản build Flutter web ngay từ server, để máy ở kho chỉ cần mở
  /// trình duyệt vào địa chỉ Tailscale là dùng được, không phải cài gì thêm.
  Handler _webHandler() {
    final root = config.resolvedWebRoot;
    final indexFile = File(p.join(root, 'index.html'));
    if (!indexFile.existsSync()) {
      return (Request request) => Response.notFound(
            'Chưa có giao diện web tại "$root".\n'
            'Hãy chạy: flutter build web  (trong packages/app) '
            'rồi chép thư mục build/web vào đó.',
          );
    }
    final static = createStaticHandler(root, defaultDocument: 'index.html');
    return (Request request) async {
      final response = await static(request);
      if (response.statusCode != 404) return _noCacheForEntryPoints(request, response);
      // Flutter web dùng định tuyến phía client: mọi đường dẫn lạ phải trả về
      // index.html thay vì 404, nếu không bấm F5 giữa chừng sẽ trắng trang.
      if (request.url.path.startsWith('api/') || request.url.path.startsWith('ws/')) {
        return response;
      }
      return Response.ok(
        indexFile.openRead(),
        headers: {
          'content-type': 'text/html; charset=utf-8',
          ..._noCacheHeaders,
        },
      );
    };
  }

  static const _noCacheHeaders = {
    'cache-control': 'no-cache, no-store, must-revalidate',
    'pragma': 'no-cache',
    'expires': '0',
  };

  /// Cấm trình duyệt cache mấy file khởi động của bản web.
  ///
  /// Flutter web cài service worker cache rất dai: sau khi cập nhật phần mềm,
  /// máy ở kho vẫn chạy bản cũ cho tới khi ai đó biết cách xoá cache — và triệu
  /// chứng thì mơ hồ (số cân không lên) nên rất khó đoán ra. Bắt buộc trình
  /// duyệt hỏi lại mấy file này mỗi lần mở là hết. Các file còn lại (main.dart.js,
  /// font, ảnh) đều có tên kèm phiên bản nên vẫn cache bình thường.
  Response _noCacheForEntryPoints(Request request, Response response) {
    const entryPoints = {
      '',
      'index.html',
      'flutter_bootstrap.js',
      'flutter_service_worker.js',
      'version.json',
    };
    if (!entryPoints.contains(request.url.path)) return response;
    return response.change(headers: _noCacheHeaders);
  }

  void _logRequest(String message, bool isError) {
    if (isError) {
      AppLog.error(message);
    }
    // Đường dẫn tĩnh và WebSocket bị bỏ qua để log không bị số cân realtime
    // làm ngập, chỉ giữ lại lời gọi API thật sự.
    else if (message.contains('/api/')) {
      AppLog.write(message);
    }
  }

  void _printBanner() {
    final host = config.host == '0.0.0.0' ? '127.0.0.1' : config.host;
    final scale = config.scale.simulate
        ? 'GIẢ LẬP (không cần phần cứng)'
        : config.scale.port.isEmpty
            ? 'CHƯA CẤU HÌNH'
            : '${config.scale.port} @ ${config.scale.baudRate} baud';

    final lines = <String>[
      '',
      '  CÂN XE — máy chủ ${config.role.value.toUpperCase()}  (v$appVersion)',
      '  ${'-' * 58}',
      '  Trạm/kho     : ${config.effectiveStationCode} '
          '${config.stationName.isEmpty ? '' : '(${config.stationName})'}',
      '  Địa chỉ web  : http://$host:${config.port}',
      '  Cơ sở dữ liệu: ${config.resolvedDatabasePath}',
      if (config.isStation) '  Đầu cân      : $scale',
      if (config.isStation) '  Trung tâm    : ${config.centralUrl}',
      if (AppLog.path != null) '  Nhật ký      : ${AppLog.path}',
      '  ${'-' * 58}',
      '  Nhấn Ctrl+C để dừng.',
      '',
    ];
    for (final line in lines) {
      AppLog.write(line);
    }
  }

  Future<void> stop() async {
    await _httpServer?.close(force: true);
    await _scaleSub?.cancel();
    await _uplink?.dispose();
    await _sync?.dispose();
    await _scale?.dispose();
    await _broker.dispose();
    _database.dispose();
    await AppLog.close();
  }
}
