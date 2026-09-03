import 'dart:async';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../core/ticket_printer.dart';
import '../state/live_weight_controller.dart';
import '../state/server_connection.dart';
import '../widgets/station_picker.dart';
import '../widgets/ticket_tile.dart';
import '../widgets/weight_display.dart';
import 'ticket_detail_sheet.dart';

/// Màn hình cân — nơi nhân viên làm việc suốt ca.
///
/// Hai chế độ tự chuyển cho nhau: xe mới vào thì lập phiếu và ghi cân lần 1;
/// xe đã có phiếu dở dang thì chỉ việc chốt cân lần 2. Biển số là khoá nhận
/// diện, gõ xong là màn hình tự biết xe đang ở bước nào.
class WeighScreen extends StatefulWidget {
  const WeighScreen({super.key});

  @override
  State<WeighScreen> createState() => _WeighScreenState();
}

class _WeighScreenState extends State<WeighScreen> {
  final _plateController = TextEditingController();
  final _customerController = TextEditingController();
  final _yieldController = TextEditingController(text: '100');
  final _noteController = TextEditingController();
  final _manualWeightController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  WeighDirection _direction = WeighDirection.nhap;
  GoodsType? _goodsType;
  Customer? _customer;
  WeighTicket? _pendingTicket;
  List<WeighTicket> _pendingList = const [];
  List<WeighTicket> _recentList = const [];
  List<Vehicle> _vehicles = const [];
  List<Customer> _customers = const [];

  bool _manualEntry = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _plateDebounce;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    // Danh sách có thể được máy khác trong cùng kho tạo ra, nên phải tự làm mới
    // định kỳ chứ không chỉ sau thao tác của chính máy này.
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadTickets());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _plateDebounce?.cancel();
    _plateController.dispose();
    _customerController.dispose();
    _yieldController.dispose();
    _noteController.dispose();
    _manualWeightController.dispose();
    super.dispose();
  }

  ServerConnection get _conn => context.read<ServerConnection>();

  Future<void> _loadAll() async {
    await Future.wait([_loadTickets(), _loadCatalogs()]);
  }

  Future<void> _loadCatalogs() async {
    final client = _conn.client;
    if (client == null) return;
    try {
      final vehicles = await client.vehicles();
      final customers = await client.customers();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _customers = customers;
        _goodsType ??= _conn.goodsTypes.firstOrNull;
        if (_goodsType != null && _yieldController.text == '100') {
          _yieldController.text = formatDecimal(_goodsType!.defaultYieldRatio);
        }
      });
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    }
  }

  Future<void> _loadTickets() async {
    final client = _conn.client;
    if (client == null) return;
    try {
      final station = _conn.stationCode;
      final pending = await client.tickets(
        stationCode: station,
        status: TicketStatus.choLan2,
        limit: 50,
      );
      final recent = await client.tickets(stationCode: station, limit: 25);
      if (!mounted) return;
      setState(() {
        _pendingList = pending;
        _recentList = recent;
      });
    } on ApiException {
      // Mất mạng tạm thời không nên xoá danh sách đang hiển thị.
    }
  }

  void _onPlateChanged(String value) {
    _plateDebounce?.cancel();
    _plateDebounce = Timer(const Duration(milliseconds: 400), () {
      final plate = Vehicle.normalizePlate(value);
      if (plate.length < 4) {
        if (_pendingTicket != null) setState(() => _pendingTicket = null);
        return;
      }
      final match = _pendingList.where((t) => t.plateNo == plate).firstOrNull;
      if (match != null) {
        _selectPending(match);
        return;
      }
      if (_pendingTicket != null) setState(() => _pendingTicket = null);
      _prefillFromVehicle(plate);
    });
  }

  /// Xe quen thì điền sẵn chủ hàng của lần cân trước.
  void _prefillFromVehicle(String plate) {
    final vehicle = _vehicles.where((v) => v.plateNo == plate).firstOrNull;
    if (vehicle == null) return;
    final customer = _customers.where((c) => c.id == vehicle.customerId).firstOrNull;
    if (customer != null && _customerController.text.isEmpty) {
      setState(() {
        _customer = customer;
        _customerController.text = customer.name;
      });
    }
  }

  void _selectPending(WeighTicket ticket) {
    setState(() {
      _pendingTicket = ticket;
      _plateController.text = ticket.plateNo;
      _customerController.text = ticket.customerName;
      _direction = ticket.direction;
      _yieldController.text = formatDecimal(ticket.yieldRatio);
      _noteController.text = ticket.note ?? '';
      _goodsType =
          _conn.goodsTypes.where((g) => g.id == ticket.goodsTypeId).firstOrNull;
      _message = null;
    });
  }

  void _clearForm() {
    setState(() {
      _pendingTicket = null;
      _customer = null;
      _plateController.clear();
      _customerController.clear();
      _noteController.clear();
      _manualWeightController.clear();
      _manualEntry = false;
      _goodsType = _conn.goodsTypes.firstOrNull;
      _yieldController.text = formatDecimal(_goodsType?.defaultYieldRatio ?? 100);
    });
  }

  /// Số cân dùng để ghi vào phiếu: lấy từ đầu cân, hoặc từ ô nhập tay khi đầu
  /// cân hỏng (vẫn phải cân được, không thể dừng cả kho vì một sợi cáp).
  double? _captureWeight() {
    if (_manualEntry) return parseNumber(_manualWeightController.text);
    final live = context.read<LiveWeightController>();
    return live.canCapture ? live.weight.roundToDouble() : null;
  }

  Future<void> _saveFirstWeigh() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final client = _conn.client;
    if (client == null) return;
    final weight = _captureWeight();
    if (weight == null) {
      _showMessage(_captureHint(), isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final ticket = await client.createTicket({
        'station_code': _conn.stationCode,
        'direction': _direction.value,
        'plate_no': _plateController.text,
        'customer_id': _customer?.id,
        'customer_name': _customerController.text,
        'goods_type_id': _goodsType?.id,
        'goods_name': _goodsType?.name ?? '',
        'yield_ratio': parseNumber(_yieldController.text) ?? 100,
        'first_weight': weight,
        'note': _noteController.text,
        'created_by': _conn.settings.operatorName,
      });
      _clearForm();
      await _loadTickets();
      _showMessage('Đã lưu cân lần 1 — phiếu ${ticket.ticketNo}, ${formatWeight(weight)} kg.');
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSecondWeigh() async {
    final ticket = _pendingTicket;
    final client = _conn.client;
    if (ticket == null || client == null) return;
    final weight = _captureWeight();
    if (weight == null) {
      _showMessage(_captureHint(), isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final done = await client.completeTicket(
        ticket.id,
        weight,
        note: _noteController.text.isEmpty ? null : _noteController.text,
      );
      _clearForm();
      await _loadTickets();
      if (!mounted) return;
      _showMessage('Hoàn tất phiếu ${done.ticketNo} — KL hàng ${formatWeight(done.netWeight)} kg.');
      // Mở ngay phiếu vừa chốt để đối chiếu với tài xế và in trước khi xe rời kho.
      await showTicketDetailSheet(context, done);
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _captureHint() => _manualEntry
      ? 'Chưa nhập số cân.'
      : 'Số cân chưa ổn định hoặc đầu cân đang mất kết nối. '
          'Có thể bật "Nhập số cân bằng tay" để cân thủ công.';

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _print(WeighTicket ticket) async {
    try {
      await TicketPrinter.print(ticket);
    } catch (e) {
      _showMessage('Không in được phiếu: $e', isError: true);
    }
  }

  // ------------------------------------------------------------------- bố cục

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    final stationName = conn.station?.displayName ?? conn.stationCode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        final pad = wide ? AppTheme.gapLg : AppTheme.gapMd;

        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad * 2),
            children: [
              WeightDisplay(
                stationName: stationName,
                compact: !wide,
                onTapStation: () => showStationPicker(context),
              ),
              SizedBox(height: pad),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: _formCard()),
                    const SizedBox(width: AppTheme.gapMd),
                    Expanded(flex: 5, child: _pendingCard()),
                  ],
                )
              else ...[
                _pendingCard(),
                const SizedBox(height: AppTheme.gapMd),
                _formCard(),
              ],
              SizedBox(height: pad),
              _recentCard(),
            ],
          ),
        );
      },
    );
  }

  Widget _formCard() {
    final live = context.watch<LiveWeightController>();
    final isSecondWeigh = _pendingTicket != null;
    final captured = _captureWeight();

    return SectionCard(
      title: isSecondWeigh
          ? 'Cân lần 2 — phiếu ${_pendingTicket!.ticketNo}'
          : 'Lập phiếu mới — cân lần 1',
      icon: isSecondWeigh ? Icons.check_circle_outline : Icons.add_box_outlined,
      accentColor: isSecondWeigh ? AppTheme.stable : AppTheme.primary,
      trailing: isSecondWeigh
          ? TextButton.icon(
              onPressed: _clearForm,
              icon: const Icon(Icons.close, size: 17),
              label: const Text('Bỏ chọn'),
            )
          : null,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<WeighDirection>(
              segments: WeighDirection.values
                  .map((d) => ButtonSegment(
                        value: d,
                        label: Text(d.label),
                        icon: Icon(
                          d == WeighDirection.nhap ? Icons.south_west : Icons.north_east,
                          size: 17,
                        ),
                      ))
                  .toList(),
              selected: {_direction},
              onSelectionChanged: isSecondWeigh
                  ? null
                  : (value) => setState(() => _direction = value.first),
            ),
            const SizedBox(height: AppTheme.gapMd),

            const Text('XE & KHÁCH HÀNG', style: AppTheme.sectionLabel),
            const SizedBox(height: AppTheme.gapSm),
            _plateField(),
            const SizedBox(height: 12),
            _customerField(),
            const SizedBox(height: AppTheme.gapMd),

            const Text('HÀNG HOÁ', style: AppTheme.sectionLabel),
            const SizedBox(height: AppTheme.gapSm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _goodsField()),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _yieldField()),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppTheme.gapMd),

            _manualEntryBlock(),
            if (isSecondWeigh) ...[
              const SizedBox(height: AppTheme.gapMd),
              _netPreview(captured),
            ],
            const SizedBox(height: AppTheme.gapMd),
            _primaryAction(live, isSecondWeigh, captured),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _messageBanner(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryAction(LiveWeightController live, bool isSecondWeigh, double? captured) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _saving ? null : (isSecondWeigh ? _saveSecondWeigh : _saveFirstWeigh),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 62),
            backgroundColor: isSecondWeigh ? AppTheme.stable : AppTheme.primary,
          ),
          icon: _saving
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(isSecondWeigh ? Icons.check_circle : Icons.save, size: 22),
          label: Text(
            isSecondWeigh
                ? 'CHỐT CÂN LẦN 2  •  ${formatWeight(captured)} kg'
                : 'LƯU CÂN LẦN 1  •  ${formatWeight(captured)} kg',
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
        ),
        if (captured == null) ...[
          const SizedBox(height: AppTheme.gapSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                live.connected ? Icons.hourglass_top : Icons.warning_amber,
                size: 15,
                color: live.connected ? AppTheme.unstable : AppTheme.offline,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _manualEntry
                      ? 'Nhập số cân vào ô bên trên để lưu phiếu.'
                      : live.connected
                          ? 'Đang chờ số cân đứng yên...'
                          : 'Đầu cân chưa sẵn sàng — bật "Nhập số cân bằng tay" để cân thủ công.',
                  style: TextStyle(
                    color: live.connected ? AppTheme.unstable : AppTheme.offline,
                    fontSize: 12.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _plateField() => Autocomplete<Vehicle>(
        displayStringForOption: (v) => v.plateNo,
        optionsBuilder: (value) {
          final text = value.text.trim().toLowerCase();
          if (text.isEmpty) return const Iterable<Vehicle>.empty();
          return _vehicles.where((v) => v.searchText.contains(text)).take(8);
        },
        onSelected: (vehicle) {
          _plateController.text = vehicle.plateNo;
          _onPlateChanged(vehicle.plateNo);
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          // Autocomplete tự quản một controller riêng; đồng bộ hai chiều để việc
          // chọn phiếu ở danh sách bên cạnh cũng điền được vào ô này.
          if (controller.text != _plateController.text) {
            controller.text = _plateController.text;
          }
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Biển số xe *',
              hintText: 'VD: 51C-123.45',
              prefixIcon: Icon(Icons.local_shipping),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 4) ? 'Nhập biển số xe' : null,
            onChanged: (value) {
              _plateController.text = value;
              _onPlateChanged(value);
            },
          );
        },
      );

  Widget _customerField() => Autocomplete<Customer>(
        displayStringForOption: (c) => c.name,
        optionsBuilder: (value) {
          final text = value.text.trim().toLowerCase();
          if (text.isEmpty) return const Iterable<Customer>.empty();
          return _customers.where((c) => c.searchText.contains(text)).take(8);
        },
        onSelected: (customer) {
          setState(() {
            _customer = customer;
            _customerController.text = customer.name;
          });
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          if (controller.text != _customerController.text) {
            controller.text = _customerController.text;
          }
          return TextFormField(
            controller: controller,
            focusNode: focusNode,
            decoration: const InputDecoration(
              labelText: 'Khách hàng',
              hintText: 'Gõ để tìm, hoặc nhập tên mới',
              prefixIcon: Icon(Icons.person),
            ),
            onChanged: (value) {
              _customerController.text = value;
              // Gõ tay đè lên lựa chọn cũ thì bỏ liên kết, để server tự khớp
              // hoặc tạo khách hàng mới theo đúng tên vừa nhập.
              if (_customer != null && _customer!.name != value) {
                _customer = null;
              }
            },
          );
        },
      );

  Widget _goodsField() {
    final goods = _conn.goodsTypes;
    return DropdownButtonFormField<GoodsType>(
      value: goods.contains(_goodsType) ? _goodsType : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Loại hàng *',
        prefixIcon: Icon(Icons.inventory_2),
      ),
      items: goods.map((g) => DropdownMenuItem(value: g, child: Text(g.name))).toList(),
      validator: (v) => v == null ? 'Chọn loại hàng' : null,
      onChanged: _pendingTicket != null
          ? null
          : (value) => setState(() {
                _goodsType = value;
                // Đổi loại hàng thì kéo theo tỷ lệ thành phẩm mặc định của loại
                // đó, nhân viên chỉ sửa khi lô hàng cụ thể khác thường.
                if (value != null) {
                  _yieldController.text = formatDecimal(value.defaultYieldRatio);
                }
              }),
    );
  }

  Widget _yieldField() => TextFormField(
        controller: _yieldController,
        decoration: const InputDecoration(labelText: 'Tỷ lệ TP *', suffixText: '%'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        validator: (v) {
          final value = parseNumber(v);
          if (value == null) return 'Nhập tỷ lệ';
          if (value < 0 || value > 100) return '0 – 100';
          return null;
        },
      );

  Widget _manualEntryBlock() => Container(
        decoration: BoxDecoration(
          color: _manualEntry ? AppTheme.unstable.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _manualEntry ? AppTheme.unstable.withValues(alpha: 0.4) : AppTheme.line,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note, size: 20, color: AppTheme.textMuted),
                const SizedBox(width: AppTheme.gapSm),
                const Expanded(
                  child: Text(
                    'Nhập số cân bằng tay',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: _manualEntry,
                  onChanged: (value) => setState(() => _manualEntry = value),
                ),
              ],
            ),
            if (_manualEntry)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 4, 12),
                child: TextFormField(
                  controller: _manualWeightController,
                  autofocus: true,
                  style: AppTheme.digits(24, weight: FontWeight.w800),
                  decoration: const InputDecoration(
                    labelText: 'Số cân (kg)',
                    prefixIcon: Icon(Icons.scale),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ],
        ),
      );

  /// Xem trước khối lượng hàng ngay trước khi bấm chốt, để phát hiện sai sót
  /// (chọn nhầm phiếu, xe chưa xuống hết bàn cân) trước khi ghi vào sổ.
  Widget _netPreview(double? captured) {
    final ticket = _pendingTicket!;
    final first = ticket.firstWeight ?? 0;
    final net = captured == null ? null : (first - captured).abs();
    final yieldRatio = parseNumber(_yieldController.text) ?? ticket.yieldRatio;
    final product = net == null ? null : net * yieldRatio / 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.stable.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.stable.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          _previewCell('Cân lần 1', formatWeight(first)),
          _previewCell('Cân lần 2', formatWeight(captured)),
          Container(width: 1, height: 34, color: AppTheme.stable.withValues(alpha: 0.25)),
          _previewCell('KL HÀNG', formatWeight(net), highlight: true),
          _previewCell('KL thành phẩm', formatWeight(product)),
        ],
      ),
    );
  }

  Widget _previewCell(String label, String value, {bool highlight = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: highlight ? FontWeight.w800 : FontWeight.w500,
                  color: highlight ? AppTheme.stable : AppTheme.textMuted,
                  letterSpacing: highlight ? 0.5 : 0,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: AppTheme.digits(
                    highlight ? 21 : 16,
                    color: highlight ? AppTheme.stable : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _messageBanner() => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: (_messageIsError ? AppTheme.offline : AppTheme.stable).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (_messageIsError ? AppTheme.offline : AppTheme.stable)
                .withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
              color: _messageIsError ? AppTheme.offline : AppTheme.stable,
              size: 20,
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(child: Text(_message!, style: const TextStyle(fontSize: 13.5))),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _message = null),
            ),
          ],
        ),
      );

  Widget _pendingCard() => SectionCard(
        title: 'Xe chờ cân lần 2',
        icon: Icons.hourglass_bottom,
        accentColor: AppTheme.unstable,
        padded: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusPill(
              label: '${_pendingList.length}',
              color: AppTheme.unstable,
              compact: true,
            ),
            IconButton(
              tooltip: 'Làm mới',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadTickets,
            ),
          ],
        ),
        child: _pendingList.isEmpty
            ? const EmptyHint(
                icon: Icons.local_shipping_outlined,
                message: 'Chưa có xe nào chờ cân lần 2.\n'
                    'Xe cân lần 1 xong sẽ hiện ở đây.',
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pendingList.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ticket = _pendingList[index];
                  final selected = _pendingTicket?.id == ticket.id;
                  return Container(
                    color: selected ? AppTheme.primary.withValues(alpha: 0.06) : null,
                    child: ListTile(
                      onTap: () => _selectPending(ticket),
                      contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                      title: Row(
                        children: [
                          Text(ticket.plateNo,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                          const SizedBox(width: AppTheme.gapSm),
                          if (selected)
                            const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
                        ],
                      ),
                      subtitle: Text(
                        '${ticket.goodsName} • ${ticket.customerName.isEmpty ? "—" : ticket.customerName}\n'
                        'Lần 1: ${formatWeight(ticket.firstWeight)} kg  •  ${formatTime(ticket.firstWeightAt)}',
                      ),
                      isThreeLine: true,
                      trailing: FilledButton.tonal(
                        onPressed: () => _selectPending(ticket),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Cân lần 2'),
                      ),
                    ),
                  );
                },
              ),
      );

  Widget _recentCard() => SectionCard(
        title: 'Phiếu cân gần đây',
        icon: Icons.history,
        padded: false,
        trailing: IconButton(
          tooltip: 'Làm mới',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _loadTickets,
        ),
        child: _recentList.isEmpty
            ? const EmptyHint(
                icon: Icons.receipt_long_outlined,
                message: 'Chưa có phiếu cân nào ở trạm này.',
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentList.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final ticket = _recentList[index];
                  return TicketTile(
                    ticket: ticket,
                    onTap: () => showTicketDetailSheet(context, ticket),
                    onPrint: () => _print(ticket),
                  );
                },
              ),
      );
}
