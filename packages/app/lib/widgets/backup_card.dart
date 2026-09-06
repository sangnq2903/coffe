import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/chon_file.dart';
import '../core/formatters.dart';
import '../core/tai_file.dart';
import '../core/theme.dart';
import '../state/server_connection.dart';

/// Thẻ **Sao lưu dữ liệu** trong màn hình Cá nhân — chỉ tài khoản chủ thấy.
///
/// File xuất ra là toàn bộ cơ sở dữ liệu: lương từng người, sổ mua bán, giá
/// vốn, và cả chuỗi băm mật khẩu của mọi tài khoản. Quyền tải nó phải bằng
/// quyền xem thứ nặng nhất bên trong, chứ không phải quyền của người quản lý
/// một kho. Máy chủ chặn lại một lần nữa, đây chỉ là lớp ngoài.
class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  DuLieuTomTat? _tomTat;
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
      final t = await _client?.duLieuTomTat();
      if (mounted && t != null) setState(() => _tomTat = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loi = e.message);
    }
  }

  /// Chạy một việc dài, khoá nút và hiện lỗi nếu có.
  Future<void> _chay(Future<void> Function() viec) async {
    if (_dangChay) return;
    setState(() {
      _dangChay = true;
      _loi = null;
    });
    try {
      await viec();
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
    final t = _tomTat;
    return SectionCard(
      title: 'Sao lưu dữ liệu',
      subtitle: 'Tải toàn bộ dữ liệu về máy, hoặc nạp lại từ file đã lưu',
      icon: Icons.inventory_2_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t != null) _bangSoLieu(t),
          if (_loi != null) ...[
            const SizedBox(height: AppTheme.gapSm),
            NoticeBar(
              icon: Icons.error_outline,
              text: _loi!,
              color: AppTheme.offline,
            ),
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
                  child: FilledButton.icon(
                    onPressed: _xuat,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Xuất ra file'),
                  ),
                ),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _nhap,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: const Text('Nhập từ file'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppTheme.gapSm),
          Text(
            'Nên xuất mỗi tuần một bản và cất ở máy khác — ổ cứng hỏng thì '
            'bản nằm cùng máy cũng mất theo.',
            style: AppTheme.meta,
          ),
        ],
      ),
    );
  }

  Widget _bangSoLieu(DuLieuTomTat t) {
    final bang = t.bangCoDuLieu.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Tổng bản ghi',
                value: formatInt(t.tongDong),
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(child: StatTile(label: 'Cỡ dữ liệu', value: t.coFile)),
          ],
        ),
        if (bang.isNotEmpty) ...[
          const SizedBox(height: AppTheme.gapSm),
          Wrap(
            spacing: AppTheme.gapSm,
            runSpacing: 4,
            children: [
              for (final e in bang)
                Text('${e.key}: ${formatInt(e.value)}',
                    style: AppTheme.meta),
            ],
          ),
        ],
      ],
    );
  }

  // ====================================================================== xuất

  Future<void> _xuat() async {
    final matKhau = await _hoiMatKhauXuat();
    if (matKhau == null || !mounted) return;

    await _chay(() async {
      final kq = await _client!.xuatDuLieu(matKhau: matKhau);
      await luuFile(kq.bytes, kq.tenFile, 'application/octet-stream');
      if (mounted) _bao('Đã tải về ${kq.tenFile}');
    });
  }

  /// Hỏi có đặt mật khẩu cho file không.
  ///
  /// Trả `null` khi bấm huỷ, chuỗi rỗng nghĩa là không mã hoá. Cố ý hỏi mỗi
  /// lần thay vì nhớ sẵn một mật khẩu: file này hay được chép sang USB rồi cất
  /// đâu đó vài năm, mà mật khẩu nhớ hộ trong máy thì mất máy là mất luôn.
  Future<String?> _hoiMatKhauXuat() {
    final o = TextEditingController();
    var che = true;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Xuất dữ liệu'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Đặt mật khẩu thì file được mã hoá, ai lấy được cũng không đọc '
                  'nổi. Trong file có lương từng người và sổ mua bán, nên nếu '
                  'định cất ở USB hay gửi qua mạng thì nên đặt.\n\n'
                  'Để trống thì ra file mở được bằng mọi công cụ xem SQLite.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: AppTheme.gapMd),
                TextField(
                  controller: o,
                  autofocus: true,
                  obscureText: che,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu (để trống nếu không cần)',
                    suffixIcon: IconButton(
                      icon: Icon(che ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setLocal(() => che = !che),
                    ),
                  ),
                  onSubmitted: (v) => Navigator.pop(context, v),
                ),
                const SizedBox(height: AppTheme.gapSm),
                Text(
                  'Quên mật khẩu là mất luôn file — không có cách nào mở lại. '
                  'Ghi ra giấy, cất khác chỗ với file.',
                  style: AppTheme.meta.copyWith(color: AppTheme.accent),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () => Navigator.pop(context, o.text),
              child: const Text('Xuất'),
            ),
          ],
        ),
      ),
    );
  }

  // ====================================================================== nhập

  Future<void> _nhap() async {
    final FileDaChon? file;
    try {
      file = await chonFile(duoi: '.db,.canxe');
    } on UnsupportedError catch (e) {
      if (mounted) setState(() => _loi = e.message?.toString());
      return;
    }
    if (file == null || !mounted) return;

    // Đọc thử trước rồi mới hỏi, để hộp xác nhận nói được file có bao nhiêu
    // phiếu cân, của ngày nào. Hỏi "có chắc không" mà không cho biết đang nhập
    // cái gì thì người dùng chỉ có nước bấm liều.
    String? matKhau;
    DuLieuTomTat? xem;
    while (xem == null) {
      try {
        xem = await _client!.xemTruocDuLieu(file.bytes, matKhau: matKhau);
      } on ApiException catch (e) {
        if (!e.message.contains('mật khẩu') || !mounted) {
          if (mounted) setState(() => _loi = e.message);
          return;
        }
        matKhau = await _hoiMatKhauNhap(e.message);
        if (matKhau == null || !mounted) return;
      }
    }

    if (!mounted || !await _xacNhanNhap(file.ten, xem)) return;

    final mk = matKhau;
    await _chay(() async {
      final kq = await _client!.nhapDuLieu(file!.bytes, matKhau: mk);
      await _tai();
      if (mounted) await _khoeKetQua(kq);
    });
  }

  Future<String?> _hoiMatKhauNhap(String vinhSao) {
    final o = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File có mã hoá'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(vinhSao, style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: AppTheme.gapMd),
              TextField(
                controller: o,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu của file'),
                onSubmitted: (v) =>
                    v.isEmpty ? null : Navigator.pop(context, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () =>
                o.text.isEmpty ? null : Navigator.pop(context, o.text),
            child: const Text('Mở file'),
          ),
        ],
      ),
    );
  }

  Future<bool> _xacNhanNhap(String tenFile, DuLieuTomTat xem) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nhập dữ liệu từ file này?'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tenFile,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '${formatInt(xem.tongDong)} bản ghi • ${xem.coFile}'
                  '${xem.moiNhat == null ? '' : ' • mới nhất ${formatDateTime(xem.moiNhat!)}'}',
                  style: AppTheme.meta,
                ),
                const SizedBox(height: AppTheme.gapMd),
                Wrap(
                  spacing: AppTheme.gapSm,
                  runSpacing: 4,
                  children: [
                    for (final e in xem.bangCoDuLieu.entries)
                      Text('${e.key}: ${formatInt(e.value)}',
                          style: AppTheme.meta),
                  ],
                ),
                const SizedBox(height: AppTheme.gapMd),
                const Text(
                  'Dữ liệu trong file sẽ được GỘP vào dữ liệu đang có, không xoá '
                  'gì cả. Bản ghi nào trên máy mới hơn thì máy giữ nguyên, nên '
                  'nhập nhầm một bản cũ không làm mất việc làm hôm nay.\n\n'
                  'Máy chủ tự cất một bản chụp trước khi gộp.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Huỷ')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Nhập vào'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _khoeKetQua(KetQuaNhapDuLieu kq) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(kq.tongThemMoi > 0 ? 'Đã nhập xong' : 'Không có gì mới'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kq.tongThemMoi > 0) ...[
                  Text('Thêm ${formatInt(kq.tongThemMoi)} bản ghi:',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  for (final e in kq.themMoi.entries)
                    Text('  • ${e.key}: +${formatInt(e.value)}'),
                ] else
                  const Text(
                    'Mọi bản ghi trong file đều đã có sẵn trên máy, hoặc bản '
                    'trên máy mới hơn. Không phải lỗi — dữ liệu vẫn nguyên vẹn.',
                    style: TextStyle(fontSize: 13, height: 1.45),
                  ),
                if (kq.duongDanAnToan.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.gapMd),
                  Text('Bản chụp trước khi gộp đã cất ở:', style: AppTheme.meta),
                  SelectableText(kq.duongDanAnToan, style: AppTheme.meta),
                ],
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Xong')),
          ],
        ),
      );

  void _bao(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));
}
