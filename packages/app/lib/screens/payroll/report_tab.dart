import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/payroll_printer.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';

/// Hai bảng báo cáo của một đoàn.
enum _ReportKind {
  thang('Bảng lương tháng'),
  mua('Quyết toán mùa');

  const _ReportKind(this.label);

  final String label;
}

/// Báo cáo và quyết toán cuối mùa.
///
/// Bảng lương là thứ đưa cho người ta xem rồi ký nhận, nên in được ra giấy —
/// xem trên màn hình thôi thì chưa dùng được.
class ReportTab extends StatefulWidget {
  const ReportTab({super.key, required this.crew, this.onCrewChanged});

  final Crew crew;

  /// Gọi khi chốt hoặc mở lại mùa, để màn hình ngoài cập nhật trạng thái đoàn.
  final VoidCallback? onCrewChanged;

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  _ReportKind _kind = _ReportKind.thang;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  MonthReport? _monthReport;
  SeasonReport? _seasonReport;
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
      if (_kind == _ReportKind.thang) {
        final report = await client.monthReport(
          widget.crew.id,
          year: _month.year,
          month: _month.month,
        );
        if (mounted) setState(() => _monthReport = report);
      } else {
        final report = await client.seasonReport(widget.crew.id);
        if (mounted) setState(() => _seasonReport = report);
      }
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapSm),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_ReportKind>(
                      segments: [
                        for (final k in _ReportKind.values)
                          ButtonSegment(value: k, label: Text(k.label)),
                      ],
                      selected: {_kind},
                      showSelectedIcon: false,
                      onSelectionChanged: (chon) {
                        setState(() => _kind = chon.first);
                        _load();
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Làm mới',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          if (_kind == _ReportKind.thang) _monthBar(),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
              child: Text(_error!, style: const TextStyle(color: AppTheme.offline)),
            ),
          Expanded(
            child: _kind == _ReportKind.thang ? _monthView() : _seasonView(),
          ),
        ],
      );

  Widget _monthBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Tháng sau',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(1),
            ),
          ],
        ),
      );

  // -------------------------------------------------------- bảng lương tháng

  Widget _monthView() {
    final report = _monthReport;
    if (report == null) return const SizedBox.shrink();
    if (report.rows.isEmpty) {
      return const EmptyHint(
        icon: Icons.description_outlined,
        message: 'Tháng này chưa có công và chưa có khoản tiền nào.',
      );
    }

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
      children: [
        SectionCard(
          title: '${report.rows.length} người'
              ' • ${formatDecimal(report.totalWorkUnits)} công'
              ' • ${formatMoney(report.totalIncome)} đ',
          icon: Icons.table_rows,
          padded: false,
          trailing: _printButtons(
            onPrint: () => PayrollPrinter.printMonth(report),
            onShare: () => PayrollPrinter.shareMonth(report),
          ),
          child: SingleChildScrollView(
            // Bảng lương nhiều cột chắc chắn rộng hơn màn hình.
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              horizontalMargin: 12,
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Họ tên')),
                DataColumn(label: Text('Công'), numeric: true),
                DataColumn(label: Text('Lương'), numeric: true),
                DataColumn(label: Text('Tăng ca'), numeric: true),
                DataColumn(label: Text('Phụ cấp'), numeric: true),
                DataColumn(label: Text('Trừ'), numeric: true),
                DataColumn(label: Text('Thu nhập'), numeric: true),
                DataColumn(label: Text('Đã ứng'), numeric: true),
                DataColumn(label: Text('Còn lại'), numeric: true),
              ],
              rows: [
                for (final row in report.rows)
                  DataRow(cells: [
                    DataCell(_nameCell(row.name, row.stationCode)),
                    DataCell(Text(formatDecimal(row.month.workUnits))),
                    DataCell(Text(formatMoney(row.month.wageEarned))),
                    DataCell(Text(formatMoney(row.month.overtime))),
                    DataCell(Text(formatMoney(row.month.allowance))),
                    DataCell(Text(formatMoney(row.month.deduction))),
                    DataCell(Text(formatMoney(row.month.income),
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(formatMoney(row.month.advanced))),
                    DataCell(Text(formatMoney(row.remaining),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                  ]),
                DataRow(
                  color: WidgetStatePropertyAll(
                      AppTheme.primary.withValues(alpha: 0.06)),
                  cells: [
                    const DataCell(
                        Text('TỔNG', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(_bold(formatDecimal(report.totalWorkUnits))),
                    DataCell(_bold(formatMoney(report.totalWage))),
                    DataCell(_bold(formatMoney(report.totalOvertime))),
                    DataCell(_bold(formatMoney(report.totalAllowance))),
                    DataCell(_bold(formatMoney(report.totalDeduction))),
                    DataCell(_bold(formatMoney(report.totalIncome))),
                    DataCell(_bold(formatMoney(report.totalAdvanced))),
                    DataCell(_bold(formatMoney(report.totalRemaining))),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (report.byStation.isNotEmpty) ...[
          const SizedBox(height: AppTheme.gapMd),
          _stationCard(report.byStation),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ quyết toán

  Widget _seasonView() {
    final report = _seasonReport;
    if (report == null) return const SizedBox.shrink();
    if (report.rows.isEmpty) {
      return const EmptyHint(
        icon: Icons.assignment_outlined,
        message: 'Đoàn này chưa có công và chưa có khoản tiền nào.',
      );
    }

    return ListView(
      padding:
          const EdgeInsets.fromLTRB(AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
      children: [
        _seasonStatus(report),
        const SizedBox(height: AppTheme.gapMd),
        SectionCard(
          title: '${report.rows.length} người'
              ' • còn phải trả ${formatMoney(report.totalBalance)} đ',
          icon: Icons.assignment_turned_in,
          padded: false,
          trailing: _printButtons(
            onPrint: () => PayrollPrinter.printSeason(report),
            onShare: () => PayrollPrinter.shareSeason(report),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 18,
              horizontalMargin: 12,
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('Họ tên')),
                DataColumn(label: Text('Công'), numeric: true),
                DataColumn(label: Text('Thu nhập'), numeric: true),
                DataColumn(label: Text('Đã ứng'), numeric: true),
                DataColumn(label: Text('Đã trả'), numeric: true),
                DataColumn(label: Text('Còn lại'), numeric: true),
                DataColumn(label: Text('Trạng thái')),
              ],
              rows: [
                for (final row in report.rows)
                  DataRow(cells: [
                    DataCell(_nameCell(row.name, row.stationCode)),
                    DataCell(Text(formatDecimal(row.workUnits))),
                    DataCell(Text(formatMoney(row.balance.totalEarned))),
                    DataCell(Text(formatMoney(row.balance.totalAdvanced))),
                    DataCell(Text(formatMoney(row.balance.totalPaid))),
                    DataCell(Text(
                      formatMoney(row.balance.balance),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: row.balance.isNegative ? AppTheme.offline : null,
                      ),
                    )),
                    DataCell(_statusPill(row)),
                  ]),
                DataRow(
                  color: WidgetStatePropertyAll(
                      AppTheme.primary.withValues(alpha: 0.06)),
                  cells: [
                    const DataCell(
                        Text('TỔNG', style: TextStyle(fontWeight: FontWeight.w700))),
                    DataCell(_bold(formatDecimal(report.totalWorkUnits))),
                    DataCell(_bold(formatMoney(report.totalEarned))),
                    DataCell(_bold(formatMoney(report.totalAdvanced))),
                    DataCell(_bold(formatMoney(report.totalPaid))),
                    DataCell(_bold(formatMoney(report.totalBalance))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (report.byStation.isNotEmpty) ...[
          const SizedBox(height: AppTheme.gapMd),
          _stationCard(report.byStation),
        ],
      ],
    );
  }

  Widget _statusPill(SeasonReportRow row) {
    if (row.balance.isNegative) {
      return const StatusPill(
          label: 'Nhận vượt', color: AppTheme.offline, compact: true);
    }
    if (row.settled) {
      return const StatusPill(
          label: 'Đã quyết toán', color: AppTheme.stable, compact: true);
    }
    if (row.balance.balance <= 0) {
      return const StatusPill(
          label: 'Đã nhận đủ', color: AppTheme.textMuted, compact: true);
    }
    return const StatusPill(label: 'Chưa trả', color: AppTheme.accent, compact: true);
  }

  Widget _seasonStatus(SeasonReport report) {
    final daDong = report.isClosed;
    return SectionCard(
      title: daDong ? 'Mùa đã chốt' : 'Mùa đang diễn ra',
      icon: daDong ? Icons.lock : Icons.lock_open,
      accentColor: daDong ? AppTheme.stable : AppTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            daDong
                ? 'Đoàn đã chốt mùa nên quyết toán được. Quyết toán ghi đúng số còn '
                    'phải trả của từng người, không nhận số tự nhập.'
                : 'Trong mùa chỉ ứng lương. Chốt mùa trước rồi mới quyết toán được — '
                    'chốt xong vẫn mở lại được nếu bấm nhầm.',
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          if (report.negativeCount > 0) ...[
            const SizedBox(height: AppTheme.gapSm),
            Text(
              '${report.negativeCount} người đã nhận nhiều hơn công đã làm — '
              'phần này phải thu lại, quyết toán sẽ bỏ qua họ.',
              style: const TextStyle(fontSize: 13, color: AppTheme.offline),
            ),
          ],
          const SizedBox(height: AppTheme.gapMd),
          Wrap(
            spacing: AppTheme.gapSm,
            runSpacing: AppTheme.gapSm,
            children: [
              if (!daDong)
                FilledButton.icon(
                  onPressed: _closeSeason,
                  icon: const Icon(Icons.lock, size: 18),
                  label: const Text('Chốt mùa'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: report.unpaidCount == 0 ? null : _settleAll,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text(report.unpaidCount == 0
                      ? 'Đã trả hết'
                      : 'Quyết toán ${report.unpaidCount} người'),
                ),
                OutlinedButton.icon(
                  onPressed: _reopenSeason,
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Mở lại mùa'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _closeSeason() async {
    final ok = await _confirm(
      title: 'Chốt mùa cho đoàn ${widget.crew.name}?',
      content: 'Chốt mùa chỉ đóng đoàn để mở cửa cho quyết toán, không tự trả tiền. '
          'Sau khi chốt thì không ứng lương được nữa. Bấm nhầm thì mở lại được.',
      action: 'Chốt mùa',
    );
    if (ok != true) return;
    await _run(() async {
      final report = await _client!.closeSeason(widget.crew.id);
      if (mounted) setState(() => _seasonReport = report);
      widget.onCrewChanged?.call();
      _snack('Đã chốt mùa. Còn ${report.unpaidCount} người chưa nhận hết.');
    });
  }

  Future<void> _reopenSeason() async {
    final ok = await _confirm(
      title: 'Mở lại mùa?',
      content: 'Mở lại để ứng lương và chấm công tiếp. Những khoản quyết toán đã '
          'ghi vẫn giữ nguyên — muốn bỏ thì xoá từng khoản trong sổ tiền.',
      action: 'Mở lại',
    );
    if (ok != true) return;
    await _run(() async {
      final report = await _client!.reopenSeason(widget.crew.id);
      if (mounted) setState(() => _seasonReport = report);
      widget.onCrewChanged?.call();
      _snack('Đã mở lại mùa.');
    });
  }

  Future<void> _settleAll() async {
    final report = _seasonReport;
    if (report == null) return;

    final ok = await _confirm(
      title: 'Quyết toán ${report.unpaidCount} người?',
      content: 'Ghi khoản thanh toán bằng đúng số còn phải trả của từng người, '
          'tổng ${formatMoney(report.totalBalance)} đ. '
          '${report.negativeCount > 0 ? '${report.negativeCount} người đã nhận vượt sẽ bị bỏ qua. ' : ''}'
          'Xoá được từng khoản trong sổ tiền nếu ghi sai.',
      action: 'Quyết toán',
    );
    if (ok != true) return;

    await _run(() async {
      final result = await _client!.settleSeason(widget.crew.id);
      if (mounted) setState(() => _seasonReport = result.report);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _SettleResultDialog(result: result),
      );
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
    required String action,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Huỷ')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------ phần chung

  Widget _printButtons({
    required Future<void> Function() onPrint,
    required Future<void> Function() onShare,
  }) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'In bảng',
            icon: const Icon(Icons.print),
            onPressed: () => _print(onPrint),
          ),
          IconButton(
            tooltip: 'Lưu / chia sẻ PDF',
            icon: const Icon(Icons.share),
            onPressed: () => _print(onShare),
          ),
        ],
      );

  Future<void> _print(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _snack('Không in được: $e');
    }
  }

  Widget _nameCell(String name, String? stationCode) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            if (stationCode != null)
              Text(stationCode,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      );

  Widget _bold(String text) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w700));

  /// Tiền công mà từng kho phải gánh.
  ///
  /// Người chuyển kho giữa mùa vẫn chia được vì mỗi ngày chấm công ghi kèm kho
  /// tại thời điểm đó — đây là con số để hai kho đối chiếu với nhau.
  Widget _stationCard(Map<String, double> byStation) {
    final keys = byStation.keys.toList()..sort();
    return SectionCard(
      title: 'Tiền công theo kho',
      icon: Icons.warehouse,
      child: Column(
        children: [
          for (final kho in keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(kho, style: const TextStyle(fontSize: 13.5))),
                  Text('${formatMoney(byStation[kho])} đ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: AppTheme.gapSm),
          const Text(
            'Chia theo số công làm ở từng kho, nên tổng các kho luôn khớp tổng lương.',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Kết quả một lần quyết toán: ai được trả, ai bị bỏ qua và vì sao.
class _SettleResultDialog extends StatelessWidget {
  const _SettleResultDialog({required this.result});

  final SettleResult result;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Đã quyết toán ${result.paidCount} người'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tổng trả: ${formatMoney(result.totalPaid)} đ',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (result.paid.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  for (final line in result.paid)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(child: Text(line.name)),
                          Text('${formatMoney(line.amount)} đ'),
                        ],
                      ),
                    ),
                ],
                if (result.skipped.isNotEmpty) ...[
                  const Divider(height: 20),
                  Text('Bỏ qua ${result.skipped.length} người',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: AppTheme.offline)),
                  const SizedBox(height: 4),
                  for (final line in result.skipped)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• ${line.name}: ${line.reason ?? 'không rõ'}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      );
}
