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
    this.carriedOverAdvance = 0,
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

  /// Dư ứng từ các tháng **trước** mang qua, đã trừ phần tháng trước đó lỡ
  /// dùng rồi — xem [PayrollCalculator.carriedOverAdvance]. Mặc định 0 khi
  /// tính một tháng đơn lẻ không quan tâm tới quá khứ.
  final double carriedOverAdvance;

  /// Thu nhập của tháng — cơ sở tính trần ứng.
  double get income => wageEarned + overtime + allowance - deduction;

  /// Trần ứng riêng của tháng này: một nửa thu nhập **đã làm được tới thời
  /// điểm này**. Chưa cộng [carriedOverAdvance] — xem [remainingAdvance].
  double get advanceCap => PayrollCalculator.roundMoney(income / 2);

  /// Còn được ứng bao nhiêu, đã gồm cả [carriedOverAdvance]. Không bao giờ âm.
  double get remainingAdvance {
    final left = carriedOverAdvance + advanceCap - advanced;
    return left <= 0 ? 0 : PayrollCalculator.roundMoney(left);
  }

  /// Đã ứng vượt quá cả trần riêng của tháng lẫn dư mang qua.
  bool get overCap => advanced > carriedOverAdvance + advanceCap;
}

/// Kết quả kiểm tra một lần ứng lương.
class AdvanceCheck {
  const AdvanceCheck({
    required this.requested,
    required this.allowed,
    required this.cap,
    required this.advancedBefore,
    required this.income,
    this.carriedOver = 0,
  });

  /// Số tiền muốn ứng.
  final double requested;

  /// Còn được ứng bao nhiêu trước khi vượt trần — đã gồm cả phần dư mang từ
  /// các tháng trước qua ([carriedOver]).
  final double allowed;

  final double cap;
  final double advancedBefore;
  final double income;

  /// Phần chưa ứng hết của các tháng trước, được cộng vào trần tháng này.
  ///
  /// Mỗi tháng trước tính riêng và chặn ở 0 trước khi cộng — tháng nào ứng
  /// *vượt* trần (có lý do) chỉ đóng góp 0, không kéo trần các tháng sau
  /// xuống âm. Chỉ có **dư** mới mang qua được, nợ thì không.
  final double carriedOver;

  bool get exceedsCap => requested > allowed;

  /// Phần vượt quá trần.
  double get excess =>
      exceedsCap ? PayrollCalculator.roundMoney(requested - allowed) : 0;

  /// Câu cảnh báo hiển thị cho người duyệt.
  String? get warning {
    if (!exceedsCap) return null;
    if (allowed <= 0) {
      return 'Người này đã ứng hết mức cho phép, kể cả phần dư các tháng '
          'trước (tổng ${PayrollCalculator.money(cap + carriedOver)}). '
          'Ứng thêm là vượt luật.';
    }
    return 'Vượt trần ${PayrollCalculator.money(excess)}. '
        'Tổng còn được ứng (trần tháng này ${PayrollCalculator.money(cap)}'
        '${carriedOver > 0 ? ' + dư tháng trước ${PayrollCalculator.money(carriedOver)}' : ''}) '
        'chỉ còn ${PayrollCalculator.money(allowed)}.';
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
  ///
  /// [carriedOverAdvance] là dư mang vào tháng này từ các tháng trước — xem
  /// [PayrollCalculator.carriedOverAdvance]. Bên gọi phải tự tính rồi đưa vào
  /// đây; hàm này không tự lùi lại xem các tháng trước, vì [attendances] và
  /// [entries] đưa vào chưa chắc đã đủ dữ liệu của mọi tháng trước đó.
  static MonthlyPayroll monthly({
    required String monthKey,
    required Iterable<Attendance> attendances,
    required Iterable<PayrollEntry> entries,
    double carriedOverAdvance = 0,
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
      carriedOverAdvance: carriedOverAdvance,
    );
  }

  /// Tính một **dãy** tháng theo đúng thứ tự thời gian, mỗi tháng tự mang
  /// theo dư ứng từ các tháng trước ([MonthlyPayroll.carriedOverAdvance]).
  ///
  /// Gọi hàm này một lần cho cả người rồi dùng thẳng kết quả ở mọi nơi cần
  /// hiển thị — tính [carriedOverAdvance] riêng ở từng nơi gọi là đúng kiểu đã
  /// gây ra lỗi (dư tháng trước không được dùng để đỡ tháng này ở màn hình,
  /// trong khi màn hình khác lại tính đúng): hai nơi chép một công thức thì
  /// chỉ sớm hay muộn sẽ lệch nhau.
  static List<MonthlyPayroll> monthlySeries({
    required Iterable<Attendance> attendances,
    required Iterable<PayrollEntry> entries,
  }) {
    final thangs = <String>{
      ...attendances.where((a) => !a.deleted).map((a) => a.monthKey),
      ...entries.where((e) => !e.deleted).map((e) => e.monthKey),
    }.toList()
      ..sort();

    var du = 0.0;
    final result = <MonthlyPayroll>[];
    for (final key in thangs) {
      final m = monthly(
        monthKey: key,
        attendances: attendances,
        entries: entries,
        carriedOverAdvance: du,
      );
      result.add(m);
      du = m.remainingAdvance;
    }
    return result;
  }

  /// Kiểm tra một lần ứng lương so với trần của tháng.
  ///
  /// [month] phải đã được tính kèm [MonthlyPayroll.carriedOverAdvance] nếu
  /// muốn tính luôn phần dư các tháng trước — gọi [monthly] với tham số đó,
  /// hoặc dùng [monthlySeries], trước khi đưa vào đây.
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
        carriedOver: month.carriedOverAdvance,
      );

  /// Dư ứng luỹ kế của các tháng **trước** [beforeMonthKey], mang qua tháng này.
  ///
  /// Đi từng tháng theo đúng thứ tự thời gian, cộng trần rồi trừ đã ứng, chặn
  /// về 0 ở **cuối mỗi tháng** trước khi sang tháng kế — không phải tính riêng
  /// từng tháng rồi cộng lại. Nhờ vậy tháng nào ứng vượt trần riêng của nó bằng
  /// cách mượn dư các tháng trước thì đúng phần dư ấy bị trừ đi (không còn hiện
  /// lại ở lần tính sau), còn tháng nào ứng vượt hẳn (không đủ dư để mượn) thì
  /// chặn về 0 chứ không kéo âm sang tháng kế — nợ dừng ở đó, không dồn tiếp.
  static double carriedOverAdvance({
    required String beforeMonthKey,
    required Iterable<Attendance> attendances,
    required Iterable<PayrollEntry> entries,
  }) {
    final series = monthlySeries(attendances: attendances, entries: entries);
    final thangTruoc = series.where((m) => m.monthKey.compareTo(beforeMonthKey) < 0);
    return thangTruoc.isEmpty ? 0 : thangTruoc.last.remainingAdvance;
  }

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
