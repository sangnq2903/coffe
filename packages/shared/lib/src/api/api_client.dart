import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../json_utils.dart';
import '../models/customer.dart';
import '../models/goods_type.dart';
import '../models/scale_reading.dart';
import '../models/station.dart';
import '../models/sync_payload.dart';
import '../models/vehicle.dart';
import '../models/weigh_ticket.dart';
import 'api_exception.dart';

/// Thông tin máy chủ trả về ở `/api/health`.
class ServerInfo {
  const ServerInfo({
    required this.role,
    required this.stationCode,
    required this.stationName,
    required this.version,
    this.scaleConnected = false,
    this.scalePort,
  });

  factory ServerInfo.fromJson(Map<String, Object?> json) => ServerInfo(
        role: asString(json['role']),
        stationCode: asString(json['station_code']),
        stationName: asString(json['station_name']),
        version: asString(json['version']),
        scaleConnected: asBool(json['scale_connected']),
        scalePort: asStringOrNull(json['scale_port']),
      );

  final String role;
  final String stationCode;
  final String stationName;
  final String version;
  final bool scaleConnected;
  final String? scalePort;

  bool get isStation => role == 'station';

  bool get isCentral => role == 'central';
}

/// Client HTTP dùng chung cho app Flutter (web/Windows/Android) và cho tiến
/// trình đồng bộ của trạm cân.
class ApiClient {
  ApiClient({required Uri baseUrl, http.Client? httpClient, this.timeout = const Duration(seconds: 15)})
      : _baseUrl = _normalize(baseUrl),
        _http = httpClient ?? http.Client();

  /// Chuẩn hoá địa chỉ gốc: bỏ dấu `/` cuối, và bỏ hẳn phần truy vấn lẫn mảnh
  /// neo `#`.
  ///
  /// Phải dựng lại bằng `Uri(...)` chứ không dùng `replace(query: '')`: trong
  /// Dart, gán chuỗi rỗng nghĩa là "có phần này nhưng rỗng", nên địa chỉ sẽ kết
  /// thúc bằng `?#`. HTTP bỏ qua được, nhưng trình duyệt từ chối thẳng mọi URL
  /// WebSocket có chứa `#` — và lỗi đó làm màn hình số cân không bao giờ nối được.
  static Uri _normalize(Uri uri) {
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
  }

  Uri _build(String path, Map<String, String>? query, {String? scheme}) => Uri(
        scheme: scheme ?? _baseUrl.scheme,
        host: _baseUrl.host,
        port: _baseUrl.hasPort ? _baseUrl.port : null,
        path: '${_baseUrl.path}$path',
        queryParameters: query == null || query.isEmpty ? null : query,
      );

  final Uri _baseUrl;
  final http.Client _http;
  final Duration timeout;

  Uri get baseUrl => _baseUrl;

  /// Địa chỉ WebSocket suy ra từ baseUrl (http → ws, https → wss).
  Uri wsUri(String path, [Map<String, String>? query]) =>
      _build(path, query, scheme: _baseUrl.scheme == 'https' ? 'wss' : 'ws');

  void close() => _http.close();

  // ---------------------------------------------------------------- hệ thống

  Future<ServerInfo> health() async =>
      ServerInfo.fromJson(await _getMap('/api/health'));

  Future<SyncStatus> syncStatus() async =>
      SyncStatus.fromJson(await _getMap('/api/sync/status'));

  /// Yêu cầu trạm đồng bộ ngay, không chờ tới chu kỳ định sẵn.
  Future<SyncStatus> syncNow() async =>
      SyncStatus.fromJson(await _postMap('/api/sync/now', const {}));

  Future<List<Station>> stations() async =>
      (await _getList('/api/stations')).map(Station.fromJson).toList();

  Future<List<String>> serialPorts() async {
    final data = await _getMap('/api/scale/ports');
    return (data['ports'] as List? ?? const []).map((e) => e.toString()).toList();
  }

  /// Số cân hiện tại — dùng để hiển thị ngay khi mới mở màn hình, trong lúc
  /// WebSocket chưa kịp bắt tay.
  Future<ScaleReading> currentReading() async =>
      ScaleReading.fromJson(await _getMap('/api/scale/current'));

  // ---------------------------------------------------------------- danh mục

  Future<List<Customer>> customers({String? query, bool includeInactive = false}) async =>
      (await _getList('/api/customers', {
        if (query != null && query.isNotEmpty) 'q': query,
        if (includeInactive) 'all': '1',
      }))
          .map(Customer.fromJson)
          .toList();

  Future<Customer> saveCustomer(Customer customer) async =>
      Customer.fromJson(await _postMap('/api/customers', customer.toJson()));

  Future<void> deleteCustomer(String id) => _delete('/api/customers/$id');

  Future<List<Vehicle>> vehicles({String? query, bool includeInactive = false}) async =>
      (await _getList('/api/vehicles', {
        if (query != null && query.isNotEmpty) 'q': query,
        if (includeInactive) 'all': '1',
      }))
          .map(Vehicle.fromJson)
          .toList();

  Future<Vehicle> saveVehicle(Vehicle vehicle) async =>
      Vehicle.fromJson(await _postMap('/api/vehicles', vehicle.toJson()));

  Future<void> deleteVehicle(String id) => _delete('/api/vehicles/$id');

  Future<List<GoodsType>> goodsTypes({bool includeInactive = false}) async =>
      (await _getList('/api/goods-types', {if (includeInactive) 'all': '1'}))
          .map(GoodsType.fromJson)
          .toList();

  Future<GoodsType> saveGoodsType(GoodsType goods) async =>
      GoodsType.fromJson(await _postMap('/api/goods-types', goods.toJson()));

  Future<void> deleteGoodsType(String id) => _delete('/api/goods-types/$id');

  // ----------------------------------------------------------------- phiếu cân

  Future<List<WeighTicket>> tickets({
    String? stationCode,
    TicketStatus? status,
    String? query,
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
  }) async =>
      (await _getList('/api/tickets', {
        if (stationCode != null && stationCode.isNotEmpty) 'station': stationCode,
        if (status != null) 'status': status.value,
        if (query != null && query.isNotEmpty) 'q': query,
        if (from != null) 'from': timeToMillis(from).toString(),
        if (to != null) 'to': timeToMillis(to).toString(),
        'limit': limit.toString(),
        'offset': offset.toString(),
      }))
          .map(WeighTicket.fromJson)
          .toList();

  Future<WeighTicket> ticket(String id) async =>
      WeighTicket.fromJson(await _getMap('/api/tickets/$id'));

  /// Tạo phiếu và ghi cân lần 1.
  ///
  /// Nhận map thay vì [WeighTicket] vì lúc này phiếu chưa tồn tại: id và số
  /// phiếu do máy chủ cấp, client chỉ gửi những gì người dùng đã nhập.
  Future<WeighTicket> createTicket(Map<String, Object?> request) async =>
      WeighTicket.fromJson(await _postMap('/api/tickets', request));

  Future<WeighTicket> updateTicket(String id, Map<String, Object?> changes) async =>
      WeighTicket.fromJson(await _postMap('/api/tickets/$id', changes));

  /// Ghi cân lần 2 và chốt phiếu.
  Future<WeighTicket> completeTicket(String id, double secondWeight, {String? note}) async =>
      WeighTicket.fromJson(await _postMap('/api/tickets/$id/second-weigh', {
        'second_weight': secondWeight,
        if (note != null) 'note': note,
      }));

  Future<WeighTicket> cancelTicket(String id, {String? reason}) async =>
      WeighTicket.fromJson(await _postMap('/api/tickets/$id/cancel', {
        if (reason != null) 'reason': reason,
      }));

  // ------------------------------------------------------------------- đồng bộ

  Future<SyncPayload> syncPull(DateTime? since, {String? stationCode}) async =>
      SyncPayload.fromJson(await _getMap('/api/sync/pull', {
        'since': timeToMillis(since ?? DateTime.fromMillisecondsSinceEpoch(0)).toString(),
        if (stationCode != null) 'station': stationCode,
      }));

  Future<SyncPayload> syncPush(SyncPayload payload) async =>
      SyncPayload.fromJson(await _postMap('/api/sync/push', payload.toJson()));

  // -------------------------------------------------------------------- nội bộ

  Uri _uri(String path, [Map<String, String>? query]) => _build(path, query);

  Future<Map<String, Object?>> _getMap(String path, [Map<String, String>? query]) async {
    final body = await _send(() => _http.get(_uri(path, query)), _uri(path, query));
    return body is Map<String, Object?> ? body : <String, Object?>{};
  }

  Future<List<Map<String, Object?>>> _getList(String path, [Map<String, String>? query]) async {
    final body = await _send(() => _http.get(_uri(path, query)), _uri(path, query));
    if (body is List) {
      return body.whereType<Map>().map((e) => e.cast<String, Object?>()).toList();
    }
    if (body is Map && body['items'] is List) {
      return asMapList(body['items']);
    }
    return const [];
  }

  Future<Map<String, Object?>> _postMap(String path, Map<String, Object?> payload) async {
    final uri = _uri(path);
    final body = await _send(
      () => _http.post(
        uri,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        body: jsonEncode(payload),
      ),
      uri,
    );
    return body is Map<String, Object?> ? body : <String, Object?>{};
  }

  Future<void> _delete(String path) async {
    final uri = _uri(path);
    await _send(() => _http.delete(uri), uri);
  }

  Future<Object?> _send(Future<http.Response> Function() request, Uri uri) async {
    http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Máy chủ không phản hồi (quá $timeout).', uri: uri);
    } catch (e) {
      throw ApiException('Không kết nối được máy chủ: $e', uri: uri);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Object? decoded;
    if (text.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode >= 400) {
      final message = decoded is Map && decoded['error'] != null
          ? decoded['error'].toString()
          : 'Máy chủ báo lỗi ${response.statusCode}';
      throw ApiException(message, statusCode: response.statusCode, uri: uri);
    }
    return decoded;
  }
}
