import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Kiểm thử tầng dữ liệu của module chấm công.
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late PayrollRepository payroll;

  late Crew doanA;
  late Crew doanB;
  late WagePhase dauMua;
  late WagePhase muaRo;
  late WageBand thoChinh;
  late WageBand thoPhu;
  late Worker nguoiThuong;
  late Worker nguoiGiaRieng;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('canxe-payroll');
    database = AppDatabase.open('${tempDir.path}/thu.db');
    repo = Repository(database);
    payroll = repo.payroll;

    doanA = payroll.upsertCrew(
      Crew.create(name: 'Đoàn hái', season: '2025-2026'),
    );
    doanB = payroll.upsertCrew(
      Crew.create(name: 'Đoàn tưới', season: '2025-2026'),
    );

    dauMua = payroll.upsertPhase(WagePhase.create(
      crewId: doanA.id,
      name: 'Đầu mùa',
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 10, 15),
      sortOrder: 1,
    ));
    muaRo = payroll.upsertPhase(WagePhase.create(
      crewId: doanA.id,
      name: 'Mùa rộ',
      fromDate: DateTime(2026, 10, 16),
      sortOrder: 2,
    ));

    thoChinh = payroll.upsertBand(WageBand.create(crewId: doanA.id, name: 'Thợ chính'));
    thoPhu = payroll.upsertBand(WageBand.create(crewId: doanA.id, name: 'Thợ phụ'));

    for (final (band, dau, ro) in [
      (thoChinh, 8000000.0, 12000000.0),
      (thoPhu, 6500000.0, 9000000.0),
    ]) {
      payroll.upsertRate(WageRate.forBand(
          crewId: doanA.id, phaseId: dauMua.id, bandId: band.id, monthlyAmount: dau));
      payroll.upsertRate(WageRate.forBand(
          crewId: doanA.id, phaseId: muaRo.id, bandId: band.id, monthlyAmount: ro));
    }

    nguoiThuong = payroll.upsertWorker(
      Worker.create(crewId: doanA.id, name: 'Nguyễn Văn A', bandId: thoChinh.id),
    );
    nguoiGiaRieng = payroll.upsertWorker(
      Worker.create(crewId: doanA.id, name: 'Trần Văn B', bandId: thoPhu.id),
    );
  });

  tearDown(() {
    database.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('Mức lương và giá', () {
    test('tra ra đúng lương tháng theo mức và theo giai đoạn', () {
      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: dauMua.id, worker: nguoiThuong),
        8000000,
      );
      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: muaRo.id, worker: nguoiThuong),
        12000000,
      );
      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: dauMua.id, worker: nguoiGiaRieng),
        6500000,
      );
    });

    test('sửa mức lương chung thì cả nhóm đổi theo', () {
      final gia = payroll
          .rates(doanA.id)
          .firstWhere((r) => r.bandId == thoChinh.id && r.phaseId == muaRo.id);
      payroll.upsertRate(gia.copyWith(monthlyAmount: 13000000));

      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: muaRo.id, worker: nguoiThuong),
        13000000,
      );
    });

    test('giá đặt riêng cho một người thắng giá của mức chung', () {
      payroll.upsertRate(WageRate.forWorker(
        crewId: doanA.id,
        phaseId: dauMua.id,
        workerId: nguoiGiaRieng.id,
        monthlyAmount: 7200000,
      ));

      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: dauMua.id, worker: nguoiGiaRieng),
        7200000,
        reason: 'người đặt riêng phải lấy giá riêng',
      );
      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: dauMua.id, worker: nguoiThuong),
        8000000,
        reason: 'người khác trong cùng mức không bị ảnh hưởng',
      );
    });

    test('người chưa gán mức nào thì không tra ra giá', () {
      final chuaGan =
          payroll.upsertWorker(Worker.create(crewId: doanA.id, name: 'Chưa gán'));
      expect(
        payroll.monthlyAmountFor(
            crewId: doanA.id, phaseId: dauMua.id, worker: chuaGan),
        isNull,
      );
    });
  });

  group('Giai đoạn theo ngày', () {
    test('tra đúng giai đoạn của một ngày, kể cả ngày sát mốc chuyển', () {
      expect(payroll.phaseForDate(doanA.id, DateTime(2026, 9, 20))?.id, dauMua.id);
      expect(payroll.phaseForDate(doanA.id, DateTime(2026, 10, 15))?.id, dauMua.id);
      expect(payroll.phaseForDate(doanA.id, DateTime(2026, 10, 16))?.id, muaRo.id);
    });

    test('ngày ngoài mọi giai đoạn thì không tra ra gì', () {
      expect(payroll.phaseForDate(doanA.id, DateTime(2026, 8, 1)), isNull);
    });
  });

  group('Chấm công', () {
    Attendance cham(DateTime date, {bool present = true}) =>
        payroll.upsertAttendance(Attendance.create(
          crewId: doanA.id,
          workerId: nguoiThuong.id,
          date: date,
          monthlyAmount: 8000000,
          phaseId: dauMua.id,
          present: present,
        ));

    test('lưu kèm mức lương và số ngày của tháng tại thời điểm chấm', () {
      final ghi = cham(DateTime(2026, 9, 10));
      expect(ghi.monthlyAmount, 8000000);
      expect(ghi.daysInMonth, 30);
    });

    test('sửa bảng giá sau đó không làm đổi bản ghi đã chấm', () {
      cham(DateTime(2026, 9, 10));
      final gia = payroll
          .rates(doanA.id)
          .firstWhere((r) => r.bandId == thoChinh.id && r.phaseId == dauMua.id);
      payroll.upsertRate(gia.copyWith(monthlyAmount: 99000000));

      final daCham = payroll.attendances(workerId: nguoiThuong.id).single;
      expect(daCham.monthlyAmount, 8000000,
          reason: 'lương tháng trước đã trả rồi, không được tự nhảy');
    });

    test('một người một ngày chỉ được một bản ghi', () {
      cham(DateTime(2026, 9, 10));
      // Chấm lần hai cùng ngày với id khác là tính công gấp đôi mà không ai
      // nhìn ra — cơ sở dữ liệu phải chặn thẳng.
      expect(
        () => payroll.upsertAttendance(Attendance.create(
          crewId: doanA.id,
          workerId: nguoiThuong.id,
          date: DateTime(2026, 9, 10),
          monthlyAmount: 8000000,
        )),
        throwsA(isA<SqliteException>()),
      );
    });

    test('tra được bản ghi của một ngày để sửa thay vì tạo mới', () {
      final ghi = cham(DateTime(2026, 9, 10));
      final tim = payroll.attendanceOn(nguoiThuong.id, DateTime(2026, 9, 10, 17, 30));
      expect(tim?.id, ghi.id, reason: 'giờ trong ngày không được làm lệch');

      payroll.upsertAttendance(tim!.copyWith(present: false));
      expect(payroll.attendanceOn(nguoiThuong.id, DateTime(2026, 9, 10))!.present, isFalse);
    });

    test('lọc được theo khoảng ngày', () {
      cham(DateTime(2026, 9, 5));
      cham(DateTime(2026, 9, 20));
      cham(DateTime(2026, 10, 5));

      final thang9 = payroll.attendances(
        workerId: nguoiThuong.id,
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(thang9.length, 2);
    });

    test('nối được với công thức tính lương', () {
      for (var d = 1; d <= 30; d++) {
        cham(DateTime(2026, 9, d));
      }
      final thang = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: payroll.attendances(workerId: nguoiThuong.id),
        entries: payroll.entries(workerId: nguoiThuong.id),
      );
      expect(thang.daysWorked, 30);
      expect(thang.wageEarned, 8000000);
      expect(thang.advanceCap, 4000000);
    });
  });

  group('Sổ tiền', () {
    test('ghi và đọc lại được các loại khoản', () {
      for (final type in PayrollEntryType.values) {
        payroll.upsertEntry(PayrollEntry.create(
          crewId: doanA.id,
          workerId: nguoiThuong.id,
          type: type,
          amount: 100000,
          date: DateTime(2026, 9, 15),
        ));
      }
      expect(payroll.entries(workerId: nguoiThuong.id).length,
          PayrollEntryType.values.length);
      expect(
        payroll.entries(workerId: nguoiThuong.id, type: PayrollEntryType.ungLuong).length,
        1,
      );
    });

    test('giữ lại lý do khi ứng vượt trần', () {
      final ghi = payroll.upsertEntry(PayrollEntry.create(
        crewId: doanA.id,
        workerId: nguoiThuong.id,
        type: PayrollEntryType.ungLuong,
        amount: 5000000,
        overCapReason: 'Chủ duyệt cho ứng gấp lo việc gia đình',
      ));
      expect(ghi.isOverCap, isTrue);
      expect(payroll.entryById(ghi.id)!.overCapReason, contains('Chủ duyệt'));
    });
  });

  group('Chuyển kho', () {
    test('kho là thuộc tính của từng người, không của cả đoàn', () {
      final o = payroll.upsertWorker(nguoiThuong.copyWith(stationCode: 'kho01'));
      final b = payroll.upsertWorker(nguoiGiaRieng.copyWith(stationCode: 'KHO02'));

      // Viết chữ thường vẫn phải ra mã chuẩn, không thì lọc theo kho sẽ trượt.
      expect(o.stationCode, 'KHO01');
      expect(b.stationCode, 'KHO02');

      expect(
        payroll.workers(doanA.id, stationCode: 'KHO01').map((e) => e.id),
        [o.id],
      );
      expect(
        payroll.workers(doanA.id, stationCode: 'kho02').map((e) => e.id),
        [b.id],
      );
    });

    test('chuyển kho hôm nay không làm đổi số liệu đã chấm', () {
      payroll.upsertWorker(nguoiThuong.copyWith(stationCode: 'KHO01'));
      final ngayCu = payroll.upsertAttendance(Attendance.create(
        crewId: doanA.id,
        workerId: nguoiThuong.id,
        date: DateTime(2026, 9, 10),
        stationCode: 'KHO01',
        monthlyAmount: 8000000,
      ));

      // Chuyển sang kho 2 rồi chấm tiếp: ngày cũ vẫn phải thuộc kho 1.
      payroll.upsertWorker(nguoiThuong.copyWith(stationCode: 'KHO02'));
      final ngayMoi = payroll.upsertAttendance(Attendance.create(
        crewId: doanA.id,
        workerId: nguoiThuong.id,
        date: DateTime(2026, 9, 11),
        stationCode: 'KHO02',
        monthlyAmount: 8000000,
      ));

      expect(payroll.attendanceById(ngayCu.id)!.stationCode, 'KHO01');
      expect(payroll.attendanceById(ngayMoi.id)!.stationCode, 'KHO02');
    });
  });

  group('Đồng bộ', () {
    setUp(() {
      final nguoiKhac = payroll
          .upsertWorker(Worker.create(crewId: doanB.id, name: 'Người đoàn khác'));
      payroll.upsertAttendance(Attendance.create(
        crewId: doanB.id,
        workerId: nguoiKhac.id,
        date: DateTime(2026, 9, 10),
        monthlyAmount: 5000000,
      ));
      payroll.upsertEntry(PayrollEntry.create(
        crewId: doanB.id,
        workerId: nguoiKhac.id,
        type: PayrollEntryType.ungLuong,
        amount: 1000000,
      ));
    });

    test('kéo về lương của cả công ty, không cắt theo kho', () {
      // Người trong đoàn chuyển kho qua lại nên bảng lương phải cộng được
      // xuyên kho — cắt theo kho thì máy ở kho 1 tính thiếu ngày làm ở kho 2.
      final data = payroll.changesSince(null);
      expect(data.crews.map((e) => e.id).toSet(), {doanA.id, doanB.id});
      expect(data.workers, isNotEmpty);
      expect(data.attendances, isNotEmpty);
      expect(data.entries, isNotEmpty);
    });

    test('gói đồng bộ chung mang theo cả dữ liệu chấm công', () {
      // Phiếu cân vẫn cắt theo kho, phần lương thì không.
      final goi = repo.changesSince(null, allowedStations: ['KHO01']);
      expect(goi.payroll.crews.map((e) => e.id).toSet(), {doanA.id, doanB.id});
    });

    test('đếm bản ghi chờ đẩy có tính cả phần chấm công', () {
      expect(repo.pendingPushCount(), greaterThan(0));
      expect(payroll.pendingPushCount(), greaterThan(0));
    });

    test('ghi dữ liệu nhận được rồi xoá cờ chờ đẩy', () {
      final data = payroll.dirtyChanges();
      expect(data.totalRecords, greaterThan(0));

      payroll.clearDirty(data);
      expect(payroll.pendingPushCount(), 0);

      // Nhận lại chính gói đó từ bên kia thì không được đánh dấu chờ đẩy nữa,
      // nếu không hai máy sẽ đẩy qua đẩy lại mãi.
      payroll.applyPayload(data, markDirty: false);
      expect(payroll.pendingPushCount(), 0);
    });
  });
}
