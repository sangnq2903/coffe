import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../core/ticket_printer.dart';
import '../state/server_connection.dart';
import '../widgets/ticket_tile.dart';
import 'ticket_detail_sheet.dart';

/// Tra cứu phiếu cân: lọc theo kho, trạng thái, khoảng ngày và từ khoá.
///
/// Ở máy chủ trung tâm màn hình này là chỗ xem gộp số liệu của mọi kho; ở trạm
/// cân thì có dữ liệu của kho đó cộng phần đã kéo về từ trung tâm.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  final _searchController = TextEditingController();

  List<WeighTicket> _tickets = const [];
  String? _stationFilter;
  TicketStatus? _statusFilter;
  DateTimeRange? _range;
  bool _loading = false;
  String? _error;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
      final list = await client.tickets(
        stationCode: _stationFilter,
        status: _statusFilter,
        query: _searchController.text,
        from: _range?.start,
        // Chọn ngày chỉ cho ra 00:00; phải kéo tới cuối ngày, nếu không phiếu
        // cân trong chính ngày kết thúc sẽ bị lọt ra ngoài kết quả.
        to: _range == null
            ? null
            : DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59),
        limit: 300,
      );
      if (!mounted) return;
      setState(() => _tickets = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
      helpText: 'Chọn khoảng ngày',
      saveText: 'Xong',
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  Future<void> _print(WeighTicket ticket) async {
    try {
      await TicketPrinter.print(ticket);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Không in được phiếu: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<ServerConnection>().stations;
    final done = _tickets.where((t) => t.status == TicketStatus.hoanThanh).toList();
    final totalNet = done.fold<double>(0, (sum, t) => sum + t.netWeight);
    final totalProduct = done.fold<double>(0, (sum, t) => sum + t.productWeight);

    return ListView(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      children: [
        SectionCard(
          title: 'Bộ lọc',
          icon: Icons.filter_alt_outlined,
          trailing: TextButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Làm mới'),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Tìm biển số / khách hàng / số phiếu',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String?>(
                  value: _stationFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kho / trạm cân'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả kho')),
                    ...stations
                        .map((s) => DropdownMenuItem(value: s.code, child: Text(s.name))),
                  ],
                  onChanged: (value) {
                    setState(() => _stationFilter = value);
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<TicketStatus?>(
                  value: _statusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tất cả')),
                    ...TicketStatus.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label))),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value);
                    _load();
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range, size: 19),
                label: Text(
                  _range == null
                      ? 'Chọn ngày'
                      : '${formatDate(_range!.start)} – ${formatDate(_range!.end)}',
                ),
              ),
              if (_range != null)
                IconButton(
                  tooltip: 'Bỏ lọc ngày',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => _range = null);
                    _load();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.gapMd),

        // Ba ô cùng một kiểu. Trước đây ô giữa tô nền đặc màu chủ đạo, nhìn như
        // đang nhấn mạnh ngẫu nhiên trong khi cả ba đều là số tổng ngang nhau.
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Số phiếu',
                value: '${_tickets.length}',
                icon: Icons.receipt_long,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Tổng KL hàng',
                value: formatWeight(totalNet),
                unit: 'kg',
                icon: Icons.scale,
                tone: AppTheme.primary,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: StatTile(
                label: 'Tổng KL thành phẩm',
                value: formatWeight(totalProduct),
                unit: 'kg',
                icon: Icons.inventory_2,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gapMd),

        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppTheme.offline)),
          const SizedBox(height: AppTheme.gapSm),
        ],

        SectionCard(
          title: 'Danh sách phiếu cân',
          icon: Icons.list_alt,
          padded: false,
          trailing: _loading
              ? const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
          child: _tickets.isEmpty && !_loading
              ? const EmptyHint(
                  icon: Icons.search_off,
                  message: 'Không có phiếu cân nào khớp bộ lọc.',
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tickets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => TicketTile(
                    ticket: _tickets[index],
                    showStation: true,
                    onTap: () => showTicketDetailSheet(context, _tickets[index]),
                    onPrint: () => _print(_tickets[index]),
                  ),
                ),
        ),
      ],
    );
  }

}
