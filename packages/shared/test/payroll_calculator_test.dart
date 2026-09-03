import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

/// Kiểm thử công thức lương và trần ứng.
///
/// Đây là nơi tiền thật đi qua: sai một công thức là công nhân nhận thiếu hoặc
/// nhận thừa mà không ai phát hiện ra cho tới cuối mùa.
void main() {
  const crew = 'doan-1';
  const worker = 'nguoi-1';

  // Hai giai đoạn theo đúng nghiệp vụ: đầu mùa rẻ hơn, mùa rộ cao hơn.
  const luongDauMua = 8000000.0;
  const luongMuaRo = 12000000.0;

  /// Chấm công liên tục [days] ngày kể từ ngày 1 của tháng.
  List<Attendance> chamCong({
    required int year,
    required int month,
    required int days,
    double monthlyAmount = luongDauMua,
    int startDay = 1,
  }) =>
      List.generate(
        days,
        (i) => Attendance.create(
          crewId: crew,
          workerId: worker,
          date: DateTime(year, month, startDay + i),
          monthlyAmount: monthlyAmount,
        ),
      );

  PayrollEntry khoan(PayrollEntryType type, double amount,
          {int year = 2026, int month = 9, int day = 15, String? reason}) =>
      PayrollEntry.create(
        crewId: crew,
        workerId: worker,
        type: type,
        amount: amount,
        date: DateTime(year, month, day),
        overCapReason: reason,
      );

  group('Lương theo ngày công', () {
    test('đi làm đủ tháng thì nhận đúng lương tháng, không lệch một đồng', () {
      // Tháng 9 có 30 ngày. Chia 8.000.000 cho 30 ra số lẻ vô hạn, nếu cộng
      // tiền của từng ngày lại sẽ không ra tròn 8.000.000.
      final cong = chamCong(year: 2026, month: 9, days: 30);
      expect(PayrollCalculator.wageEarnedInMonth(cong), luongDauMua);
    });

    test('tháng 31 ngày đi làm đủ cũng ra đúng lương tháng', () {
      final cong = chamCong(year: 2026, month: 10, days: 31);
      expect(PayrollCalculator.wageEarnedInMonth(cong), luongDauMua);
    });

    test('tháng 2 nhuận 29 ngày vẫn đúng', () {
      final cong = chamCong(year: 2028, month: 2, days: 29);
      expect(PayrollCalculator.wageEarnedInMonth(cong), luongDauMua);
    });

    test('nghỉ ngày nào mất công ngày đó', () {
      // Tháng 9 có 30 ngày, đi làm 28 → nhận 28/30 lương tháng.
      final cong = chamCong(year: 2026, month: 9, days: 28);
      expect(PayrollCalculator.wageEarnedInMonth(cong),
          (luongDauMua * 28 / 30).roundToDouble());
    });

    test('ngày chấm là nghỉ thì không tính công', () {
      final cong = [
        ...chamCong(year: 2026, month: 9, days: 10),
        Attendance.create(
          crewId: crew,
          workerId: worker,
          date: DateTime(2026, 9, 11),
          monthlyAmount: luongDauMua,
          present: false,
        ),
      ];
      expect(PayrollCalculator.wageEarnedInMonth(cong),
          (luongDauMua * 10 / 30).roundToDouble());
    });

    test('bản ghi đã xoá không được tính vào lương', () {
      final cong = chamCong(year: 2026, month: 9, days: 10);
      final coXoa = [...cong, cong.first.copyWith(deleted: true)];
      expect(PayrollCalculator.wageEarnedInMonth(coXoa),
          PayrollCalculator.wageEarnedInMonth(cong));
    });

    test('tháng vắt qua hai giai đoạn thì cộng hai phần', () {
      // Mốc chuyển 16/10: 15 ngày đầu mùa + 16 ngày mùa rộ, tháng 31 ngày.
      final cong = [
        ...chamCong(year: 2026, month: 10, days: 15, monthlyAmount: luongDauMua),
        ...chamCong(
            year: 2026, month: 10, days: 16, startDay: 16, monthlyAmount: luongMuaRo),
      ];
      final mongDoi =
          (luongDauMua * 15 / 31 + luongMuaRo * 16 / 31).roundToDouble();
      expect(PayrollCalculator.wageEarnedInMonth(cong), mongDoi);
    });

    test('chưa chấm ngày nào thì lương bằng 0', () {
      expect(PayrollCalculator.wageEarnedInMonth(const []), 0);
    });

    test('nghỉ vài giờ thì hưởng theo tỷ lệ trên giờ chuẩn', () {
      // Ca đầu mùa 8,5 giờ; nghỉ 2 giờ thì còn 6,5/8,5 ngày công.
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final nghiHaiGio = cong.first.copyWith(hoursOff: 2, standardHours: 8.5);
      final thang = [nghiHaiGio, ...cong.skip(1)];

      expect(nghiHaiGio.workUnit, closeTo(6.5 / 8.5, 1e-9));
      expect(
        PayrollCalculator.wageEarnedInMonth(thang),
        (luongDauMua * (29 + 6.5 / 8.5) / 30).round(),
      );
      expect(PayrollCalculator.workUnitsInMonth(thang), closeTo(29 + 6.5 / 8.5, 1e-9));
    });

    test('ca mùa rộ 12 giờ thì cùng số giờ nghỉ mất ít công hơn', () {
      final dauMua = Attendance.create(
          crewId: crew, workerId: worker, date: DateTime(2026, 9, 1),
          monthlyAmount: luongDauMua, hoursOff: 3, standardHours: 8.5);
      final muaRo = Attendance.create(
          crewId: crew, workerId: worker, date: DateTime(2026, 11, 1),
          monthlyAmount: luongMuaRo, hoursOff: 3, standardHours: 12);
      expect(dauMua.workUnit, lessThan(muaRo.workUnit));
      expect(muaRo.workUnit, closeTo(9 / 12, 1e-9));
    });

    test('nghỉ đủ giờ chuẩn thì bằng nghỉ cả ngày, không âm', () {
      final a = Attendance.create(
          crewId: crew, workerId: worker, date: DateTime(2026, 9, 1),
          monthlyAmount: luongDauMua, hoursOff: 10, standardHours: 8.5);
      expect(a.workUnit, 0);
      expect(a.hoursWorked, 0);
    });

    test('đổi thành nghỉ cả ngày thì giờ nghỉ cũ bị xoá', () {
      final a = Attendance.create(
          crewId: crew, workerId: worker, date: DateTime(2026, 9, 1),
          monthlyAmount: luongDauMua, hoursOff: 2);
      final nghi = a.copyWith(present: false);
      expect(nghi.hoursOff, 0);
      // Cho đi làm lại thì bắt đầu từ đủ ngày, không lôi 2 giờ cũ về.
      expect(nghi.copyWith(present: true).workUnit, 1);
    });
  });

  group('Trần ứng 50%', () {
    test('trần đúng bằng nửa thu nhập đã làm được', () {
      // Ngày 10, mới làm 8 ngày trong tháng 30 ngày.
      final thang = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: chamCong(year: 2026, month: 9, days: 8),
        entries: const [],
      );
      final luong = (luongDauMua * 8 / 30).roundToDouble();
      expect(thang.wageEarned, luong);
      expect(thang.advanceCap, (luong / 2).roundToDouble());
      expect(thang.remainingAdvance, thang.advanceCap);
    });

    test('trần nhích lên theo từng ngày đi làm', () {
      double tran(int soNgay) => PayrollCalculator.monthly(
            monthKey: '2026-09',
            attendances: chamCong(year: 2026, month: 9, days: soNgay),
            entries: const [],
          ).advanceCap;

      expect(tran(15), greaterThan(tran(8)));
      expect(tran(30), greaterThan(tran(15)));
    });

    test('tăng ca và phụ cấp làm trần cao lên, tiền phạt làm trần thấp xuống', () {
      final cong = chamCong(year: 2026, month: 9, days: 30);

      final khongKhoan = PayrollCalculator.monthly(
          monthKey: '2026-09', attendances: cong, entries: const []);
      final coThem = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: cong,
        entries: [
          khoan(PayrollEntryType.tangCa, 500000),
          khoan(PayrollEntryType.phuCap, 300000),
          khoan(PayrollEntryType.truTien, 200000),
        ],
      );

      expect(coThem.income, khongKhoan.income + 500000 + 300000 - 200000);
      expect(coThem.advanceCap, (coThem.income / 2).roundToDouble());
    });

    test('đã ứng rồi thì phần còn được ứng giảm đi đúng bấy nhiêu', () {
      final thang = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: chamCong(year: 2026, month: 9, days: 30),
        entries: [khoan(PayrollEntryType.ungLuong, 1000000)],
      );
      expect(thang.advanced, 1000000);
      expect(thang.remainingAdvance, thang.advanceCap - 1000000);
    });

    test('ứng hết trần thì không còn được ứng, và không ra số âm', () {
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final tran = PayrollCalculator.monthly(
              monthKey: '2026-09', attendances: cong, entries: const [])
          .advanceCap;

      final thang = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: cong,
        entries: [khoan(PayrollEntryType.ungLuong, tran + 500000)],
      );
      expect(thang.remainingAdvance, 0);
      expect(thang.overCap, isTrue);
    });

    test('ứng lương và thanh toán KHÔNG làm tăng thu nhập', () {
      // Nếu lẫn hai nhóm này vào thu nhập thì cứ ứng một lần là trần lại cao
      // lên, ứng được vô hạn.
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final goc = PayrollCalculator.monthly(
          monthKey: '2026-09', attendances: cong, entries: const []);
      final sauKhiUng = PayrollCalculator.monthly(
        monthKey: '2026-09',
        attendances: cong,
        entries: [
          khoan(PayrollEntryType.ungLuong, 2000000),
          khoan(PayrollEntryType.thanhToan, 1000000),
        ],
      );
      expect(sauKhiUng.income, goc.income);
      expect(sauKhiUng.advanceCap, goc.advanceCap);
    });
  });

  group('Nợ dồn không làm tăng trần ứng', () {
    test('tháng sau vẫn chỉ được ứng nửa lương tháng sau', () {
      // Tháng 9: làm đủ, ứng hết trần → treo lại một nửa.
      final congT9 = chamCong(year: 2026, month: 9, days: 30);
      final tranT9 = PayrollCalculator.monthly(
              monthKey: '2026-09', attendances: congT9, entries: const [])
          .advanceCap;

      // Tháng 10 mùa rộ, làm đủ 31 ngày.
      final congT10 =
          chamCong(year: 2026, month: 10, days: 31, monthlyAmount: luongMuaRo);

      final tatCaCong = [...congT9, ...congT10];
      final tatCaKhoan = [
        khoan(PayrollEntryType.ungLuong, tranT9, month: 9, day: 30),
      ];

      final thang10 = PayrollCalculator.monthly(
        monthKey: '2026-10',
        attendances: tatCaCong,
        entries: tatCaKhoan,
      );

      // Trần tháng 10 chỉ dựa trên lương tháng 10, không cộng phần treo của T9.
      expect(thang10.advanced, 0, reason: 'khoản ứng tháng 9 không tính sang tháng 10');
      expect(thang10.advanceCap, (luongMuaRo / 2).roundToDouble());
      expect(thang10.remainingAdvance, (luongMuaRo / 2).roundToDouble());

      // Trong khi đó công nợ vẫn đang treo một khoản lớn.
      final congNo = PayrollCalculator.balance(
          attendances: tatCaCong, entries: tatCaKhoan);
      expect(congNo.balance, greaterThan(thang10.advanceCap),
          reason: 'nợ nhiều hơn trần nhưng trần không vì thế mà cao lên');
    });
  });

  group('Kiểm tra một lần ứng', () {
    MonthlyPayroll thangDayDu({double daUng = 0}) => PayrollCalculator.monthly(
          monthKey: '2026-09',
          attendances: chamCong(year: 2026, month: 9, days: 30),
          entries: daUng == 0 ? const [] : [khoan(PayrollEntryType.ungLuong, daUng)],
        );

    test('ứng trong trần thì không cảnh báo', () {
      final check = PayrollCalculator.checkAdvance(
          month: thangDayDu(), requested: 1000000);
      expect(check.exceedsCap, isFalse);
      expect(check.warning, isNull);
      expect(check.excess, 0);
    });

    test('ứng đúng bằng trần vẫn được, không tính là vượt', () {
      final thang = thangDayDu();
      final check = PayrollCalculator.checkAdvance(
          month: thang, requested: thang.advanceCap);
      expect(check.exceedsCap, isFalse);
    });

    test('ứng quá trần thì báo rõ vượt bao nhiêu', () {
      final thang = thangDayDu();
      final check = PayrollCalculator.checkAdvance(
          month: thang, requested: thang.advanceCap + 250000);

      expect(check.exceedsCap, isTrue);
      expect(check.excess, 250000);
      expect(check.warning, contains('Vượt trần'));
      expect(check.warning, contains('250.000 đ'));
    });

    test('đã ứng hết trần rồi thì cảnh báo nói rõ là hết mức', () {
      final thang = thangDayDu(daUng: 4000000);
      final check = PayrollCalculator.checkAdvance(month: thang, requested: 100000);
      expect(check.exceedsCap, isTrue);
      expect(check.warning, contains('đã ứng hết mức'));
    });

    test('làm tròn tiền ứng xuống bội số 10.000', () {
      expect(PayrollCalculator.roundAdvanceDown(1234567), 1230000);
      expect(PayrollCalculator.roundAdvanceDown(9999), 0);
      expect(PayrollCalculator.roundAdvanceDown(-5000), 0);
    });
  });

  group('Công nợ cả mùa', () {
    test('còn phải trả bằng thu nhập trừ đi phần đã nhận', () {
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final congNo = PayrollCalculator.balance(
        attendances: cong,
        entries: [
          khoan(PayrollEntryType.phuCap, 500000),
          khoan(PayrollEntryType.ungLuong, 3000000),
        ],
      );
      expect(congNo.totalEarned, luongDauMua + 500000);
      expect(congNo.totalReceived, 3000000);
      expect(congNo.balance, luongDauMua + 500000 - 3000000);
      expect(congNo.isNegative, isFalse);
    });

    test('nhận vượt công đã làm thì số dư âm và bị đánh dấu', () {
      // Đúng tình huống trong ảnh: ông A Tình âm 30 triệu.
      final cong = chamCong(year: 2026, month: 9, days: 10);
      final congNo = PayrollCalculator.balance(
        attendances: cong,
        entries: [khoan(PayrollEntryType.ungLuong, 5000000)],
      );
      expect(congNo.isNegative, isTrue);
      expect(congNo.balance, lessThan(0));
    });

    test('cộng đúng qua nhiều tháng và nhiều giai đoạn lương', () {
      final cong = [
        ...chamCong(year: 2026, month: 9, days: 30),
        ...chamCong(year: 2026, month: 10, days: 31, monthlyAmount: luongMuaRo),
      ];
      final congNo =
          PayrollCalculator.balance(attendances: cong, entries: const []);
      expect(congNo.totalEarned, luongDauMua + luongMuaRo);
    });

    test('thanh toán cuối mùa đưa số dư về 0', () {
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final congNo = PayrollCalculator.balance(
        attendances: cong,
        entries: [
          khoan(PayrollEntryType.ungLuong, 4000000),
          khoan(PayrollEntryType.thanhToan, 4000000, month: 12, day: 31),
        ],
      );
      expect(congNo.balance, 0);
    });

    test('tiền phạt làm giảm thu nhập cả mùa', () {
      final cong = chamCong(year: 2026, month: 9, days: 30);
      final congNo = PayrollCalculator.balance(
        attendances: cong,
        entries: [khoan(PayrollEntryType.truTien, 1000000)],
      );
      expect(congNo.totalEarned, luongDauMua - 1000000);
    });
  });

  group('Số ngày của tháng', () {
    test('lấy đúng cho tháng 28, 29, 30 và 31 ngày', () {
      expect(Attendance.daysInMonthOf(DateTime(2026, 2, 5)), 28);
      expect(Attendance.daysInMonthOf(DateTime(2028, 2, 5)), 29);
      expect(Attendance.daysInMonthOf(DateTime(2026, 9, 5)), 30);
      expect(Attendance.daysInMonthOf(DateTime(2026, 10, 5)), 31);
    });
  });

  group('Giai đoạn lương', () {
    final dauMua = WagePhase.create(
      crewId: crew,
      name: 'Đầu mùa',
      fromDate: DateTime(2026, 9, 1),
      toDate: DateTime(2026, 10, 15),
    );
    final muaRo = WagePhase.create(
      crewId: crew,
      name: 'Mùa rộ',
      fromDate: DateTime(2026, 10, 16),
    );

    test('nhận đúng ngày thuộc giai đoạn nào', () {
      expect(dauMua.contains(DateTime(2026, 9, 1)), isTrue);
      expect(dauMua.contains(DateTime(2026, 10, 15)), isTrue);
      expect(dauMua.contains(DateTime(2026, 10, 16)), isFalse);
      expect(muaRo.contains(DateTime(2026, 10, 16)), isTrue);
      expect(muaRo.contains(DateTime(2027, 1, 1)), isTrue,
          reason: 'giai đoạn chưa chốt ngày kết thúc thì còn kéo dài');
    });

    test('giờ chuẩn tính từ giờ vào, giờ về và giờ nghỉ', () {
      expect(
        WagePhase.standardHoursOf(workStart: '07:00', workEnd: '17:00', breakHours: 1.5),
        8.5,
      );
      expect(
        WagePhase.standardHoursOf(workStart: '07:00', workEnd: '22:00', breakHours: 3),
        12,
      );
      expect(WagePhase.parseClock('17:30'), 17.5);
      expect(WagePhase.parseClock('25:00'), isNull);
      expect(WagePhase.parseClock('7h'), isNull);
    });

    test('giờ trong ngày không làm lệch kết quả', () {
      expect(dauMua.contains(DateTime(2026, 10, 15, 23, 59)), isTrue);
      expect(dauMua.contains(DateTime(2026, 8, 31, 23, 59)), isFalse);
    });
  });

  group('Định dạng tiền trong cảnh báo', () {
    test('chấm phân cách hàng nghìn', () {
      expect(PayrollCalculator.money(1650000), '1.650.000 đ');
      expect(PayrollCalculator.money(0), '0 đ');
      expect(PayrollCalculator.money(999), '999 đ');
      expect(PayrollCalculator.money(-30140000), '-30.140.000 đ');
    });
  });
}
