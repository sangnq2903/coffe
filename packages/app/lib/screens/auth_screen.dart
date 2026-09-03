import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Màn hình đăng nhập, và màn hình tạo tài khoản quản lý tổng khi hệ thống còn
/// trắng — dùng chung một khung cho nhất quán.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.setupMode});

  /// `true` khi hệ thống chưa có tài khoản nào.
  final bool setupMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final conn = context.read<ServerConnection>();
    try {
      if (widget.setupMode) {
        await conn.setupFirstAdmin(
          username: _username.text,
          fullName: _fullName.text,
          password: _password.text,
        );
      } else {
        await conn.login(_username.text, _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(),
                const SizedBox(height: AppTheme.gapLg),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(color: AppTheme.line),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.setupMode) ...[
                          _hint(),
                          const SizedBox(height: AppTheme.gapMd),
                        ],
                        TextFormField(
                          controller: _username,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Tên đăng nhập',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().length < 3)
                              ? 'Tên đăng nhập phải từ 3 ký tự'
                              : null,
                        ),
                        if (widget.setupMode) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _fullName,
                            decoration: const InputDecoration(
                              labelText: 'Họ tên',
                              prefixIcon: Icon(Icons.badge_outlined),
                              helperText: 'Tên này sẽ hiện ở ô "người lập" trên phiếu cân',
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Nhập họ tên' : null,
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _hidePassword ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () =>
                                  setState(() => _hidePassword = !_hidePassword),
                            ),
                          ),
                          textInputAction:
                              widget.setupMode ? TextInputAction.next : TextInputAction.done,
                          onFieldSubmitted: (_) => widget.setupMode ? null : _submit(),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Mật khẩu phải từ 6 ký tự'
                              : null,
                        ),
                        if (widget.setupMode) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirm,
                            obscureText: _hidePassword,
                            decoration: const InputDecoration(
                              labelText: 'Nhập lại mật khẩu',
                              prefixIcon: Icon(Icons.lock_reset),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (v) =>
                                v != _password.text ? 'Hai lần nhập chưa khớp' : null,
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppTheme.gapMd),
                          _errorBox(_error!),
                        ],
                        const SizedBox(height: AppTheme.gapLg),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                          icon: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(widget.setupMode ? Icons.person_add : Icons.login),
                          label: Text(
                            widget.setupMode ? 'TẠO TÀI KHOẢN' : 'ĐĂNG NHẬP',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.gapMd),
                _serverLine(conn),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.scale, size: 40, color: Colors.white),
          ),
          const SizedBox(height: AppTheme.gapMd),
          Text(
            'HỆ THỐNG CÂN XE',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
          const SizedBox(height: 4),
          Text(
            widget.setupMode ? 'Thiết lập lần đầu' : 'Đăng nhập để tiếp tục',
            style: const TextStyle(color: AppTheme.textMuted),
          ),
        ],
      );

  Widget _hint() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 19, color: AppTheme.primary),
            SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Text(
                'Hệ thống chưa có tài khoản nào. Tài khoản đầu tiên là quản lý tổng, '
                'thấy được dữ liệu của mọi kho và tạo được tài khoản cho người khác.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.offline.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.offline.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.offline, size: 20),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );

  Widget _serverLine(ServerConnection conn) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.dns, size: 15, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${conn.baseUrl}',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _changeServer(context),
            child: const Text('Đổi'),
          ),
        ],
      );

  Future<void> _changeServer(BuildContext context) async {
    final settings = context.read<AppSettings>();
    final conn = context.read<ServerConnection>();
    final controller = TextEditingController(text: settings.serverUrl);

    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Địa chỉ máy chủ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'http://100.76.81.118:9080',
            helperText: 'Địa chỉ Tailscale của máy chủ trung tâm hoặc của trạm cân',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Kết nối'),
          ),
        ],
      ),
    );
    if (url == null) return;
    await settings.setServerUrl(url);
    await conn.connect();
  }
}
