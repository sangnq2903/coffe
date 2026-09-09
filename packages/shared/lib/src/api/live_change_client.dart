import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Một lần máy chủ báo "dữ liệu vừa đổi".
class ThayDoiDuLieu {
  const ThayDoiDuLieu(this.bang, {this.noiLai = false});

  /// Tên các bảng vừa đổi, ví dụ `tickets`, `customers`, `cham_cong`.
  final Set<String> bang;

  /// Đây là tín hiệu phát ra ngay sau khi nối lại được, không phải một thay đổi
  /// cụ thể. Lúc mất kết nối máy chủ vẫn ghi tiếp mà không ai nghe, nên nối lại
  /// thì phải coi như **mọi thứ đều có thể đã đổi**.
  final bool noiLai;

  bool coBang(Iterable<String> ten) => noiLai || ten.any(bang.contains);

  @override
  String toString() => noiLai ? 'nối lại' : bang.join(', ');
}

/// Nghe tín hiệu thay đổi dữ liệu từ máy chủ qua WebSocket.
///
/// Máy chủ chỉ gửi **tên bảng**, không gửi dữ liệu — bên nhận tự gọi lại đúng
/// cửa API cũ. Nhờ vậy luật phân quyền chỉ có một bản, nằm ở API.
///
/// Đường mạng ở kho đi qua Tailscale nên rớt là chuyện thường; lớp này tự nối
/// lại với khoảng chờ giãn dần, và **mỗi lần nối lại được thì phát một tín hiệu
/// `noiLai`** để màn hình tải lại toàn bộ. Bỏ bước đó thì đúng lúc mạng chập là
/// lúc màn hình bắt đầu hiện số cũ mà không ai biết — hỏng đúng kiểu tính năng
/// này sinh ra để chữa.
class LiveChangeClient {
  LiveChangeClient({
    required this.wsUrl,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 20),
    WebSocketChannel Function(Uri)? connector,
  }) : _connect = connector ?? WebSocketChannel.connect;

  final Uri wsUrl;
  final Duration reconnectDelay;
  final Duration maxReconnectDelay;

  final WebSocketChannel Function(Uri) _connect;

  final _controller = StreamController<ThayDoiDuLieu>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _henNoiLai;
  int _lanThu = 0;
  bool _dongRoi = false;

  /// Đã từng nối được lần nào chưa — để lần nối **đầu tiên** không bắt tải lại,
  /// vì màn hình vừa mới tự tải xong rồi.
  bool _daTungNoi = false;

  Stream<ThayDoiDuLieu> get thayDoi => _controller.stream;

  bool get dangNoi => _channel != null;

  void start() {
    if (_dongRoi) return;
    _mo();
  }

  void _mo() {
    _henNoiLai?.cancel();
    _henNoiLai = null;
    try {
      final channel = _connect(wsUrl);
      _channel = channel;
      _sub = channel.stream.listen(
        _nhan,
        onError: (Object _) => _mat(),
        onDone: _mat,
        cancelOnError: true,
      );
      _lanThu = 0;

      if (_daTungNoi && !_controller.isClosed) {
        _controller.add(const ThayDoiDuLieu({}, noiLai: true));
      }
      _daTungNoi = true;
    } catch (_) {
      _mat();
    }
  }

  void _nhan(dynamic message) {
    if (_controller.isClosed) return;
    try {
      final raw = jsonDecode('$message');
      if (raw is! Map) return;
      final bang = (raw['bang'] as List?)?.map((e) => e.toString()).toSet();
      if (bang == null || bang.isEmpty) return;
      _controller.add(ThayDoiDuLieu(bang));
    } catch (_) {
      // Khung lạ thì bỏ qua; không đáng để cắt kết nối.
    }
  }

  void _mat() {
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (_dongRoi || _controller.isClosed) return;

    // Giãn dần để mạng đứt lâu không thành hàng nghìn lần thử vô ích.
    _lanThu++;
    final cho = Duration(
      milliseconds: (reconnectDelay.inMilliseconds * _lanThu)
          .clamp(reconnectDelay.inMilliseconds, maxReconnectDelay.inMilliseconds),
    );
    _henNoiLai = Timer(cho, _mo);
  }

  Future<void> dispose() async {
    _dongRoi = true;
    _henNoiLai?.cancel();
    await _sub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    await _controller.close();
  }
}
