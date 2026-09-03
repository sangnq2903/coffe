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
