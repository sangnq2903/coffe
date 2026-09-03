import 'dart:async';
import 'dart:convert';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';

/// Kênh thường trực từ trạm cân lên máy chủ trung tâm.
///
/// Khác với [SyncWorker] (đồng bộ dữ liệu đã lưu, theo chu kỳ), kênh này đẩy số
/// cân realtime để máy ở văn phòng và điện thoại nối vào trung tâm cũng nhìn
/// thấy bàn cân của từng kho đang chỉ bao nhiêu.
class StationUplink {
  StationUplink({
    required this.config,
    required this.readings,
    this.throttle = const Duration(milliseconds: 400),
    WebSocketChannel Function(Uri)? connector,
  }) : _connect = connector ?? WebSocketChannel.connect;

  final ServerConfig config;
  final Stream<ScaleReading> readings;

  /// Đẩy thưa hơn nhịp nội bộ: đường Tailscale giữa các kho có thể là 4G, không
  /// cần bắn 5 gói mỗi giây cho một con số mà mắt người chỉ đọc được vài lần.
  final Duration throttle;

  final WebSocketChannel Function(Uri) _connect;

  WebSocketChannel? _channel;
  StreamSubscription<ScaleReading>? _readingSub;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  ScaleReading? _lastSentReading;
  int _attempt = 0;
  bool _closed = false;

  bool get connected => _channel != null;

  void start() {
    final central = config.centralUri;
    if (central == null) return;
    _open(central);
  }

  void _open(Uri central) {
    if (_closed) return;
    final wsUri = central.replace(
      scheme: central.scheme == 'https' ? 'wss' : 'ws',
      path: '${central.path.replaceAll(RegExp(r'/$'), '')}/ws/station',
    );
    try {
      final channel = _connect(wsUri);
      _channel = channel;
      _socketSub = channel.stream.listen(
        (_) {},
        onDone: () => _onDisconnected(central),
        onError: (_) => _onDisconnected(central),
        cancelOnError: true,
      );
      _register(channel);
      _readingSub = readings.listen((reading) => _sendReading(channel, reading));
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _send(channel, {'type': 'ping'});
      });
      _attempt = 0;
    } catch (_) {
      _onDisconnected(central);
    }
  }

  void _register(WebSocketChannel channel) {
    final station = Station(
      code: config.effectiveStationCode,
      name: config.stationName.isEmpty ? config.effectiveStationCode : config.stationName,
      warehouseName: config.warehouseName,
      address: config.address,
      baseUrl: config.publicBaseUrl,
      online: true,
      lastSeenAt: DateTime.now(),
      scalePort: config.scale.simulate ? 'GIẢ LẬP' : config.scale.port,
      updatedAt: DateTime.now(),
    );
    _send(channel, {'type': 'register', ...station.toJson()});
  }

  void _sendReading(WebSocketChannel channel, ScaleReading reading) {
    final now = DateTime.now();
    final changed = _lastSentReading == null ||
        _lastSentReading!.weight != reading.weight ||
        _lastSentReading!.connected != reading.connected;
    if (!changed && now.difference(_lastSent) < const Duration(seconds: 1)) return;
    if (now.difference(_lastSent) < throttle) return;
    _lastSent = now;
    _lastSentReading = reading;
    _send(channel, {'type': 'reading', ...reading.toJson()});
  }

  void _send(WebSocketChannel channel, Map<String, Object?> data) {
    try {
      channel.sink.add(jsonEncode(data));
    } catch (_) {
      // Kênh đã hỏng; listener onError/onDone sẽ lo việc nối lại.
    }
  }

  void _onDisconnected(Uri central) {
    _cleanupChannel();
    if (_closed || _reconnectTimer != null) return;
    _attempt++;
    final seconds = (_attempt * 2).clamp(2, 30);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      _open(central);
    });
  }

  void _cleanupChannel() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _readingSub?.cancel();
    _readingSub = null;
    _socketSub?.cancel();
    _socketSub = null;
    _channel = null;
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    final channel = _channel;
    _cleanupChannel();
    await channel?.sink.close();
  }
}
