import 'dart:io';

import 'package:args/args.dart';
import 'package:canxe_server/canxe_server.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Công cụ sao lưu và **khôi phục** cơ sở dữ liệu cân xe.
///
/// Việc khôi phục nằm ngay cạnh việc sao lưu là có chủ ý: một bản sao lưu chưa
/// từng được thử khôi phục thì chưa phải bản sao lưu, mới chỉ là một file trên
/// mạng. Chạy `thu` mỗi vài tháng để biết chắc đường về vẫn còn thông.
///
///   dart run bin/sao_luu.dart --config config.central.json kiem-tra
///   dart run bin/sao_luu.dart --config config.central.json chay
///   dart run bin/sao_luu.dart --config config.central.json liet-ke
///   dart run bin/sao_luu.dart --config config.central.json khoi-phuc <ten-ban>
///   dart run bin/sao_luu.dart --config config.central.json thu
Future<void> main(List<String> arguments) async {
  enableUtf8Console();

  final parser = ArgParser()
    ..addOption('config', abbr: 'c', defaultsTo: 'config.json')
    ..addOption('ra', help: 'Đường dẫn file .db ghi ra khi khôi phục.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  final lenh = args.rest.isEmpty ? '' : args.rest.first;

  if (args.flag('help') || lenh.isEmpty) {
    stdout.writeln('''
Sao lưu cơ sở dữ liệu cân xe lên đám mây.

  kiem-tra              Thử kết nối máy chủ sao lưu.
  chay                  Chụp, mã hoá và đẩy một bản lên ngay.
  liet-ke               Danh sách bản đang có trên đám mây.
  khoi-phuc <ten-ban>   Tải một bản về, giải mã, ghi ra file .db.
  mo <file.canxe>       Giải mã một gói có sẵn trên đĩa.
  thu                   Chạy trọn vòng: đẩy lên, tải về, so từng byte.

${parser.usage}''');
    return;
  }

  final ServerConfig config;
  try {
    config = await ServerConfig.load(args.option('config')!);
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(78);
  }

  final sl = config.backup;
  if (lenh != 'mo' && !sl.sanSang) {
    stderr.writeln(
      'Chưa đủ cấu hình sao lưu (thiếu: ${sl.thieuGi().join(", ")}).\n'
      'Chép packages/server/config.sao-luu.example.json thành config.sao-luu.json '
      'rồi điền.',
    );
    exit(78);
  }

  final db = AppDatabase.open(config.resolvedDatabasePath);
  final dichVu = BackupService(
    config: sl,
    database: db,
    may: config.effectiveStationCode,
    thuMucGoc: Directory.current.path,
  );
  final store = BackupStore(url: sl.url, token: sl.token);

  try {
    switch (lenh) {
      case 'kiem-tra':
        final kq = await store.kiemTra();
        stdout.writeln('Máy chủ sao lưu trả lời: $kq');

      case 'chay':
        final ten = await dichVu.chayNgay(baoCao: stdout.writeln);
        stdout.writeln('Đã đẩy lên: $ten');

      case 'liet-ke':
        final ds = await store.lietKe();
        if (ds.isEmpty) {
          stdout.writeln('Chưa có bản sao lưu nào trên đám mây.');
        }
        for (final b in ds) {
          stdout.writeln('  ${b.moTa}');
        }

      case 'khoi-phuc':
        if (args.rest.length < 2) {
          stderr.writeln('Thiếu tên bản. Chạy "liet-ke" để xem có những bản nào.');
          exit(64);
        }
        await _khoiPhuc(
          goi: await store.tai(args.rest[1],
              tienDo: (i, n) => stdout.writeln('Đang tải phần $i/$n...')),
          matKhau: sl.matKhau,
          ra: args.option('ra'),
        );

      case 'mo':
        if (args.rest.length < 2) {
          stderr.writeln('Thiếu đường dẫn file .canxe.');
          exit(64);
        }
        await _khoiPhuc(
          goi: await File(args.rest[1]).readAsBytes(),
          matKhau: sl.matKhau,
          ra: args.option('ra'),
        );

      case 'thu':
        await _thuTronVong(dichVu, store, sl.matKhau);

      default:
        stderr.writeln('Không hiểu lệnh "$lenh". Chạy --help để xem danh sách.');
        exit(64);
    }
  } on BackupException catch (e) {
    stderr.writeln('Hỏng: ${e.message}');
    exit(1);
  } finally {
    store.dispose();
    dichVu.dispose();
    db.dispose();
  }
}

/// Giải mã một gói rồi ghi ra file, **không đụng vào cơ sở dữ liệu đang chạy**.
///
/// Cố ý ghi ra chỗ khác chứ không tự đè lên: khôi phục nhầm bản là mất trắng
/// dữ liệu từ lúc sao lưu tới giờ, mà đó lại chính là phần chưa có bản sao nào.
/// Người dùng tự dừng máy chủ rồi đổi tên file — chậm hơn vài phút, đổi lấy
/// việc không có nút nào bấm nhầm một cái là hỏng.
Future<void> _khoiPhuc({
  required List<int> goi,
  required String matKhau,
  String? ra,
}) async {
  final (meta, duLieu) = BackupArchive.moGoi(goi: goi, matKhau: matKhau);
  final dich = File(ra ?? p.join('data', 'khoi-phuc-${meta.tenGoi}.db'));
  await dich.parent.create(recursive: true);
  await dich.writeAsBytes(duLieu);

  stdout.writeln('Bản sao chụp lúc ${meta.luc.toLocal()} từ máy "${meta.may}".');
  stdout.writeln('Đã ghi ra: ${dich.absolute.path}');
  stdout.writeln(_kiemTraToanVen(dich.path));
  stdout.writeln(
    '\nĐể dùng bản này: dừng máy chủ, đổi tên file cơ sở dữ liệu cũ để giữ lại,\n'
    'rồi chép file trên vào đúng chỗ và tên cũ. Đừng xoá file cũ.',
  );
}

/// Mở thử file vừa ghi bằng chính SQLite, để biết chắc nó dùng được.
String _kiemTraToanVen(String duongDan) {
  Database? db;
  try {
    db = sqlite3.open(duongDan);
    final kq = db.select('PRAGMA integrity_check;').first.values.first;
    final phieu = db.select('SELECT COUNT(*) FROM tickets;').first.values.first;
    return 'SQLite kiểm tra: $kq — đọc được $phieu phiếu cân.';
  } catch (e) {
    return 'CẢNH BÁO: mở file vừa ghi không được ($e).';
  } finally {
    db?.dispose();
  }
}

/// Đẩy một bản lên rồi tải ngay bản đó về và so từng byte.
///
/// Đây là phép thử duy nhất trả lời được câu "bản sao lưu có thật sự dùng được
/// không". Nó chạy qua đủ mọi khâu: chụp, nén, mã hoá, cắt phần, mạng, ghép
/// lại, kiểm chữ ký, giải mã. Bỏ qua khâu nào cũng là đoán.
Future<void> _thuTronVong(
  BackupService dichVu,
  BackupStore store,
  String matKhau,
) async {
  stdout.writeln('--- 1/3 Đẩy một bản lên ---');
  final ten = await dichVu.chayNgay(baoCao: stdout.writeln);

  stdout.writeln('\n--- 2/3 Tải chính bản đó về ---');
  final goi = await store.tai(ten, tienDo: (i, n) => stdout.writeln('  phần $i/$n'));

  stdout.writeln('\n--- 3/3 Giải mã và đối chiếu ---');
  final (meta, duLieu) = BackupArchive.moGoi(goi: goi, matKhau: matKhau);
  stdout.writeln('  Giải mã ra ${duLieu.length} byte, khớp mã kiểm tra.');
  stdout.writeln('  Chụp lúc: ${meta.luc.toLocal()}');

  // Thử luôn cả trường hợp sai mật khẩu: nếu gói sai khoá mà vẫn mở được thì
  // lớp mã hoá không bảo vệ được gì cả.
  try {
    BackupArchive.moGoi(goi: goi, matKhau: '$matKhau-sai');
    stderr.writeln('  LỖI NẶNG: gói mở được bằng mật khẩu sai!');
    exit(1);
  } on BackupException {
    stdout.writeln('  Mật khẩu sai bị từ chối — đúng như mong đợi.');
  }

  stdout.writeln('\nTrọn vòng chạy được. Bản "$ten" khôi phục lại được.');
}
