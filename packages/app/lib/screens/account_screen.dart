import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/server_connection.dart';

/// Màn hình *Cá nhân*: thông tin tài khoản, đổi mật khẩu, đăng xuất, và phần
/// quản lý tài khoản dành riêng cho quản lý tổng.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<AppUser> _users = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    final conn = context.read<ServerConnection>();
    if (conn.currentUser?.isAdmin != true) return;
    setState(() => _loading = true);
    try {
      final list = await conn.client!.users();
      if (mounted) setState(() => _users = list);
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();
    final user = conn.currentUser;
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      children: [
        _profileCard(user, conn),
        const SizedBox(height: AppTheme.gapMd),
        SectionCard(
          title: 'Bảo mật',
          icon: Icons.lock_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _changePassword,
                icon: const Icon(Icons.key),
                label: const Text('Đổi mật khẩu'),
              ),
              const SizedBox(height: AppTheme.gapSm),
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(conn),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.offline),
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
        if (user.isAdmin) ...[
          const SizedBox(height: AppTheme.gapMd),
          _usersCard(),
        ],
      ],
    );
  }

  Widget _profileCard(AppUser user, ServerConnection conn) => SectionCard(
        title: 'Tài khoản đang dùng',
        icon: Icons.person,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
                  child: Text(
                    _initials(user.displayName),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      Text('@${user.username}',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                StatusPill(
                  label: user.role.label,
                  color: user.isAdmin ? AppTheme.primary : AppTheme.unstable,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.gapMd),
            _row('Phạm vi kho',
                user.seesAllStations ? 'Toàn bộ kho' : user.stationScope.join(', ')),
            _row('Máy chủ', '${conn.baseUrl}'),
            _row('Vai trò máy chủ',
                conn.serverInfo?.isCentral == true ? 'Trung tâm' : 'Trạm cân'),
          ],
        ),
      );

  Widget _usersCard() => SectionCard(
        title: 'Quản lý tài khoản',
        icon: Icons.group,
        padded: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Làm mới',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadUsers,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _createUser,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm'),
              ),
            ),
          ],
        ),
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_users.isEmpty && !_loading)
              const EmptyHint(icon: Icons.group_outlined, message: 'Chưa có tài khoản nào khác.')
            else
              ...List.generate(_users.length, (i) => _userTile(_users[i], i)),
          ],
        ),
      );

  Widget _userTile(AppUser user, int index) {
    final me = context.read<ServerConnection>().currentUser;
    final isMe = me?.id == user.id;
    return Column(
      children: [
        if (index > 0) const Divider(height: 1),
        ListTile(
          leading: CircleAvatar(
            backgroundColor: (user.isAdmin ? AppTheme.primary : AppTheme.unstable)
                .withValues(alpha: 0.14),
            child: Text(
              _initials(user.displayName),
              style: TextStyle(
                color: user.isAdmin ? AppTheme.primary : AppTheme.unstable,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          title: Row(
            children: [
              Flexible(child: Text(user.displayName)),
              if (isMe)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('(bạn)',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
            ],
          ),
          subtitle: Text(
            '@${user.username} • ${user.role.label}'
            '${user.seesAllStations ? '' : ' • ${user.stationScope.join(", ")}'}',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'mat-khau' => _resetPassword(user),
              'xoa' => _deleteUser(user),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'mat-khau', child: Text('Đặt lại mật khẩu')),
              if (!isMe)
                const PopupMenuItem(
                  value: 'xoa',
                  child: Text('Xoá tài khoản', style: TextStyle(color: AppTheme.offline)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(label,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ],
        ),
      );

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[parts.length - 2].substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  // ------------------------------------------------------------- thao tác

  Future<void> _confirmLogout(ServerConnection conn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
          'Lần sau mở lại sẽ phải nhập tên đăng nhập và mật khẩu. '
          'Máy ở bàn cân nên giữ đăng nhập để không phải gõ lại mỗi ca.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.offline),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok == true) await conn.logout();
  }

  Future<void> _changePassword() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<ServerConnection>().client!.changePassword(result.$1, result.$2);
      _snack('Đã đổi mật khẩu.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _resetPassword(AppUser user) async {
    final password = await _askPassword('Đặt lại mật khẩu cho ${user.displayName}');
    if (password == null || !mounted) return;
    try {
      await context.read<ServerConnection>().client!.resetPassword(user.id, password);
      _snack('Đã đặt lại mật khẩu cho ${user.displayName}.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá tài khoản ${user.displayName}?'),
        content: const Text(
          'Người này sẽ không đăng nhập được nữa. Phiếu cân họ đã lập vẫn giữ nguyên.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
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
      await context.read<ServerConnection>().client!.deleteUser(user.id);
      await _loadUsers();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<String?> _askPassword(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Mật khẩu mới',
            helperText: 'Từ 6 ký tự trở lên',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser() async {
    final conn = context.read<ServerConnection>();
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _NewUserDialog(stations: conn.stations),
    );
    if (result == null || !mounted) return;
    try {
      await conn.client!.createUser(
        username: result['username'] as String,
        fullName: result['full_name'] as String,
        password: result['password'] as String,
        role: result['role'] as UserRole,
        stationScope: (result['scope'] as List).cast<String>(),
      );
      await _loadUsers();
      _snack('Đã tạo tài khoản.');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _old,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Nhập mật khẩu hiện tại' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _new,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
                  validator: (v) => (v == null || v.length < 6) ? 'Từ 6 ký tự trở lên' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
                  validator: (v) => v != _new.text ? 'Hai lần nhập chưa khớp' : null,
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
              Navigator.pop(context, (_old.text, _new.text));
            },
            child: const Text('Đổi'),
          ),
        ],
      );
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog({required this.stations});

  final List<Station> stations;

  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();

  UserRole _role = UserRole.tram;
  final Set<String> _scope = {};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Thêm tài khoản'),
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
                    controller: _username,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập *',
                      helperText: 'Chữ thường, số và các ký tự . _ -',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().length < 3) ? 'Từ 3 ký tự trở lên' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(labelText: 'Họ tên *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Mật khẩu *'),
                    validator: (v) => (v == null || v.length < 6) ? 'Từ 6 ký tự' : null,
                  ),
                  const SizedBox(height: AppTheme.gapMd),
                  const Text('QUYỀN', style: AppTheme.sectionLabel),
                  const SizedBox(height: AppTheme.gapSm),
                  SegmentedButton<UserRole>(
                    segments: UserRole.values
                        .map((r) => ButtonSegment(value: r, label: Text(r.label)))
                        .toList(),
                    selected: {_role},
                    onSelectionChanged: (v) => setState(() => _role = v.first),
                  ),
                  if (_role == UserRole.tram) ...[
                    const SizedBox(height: AppTheme.gapMd),
                    const Text('CHỌN KHO ĐƯỢC XEM', style: AppTheme.sectionLabel),
                    const SizedBox(height: AppTheme.gapSm),
                    if (widget.stations.isEmpty)
                      const Text(
                        'Chưa có kho nào. Bật máy trạm lên rồi quay lại.',
                        style: TextStyle(color: AppTheme.offline, fontSize: 13),
                      )
                    else
                      ...widget.stations.map((s) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _scope.contains(s.code),
                            title: Text('${s.name} (${s.code})'),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _scope.add(s.code);
                              } else {
                                _scope.remove(s.code);
                              }
                            }),
                          )),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              if (_role == UserRole.tram && _scope.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chọn ít nhất một kho cho tài khoản trạm.')),
                );
                return;
              }
              Navigator.pop(context, {
                'username': _username.text.trim(),
                'full_name': _fullName.text.trim(),
                'password': _password.text,
                'role': _role,
                'scope': _scope.toList(),
              });
            },
            child: const Text('Tạo'),
          ),
        ],
      );
}
