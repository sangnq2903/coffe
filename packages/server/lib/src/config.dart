import 'dart:convert';
import 'dart:io';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;

import 'backup/backup_config.dart';

/// Vai trò của tiến trình server.
enum ServerRole {
  /// Máy chủ trung tâm (100.76.81.118): giữ dữ liệu gộp của mọi kho.
  central('central'),

  /// Máy đặt tại kho, nối cổng COM với đầu cân.
  station('station');

  const ServerRole(this.value);

  final String value;

  static ServerRole parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString().toLowerCase(),
        orElse: () => ServerRole.central,
      );
}

/// Cấu hình cổng COM của đầu cân.
class ScaleConfig {
  const ScaleConfig({
    this.port = '',
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.parity = 'none',
    this.protocol = ScaleProtocol.auto,
    this.divisor = 1,
    this.unit = 'kg',
    this.customPattern,
    this.customGroup = 1,
    this.stableTolerance = 5,
    this.stableSamples = 5,
    this.simulate = false,
    this.broadcastIntervalMs = 200,
    this.dataTimeoutSeconds = 5,
  });

  factory ScaleConfig.fromJson(Map<String, Object?> json) => ScaleConfig(
        port: asString(json['port']),
        baudRate: asInt(json['baud_rate'], fallback: 9600),
        dataBits: asInt(json['data_bits'], fallback: 8),
        stopBits: asInt(json['stop_bits'], fallback: 1),
        parity: asString(json['parity'], fallback: 'none'),
        protocol: ScaleProtocol.parse(json['protocol']),
        divisor: asDouble(json['divisor'], fallback: 1),
        unit: asString(json['unit'], fallback: 'kg'),
        customPattern: asStringOrNull(json['custom_pattern']),
        customGroup: asInt(json['custom_group'], fallback: 1),
        stableTolerance: asDouble(json['stable_tolerance'], fallback: 5),
        stableSamples: asInt(json['stable_samples'], fallback: 5),
        simulate: asBool(json['simulate']),
        broadcastIntervalMs: asInt(json['broadcast_interval_ms'], fallback: 200),
        dataTimeoutSeconds: asInt(json['data_timeout_seconds'], fallback: 5),
      );

  final String port;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final String parity;
  final ScaleProtocol protocol;
  final double divisor;
  final String unit;
  final String? customPattern;
  final int customGroup;
  final double stableTolerance;
  final int stableSamples;

  /// Bật chế độ giả lập đầu cân để chạy thử phần mềm khi chưa có phần cứng.
  final bool simulate;

  /// Chặn tần suất đẩy xuống client. Đầu cân có thể gửi 10-20 khung/giây;
  /// đẩy hết xuống trình duyệt là thừa, mắt người không theo kịp.
  final int broadcastIntervalMs;

  /// Bao lâu không nhận được khung nào thì coi như đầu cân đã ngừng phát.
  ///
  /// Cổng COM vẫn mở được kể cả khi đầu cân bị tắt nguồn hay rút dây tín hiệu,
  /// nên không thể chỉ dựa vào việc mở cổng thành công để nói là đang kết nối —
  /// làm vậy màn hình sẽ giữ nguyên số cân cuối cùng và bị hiểu nhầm là số thật.
  final int dataTimeoutSeconds;

  bool get enabled => simulate || port.isNotEmpty;

  WeightParserConfig get parserConfig => WeightParserConfig(
        protocol: protocol,
        unit: unit,
        divisor: divisor,
        customPattern: customPattern,
        customGroup: customGroup,
      );

  Map<String, Object?> toJson() => {
        'port': port,
        'baud_rate': baudRate,
        'data_bits': dataBits,
        'stop_bits': stopBits,
        'parity': parity,
        'protocol': protocol.value,
        'divisor': divisor,
        'unit': unit,
        'custom_pattern': customPattern,
        'custom_group': customGroup,
        'stable_tolerance': stableTolerance,
        'stable_samples': stableSamples,
        'simulate': simulate,
        'broadcast_interval_ms': broadcastIntervalMs,
        'data_timeout_seconds': dataTimeoutSeconds,
      };
}

/// Toàn bộ cấu hình của một tiến trình server.
class ServerConfig {
  const ServerConfig({
    required this.role,
    this.host = '0.0.0.0',
    this.port = 8080,
    this.stationCode = '',
    this.stationName = '',
    this.warehouseName,
    this.address,
    this.publicBaseUrl,
    this.centralUrl,
    this.centralUsername,
    this.centralPassword,
    this.syncIntervalSeconds = 20,
    this.databasePath = 'data/canxe.db',
    this.webRoot = 'web',
    this.scale = const ScaleConfig(),
    this.backup = const BackupConfig(),
  });

  factory ServerConfig.fromJson(Map<String, Object?> json) {
    final http = (json['http'] as Map?)?.cast<String, Object?>() ?? const {};
    final station = (json['station'] as Map?)?.cast<String, Object?>() ?? const {};
    final central = (json['central'] as Map?)?.cast<String, Object?>() ?? const {};
    final db = (json['database'] as Map?)?.cast<String, Object?>() ?? const {};
    final scale = (json['scale'] as Map?)?.cast<String, Object?>() ?? const {};

    return ServerConfig(
      role: ServerRole.parse(json['role']),
      host: asString(http['host'], fallback: '0.0.0.0'),
      port: asInt(http['port'], fallback: 8080),
      stationCode: asString(station['code']).toUpperCase(),
      stationName: asString(station['name']),
      warehouseName: asStringOrNull(station['warehouse_name']),
      address: asStringOrNull(station['address']),
      publicBaseUrl: asStringOrNull(station['public_base_url']),
      centralUrl: asStringOrNull(central['url']),
      centralUsername: asStringOrNull(central['username']),
      centralPassword: asStringOrNull(central['password']),
      syncIntervalSeconds: asInt(central['sync_interval_seconds'], fallback: 20),
      databasePath: asString(db['path'], fallback: 'data/canxe.db'),
      webRoot: asString(json['web_root'], fallback: 'web'),
      scale: ScaleConfig.fromJson(scale),
    );
  }

  /// Đọc cấu hình từ file JSON; thiếu file thì dùng mặc định vai trò trung tâm.
  static Future<ServerConfig> load(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'Không tìm thấy file cấu hình "$path".\n'
        'Hãy sao chép config.central.example.json hoặc config.station.example.json '
        'thành config.json rồi sửa lại cho đúng máy.',
      );
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) {
      throw StateError('File cấu hình "$path" không phải đối tượng JSON hợp lệ.');
    }
    return ServerConfig.fromJson(raw.cast<String, Object?>())
        .copyWith(backup: BackupConfig.load(path));
  }

  final ServerRole role;
  final String host;
  final int port;

  /// Mã trạm — bắt buộc với vai trò station, là tiền tố của mọi số phiếu.
  final String stationCode;
  final String stationName;
  final String? warehouseName;
  final String? address;

  /// Địa chỉ Tailscale của máy trạm để máy khác/điện thoại nối vào lấy số cân,
  /// ví dụ `http://100.101.102.103:8080`. Trạm khai báo lên trung tâm khi đăng ký.
  final String? publicBaseUrl;

  /// URL máy chủ trung tâm, ví dụ `http://100.76.81.118:9080`.
  final String? centralUrl;

  /// Tài khoản máy trạm dùng để đăng nhập lên trung tâm.
  ///
  /// Máy trạm cũng phải qua cửa đăng nhập như người dùng, không có cửa sau
  /// riêng. Nhờ vậy phạm vi kho của trạm do chính tài khoản này quyết định, và
  /// tra được trạm nào đồng bộ lúc nào.
  final String? centralUsername;
  final String? centralPassword;
  final int syncIntervalSeconds;
  final String databasePath;

  /// Thư mục chứa bản build Flutter web để server host luôn giao diện.
  final String webRoot;
  final ScaleConfig scale;

  /// Sao lưu lên đám mây. Đọc từ file riêng `config.sao-luu.json` đặt cạnh file
  /// cấu hình này, vì nó chứa chìa khoá và mật khẩu — xem [BackupConfig].
  final BackupConfig backup;

  bool get isCentral => role == ServerRole.central;

  bool get isStation => role == ServerRole.station;

  Uri? get centralUri {
    final url = centralUrl;
    if (url == null || url.isEmpty) return null;
    return Uri.parse(url);
  }

  String get resolvedDatabasePath => p.isAbsolute(databasePath)
      ? databasePath
      : p.normalize(p.join(Directory.current.path, databasePath));

  String get resolvedWebRoot =>
      p.isAbsolute(webRoot) ? webRoot : p.normalize(p.join(Directory.current.path, webRoot));

  /// Mã dùng để gắn nhãn dữ liệu do chính máy này tạo ra.
  String get effectiveStationCode =>
      stationCode.isNotEmpty ? stationCode : (isCentral ? 'TRUNGTAM' : 'TRAM');

  ServerConfig copyWith({
    ServerRole? role,
    String? host,
    int? port,
    String? stationCode,
    String? centralUrl,
    String? databasePath,
    String? webRoot,
    ScaleConfig? scale,
    BackupConfig? backup,
  }) =>
      ServerConfig(
        role: role ?? this.role,
        host: host ?? this.host,
        port: port ?? this.port,
        stationCode: stationCode ?? this.stationCode,
        stationName: stationName,
        warehouseName: warehouseName,
        address: address,
        publicBaseUrl: publicBaseUrl,
        centralUrl: centralUrl ?? this.centralUrl,
        centralUsername: centralUsername,
        centralPassword: centralPassword,
        syncIntervalSeconds: syncIntervalSeconds,
        databasePath: databasePath ?? this.databasePath,
        webRoot: webRoot ?? this.webRoot,
        scale: scale ?? this.scale,
        backup: backup ?? this.backup,
      );

  /// Thiếu tài khoản đăng nhập lên trung tâm.
  ///
  /// Cố tình KHÔNG coi đây là lỗi cấu hình: bàn cân phải cân được ngay cả khi
  /// chưa khai tài khoản đồng bộ. Chặn máy trạm khởi động vì lý do này là làm
  /// cả kho đứng bánh chỉ vì một dòng cấu hình chưa điền.
  bool get missingCentralAccount =>
      isStation &&
      ((centralUsername ?? '').isEmpty || (centralPassword ?? '').isEmpty);

  /// Kiểm tra cấu hình trước khi khởi động để báo lỗi rõ ràng ngay từ đầu thay
  /// vì để server chạy nửa vời rồi hỏng lúc đang cân xe.
  List<String> validate() {
    final errors = <String>[];
    if (port <= 0 || port > 65535) {
      errors.add('Cổng HTTP không hợp lệ: $port');
    }
    if (isStation) {
      if (stationCode.isEmpty) {
        errors.add('Vai trò "station" bắt buộc phải khai báo station.code (mã kho).');
      }
      if (centralUri == null) {
        errors.add('Vai trò "station" bắt buộc phải khai báo central.url để đồng bộ.');
      }

    }
    if (scale.simulate && scale.port.isNotEmpty) {
      errors.add('Không thể vừa bật scale.simulate vừa khai báo scale.port.');
    }
    return errors;
  }
}
