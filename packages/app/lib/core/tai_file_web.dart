import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Đưa file cho trình duyệt tải về, bằng cách dựng một liên kết tạm rồi bấm nó.
///
/// Đây là cách tải file duy nhất chắc chắn chạy trên web: dữ liệu đã nằm sẵn
/// trong bộ nhớ trang nên không cần gọi mạng lần nữa, không cần quyền mở cửa
/// sổ, và không phải đính phiếu phiên vào địa chỉ.
Future<void> luuFileTheoNenTang(
  Uint8List bytes, String tenFile, String kieu) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: kieu),
  );
  final url = web.URL.createObjectURL(blob);

  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = tenFile
    ..style.display = 'none';
  web.document.body!.appendChild(a);
  a.click();
  a.remove();

  // Trả lại bộ nhớ, nhưng chờ một nhịp: thu hồi ngay lúc vừa bấm thì có trình
  // duyệt chưa kịp bắt đầu tải, và file hỏng mà không báo lỗi gì.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
