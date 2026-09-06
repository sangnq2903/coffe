import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Kiểm thử sao lưu và khôi phục.
///
/// Sao lưu là loại tính năng hỏng trong im lặng: không ai mở bản sao lưu ra
/// xem hằng ngày, nên nó có thể hỏng hàng tháng trời mà mọi thứ vẫn bình
/// thường — cho tới hôm cần dùng. Vì vậy phần lớn kiểm thử ở đây là kiểm thử
/// **đường về**, không phải đường đi.
void main() {
  // Vòng PBKDF2 thật là 200.000, mỗi lần chạy mất non một giây. Trong kiểm thử
  // hạ xuống cho nhanh; thuật toán không đổi, chỉ đổi số vòng lặp.
  const vongNhanh = 1000;

  Uint8List goiThu({
    List<int>? duLieu,
    String matKhau = 'cau-mat-khau-dai-va-kho-doan',
  }) =>
      BackupArchive.dongGoi(
        duLieu: duLieu ?? utf8.encode('nội dung cơ sở dữ liệu giả lập'),
        matKhau: matKhau,
        tenGoc: 'canxe-central.db',
        may: 'TRUNGTAM',
        vong: vongNhanh,
      );

  group('Đóng gói và mở gói', () {
    test('mở ra đúng từng byte đã bỏ vào', () {
      final goc = List<int>.generate(50000, (i) => (i * 7 + 3) % 256);
      final (meta, ra) = BackupArchive.moGoi(
        goi: goiThu(duLieu: goc),
        matKhau: 'cau-mat-khau-dai-va-kho-doan',
      );

      expect(ra, equals(goc));
      expect(meta.tenGoc, 'canxe-central.db');
      expect(meta.may, 'TRUNGTAM');
      expect(meta.kichThuocGoc, goc.length);
    });

    test('sai mật khẩu thì từ chối, không trả về rác', () {
      expect(
        () => BackupArchive.moGoi(goi: goiThu(), matKhau: 'sai-mat-khau'),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'lời báo', contains('sai mật khẩu'))),
      );
    });

    test('sửa một byte trong ruột gói thì bị bắt', () {
      // Không có chữ ký thì gói hỏng vẫn "giải mã" ra được, chỉ là ra rác — và
      // rác đó có thể bị ghi đè lên cơ sở dữ liệu thật.
      final goi = goiThu();
      goi[goi.length - 5] ^= 0xFF;

      expect(
        () => BackupArchive.moGoi(goi: goi, matKhau: 'cau-mat-khau-dai-va-kho-doan'),
        throwsA(isA<BackupException>()),
      );
    });

    test('sửa phần mô tả cũng bị bắt', () {
      // Phần mô tả để trần cho đọc được, nhưng vẫn nằm trong vùng được ký.
      final goi = goiThu();
      goi[20] ^= 0x01;

      expect(
        () => BackupArchive.moGoi(goi: goi, matKhau: 'cau-mat-khau-dai-va-kho-doan'),
        throwsA(isA<BackupException>()),
      );
    });

    test('gói bị cắt cụt thì báo lỗi chứ không tính bừa', () {
      final goi = goiThu();
      expect(
        () => BackupArchive.moGoi(
          goi: goi.sublist(0, goi.length - 100),
          matKhau: 'cau-mat-khau-dai-va-kho-doan',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('file lạ thì nói rõ là file lạ', () {
      expect(
        () => BackupArchive.docMeta(utf8.encode('đây là file văn bản thường')),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'lời báo', contains('không phải gói sao lưu'))),
      );
    });

    test('đọc được mô tả mà không cần mật khẩu', () {
      final meta = BackupArchive.docMeta(goiThu());
      expect(meta.may, 'TRUNGTAM');
      expect(meta.vong, vongNhanh);
    });

    test('chưa đặt mật khẩu thì không cho đóng gói', () {
      expect(
        () => BackupArchive.dongGoi(
            duLieu: [1, 2, 3], matKhau: '', tenGoc: 'a.db', may: 'X'),
        throwsA(isA<BackupException>()),
      );
    });

    test('tên gói xếp theo thứ tự thời gian', () {
      String ten(DateTime luc) => BackupArchive.docMeta(BackupArchive.dongGoi(
            duLieu: [1],
            matKhau: 'x',
            tenGoc: 'a.db',
            may: 'KHO01',
            luc: luc,
            vong: vongNhanh,
          )).tenGoi;

      final cu = ten(DateTime.utc(2026, 1, 5, 1, 30));
      final moi = ten(DateTime.utc(2026, 11, 5, 1, 30));
      expect(cu.compareTo(moi), lessThan(0),
          reason: 'kho lưu trữ sắp theo tên, nên tên phải sắp đúng theo ngày');
    });

    test('nén lại thì nhỏ hơn hẳn — dữ liệu SQLite lặp nhiều', () {
      final goc = List<int>.filled(200000, 65);
      expect(goiThu(duLieu: goc).length, lessThan(goc.length ~/ 10));
    });
  });

  group('Chụp cơ sở dữ liệu đang chạy', () {
    late Directory tempDir;
    late AppDatabase database;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('canxe-sao-luu');
      database = AppDatabase.open('${tempDir.path}/thu.db');
    });

    tearDown(() {
      database.dispose();
      tempDir.deleteSync(recursive: true);
    });

    BackupService dichVu({BackupStore? store}) => BackupService(
          config: BackupConfig(
            bat: true,
            url: 'https://vi-du.test/api/sao-luu',
            token: 'token-thu',
            matKhau: 'mat-khau-thu',
            thuMucTam: '${tempDir.path}/sao-luu',
            giuBanTaiCho: 3,
          ),
          database: database,
          may: 'TRUNGTAM',
          thuMucGoc: tempDir.path,
          store: store,
        );

    test('bản chụp có đủ dữ liệu vừa ghi', () {
      final repo = Repository(database);
      repo.upsertCustomer(Customer.create(name: 'Nguyễn Văn Bảy'));

      final chup = dichVu().chupNhanh();
      expect(chup.existsSync(), isTrue);

      // Mở bản chụp bằng SQLite khác hẳn phiên đang chạy: đây mới là thứ chứng
      // minh file đứng một mình vẫn dùng được.
      final khac = sqlite3.open(chup.path);
      try {
        expect(khac.select('PRAGMA integrity_check;').first.values.first, 'ok');
        expect(
          khac.select('SELECT name FROM customers').first.values.first,
          'Nguyễn Văn Bảy',
        );
      } finally {
        khac.dispose();
      }
    });

    test('chụp lần hai vẫn được dù file cũ còn đó', () {
      // `VACUUM INTO` từ chối ghi đè, nên không dọn trước là hôm sau hỏng.
      final d = dichVu();
      d.chupNhanh();
      expect(d.chupNhanh().existsSync(), isTrue);
    });

    test('chạy trọn một lượt: chụp, mã hoá, đẩy, và mở lại được', () async {
      Repository(database).upsertCustomer(Customer.create(name: 'Bảy Cà'));

      final kho = _KhoGia();
      final d = dichVu(store: kho.store());
      final ten = await d.chayNgay();

      expect(d.state.thanhCong, isTrue);
      expect(kho.manifest, isNotNull, reason: 'phải ghi phần mô tả sau cùng');

      final (_, duLieu) = BackupArchive.moGoi(
        goi: kho.ghep(ten),
        matKhau: 'mat-khau-thu',
      );
      final lai = File('${tempDir.path}/lai.db')..writeAsBytesSync(duLieu);
      final db = sqlite3.open(lai.path);
      try {
        expect(
          db.select('SELECT name FROM customers').first.values.first,
          'Bảy Cà',
          reason: 'đi hết một vòng mà dữ liệu vẫn về nguyên',
        );
      } finally {
        db.dispose();
      }
    });

    test('không để lại bản chụp thô trên đĩa', () async {
      // Bản chụp thô là cơ sở dữ liệu đầy đủ, không khoá. Nó mà nằm lại thì
      // việc mã hoá gói coi như vô nghĩa.
      final d = dichVu(store: _KhoGia().store());
      await d.chayNgay();
      expect(File('${tempDir.path}/sao-luu/chup-tam.db').existsSync(), isFalse);
    });

    test('giữ bản tại chỗ và dọn bản cũ', () async {
      final thuMuc = Directory('${tempDir.path}/sao-luu');
      for (var i = 0; i < 5; i++) {
        final d = dichVu(store: _KhoGia().store());
        await d.chayNgay();
        // Tên gói tính theo giây, nên phải tách các lần chạy ra.
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
      final con = thuMuc.listSync().where((f) => f.path.endsWith('.canxe')).length;
      expect(con, 3, reason: 'giu_ban_tai_cho = 3');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('thiếu cấu hình thì báo rõ thiếu gì, không chạy nửa vời', () async {
      final d = BackupService(
        config: const BackupConfig(bat: true, url: 'https://x.test/api'),
        database: database,
        may: 'TRUNGTAM',
        thuMucGoc: tempDir.path,
      );
      expect(
        () => d.chayNgay(),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'lời báo', allOf(contains('token'), contains('mat_khau')))),
      );
    });
  });

  group('Đẩy lên theo từng phần', () {
    test('gói lớn bị cắt nhỏ, ghép lại thì khớp', () async {
      // Hàm serverless của Vercel chỉ nhận thân yêu cầu tối đa 4,5 MB. Không
      // cắt thì hôm nay chạy được, vài năm nữa dữ liệu lớn lên là hỏng ngầm.
      final kho = _KhoGia();
      final store = kho.store(coPhan: 1000);
      final goi = Uint8List.fromList(List.generate(3500, (i) => i % 256));

      await store.day(
        ten: 'ban-thu',
        meta: BackupArchive.docMeta(BackupArchive.dongGoi(
            duLieu: [1], matKhau: 'x', tenGoc: 'a.db', may: 'X', vong: 1000)),
        goi: goi,
      );

      expect(kho.phan.length, 4, reason: '3500 byte chia 1000 ra 4 phần');
      expect(await store.tai('ban-thu'), equals(goi));
    });

    test('mô tả được ghi sau cùng, sau khi mọi phần đã lên', () async {
      final kho = _KhoGia();
      await kho.store(coPhan: 1000).day(
            ten: 'ban-thu',
            meta: BackupArchive.docMeta(BackupArchive.dongGoi(
                duLieu: [1], matKhau: 'x', tenGoc: 'a.db', may: 'X', vong: 1000)),
            goi: Uint8List.fromList(List.filled(2500, 1)),
          );

      // Bản chưa có mô tả bị coi là chưa xong. Ghi mô tả trước thì đứt mạng
      // giữa chừng để lại một bản trông lành lặn mà bên trong thiếu ruột.
      expect(kho.thuTu.last, 'xong');
      expect(kho.thuTu.where((e) => e == 'phan').length, 3);
    });

    test('sai token thì nói thẳng là sai token', () async {
      final store = BackupStore(
        url: 'https://vi-du.test/api/sao-luu',
        token: 'sai',
        client: MockClient((_) async => http.Response(
            jsonEncode({'loi': 'Sai hoặc thiếu token.'}), 401,
            headers: {'content-type': 'application/json'})),
      );
      expect(
        store.lietKe(),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'lời báo', contains('sai token'))),
      );
    });

    test('gọi nhầm địa chỉ thì chỉ ra là sai địa chỉ', () async {
      final store = BackupStore(
        url: 'https://vi-du.test/sai-duong-dan',
        token: 't',
        client: MockClient((_) async => http.Response('<!doctype html>', 404)),
      );
      expect(
        store.lietKe(),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'lời báo', contains('kiểm tra lại địa chỉ'))),
      );
    });

    test('tải thiếu một phần thì không im lặng trả gói cụt', () async {
      final kho = _KhoGia()..noiDoiSoByte = true;
      final store = kho.store(coPhan: 1000);
      await store.day(
        ten: 'ban-thu',
        meta: BackupArchive.docMeta(BackupArchive.dongGoi(
            duLieu: [1], matKhau: 'x', tenGoc: 'a.db', may: 'X', vong: 1000)),
        goi: Uint8List.fromList(List.filled(2500, 9)),
      );
      expect(store.tai('ban-thu'), throwsA(isA<BackupException>()));
    });
  });

  group('Đọc cấu hình', () {
    test('không có file thì tắt, không làm server đứng', () {
      final dir = Directory.systemTemp.createTempSync('canxe-cfg');
      try {
        final cfg = BackupConfig.load('${dir.path}/config.central.json');
        expect(cfg.bat, isFalse);
        expect(cfg.sanSang, isFalse);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('đọc được file đặt cạnh cấu hình chính', () {
      final dir = Directory.systemTemp.createTempSync('canxe-cfg');
      try {
        File('${dir.path}/config.sao-luu.json').writeAsStringSync(jsonEncode({
          'bat': true,
          'url': 'https://a.test/api/sao-luu',
          'token': 'tk',
          'mat_khau': 'mk',
          'giu_ban': 10,
        }));
        final cfg = BackupConfig.load('${dir.path}/config.central.json');
        expect(cfg.sanSang, isTrue);
        expect(cfg.giuBan, 10);
        expect(cfg.thieuGi(), isEmpty);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}

/// Kho giả đứng thay hàm trên Vercel, để thử được cả đường đi lẫn đường về mà
/// không phải chạm vào mạng thật.
class _KhoGia {
  final Map<int, List<int>> phan = {};
  final List<String> thuTu = [];
  Map<String, Object?>? manifest;

  /// Bật lên để giả cảnh mô tả ghi một đằng, phần thật một nẻo.
  bool noiDoiSoByte = false;

  BackupStore store({int coPhan = 2 * 1024 * 1024}) => BackupStore(
        url: 'https://vi-du.test/api/sao-luu',
        token: 'token-thu',
        coPhan: coPhan,
        client: MockClient(_xuLy),
      );

  List<int> ghep(String ten) {
    final khoa = phan.keys.toList()..sort();
    return [for (final k in khoa) ...phan[k]!];
  }

  Future<http.Response> _xuLy(http.Request req) async {
    final q = req.url.queryParameters;
    final viec = q['viec'] ?? '';

    if (req.method == 'POST' && viec == 'phan') {
      thuTu.add('phan');
      final body = jsonDecode(req.body) as Map;
      phan[int.parse(q['so']!)] = base64.decode(body['du_lieu'] as String);
      return _ok({'ok': true});
    }
    if (req.method == 'POST' && viec == 'xong') {
      thuTu.add('xong');
      manifest = (jsonDecode(req.body) as Map).cast<String, Object?>();
      return _ok({'ok': true});
    }
    if (req.method == 'GET' && viec == 'tai') {
      final m = manifest;
      if (m == null) return _ok({'loi': 'chưa xong'}, 404);
      return _ok({
        'so_phan': m['so_phan'],
        'bytes': noiDoiSoByte ? (m['bytes'] as int) + 1 : m['bytes'],
      });
    }
    if (req.method == 'GET' && viec == 'phan') {
      final so = int.parse(q['so']!);
      return http.Response.bytes(phan[so] ?? const [], phan.containsKey(so) ? 200 : 404);
    }
    if (req.method == 'GET' && viec == 'danh-sach') {
      return _ok({'ban': manifest == null ? [] : [manifest]});
    }
    return _ok({'loi': 'không hiểu'}, 400);
  }

  http.Response _ok(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
