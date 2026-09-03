import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_settings.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'state/server_connection.dart';
import 'state/live_weight_controller.dart';

class CanXeApp extends StatelessWidget {
  const CanXeApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => ServerConnection(settings)..connect(),
        ),
        ChangeNotifierProvider(create: (_) => LiveWeightController()),
      ],
      child: MaterialApp(
        title: 'Cân xe',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('vi', 'VN'),
        supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _Gate(),
      ),
    );
  }
}

/// Chặn vào màn hình chính khi chưa nối được máy chủ, và nói rõ lý do — người
/// ở kho cần biết là "sai địa chỉ" hay "máy chủ chưa bật", không phải màn hình trắng.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ServerConnection>();

    if (conn.isConnected) return const HomeShell();

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.scale, size: 64, color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'HỆ THỐNG CÂN XE',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 24),
                if (conn.connecting) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Đang kết nối ${conn.baseUrl}...'),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.offline.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.cloud_off, color: AppTheme.offline),
                        const SizedBox(height: 8),
                        Text(
                          conn.error ?? 'Chưa kết nối được máy chủ.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Địa chỉ đang thử: ${conn.baseUrl}',
                          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: conn.connect,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openServerDialog(context),
                          icon: const Icon(Icons.settings_ethernet),
                          label: const Text('Đổi địa chỉ'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openServerDialog(BuildContext context) async {
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
