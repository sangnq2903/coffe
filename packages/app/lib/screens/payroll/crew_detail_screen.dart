import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';
import 'attendance_tab.dart';
import 'money_tab.dart';
import 'report_tab.dart';

/// Chi tiết một đoàn: chấm công, bảng tháng, nhân viên và cấu hình lương.
///
/// Mở ra là vào ngay tab chấm công vì đó là việc làm hằng ngày. Không khai đủ
/// giai đoạn và giá thì chấm công không tra ra lương, nên tab cấu hình có cảnh
/// báo riêng.
class CrewDetailScreen extends StatefulWidget {
  const CrewDetailScreen({super.key, required this.crew});

  final Crew crew;

  @override
  State<CrewDetailScreen> createState() => _CrewDetailScreenState();
}

class _CrewDetailScreenState extends State<CrewDetailScreen> {
  /// Bản đoàn đang hiển thị.
  ///
  /// Chốt mùa đổi trạng thái đoàn, mà nút thanh toán ở tab Tiền lại phụ thuộc
  /// trạng thái đó — giữ bản riêng để chốt xong là các tab thấy ngay.
  late Crew _crew = widget.crew;

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

  Future<void> _reloadCrew() async {
    final client = _client;
    if (client == null) return;
    try {
      final crew = await client.crew(_crew.id);
      if (mounted) setState(() => _crew = crew);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_crew.displayName),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.how_to_reg), text: 'Chấm công'),
              Tab(icon: Icon(Icons.table_chart), text: 'Bảng tháng'),
              Tab(icon: Icon(Icons.payments), text: 'Tiền'),
              Tab(icon: Icon(Icons.assignment), text: 'Báo cáo'),
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
              child: PageBody(
                padding: EdgeInsets.zero,
                child: TabBarView(
                  children: [
                    AttendanceDayTab(crewId: widget.crew.id),
                    AttendanceMonthTab(crewId: widget.crew.id),
                  MoneyTab(crew: _crew),
                  ReportTab(crew: _crew, onCrewChanged: _reloadCrew),
                    _workersTab(),
                    _configTab(),
                  ],
                ),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_dangLam.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _transferMany,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Chuyển kho'),
                    ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _editWorker(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm'),
                  ),
                ],
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
        // Kho đứng trước mức lương vì đây là thứ hay đổi nhất — người trong
        // đoàn chuyển qua lại giữa các kho.
        worker.stationCode == null ? 'CHƯA GÁN KHO' : 'Kho ${worker.stationCode}',
        band?.name ?? 'CHƯA GÁN MỨC LƯƠNG',
        if (worker.phone != null && worker.phone!.isNotEmpty) worker.phone!,
        if (worker.joinDate != null) 'vào ${formatDate(worker.joinDate)}',
        if (!working && worker.leaveDate != null) 'nghỉ ${formatDate(worker.leaveDate)}',
      ].join(' • ')),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => switch (value) {
          'sua' => _editWorker(worker),
          'chuyen-kho' => _transferMany(only: worker),
          'nghi' => _run(() => _client!.stopWorker(worker.id).then((_) {})),
          'lam-lai' => _run(() => _client!.resumeWorker(worker.id).then((_) {})),
          _ => null,
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'sua', child: Text('Sửa thông tin')),
          if (working)
            const PopupMenuItem(value: 'chuyen-kho', child: Text('Chuyển kho')),
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
      builder: (context) => _WorkerDialog(
        worker: worker,
        bands: _wage.bands,
        stations: context.read<ServerConnection>().stations,
      ),
    );
    if (result == null || !mounted) return;
    await _run(() => _client!
        .saveWorker(
          crewId: widget.crew.id,
          id: worker?.id,
          name: result['name'] as String,
          phone: result['phone'] as String?,
          stationCode: result['station_code'] as String?,
          bandId: result['band_id'] as String?,
          joinDate: result['join_date'] as DateTime?,
        )
        .then((_) {}));
  }

  /// Chuyển người sang kho khác, có hiệu lực từ bây giờ.
  ///
  /// Truyền [only] để chuyển đúng một người; bỏ trống thì mở hộp thoại chọn
  /// nhiều người cùng lúc — cả tổ chuyển sang kho khác là chuyện thường.
  Future<void> _transferMany({Worker? only}) async {
    final stations = context.read<ServerConnection>().stations;
    if (stations.isEmpty) {
      _snack('Chưa có kho nào. Bật máy trạm lên rồi quay lại.');
      return;
    }

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _TransferDialog(
        workers: only != null ? [only] : _dangLam,
        stations: stations,
        preselect: only != null ? {only.id} : const {},
      ),
    );
    if (result == null || !mounted) return;

    final ids = (result['worker_ids'] as List).cast<String>();
    final kho = result['station_code'] as String;
    await _run(() async {
      final moved = await _client!.transferWorkers(
        crewId: widget.crew.id,
        workerIds: ids,
        stationCode: kho,
      );
      _snack('Đã chuyển ${moved.length} người sang kho $kho. '
          'Những ngày đã chấm công vẫn tính cho kho cũ.');
    });
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
                            '${_wage.phases[i].toDate == null ? '— chưa chốt ngày kết thúc' : 'đến ${formatDate(_wage.phases[i].toDate)}'}\n'
                            'Ca ${_wage.phases[i].workStart}–${_wage.phases[i].workEnd}, '
                            'nghỉ ${formatDecimal(_wage.phases[i].breakHours)} giờ '
                            '→ ${formatDecimal(_wage.phases[i].standardHours)} giờ chuẩn/ngày',
                          ),
                          isThreeLine: true,
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
          workStart: result['work_start'] as String,
          workEnd: result['work_end'] as String,
          breakHours: result['break_hours'] as double,
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
  late String _workStart = widget.phase?.workStart ?? WagePhase.defaultWorkStart;
  late String _workEnd = widget.phase?.workEnd ?? WagePhase.defaultWorkEnd;
  late final _breakHours = TextEditingController(
      text: formatDecimal(widget.phase?.breakHours ?? WagePhase.defaultBreakHours));

  double? get _break => parseNumber(_breakHours.text);

  /// Giờ chuẩn tính sẵn để người khai thấy ngay con số mình đang chốt.
  double? get _standardHours {
    final start = WagePhase.parseClock(_workStart);
    final end = WagePhase.parseClock(_workEnd);
    final nghi = _break;
    if (start == null || end == null || nghi == null) return null;
    final gio = end - start - nghi;
    return gio > 0 ? gio : null;
  }

  Future<void> _pickClock({required bool isStart}) async {
    final current = WagePhase.parseClock(isStart ? _workStart : _workEnd) ?? 7;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.floor(), minute: ((current % 1) * 60).round()),
    );
    if (picked == null) return;
    final text = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() => isStart ? _workStart = text : _workEnd = text);
  }

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
                const Divider(height: 28),
                const Text('Giờ làm trong ngày',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppTheme.gapSm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickClock(isStart: true),
                        icon: const Icon(Icons.login, size: 18),
                        label: Text('Vào ca $_workStart'),
                      ),
                    ),
                    const SizedBox(width: AppTheme.gapSm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickClock(isStart: false),
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text('Tan ca $_workEnd'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.gapSm),
                TextFormField(
                  controller: _breakHours,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tổng giờ nghỉ giữa ca',
                    helperText: 'Nghỉ trưa 11:30–13:00 là 1,5; thêm nghỉ tối 17:30–19:00 là 3',
                    suffixText: 'giờ',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = parseNumber(v);
                    if (n == null || n < 0) return 'Nhập số giờ nghỉ, ví dụ 1,5';
                    if (_standardHours == null) return 'Giờ nghỉ nuốt cả ca — kiểm lại';
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.gapSm),
                Text(
                  _standardHours == null
                      ? 'Chưa ra được giờ chuẩn — giờ tan ca phải sau giờ vào ca và '
                          'giờ nghỉ phải nhỏ hơn cả ca.'
                      : 'Giờ chuẩn: ${formatDecimal(_standardHours)} giờ/ngày. '
                          'Ai nghỉ vài giờ thì công tính theo tỷ lệ trên số này.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _standardHours == null ? AppTheme.offline : AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
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
              if (_standardHours == null) return;
              Navigator.pop(context, {
                'name': _name.text.trim(),
                'from': _from,
                'to': _to,
                'work_start': _workStart,
                'work_end': _workEnd,
                'break_hours': _break!,
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

class _WorkerDialog extends StatefulWidget {
  const _WorkerDialog({this.worker, required this.bands, required this.stations});

  final Worker? worker;
  final List<WageBand> bands;
  final List<Station> stations;

  @override
  State<_WorkerDialog> createState() => _WorkerDialogState();
}

class _WorkerDialogState extends State<_WorkerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.worker?.name ?? '');
  late final _phone = TextEditingController(text: widget.worker?.phone ?? '');
  late String? _bandId = widget.worker?.bandId;
  late String? _stationCode = widget.worker?.stationCode;
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
                DropdownButtonFormField<String?>(
                  value: widget.stations.any((s) => s.code == _stationCode)
                      ? _stationCode
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kho đang làm',
                    helperText: 'Đổi được bất cứ lúc nào bằng chức năng "Chuyển kho"',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Chưa gán kho')),
                    for (final s in widget.stations)
                      DropdownMenuItem<String?>(
                          value: s.code, child: Text('${s.name} (${s.code})')),
                  ],
                  onChanged: (v) => setState(() => _stationCode = v),
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
                'station_code': _stationCode,
                'band_id': _bandId,
                'join_date': _joinDate,
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

/// Chọn người và kho đích để chuyển.
///
/// Cho chọn nhiều người vì cả tổ chuyển sang kho khác là chuyện thường; chuyển
/// từng người một thì vừa lâu vừa dễ sót.
class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    required this.workers,
    required this.stations,
    required this.preselect,
  });

  final List<Worker> workers;
  final List<Station> stations;
  final Set<String> preselect;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late final Set<String> _chosen = {...widget.preselect};
  late String _stationCode = widget.stations.first.code;

  @override
  Widget build(BuildContext context) {
    final single = widget.workers.length == 1;
    return AlertDialog(
      title: Text(single ? 'Chuyển kho cho ${widget.workers.single.name}' : 'Chuyển kho'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _stationCode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Chuyển sang kho *'),
              items: widget.stations
                  .map((s) => DropdownMenuItem(
                        value: s.code,
                        child: Text('${s.name} (${s.code})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _stationCode = v ?? _stationCode),
            ),
            const SizedBox(height: 12),
            if (!single) ...[
              Row(
                children: [
                  Text('Chọn người (${_chosen.length}/${widget.workers.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      if (_chosen.length == widget.workers.length) {
                        _chosen.clear();
                      } else {
                        _chosen.addAll(widget.workers.map((w) => w.id));
                      }
                    }),
                    child: Text(_chosen.length == widget.workers.length
                        ? 'Bỏ chọn hết'
                        : 'Chọn hết'),
                  ),
                ],
              ),
              // Danh sách có thể dài nên giới hạn chiều cao rồi cho cuộn, chứ
              // không thì hộp thoại tràn khỏi màn hình.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.workers.length,
                  itemBuilder: (context, i) {
                    final w = widget.workers[i];
                    return CheckboxListTile(
                      dense: true,
                      value: _chosen.contains(w.id),
                      title: Text(w.name),
                      subtitle: Text(w.stationCode == null
                          ? 'chưa gán kho'
                          : 'đang ở ${w.stationCode}'),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _chosen.add(w.id);
                        } else {
                          _chosen.remove(w.id);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Chỉ đổi kho từ bây giờ. Những ngày đã chấm công vẫn tính cho kho cũ.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, {
                    'worker_ids': _chosen.toList(),
                    'station_code': _stationCode,
                  }),
          child: const Text('Chuyển'),
        ),
      ],
    );
  }
}
