import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';

/// Đặt lại mật khẩu khi **quên mật khẩu tài khoản quản lý tổng** — cửa sau duy
/// nhất, vì bình thường chỉ tài khoản tổng mới đặt lại mật khẩu cho người khác
/// (xem [AuthService.resetPassword]), nên không ai tự cứu được chính mình qua
/// màn hình web.
///
/// Phải chạy trực tiếp trên máy giữ cơ sở dữ liệu, và máy chủ phải đang TẮT —
/// công cụ mở thẳng file SQLite, ghi đè trong lúc máy chủ đang giữ file dễ gây
/// xung đột khoá.
///
///   dart run bin/khoi_phuc_mat_khau.dart --config config.central.json
///   dart run bin/khoi_phuc_mat_khau.dart --config config.central.json --username chu --password matkhaumoi123
Future<void> main(List<String> arguments) async {
  enableUtf8Console();

  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.central.json', help: 'File cấu hình trỏ tới cơ sở dữ liệu cần sửa.')
    ..addOption('username', abbr: 'u', help: 'Tài khoản cần đặt lại. Bỏ trống thì tự chọn tài khoản chủ.')
    ..addOption('password', abbr: 'p', help: 'Mật khẩu mới. Bỏ trống thì tự sinh một mật khẩu ngẫu nhiên.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args.flag('help')) {
    stdout
      ..writeln('Đặt lại mật khẩu tài khoản quản lý tổng khi bị quên.\n')
      ..writeln('Cách dùng: dart run bin/khoi_phuc_mat_khau.dart [tuỳ chọn]\n')
      ..writeln(parser.usage);
    return;
  }

  final configPath = args.option('config')!;
  ServerConfig config;
  try {
    config = await ServerConfig.load(configPath);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 78;
    return;
  }

  final dbPath = config.resolvedDatabasePath;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Không thấy file cơ sở dữ liệu "$dbPath" (theo "$configPath").');
    exitCode = 1;
    return;
  }

  stdout.writeln('==> Mở "$dbPath"...');
  final database = AppDatabase.open(dbPath);
  try {
    final repo = Repository(database);
    final auth = AuthService(repo);

    final tongAccounts = repo
        .users(includeInactive: true)
        .where((u) => u.role == UserRole.tong)
        .toList();
    if (tongAccounts.isEmpty) {
      stderr.writeln('Không có tài khoản quản lý tổng nào trong cơ sở dữ liệu này.');
      exitCode = 1;
      return;
    }

    stdout.writeln('    Tài khoản quản lý tổng đang có:');
    for (final u in tongAccounts) {
      stdout.writeln('      - ${u.username} (${u.fullName})'
          '${u.isOwner ? ' [chủ]' : ''}${u.active ? '' : ' [đã khoá]'}');
    }

    final usernameArg = args.option('username')?.trim().toLowerCase();
    final target = usernameArg == null
        ? tongAccounts.firstWhere((u) => u.isOwner, orElse: () => tongAccounts.first)
        : tongAccounts.firstWhere(
            (u) => u.username == usernameArg,
            orElse: () => throw StateError('Không có tài khoản quản lý tổng tên "$usernameArg".'),
          );

    final newPassword = args.option('password') ?? _taoMatKhauNgauNhien();
    auth.resetPassword(target: target, newPassword: newPassword);

    stdout
      ..writeln('')
      ..writeln('==> ĐÃ ĐẶT LẠI MẬT KHẨU')
      ..writeln('    Tài khoản : ${target.username}')
      ..writeln('    Mật khẩu  : $newPassword')
      ..writeln('')
      ..writeln('    Đăng nhập lại rồi đổi sang mật khẩu riêng ngay (Cá nhân > Đổi mật khẩu).');
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } finally {
    database.dispose();
  }
}

String _taoMatKhauNgauNhien() {
  // Bỏ các chữ dễ lẫn (0/O, 1/l/I) vì mật khẩu này phải gõ tay lại một lần.
  const bang = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  final rnd = Random.secure();
  return List.generate(14, (_) => bang[rnd.nextInt(bang.length)]).join();
}
