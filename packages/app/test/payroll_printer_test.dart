import 'package:canxe_app/core/payroll_printer.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

MonthReportRow _monthRow(String name, {String? kho, double wage = 8000000}) =>
    MonthReportRow(
      workerId: 'w-$name',
      name: name,
      stationCode: kho,
      month: MonthlyPayroll(
        monthKey: '2026-09',
        daysWorked: 30,
        workUnits: 30,
        wageEarned: wage,
        overtime: 500000,
        allowance: 200000,
        deduction: 100000,
        advanced: 2000000,
      ),
      byStation: {if (kho != null) kho: wage},
      remaining: wage + 600000 - 2000000,
    );

MonthReport _monthReport({int people = 3}) => MonthReport(
      crewName: 'Đoàn hái cà — Đắk Lắk',
      monthKey: '2026-09',
      year: 2026,
      month: 9,
      rows: [
        for (var i = 0; i < people; i++)
          _monthRow('Nguyễn Văn Tình $i', kho: i.isEven ? 'KHO01' : 'KHO02'),
      ],
      byStation: const {'KHO01': 16000000, 'KHO02': 8000000},
      totalWorkUnits: 90,
      totalWage: 24000000,
      totalOvertime: 1500000,
      totalAllowance: 600000,
      totalDeduction: 300000,
      totalIncome: 25800000,
      totalAdvanced: 6000000,
      totalRemaining: 19800000,
    );

SeasonReportRow _seasonRow(String name, {double earned = 8000000, double paid = 0}) =>
    SeasonReportRow(
      workerId: 'w-$name',
      name: name,
      stationCode: 'KHO01',
      months: 2,
      workUnits: 40.5,
      wageEarned: earned,
      overtime: 300000,
      allowance: 100000,
      deduction: 50000,
      balance: WorkerBalance(
        totalEarned: earned,
        totalAdvanced: 2000000,
        totalPaid: paid,
      ),
      settled: paid > 0,
    );

SeasonReport _seasonReport({int negative = 0}) => SeasonReport(
      crewName: 'Đoàn hái cà — Đắk Lắk',
      crewStatus: CrewStatus.daHoanThanh,
      season: '2025-2026',
      months: const ['2026-09', '2026-10'],
      rows: [
        _seasonRow('Trần Thị Hường'),
        _seasonRow('Lê Quốc Vũ', paid: 6000000),
        // Người đã nhận vượt: thu nhập thấp hơn số đã ứng.
        if (negative > 0) _seasonRow('Đỗ Đình Đạt', earned: 1000000),
      ],
      byStation: const {'KHO01': 12000000, 'KHO02': 5000000},
      totalWorkUnits: 81,
      totalEarned: 17000000,
      totalAdvanced: 6000000,
      totalPaid: 6000000,
      totalBalance: 5000000,
      negativeCount: negative,
      unpaidCount: 1,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('vi_VN');
  });

  group('PayrollPrinter — bảng lương tháng', () {
    test('dựng được file PDF hợp lệ', () async {
      final bytes = await PayrollPrinter.buildMonth(_monthReport());

      expect(bytes.length, greaterThan(1000));
      // Bốn byte đầu của mọi file PDF là "%PDF".
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nhúng được font có dấu tiếng Việt', () async {
      // Font mặc định của thư viện PDF không có dấu; không nhúng Roboto thì
      // bảng lương in ra mất dấu hết mà không báo lỗi gì.
      final bytes = await PayrollPrinter.buildMonth(_monthReport());
      final content = String.fromCharCodes(bytes);

      // Font nhúng phải xuất hiện trong file; thiếu nó là bảng in ra mất dấu.
      expect(content.contains('Roboto'), isTrue);
      expect(content.contains('FontFile2'), isTrue);
    });

    test('bảng nhiều người vẫn dựng được, tự sang trang', () async {
      final bytes = await PayrollPrinter.buildMonth(_monthReport(people: 80));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('bảng rỗng không làm vỡ bố cục', () async {
      final bytes = await PayrollPrinter.buildMonth(_monthReport(people: 0));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nhận tên đơn vị in trên đầu bảng', () async {
      final bytes = await PayrollPrinter.buildMonth(
        _monthReport(),
        companyName: 'Công ty Cà phê Sang NQ',
      );
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('PayrollPrinter — quyết toán mùa', () {
    test('dựng được file PDF hợp lệ', () async {
      final bytes = await PayrollPrinter.buildSeason(_seasonReport());
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
    });

    test('có người nhận vượt thì vẫn dựng được kèm phần lưu ý', () async {
      final bytes = await PayrollPrinter.buildSeason(_seasonReport(negative: 1));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('đoàn chưa có tháng nào cũng không lỗi', () async {
      const trong = SeasonReport(crewName: 'Đoàn mới');
      final bytes = await PayrollPrinter.buildSeason(trong);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
