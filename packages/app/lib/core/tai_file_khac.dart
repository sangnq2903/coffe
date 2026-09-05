import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// Lưu file rồi mở bảng chia sẻ của hệ điều hành (Windows, Android, iOS).
///
/// Trên máy tính để bàn và điện thoại không có khái niệm "thư mục Tải về của
/// trình duyệt", nên ghi ra thư mục tạm rồi để người dùng chọn gửi đi đâu —
/// gửi thẳng cho kế toán qua Zalo hay email cũng từ đây.
Future<void> luuFileTheoNenTang(
    Uint8List bytes, String tenFile, String kieu) async {
  final thuMuc = await getTemporaryDirectory();
  final duongDan = '${thuMuc.path}${Platform.pathSeparator}$tenFile';
  await File(duongDan).writeAsBytes(bytes, flush: true);
  await Printing.sharePdf(bytes: bytes, filename: tenFile);
}
