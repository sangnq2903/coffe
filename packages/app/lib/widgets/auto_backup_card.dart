import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Thẻ **Tự động sao lưu** — chỉ tài khoản chủ thấy.
///
/// Máy chủ tự chụp lại cơ sở dữ liệu mỗi khi có thay đổi, cất vào thư mục người
/// dùng chọn. Không phải bấm nút, không phải nhớ.
class AutoBackupCard extends StatefulWidget {
  const AutoBackupCard({super.key});

  @override
  State<AutoBackupCard> createState() => _AutoBackupCardState();
}

class _AutoBackupCardState extends State<AutoBackupCard> {
  TuDongSaoLuu? _tt;
  bool _dangChay = false;
  String? _loi;

  ApiClient? get _client => context.read<ServerConnection>().client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tai());
  }

  Future<void> _tai() async {
    try {
      final t = await _client?.tuDongSaoLuu();
      if (mounted && t != null) setState(() => _tt = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loi = e.message);
    }
  }

  Future<void> _chay(Future<TuDongSaoLuu?> Function() viec) async {
    if (_dangChay) return;
    setState(() {
      _dangChay = true;
      _loi = null;
    });
    try {
      final t = await viec();
      if (mounted && t != null) setState(() => _tt = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loi = e.message);
    } catch (e) {
      if (mounted) setState(() => _loi = '$e');
    } finally {
      if (mounted) setState(() => _dangChay = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _tt;
    return SectionCard(
      title: 'Tự động sao lưu',
      subtitle: 'Máy chủ tự chụp lại mỗi khi dữ liệu có thay đổi',
      icon: Icons.history_toggle_off,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else ...[
            _dongTrangThai(t),
            if (t.bat) ...[
              const SizedBox(height: AppTheme.gapSm),
              _thongTin(t),
              if (t.file.isNotEmpty) ...[
                const SizedBox(height: AppTheme.gapSm),
                ...t.file.map(_dongFile),
              ],
            ],
            if (t.loi != null) ...[
              const SizedBox(height: AppTheme.gapSm),
              NoticeBar(
                icon: Icons.error_outline,
                color: AppTheme.offline,
                text: 'Lần chụp gần nhất hỏng: ${t.loi}',
              ),
            ],
          ],
          if (_loi != null) ...[
            const SizedBox(height: AppTheme.gapSm),
            NoticeBar(icon: Icons.error_outline, color: AppTheme.offline, text: _loi!),
          ],
          const SizedBox(height: AppTheme.gapMd),
          if (_dangChay)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: t == null ? null : () => _sua(t),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(t?.bat == true ? 'Đổi thiết lập' : 'Bật và chọn thư mục'),
                  ),
                ),
                if (t?.bat == true) ...[
                  const SizedBox(width: AppTheme.gapSm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _chay(() => _client!.chayTuDongSaoLuu()),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Chụp ngay'),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _dongTrangThai(TuDongSaoLuu t) {
    if (!t.bat) {
      return Text(
        'Đang tắt. Bật lên thì mỗi lần lập phiếu, chấm công hay ghi sổ, máy chủ '
        'sẽ tự cất một bản vào thư mục ông chọn.',
        style: AppTheme.meta,
      );
    }
    final (chu, mau) = t.dangChay
        ? ('Đang chụp', AppTheme.primary)
        : t.dangCho
            ? ('Có thay đổi, sắp chụp', AppTheme.accent)
            : ('Đã sao lưu đầy đủ', AppTheme.primary);
    return Row(
      children: [
        StatusPill(label: chu, color: mau),
        const SizedBox(width: AppTheme.gapSm),
        if (t.lanCuoi != null)
          Expanded(
            child: Text('Lần cuối ${formatDateTime(t.lanCuoi)}', style: AppTheme.meta),
          ),
      ],
    );
  }

  Widget _thongTin(TuDongSaoLuu t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(t.thuMuc, style: AppTheme.meta),
          const SizedBox(height: 2),
          Text(
            'Giữ tối đa ${t.giuBan} bản'
            '${t.coMatKhau ? ' • có mã hoá' : ' • không mã hoá'}',
            style: AppTheme.meta,
          ),
        ],
      );

  Widget _dongFile(BanTuDong f) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Expanded(child: Text(f.ten, style: AppTheme.meta)),
            Text('${f.coFile} • ${formatDateTime(f.luc)}', style: AppTheme.meta),
          ],
        ),
      );

  Future<void> _sua(TuDongSaoLuu t) async {
    final kq = await showDialog<_KetQuaSua>(
      context: context,
      builder: (context) => _CaiDatDialog(hienTai: t),
    );
    if (kq == null || !mounted) return;
    await _chay(() => _client!.luuTuDongSaoLuu(
          bat: kq.bat,
          thuMuc: kq.thuMuc,
          giuBan: kq.giuBan,
          matKhau: kq.matKhau,
        ));
  }
}

class _KetQuaSua {
  const _KetQuaSua({
    required this.bat,
    required this.thuMuc,
    required this.giuBan,
    this.matKhau,
  });

  final bool bat;
  final String thuMuc;
  final int giuBan;

  /// `null` = giữ nguyên mật khẩu đang có.
  final String? matKhau;
}

class _CaiDatDialog extends StatefulWidget {
  const _CaiDatDialog({required this.hienTai});

  final TuDongSaoLuu hienTai;

  @override
  State<_CaiDatDialog> createState() => _CaiDatDialogState();
}

class _CaiDatDialogState extends State<_CaiDatDialog> {
  late final _thuMuc = TextEditingController(text: widget.hienTai.thuMuc);
  late final _giuBan = TextEditingController(text: '${widget.hienTai.giuBan}');
  final _matKhau = TextEditingController();

  late bool _bat = widget.hienTai.bat;

  /// Chỉ gửi mật khẩu lên khi người dùng thật sự động vào ô đó.
  bool _doiMatKhau = false;

  @override
  void dispose() {
    for (final o in [_thuMuc, _giuBan, _matKhau]) {
      o.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tự động sao lưu'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _bat,
                  onChanged: (v) => setState(() => _bat = v),
                  title: const Text('Bật tự động sao lưu'),
                ),
                const Divider(height: 20),
                TextField(
                  controller: _thuMuc,
                  enabled: _bat,
                  decoration: const InputDecoration(
                    labelText: 'Thư mục cất bản sao *',
                    hintText: r'D:\SaoLuuCanXe',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đây là thư mục trên MÁY CHẠY MÁY CHỦ, không phải máy ông '
                  'đang ngồi. Chọn một ổ đĩa khác với ổ chứa dữ liệu — cùng một '
                  'ổ mà ổ đó hỏng thì mất cả hai. Ổ ngoài cắm sẵn hay ổ mạng đều '
                  'được, miễn máy chủ ghi vào được.',
                  style: AppTheme.meta,
                ),
                const SizedBox(height: AppTheme.gapMd),
                TextField(
                  controller: _giuBan,
                  enabled: _bat,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Giữ tối đa mấy bản',
                    helperText: 'Quá số này thì bản cũ nhất bị xoá',
                  ),
                ),
                const SizedBox(height: AppTheme.gapMd),
                TextField(
                  controller: _matKhau,
                  enabled: _bat,
                  obscureText: true,
                  onChanged: (_) => _doiMatKhau = true,
                  decoration: InputDecoration(
                    labelText: widget.hienTai.coMatKhau
                        ? 'Mật khẩu mã hoá (đang có — gõ để đổi)'
                        : 'Mật khẩu mã hoá (để trống nếu không cần)',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Đặt mật khẩu thì file không đọc được nếu thiếu nó — đáng làm '
                  'khi thư mục nằm ở USB hay ổ đĩa chung. Quên mật khẩu là mất '
                  'luôn mấy file đó.',
                  style: AppTheme.meta,
                ),
                const SizedBox(height: AppTheme.gapMd),
                NoticeBar(
                  icon: Icons.info_outline,
                  color: AppTheme.textMuted,
                  text: 'Máy chủ không chụp ngay sau từng lần lưu mà gom lại: '
                      'hết khoảng nửa phút không ai ghi gì nữa thì chụp một bản. '
                      'Cả một trận nhập liệu dồn thành một file thay vì hàng trăm.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _KetQuaSua(
                bat: _bat,
                thuMuc: _thuMuc.text.trim(),
                giuBan: int.tryParse(_giuBan.text.trim()) ?? 2,
                matKhau: _doiMatKhau ? _matKhau.text : null,
              ),
            ),
            child: const Text('Lưu'),
          ),
        ],
      );
}
