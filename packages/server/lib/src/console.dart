import 'dart:ffi';
import 'dart:io';

/// Bật chế độ UTF-8 cho cửa sổ lệnh trên Windows.
///
/// Cửa sổ lệnh mặc định dùng bảng mã cũ (437/1258), nên mọi dòng thông báo
/// tiếng Việt của server sẽ hiện thành ký tự rác. Đây chỉ là chuyện hiển thị,
/// nhưng người vận hành ở kho đọc log để biết máy đang chạy đúng hay sai, nên
/// vẫn phải sửa.
void enableUtf8Console() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setConsoleOutputCP = kernel32
        .lookupFunction<Int32 Function(Uint32), int Function(int)>('SetConsoleOutputCP');
    const cpUtf8 = 65001;
    setConsoleOutputCP(cpUtf8);
  } catch (_) {
    // Không đổi được bảng mã thì server vẫn chạy bình thường, chỉ là log khó đọc.
  }
}
