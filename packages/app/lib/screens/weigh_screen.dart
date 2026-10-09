import 'dart:async';
import 'dart:math' as math;

import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../core/ticket_printer.dart';
import '../state/data_refresh_controller.dart';
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

  // Bố cục máy tính cho nhập tay cả số cân lẫn giờ cân của từng lần.
  final _firstCtl = TextEditingController();
  final _secondCtl = TextEditingController();
  final _firstAtCtl = TextEditingController();
  final _secondAtCtl = TextEditingController();
  WeighTicket? _editTicket;
  bool _classic = false;

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

  // Bảng phiếu của bố cục máy tính: lọc theo ngày xem và ô tìm phiếu.
  List<WeighTicket> _tableList = const [];
  String? _selectedId;
  String _searchQuery = '';
  late int _viewYear;
  late int _viewMonth;
  late int _viewDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewYear = now.year;
    _viewMonth = now.month;
    _viewDay = now.day;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());

    // Máy khác trong cùng kho lập phiếu thì máy này tự tải lại ngay. Chỉ tải
    // lại danh sách, không đụng vào form đang gõ dở.
    _huyLamMoi =
        context.read<DataRefreshController>().dangKy(const ['tickets'], _loadTickets);

    // Vẫn giữ một nhịp tự làm mới, nhưng thưa hẳn: giờ nó chỉ còn là lưới đỡ
    // cho trường hợp kênh tín hiệu chết mà không ai hay. Trước đây 10 giây một
    // lần vì đó là cách duy nhất biết máy khác vừa ghi gì.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadTickets());
  }

  /// Huỷ đăng ký nhận tín hiệu; gọi trong `dispose`.
  VoidCallback? _huyLamMoi;

  @override
  void dispose() {
    _huyLamMoi?.call();
    _refreshTimer?.cancel();
    _plateDebounce?.cancel();
    _plateController.dispose();
    _customerController.dispose();
    _yieldController.dispose();
    _noteController.dispose();
    _manualWeightController.dispose();
    _firstCtl.dispose();
    _secondCtl.dispose();
    _firstAtCtl.dispose();
    _secondAtCtl.dispose();
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
      await _loadTable();
    } on ApiException {
      // Mất mạng tạm thời không nên xoá danh sách đang hiển thị.
    }
  }

  /// Phiếu của ngày đang xem; ngày = 0 nghĩa là cả tháng.
  Future<void> _loadTable() async {
    final client = _conn.client;
    if (client == null) return;
    final from = DateTime(_viewYear, _viewMonth, _viewDay == 0 ? 1 : _viewDay);
    final to = _viewDay == 0
        ? DateTime(_viewYear, _viewMonth + 1, 1)
        : DateTime(_viewYear, _viewMonth, _viewDay + 1);
    try {
      final list = await client.tickets(
        stationCode: _conn.stationCode,
        query: _searchQuery,
        from: from,
        to: to.subtract(const Duration(milliseconds: 1)),
        limit: 500,
      );
      if (!mounted) return;
      setState(() => _tableList = list);
    } on ApiException {
      // Giữ nguyên bảng đang hiển thị khi mạng chập chờn.
    }
  }

  void _onPlateChanged(String value) {
    _plateDebounce?.cancel();
    _plateDebounce = Timer(const Duration(milliseconds: 400), () {
      // Đang sửa một phiếu đã chọn thì gõ biển số là sửa biển, không phải tìm phiếu khác.
      if (_classic && (_pendingTicket != null || _editTicket != null)) return;
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
      _editTicket = null;
      _fillWeights(ticket);
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
      _editTicket = null;
      _firstCtl.clear();
      _secondCtl.clear();
      _firstAtCtl.clear();
      _secondAtCtl.clear();
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
    final typed = parseNumber((_pendingTicket != null ? _secondCtl : _firstCtl).text);
    if (typed != null) return typed;
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
    final firstAt = _readDT(_firstAtCtl);
    if (!firstAt.ok) {
      _showMessage('Giờ cân lần 1 sai định dạng — gõ dd/mm/yyyy hh:mm.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final ticket = await client.createTicket({
        if (firstAt.value != null) 'first_weight_at': timeToMillis(firstAt.value),
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
        // Người lập phiếu do máy chủ điền từ tài khoản đang đăng nhập.
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
    if (_classic && !(_formKey.currentState?.validate() ?? false)) return;
    final firstAt = _readDT(_firstAtCtl);
    final secondAt = _readDT(_secondAtCtl);
    if (!firstAt.ok || !secondAt.ok) {
      _showMessage('Giờ cân sai định dạng — gõ dd/mm/yyyy hh:mm.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      // Bố cục máy tính cho sửa mọi ô ngay lúc chốt: ghi phần đã sửa trước, rồi mới chốt.
      if (_classic) {
        final changes = _fieldChanges(ticket, firstAt: firstAt.value);
        if (changes.isNotEmpty) await client.updateTicket(ticket.id, changes);
      }
      final done = await client.completeTicket(
        ticket.id,
        weight,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        secondWeightAt: secondAt.value,
      );
      _clearForm();
      await _loadTickets();
      if (!mounted) return;
      _showMessage('Hoàn tất phiếu ${done.ticketNo} — KL hàng ${formatWeight(done.netWeight)} kg.');
      // Mở ngay phiếu vừa chốt để đối chiếu với tài xế và in trước khi xe rời kho.
      if (await showTicketDetailSheet(context, done) && mounted) {
        await _loadTickets();
      }
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
        _classic = wide;
        if (wide) return _classicLayout(constraints, stationName);
        final pad = AppTheme.gapMd;

        return RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, pad * 2),
            children: [
              WeightDisplay(
                stationName: stationName,
                compact: true,
                onTapStation: () => showStationPicker(context),
              ),
              SizedBox(height: pad),
              _pendingCard(),
              const SizedBox(height: AppTheme.gapMd),
              _formCard(),
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

  Widget _plateField({bool classic = false}) => Autocomplete<Vehicle>(
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
            style: TextStyle(fontSize: classic ? 15 : 17, fontWeight: FontWeight.w700),
            decoration: classic
                ? _cDeco(hint: 'VD: 51C-123.45')
                : const InputDecoration(
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

  Widget _customerField({bool classic = false}) => Autocomplete<Customer>(
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
            decoration: classic
                ? _cDeco(hint: 'Gõ để tìm, hoặc nhập tên mới')
                : const InputDecoration(
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

  Widget _goodsField({bool classic = false}) {
    final goods = _conn.goodsTypes;
    return DropdownButtonFormField<GoodsType>(
      value: goods.contains(_goodsType) ? _goodsType : null,
      isExpanded: true,
      decoration: classic
          ? _cDeco()
          : const InputDecoration(
              labelText: 'Loại hàng *',
              prefixIcon: Icon(Icons.inventory_2),
            ),
      items: goods.map((g) => DropdownMenuItem(value: g, child: Text(g.name))).toList(),
      validator: (v) => v == null ? 'Chọn loại hàng' : null,
      onChanged: (!classic && _pendingTicket != null)
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

  Widget _yieldField({bool classic = false}) => TextFormField(
        controller: _yieldController,
        decoration: classic
            ? _cDeco(suffix: '%')
            : const InputDecoration(labelText: 'Tỷ lệ TP *', suffixText: '%'),
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
                    onTap: () async {
                      // Sửa hay xoá trong phiếu thì danh sách phải theo ngay,
                      // không thì vẫn thấy số cũ cho tới lần làm mới sau.
                      if (await showTicketDetailSheet(context, ticket) && mounted) {
                        await _loadTickets();
                      }
                    },
                    onPrint: () => _print(ticket),
                  );
                },
              ),
      );

  // ================================================= bố cục máy tính (kiểu cổ điển)
  //
  // Bố cục này bám theo phần mềm cân cũ mà nhân viên đã quen: bảng số cân đỏ lớn
  // bên trái, ô nhập bên phải, bảng phiếu bên dưới và bốn nút Tìm/Xoá/Xem/In.
  // Logic lưu cân vẫn dùng chung với bố cục điện thoại ở trên.

  static const _cPanel = Color(0xFFD9E7FB);
  static const _cBorder = Color(0xFF8DB0E3);
  static const _cHeader = Color(0xFFC6E0B4);
  static const _cRed = Color(0xFFE00000);
  static const _cLabel = TextStyle(fontSize: 13.5, color: Color(0xFF1B1A17));

  InputDecoration _cDeco({String? hint, String? suffix, Widget? suffixIcon}) {
    const side = BorderSide(color: Color(0xFF7A7A7A));
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      suffixText: suffix,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: side),
      enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: side),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Color(0xFF1F5FBF), width: 1.6),
      ),
    );
  }

  WeighTicket? get _selectedTicket =>
      _tableList.where((t) => t.id == _selectedId).firstOrNull;

  Widget _classicLayout(BoxConstraints constraints, String stationName) {
    final height =
        constraints.maxHeight.isFinite ? math.max(constraints.maxHeight, 860.0) : 860.0;
    return SingleChildScrollView(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 480,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 400, child: _classicLeftPanel(stationName)),
                    const SizedBox(width: 12),
                    Expanded(child: _classicFormPanel()),
                  ],
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                _messageBanner(),
              ],
              const SizedBox(height: 10),
              Expanded(child: _classicTable()),
              const SizedBox(height: 10),
              _classicActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cPanel,
          border: Border.all(color: _cBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: child,
      );

  /// Khung có tiêu đề nằm đè lên viền, như nhóm ô trong phần mềm cân cũ.
  Widget _group(String? title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(12, title == null ? 12 : 16, 12, 12),
              decoration: BoxDecoration(
                border: Border.all(color: _cBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: child,
            ),
            if (title != null)
              Positioned(
                left: 10,
                top: -9,
                child: Container(
                  color: _cPanel,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(title, style: _cLabel),
                ),
              ),
          ],
        ),
      );

  Widget _classicLeftPanel(String stationName) {
    final live = context.watch<LiveWeightController>();
    final statusColor = !live.connected
        ? AppTheme.offline
        : live.stable
            ? AppTheme.stable
            : AppTheme.unstable;
    final statusLabel = !live.connected
        ? 'MẤT KẾT NỐI ĐẦU CÂN'
        : live.stable
            ? 'SỐ ĐÃ ỔN ĐỊNH'
            : 'ĐANG DAO ĐỘNG';

    Widget radio(WeighDirection d) => InkWell(
          onTap: () => setState(() => _direction = d),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _direction == d ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 21,
                color: AppTheme.primaryDark,
              ),
              const SizedBox(width: 6),
              Text(d == WeighDirection.nhap ? 'Nhập' : 'Xuất',
                  style: const TextStyle(fontSize: 17)),
            ],
          ),
        );

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => showStationPicker(context),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(stationName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  height: 112,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EDF2),
                    border: Border.all(color: const Color(0xFF9AA3AE), width: 2),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      live.connected ? formatWeight(live.weight) : '—',
                      style: AppTheme.digits(78, color: _cRed, weight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('Kg',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: _cRed)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.circle, size: 11, color: statusColor),
              const SizedBox(width: 6),
              Text(statusLabel,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800, color: statusColor)),
            ],
          ),
          const SizedBox(height: 4),
          _group(
            null,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [for (final d in WeighDirection.values) radio(d)],
            ),
          ),
          _dateGroup(),
        ],
      ),
    );
  }

  Widget _dateGroup() {
    final days = DateUtils.getDaysInMonth(_viewYear, _viewMonth);
    final nowYear = DateTime.now().year;

    Widget dropdown(String label, int value, List<int> items, String Function(int) text,
            ValueChanged<int> onChanged) =>
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _cLabel),
            const SizedBox(width: 4),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DropdownButton<int>(
                value: value,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [
                  for (final v in items) DropdownMenuItem(value: v, child: Text(text(v))),
                ],
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ],
        );

    void apply(VoidCallback change) {
      setState(() {
        change();
        final max = DateUtils.getDaysInMonth(_viewYear, _viewMonth);
        if (_viewDay > max) _viewDay = max;
      });
      _loadTable();
    }

    return _group(
      'Ngày xem phiếu',
      Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          dropdown('Ngày:', _viewDay, [0, for (var i = 1; i <= days; i++) i],
              (v) => v == 0 ? 'Cả tháng' : '$v', (v) => apply(() => _viewDay = v)),
          dropdown('Tháng:', _viewMonth, [for (var i = 1; i <= 12; i++) i], (v) => '$v',
              (v) => apply(() => _viewMonth = v)),
          dropdown('Năm:', _viewYear, [for (var y = nowYear - 3; y <= nowYear + 1; y++) y],
              (v) => '$v', (v) => apply(() => _viewYear = v)),
        ],
      ),
    );
  }

  Widget _clbl(String text, {double w = 92}) =>
      SizedBox(width: w, child: Text(text, style: _cLabel));

  Widget _crow(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      );

  /// Ô chỉ đọc: số đỏ đậm cho khối lượng, chữ thường cho phần còn lại.
  Widget _ro(String value, {bool red = false, String? unit}) => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFF7A7A7A)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: red
                    ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _cRed)
                    : const TextStyle(fontSize: 14),
              ),
            ),
            if (unit != null)
              Text(unit, style: const TextStyle(fontSize: 13, color: _cRed)),
          ],
        ),
      );

  // ------------------------------------------------ giờ cân nhập tay

  static final _dtFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _dtRegex =
      RegExp(r'^\s*(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})\s+(\d{1,2})[:h](\d{2})\s*$');

  String _fmtDT(DateTime? value) => value == null ? '' : _dtFormat.format(value);

  /// Đọc "dd/mm/yyyy hh:mm" người dùng gõ; chuỗi sai định dạng hoặc ngày không có thật trả về `null`.
  DateTime? _parseDT(String text) {
    final m = _dtRegex.firstMatch(text);
    if (m == null) return null;
    var year = int.parse(m[3]!);
    if (year < 100) year += 2000;
    final month = int.parse(m[2]!);
    final day = int.parse(m[1]!);
    final hour = int.parse(m[4]!);
    final minute = int.parse(m[5]!);
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return null;
    final value = DateTime(year, month, day, hour, minute);
    return value.month == month && value.day == day ? value : null;
  }

  /// Ô để trống là hợp lệ (máy chủ lấy giờ hiện tại); gõ sai mới là lỗi.
  ({bool ok, DateTime? value}) _readDT(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return (ok: true, value: null);
    final value = _parseDT(text);
    return (ok: value != null, value: value);
  }

  Future<void> _pickDT(TextEditingController c) async {
    final current = _parseDT(c.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() => c.text =
        _fmtDT(DateTime(date.year, date.month, date.day, time.hour, time.minute)));
  }

  void _fillWeights(WeighTicket t) {
    _firstCtl.text = t.firstWeight == null ? '' : formatDecimal(t.firstWeight!);
    _firstAtCtl.text = _fmtDT(t.firstWeightAt);
    _secondCtl.text = t.secondWeight == null ? '' : formatDecimal(t.secondWeight!);
    _secondAtCtl.text = _fmtDT(t.secondWeightAt);
  }

  /// Những ô đã khác so với phiếu đang sửa — chỉ gửi phần đổi để không đè lên
  /// thứ người khác vừa sửa ở máy khác.
  Map<String, Object?> _fieldChanges(WeighTicket t,
      {DateTime? firstAt, bool includeWeights = true}) {
    final changes = <String, Object?>{};
    final plate = Vehicle.normalizePlate(_plateController.text);
    if (plate.isNotEmpty && plate != t.plateNo) changes['plate_no'] = plate;

    final customerName = _customerController.text.trim();
    if (customerName != t.customerName) {
      changes['customer_name'] = customerName;
      if (_customer != null) changes['customer_id'] = _customer!.id;
    }

    final goods = _goodsType;
    if (goods != null && goods.id != t.goodsTypeId) {
      changes['goods_type_id'] = goods.id;
      changes['goods_name'] = goods.name;
    }

    final ratio = parseNumber(_yieldController.text);
    if (ratio != null && (ratio - t.yieldRatio).abs() > 0.000001) {
      changes['yield_ratio'] = ratio;
    }
    if (_direction != t.direction) changes['direction'] = _direction.value;

    if (includeWeights) {
      final first = parseNumber(_firstCtl.text);
      if (first != null && first != t.firstWeight) changes['first_weight'] = first;
      if (firstAt != null && _fmtDT(t.firstWeightAt) != _firstAtCtl.text.trim()) {
        changes['first_weight_at'] = timeToMillis(firstAt);
      }
    }
    return changes;
  }

  /// Chọn một phiếu đã hoàn thành vào ô nhập để sửa mọi thứ, kể cả số cân và giờ cân.
  void _selectEdit(WeighTicket t) {
    setState(() {
      _pendingTicket = null;
      _editTicket = t;
      _customer = null;
      _plateController.text = t.plateNo;
      _customerController.text = t.customerName;
      _direction = t.direction;
      _yieldController.text = formatDecimal(t.yieldRatio);
      _noteController.text = t.note ?? '';
      _goodsType = _conn.goodsTypes.where((g) => g.id == t.goodsTypeId).firstOrNull ??
          _conn.goodsTypes.where((g) => g.name == t.goodsName).firstOrNull;
      _fillWeights(t);
      _message = null;
    });
  }

  Future<void> _saveEdit() async {
    final ticket = _editTicket;
    final client = _conn.client;
    if (ticket == null || client == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final first = parseNumber(_firstCtl.text);
    final second = parseNumber(_secondCtl.text);
    if (first == null || first <= 0) {
      _showMessage('Cân lần 1 phải lớn hơn 0.', isError: true);
      return;
    }
    if (second == null || second <= 0) {
      _showMessage('Cân lần 2 phải lớn hơn 0.', isError: true);
      return;
    }
    final firstAt = _readDT(_firstAtCtl);
    final secondAt = _readDT(_secondAtCtl);
    if (!firstAt.ok || !secondAt.ok) {
      _showMessage('Giờ cân sai định dạng — gõ dd/mm/yyyy hh:mm.', isError: true);
      return;
    }

    final changes = _fieldChanges(ticket, firstAt: firstAt.value);
    if (second != ticket.secondWeight) changes['second_weight'] = second;
    if (secondAt.value != null && _fmtDT(ticket.secondWeightAt) != _secondAtCtl.text.trim()) {
      changes['second_weight_at'] = timeToMillis(secondAt.value);
    }
    final note = _noteController.text.trim();
    if (note.isNotEmpty && note != (ticket.note ?? '').trim()) changes['note'] = note;
    if (changes.isEmpty) {
      _showMessage('Chưa có ô nào thay đổi.');
      return;
    }

    setState(() => _saving = true);
    try {
      final done = await client.updateTicket(ticket.id, changes);
      _clearForm();
      await _loadTickets();
      _showMessage('Đã cập nhật phiếu ${done.ticketNo} — KL hàng ${formatWeight(done.netWeight)} kg.');
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _weightField(TextEditingController c, LiveWeightController live,
      {bool enabled = true}) {
    final cap = live.canCapture ? live.weight.roundToDouble() : null;
    return TextFormField(
      controller: c,
      enabled: enabled,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _cRed),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: _cDeco(
        hint: cap != null ? formatWeight(cap) : 'nhập số',
        suffix: 'kg',
        suffixIcon: IconButton(
          tooltip: 'Lấy số đang hiện trên đầu cân',
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          icon: const Icon(Icons.scale),
          onPressed: !enabled || cap == null ? null : () => setState(() => c.text = formatDecimal(cap)),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dtField(TextEditingController c, {bool enabled = true}) => TextFormField(
        controller: c,
        enabled: enabled,
        style: const TextStyle(fontSize: 14),
        decoration: _cDeco(
          hint: 'dd/mm/yyyy hh:mm',
          suffixIcon: IconButton(
            tooltip: 'Chọn ngày giờ',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.event),
            onPressed: enabled ? () => _pickDT(c) : null,
          ),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty || _parseDT(v) != null) ? null : 'Gõ dd/mm/yyyy hh:mm',
        onChanged: (_) => setState(() {}),
      );

  Widget _classicFormPanel() {
    final live = context.watch<LiveWeightController>();
    final pending = _pendingTicket;
    final editing = _editTicket;
    final current = pending ?? editing;
    final isSecond = pending != null;
    final isEdit = editing != null;
    final isNew = current == null;

    final liveWeight = live.canCapture ? live.weight.roundToDouble() : null;
    final first = parseNumber(_firstCtl.text) ?? (isNew ? liveWeight : null);
    final second = parseNumber(_secondCtl.text) ?? (isSecond ? liveWeight : null);
    final net = first != null && second != null ? (first - second).abs() : null;
    final ratio = parseNumber(_yieldController.text) ?? current?.yieldRatio ?? 100;
    final product = net == null ? null : net * ratio / 100;
    final savedAt = _parseDT(_firstAtCtl.text) ?? current?.createdAt ?? DateTime.now();
    final accent = isNew ? AppTheme.primaryDark : (isEdit ? AppTheme.accent : AppTheme.stable);
    final title = isEdit
        ? 'Sửa phiếu ${editing.ticketNo} — sửa mọi ô rồi bấm Cập nhật'
        : isSecond
            ? 'Cân lần 2 — phiếu ${pending.ticketNo}'
            : 'Nhập vào ô cần sửa — lập phiếu mới (cân lần 1)';
    final actionLabel = _saving
        ? 'Đang lưu...'
        : isEdit
            ? 'Cập nhật phiếu'
            : isSecond
                ? 'Chốt cân lần 2'
                : 'Lưu cân lần 1';
    final VoidCallback? action =
        _saving ? null : (isEdit ? _saveEdit : (isSecond ? _saveSecondWeigh : _saveFirstWeigh));
    final needsReading = !isEdit &&
        (isNew ? parseNumber(_firstCtl.text) : parseNumber(_secondCtl.text)) == null &&
        liveWeight == null;

    return _panel(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accent),
                    ),
                  ),
                  if (!isNew) TextButton(onPressed: _clearForm, child: const Text('Bỏ chọn')),
                ],
              ),
              const SizedBox(height: 6),
              _crow([
                _clbl('Biển số xe *'),
                Expanded(flex: 3, child: _plateField(classic: true)),
                const SizedBox(width: 14),
                _clbl('Số phiếu', w: 72),
                Expanded(flex: 2, child: _ro(current?.ticketNo ?? 'Tự động cấp')),
              ]),
              _crow([
                _clbl('Khách hàng'),
                Expanded(flex: 3, child: _customerField(classic: true)),
                const SizedBox(width: 14),
                _clbl('Ngày lưu', w: 72),
                Expanded(flex: 2, child: _ro(formatDate(savedAt))),
              ]),
              _crow([
                _clbl('Loại hàng *'),
                Expanded(flex: 3, child: _goodsField(classic: true)),
                const SizedBox(width: 14),
                _clbl('Tỷ lệ TP *', w: 72),
                Expanded(flex: 2, child: _yieldField(classic: true)),
              ]),
              _crow([
                _clbl('Cân lần 1'),
                Expanded(flex: 2, child: _weightField(_firstCtl, live)),
                const SizedBox(width: 14),
                _clbl('Giờ cân 1', w: 72),
                Expanded(flex: 3, child: _dtField(_firstAtCtl)),
              ]),
              _crow([
                _clbl('Cân lần 2'),
                Expanded(flex: 2, child: _weightField(_secondCtl, live, enabled: !isNew)),
                const SizedBox(width: 14),
                _clbl('Giờ cân 2', w: 72),
                Expanded(flex: 3, child: _dtField(_secondAtCtl, enabled: !isNew)),
              ]),
              _crow([
                _clbl('KL hàng'),
                Expanded(flex: 2, child: _ro(formatWeight(net), red: true, unit: 'kg')),
                const SizedBox(width: 14),
                _clbl('KL thực', w: 72),
                Expanded(flex: 3, child: _ro(formatWeight(product), red: true, unit: 'kg')),
              ]),
              _crow([
                _clbl('Ghi chú'),
                Expanded(child: TextFormField(controller: _noteController, decoration: _cDeco())),
              ]),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _cBtn(actionLabel, action, primary: true),
                  const SizedBox(width: 24),
                  _cBtn('Huỷ bỏ', _clearForm),
                ],
              ),
              if (needsReading)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    live.connected
                        ? 'Đang chờ số cân đứng yên — hoặc gõ tay số cân vào ô.'
                        : 'Đầu cân chưa sẵn sàng — gõ tay số cân vào ô để cân thủ công.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: live.connected ? AppTheme.unstable : AppTheme.offline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cBtn(String label, VoidCallback? onPressed, {bool primary = false}) => SizedBox(
        height: 38,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary ? AppTheme.primary : const Color(0xFFF0F0F0),
            foregroundColor: primary ? Colors.white : Colors.black,
            minimumSize: const Size(140, 38),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
              side: const BorderSide(color: Color(0xFF666666)),
            ),
            textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
          child: Text(label),
        ),
      );

  Widget _classicTable() {
    const columns = <(String, int, bool)>[
      ('NGÀY CÂN', 12, false),
      ('SỐ PHIẾU', 19, false),
      ('SỐ XE', 14, false),
      ('KHÁCH HÀNG', 22, false),
      ('LOẠI HÀNG', 14, false),
      ('KL XE+HÀNG', 12, true),
      ('KL XE', 11, true),
      ('KL HÀNG', 11, true),
      ('T/C (%)', 8, true),
      ('KL THỰC', 12, true),
    ];

    Widget cell(String text, int flex,
            {bool right = false, bool bold = false, Color? color}) =>
        Expanded(
          flex: flex,
          child: Container(
            height: 30,
            alignment: right ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFD3D8D5))),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
        );

    Widget row(WeighTicket t) {
      final done = t.status == TicketStatus.hoanThanh;
      final selected = t.id == _selectedId;
      const dash = '—';
      final values = <String>[
        formatDate(t.createdAt),
        t.ticketNo,
        t.plateNo,
        t.customerName,
        t.goodsName,
        done ? formatWeight(t.grossWeight) : dash,
        done ? formatWeight(t.tareWeight) : dash,
        done ? formatWeight(t.netWeight) : dash,
        formatDecimal(t.yieldRatio),
        done ? formatWeight(t.productWeight) : t.status.label,
      ];
      return InkWell(
        onTap: () => _selectRow(t),
        onDoubleTap: () => _xemPhieu(t),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFBBD6F5)
                : t.status == TicketStatus.choLan2
                    ? const Color(0xFFFFF4D6)
                    : Colors.white,
            border: const Border(bottom: BorderSide(color: Color(0xFFD3D8D5))),
          ),
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                cell(
                  values[i],
                  columns[i].$2,
                  right: columns[i].$3,
                  bold: i == 2 || (i == 9 && !done),
                  color: i == 9 && !done ? AppTheme.unstable : null,
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF7A7A7A))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchQuery.isNotEmpty)
            Container(
              color: const Color(0xFFFFF4D6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                        'Kết quả tìm "$_searchQuery" (mọi ngày) — ${_tableList.length} phiếu',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _searchQuery = '');
                      _loadTable();
                    },
                    child: const Text('Bỏ lọc'),
                  ),
                ],
              ),
            ),
          Container(
            color: _cHeader,
            child: Row(
              children: [
                for (final c in columns)
                  Expanded(
                    flex: c.$2,
                    child: Container(
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: Color(0xFFA9C597))),
                      ),
                      child: Text(
                        c.$1,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F3F8F),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: _tableList.isEmpty
                  ? const Center(
                      child: Text('Không có phiếu cân nào trong thời gian đã chọn.',
                          style: TextStyle(color: AppTheme.textMuted)),
                    )
                  : ListView.builder(
                      itemCount: _tableList.length,
                      itemBuilder: (context, index) => row(_tableList[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _classicActions() {
    final selected = _selectedTicket;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _cPanel,
        border: Border.all(color: _cBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _cBtn('Tìm phiếu', _timPhieu),
          _cBtn('Xoá phiếu', selected == null ? null : _xoaPhieu),
          _cBtn('Xem phiếu', selected == null ? null : () => _xemPhieu(selected)),
          _cBtn('In phiếu', selected == null ? null : () => _inNhanh(selected)),
        ],
      ),
    );
  }

  /// Chọn dòng trong bảng: xe chờ cân lần 2 đưa vào ô nhập để chốt, phiếu đã xong đưa vào để sửa.
  void _selectRow(WeighTicket ticket) {
    setState(() => _selectedId = ticket.id);
    if (ticket.status == TicketStatus.choLan2) {
      _selectPending(ticket);
    } else if (ticket.status == TicketStatus.hoanThanh) {
      _selectEdit(ticket);
    }
  }

  Future<void> _timPhieu() async {
    final controller = TextEditingController(text: _searchQuery);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tìm phiếu'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Số phiếu, biển số hoặc tên khách hàng'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Bỏ lọc')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Tìm')),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    setState(() => _searchQuery = value.trim());
    await _loadTable();
  }

  Future<void> _xoaPhieu() async {
    final ticket = _selectedTicket;
    final client = _conn.client;
    if (ticket == null || client == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xoá phiếu ${ticket.ticketNo}?'),
        content: Text('Xe ${ticket.plateNo} — ${ticket.customerName}.\n'
            'Thao tác này không hoàn tác được.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.offline),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá phiếu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await client.deleteTicket(ticket.id);
      if (_pendingTicket?.id == ticket.id) _clearForm();
      setState(() => _selectedId = null);
      await _loadTickets();
      _showMessage('Đã xoá phiếu ${ticket.ticketNo}.');
    } on ApiException catch (e) {
      _showMessage(e.message, isError: true);
    }
  }

  Future<void> _xemPhieu(WeighTicket ticket) async {
    if (await showTicketDetailSheet(context, ticket) && mounted) {
      await _loadTickets();
    }
  }

  /// In ngay bằng máy in mặc định của máy đang chạy app; trên web không in thẳng
  /// được nên mở khung phiếu (có ô chọn máy in) để người dùng bấm in.
  Future<void> _inNhanh(WeighTicket ticket) async {
    if (kIsWeb) {
      await _xemPhieu(ticket);
      return;
    }
    try {
      final may = await Printing.listPrinters();
      final chon = may.where((p) => p.isDefault).firstOrNull ?? may.firstOrNull;
      if (chon == null) {
        _showMessage('Máy này chưa cài máy in nào.', isError: true);
        return;
      }
      final ok = await TicketPrinter.inTrucTiep(ticket, chon.name);
      _showMessage(
        ok
            ? 'Đã gửi phiếu ${ticket.ticketNo} tới máy in: ${chon.name}'
            : 'Không gửi được phiếu tới máy in ${chon.name}',
        isError: !ok,
      );
    } catch (e) {
      _showMessage('Không in được phiếu: $e', isError: true);
    }
  }
}
