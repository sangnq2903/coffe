import '../models/payroll/attendance.dart';
import '../models/payroll/payroll_entry.dart';

/// Kết quả tính lương của **một người trong một tháng**.
class MonthlyPayroll {
  const MonthlyPayroll({
    required this.monthKey,
    required this.daysWorked,
    this.workUnits = 0,
    required this.wageEarned,
    required this.overtime,
    required this.allowance,
    required this.deduction,
    required this.advanced,
  });

  final String monthKey;

  /// Số ngày đã chấm là có đi làm.
  final int daysWorked;

  /// Số công thực, tính cả ngày nghỉ vài giờ — ví dụ 28,5 công.
  final double workUnits;

  /// Lương theo ngày công đã làm, quy từ lương tháng.
  final double wageEarned;

  final double overtime;
  final double allowance;
  final double deduction;

  /// Đã ứng trong chính tháng này.
  final double advanced;

  /// Thu nhập của tháng — cơ sở tính trần ứng.
  double get income => wageEarned + overtime + allowance - deduction;

  /// Trần ứng: một nửa thu nhập **đã làm được tới thời điểm này**.
  double get advanceCap => PayrollCalculator.roundMoney(income / 2);

  /// Còn được ứng bao nhiêu. Không bao giờ âm.
  double get remainingAdvance {
    final left = advanceCap - advanced;
    return left <= 0 ? 0 : PayrollCalculator.roundMoney(left);
  }

  /// Đã ứng vượt quá nửa thu nhập của tháng.
  bool get overCap => advanced > advanceCap;
}

/// Kết quả kiểm tra một lần ứng lương.
class AdvanceCheck {
  const AdvanceCheck({
    required this.requested,
    required this.allowed,
    required this.cap,
    required this.advancedBefore,
    required this.income,
  });

  /// Số tiền muốn ứng.
  final double requested;

  /// Còn được ứng bao nhiêu trước khi vượt trần.
  final double allowed;

  final double cap;
  final double advancedBefore;
  final double income;

  bool get exceedsCap => requested > allowed;

  /// Phần vượt quá trần.
  double get excess =>
      exceedsCap ? PayrollCalculator.roundMoney(requested - allowed) : 0;

  /// Câu cảnh báo hiển thị cho người duyệt.
  String? get warning {
    if (!exceedsCap) return null;
    if (allowed <= 0) {
      return 'Người này đã ứng hết mức cho phép của tháng '
          '(${PayrollCalculator.money(cap)}). Ứng thêm là vượt luật.';
    }
    return 'Vượt trần ${PayrollCalculator.money(excess)}. '
        'Tháng này chỉ còn được ứng ${PayrollCalculator.money(allowed)} '
        'trên tổng trần ${PayrollCalculator.money(cap)}.';
  }
}

/// Công nợ luỹ kế của một người trong cả mùa.
class WorkerBalance {
  const WorkerBalance({
    required this.totalEarned,
    required this.totalAdvanced,
    required this.totalPaid,
  });

  /// Tổng thu nhập cả mùa: lương + tăng ca + phụ cấp − trừ tiền.
  final double totalEarned;

  final double totalAdvanced;
  final double totalPaid;

  double get totalReceived => totalAdvanced + totalPaid;

  /// Còn phải trả cho người này. Âm nghĩa là họ đã nhận vượt công đã làm.
  double get balance => PayrollCalculator.roundMoney(totalEarned - totalReceived);

  /// Đã nhận nhiều hơn công đã làm — phải cảnh báo, không được im lặng.
  bool get isNegative => balance < 0;
}

/// Toàn bộ công thức tính lương của module chấm công.
///
/// Cố tình viết thuần: không đụng cơ sở dữ liệu, không đụng mạng, chỉ nhận vào
/// danh sách bản ghi và trả ra con số. Đây là nơi tiền thật đi qua nên phải
/// kiểm thử được từng công thức, không phải chạy cả hệ thống lên mới biết đúng sai.
abstract final class PayrollCalculator {
  /// Tỷ lệ ứng tối đa trên thu nhập của tháng.
  static const double advanceRatio = 0.5;

  /// Làm tròn tiền ứng xuống bội số này cho khớp việc đưa tiền mặt.
  static const double advanceRoundingStep = 10000;

  /// Lương đã làm được trong một tháng.
  ///
  /// Gộp các ngày có **cùng mức lương tháng** rồi mới chia, thay vì cộng dồn
  /// tiền của từng ngày. Chia từng ngày rồi cộng lại sẽ lệch: 8.000.000 chia
  /// cho 30 ngày ra số lẻ vô hạn, đi làm đủ tháng lại không ra đúng 8.000.000.
  /// Người ta đếm tiền, lệch vài đồng cũng thành thắc mắc.
  ///
  /// Ngày nghỉ vài giờ đóng góp một phần công ([Attendance.workUnit]) chứ không
  /// phải trọn một ngày.
  static double wageEarnedInMonth(Iterable<Attendance> attendances) {
    final units = <String, double>{};
    final amounts = <String, double>{};
    final divisors = <String, int>{};

    for (final a in attendances) {
      if (a.deleted || !a.present) continue;
      final key = '${a.monthlyAmount}|${a.daysInMonth}';
      units[key] = (units[key] ?? 0) + a.workUnit;
      amounts[key] = a.monthlyAmount;
      divisors[key] = a.daysInMonth;
    }

    var total = 0.0;
    for (final key in units.keys) {
      final divisor = divisors[key]!;
      if (divisor <= 0) continue;
      total += amounts[key]! * units[key]! / divisor;
    }
    return roundMoney(total);
  }

  /// Tổng công của một tháng, tính cả ngày nghỉ vài giờ.
  static double workUnitsInMonth(Iterable<Attendance> attendances) =>
      attendances.where((a) => !a.deleted).fold(0.0, (sum, a) => sum + a.workUnit);

  /// Tính lương một tháng của một người.
  ///
  /// [attendances] và [entries] có thể chứa dữ liệu của nhiều tháng — hàm tự
  /// lọc theo [monthKey], để bên gọi không phải nhớ lọc trước.
  static MonthlyPayroll monthly({
    required String monthKey,
    required Iterable<Attendance> attendances,
    required Iterable<PayrollEntry> entries,
  }) {
    final ofMonth = attendances.where((a) => !a.deleted && a.monthKey == monthKey);
    final money = entries.where((e) => !e.deleted && e.monthKey == monthKey);

    double sum(PayrollEntryType type) => money
        .where((e) => e.type == type)
        .fold<double>(0, (total, e) => total + e.amount);

    return MonthlyPayroll(
      monthKey: monthKey,
      daysWorked: ofMonth.where((a) => a.present).length,
      workUnits: workUnitsInMonth(ofMonth),
      wageEarned: wageEarnedInMonth(ofMonth),
      overtime: sum(PayrollEntryType.tangCa),
      allowance: sum(PayrollEntryType.phuCap),
      deduction: sum(PayrollEntryType.truTien),
      advanced: sum(PayrollEntryType.ungLuong),
    );
  }

  /// Kiểm tra một lần ứng lương so với trần của tháng.
  ///
  /// Trần chỉ nhìn thu nhập **của chính tháng đó**. Nợ dồn từ tháng trước không
  /// làm trần cao lên — đây là quy tắc cốt lõi của cả module.
  static AdvanceCheck checkAdvance({
    required MonthlyPayroll month,
    required double requested,
  }) =>
      AdvanceCheck(
        requested: requested,
        allowed: month.remainingAdvance,
        cap: month.advanceCap,
        advancedBefore: month.advanced,
        income: month.income,
      );

  /// Công nợ luỹ kế cả mùa.
  static WorkerBalance balance({
    required Iterable<Attendance> attendances,
    required Iterable<PayrollEntry> entries,
  }) {
    final months = attendances
        .where((a) => !a.deleted && a.present)
        .map((a) => a.monthKey)
        .toSet();

    var wage = 0.0;
    for (final month in months) {
      wage += wageEarnedInMonth(attendances.where((a) => a.monthKey == month));
    }

    final live = entries.where((e) => !e.deleted);
    double sum(PayrollEntryType type) =>
        live.where((e) => e.type == type).fold<double>(0, (t, e) => t + e.amount);

    return WorkerBalance(
      totalEarned: roundMoney(wage +
          sum(PayrollEntryType.tangCa) +
          sum(PayrollEntryType.phuCap) -
          sum(PayrollEntryType.truTien)),
      totalAdvanced: sum(PayrollEntryType.ungLuong),
      totalPaid: sum(PayrollEntryType.thanhToan),
    );
  }

  /// Làm tròn số tiền ứng xuống bội số 10.000 đồng.
  static double roundAdvanceDown(double amount) {
    if (amount <= 0) return 0;
    return (amount / advanceRoundingStep).floor() * advanceRoundingStep;
  }

  /// Làm tròn về đồng chẵn.
  ///
  /// Phép chia lương tháng cho số ngày luôn ra số lẻ; để nguyên thì mỗi lần
  /// cộng dồn lại sai thêm một chút, tới cuối mùa thành lệch thấy được.
  static double roundMoney(double amount) => amount.roundToDouble();

  /// Định dạng tiền cho câu cảnh báo, ví dụ `1.650.000 đ`.
  static String money(double amount) {
    final text = amount.abs().round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }
    return '${amount < 0 ? '-' : ''}$buffer đ';
  }
}
