import '../json_utils.dart';
import '../models/payroll/crew.dart';
import '../models/payroll/payroll_entry.dart';
import '../models/payroll/wage.dart';
import '../models/payroll/worker.dart';
import '../payroll/payroll_calculator.dart';
import 'api_client.dart';

/// Bảng lương của một đoàn, dựng sẵn cho màn hình cấu hình.
class WageTable {
  const WageTable({
    this.phases = const [],
    this.bands = const [],
    this.rates = const [],
    this.missing = const [],
  });

  factory WageTable.fromJson(Map<String, Object?> json) => WageTable(
        phases: asMapList(json['phases']).map(WagePhase.fromJson).toList(),
        bands: asMapList(json['bands']).map(WageBand.fromJson).toList(),
        rates: asMapList(json['rates']).map(WageRate.fromJson).toList(),
        missing: asMapList(json['missing'])
            .map((e) => MissingRate(
                  bandId: asString(e['band_id']),
                  bandName: asString(e['band_name']),
                  phaseId: asString(e['phase_id']),
                  phaseName: asString(e['phase_name']),
                ))
            .toList(),
      );

  final List<WagePhase> phases;
  final List<WageBand> bands;
  final List<WageRate> rates;

  /// Những ô chưa khai giá — phải chỉ ra được, chứ để trống thì tới lúc chấm
  /// công mới phát hiện là không tra ra lương.
  final List<MissingRate> missing;

  /// Giá của một ô trong bảng, `null` nếu chưa khai.
  double? amountFor(String bandId, String phaseId) {
    for (final rate in rates) {
      if (rate.bandId == bandId && rate.phaseId == phaseId) return rate.monthlyAmount;
    }
    return null;
  }

  bool get isComplete => missing.isEmpty && phases.isNotEmpty && bands.isNotEmpty;
}

/// Một ô trống trong bảng lương.
class MissingRate {
  const MissingRate({
    required this.bandId,
    required this.bandName,
    required this.phaseId,
    required this.phaseName,
  });

  final String bandId;
  final String bandName;
  final String phaseId;
  final String phaseName;
}

/// Bảng chấm công của một ngày.
class DaySheet {
  const DaySheet({
    required this.date,
    required this.daysInMonth,
    this.standardHours,
    this.phase,
    this.rows = const [],
    this.missingRate = const [],
    this.skipped = const [],
  });

  factory DaySheet.fromJson(Map<String, Object?> json) => DaySheet(
        date: asTime(json['date']),
        daysInMonth: asInt(json['days_in_month'], fallback: 30),
        standardHours: asDoubleOrNull(json['standard_hours']),
        phase: json['phase'] == null
            ? null
            : WagePhase.fromJson((json['phase']! as Map).cast<String, Object?>()),
        rows: asMapList(json['rows']).map(DayRow.fromJson).toList(),
        missingRate: asMapList(json['missing_rate'])
            .map((e) => SkippedWorker(
                  workerId: asString(e['worker_id']),
                  name: asString(e['name']),
                  reason: asString(e['reason'], fallback: 'chưa tra ra lương'),
                ))
            .toList(),
        skipped: asMapList(json['skipped'])
            .map((e) => SkippedWorker(
                  workerId: asString(e['worker_id']),
                  name: asString(e['name']),
                  reason: asString(e['reason']),
                ))
            .toList(),
      );

  final DateTime date;
  final int daysInMonth;

  /// Giờ chuẩn của ngày theo giai đoạn, `null` nếu ngày chưa thuộc giai đoạn.
  final double? standardHours;

  /// Giai đoạn lương của ngày này. `null` nghĩa là chưa khai — chấm công ngày
  /// đó sẽ bị chặn vì không tra ra lương.
  final WagePhase? phase;

  final List<DayRow> rows;

  /// Người chưa tra ra lương nên chấm công sẽ bỏ qua.
  final List<SkippedWorker> missingRate;

  /// Người vừa bị bỏ qua ở lần lưu gần nhất.
  final List<SkippedWorker> skipped;

  int get presentCount => rows.where((r) => r.present == true).length;
  int get markedCount => rows.where((r) => r.present != null).length;
  bool get isEmpty => rows.isEmpty;
}

/// Một người trong bảng chấm công ngày.
class DayRow {
  const DayRow({
    required this.workerId,
    required this.name,
    this.stationCode,
    this.attendanceId,
    this.present,
    this.monthlyAmount,
    required this.daysInMonth,
    this.hoursOff = 0,
    this.standardHours,
    this.note,
  });

  factory DayRow.fromJson(Map<String, Object?> json) => DayRow(
        workerId: asString(json['worker_id']),
        name: asString(json['name']),
        stationCode: asStringOrNull(json['station_code']),
        attendanceId: asStringOrNull(json['attendance_id']),
        present: json['present'] == null ? null : asBool(json['present']),
        monthlyAmount: asDoubleOrNull(json['monthly_amount']),
        daysInMonth: asInt(json['days_in_month'], fallback: 30),
        hoursOff: asDouble(json['hours_off']),
        standardHours: asDoubleOrNull(json['standard_hours']),
        note: asStringOrNull(json['note']),
      );

  DayRow copyWith({bool? present, double? hoursOff}) {
    final nowPresent = present ?? this.present;
    return DayRow(
      workerId: workerId,
      name: name,
      stationCode: stationCode,
      attendanceId: attendanceId,
      present: nowPresent,
      monthlyAmount: monthlyAmount,
      daysInMonth: daysInMonth,
      // Nghỉ cả ngày thì số giờ nghỉ không còn nghĩa — giống phía máy chủ.
      hoursOff: nowPresent == true ? (hoursOff ?? this.hoursOff) : 0,
      standardHours: standardHours,
      note: note,
    );
  }

  final String workerId;
  final String name;
  final String? stationCode;
  final String? attendanceId;

  /// `null` nghĩa là **chưa chấm** — khác với đã chấm là nghỉ.
  final bool? present;

  final double? monthlyAmount;
  final int daysInMonth;

  /// Số giờ nghỉ trong ngày, chỉ có nghĩa khi [present] là `true`.
  final double hoursOff;

  /// Giờ chuẩn của ngày — đã chốt lúc chấm, hoặc theo giai đoạn nếu chưa chấm.
  final double? standardHours;

  final String? note;

  /// Tiền một ngày công, `null` nếu chưa tra ra lương tháng.
  double? get dailyAmount => monthlyAmount == null || daysInMonth <= 0
      ? null
      : monthlyAmount! / daysInMonth;

  /// Số giờ làm thực, `null` nếu chưa chấm hoặc chưa biết giờ chuẩn.
  double? get hoursWorked {
    final chuan = standardHours;
    if (present != true || chuan == null) return null;
    final left = chuan - hoursOff;
    return left < 0 ? 0 : left;
  }

  /// Phần công của ngày: 1 đủ ngày, 0 nghỉ, ở giữa là nghỉ vài giờ.
  double? get workUnit {
    if (present == null) return null;
    if (present == false) return 0;
    final chuan = standardHours;
    final lam = hoursWorked;
    if (chuan == null || chuan <= 0 || lam == null) return 1;
    return lam / chuan;
  }
}

/// Người bị bỏ qua khi chấm công, kèm lý do.
class SkippedWorker {
  const SkippedWorker({
    required this.workerId,
    required this.name,
    required this.reason,
  });

  final String workerId;
  final String name;
  final String reason;
}

/// Bảng chấm công cả tháng.
class MonthSheet {
  const MonthSheet({
    required this.year,
    required this.month,
    required this.daysInMonth,
    this.rows = const [],
    this.totalDaysWorked = 0,
    this.totalWorkUnits = 0,
    this.totalWage = 0,
  });

  factory MonthSheet.fromJson(Map<String, Object?> json) => MonthSheet(
        year: asInt(json['year'], fallback: DateTime.now().year),
        month: asInt(json['month'], fallback: DateTime.now().month),
        daysInMonth: asInt(json['days_in_month'], fallback: 30),
        rows: asMapList(json['rows']).map(MonthRow.fromJson).toList(),
        totalDaysWorked: asInt(json['total_days_worked']),
        totalWorkUnits: asDouble(json['total_work_units']),
        totalWage: asDouble(json['total_wage']),
      );

  final int year;
  final int month;
  final int daysInMonth;
  final List<MonthRow> rows;
  final int totalDaysWorked;

  /// Tổng công thực, tính cả ngày nghỉ vài giờ.
  final double totalWorkUnits;
  final double totalWage;
}

/// Một người trong bảng tháng.
class MonthRow {
  const MonthRow({
    required this.workerId,
    required this.name,
    this.stationCode,
    this.bandName,
    this.presentDays = const {},
    this.absentDays = const {},
    this.partialDays = const {},
    this.daysWorked = 0,
    this.workUnits = 0,
    this.wageEarned = 0,
  });

  factory MonthRow.fromJson(Map<String, Object?> json) => MonthRow(
        workerId: asString(json['worker_id']),
        name: asString(json['name']),
        stationCode: asStringOrNull(json['station_code']),
        bandName: asStringOrNull(json['band_name']),
        presentDays: _days(json['present_days']),
        absentDays: _days(json['absent_days']),
        partialDays: _partial(json['partial_days']),
        daysWorked: asInt(json['days_worked']),
        workUnits: asDouble(json['work_units']),
        wageEarned: asDouble(json['wage_earned']),
      );

  static Set<int> _days(Object? raw) =>
      raw is List ? raw.map((e) => asInt(e)).toSet() : const {};

  static Map<int, double> _partial(Object? raw) => raw is Map
      ? {for (final e in raw.entries) asInt(e.key): asDouble(e.value)}
      : const {};

  final String workerId;
  final String name;
  final String? stationCode;
  final String? bandName;

  /// Ngày trong tháng có đi làm.
  final Set<int> presentDays;

  /// Ngày đã chấm là nghỉ — khác với ngày chưa chấm.
  final Set<int> absentDays;

  /// Ngày đi làm nhưng nghỉ vài giờ: `{ngày: số giờ làm thực}`.
  final Map<int, double> partialDays;

  final int daysWorked;

  /// Số công thực, ví dụ 28,5.
  final double workUnits;
  final double wageEarned;

  /// Trạng thái một ngày: `true` đi làm, `false` nghỉ, `null` chưa chấm.
  bool? stateOf(int day) {
    if (presentDays.contains(day)) return true;
    if (absentDays.contains(day)) return false;
    return null;
  }
}

/// Kết quả bấm nút tính lại lương của một tháng.
class RecalcResult {
  const RecalcResult({this.count = 0, this.changed = const []});

  factory RecalcResult.fromJson(Map<String, Object?> json) => RecalcResult(
        count: asInt(json['count']),
        changed: asMapList(json['changed'])
            .map((e) => RecalcChange(
                  workerId: asString(e['worker_id']),
                  name: asString(e['name']),
                  date: asTime(e['date']),
                  from: asDouble(e['from']),
                  to: asDouble(e['to']),
                ))
            .toList(),
      );

  final int count;
  final List<RecalcChange> changed;
}

/// Một ngày bị đổi mức lương khi tính lại.
class RecalcChange {
  const RecalcChange({
    required this.workerId,
    required this.name,
    required this.date,
    required this.from,
    required this.to,
  });

  final String workerId;
  final String name;
  final DateTime date;
  final double from;
  final double to;
}

/// Sổ tiền của một người: từng tháng, công nợ cả mùa và danh sách khoản.
class MoneySheet {
  const MoneySheet({
    this.worker,
    this.months = const [],
    this.balance = const WorkerBalance(totalEarned: 0, totalAdvanced: 0, totalPaid: 0),
    this.entries = const [],
  });

  factory MoneySheet.fromJson(Map<String, Object?> json) => MoneySheet(
        worker: json['worker'] == null
            ? null
            : Worker.fromJson((json['worker']! as Map).cast<String, Object?>()),
        months: asMapList(json['months']).map(monthlyPayrollFromJson).toList(),
        balance: workerBalanceFromJson(json['balance']),
        entries: asMapList(json['entries']).map(PayrollEntry.fromJson).toList(),
      );

  final Worker? worker;

  /// Các tháng có chấm công hoặc có khoản tiền, cũ trước mới sau.
  final List<MonthlyPayroll> months;

  final WorkerBalance balance;

  /// Mọi khoản tiền của người này, mới nhất trước.
  final List<PayrollEntry> entries;

  /// Tháng gần nhất, dùng khi cần một mốc để ứng lương.
  MonthlyPayroll? get latestMonth => months.isEmpty ? null : months.last;

  List<PayrollEntry> entriesOfMonth(String monthKey) =>
      entries.where((e) => e.monthKey == monthKey).toList();
}

/// Bảng tiền của cả đoàn.
class CrewMoney {
  const CrewMoney({
    this.monthKey = '',
    this.rows = const [],
    this.totalEarned = 0,
    this.totalAdvanced = 0,
    this.totalPaid = 0,
    this.totalBalance = 0,
    this.negativeCount = 0,
  });

  factory CrewMoney.fromJson(Map<String, Object?> json) => CrewMoney(
        monthKey: asString(json['month_key']),
        rows: asMapList(json['rows']).map(MoneyRow.fromJson).toList(),
        totalEarned: asDouble(json['total_earned']),
        totalAdvanced: asDouble(json['total_advanced']),
        totalPaid: asDouble(json['total_paid']),
        totalBalance: asDouble(json['total_balance']),
        negativeCount: asInt(json['negative_count']),
      );

  final String monthKey;
  final List<MoneyRow> rows;
  final double totalEarned;
  final double totalAdvanced;
  final double totalPaid;
  final double totalBalance;

  /// Số người đã nhận vượt công đã làm — phải hiện ra, không được im lặng.
  final int negativeCount;
}

/// Một người trong bảng tiền của đoàn.
class MoneyRow {
  const MoneyRow({
    required this.workerId,
    required this.name,
    this.stationCode,
    required this.balance,
    required this.thisMonth,
  });

  factory MoneyRow.fromJson(Map<String, Object?> json) => MoneyRow(
        workerId: asString(json['worker_id']),
        name: asString(json['name']),
        stationCode: asStringOrNull(json['station_code']),
        balance: workerBalanceFromJson(json['balance']),
        thisMonth: monthlyPayrollFromJson(
            (json['this_month'] as Map?)?.cast<String, Object?>() ?? const {}),
      );

  final String workerId;
  final String name;
  final String? stationCode;
  final WorkerBalance balance;
  final MonthlyPayroll thisMonth;
}

/// Kết quả thử một lần ứng trước khi ghi.
class AdvancePreview {
  const AdvancePreview({
    this.requested = 0,
    this.allowed = 0,
    this.cap = 0,
    this.advancedBefore = 0,
    this.income = 0,
    this.exceedsCap = false,
    this.excess = 0,
    this.warning,
    this.suggested = 0,
  });

  factory AdvancePreview.fromJson(Map<String, Object?> json) => AdvancePreview(
        requested: asDouble(json['requested']),
        allowed: asDouble(json['allowed']),
        cap: asDouble(json['cap']),
        advancedBefore: asDouble(json['advanced_before']),
        income: asDouble(json['income']),
        exceedsCap: asBool(json['exceeds_cap']),
        excess: asDouble(json['excess']),
        warning: asStringOrNull(json['warning']),
        suggested: asDouble(json['suggested']),
      );

  final double requested;

  /// Còn được ứng bao nhiêu trước khi vượt trần.
  final double allowed;

  final double cap;
  final double advancedBefore;
  final double income;
  final bool exceedsCap;
  final double excess;

  /// Câu cảnh báo dựng sẵn ở máy chủ, `null` nếu không vượt trần.
  final String? warning;

  /// Số tròn bội số 10.000 nên ứng, cho khớp việc đưa tiền mặt.
  final double suggested;
}

/// Bảng lương một tháng của cả đoàn.
class MonthReport {
  const MonthReport({
    this.crewName = '',
    this.monthKey = '',
    this.year = 0,
    this.month = 0,
    this.rows = const [],
    this.byStation = const {},
    this.totalWorkUnits = 0,
    this.totalWage = 0,
    this.totalOvertime = 0,
    this.totalAllowance = 0,
    this.totalDeduction = 0,
    this.totalIncome = 0,
    this.totalAdvanced = 0,
    this.totalRemaining = 0,
  });

  factory MonthReport.fromJson(Map<String, Object?> json) => MonthReport(
        crewName: asString(json['crew_name']),
        monthKey: asString(json['month_key']),
        year: asInt(json['year']),
        month: asInt(json['month']),
        rows: asMapList(json['rows']).map(MonthReportRow.fromJson).toList(),
        byStation: _money(json['by_station']),
        totalWorkUnits: asDouble(json['total_work_units']),
        totalWage: asDouble(json['total_wage']),
        totalOvertime: asDouble(json['total_overtime']),
        totalAllowance: asDouble(json['total_allowance']),
        totalDeduction: asDouble(json['total_deduction']),
        totalIncome: asDouble(json['total_income']),
        totalAdvanced: asDouble(json['total_advanced']),
        totalRemaining: asDouble(json['total_remaining']),
      );

  final String crewName;
  final String monthKey;
  final int year;
  final int month;
  final List<MonthReportRow> rows;

  /// Tiền công mà từng kho phải gánh trong tháng.
  final Map<String, double> byStation;

  final double totalWorkUnits;
  final double totalWage;
  final double totalOvertime;
  final double totalAllowance;
  final double totalDeduction;
  final double totalIncome;
  final double totalAdvanced;
  final double totalRemaining;
}

/// Một người trong bảng lương tháng.
class MonthReportRow {
  const MonthReportRow({
    required this.workerId,
    required this.name,
    this.stationCode,
    required this.month,
    this.byStation = const {},
    this.remaining = 0,
  });

  factory MonthReportRow.fromJson(Map<String, Object?> json) => MonthReportRow(
        workerId: asString(json['worker_id']),
        name: asString(json['name']),
        stationCode: asStringOrNull(json['station_code']),
        month: monthlyPayrollFromJson(json),
        byStation: _money(json['by_station']),
        remaining: asDouble(json['remaining']),
      );

  final String workerId;
  final String name;
  final String? stationCode;

  /// Số liệu của tháng, dùng lại đúng lớp trong công thức lương.
  final MonthlyPayroll month;

  final Map<String, double> byStation;

  /// Còn lại của riêng tháng này (thu nhập − đã ứng), chưa tính nợ dồn.
  final double remaining;
}

/// Báo cáo cả mùa, gộp mọi tháng.
class SeasonReport {
  const SeasonReport({
    this.crewName = '',
    this.crewStatus = CrewStatus.dangDienRa,
    this.season = '',
    this.months = const [],
    this.rows = const [],
    this.byStation = const {},
    this.totalWorkUnits = 0,
    this.totalEarned = 0,
    this.totalAdvanced = 0,
    this.totalPaid = 0,
    this.totalBalance = 0,
    this.negativeCount = 0,
    this.unpaidCount = 0,
  });

  factory SeasonReport.fromJson(Map<String, Object?> json) => SeasonReport(
        crewName: asString(json['crew_name']),
        crewStatus: CrewStatus.parse(json['crew_status']),
        season: asString(json['season']),
        months: (json['months'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        rows: asMapList(json['rows']).map(SeasonReportRow.fromJson).toList(),
        byStation: _money(json['by_station']),
        totalWorkUnits: asDouble(json['total_work_units']),
        totalEarned: asDouble(json['total_earned']),
        totalAdvanced: asDouble(json['total_advanced']),
        totalPaid: asDouble(json['total_paid']),
        totalBalance: asDouble(json['total_balance']),
        negativeCount: asInt(json['negative_count']),
        unpaidCount: asInt(json['unpaid_count']),
      );

  final String crewName;
  final CrewStatus crewStatus;
  final String season;

  /// Các tháng có số liệu, dạng `2026-09`.
  final List<String> months;

  final List<SeasonReportRow> rows;
  final Map<String, double> byStation;
  final double totalWorkUnits;
  final double totalEarned;
  final double totalAdvanced;
  final double totalPaid;
  final double totalBalance;

  /// Số người đã nhận vượt công đã làm.
  final int negativeCount;

  /// Số người còn chưa nhận hết — mùa xong hay chưa nhìn con số này.
  final int unpaidCount;

  bool get isClosed => crewStatus == CrewStatus.daHoanThanh;
}

/// Một người trong báo cáo mùa.
class SeasonReportRow {
  const SeasonReportRow({
    required this.workerId,
    required this.name,
    this.stationCode,
    this.months = 0,
    this.workUnits = 0,
    this.wageEarned = 0,
    this.overtime = 0,
    this.allowance = 0,
    this.deduction = 0,
    required this.balance,
    this.settled = false,
  });

  factory SeasonReportRow.fromJson(Map<String, Object?> json) => SeasonReportRow(
        workerId: asString(json['worker_id']),
        name: asString(json['name']),
        stationCode: asStringOrNull(json['station_code']),
        months: asInt(json['months']),
        workUnits: asDouble(json['work_units']),
        wageEarned: asDouble(json['wage_earned']),
        overtime: asDouble(json['overtime']),
        allowance: asDouble(json['allowance']),
        deduction: asDouble(json['deduction']),
        balance: workerBalanceFromJson(json['balance']),
        settled: asBool(json['settled']),
      );

  final String workerId;
  final String name;
  final String? stationCode;

  /// Số tháng có số liệu.
  final int months;

  final double workUnits;
  final double wageEarned;
  final double overtime;
  final double allowance;
  final double deduction;
  final WorkerBalance balance;

  /// Đã có khoản thanh toán quyết toán.
  final bool settled;
}

/// Kết quả một lần quyết toán.
class SettleResult {
  const SettleResult({
    this.paid = const [],
    this.skipped = const [],
    this.paidCount = 0,
    this.totalPaid = 0,
    required this.report,
  });

  factory SettleResult.fromJson(Map<String, Object?> json) => SettleResult(
        paid: asMapList(json['paid'])
            .map((e) => SettleLine(
                  workerId: asString(e['worker_id']),
                  name: asString(e['name']),
                  amount: asDouble(e['amount']),
                ))
            .toList(),
        skipped: asMapList(json['skipped'])
            .map((e) => SettleLine(
                  workerId: asString(e['worker_id']),
                  name: asString(e['name']),
                  amount: asDouble(e['balance']),
                  reason: asStringOrNull(e['reason']),
                ))
            .toList(),
        paidCount: asInt(json['paid_count']),
        totalPaid: asDouble(json['total_paid']),
        report: SeasonReport.fromJson(
            (json['report'] as Map?)?.cast<String, Object?>() ?? const {}),
      );

  final List<SettleLine> paid;

  /// Người bị bỏ qua kèm lý do: đã nhận đủ, hoặc đã nhận vượt phải thu lại.
  final List<SettleLine> skipped;

  final int paidCount;
  final double totalPaid;
  final SeasonReport report;
}

/// Một dòng trong kết quả quyết toán.
class SettleLine {
  const SettleLine({
    required this.workerId,
    required this.name,
    required this.amount,
    this.reason,
  });

  final String workerId;
  final String name;
  final double amount;
  final String? reason;
}

Map<String, double> _money(Object? raw) => raw is Map
    ? {for (final e in raw.entries) e.key.toString(): asDouble(e.value)}
    : const {};

/// Đọc [MonthlyPayroll] từ JSON của máy chủ.
///
/// Dùng lại đúng lớp trong công thức lương thay vì tạo lớp riêng cho client:
/// trần ứng và thu nhập chỉ được tính ở một chỗ, hai chỗ là sớm muộn lệch nhau.
MonthlyPayroll monthlyPayrollFromJson(Map<String, Object?> json) => MonthlyPayroll(
      monthKey: asString(json['month_key']),
      daysWorked: asInt(json['days_worked']),
      workUnits: asDouble(json['work_units']),
      wageEarned: asDouble(json['wage_earned']),
      overtime: asDouble(json['overtime']),
      allowance: asDouble(json['allowance']),
      deduction: asDouble(json['deduction']),
      advanced: asDouble(json['advanced']),
    );

WorkerBalance workerBalanceFromJson(Object? raw) {
  final json = (raw as Map?)?.cast<String, Object?>() ?? const {};
  return WorkerBalance(
    totalEarned: asDouble(json['total_earned']),
    totalAdvanced: asDouble(json['total_advanced']),
    totalPaid: asDouble(json['total_paid']),
  );
}

/// Các lời gọi API của module chấm công.
extension PayrollApi on ApiClient {
  // ------------------------------------------------------------------- đoàn

  Future<List<Crew>> crews({bool includeClosed = true}) async =>
      (await getList('/api/doan', {if (!includeClosed) 'all': '0'}))
          .map(Crew.fromJson)
          .toList();

  Future<Crew> crew(String id) async =>
      Crew.fromJson(await getMap('/api/doan/$id'));

  Future<Crew> saveCrew({
    String? id,
    required String name,
    String season = '',
    DateTime? startDate,
    DateTime? endDate,
    String? note,
  }) async =>
      Crew.fromJson(await postMap(id == null ? '/api/doan' : '/api/doan/$id', {
        'name': name,
        'season': season,
        'start_date': timeToMillisOrNull(startDate),
        'end_date': timeToMillisOrNull(endDate),
        'note': note,
      }));

  Future<Crew> closeCrew(String id) async => Crew.fromJson(
      await postMap('/api/doan/$id', {'status': CrewStatus.daHoanThanh.value}));

  Future<void> deleteCrew(String id) => deletePath('/api/doan/$id');

  // ------------------------------------------------------------ bảng lương

  Future<WageTable> wageTable(String crewId) async =>
      WageTable.fromJson(await getMap('/api/doan/$crewId/bang-luong'));

  Future<WagePhase> savePhase({
    required String crewId,
    String? id,
    required String name,
    required DateTime fromDate,
    DateTime? toDate,
    int sortOrder = 0,
    String? workStart,
    String? workEnd,
    double? breakHours,
  }) async =>
      WagePhase.fromJson(await postMap('/api/doan/$crewId/giai-doan', {
        if (id != null) 'id': id,
        'name': name,
        'from_date': timeToMillis(fromDate),
        'to_date': timeToMillisOrNull(toDate),
        'sort_order': sortOrder,
        if (workStart != null) 'work_start': workStart,
        if (workEnd != null) 'work_end': workEnd,
        if (breakHours != null) 'break_hours': breakHours,
      }));

  Future<void> deletePhase(String crewId, String phaseId) =>
      deletePath('/api/doan/$crewId/giai-doan/$phaseId');

  Future<WageBand> saveBand({
    required String crewId,
    String? id,
    required String name,
    int sortOrder = 0,
  }) async =>
      WageBand.fromJson(await postMap('/api/doan/$crewId/muc-luong', {
        if (id != null) 'id': id,
        'name': name,
        'sort_order': sortOrder,
      }));

  Future<void> deleteBand(String crewId, String bandId) =>
      deletePath('/api/doan/$crewId/muc-luong/$bandId');

  Future<WageRate> saveRate({
    required String crewId,
    required String phaseId,
    String? bandId,
    String? workerId,
    required double monthlyAmount,
  }) async =>
      WageRate.fromJson(await postMap('/api/doan/$crewId/gia-luong', {
        'phase_id': phaseId,
        if (bandId != null) 'band_id': bandId,
        if (workerId != null) 'worker_id': workerId,
        'monthly_amount': monthlyAmount,
      }));

  // -------------------------------------------------------------- nhân viên

  Future<List<Worker>> workers(String crewId,
          {WorkerStatus? status, String? query, String? stationCode}) async =>
      (await getList('/api/doan/$crewId/nhan-vien', {
        if (status != null) 'status': status.value,
        if (query != null && query.isNotEmpty) 'q': query,
        if (stationCode != null && stationCode.isNotEmpty) 'kho': stationCode,
      }))
          .map(Worker.fromJson)
          .toList();

  Future<Worker> saveWorker({
    required String crewId,
    String? id,
    required String name,
    String? phone,
    String? stationCode,
    String? bandId,
    DateTime? joinDate,
    String? note,
  }) async =>
      Worker.fromJson(await postMap('/api/doan/$crewId/nhan-vien', {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'station_code': stationCode,
        'band_id': bandId,
        'join_date': timeToMillisOrNull(joinDate),
        'note': note,
      }));

  /// Chuyển người sang kho khác, có hiệu lực từ bây giờ.
  ///
  /// Những ngày đã chấm công vẫn giữ kho ghi lúc đó, nên chuyển qua chuyển lại
  /// bao nhiêu lần cũng không làm sai số liệu tháng trước.
  Future<List<Worker>> transferWorkers({
    required String crewId,
    required List<String> workerIds,
    required String stationCode,
  }) async =>
      (await postList('/api/doan/$crewId/chuyen-kho', {
        'worker_ids': workerIds,
        'station_code': stationCode,
      }))
          .map(Worker.fromJson)
          .toList();

  Future<Worker> stopWorker(String workerId, {DateTime? leaveDate}) async =>
      Worker.fromJson(await postMap('/api/nhan-vien/$workerId/nghi-lam', {
        'leave_date': timeToMillisOrNull(leaveDate),
      }));

  Future<Worker> resumeWorker(String workerId) async =>
      Worker.fromJson(await postMap('/api/nhan-vien/$workerId/lam-lai', const {}));

  // ------------------------------------------------------------- chấm công

  Future<DaySheet> daySheet(String crewId, DateTime date) async =>
      DaySheet.fromJson(await getMap('/api/doan/$crewId/cham-cong', {
        'date': timeToMillis(date).toString(),
      }));

  /// Chấm công cho một ngày.
  ///
  /// [marks] là `{id nhân viên: có đi làm}` — gửi cả người nghỉ chứ không chỉ
  /// người đi làm, để phân biệt với ngày chưa chấm.
  Future<DaySheet> markDay({
    required String crewId,
    required DateTime date,
    required Map<String, bool> marks,
    Map<String, double> hoursOff = const {},
    String? note,
  }) async =>
      DaySheet.fromJson(await postMap('/api/doan/$crewId/cham-cong', {
        'date': timeToMillis(date),
        'marks': marks,
        if (hoursOff.isNotEmpty) 'hours_off': hoursOff,
        'note': note,
      }));

  Future<MonthSheet> monthSheet(String crewId, {required int year, required int month}) async =>
      MonthSheet.fromJson(await getMap('/api/doan/$crewId/cham-cong/thang', {
        'year': '$year',
        'month': '$month',
      }));

  /// Tính lại mức lương đã chốt của một tháng theo bảng giá hiện tại.
  Future<RecalcResult> recalcMonth(String crewId,
          {required int year, required int month}) async =>
      RecalcResult.fromJson(await postMap('/api/doan/$crewId/cham-cong/tinh-lai', {
        'year': year,
        'month': month,
      }));

  // ---------------------------------------------------------------- sổ tiền

  Future<CrewMoney> crewMoney(String crewId,
          {required int year, required int month}) async =>
      CrewMoney.fromJson(await getMap('/api/doan/$crewId/tien', {
        'year': '$year',
        'month': '$month',
      }));

  Future<MoneySheet> moneySheet(String crewId, String workerId) async =>
      MoneySheet.fromJson(
          await getMap('/api/doan/$crewId/nhan-vien/$workerId/tien'));

  /// Thử một lần ứng trước khi ghi, để cảnh báo ngay lúc đang nhập.
  ///
  /// Truyền [entryId] khi đang sửa một khoản, không thì tiền cũ bị đếm hai lần.
  Future<AdvancePreview> previewAdvance({
    required String crewId,
    required String workerId,
    required double amount,
    DateTime? date,
    String? entryId,
  }) async =>
      AdvancePreview.fromJson(await postMap('/api/doan/$crewId/so-tien/kiem-tra', {
        'worker_id': workerId,
        'amount': amount,
        'date': timeToMillisOrNull(date),
        if (entryId != null) 'id': entryId,
      }));

  /// Ghi một khoản tiền và nhận lại sổ tiền đã cập nhật của người đó.
  ///
  /// Ứng vượt trần thì bắt buộc có [overCapReason], không thì máy chủ từ chối
  /// kèm câu cảnh báo nói rõ còn được ứng bao nhiêu.
  Future<MoneySheet> saveEntry({
    required String crewId,
    required String workerId,
    required PayrollEntryType type,
    required double amount,
    String? id,
    DateTime? date,
    String? note,
    String? overCapReason,
  }) async =>
      MoneySheet.fromJson(await postMap('/api/doan/$crewId/so-tien', {
        if (id != null) 'id': id,
        'worker_id': workerId,
        'type': type.value,
        'amount': amount,
        'date': timeToMillisOrNull(date),
        'note': note,
        if (overCapReason != null) 'over_cap_reason': overCapReason,
      }));

  Future<MoneySheet> deleteEntry(String crewId, String entryId) async =>
      MoneySheet.fromJson(
          await deleteMap('/api/doan/$crewId/so-tien/$entryId'));

  // ---------------------------------------------- báo cáo và quyết toán mùa

  Future<MonthReport> monthReport(String crewId,
          {required int year, required int month}) async =>
      MonthReport.fromJson(await getMap('/api/doan/$crewId/bao-cao/thang', {
        'year': '$year',
        'month': '$month',
      }));

  Future<SeasonReport> seasonReport(String crewId) async =>
      SeasonReport.fromJson(await getMap('/api/doan/$crewId/bao-cao/mua'));

  /// Chốt mùa: đóng đoàn để mở cửa cho quyết toán. Không tự trả tiền.
  Future<SeasonReport> closeSeason(String crewId, {DateTime? endDate}) async =>
      SeasonReport.fromJson(await postMap('/api/doan/$crewId/chot-mua', {
        'end_date': timeToMillisOrNull(endDate),
      }));

  Future<SeasonReport> reopenSeason(String crewId) async =>
      SeasonReport.fromJson(await postMap('/api/doan/$crewId/mo-lai-mua', const {}));

  /// Quyết toán: trả hết phần còn lại. Bỏ trống [workerIds] là cho cả đoàn.
  Future<SettleResult> settleSeason(
    String crewId, {
    List<String>? workerIds,
    DateTime? date,
  }) async =>
      SettleResult.fromJson(await postMap('/api/doan/$crewId/quyet-toan', {
        if (workerIds != null) 'worker_ids': workerIds,
        'date': timeToMillisOrNull(date),
      }));
}
