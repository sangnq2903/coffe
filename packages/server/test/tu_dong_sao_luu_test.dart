import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Kiểm thử tự động sao lưu.
///
/// Tính năng này chạy một mình trong nền, không ai bấm nút, không ai nhìn. Nếu
/// nó hỏng thì hỏng lặng lẽ — vẫn báo "đã bật" trên màn hình mà thư mục thì
/// trống. Nên phần lớn bài ở đây soi mấy chỗ dễ hỏng lặng: thư mục không ghi
/// được, chụp giữa chừng mất điện, và luật giữ lại mấy bản.
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late AutoBackupService tuDong;
  late String thuMucLuu;

  String duongDan(String ten) => '${tempDir.path}/$ten';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('canxe-tu-dong');
    thuMucLuu = duongDan('sao-luu');
    database = AppDatabase.open(duongDan('may/canxe.db'));
    repo = Repository(database);
    tuDong = AutoBackupService(
      database: database,
      duLieu: DataTransferService(database: database, repo: repo, may: 'KHO01'),
      may: 'KHO01',
    );
  });

  tearDown(() {
    tuDong.dispose();
    database.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows đôi lúc còn giữ handle một nhịp sau khi đóng.
    }
  });

  void bat({String? thuMuc, int giuBan = 2, String? matKhau}) => tuDong.luuCaiDat({
        'bat': true,
        'thu_muc': thuMuc ?? thuMucLuu,
        'giu_ban': giuBan,
        if (matKhau != null) 'mat_khau': matKhau,
      });

  List<String> daLuu() {
    final d = Directory(thuMucLuu);
    if (!d.existsSync()) return const [];
    return d.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()
      ..sort();
  }

  group('Thiết lập', () {
    test('lưu rồi đọc lại vẫn còn', () {
      bat(giuBan: 5);
      expect(tuDong.docCaiDat().bat, isTrue);
      expect(tuDong.docCaiDat().thuMuc, thuMucLuu);
      expect(tuDong.docCaiDat().giuBan, 5);
    });

    test('tự tạo thư mục nếu chưa có', () {
      expect(Directory(thuMucLuu).existsSync(), isFalse);
      bat();
      expect(Directory(thuMucLuu).existsSync(), isTrue);
    });

    test('bật mà chưa chọn thư mục thì bị chặn', () {
      expect(
        () => tuDong.luuCaiDat({'bat': true, 'thu_muc': ''}),
        throwsA(isA<BusinessException>()
            .having((e) => e.message, 'lời báo', contains('Chưa chọn thư mục'))),
      );
    });

    test('đường dẫn tương đối bị chặn', () {
      // Đường dẫn tương đối tính từ chỗ máy chủ đang chạy — mà máy chủ chạy
      // dưới quyền SYSTEM nên chỗ đó không phải nơi người dùng tưởng.
      expect(
        () => tuDong.luuCaiDat({'bat': true, 'thu_muc': 'sao-luu'}),
        throwsA(isA<BusinessException>()
            .having((e) => e.message, 'lời báo', contains('đường dẫn đầy đủ'))),
      );
    });

    test('tắt thì không đòi thư mục', () {
      tuDong.luuCaiDat({'bat': false, 'thu_muc': ''});
      expect(tuDong.caiDat.bat, isFalse);
    });

    test('giữ bản luôn ít nhất 1', () {
      bat(giuBan: 0);
      expect(tuDong.caiDat.giuBan, 1, reason: 'giữ 0 bản thì bật lên làm gì');
    });

    test('không trả mật khẩu ra ngoài', () {
      bat(matKhau: 'bi-mat-cua-toi');
      final ra = tuDong.caiDat.toJson();
      expect(ra['co_mat_khau'], isTrue);
      expect(ra.values.join(' '), isNot(contains('bi-mat-cua-toi')));
    });

    test('không gửi trường mật khẩu thì giữ nguyên cái cũ', () {
      // Màn hình không đọc được mật khẩu cũ nên không thể gửi lại nó; gửi
      // thiếu mà bị hiểu là "xoá mật khẩu" thì lần lưu thiết lập sau là bản
      // sao lưu hết mã hoá mà không ai hay.
      bat(matKhau: 'mk-cu');
      tuDong.luuCaiDat({'bat': true, 'thu_muc': thuMucLuu, 'giu_ban': 3});
      expect(tuDong.docCaiDat().matKhau, 'mk-cu');
      expect(tuDong.docCaiDat().giuBan, 3);
    });
  });

  group('Chụp', () {
    test('ra file SQLite mở được', () async {
      bat();
      repo.upsertCustomer(Customer.create(name: 'Nguyễn Văn Bảy'));
      final ten = await tuDong.chayNgay();

      expect(ten, endsWith('.db'));
      final db = sqlite3.open('$thuMucLuu/$ten');
      try {
        expect(db.select('PRAGMA integrity_check;').first.values.first, 'ok');
        expect(db.select('SELECT name FROM customers').first.values.first,
            'Nguyễn Văn Bảy');
      } finally {
        db.dispose();
      }
    });

    test('có mật khẩu thì ra gói mã hoá mở lại được', () async {
      bat(matKhau: 'mk-dai-va-kho-doan');
      repo.upsertCustomer(Customer.create(name: 'Lê Thị Chín'));
      final ten = await tuDong.chayNgay();

      expect(ten, endsWith('.canxe'));
      final goi = File('$thuMucLuu/$ten').readAsBytesSync();
      final (_, goc) =
          BackupArchive.moGoi(goi: goi, matKhau: 'mk-dai-va-kho-doan');
      expect(goc.sublist(0, 6), equals('SQLite'.codeUnits));
    });

    test('chưa bật thì từ chối chạy', () {
      expect(tuDong.chayNgay(), throwsA(isA<BusinessException>()));
    });

    test('không để lại file .dangghi', () async {
      // Ghi ra tên tạm rồi đổi tên; sót lại file tạm thì nó lẫn vào danh sách
      // và chiếm suất trong hạn giữ.
      bat(matKhau: 'mk');
      await tuDong.chayNgay();
      expect(daLuu().where((f) => f.contains('dangghi')), isEmpty);
    });

    test('trạng thái ghi lại tên và cỡ file', () async {
      bat();
      final ten = await tuDong.chayNgay();
      expect(tuDong.state.tenFileCuoi, ten);
      expect(tuDong.state.bytesCuoi, greaterThan(0));
      expect(tuDong.state.soLanChay, 1);
      expect(tuDong.state.loi, isNull);
    });
  });

  group('Giữ lại tối đa mấy bản', () {
    /// Chạy nhiều lượt, cách nhau đủ để dấu thời gian trong tên file khác nhau.
    Future<void> chayNhieuLan(int lan) async {
      for (var i = 0; i < lan; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 1100));
        await tuDong.chayNgay();
      }
    }

    test('giữ đúng 2 bản mới nhất', () async {
      bat(giuBan: 2);
      await chayNhieuLan(4);

      final ds = daLuu();
      expect(ds.length, 2);
      expect(ds.last, tuDong.state.tenFileCuoi,
          reason: 'bản mới nhất phải còn lại');
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('đổi số giữ xuống thì lần chạy sau dọn bớt', () async {
      bat(giuBan: 3);
      await chayNhieuLan(3);
      expect(daLuu().length, 3);

      bat(giuBan: 1);
      await tuDong.chayNgay();
      expect(daLuu().length, 1);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('không đụng vào file của người khác trong cùng thư mục', () async {
      // Thư mục có thể là chỗ chung. Dọn nhầm file người ta là chuyện không
      // sửa lại được.
      Directory(thuMucLuu).createSync(recursive: true);
      final la = File('$thuMucLuu/bao-cao-thue.xlsx')..writeAsStringSync('x');
      final khac = File('$thuMucLuu/canxe-kho99-20200101-000000.db')
        ..writeAsStringSync('x');

      bat(giuBan: 1);
      await chayNhieuLan(2);

      expect(la.existsSync(), isTrue);
      expect(khac.existsSync(), isTrue, reason: 'bản của máy khác cũng không đụng');
      expect(daLuu().where((f) => f.startsWith('canxe-kho01-')).length, 1);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('Hỏng thì báo, không im lặng', () {
    test('thư mục không ghi được thì chặn ngay lúc lưu thiết lập', () {
      // Chặn ở đây mới đúng chỗ: nhận bừa rồi báo "đã bật" trong khi chẳng bản
      // nào ghi ra được là kiểu hỏng tệ nhất.
      final vuongMat = File(duongDan('day-la-file.txt'))..writeAsStringSync('x');
      expect(
        () => tuDong.luuCaiDat({'bat': true, 'thu_muc': vuongMat.path}),
        throwsA(isA<BusinessException>()),
      );
    });

    test('không để lại file thử ghi', () {
      bat();
      expect(daLuu().where((f) => f.contains('thu-ghi')), isEmpty);
    });

    test('chụp hỏng thì ghi lỗi vào trạng thái và vẫn coi là còn nợ', () async {
      bat();
      // Xoá thư mục rồi chặn đường tạo lại bằng một file cùng tên.
      Directory(thuMucLuu).deleteSync(recursive: true);
      File(thuMucLuu).writeAsStringSync('chan duong');

      await expectLater(tuDong.chayNgay(), throwsA(isA<Object>()));
      expect(tuDong.state.loi, isNotNull);
      expect(tuDong.state.dangCho, isTrue,
          reason: 'quên đi thì từ giờ tới mãi sau không bản nào được sao lưu');
    });
  });

  group('Hình dạng dữ liệu trả về', () {
    test('thiết lập và tình trạng luôn đi cùng nhau', () {
      // Màn hình dựng lại toàn bộ thẻ từ mỗi phản hồi. Cửa nào trả thiếu phần
      // thiết lập thì thẻ đọc `bat` ra rỗng và hiện "đang tắt" ngay sau khi
      // vừa chụp xong — trông như tính năng tự tắt.
      bat(giuBan: 4);
      final gop = {...tuDong.caiDat.toJson(), ...tuDong.state.toJson()};

      expect(gop['bat'], isTrue);
      expect(gop['thu_muc'], thuMucLuu);
      expect(gop['giu_ban'], 4);
      expect(gop.containsKey('dang_cho'), isTrue);
      expect(gop.containsKey('so_lan_chay'), isTrue);
      expect(gop.containsKey('mat_khau'), isFalse, reason: 'không lộ mật khẩu');
    });
  });

  group('Theo dõi sự kiện lưu', () {
    test('ghi vào cơ sở dữ liệu thì được ghi nhận là có thay đổi', () async {
      bat();
      tuDong.start();
      expect(tuDong.state.dangCho, isFalse);

      repo.upsertCustomer(Customer.create(name: 'Trần Văn Tám'));
      // Móc báo của SQLite bắn ra ngay trong lời gọi ghi.
      expect(tuDong.state.dangCho, isTrue);
    });

    test('chụp xong thì hết nợ', () async {
      bat();
      tuDong.start();
      repo.upsertCustomer(Customer.create(name: 'Trần Văn Tám'));
      await tuDong.chayNgay();
      expect(tuDong.state.dangCho, isFalse);
    });

    test('thay đổi xảy ra trong lúc đang chụp không bị bỏ quên', () async {
      // Mốc nợ phải xoá TRƯỚC khi chụp. Xoá sau thì mọi thay đổi trong lúc
      // chụp bị xoá theo, và bản sau thiếu đúng những dòng ấy.
      bat();
      tuDong.start();

      final dangChay = tuDong.chayNgay();
      repo.upsertCustomer(Customer.create(name: 'Ghi giữa chừng'));
      await dangChay;

      expect(tuDong.state.dangCho, isTrue);
    });

    test('ghi vào sync_state hay stations không tính là có thay đổi', () async {
      // Trạm ghi sync_state mỗi vòng đồng bộ (mặc định 20 giây, nhặt hơn mốc
      // chờ yên lặng 30 giây), và trung tâm ghi stations mỗi lần trạm báo còn
      // sống. Nếu tính hai bảng này thì đồng hồ chờ yên lặng không bao giờ
      // chạm tới, sao lưu chỉ còn trông vào mốc chặn trên 10 phút.
      bat();
      tuDong.start();

      repo.setSyncMark('central_pull_mark', DateTime.now());
      repo.upsertStation(Station(
        code: 'KHO01',
        name: 'Kho 1',
        online: true,
        lastSeenAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect(tuDong.state.dangCho, isFalse);
    });
  });
}
