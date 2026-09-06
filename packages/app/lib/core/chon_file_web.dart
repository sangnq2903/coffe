import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Mở hộp chọn file của trình duyệt và đọc file ra bộ nhớ.
///
/// Trả `null` khi người dùng bấm huỷ. Bắt cho được cú huỷ là phần khó: trình
/// duyệt **không** báo gì khi đóng hộp thoại mà không chọn file, nên nếu chỉ
/// chờ sự kiện `change` thì bấm huỷ xong màn hình đứng nguyên ở vòng quay chờ,
/// không có cách nào thoát ngoài tải lại trang.
///
/// Nên ở đây bắt cả ba đường: `change` (đã chọn), `cancel` (trình duyệt mới có
/// báo), và cửa sổ được focus trở lại mà vẫn chưa thấy `change` (đường lui cho
/// trình duyệt cũ).
Future<({Uint8List bytes, String ten})?> chonFileTheoNenTang(String duoi) async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = duoi
    ..style.display = 'none';
  web.document.body!.appendChild(input);

  final xong = Completer<({Uint8List bytes, String ten})?>();
  void tra(({Uint8List bytes, String ten})? kq) {
    if (!xong.isCompleted) xong.complete(kq);
  }

  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      tra(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final buf = reader.result as JSArrayBuffer?;
      tra(buf == null
          ? null
          : (bytes: buf.toDart.asUint8List(), ten: file.name));
    }).toJS;
    reader.onerror = ((web.Event _) => tra(null)).toJS;
    reader.readAsArrayBuffer(file);
  }).toJS;

  input.oncancel = ((web.Event _) => tra(null)).toJS;

  // Đường lui: cửa sổ sáng lại tức là hộp thoại đã đóng. Chờ một nhịp rồi mới
  // kết luận là huỷ, vì `change` bắn ra ngay sau `focus` chứ không trước.
  void khiFocus(web.Event _) {
    Timer(const Duration(milliseconds: 800), () {
      if (input.files == null || input.files!.length == 0) tra(null);
    });
  }

  final focus = khiFocus.toJS;
  web.window.addEventListener('focus', focus);

  input.click();
  try {
    return await xong.future;
  } finally {
    web.window.removeEventListener('focus', focus);
    input.remove();
  }
}
