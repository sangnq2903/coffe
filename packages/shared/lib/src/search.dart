/// Bảng quy các nguyên âm có dấu về nguyên âm trần, dùng cho việc tìm kiếm.
const Map<String, String> _khongDau = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

/// Đưa chuỗi về dạng để so khi tìm kiếm: chữ thường, bỏ dấu, gộp khoảng trắng.
///
/// Người dùng gõ nhanh trên bàn phím thường không bật bộ gõ tiếng Việt, nên
/// "tinh" phải tìm ra "Tình" và "ca nhan" phải tìm ra "Cà nhân" — không bỏ dấu
/// thì tìm theo tên gần như vô dụng.
///
/// Nằm ở gói dùng chung vì cả hai bên đều cần: máy chủ lọc bằng câu truy vấn
/// SQL, còn giao diện lọc tại chỗ. Hai bên dùng hai luật khác nhau thì gõ cùng
/// một chữ lại ra hai kết quả.
String normalizeForSearch(String? raw) {
  if (raw == null) return '';
  final buffer = StringBuffer();
  for (final ch in raw.toLowerCase().trim().split('')) {
    var plain = ch;
    for (final entry in _khongDau.entries) {
      if (entry.value.contains(ch)) {
        plain = entry.key;
        break;
      }
    }
    buffer.write(plain);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}
