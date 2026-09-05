import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thiết lập kết nối của máy/điện thoại đang dùng app.
///
/// Lưu tại thiết bị: mỗi máy ở kho trỏ vào một server khác nhau (máy trong kho
/// trỏ thẳng vào trạm cân của kho đó, máy văn phòng trỏ vào máy chủ trung tâm).
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const _kServerUrl = 'server_url';
  static const _kStationCode = 'station_code';
  static const _kAuthToken = 'auth_token';
  static const _kTrauGiaMua = 'trau_gia_mua';
  static const _kTrauGiaBan = 'trau_gia_ban';
  static const _kTrauTyLe = 'trau_ty_le';

  /// Giá tham chiếu và tỷ lệ mặc định của phần quy đổi trấu thành phẩm.
  static const double trauGiaMuaMacDinh = 1500;
  static const double trauGiaBanMacDinh = 8000;
  static const double trauTyLeMacDinh = 100;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  final SharedPreferences _prefs;

  /// Địa chỉ server đang dùng, ví dụ `http://100.76.81.118:9080`.
  ///
  /// Khi app được chính server phục vụ (mở trình duyệt vào địa chỉ server) thì
  /// để trống, app sẽ tự dùng địa chỉ đang mở — người dùng không phải gõ gì.
  String get serverUrl => _prefs.getString(_kServerUrl) ?? '';

  /// Mã trạm đang theo dõi số cân.
  String get stationCode => _prefs.getString(_kStationCode) ?? '';

  /// Phiếu phiên đăng nhập.
  ///
  /// Giữ lại giữa các lần mở app để nhân viên ở kho không phải đăng nhập mỗi
  /// sáng — phiên có hạn 30 ngày, hết hạn máy chủ tự từ chối.
  String get authToken => _prefs.getString(_kAuthToken) ?? '';

  /// Giá mua tham chiếu của trấu (đ/kg), dùng cho phần quy đổi thành phẩm.
  ///
  /// Lưu tại thiết bị chứ không lên máy chủ: đây là con số để ướm thử lời lỗ,
  /// mỗi người xem có thể muốn ướm một giá khác nhau, và giá thị trường thì đổi
  /// luôn. Số thật đã mua bán vẫn nằm trong sổ.
  double get trauGiaMua => _prefs.getDouble(_kTrauGiaMua) ?? trauGiaMuaMacDinh;

  /// Giá bán tham chiếu của trấu thành phẩm (đ/kg).
  double get trauGiaBan => _prefs.getDouble(_kTrauGiaBan) ?? trauGiaBanMacDinh;

  /// Tỷ lệ thành phẩm của trấu (%): mua thô về, phơi sàng xong còn lại bao nhiêu.
  double get trauTyLe => _prefs.getDouble(_kTrauTyLe) ?? trauTyLeMacDinh;

  Future<void> setTrau({double? giaMua, double? giaBan, double? tyLe}) async {
    if (giaMua != null) await _prefs.setDouble(_kTrauGiaMua, giaMua);
    if (giaBan != null) await _prefs.setDouble(_kTrauGiaBan, giaBan);
    if (tyLe != null) await _prefs.setDouble(_kTrauTyLe, tyLe);
    notifyListeners();
  }

  Future<void> setServerUrl(String value) async {
    await _prefs.setString(_kServerUrl, value.trim());
    // Đổi máy chủ thì phiếu phiên cũ vô dụng: mỗi máy chủ ký bằng khoá riêng.
    await _prefs.remove(_kAuthToken);
    notifyListeners();
  }

  Future<void> setStationCode(String value) async {
    await _prefs.setString(_kStationCode, value.trim().toUpperCase());
    notifyListeners();
  }

  Future<void> setAuthToken(String value) async {
    await _prefs.setString(_kAuthToken, value);
    notifyListeners();
  }

  Future<void> clearAuthToken() async {
    await _prefs.remove(_kAuthToken);
    notifyListeners();
  }
}
