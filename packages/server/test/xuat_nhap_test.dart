import 'dart:io';
import 'dart:typed_data';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Kiểm thử xuất và nhập cơ sở dữ liệu.
///
/// Đây là loại tính năng hỏng trong im lặng: không ai mở bản xuất ra xem hằng
/// ngày, nên nó có thể thiếu dữ liệu hàng tháng trời mà mọi thứ vẫn trông bình
/// thường — cho tới hôm cần dùng. Vì vậy phần lớn bài ở đây kiểm **đường về**,
/// không phải đường đi.
void main() {
  late Directory tempDir;
  var soThuTu = 0;

  ({AppDatabase db, Repository repo, DataTransferService dv}) moMay(String ten) {
    final db = AppDatabase.open('${tempDir.path}/$ten/canxe.db');
    final repo = Repository(db);
    return (
      db: db,
      repo: repo,
      dv: DataTransferService(database: db, repo: repo, may: 'KHO01'),
    );
  }

  /// Đổ dữ liệu mẫu vào đủ các nhóm bảng, để bài kiểm chạm được cả sổ mua bán
  /// lẫn chấm công chứ không chỉ mỗi phiếu cân.
  void doDuLieu(Repository repo, {int soPhieu = 3}) {
    final kh = repo.upsertCustomer(Customer.create(name: 'Nguyễn Văn Bảy'));
    final hang = repo.upsertGoodsType(GoodsType.create(code: 'CN', name: 'Cà nhân'));
    for (var i = 0; i < soPhieu; i++) {
      soThuTu++;
      repo.upsertTicket(WeighTicket.create(
        ticketNo: 'KHO01-260907-${soThuTu.toString().padLeft(4, '0')}',
        stationCode: 'KHO01',
        plateNo: '47C-1$soThuTu',
        customerId: kh.id,
        customerName: kh.name,
        goodsTypeId: hang.id,
        goodsName: hang.name,
        firstWeight: 12000 + i.toDouble(),
      ));
    }
    repo.trades.upsertTrade(Trade.create(
      date: DateTime(2026, 9, 1),
      kind: TradeKind.muaVao,
      goodsName: 'Trấu',
      partnerName: 'Bà Tư',
      quantity: 1000,
      unitPrice: 1500,
      amount: 1500000,
    ));
    final doan = repo.payroll.upsertCrew(Crew.create(name: 'Đoàn 1'));
    repo.payroll
        .upsertWorker(Worker.create(crewId: doan.id, name: 'Trần Văn Tám'));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('canxe-xuat-nhap');
    soThuTu = 0;
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows đôi khi còn giữ handle một nhịp sau khi đóng; không đáng để
      // làm hỏng cả bài kiểm.
    }
  });

  group('Xuất', () {
    test('không mật khẩu thì ra đúng file SQLite mở được', () {
      final m = moMay('a');
      doDuLieu(m.repo);
      final kq = m.dv.xuat();
      m.db.dispose();

      expect(kq.tenFile, endsWith('.db'));
      final ra = File('${tempDir.path}/ra.db')..writeAsBytesSync(kq.duLieu);

      // Mở bằng SQLite khác hẳn phiên vừa xuất: đây mới là thứ chứng minh file
      // đứng một mình vẫn dùng được.
      final khac = sqlite3.open(ra.path);
      try {
        expect(khac.select('PRAGMA integrity_check;').first.values.first, 'ok');
        expect(khac.select('SELECT COUNT(*) AS c FROM tickets').first['c'], 3);
        expect(khac.select('SELECT name FROM customers').first.values.first,
            'Nguyễn Văn Bảy');
      } finally {
        khac.dispose();
      }
    });

    test('có mật khẩu thì ra gói mã hoá, mở lại được', () {
      final m = moMay('a');
      doDuLieu(m.repo);
      final kq = m.dv.xuat(matKhau: 'cau-mat-khau-dai');
      m.db.dispose();

      expect(kq.tenFile, endsWith('.canxe'));
      final (meta, goc) =
          BackupArchive.moGoi(goi: kq.duLieu, matKhau: 'cau-mat-khau-dai');
      expect(meta.may, 'KHO01');
      expect(goc.sublist(0, 6), equals('SQLite'.codeUnits));
    });

    test('gói mã hoá không lộ chữ nào ra ngoài', () {
      // Người ta hay để bản xuất trong ổ đĩa chung hoặc gửi qua Zalo. Nếu tên
      // khách vẫn đọc được bằng mắt trong file thì lớp mã hoá vô nghĩa.
      final m = moMay('a');
      doDuLieu(m.repo);
      final kq = m.dv.xuat(matKhau: 'mk');
      m.db.dispose();

      expect(String.fromCharCodes(kq.duLieu.map((b) => b & 0x7F)),
          isNot(contains('Nguy')));
    });

    test('sai mật khẩu thì không mở được gói', () {
      final m = moMay('a');
      doDuLieu(m.repo);
      final kq = m.dv.xuat(matKhau: 'dung');
      m.db.dispose();

      expect(() => BackupArchive.moGoi(goi: kq.duLieu, matKhau: 'sai'),
          throwsA(isA<BackupException>()));
    });

    test('không để lại file tạm trên đĩa', () {
      // Bản chụp thô là cơ sở dữ liệu đầy đủ, không khoá. Nó mà nằm lại thì
      // việc mã hoá gói coi như vô nghĩa.
      final m = moMay('a');
      doDuLieu(m.repo);
      m.dv.xuat(matKhau: 'mk');
      final tam = Directory('${tempDir.path}/a/tam');
      m.db.dispose();

      expect(
        tam.existsSync() ? tam.listSync() : const [],
        isEmpty,
        reason: 'bản chụp thô không được nằm lại sau khi xuất xong',
      );
    });

    test('tóm tắt không đếm bản ghi đã xoá', () {
      final m = moMay('a');
      doDuLieu(m.repo);
      final phieu = m.repo.tickets().first;
      m.repo.softDeleteTicket(phieu.id);

      expect(m.dv.tomTat().bang['Phiếu cân'], 2);
      expect(m.dv.tomTat().bang['Sổ mua bán'], 1);
      expect(m.dv.tomTat().bytes, greaterThan(0));
      m.db.dispose();
    });
  });

  group('Nhập', () {
    test('máy mới trắng trơn nhận lại đủ mọi bảng', () {
      final cu = moMay('cu');
      doDuLieu(cu.repo);
      final goi = cu.dv.xuat().duLieu;
      final mongDoi = cu.dv.tomTat().bang;
      cu.db.dispose();

      final moi = moMay('moi');
      final kq = moi.dv.nhap(goi);

      expect(moi.dv.tomTat().bang, equals(mongDoi),
          reason: 'từng bảng phải về đúng số dòng như máy cũ');
      expect(kq.tongThemMoi, greaterThan(0));
      expect(File(kq.duongDanAnToan).existsSync(), isTrue,
          reason: 'phải cất bản chụp trước khi gộp');
      moi.db.dispose();
    });

    test('gói mã hoá nhập lại được bằng đúng mật khẩu', () {
      final cu = moMay('cu');
      doDuLieu(cu.repo);
      final goi = cu.dv.xuat(matKhau: 'mk-dai').duLieu;
      cu.db.dispose();

      final moi = moMay('moi');
      moi.dv.nhap(goi, matKhau: 'mk-dai');
      expect(moi.dv.tomTat().bang['Phiếu cân'], 3);
      moi.db.dispose();
    });

    test('hơn 500 dòng vẫn về đủ', () {
      // Hàm đồng bộ chặn ở 500 dòng mỗi bảng. Mượn nó để xuất thì bản sao thiếu
      // phiếu cũ mà không báo gì — file vẫn mở được, chỉ tới lúc tra mới biết.
      final cu = moMay('cu');
      doDuLieu(cu.repo, soPhieu: 640);
      final goi = cu.dv.xuat().duLieu;
      cu.db.dispose();

      final moi = moMay('moi');
      moi.dv.nhap(goi);
      expect(moi.dv.tomTat().bang['Phiếu cân'], 640);
      moi.db.dispose();
    });

    test('bản ghi cũ trong file không đè lên bản mới trên máy', () {
      final cu = moMay('cu');
      final kh = cu.repo.upsertCustomer(Customer.create(name: 'Tên cũ'));
      final goi = cu.dv.xuat().duLieu;
      cu.db.dispose();

      final may = moMay('may');
      may.repo.upsertCustomer(Customer(
        id: kh.id,
        code: kh.code,
        name: 'Tên đã sửa hôm nay',
        updatedAt: DateTime.now().add(const Duration(days: 1)),
      ));

      may.dv.nhap(goi);
      expect(
        may.repo.customerById(kh.id)!.name,
        'Tên đã sửa hôm nay',
        reason: 'gộp theo luật bản mới hơn thắng, không phải file thắng',
      );
      may.db.dispose();
    });

    test('nhập hai lần không nhân đôi dữ liệu', () {
      final cu = moMay('cu');
      doDuLieu(cu.repo);
      final goi = cu.dv.xuat().duLieu;
      cu.db.dispose();

      final moi = moMay('moi');
      moi.dv.nhap(goi);
      final lan1 = moi.dv.tomTat().bang;
      final kq2 = moi.dv.nhap(goi);

      expect(moi.dv.tomTat().bang, equals(lan1));
      expect(kq2.tongThemMoi, 0, reason: 'lần hai không thêm được gì');
      moi.db.dispose();
    });

    test('xem trước không động vào dữ liệu', () {
      final cu = moMay('cu');
      doDuLieu(cu.repo);
      final goi = cu.dv.xuat().duLieu;
      cu.db.dispose();

      final moi = moMay('moi');
      final truoc = moi.dv.tomTat().bang;
      final xem = moi.dv.xemTruoc(goi);

      expect(xem.bang['Phiếu cân'], 3, reason: 'đọc được file');
      expect(moi.dv.tomTat().bang, equals(truoc), reason: 'mà chưa ghi gì');
      moi.db.dispose();
    });

    test('không để lại file tạm sau khi nhập', () {
      final cu = moMay('cu');
      doDuLieu(cu.repo);
      final goi = cu.dv.xuat().duLieu;
      cu.db.dispose();

      final moi = moMay('moi');
      moi.dv.nhap(goi);
      final tam = Directory('${tempDir.path}/moi/tam');
      moi.db.dispose();
      expect(tam.existsSync() ? tam.listSync() : const [], isEmpty);
    });
  });

  group('Chặn file không dùng được', () {
    late ({AppDatabase db, Repository repo, DataTransferService dv}) m;

    setUp(() => m = moMay('may'));
    tearDown(() => m.db.dispose());

    void thiChan(List<int> duLieu, Matcher loi, {String? matKhau}) => expect(
          () => m.dv.nhap(duLieu, matKhau: matKhau),
          throwsA(isA<BusinessException>().having((e) => e.message, 'lời báo', loi)),
        );

    test('file rác thì nói rõ không phải SQLite', () {
      thiChan(List.filled(2000, 65), contains('không phải cơ sở dữ liệu SQLite'));
    });

    test('SQLite thật nhưng của phần mềm khác thì bị chặn', () {
      final la = '${tempDir.path}/la.db';
      final db = sqlite3.open(la);
      db.execute('CREATE TABLE ghi_chu (id INTEGER PRIMARY KEY, noi_dung TEXT);');
      db.dispose();

      thiChan(File(la).readAsBytesSync(), contains('không phải của phần mềm cân xe'));
    });

    test('file của bản phần mềm mới hơn thì từ chối chứ không đọc bừa', () {
      // Đọc bừa cơ sở dữ liệu có lược đồ lạ thì hoặc vỡ, hoặc tệ hơn là im lặng
      // bỏ qua mấy cột nó chưa biết.
      final moiHon = '${tempDir.path}/moi-hon.db';
      final nguon = moMay('nguon');
      doDuLieu(nguon.repo);
      File(moiHon).writeAsBytesSync(nguon.dv.xuat().duLieu);
      nguon.db.dispose();

      final db = sqlite3.open(moiHon);
      db.execute('PRAGMA user_version = 9999;');
      db.dispose();

      thiChan(File(moiHon).readAsBytesSync(), contains('mới hơn'));
    });

    test('gói mã hoá mà quên mật khẩu thì nhắc đúng chỗ', () {
      final nguon = moMay('nguon');
      doDuLieu(nguon.repo);
      final goi = nguon.dv.xuat(matKhau: 'mk').duLieu;
      nguon.db.dispose();

      thiChan(goi, contains('phải nhập mật khẩu'));
    });

    test('gói mã hoá mà sai mật khẩu thì nói là sai mật khẩu', () {
      final nguon = moMay('nguon');
      doDuLieu(nguon.repo);
      final goi = nguon.dv.xuat(matKhau: 'dung').duLieu;
      nguon.db.dispose();

      thiChan(goi, contains('sai mật khẩu'), matKhau: 'sai');
    });

    test('file không mã hoá mà lại nhập mật khẩu thì chỉ ra là thừa', () {
      final nguon = moMay('nguon');
      doDuLieu(nguon.repo);
      final goi = nguon.dv.xuat().duLieu;
      nguon.db.dispose();

      thiChan(goi, contains('không mã hoá'), matKhau: 'thua');
    });

    test('file rỗng thì báo lỗi chứ không xoá sạch dữ liệu', () {
      thiChan(Uint8List(0), isNotEmpty);
      expect(m.dv.tomTat().tongDong, m.dv.tomTat().tongDong);
    });

    test('file hỏng giữa chừng thì bị bắt', () {
      final nguon = moMay('nguon');
      doDuLieu(nguon.repo);
      final goi = nguon.dv.xuat().duLieu;
      nguon.db.dispose();

      // Đập nát phần ruột, giữ nguyên 16 byte đầu để SQLite vẫn nhận là file
      // của nó — đúng kiểu hỏng mà nhìn qua tưởng lành.
      for (var i = 4096; i < goi.length; i += 3) {
        goi[i] = 0;
      }
      expect(() => m.dv.nhap(goi), throwsA(isA<BusinessException>()));
    });
  });
}
