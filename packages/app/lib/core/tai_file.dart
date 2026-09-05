import 'dart:typed_data';

import 'tai_file_khac.dart' if (dart.library.js_interop) 'tai_file_web.dart';

/// Giao một file đã tải về cho người dùng lưu lại.
///
/// Không dùng `url_launcher` để mở thẳng địa chỉ tải: trình duyệt chặn im lặng
/// việc mở cửa sổ khi nó không đến từ một cú bấm trực tiếp, và khi bị chặn thì
/// không báo lỗi gì — bấm nút xong không có phản hồi nào cả.
///
/// Cách này lấy dữ liệu qua chính [ApiClient] (đã có sẵn phiếu phiên trong tiêu
/// đề) rồi mới đưa cho trình duyệt, nên không phụ thuộc vào quyền mở cửa sổ và
/// cũng không phải nhét phiếu phiên vào địa chỉ.
Future<void> luuFile(Uint8List bytes, String tenFile, String kieu) =>
    luuFileTheoNenTang(bytes, tenFile, kieu);
