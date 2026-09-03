import 'package:intl/intl.dart';

/// Định dạng số và ngày giờ theo cách người dùng Việt Nam quen đọc.

final NumberFormat _weightFormat = NumberFormat('#,##0', 'vi_VN');
final NumberFormat _decimalFormat = NumberFormat('#,##0.##', 'vi_VN');
final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');
final DateFormat _timeFormat = DateFormat('HH:mm:ss', 'vi_VN');
final DateFormat _dateFormat = DateFormat('dd/MM/yyyy', 'vi_VN');

/// Khối lượng luôn hiển thị làm tròn tới kg: đầu cân chia vạch 10–20 kg nên
/// phần thập phân chỉ gây rối cho người đọc.
String formatWeight(double? value) =>
    value == null ? '—' : _weightFormat.format(value.roundToDouble());

String formatDecimal(double? value) =>
    value == null ? '—' : _decimalFormat.format(value);

/// Tiền luôn làm tròn tới đồng và không kèm đơn vị, để chỗ gọi tự ghép `đ`.
///
/// Lương chia theo ngày ra số lẻ vô hạn; hiện phần thập phân của đồng thì
/// không ai đọc mà chỉ làm người ta nghi số sai.
String formatMoney(double? value) =>
    value == null ? '—' : _weightFormat.format(value.roundToDouble());

String formatPercent(double? value) =>
    value == null ? '—' : '${_decimalFormat.format(value)}%';

String formatDateTime(DateTime? value) =>
    value == null ? '—' : _dateTimeFormat.format(value);

String formatTime(DateTime? value) =>
    value == null ? '—' : _timeFormat.format(value);

String formatDate(DateTime? value) =>
    value == null ? '—' : _dateFormat.format(value);

/// Bảng quy các nguyên âm có dấu về nguyên âm trần, dùng cho việc tìm tên.
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
/// "tinh" phải tìm ra "Tình" — không bỏ dấu thì tìm tên gần như vô dụng.
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

/// Đọc số người dùng gõ vào, chấp nhận cả kiểu Việt Nam (`12.345,6`) lẫn kiểu
/// Anh Mỹ (`12,345.6`) và cả khi không có dấu phân cách nào.
///
/// Quy tắc: dấu phân cách cuối cùng có đúng 3 chữ số đứng sau thì đó là dấu
/// hàng nghìn (`1.234` = 1234), ngược lại là dấu thập phân (`12,5` = 12,5).
double? parseNumber(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;

  final lastSeparator = [s.lastIndexOf('.'), s.lastIndexOf(',')]
      .reduce((a, b) => a > b ? a : b);
  if (lastSeparator < 0) return double.tryParse(s);

  final digitsAfter = s.length - lastSeparator - 1;
  if (digitsAfter == 3) {
    return double.tryParse(s.replaceAll(RegExp(r'[.,]'), ''));
  }
  final integerPart = s.substring(0, lastSeparator).replaceAll(RegExp(r'[.,]'), '');
  return double.tryParse('$integerPart.${s.substring(lastSeparator + 1)}');
}
