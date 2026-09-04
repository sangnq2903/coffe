import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';

/// Nhóm người đang xem trong bảng chấm công ngày.
enum _DayFilter {
  tatCa('Tất cả'),
  chuaCham('Chưa chấm'),
  daCham('Đã chấm');

  const _DayFilter(this.label);

  final String label;
}

/// Chấm công theo ngày.
///
/// Mỗi ngày chỉ trả lời một câu: hôm đó ai đi làm. Ba trạng thái — đi làm, nghỉ,
/// và **chưa chấm** — phải phân biệt được, vì "chưa chấm" là việc còn dở còn
/// "nghỉ" là đã chốt.
///
/// Đoàn đông thì cuộn tìm từng người rất lâu, nên có ô tìm tên (gõ không dấu
/// vẫn ra) và ba nhóm lọc. Nhóm "Chưa chấm" là danh sách việc còn phải làm:
/// chấm xong ai thì người đó rời khỏi nhóm, hết danh sách là xong ngày.
class AttendanceDayTab extends StatefulWidget {
  const AttendanceDayTab({super.key, required this.crewId});

  final String crewId;

  @override
  State<AttendanceDayTab> createState() => _AttendanceDayTabState();
}

class _AttendanceDayTabState extends State<AttendanceDayTab> {
  final _search = TextEditingController();

  DateTime _day = DateTime.now();
  _DayFilter _filter = _DayFilter.tatCa;
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Người khớp ô tìm tên, chưa lọc theo nhóm.
  ///
  /// Tách riêng để số trên ba nhóm đếm đúng phạm vi đang xem: tìm "tinh" thì
  /// "Chưa chấm (1)" nói về mình Tình, chứ không phải cả đoàn.
  List<DayRow> _matchingSearch(DaySheet sheet) {
    final q = normalizeForSearch(_search.text);
    if (q.isEmpty) return sheet.rows;
    return sheet.rows.where((r) => normalizeForSearch(r.name).contains(q)).toList();
  }

  List<DayRow> _visible(DaySheet sheet) => switch (_filter) {
        _DayFilter.tatCa => _matchingSearch(sheet),
        _DayFilter.chuaCham =>
          _matchingSearch(sheet).where((r) => r.present == null).toList(),
        _DayFilter.daCham =>
          _matchingSearch(sheet).where((r) => r.present != null).toList(),
      };

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
  Future<void> _mark(Map<String, bool> marks,
      {Map<String, double> hoursOff = const {}}) async {
    final client = _client;
    final sheet = _sheet;
    if (client == null || sheet == null) return;

    final ticket = ++_lastSent;
    setState(() {
      _sheet = _applyLocally(sheet, marks, hoursOff);
      _inFlight++;
      _error = null;
    });

    try {
      final fresh = await client.markDay(
        crewId: widget.crewId,
        date: _day,
        marks: marks,
        hoursOff: hoursOff,
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
  static DaySheet _applyLocally(
    DaySheet sheet,
    Map<String, bool> marks,
    Map<String, double> hoursOff,
  ) =>
      DaySheet(
        date: sheet.date,
        daysInMonth: sheet.daysInMonth,
        standardHours: sheet.standardHours,
        phase: sheet.phase,
        missingRate: sheet.missingRate,
        rows: [
          for (final row in sheet.rows)
            if (!marks.containsKey(row.workerId))
              row
            else
              row.copyWith(
                present: marks[row.workerId],
                hoursOff: hoursOff[row.workerId],
              ),
        ],
      );

  /// Ghi số giờ nghỉ trong ngày cho một người đang đi làm.
  Future<void> _editHours(DayRow row) async {
    final chuan = row.standardHours;
    if (chuan == null) return;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => _HoursOffDialog(row: row, standardHours: chuan),
    );
    if (result == null || !mounted) return;
    await _mark({row.workerId: true}, hoursOff: {row.workerId: result});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    final visible = sheet == null ? const <DayRow>[] : _visible(sheet);
    return Column(
      children: [
        _dayBar(),
        if (sheet != null && sheet.rows.isNotEmpty) _searchBar(sheet),
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
                      trailing: visible.isEmpty || sheet.phase == null
                          ? null
                          : _bulkButtons(sheet, visible),
                      child: sheet.rows.isEmpty
                          ? const EmptyHint(
                              icon: Icons.person_off_outlined,
                              message: 'Ngày này không có ai trong đoàn.\n'
                                  'Kiểm lại ngày vào làm của nhân viên.',
                            )
                          : visible.isEmpty
                              ? EmptyHint(
                                  icon: Icons.search_off,
                                  message: _emptyMessage(),
                                )
                              : Column(
                                  children: [
                                    for (var i = 0; i < visible.length; i++) ...[
                                      if (i > 0) const Divider(height: 1),
                                      _row(visible[i], sheet.phase != null),
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

  /// Ô tìm tên và ba nhóm lọc.
  Widget _searchBar(DaySheet sheet) {
    final khop = _matchingSearch(sheet);
    final chua = khop.where((r) => r.present == null).length;
    final da = khop.length - chua;
    final dem = {
      _DayFilter.tatCa: khop.length,
      _DayFilter.chuaCham: chua,
      _DayFilter.daCham: da,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Tìm tên để chấm riêng',
              helperText: 'Gõ không dấu cũng ra — "tinh" tìm được "Tình"',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xoá tìm kiếm',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppTheme.gapSm),
          SingleChildScrollView(
            // Ba nhóm kèm số đếm dễ rộng hơn màn hình điện thoại.
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_DayFilter>(
              segments: [
                for (final f in _DayFilter.values)
                  ButtonSegment(value: f, label: Text('${f.label} (${dem[f]})')),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (chon) => setState(() => _filter = chon.first),
            ),
          ),
        ],
      ),
    );
  }

  String _emptyMessage() {
    if (_search.text.trim().isNotEmpty) {
      return 'Không có ai tên khớp "${_search.text.trim()}"\n'
          'trong nhóm "${_filter.label}".';
    }
    return switch (_filter) {
      _DayFilter.chuaCham => 'Đã chấm hết cả đoàn cho ngày này.',
      _DayFilter.daCham => 'Chưa chấm cho ai trong ngày này.',
      _DayFilter.tatCa => 'Không có ai để chấm.',
    };
  }

  /// Thanh chọn ngày.
  ///
  /// Hai mũi tên nằm sát ngày chứ không dạt ra hai mép màn hình: đổi ngày là
  /// việc làm liên tục, để xa nhau thì mỗi lần bấm phải rê chuột cả gang tay.
  Widget _dayBar() {
    final laHomNay = _sameDay(_day, DateTime.now());
    final phase = _sheet?.phase;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StepButton(
            tooltip: 'Ngày trước',
            icon: Icons.chevron_left,
            onTap: () => _goto(_day.subtract(const Duration(days: 1))),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: InkWell(
              onTap: _pickDay,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Container(
                constraints: const BoxConstraints(minWidth: 210),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.lineStrong),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_weekday(_day)}, ${formatDate(_day)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      phase == null
                          ? 'chưa khai giai đoạn lương'
                          : 'Giai đoạn: ${phase.name}',
                      style: TextStyle(
                        fontSize: 12,
                        color: phase == null ? AppTheme.offline : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _StepButton(
            tooltip: 'Ngày sau',
            icon: Icons.chevron_right,
            onTap: () => _goto(_day.add(const Duration(days: 1))),
          ),
          if (!laHomNay) ...[
            const SizedBox(width: AppTheme.gapSm),
            OutlinedButton(
              onPressed: () => _goto(DateTime.now()),
              child: const Text('Hôm nay'),
            ),
          ],
        ],
      ),
    );
  }

  /// Hai nút chấm hàng loạt, chỉ tác động lên **những người đang hiện**.
  ///
  /// Lọc "Chưa chấm" rồi bấm "Đi làm" là chấm đúng số người còn lại, không đụng
  /// tới ai đã chấm — nên nhãn phải nói rõ số người, kẻo tưởng là cả đoàn.
  Widget _bulkButtons(DaySheet sheet, List<DayRow> visible) {
    final locHep = visible.length != sheet.rows.length;
    final hau = locHep ? ' ${visible.length} người' : ' hết';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => _mark({for (final r in visible) r.workerId: true}),
          child: Text('Đi làm$hau'),
        ),
        TextButton(
          onPressed: () => _mark({for (final r in visible) r.workerId: false}),
          child: Text('Nghỉ$hau'),
        ),
      ],
    );
  }

  /// Một người trong bảng ngày.
  ///
  /// Hai nút "Đi làm" / "Nghỉ" dính liền thành một cặp, cao [AppTheme.minTouch]
  /// và có chữ hẳn hoi. Trước đây là ba ô vuông 36px không nhãn nằm sát mép
  /// phải màn hình — bấm nhầm liên tục, và phải rê chuột từ tên người sang tận
  /// bên kia màn hình.
  Widget _row(DayRow row, bool canMark) {
    final tienNgay = row.dailyAmount;
    final thieuGio = row.present == true && row.hoursOff > 0;
    final nghi = row.present == false;

    return Container(
      // Người nghỉ được tô nền nhạt: lướt mắt xuống là thấy ngay hôm nay vắng
      // những ai, không phải đọc từng dòng.
      color: nghi ? AppTheme.offline.withValues(alpha: 0.035) : null,
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.name, style: AppTheme.body),
                const SizedBox(height: 2),
                Text(
                  [
                    if (row.stationCode != null) row.stationCode!,
                    if (tienNgay != null)
                      '${formatMoney(tienNgay)} đ/ngày'
                    else
                      'chưa tra ra lương',
                  ].join('  ·  '),
                  style: AppTheme.meta,
                ),
                if (thieuGio) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Nghỉ ${formatDecimal(row.hoursOff)} giờ → làm '
                    '${formatDecimal(row.hoursWorked)}/${formatDecimal(row.standardHours)} giờ'
                    '  ·  ${formatDecimal(row.workUnit)} công',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.gapSm),
          if (canMark && row.present == true) ...[
            _HoursButton(
              active: thieuGio,
              hoursOff: row.hoursOff,
              onTap: () => _editHours(row),
            ),
            const SizedBox(width: 6),
          ],
          _StateToggle(
            present: row.present,
            enabled: canMark,
            onChanged: (v) => _mark({row.workerId: v}),
          ),
        ],
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
        child: NoticeBar(icon: icon, color: color, text: text),
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
              const Spacer(),
              _StepButton(
                tooltip: 'Tháng trước',
                icon: Icons.chevron_left,
                onTap: () => _shift(-1),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 150),
                alignment: Alignment.center,
                child: Text(
                  'Tháng ${_month.month}/${_month.year}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              _StepButton(
                tooltip: 'Tháng sau',
                icon: Icons.chevron_right,
                onTap: () => _shift(1),
              ),
              const Spacer(),
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
            title: 'Tổng ${formatDecimal(sheet.totalWorkUnits)} công'
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
                        DataCell(_dayCell(row.stateOf(d), row.partialDays[d])),
                      DataCell(Text(formatDecimal(row.workUnits),
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
            'Ô trống là chưa chấm, khác với dấu ✕ là đã chấm nghỉ. Ô ghi số là ngày '
            'đi làm nhưng nghỉ vài giờ (số giờ làm thực). '
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

  /// Ngày đi làm nhưng nghỉ vài giờ hiện số giờ làm thực thay cho dấu ✓ —
  /// nhìn vào bảng là thấy ngay ngày nào thiếu.
  Widget _dayCell(bool? state, double? hoursWorked) {
    if (state == true && hoursWorked != null) {
      return Text(
        formatDecimal(hoursWorked),
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.accent),
      );
    }
    return switch (state) {
      true => const Icon(Icons.check, size: 16, color: AppTheme.stable),
      false => const Icon(Icons.close, size: 16, color: AppTheme.offline),
      _ => const Text('·', style: TextStyle(color: AppTheme.line)),
    };
  }

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

/// Nút mũi tên lùi/tới một bước, cỡ chạm được bằng ngón cái.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            width: AppTheme.minTouch,
            height: AppTheme.minTouch,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.lineStrong),
            ),
            child: Icon(icon, size: 22, color: AppTheme.textSoft),
          ),
        ),
      );
}

/// Cặp nút "Đi làm" / "Nghỉ" dính liền nhau.
///
/// Có nhãn chữ chứ không chỉ dấu ✓ ✕: người mới dùng không phải đoán, và ô bấm
/// rộng hơn hẳn nên chấm cả đoàn không bị trượt tay. Màn hình hẹp thì bỏ chữ,
/// giữ nguyên bề cao chạm được.
class _StateToggle extends StatelessWidget {
  const _StateToggle({
    required this.present,
    required this.enabled,
    required this.onChanged,
  });

  /// `null` là chưa chấm — khi đó không nút nào sáng.
  final bool? present;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, _) {
          final rong = MediaQuery.sizeOf(context).width >= 560;
          return Container(
            height: AppTheme.minTouch,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: AppTheme.lineStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _half(
                  value: true,
                  icon: Icons.check,
                  label: 'Đi làm',
                  color: AppTheme.stable,
                  showLabel: rong,
                ),
                const VerticalDivider(width: 1),
                _half(
                  value: false,
                  icon: Icons.close,
                  label: 'Nghỉ',
                  color: AppTheme.offline,
                  showLabel: rong,
                ),
              ],
            ),
          );
        },
      );

  Widget _half({
    required bool value,
    required IconData icon,
    required String label,
    required Color color,
    required bool showLabel,
  }) {
    final chosen = present == value;
    return InkWell(
      onTap: enabled ? () => onChanged(value) : null,
      child: Container(
        constraints: BoxConstraints(minWidth: showLabel ? 84 : 46),
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 0),
        color: chosen ? color.withValues(alpha: 0.14) : AppTheme.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: chosen ? color : AppTheme.textMuted),
            if (showLabel) ...[
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: chosen ? FontWeight.w700 : FontWeight.w600,
                  color: chosen ? color : AppTheme.textSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nút ghi giờ nghỉ. Hiện luôn số giờ đã ghi để khỏi phải mở ra xem.
class _HoursButton extends StatelessWidget {
  const _HoursButton({
    required this.active,
    required this.hoursOff,
    required this.onTap,
  });

  final bool active;
  final double hoursOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: active ? 'Sửa giờ nghỉ' : 'Nghỉ vài giờ trong ngày',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            height: AppTheme.minTouch,
            constraints: const BoxConstraints(minWidth: AppTheme.minTouch),
            padding: EdgeInsets.symmetric(horizontal: active ? 10 : 0),
            decoration: BoxDecoration(
              color: active ? AppTheme.accentSoft : AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: active ? AppTheme.accent.withValues(alpha: 0.5) : AppTheme.lineStrong,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.more_time,
                    size: 19, color: active ? AppTheme.accent : AppTheme.textMuted),
                if (active) ...[
                  const SizedBox(width: 4),
                  Text(
                    formatDecimal(hoursOff),
                    style: AppTheme.number(13, color: AppTheme.accent),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Nhập số giờ nghỉ trong ngày.
///
/// Chỉ hỏi một con số — người chấm công không ghi giờ đến giờ về, chỉ biết
/// "hôm nay nghỉ 2 tiếng". Nghỉ hết ca thì phải chấm là nghỉ cả ngày.
class _HoursOffDialog extends StatefulWidget {
  const _HoursOffDialog({required this.row, required this.standardHours});

  final DayRow row;
  final double standardHours;

  @override
  State<_HoursOffDialog> createState() => _HoursOffDialogState();
}

class _HoursOffDialogState extends State<_HoursOffDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _hours = TextEditingController(
      text: widget.row.hoursOff > 0 ? formatDecimal(widget.row.hoursOff) : '');

  double? get _value => parseNumber(_hours.text);

  @override
  Widget build(BuildContext context) {
    final gio = _value;
    final conLai = gio == null ? null : widget.standardHours - gio;
    return AlertDialog(
      title: Text('Giờ nghỉ của ${widget.row.name}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _hours,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Số giờ nghỉ trong ngày',
                helperText: 'Ca ${formatDecimal(widget.standardHours)} giờ chuẩn. '
                    'Nghỉ hết ca thì bấm ✕ chấm nghỉ cả ngày.',
                suffixText: 'giờ',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = parseNumber(v);
                if (n == null || n < 0) return 'Nhập số giờ, ví dụ 2 hoặc 1,5';
                if (n >= widget.standardHours) {
                  return 'Bằng hoặc vượt giờ chuẩn — chấm nghỉ cả ngày thay vì ghi giờ';
                }
                return null;
              },
            ),
            const SizedBox(height: AppTheme.gapSm),
            if (conLai != null && conLai > 0)
              Text(
                'Còn ${formatDecimal(conLai)}/${formatDecimal(widget.standardHours)} giờ '
                '→ công ${formatDecimal(conLai / widget.standardHours)}',
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.primary, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.row.hoursOff > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: const Text('Đủ ngày'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _value);
          },
          child: const Text('Ghi'),
        ),
      ],
    );
  }
}
