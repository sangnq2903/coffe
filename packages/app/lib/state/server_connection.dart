import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart';

import '../core/app_settings.dart';

/// Quản lý kết nối tới server, phiên đăng nhập và danh mục dùng chung.
class ServerConnection extends ChangeNotifier {
  ServerConnection(this.settings) {
    settings.addListener(_onSettingsChanged);
  }

  final AppSettings settings;

  ApiClient? _client;
  ServerInfo? _serverInfo;
  AppUser? _currentUser;
  bool _needsSetup = false;
  List<Station> _stations = const [];
  List<GoodsType> _goodsTypes = const [];
  String? _error;
  bool _connecting = false;

  ApiClient? get client => _client;

  ServerInfo? get serverInfo => _serverInfo;

  /// Tài khoản đang đăng nhập; `null` nghĩa là phải qua màn hình đăng nhập.
  AppUser? get currentUser => _currentUser;

  /// Hệ thống chưa có tài khoản nào — hiện màn hình tạo tài khoản quản lý tổng.
  bool get needsSetup => _needsSetup;

  List<Station> get stations => _stations;

  List<GoodsType> get goodsTypes => _goodsTypes;

  String? get error => _error;

  bool get connecting => _connecting;

  /// Đã nói chuyện được với máy chủ hay chưa (chưa xét đăng nhập).
  bool get isConnected => _serverInfo != null;

  bool get isSignedIn => _currentUser != null;

  /// Trạm đang được chọn để theo dõi số cân và lập phiếu.
  String get stationCode {
    if (settings.stationCode.isNotEmpty) return settings.stationCode;
    final withScale = _stations.where((s) => s.hasScale).firstOrNull;
    return withScale?.code ?? _serverInfo?.stationCode ?? '';
  }

  Station? get station => _stations.where((s) => s.code == stationCode).firstOrNull;

  /// Địa chỉ server đang dùng.
  Uri get baseUrl {
    final configured = settings.serverUrl.trim();
    if (configured.isNotEmpty) {
      final withScheme = configured.startsWith('http') ? configured : 'http://$configured';
      return Uri.parse(withScheme);
    }
    if (kIsWeb) {
      // Chỉ lấy đúng scheme + host + cổng. Dùng replace(query: '', fragment: '')
      // sẽ tạo ra địa chỉ kết thúc bằng "?#", và trình duyệt từ chối mọi URL
      // WebSocket có dấu "#".
      final base = Uri.base;
      return Uri(
        scheme: base.scheme,
        host: base.host,
        port: base.hasPort ? base.port : null,
      );
    }
    return Uri.parse('http://127.0.0.1:9080');
  }

  /// Nối tới máy chủ và khôi phục phiên đăng nhập đã lưu (nếu còn hạn).
  Future<void> connect() async {
    if (_connecting) return;
    _connecting = true;
    _error = null;
    notifyListeners();

    _client?.close();
    final client = ApiClient(baseUrl: baseUrl);
    _client = client;
    _currentUser = null;

    try {
      final status = await client.authStatus();
      _needsSetup = asBool(status['can_tao_tai_khoan_chu']);
      _serverInfo = ServerInfo.fromJson(status);

      final savedToken = settings.authToken;
      if (!_needsSetup && savedToken.isNotEmpty) {
        client.authToken = savedToken;
        try {
          _currentUser = await client.me();
          await _afterSignIn();
        } on ApiException {
          // Phiên hết hạn hoặc máy chủ đã sinh khoá ký mới: bỏ phiếu cũ đi và
          // đưa người dùng về màn hình đăng nhập, đừng để họ thấy màn hình
          // trống rỗng không hiểu vì sao.
          client.authToken = null;
          await settings.clearAuthToken();
        }
      }
    } on ApiException catch (e) {
      _serverInfo = null;
      _error = e.message;
    } catch (e) {
      _serverInfo = null;
      _error = '$e';
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    final client = _client;
    if (client == null) throw ApiException('Chưa kết nối được máy chủ.');

    final result = await client.login(username, password);
    client.authToken = result.token;
    await settings.setAuthToken(result.token);
    _currentUser = result.user;
    await _afterSignIn();
    notifyListeners();
  }

  Future<void> setupFirstAdmin({
    required String username,
    required String fullName,
    required String password,
  }) async {
    final client = _client;
    if (client == null) throw ApiException('Chưa kết nối được máy chủ.');

    final result = await client.setupFirstAdmin(
      username: username,
      fullName: fullName,
      password: password,
    );
    client.authToken = result.token;
    await settings.setAuthToken(result.token);
    _currentUser = result.user;
    _needsSetup = false;
    await _afterSignIn();
    notifyListeners();
  }

  Future<void> logout() async {
    _client?.authToken = null;
    _currentUser = null;
    _stations = const [];
    _goodsTypes = const [];
    await settings.clearAuthToken();
    notifyListeners();
  }

  /// Nạp danh mục ngay sau khi đăng nhập — trước đó gọi sẽ bị máy chủ từ chối.
  Future<void> _afterSignIn() async {
    await refreshCatalogs();
    await _chooseDefaultStation();
  }

  /// Các trạm thực sự có bàn cân — chỉ những trạm này mới cấp được số cân.
  List<Station> get scaleStations => _stations.where((s) => s.hasScale).toList();

  /// Chọn sẵn trạm cân khi máy chưa từng chọn, hoặc khi trạm đã chọn nằm ngoài
  /// phạm vi của tài khoản vừa đăng nhập.
  Future<void> _chooseDefaultStation() async {
    final current = settings.stationCode;
    final user = _currentUser;
    final stillValid = current.isNotEmpty &&
        _stations.any((s) => s.code == current && s.hasScale) &&
        (user == null || user.canAccessStation(current));
    if (stillValid) return;

    final info = _serverInfo;
    final preferred = [
      if (info != null && info.isStation)
        ..._stations.where((s) => s.code == info.stationCode && s.hasScale),
      ...scaleStations.where((s) => s.online),
      ...scaleStations,
    ];
    if (preferred.isEmpty) return;
    await settings.setStationCode(preferred.first.code);
  }

  Future<void> refreshCatalogs() async {
    final client = _client;
    if (client == null || !isSignedIn) return;
    try {
      _stations = await client.stations();
      _goodsTypes = await client.goodsTypes();
      await _chooseDefaultStation();
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  /// Địa chỉ WebSocket lấy số cân của trạm đang chọn.
  ///
  /// Máy chủ bắt đăng nhập cả với WebSocket, nên chưa đăng nhập thì không mở
  /// kênh — mở cũng bị từ chối ngay.
  Uri? scaleWsUri() {
    final client = _client;
    if (client == null || !isSignedIn || stationCode.isEmpty) return null;
    return client.wsUri('/ws/scale', {'station': stationCode});
  }

  void _onSettingsChanged() => notifyListeners();

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _client?.close();
    super.dispose();
  }
}
