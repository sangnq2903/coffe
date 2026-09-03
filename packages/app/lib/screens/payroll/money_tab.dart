import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';

/// Che số tiền sau dấu chấm khi chưa bấm mở.
///
/// Chấm công thường làm ngay trước mặt cả đoàn, mà lương từng người là chuyện
/// riêng — nên mặc định che, muốn xem thì bấm con mắt.
String maskMoney(double? value, {required bool masked}) =>
    masked ? '•••' : formatMoney(value);

/// Bảng tiền của cả đoàn: ai còn phải trả bao nhiêu, ai đã nhận vượt.
class MoneyTab extends StatefulWidget {
  const MoneyTab({super.key, required this.crew});

  final Crew crew;

  @override
  State<MoneyTab> createState() => _MoneyTabState();
}

class _MoneyTabState extends State<MoneyTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  CrewMoney? _money;
  bool _loading = false;
  bool _masked = true;
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
      final money = await client.crewMoney(
        widget.crew.id,
        year: _month.year,
        month: _month.month,
      );
      if (mounted) setState(() => _money = money);
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
    final money = _money;
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
                  'Trần ứng tháng ${_month.month}/${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
              IconButton(
                tooltip: _masked ? 'Hiện số tiền' : 'Che số tiền',
                icon: Icon(_masked ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _masked = !_masked),
              ),
              IconButton(
                tooltip: 'Làm mới',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
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
          child: money == null
              ? const SizedBox.shrink()
              : money.rows.isEmpty
                  ? const EmptyHint(
                      icon: Icons.payments_outlined,
                      message: 'Chưa có ai để tính tiền.\n'
                          'Thêm người vào đoàn và chấm công trước đã.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
                      children: [
                        if (money.negativeCount > 0) _negativeWarning(money),
                        _totals(money),
                        const SizedBox(height: AppTheme.gapMd),
                        SectionCard(
                          title: 'Từng người (${money.rows.length})',
                          icon: Icons.groups,
                          padded: false,
                          child: Column(
                            children: [
                              for (var i = 0; i < money.rows.length; i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _row(money.rows[i]),
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

  Widget _negativeWarning(CrewMoney money) => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.offline.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppTheme.offline.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.report_problem, size: 20, color: AppTheme.offline),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(
                  '${money.negativeCount} người đã nhận nhiều hơn công đã làm. '
                  'Số dư âm là tiền công ty đang cho vay — xem lại trước khi ứng thêm.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _totals(CrewMoney money) => SectionCard(
        title: 'Cả đoàn',
        icon: Icons.account_balance_wallet,
        child: Column(
          children: [
            _totalLine('Thu nhập cả mùa', money.totalEarned),
            _totalLine('Đã ứng', money.totalAdvanced),
            _totalLine('Đã thanh toán', money.totalPaid),
            const Divider(height: 20),
            _totalLine(
              'Còn phải trả',
              money.totalBalance,
              color: money.totalBalance < 0 ? AppTheme.offline : AppTheme.primary,
              bold: true,
            ),
          ],
        ),
      );

  Widget _totalLine(String label, double value, {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textMuted,
                      fontWeight: bold ? FontWeight.w700 : null)),
            ),
            Text(
              '${maskMoney(value, masked: _masked)} đ',
              style: TextStyle(
                fontSize: bold ? 16 : 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );

  Widget _row(MoneyRow row) {
    final am = row.balance.isNegative;
    final conUng = row.thisMonth.remainingAdvance;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (am ? AppTheme.offline : AppTheme.primary).withValues(alpha: 0.14),
        child: Icon(am ? Icons.trending_down : Icons.person,
            color: am ? AppTheme.offline : AppTheme.primary, size: 20),
      ),
      title: Text(row.name),
      subtitle: Text([
        if (row.stationCode != null) 'Kho ${row.stationCode}',
        'trần tháng ${maskMoney(row.thisMonth.advanceCap, masked: _masked)}',
        conUng <= 0
            ? 'hết mức ứng'
            : 'còn ứng được ${maskMoney(conUng, masked: _masked)}',
      ].join(' • ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${maskMoney(row.balance.balance, masked: _masked)} đ',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: am ? AppTheme.offline : null,
            ),
          ),
          Text(am ? 'đã nhận vượt' : 'còn phải trả',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
      onTap: () => _open(row),
    );
  }

  Future<void> _open(MoneyRow row) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => WorkerMoneyScreen(
        crew: widget.crew,
        workerId: row.workerId,
        workerName: row.name,
      ),
    ));
    await _load();
  }
}

/// Sổ tiền của một người: công nợ, từng tháng và từng khoản.
class WorkerMoneyScreen extends StatefulWidget {
  const WorkerMoneyScreen({
    super.key,
    required this.crew,
    required this.workerId,
    required this.workerName,
  });

  final Crew crew;
  final String workerId;
  final String workerName;

  @override
  State<WorkerMoneyScreen> createState() => _WorkerMoneyScreenState();
}

class _WorkerMoneyScreenState extends State<WorkerMoneyScreen> {
  MoneySheet? _sheet;
  bool _loading = false;
  bool _masked = false;
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
      final sheet = await client.moneySheet(widget.crew.id, widget.workerId);
      if (mounted) setState(() => _sheet = sheet);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double? value) => maskMoney(value, masked: _masked);

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workerName),
        actions: [
          IconButton(
            tooltip: _masked ? 'Hiện số tiền' : 'Che số tiền',
            icon: Icon(_masked ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _masked = !_masked),
          ),
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppTheme.gapMd),
              child: Text(_error!, style: const TextStyle(color: AppTheme.offline)),
            ),
          Expanded(
            child: sheet == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.all(AppTheme.gapMd),
                    children: [
                      _balanceCard(sheet),
                      const SizedBox(height: AppTheme.gapMd),
                      _actions(sheet),
                      const SizedBox(height: AppTheme.gapMd),
                      _monthsCard(sheet),
                      const SizedBox(height: AppTheme.gapMd),
                      _entriesCard(sheet),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(MoneySheet sheet) {
    final b = sheet.balance;
    return SectionCard(
      title: 'Công nợ cả mùa',
      icon: Icons.account_balance_wallet,
      accentColor: b.isNegative ? AppTheme.offline : AppTheme.primary,
      child: Column(
        children: [
          _line('Thu nhập (lương + tăng ca + phụ cấp − trừ tiền)', b.totalEarned),
          _line('Đã ứng', b.totalAdvanced),
          _line('Đã thanh toán', b.totalPaid),
          const Divider(height: 20),
          _line(
            b.isNegative ? 'Đã nhận vượt' : 'Còn phải trả',
            b.balance,
            color: b.isNegative ? AppTheme.offline : AppTheme.primary,
            bold: true,
          ),
          if (b.isNegative)
            const Padding(
              padding: EdgeInsets.only(top: AppTheme.gapSm),
              child: Text(
                'Người này đã nhận nhiều hơn công đã làm. Số dư âm là tiền công ty '
                'đang cho vay — cân nhắc trước khi ứng thêm.',
                style: TextStyle(fontSize: 12, color: AppTheme.offline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(String label, double value, {Color? color, bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                      fontWeight: bold ? FontWeight.w700 : null)),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Text(
              '${_money(value)} đ',
              style: TextStyle(
                  fontSize: bold ? 17 : 14, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      );

  Widget _actions(MoneySheet sheet) {
    final daDong = widget.crew.status == CrewStatus.daHoanThanh;
    return SectionCard(
      title: 'Ghi khoản mới',
      icon: Icons.add_card,
      child: Wrap(
        spacing: AppTheme.gapSm,
        runSpacing: AppTheme.gapSm,
        children: [
          FilledButton.icon(
            onPressed: () => _addEntry(PayrollEntryType.ungLuong),
            icon: const Icon(Icons.payments, size: 18),
            label: const Text('Ứng lương'),
          ),
          OutlinedButton.icon(
            onPressed: () => _addEntry(PayrollEntryType.tangCa),
            icon: const Icon(Icons.more_time, size: 18),
            label: const Text('Tăng ca'),
          ),
          OutlinedButton.icon(
            onPressed: () => _addEntry(PayrollEntryType.phuCap),
            icon: const Icon(Icons.card_giftcard, size: 18),
            label: const Text('Phụ cấp'),
          ),
          OutlinedButton.icon(
            onPressed: () => _addEntry(PayrollEntryType.truTien),
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            label: const Text('Trừ tiền'),
          ),
          // Quyết toán chỉ làm một lần vào cuối mùa, nên chỉ bật khi đoàn đã
          // đóng — máy chủ cũng chặn, đây chỉ là tránh bấm rồi mới báo lỗi.
          Tooltip(
            message: daDong
                ? 'Quyết toán cuối mùa'
                : 'Trong mùa chỉ ứng lương. Đóng đoàn rồi mới thanh toán.',
            child: OutlinedButton.icon(
              onPressed: daDong ? () => _addEntry(PayrollEntryType.thanhToan) : null,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Thanh toán'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthsCard(MoneySheet sheet) => SectionCard(
        title: 'Theo tháng (${sheet.months.length})',
        icon: Icons.calendar_month,
        padded: false,
        child: sheet.months.isEmpty
            ? const EmptyHint(
                icon: Icons.calendar_today_outlined,
                message: 'Chưa có tháng nào có công hoặc có khoản tiền.')
            : Column(
                children: [
                  for (var i = 0; i < sheet.months.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _monthTile(sheet.months[i]),
                  ],
                ],
              ),
      );

  Widget _monthTile(MonthlyPayroll m) {
    final hetMuc = m.remainingAdvance <= 0;
    return ExpansionTile(
      title: Text('Tháng ${m.monthKey.substring(5)}/${m.monthKey.substring(0, 4)}'),
      subtitle: Text(
        '${formatDecimal(m.workUnits)} công • thu nhập ${_money(m.income)} • '
        '${hetMuc ? 'hết mức ứng' : 'còn ứng ${_money(m.remainingAdvance)}'}',
        style: TextStyle(color: m.overCap ? AppTheme.offline : null),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              _line('Lương theo công (${m.daysWorked} ngày)', m.wageEarned),
              if (m.overtime > 0) _line('Tăng ca', m.overtime),
              if (m.allowance > 0) _line('Phụ cấp', m.allowance),
              if (m.deduction > 0) _line('Trừ tiền', -m.deduction),
              const Divider(height: 16),
              _line('Thu nhập của tháng', m.income),
              _line('Trần ứng (50% thu nhập)', m.advanceCap),
              _line('Đã ứng trong tháng', m.advanced),
              _line('Còn được ứng', m.remainingAdvance,
                  color: hetMuc ? AppTheme.offline : AppTheme.primary, bold: true),
              if (m.overCap)
                const Padding(
                  padding: EdgeInsets.only(top: AppTheme.gapSm),
                  child: Text(
                    'Tháng này đã ứng vượt trần. Nợ dồn sang tháng sau không làm '
                    'trần tháng sau cao lên.',
                    style: TextStyle(fontSize: 12, color: AppTheme.offline),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entriesCard(MoneySheet sheet) => SectionCard(
        title: 'Sổ tiền (${sheet.entries.length} khoản)',
        icon: Icons.receipt_long,
        padded: false,
        child: sheet.entries.isEmpty
            ? const EmptyHint(
                icon: Icons.receipt_long_outlined,
                message: 'Chưa ghi khoản tiền nào.')
            : Column(
                children: [
                  for (var i = 0; i < sheet.entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _entryTile(sheet.entries[i]),
                  ],
                ],
              ),
      );

  Widget _entryTile(PayrollEntry entry) {
    final ra = entry.type == PayrollEntryType.ungLuong ||
        entry.type == PayrollEntryType.thanhToan ||
        entry.type == PayrollEntryType.truTien;
    return ListTile(
      leading: Icon(
        switch (entry.type) {
          PayrollEntryType.ungLuong => Icons.payments,
          PayrollEntryType.tangCa => Icons.more_time,
          PayrollEntryType.phuCap => Icons.card_giftcard,
          PayrollEntryType.truTien => Icons.remove_circle_outline,
          PayrollEntryType.thanhToan => Icons.done_all,
        },
        color: ra ? AppTheme.accent : AppTheme.stable,
      ),
      title: Row(
        children: [
          Expanded(child: Text(entry.type.label)),
          Text('${_money(entry.amount)} đ',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      subtitle: Text([
        formatDate(entry.date),
        if (entry.note != null && entry.note!.isNotEmpty) entry.note!,
        if (entry.isOverCap) '⚠ vượt trần: ${entry.overCapReason}',
      ].join(' • '),
          style: entry.isOverCap ? const TextStyle(color: AppTheme.offline) : null),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => switch (value) {
          'sua' => _addEntry(entry.type, entry: entry),
          'xoa' => _deleteEntry(entry),
          _ => null,
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'sua', child: Text('Sửa')),
          PopupMenuItem(value: 'xoa', child: Text('Xoá')),
        ],
      ),
    );
  }

  Future<void> _addEntry(PayrollEntryType type, {PayrollEntry? entry}) async {
    final sheet = _sheet;
    if (sheet == null) return;

    final saved = await showDialog<MoneySheet>(
      context: context,
      builder: (context) => _EntryDialog(
        crewId: widget.crew.id,
        workerId: widget.workerId,
        workerName: widget.workerName,
        type: type,
        entry: entry,
      ),
    );
    if (saved != null && mounted) setState(() => _sheet = saved);
  }

  Future<void> _deleteEntry(PayrollEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá khoản ${entry.type.label.toLowerCase()}?'),
        content: Text(
          '${formatMoney(entry.amount)} đ ngày ${formatDate(entry.date)}. '
          'Xoá rồi thì trần ứng và công nợ tính lại theo số còn lại.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.offline),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final sheet = await _client!.deleteEntry(widget.crew.id, entry.id);
      if (mounted) setState(() => _sheet = sheet);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }
}

/// Nhập một khoản tiền.
///
/// Riêng ứng lương thì vừa nhập vừa hỏi máy chủ còn được ứng bao nhiêu, để
/// người duyệt thấy cảnh báo **trước** khi bấm ghi chứ không phải sau.
class _EntryDialog extends StatefulWidget {
  const _EntryDialog({
    required this.crewId,
    required this.workerId,
    required this.workerName,
    required this.type,
    this.entry,
  });

  final String crewId;
  final String workerId;
  final String workerName;
  final PayrollEntryType type;
  final PayrollEntry? entry;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: widget.entry == null ? '' : formatMoney(widget.entry!.amount));
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late final _reason = TextEditingController(text: widget.entry?.overCapReason ?? '');
  late DateTime _date = widget.entry?.date ?? DateTime.now();

  AdvancePreview? _preview;
  bool _checking = false;
  bool _saving = false;
  String? _error;

  /// Số thứ tự lần hỏi gần nhất, để bỏ phản hồi cũ về muộn.
  int _lastCheck = 0;

  bool get _isAdvance => widget.type == PayrollEntryType.ungLuong;
  double? get _value => parseNumber(_amount.text);

  @override
  void initState() {
    super.initState();
    if (_isAdvance) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Hỏi máy chủ còn được ứng bao nhiêu với số vừa nhập.
  Future<void> _check() async {
    if (!_isAdvance) return;
    final client = context.read<ServerConnection>().client;
    if (client == null) return;

    final ticket = ++_lastCheck;
    setState(() => _checking = true);
    try {
      final preview = await client.previewAdvance(
        crewId: widget.crewId,
        workerId: widget.workerId,
        amount: _value ?? 0,
        date: _date,
        entryId: widget.entry?.id,
      );
      if (mounted && ticket == _lastCheck) setState(() => _preview = preview);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final client = context.read<ServerConnection>().client;
    if (client == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sheet = await client.saveEntry(
        crewId: widget.crewId,
        workerId: widget.workerId,
        type: widget.type,
        amount: _value!,
        id: widget.entry?.id,
        date: _date,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        overCapReason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, sheet);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final vuot = _isAdvance && (preview?.exceedsCap ?? false);
    return AlertDialog(
      title: Text('${widget.entry == null ? '' : 'Sửa '}'
          '${widget.type.label.toLowerCase()} — ${widget.workerName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Số tiền *',
                    suffixText: 'đ',
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _check();
                  },
                  validator: (v) {
                    final n = parseNumber(v);
                    if (n == null || n <= 0) return 'Nhập số tiền lớn hơn 0';
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.gapSm),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(DateTime.now().year - 2),
                      lastDate: DateTime(DateTime.now().year + 1),
                    );
                    if (picked == null) return;
                    setState(() => _date = picked);
                    // Trần ứng tính theo tháng, đổi ngày là đổi cả trần.
                    _check();
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Ngày: ${formatDate(_date)}'),
                ),
                const SizedBox(height: AppTheme.gapSm),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                ),
                if (_isAdvance) ...[
                  const SizedBox(height: AppTheme.gapMd),
                  _capPanel(preview),
                ],
                if (vuot) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  TextFormField(
                    controller: _reason,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Lý do ứng vượt trần *',
                      helperText: 'Mọi lần vượt đều vào sổ để tra lại sau',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ứng vượt trần thì phải ghi lý do'
                        : null,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  Text(_error!, style: const TextStyle(color: AppTheme.offline)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: vuot ? FilledButton.styleFrom(backgroundColor: AppTheme.offline) : null,
          child: Text(vuot ? 'Vẫn ứng' : 'Ghi'),
        ),
      ],
    );
  }

  Widget _capPanel(AdvancePreview? preview) {
    if (preview == null) {
      return const Text('Đang tính trần ứng…',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted));
    }
    final vuot = preview.exceedsCap;
    final mau = vuot ? AppTheme.offline : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mau.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: mau.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vuot ? Icons.warning_amber_rounded : Icons.verified_outlined,
                  size: 18, color: mau),
              const SizedBox(width: 6),
              Text(
                'Trần ứng tháng ${_date.month}/${_date.year}',
                style: TextStyle(fontWeight: FontWeight.w700, color: mau),
              ),
              if (_checking) ...[
                const SizedBox(width: 8),
                const SizedBox(
                    width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Thu nhập đã làm được: ${formatMoney(preview.income)} đ\n'
            'Trần 50%: ${formatMoney(preview.cap)} đ • '
            'đã ứng ${formatMoney(preview.advancedBefore)} đ\n'
            'Còn được ứng: ${formatMoney(preview.allowed)} đ',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (preview.warning != null) ...[
            const SizedBox(height: 6),
            Text(preview.warning!,
                style: TextStyle(
                    fontSize: 12.5, color: mau, fontWeight: FontWeight.w600)),
          ],
          if (preview.suggested > 0 && preview.suggested != _value) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                _amount.text = formatMoney(preview.suggested);
                setState(() {});
                _check();
              },
              child: Text('Ứng tối đa ${formatMoney(preview.suggested)} đ'),
            ),
          ],
        ],
      ),
    );
  }
}
