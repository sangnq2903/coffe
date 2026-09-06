import 'dart:typed_data';

import 'chon_file_khac.dart' if (dart.library.js_interop) 'chon_file_web.dart';

/// Một file người dùng vừa chọn từ máy của họ.
typedef FileDaChon = ({Uint8List bytes, String ten});

/// Mở hộp chọn file của hệ điều hành. `null` nghĩa là người dùng bấm huỷ.
///
/// [duoi] là gợi ý cho hộp thoại lọc bớt, ví dụ `'.db,.canxe'`. Chỉ là gợi ý —
/// người dùng vẫn chọn được file khác, nên phía máy chủ vẫn phải tự kiểm.
Future<FileDaChon?> chonFile({String duoi = ''}) => chonFileTheoNenTang(duoi);
