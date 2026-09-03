import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../models/scale_reading.dart';

/// Nhận số cân realtime từ server của trạm cân qua WebSocket.
///
/// Đây là thành phần đứng sau yêu cầu "màn hình hiển thị số cân nhảy liên tục":
/// server đẩy mỗi khung đọc được từ cổng COM xuống, client chỉ việc vẽ lại.
/// Mất mạng thì tự nối lại và phát ra trạng thái mất kết nối để màn hình báo
/// rõ, tuyệt đối không để số cân cũ đứng im mà người dùng tưởng là số thật.
class LiveScaleClient {
  LiveScaleClient({
    required this.wsUrl,
    required this.stationCode,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 15),
    this.staleAfter = const Duration(seconds: 5),
    WebSocketChannel Function(Uri)? connector,
  }) : _connect = connector ?? WebSocketChannel.connect;

  final Uri wsUrl;
  final String stationCode;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;

  /// Không nhận được khung nào trong khoảng này thì coi như đầu cân đã ngưng
  /// gửi (rút cáp COM, tắt đầu cân) và báo mất tín hiệu.
  final Duration staleAfter;

  final WebSocketChannel Function(Uri) _connect;

  final _controller = StreamController<ScaleReading>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _staleTimer;
  int _attempt = 0;
  bool _closed = false;
  ScaleReading? _last;

  Stream<ScaleReading> get readings => _controller.stream;

  ScaleReading? get lastReading => _last;

  bool get isConnected => _channel != null;

  void start() {
    if (_closed) return;
    _open();
  }

  void _open() {
    _cancelReconnect();
    try {
      final channel = _connect(wsUrl);
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) => _onDisconnected('Lỗi kết nối: $error'),
        onDone: () => _onDisconnected('Mất kết nối tới trạm cân'),
        cancelOnError: true,
      );
      _armStaleTimer();
    } catch (e) {
      _onDisconnected('Không mở được kết nối: $e');
    }
  }

  void _onMessage(dynamic message) {
    _attempt = 0;
    _armStaleTimer();
    try {
      final decoded = jsonDecode(message is List<int> ? utf8.decode(message) : '$message');
      if (decoded is! Map) return;
      final map = decoded.cast<String, Object?>();
      // Server có thể gửi kèm gói điều khiển (ping, thông báo trạng thái trạm).
      if (map['type'] != null && map['type'] != 'reading') return;
      _emit(ScaleReading.fromJson(map));
    } catch (_) {
      // Khung hỏng thì bỏ qua, luồng số cân vẫn chạy tiếp.
    }
  }

  void _armStaleTimer() {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleAfter, () {
      _emit(ScaleReading.disconnected(
        stationCode,
        error: 'Không nhận được tín hiệu từ đầu cân',
      ));
    });
  }

  void _onDisconnected(String reason) {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _staleTimer?.cancel();
    _emit(ScaleReading.disconnected(stationCode, error: reason));
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _attempt++;
    final ms = (reconnectDelay.inMilliseconds * _attempt)
        .clamp(reconnectDelay.inMilliseconds, maxReconnectDelay.inMilliseconds);
    _reconnectTimer = Timer(Duration(milliseconds: ms), () {
      _reconnectTimer = null;
      _open();
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _emit(ScaleReading reading) {
    _last = reading;
    if (!_controller.isClosed) _controller.add(reading);
  }

  Future<void> dispose() async {
    _closed = true;
    _cancelReconnect();
    _staleTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close(ws_status.normalClosure);
    await _controller.close();
  }
}
