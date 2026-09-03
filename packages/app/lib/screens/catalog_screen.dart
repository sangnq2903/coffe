import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/server_connection.dart';

/// Danh mục dùng chung: khách hàng, xe và loại hàng.
///
/// Sửa ở bất kỳ máy nào cũng được — bản ghi sẽ theo luồng đồng bộ lan sang các
/// kho khác, nên cả hệ thống dùng chung một bộ danh mục.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Khách hàng'),
              Tab(icon: Icon(Icons.local_shipping), text: 'Xe'),
              Tab(icon: Icon(Icons.inventory_2), text: 'Loại hàng'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [_CustomersTab(), _VehiclesTab(), _GoodsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ khách hàng

class _CustomersTab extends StatefulWidget {
  const _CustomersTab();

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  List<Customer> _items = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final items = await client.customers();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Customer? existing]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CustomerDialog(customer: existing),
    );
    if (result == null || !mounted) return;
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    try {
      await client.saveCustomer(Customer.fromJson({
        ...?existing?.toJson(),
        ...result,
        'updated_at': timeToMillis(DateTime.now()),
      }));
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => _CatalogList(
        loading: _loading,
        onAdd: _edit,
        onRefresh: _load,
        addLabel: 'Thêm khách hàng',
        emptyLabel: 'Chưa có khách hàng nào.',
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final c = _items[index];
          return ListTile(
            title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (c.phone != null && c.phone!.isNotEmpty) c.phone!,
              if (c.address != null && c.address!.isNotEmpty) c.address!,
            ].join(' • ')),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _edit(c),
            ),
          );
        },
      );
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer});

  final Customer? customer;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _code = TextEditingController(text: widget.customer?.code ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _address = TextEditingController(text: widget.customer?.address ?? '');
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.customer == null ? 'Thêm khách hàng' : 'Sửa khách hàng'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Tên khách hàng *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Mã khách hàng'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Điện thoại'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Địa chỉ'),
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
                'code': _code.text.trim(),
                'phone': _phone.text.trim(),
                'address': _address.text.trim(),
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

// --------------------------------------------------------------------------- xe

class _VehiclesTab extends StatefulWidget {
  const _VehiclesTab();

  @override
  State<_VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends State<_VehiclesTab> {
  List<Vehicle> _items = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final items = await client.vehicles();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Vehicle? existing]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _VehicleDialog(vehicle: existing),
    );
    if (result == null || !mounted) return;
    final client = context.read<ServerConnection>().client;
    if (client == null) return;
    try {
      await client.saveVehicle(Vehicle.fromJson({
        ...?existing?.toJson(),
        ...result,
        'updated_at': timeToMillis(DateTime.now()),
      }));
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => _CatalogList(
        loading: _loading,
        onAdd: _edit,
        onRefresh: _load,
        addLabel: 'Thêm xe',
        emptyLabel: 'Chưa có xe nào. Xe mới sẽ tự được thêm khi lập phiếu cân.',
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final v = _items[index];
          return ListTile(
            title: Text(v.plateNo, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (v.driverName != null && v.driverName!.isNotEmpty) 'Tài xế: ${v.driverName}',
              if (v.tareWeight != null) 'KL bì: ${formatWeight(v.tareWeight)} kg',
            ].join(' • ')),
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(v)),
          );
        },
      );
}

class _VehicleDialog extends StatefulWidget {
  const _VehicleDialog({this.vehicle});

  final Vehicle? vehicle;

  @override
  State<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends State<_VehicleDialog> {
  late final _plate = TextEditingController(text: widget.vehicle?.plateNo ?? '');
  late final _driver = TextEditingController(text: widget.vehicle?.driverName ?? '');
  late final _phone = TextEditingController(text: widget.vehicle?.driverPhone ?? '');
  late final _tare =
      TextEditingController(text: widget.vehicle?.tareWeight?.toStringAsFixed(0) ?? '');
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.vehicle == null ? 'Thêm xe' : 'Sửa xe'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Biển số xe *'),
                  validator: (v) =>
                      (v == null || v.trim().length < 4) ? 'Nhập biển số' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _driver,
                  decoration: const InputDecoration(labelText: 'Tài xế'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Điện thoại tài xế'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tare,
                  decoration: const InputDecoration(
                    labelText: 'KL bì đăng ký (kg)',
                    helperText: 'Chỉ để đối chiếu, không dùng thay cân lần 2',
                  ),
                  keyboardType: TextInputType.number,
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
                'plate_no': Vehicle.normalizePlate(_plate.text),
                'driver_name': _driver.text.trim(),
                'driver_phone': _phone.text.trim(),
                'tare_weight': parseNumber(_tare.text),
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

// -------------------------------------------------------------------- loại hàng

class _GoodsTab extends StatefulWidget {
  const _GoodsTab();

  @override
  State<_GoodsTab> createState() => _GoodsTabState();
}

class _GoodsTabState extends State<_GoodsTab> {
  Future<void> _edit([GoodsType? existing]) async {
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _GoodsDialog(goods: existing),
    );
    if (result == null || !mounted) return;
    final conn = context.read<ServerConnection>();
    final client = conn.client;
    if (client == null) return;
    try {
      await client.saveGoodsType(GoodsType.fromJson({
        ...?existing?.toJson(),
        ...result,
        'updated_at': timeToMillis(DateTime.now()),
      }));
      await conn.refreshCatalogs();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    final items = conn.goodsTypes;
    return _CatalogList(
      loading: false,
      onAdd: _edit,
      onRefresh: conn.refreshCatalogs,
      addLabel: 'Thêm loại hàng',
      emptyLabel: 'Chưa có loại hàng nào.',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final g = items[index];
        return ListTile(
          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            'Mã ${g.code} • Tỷ lệ thành phẩm mặc định ${formatPercent(g.defaultYieldRatio)}',
          ),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _edit(g)),
        );
      },
    );
  }
}

class _GoodsDialog extends StatefulWidget {
  const _GoodsDialog({this.goods});

  final GoodsType? goods;

  @override
  State<_GoodsDialog> createState() => _GoodsDialogState();
}

class _GoodsDialogState extends State<_GoodsDialog> {
  late final _name = TextEditingController(text: widget.goods?.name ?? '');
  late final _code = TextEditingController(text: widget.goods?.code ?? '');
  late final _ratio = TextEditingController(
      text: formatDecimal(widget.goods?.defaultYieldRatio ?? 100));
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.goods == null ? 'Thêm loại hàng' : 'Sửa loại hàng'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Tên loại hàng *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Mã'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ratio,
                  decoration: const InputDecoration(
                    labelText: 'Tỷ lệ thành phẩm mặc định (%) *',
                    suffixText: '%',
                    helperText: 'Điền sẵn khi lập phiếu, vẫn sửa được từng phiếu',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final value = parseNumber(v);
                    if (value == null) return 'Nhập tỷ lệ';
                    if (value < 0 || value > 100) return '0 – 100';
                    return null;
                  },
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
                'code': _code.text.trim().isEmpty
                    ? _name.text.trim().toUpperCase()
                    : _code.text.trim().toUpperCase(),
                'default_yield_ratio': parseNumber(_ratio.text) ?? 100,
              });
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

// ----------------------------------------------------------------------- chung

class _CatalogList extends StatelessWidget {
  const _CatalogList({
    required this.loading,
    required this.onAdd,
    required this.onRefresh,
    required this.addLabel,
    required this.emptyLabel,
    required this.itemCount,
    required this.itemBuilder,
  });

  final bool loading;
  final VoidCallback onAdd;
  final Future<void> Function() onRefresh;
  final String addLabel;
  final String emptyLabel;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: Text(addLabel),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Làm mới',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
              ],
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: itemCount == 0
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(emptyLabel, textAlign: TextAlign.center),
                    ),
                  )
                : ListView.separated(
                    itemCount: itemCount,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: itemBuilder,
                  ),
          ),
        ],
      );
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
