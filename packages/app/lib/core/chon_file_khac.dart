import 'dart:typed_data';

/// Chọn file trên máy tính để bàn và điện thoại.
///
/// Chưa làm, và cố ý báo lỗi rõ ràng thay vì trả về `null` lặng lẽ — trả `null`
/// thì màn hình sẽ trông y như người dùng vừa bấm huỷ, và họ sẽ ngồi bấm lại
/// mãi mà không hiểu vì sao không có gì xảy ra.
///
/// Ở kho mọi người vào phần mềm bằng trình duyệt qua địa chỉ Tailscale, nên
/// đường này gần như không ai đi. Khi nào cần thì thêm gói `file_selector`.
Future<({Uint8List bytes, String ten})?> chonFileTheoNenTang(String duoi) =>
    throw UnsupportedError(
      'Bản chạy trực tiếp trên máy chưa chọn được file. '
      'Hãy mở phần mềm bằng trình duyệt rồi nhập dữ liệu ở đó.',
    );
