import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:canxe_server/canxe_server.dart';

/// Điểm khởi động server cân xe.
///
/// Ví dụ:
///   dart run bin/server.dart --config config.central.json
///   dart run bin/server.dart --config config.station.json
///   dart run bin/server.dart --config config.station.json --port 8081 --simulate
///   canxe-server.exe --config config.station.json --log-file logs/tram.log
Future<void> main(List<String> arguments) async {
  enableUtf8Console();

  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.json', help: 'Đường dẫn file cấu hình JSON.')
    ..addOption('role', abbr: 'r', allowed: ['central', 'station'], help: 'Ghi đè vai trò trong file cấu hình.')
    ..addOption('port', abbr: 'p', help: 'Ghi đè cổng HTTP.')
    ..addOption('web-root', help: 'Thư mục chứa bản build Flutter web.')
    ..addOption('log-file',
        help: 'Ghi nhật ký ra file (bắt buộc khi chạy dưới dạng tác vụ Windows, '
            'vì lúc đó không có cửa sổ nào để xem).')
    ..addFlag('simulate', negatable: false, help: 'Giả lập đầu cân, dùng khi chưa đấu nối phần cứng.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Hiện hướng dẫn.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Tham số không hợp lệ: ${e.message}\n');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (args.flag('help')) {
    stdout.writeln('Máy chủ cân xe — chạy vai trò trung tâm hoặc trạm cân.\n');
    stdout.writeln(parser.usage);
    return;
  }

  ServerConfig config;
  try {
    config = await ServerConfig.load(args.option('config')!);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(78);
  }

  final roleOverride = args.option('role');
  final portOverride = args.option('port');
  config = config.copyWith(
    role: roleOverride == null ? null : ServerRole.parse(roleOverride),
    port: portOverride == null ? null : int.tryParse(portOverride),
    webRoot: args.option('web-root'),
    scale: args.flag('simulate')
        ? ScaleConfig.fromJson({...config.scale.toJson(), 'simulate': true, 'port': ''})
        : null,
  );

  AppLog.init(args.option('log-file'));

  final app = ServerApp(config);
  try {
    await app.start();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(78);
  }

  // Ctrl+C phải đóng cổng COM và cơ sở dữ liệu tử tế, nếu không lần chạy sau
  // sẽ báo cổng đang bị chiếm.
  late final StreamSubscription<ProcessSignal> sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('\nĐang dừng máy chủ...');
    await sigint.cancel();
    await app.stop();
    exit(0);
  });
}
