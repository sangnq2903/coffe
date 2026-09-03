import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';

/// Chấm công theo ngày.
///
/// Mỗi ngày chỉ trả lời một câu: hôm đó ai đi làm. Ba trạng thái — đi làm, nghỉ,
/// và **chưa chấm** — phải phân biệt được, vì "chưa chấm" là việc còn dở còn
/// "nghỉ" là đã chốt.
class AttendanceDayTab extends StatefulWidget {
  const AttendanceDayTab({super.key, required this.crewId});

  final String crewId;

  @override
  State<AttendanceDayTab> createState() => _AttendanceDayTabState();
}

class _AttendanceDayTabState extends State<AttendanceDayTab> {
  DateTime _day = DateTime.now();
  DaySheet? _sheet;
  bool _loading = false;
  int _inFlight = 0;
  String? _error;

  /// Số thứ tự lần ghi gần nhất.
  ///
  /// Chấm nhanh thì nhiều lần ghi chồng nhau, và phản hồi không chắc về theo
  /// thứ tự gửi. Chỉ nhận bảng của lần ghi mới nhất, chứ nhận bảng cũ về sau
  /// thì ô vừa bấm lại nhảy về trạng thái trước đó.
  int _lastSent = 0;

  ApiClient? get _client => context.read<ServerConnection>().client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = await client.daySheet(widget.crewId, _day);
      if (mounted) setState(() => _sheet = sheet);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goto(DateTime day) {
    setState(() => _day = day);
    _load();
  }

  /// Ghi ngay khi bấm, không chờ nút "Lưu".
  ///
  /// Chấm công là việc bấm liên tục cả chục người; để dồn lại rồi lưu thì chỉ
  /// cần đóng màn hình là mất hết mà không ai biết. Vì vậy cũng **không chặn**
  /// lượt bấm sau trong lúc đang gửi: ô đổi màu ngay tại chỗ, còn phản hồi của
  /// máy chủ về sau mới ghi đè lên.
  Future<void> _mark(Map<String, bool> marks) async {
    final client = _client;
    final sheet = _sheet;
    if (client == null || sheet == null) return;

    final ticket = ++_lastSent;
    setState(() {
      _sheet = _applyLocally(sheet, marks);
      _inFlight++;
      _error = null;
    });

    try {
      final fresh = await client.markDay(
        crewId: widget.crewId,
        date: _day,
        marks: marks,
      );
      if (!mounted) return;
      // Bảng của lần ghi cũ về muộn thì bỏ, không thì ô vừa bấm bị lùi lại.
      if (ticket == _lastSent) setState(() => _sheet = fresh);
      if (fresh.skipped.isNotEmpty) {
        _snack('Bỏ qua ${fresh.skipped.length} người: '
            '${fresh.skipped.map((e) => '${e.name} (${e.reason})').join('; ')}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      // Ghi thất bại thì màn hình đang hiện trạng thái không có thật.
      await _load();
    } finally {
      if (mounted) setState(() => _inFlight--);
    }
  }

  /// Đổi màu ô ngay tại chỗ, trước khi máy chủ trả lời.
  static DaySheet _applyLocally(DaySheet sheet, Map<String, bool> marks) => DaySheet(
        date: sheet.date,
        daysInMonth: sheet.daysInMonth,
        phase: sheet.phase,
        missingRate: sheet.missingRate,
        rows: [
          for (final row in sheet.rows)
            if (!marks.containsKey(row.workerId))
              row
            else
              DayRow(
                workerId: row.workerId,
                name: row.name,
                stationCode: row.stationCode,
                attendanceId: row.attendanceId,
                present: marks[row.workerId],
                monthlyAmount: row.monthlyAmount,
                daysInMonth: row.daysInMonth,
                note: row.note,
              ),
        ],
      );

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return Column(
      children: [
        _dayBar(),
        if (_loading || _inFlight > 0) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
            child: Text(_error!, style: const TextStyle(color: AppTheme.offline)),
          ),
        Expanded(
          child: sheet == null
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
                  children: [
                    if (sheet.phase == null) _noPhaseWarning(),
                    if (sheet.missingRate.isNotEmpty) _missingRateWarning(sheet),
                    SectionCard(
                      title: 'Đã chấm ${sheet.markedCount}/${sheet.rows.length}'
                          ' • Đi làm ${sheet.presentCount}',
                      icon: Icons.how_to_reg,
                      padded: false,
                      trailing: sheet.rows.isEmpty || sheet.phase == null
                          ? null
                          : _bulkButtons(sheet),
                      child: sheet.rows.isEmpty
                          ? const EmptyHint(
                              icon: Icons.person_off_outlined,
                              message: 'Ngày này không có ai trong đoàn.\n'
                                  'Kiểm lại ngày vào làm của nhân viên.',
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < sheet.rows.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  _row(sheet.rows[i], sheet.phase != null),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _dayBar() {
    final laHomNay = _sameDay(_day, DateTime.now());
    final phase = _sheet?.phase;
    return Padding(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Ngày trước',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goto(_day.subtract(const Duration(days: 1))),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(
                      '${_weekday(_day)}, ${formatDate(_day)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      phase == null ? 'chưa khai giai đoạn lương' : 'Giai đoạn: ${phase.name}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: phase == null ? AppTheme.offline : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ngày sau',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goto(_day.add(const Duration(days: 1))),
          ),
          if (!laHomNay)
            TextButton(
              onPressed: () => _goto(DateTime.now()),
              child: const Text('Hôm nay'),
            ),
        ],
      ),
    );
  }

  Widget _bulkButtons(DaySheet sheet) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => _mark({for (final r in sheet.rows) r.workerId: true}),
            child: const Text('Đi làm hết'),
          ),
          TextButton(
            onPressed: () => _mark({for (final r in sheet.rows) r.workerId: false}),
            child: const Text('Nghỉ hết'),
          ),
        ],
      );

  Widget _row(DayRow row, bool canMark) {
    final tienNgay = row.dailyAmount;
    return ListTile(
      title: Text(row.name),
      subtitle: Text([
        row.stationCode == null ? 'chưa gán kho' : 'Kho ${row.stationCode}',
        if (tienNgay != null) '${formatMoney(tienNgay)} đ/ngày' else 'chưa tra ra lương',
      ].join(' • ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _markButton(
            row: row,
            value: true,
            icon: Icons.check,
            color: AppTheme.stable,
            tooltip: 'Đi làm',
            enabled: canMark,
          ),
          const SizedBox(width: 4),
          _markButton(
            row: row,
            value: false,
            icon: Icons.close,
            color: AppTheme.offline,
            tooltip: 'Nghỉ',
            enabled: canMark,
          ),
        ],
      ),
    );
  }

  Widget _markButton({
    required DayRow row,
    required bool value,
    required IconData icon,
    required Color color,
    required String tooltip,
    required bool enabled,
  }) {
    final chosen = row.present == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? () => _mark({row.workerId: value}) : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: chosen ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: chosen ? color.withValues(alpha: 0.55) : AppTheme.line,
            ),
          ),
          child: Icon(icon, size: 20, color: chosen ? color : AppTheme.line),
        ),
      ),
    );
  }

  Widget _noPhaseWarning() => _banner(
        icon: Icons.event_busy,
        color: AppTheme.offline,
        text: 'Ngày này chưa thuộc giai đoạn lương nào nên không chấm công được. '
            'Sang tab "Cấu hình lương" khai giai đoạn phủ ngày này trước đã.',
      );

  Widget _missingRateWarning(DaySheet sheet) => _banner(
        icon: Icons.warning_amber_rounded,
        color: AppTheme.accent,
        text: 'Chưa tra ra lương cho ${sheet.missingRate.length} người '
            '(${sheet.missingRate.map((e) => e.name).join(', ')}). '
            'Chấm công sẽ bỏ qua họ — gán mức lương rồi chấm lại.',
      );

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      );

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null) _goto(picked);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekday(DateTime day) => switch (day.weekday) {
        DateTime.monday => 'Thứ hai',
        DateTime.tuesday => 'Thứ ba',
        DateTime.wednesday => 'Thứ tư',
        DateTime.thursday => 'Thứ năm',
        DateTime.friday => 'Thứ sáu',
        DateTime.saturday => 'Thứ bảy',
        _ => 'Chủ nhật',
      };
}

/// Bảng chấm công cả tháng: mỗi người một dòng, mỗi ngày một ô.
///
/// Đây là bảng để đối chiếu và trả lương, nên phải thấy được cả tháng một lượt
/// chứ không bấm qua từng ngày.
class AttendanceMonthTab extends StatefulWidget {
  const AttendanceMonthTab({super.key, required this.crewId});

  final String crewId;

  @override
  State<AttendanceMonthTab> createState() => _AttendanceMonthTabState();
}

class _AttendanceMonthTabState extends State<AttendanceMonthTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthSheet? _sheet;
  bool _loading = false;
  String? _error;

  ApiClient? get _client => context.read<ServerConnection>().client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = await client.monthSheet(
        widget.crewId,
        year: _month.year,
        month: _month.month,
      );
      if (mounted) setState(() => _sheet = sheet);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.gapMd),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(
                  'Tháng ${_month.month}/${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
              IconButton(
                tooltip: 'Tính lại lương của tháng này',
                icon: const Icon(Icons.calculate_outlined),
                onPressed: _recalc,
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
            child: Text(_error!, style: const TextStyle(color: AppTheme.offline)),
          ),
        Expanded(
          child: sheet == null
              ? const SizedBox.shrink()
              : sheet.rows.isEmpty
                  ? const EmptyHint(
                      icon: Icons.event_note_outlined,
                      message: 'Tháng này chưa có ai chấm công.',
                    )
                  : _grid(sheet),
        ),
      ],
    );
  }

  Widget _grid(MonthSheet sheet) => ListView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
        children: [
          SectionCard(
            title: 'Tổng ${sheet.totalDaysWorked} công'
                ' • ${formatMoney(sheet.totalWage)} đ',
            icon: Icons.table_chart,
            padded: false,
            child: SingleChildScrollView(
              // Bảng 31 cột chắc chắn rộng hơn màn hình, nên cho cuộn ngang
              // thay vì bóp chữ lại tới mức không đọc được.
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 8,
                horizontalMargin: 12,
                headingRowHeight: 38,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 46,
                columns: [
                  const DataColumn(label: Text('Người')),
                  for (var d = 1; d <= sheet.daysInMonth; d++)
                    DataColumn(
                      label: Text(
                        '$d',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _isSunday(d) ? AppTheme.accent : AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const DataColumn(label: Text('Công'), numeric: true),
                  const DataColumn(label: Text('Lương'), numeric: true),
                ],
                rows: [
                  for (final row in sheet.rows)
                    DataRow(cells: [
                      DataCell(_nameCell(row)),
                      for (var d = 1; d <= sheet.daysInMonth; d++)
                        DataCell(_dayCell(row.stateOf(d))),
                      DataCell(Text('${row.daysWorked}',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(formatMoney(row.wageEarned),
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.gapSm),
          const Text(
            'Ô trống là chưa chấm, khác với dấu ✕ là đã chấm nghỉ. '
            'Ngày công của tháng tính bằng số ngày của tháng, kể cả chủ nhật.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      );

  Widget _nameCell(MonthRow row) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 190),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(row.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              [
                if (row.stationCode != null) row.stationCode!,
                if (row.bandName != null) row.bandName!,
              ].join(' • '),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      );

  Widget _dayCell(bool? state) => switch (state) {
        true => const Icon(Icons.check, size: 16, color: AppTheme.stable),
        false => const Icon(Icons.close, size: 16, color: AppTheme.offline),
        _ => const Text('·', style: TextStyle(color: AppTheme.line)),
      };

  bool _isSunday(int day) =>
      DateTime(_month.year, _month.month, day).weekday == DateTime.sunday;

  /// Bấm nút mới tính lại quá khứ.
  ///
  /// Bình thường ngày đã chấm giữ nguyên mức lương lúc chấm, nên phải hỏi lại
  /// cho chắc — đổi số của tháng đã trả lương là chuyện lớn.
  Future<void> _recalc() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tính lại lương tháng ${_month.month}/${_month.year}?'),
        content: const Text(
          'Những ngày đã chấm sẽ lấy lại mức lương theo bảng giá hiện tại. '
          'Dùng khi khai sai giá rồi mới phát hiện. Nếu tháng này đã trả lương '
          'thì con số sẽ lệch với số đã trả.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: const Text('Tính lại')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final client = _client;
    if (client == null) return;
    try {
      final result = await client.recalcMonth(
        widget.crewId,
        year: _month.year,
        month: _month.month,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.count == 0
            ? 'Không có ngày nào phải đổi.'
            : 'Đã đổi mức lương của ${result.count} ngày.'),
      ));
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }
}
