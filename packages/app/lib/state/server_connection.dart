import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter/foundation.dart';

import '../core/app_settings.dart';

/// Quản lý kết nối tới server và danh mục dùng chung của toàn app.
class ServerConnection extends ChangeNotifier {
  ServerConnection(this.settings) {
    settings.addListener(_onSettingsChanged);
  }

  final AppSettings settings;

  ApiClient? _client;
  ServerInfo? _serverInfo;
  List<Station> _stations = const [];
  List<GoodsType> _goodsTypes = const [];
  String? _error;
  bool _connecting = false;

  ApiClient? get client => _client;

  ServerInfo? get serverInfo => _serverInfo;

  List<Station> get stations => _stations;

  List<GoodsType> get goodsTypes => _goodsTypes;

  String? get error => _error;

  bool get connecting => _connecting;

  bool get isConnected => _serverInfo != null;

  /// Trạm đang được chọn để theo dõi số cân và lập phiếu.
  String get stationCode {
    if (settings.stationCode.isNotEmpty) return settings.stationCode;
    final withScale = _stations.where((s) => s.hasScale).firstOrNull;
    return withScale?.code ?? _serverInfo?.stationCode ?? '';
  }

  Station? get station =>
      _stations.where((s) => s.code == stationCode).firstOrNull;

  /// Địa chỉ server đang dùng.
  ///
  /// Khi mở app từ chính server (bản web) thì mặc định dùng luôn địa chỉ trên
  /// thanh địa chỉ, người dùng không phải cấu hình gì.
  Uri get baseUrl {
    final configured = settings.serverUrl.trim();
    if (configured.isNotEmpty) {
      final withScheme =
          configured.startsWith('http') ? configured : 'http://$configured';
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

  Future<void> connect() async {
    if (_connecting) return;
    _connecting = true;
    _error = null;
    notifyListeners();

    _client?.close();
    final client = ApiClient(baseUrl: baseUrl);
    _client = client;
    try {
      _serverInfo = await client.health();
      await refreshCatalogs();
      await _chooseDefaultStation();
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

  /// Các trạm thực sự có bàn cân — chỉ những trạm này mới cấp được số cân.
  List<Station> get scaleStations => _stations.where((s) => s.hasScale).toList();

  /// Chọn sẵn trạm cân khi máy chưa từng chọn.
  ///
  /// Máy chủ trung tâm không có bàn cân, nên khi mở app từ trung tâm phải trỏ
  /// sang một trạm có đầu cân — nếu không màn hình sẽ đứng ở "mất kết nối" dù
  /// hệ thống vẫn chạy đúng.
  Future<void> _chooseDefaultStation() async {
    final current = settings.stationCode;
    if (current.isNotEmpty && _stations.any((s) => s.code == current && s.hasScale)) {
      return;
    }
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
    if (client == null) return;
    try {
      _stations = await client.stations();
      _goodsTypes = await client.goodsTypes();
      // Trạm có thể lên mạng sau khi app đã mở, nên mỗi lần làm mới lại cân
      // nhắc xem đã chọn được trạm có bàn cân chưa.
      await _chooseDefaultStation();
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  /// Địa chỉ WebSocket lấy số cân của trạm đang chọn.
  ///
  /// Nếu trạm đã khai báo địa chỉ Tailscale riêng và app đang nối vào máy chủ
  /// trung tâm, vẫn dùng đường qua trung tâm: trung tâm đã nhận sẵn luồng số
  /// cân của mọi trạm, đi thẳng vào trạm chỉ thêm một điểm có thể hỏng.
  Uri? scaleWsUri() {
    final client = _client;
    if (client == null || stationCode.isEmpty) return null;
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
