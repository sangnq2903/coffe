import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/server_connection.dart';
import 'crew_detail_screen.dart';

/// Danh sách đoàn — mỗi đoàn là một mùa vụ tại một kho.
class CrewsScreen extends StatefulWidget {
  const CrewsScreen({super.key});

  @override
  State<CrewsScreen> createState() => _CrewsScreenState();
}

class _CrewsScreenState extends State<CrewsScreen> {
  final _searchController = TextEditingController();

  List<Crew> _crews = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await client.crews();
      if (mounted) setState(() => _crews = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Crew> get _visible {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _crews;
    return _crews
        .where((c) => '${c.name} ${c.season} ${c.stationCode}'.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _createCrew() async {
    final conn = context.read<ServerConnection>();
    final stations = conn.stations;
    if (stations.isEmpty) {
      _snack('Chưa có kho nào. Bật máy trạm lên rồi quay lại.');
      return;
    }

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CrewDialog(stations: stations),
    );
    if (result == null || !mounted) return;
    try {
      await conn.client!.saveCrew(
        name: result['name'] as String,
        stationCode: result['station'] as String,
        season: result['season'] as String,
        startDate: result['start'] as DateTime?,
      );
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapMd, AppTheme.gapSm),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Tìm đoàn theo tên, niên vụ hoặc kho',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppTheme.gapSm),
              FilledButton.icon(
                onPressed: _createCrew,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.add),
                label: const Text('Lập đoàn'),
              ),
              const SizedBox(width: AppTheme.gapSm),
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
          child: _visible.isEmpty && !_loading
              ? const EmptyHint(
                  icon: Icons.groups_outlined,
                  message: 'Chưa có đoàn nào.\n'
                      'Mỗi mùa vụ lập một đoàn với danh sách người riêng.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.gapMd, 0, AppTheme.gapMd, AppTheme.gapLg),
                  itemCount: _visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppTheme.gapSm),
                  itemBuilder: (context, index) => _CrewCard(
                    crew: _visible[index],
                    onOpen: () => _open(_visible[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _open(Crew crew) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => CrewDetailScreen(crew: crew),
    ));
    await _load();
  }
}

class _CrewCard extends StatelessWidget {
  const _CrewCard({required this.crew, required this.onOpen});

  final Crew crew;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = crew.isOpen ? AppTheme.primary : AppTheme.textMuted;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.gapMd),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.line),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.groups, color: color),
            ),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crew.displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      'Kho ${crew.stationCode}',
                      if (crew.startDate != null) 'từ ${formatDate(crew.startDate)}',
                    ].join(' • '),
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            StatusPill(label: crew.status.label, color: color, compact: true),
            const SizedBox(width: AppTheme.gapSm),
            const Icon(Icons.chevron_right, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CrewDialog extends StatefulWidget {
  const _CrewDialog({required this.stations});

  final List<Station> stations;

  @override
  State<_CrewDialog> createState() => _CrewDialogState();
}

class _CrewDialogState extends State<_CrewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _season = TextEditingController();

  String? _station;
  DateTime? _start;

  @override
  void initState() {
    super.initState();
    _station = widget.stations.first.code;
    final now = DateTime.now();
    _season.text = '${now.year}-${now.year + 1}';
    _start = now;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Lập đoàn mới'),
        content: SizedBox(
          width: 460,
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
                    labelText: 'Tên đoàn *',
                    hintText: 'VD: Đoàn hái cà',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên đoàn' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _season,
                  decoration: const InputDecoration(
                    labelText: 'Niên vụ',
                    hintText: 'VD: 2025-2026',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _station,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kho *',
                    helperText: 'Đoàn thuộc kho nào thì chỉ người của kho đó xem được',
                  ),
                  items: widget.stations
                      .map((s) => DropdownMenuItem(
                            value: s.code,
                            child: Text('${s.name} (${s.code})'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _station = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _start ?? DateTime.now(),
                      firstDate: DateTime(DateTime.now().year - 2),
                      lastDate: DateTime(DateTime.now().year + 3),
                    );
                    if (picked != null) setState(() => _start = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text('Ngày bắt đầu: ${formatDate(_start)}'),
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
                'season': _season.text.trim(),
                'station': _station!,
                'start': _start,
              });
            },
            child: const Text('Lập đoàn'),
          ),
        ],
      );
}
