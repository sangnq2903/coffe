import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';

/// Chi tiết một đoàn: danh sách nhân viên và cấu hình lương.
///
/// Phần chấm công và tiền lương làm ở bước sau; màn hình này lo phần khai báo
/// nền — không khai đủ giai đoạn và giá thì chấm công không tra ra lương.
class CrewDetailScreen extends StatefulWidget {
  const CrewDetailScreen({super.key, required this.crew});

  final Crew crew;

  @override
  State<CrewDetailScreen> createState() => _CrewDetailScreenState();
}

class _CrewDetailScreenState extends State<CrewDetailScreen> {
  WageTable _wage = const WageTable();
  List<Worker> _dangLam = const [];
  List<Worker> _daNghi = const [];
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
      final wage = await client.wageTable(widget.crew.id);
      final lam = await client.workers(widget.crew.id, status: WorkerStatus.dangLam);
      final nghi = await client.workers(widget.crew.id, status: WorkerStatus.daNghi);
      if (!mounted) return;
      setState(() {
        _wage = wage;
        _dangLam = lam;
        _daNghi = nghi;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.crew.displayName),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Nhân viên'),
              Tab(icon: Icon(Icons.tune), text: 'Cấu hình lương'),
            ],
          ),
          actions: [
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
              child: TabBarView(
                children: [_workersTab(), _configTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- nhân viên

  Widget _workersTab() => ListView(
        padding: const EdgeInsets.all(AppTheme.gapMd),
        children: [
          if (!_wage.isComplete) _configWarning(),
          SectionCard(
            title: 'Đang làm việc (${_dangLam.length})',
            icon: Icons.badge,
            padded: false,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _editWorker(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm'),
              ),
            ),
            child: _dangLam.isEmpty
                ? const EmptyHint(
                    icon: Icons.person_add_alt,
                    message: 'Chưa có ai trong đoàn.')
                : Column(
                    children: [
                      for (var i = 0; i < _dangLam.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _workerTile(_dangLam[i], working: true),
                      ],
                    ],
                  ),
          ),
          if (_daNghi.isNotEmpty) ...[
            const SizedBox(height: AppTheme.gapMd),
            SectionCard(
              title: 'Đã nghỉ làm (${_daNghi.length})',
              icon: Icons.person_off,
              accentColor: AppTheme.textMuted,
              padded: false,
              child: Column(
                children: [
                  for (var i = 0; i < _daNghi.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _workerTile(_daNghi[i], working: false),
                  ],
                ],
              ),
            ),
          ],
        ],
      );

  Widget _workerTile(Worker worker, {required bool working}) {
    final band = _wage.bands.where((b) => b.id == worker.bandId).firstOrNull;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (working ? AppTheme.primary : AppTheme.textMuted)
            .withValues(alpha: 0.14),
        child: Text(
          worker.name.trim().isEmpty ? '?' : worker.name.trim()[0].toUpperCase(),
          style: TextStyle(
            color: working ? AppTheme.primary : AppTheme.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(worker.name),
      subtitle: Text([
        band?.name ?? 'CHƯA GÁN MỨC LƯƠNG',
        if (worker.phone != null && worker.phone!.isNotEmpty) worker.phone!,
        if (worker.joinDate != null) 'vào ${formatDate(worker.joinDate)}',
        if (!working && worker.leaveDate != null) 'nghỉ ${formatDate(worker.leaveDate)}',
      ].join(' • ')),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => switch (value) {
          'sua' => _editWorker(worker),
          'nghi' => _run(() => _client!.stopWorker(worker.id).then((_) {})),
          'lam-lai' => _run(() => _client!.resumeWorker(worker.id).then((_) {})),
          _ => null,
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'sua', child: Text('Sửa thông tin')),
          if (working)
            const PopupMenuItem(value: 'nghi', child: Text('Cho nghỉ làm'))
          else
            const PopupMenuItem(value: 'lam-lai', child: Text('Cho làm lại')),
        ],
      ),
    );
  }

  Future<void> _editWorker([Worker? worker]) async {
    if (_wage.bands.isEmpty && worker == null) {
      _snack('Khai bảng mức lương trước đã — sang tab "Cấu hình lương".');
      return;
    }
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _WorkerDialog(worker: worker, bands: _wage.bands),
    );
    if (result == null || !mounted) return;
    await _run(() => _client!
        .saveWorker(
          crewId: widget.crew.id,
          id: worker?.id,
          name: result['name'] as String,
          phone: result['phone'] as String?,
          bandId: result['band_id'] as String?,
          joinDate: result['join_date'] as DateTime?,
        )
        .then((_) {}));
  }

  // ------------------------------------------------------------- cấu hình

  Widget _configWarning() => Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.gapMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.unstable.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.unstable.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: AppTheme.unstable, size: 20),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(
                  _wage.phases.isEmpty
                      ? 'Chưa khai giai đoạn lương nào. Chấm công sẽ không tra ra lương.'
                      : _wage.bands.isEmpty
                          ? 'Chưa có mức lương nào. Sang tab "Cấu hình lương" để khai.'
                          : 'Còn ${_wage.missing.length} ô chưa khai giá — '
                              'người thuộc mức đó sẽ không tính được lương.',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _configTab() => ListView(
        padding: const EdgeInsets.all(AppTheme.gapMd),
        children: [
          SectionCard(
            title: 'Giai đoạn lương',
            icon: Icons.date_range,
            padded: false,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _editPhase(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm'),
              ),
            ),
            child: _wage.phases.isEmpty
                ? const EmptyHint(
                    icon: Icons.event_note,
                    message: 'Chưa có giai đoạn nào.\n'
                        'Thường có hai: đầu mùa và mùa rộ, khác nhau mức lương.',
                  )
                : Column(
                    children: [
                      for (var i = 0; i < _wage.phases.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.label_outline),
                          title: Text(_wage.phases[i].name),
                          subtitle: Text(
                            'Từ ${formatDate(_wage.phases[i].fromDate)} '
                            '${_wage.phases[i].toDate == null ? '— chưa chốt ngày kết thúc' : 'đến ${formatDate(_wage.phases[i].toDate)}'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editPhase(_wage.phases[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: AppTheme.gapMd),
          SectionCard(
            title: 'Bảng mức lương (đồng/tháng)',
            icon: Icons.table_chart,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _addBand,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm mức'),
              ),
            ),
            child: _wageMatrix(),
          ),
        ],
      );

  Widget _wageMatrix() {
    if (_wage.phases.isEmpty) {
      return const EmptyHint(
        icon: Icons.tune,
        message: 'Khai giai đoạn lương trước, rồi mới khai giá cho từng mức.',
      );
    }
    if (_wage.bands.isEmpty) {
      return const EmptyHint(
        icon: Icons.layers_outlined,
        message: 'Chưa có mức lương nào.\n'
            'Nhiều người dùng chung một mức — đổi giá chỉ phải sửa một chỗ.',
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 28,
        columns: [
          const DataColumn(label: Text('Mức lương')),
          for (final phase in _wage.phases) DataColumn(label: Text(phase.name)),
          const DataColumn(label: Text('')),
        ],
        rows: [
          for (final band in _wage.bands)
            DataRow(cells: [
              DataCell(Text(band.name,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              for (final phase in _wage.phases)
                DataCell(
                  _rateCell(_wage.amountFor(band.id, phase.id)),
                  onTap: () => _editRate(band, phase),
                ),
              DataCell(IconButton(
                tooltip: 'Xoá mức lương',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _run(
                    () => _client!.deleteBand(widget.crew.id, band.id)),
              )),
            ]),
        ],
      ),
    );
  }

  Widget _rateCell(double? amount) => amount == null
      ? const Row(
          children: [
            Icon(Icons.add, size: 15, color: AppTheme.offline),
            SizedBox(width: 4),
            Text('chưa khai',
                style: TextStyle(color: AppTheme.offline, fontSize: 13)),
          ],
        )
      : Text(formatWeight(amount), style: AppTheme.digits(15));

  Future<void> _editPhase([WagePhase? phase]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _PhaseDialog(phase: phase),
    );
    if (result == null || !mounted) return;
    await _run(() => _client!
        .savePhase(
          crewId: widget.crew.id,
          id: phase?.id,
          name: result['name'] as String,
          fromDate: result['from'] as DateTime,
          toDate: result['to'] as DateTime?,
          sortOrder: _wage.phases.length,
        )
        .then((_) {}));
  }

  Future<void> _addBand() async {
    final name = await _askText('Thêm mức lương', 'Tên mức', 'VD: Thợ chính');
    if (name == null || !mounted) return;
    await _run(() =>
        _client!.saveBand(crewId: widget.crew.id, name: name).then((_) {}));
  }

  Future<void> _editRate(WageBand band, WagePhase phase) async {
    final current = _wage.amountFor(band.id, phase.id);
    final text = await _askText(
      '${band.name} — ${phase.name}',
      'Lương một tháng (đồng)',
      'VD: 8000000',
      initial: current == null ? '' : current.round().toString(),
      numeric: true,
    );
    if (text == null || !mounted) return;
    final amount = parseNumber(text);
    if (amount == null || amount < 0) {
      _snack('Số tiền không hợp lệ.');
      return;
    }
    await _run(() => _client!
        .saveRate(
          crewId: widget.crew.id,
          phaseId: phase.id,
          bandId: band.id,
          monthlyAmount: amount,
        )
        .then((_) {}));
  }

  Future<String?> _askText(
    String title,
    String label,
    String hint, {
    String initial = '',
    bool numeric = false,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

class _PhaseDialog extends StatefulWidget {
  const _PhaseDialog({this.phase});

  final WagePhase? phase;

  @override
  State<_PhaseDialog> createState() => _PhaseDialogState();
}

class _PhaseDialogState extends State<_PhaseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.phase?.name ?? '');
  late DateTime _from = widget.phase?.fromDate ?? DateTime.now();
  late DateTime? _to = widget.phase?.toDate;

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.phase == null ? 'Thêm giai đoạn' : 'Sửa giai đoạn'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên giai đoạn *',
                    hintText: 'VD: Đầu mùa / Mùa rộ',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pick(isFrom: true),
                  icon: const Icon(Icons.event),
                  label: Text('Từ ngày: ${formatDate(_from)}'),
                ),
                const SizedBox(height: AppTheme.gapSm),
                OutlinedButton.icon(
                  onPressed: () => _pick(isFrom: false),
                  icon: const Icon(Icons.event_available),
                  label: Text(_to == null
                      ? 'Đến ngày: chưa chốt'
                      : 'Đến ngày: ${formatDate(_to)}'),
                ),
                if (_to != null)
                  TextButton(
                    onPressed: () => setState(() => _to = null),
                    child: const Text('Bỏ ngày kết thúc'),
                  ),
                const SizedBox(height: AppTheme.gapSm),
                const Text(
                  'Hai giai đoạn không được phủ lên cùng một ngày — nếu chồng nhau '
                  'thì một ngày chấm công tra ra hai mức lương khác nhau.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'from': _from,
                'to': _to,
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

class _WorkerDialog extends StatefulWidget {
  const _WorkerDialog({this.worker, required this.bands});

  final Worker? worker;
  final List<WageBand> bands;

  @override
  State<_WorkerDialog> createState() => _WorkerDialogState();
}

class _WorkerDialogState extends State<_WorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.worker?.name ?? '');
  late final _phone = TextEditingController(text: widget.worker?.phone ?? '');
  late String? _bandId = widget.worker?.bandId;
  late DateTime _joinDate = widget.worker?.joinDate ?? DateTime.now();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.worker == null ? 'Thêm nhân viên' : 'Sửa nhân viên'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Họ tên *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Điện thoại'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: widget.bands.any((b) => b.id == _bandId) ? _bandId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Mức lương',
                    helperText: 'Nhiều người dùng chung một mức',
                  ),
                  items: widget.bands
                      .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _bandId = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _joinDate,
                      firstDate: DateTime(DateTime.now().year - 3),
                      lastDate: DateTime(DateTime.now().year + 1),
                    );
                    if (picked != null) setState(() => _joinDate = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Ngày vào làm: ${formatDate(_joinDate)}'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'phone': _phone.text.trim(),
                'band_id': _bandId,
                'join_date': _joinDate,
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}
