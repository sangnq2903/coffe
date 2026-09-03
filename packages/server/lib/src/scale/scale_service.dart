import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';

import '../config.dart';
import '../logging.dart';
import 'win32_serial.dart';

/// Đọc số cân từ cổng COM và phát ra luồng [ScaleReading] cho toàn hệ thống.
///
/// Việc đọc cổng COM là thao tác chặn, nên được đẩy sang một Isolate riêng;
/// isolate chính chỉ nhận byte về, ghép khung, giải mã và phát cho các
/// WebSocket đang mở.
class ScaleService {
  ScaleService({required this.config, required this.stationCode})
      : _parser = WeightParser(config.parserConfig),
        _stability = StabilityTracker(
          tolerance: config.stableTolerance,
          requiredSamples: config.stableSamples,
        );

  final ScaleConfig config;
  final String stationCode;

  final WeightParser _parser;
  final StabilityTracker _stability;
  final FrameAssembler _assembler = FrameAssembler();
  final _controller = StreamController<ScaleReading>.broadcast();

  Isolate? _isolate;
  ReceivePort? _fromIsolate;
  SendPort? _isolateControl;
  Timer? _flushTimer;
  Timer? _simulatorTimer;
  StreamSubscription<dynamic>? _isolateSub;

  ScaleReading _current = ScaleReading.disconnected('', error: 'Chưa khởi động');
  ScaleReading? _lastBroadcast;
  bool _pendingBroadcast = false;
  bool _running = false;
  DateTime? _lastFrameAt;
  DateTime? _readerStartedAt;
  bool _readerReported = false;
  bool _hangReported = false;
  DateTime? _hangLoggedAt;

  /// Luồng số cân realtime. Broadcast nên nhiều WebSocket cùng nghe được.
  Stream<ScaleReading> get readings => _controller.stream;

  ScaleReading get current => _current;

  bool get connected => _current.connected;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _current = ScaleReading.disconnected(stationCode, error: 'Đang kết nối đầu cân...');

    if (!config.enabled) {
      _current = ScaleReading.disconnected(
        stationCode,
        error: 'Chưa cấu hình cổng COM cho đầu cân.',
      );
      return;
    }

    _flushTimer = Timer.periodic(
      Duration(milliseconds: config.broadcastIntervalMs),
      (_) => _flush(),
    );

    if (config.simulate) {
      _startSimulator();
      return;
    }
    await _startSerialIsolate();
  }

  Future<void> _startSerialIsolate() async {
    final receive = ReceivePort();
    _fromIsolate = receive;
    _isolateSub = receive.listen(_onIsolateMessage);
    _readerStartedAt = DateTime.now();
    _isolate = await Isolate.spawn(
      _serialReaderEntry,
      _SerialReaderArgs(
        sendPort: receive.sendPort,
        port: config.port,
        baudRate: config.baudRate,
        dataBits: config.dataBits,
        stopBits: config.stopBits,
        parity: config.parity,
      ),
      debugName: 'scale-reader-$stationCode',
      errorsAreFatal: false,
    );
  }

  void _onIsolateMessage(dynamic message) {
    if (message is! Map) return;
    switch (message['type']) {
      case 'ready':
        _isolateControl = message['control'] as SendPort;
        AppLog.write('[đầu cân] tiến trình đọc cổng đã sẵn sàng');
      case 'open':
        _readerReported = true;
        _hangReported = false;
        AppLog.write('[đầu cân] đã mở ${config.port} @ ${config.baudRate} baud');
        _lastFrameAt = DateTime.now();
        _setReading(ScaleReading(
          stationCode: stationCode,
          weight: 0,
          unit: config.unit,
          stable: false,
          at: DateTime.now(),
          connected: true,
        ));
      case 'data':
        _ingest(message['bytes'] as Uint8List);
      case 'error':
        _readerReported = true;
        AppLog.error('[đầu cân] ${message['message']}');
        _assembler.reset();
        _stability.reset();
        _lastFrameAt = null;
        _setReading(ScaleReading.disconnected(
          stationCode,
          error: message['message']?.toString(),
        ));
    }
  }

  void _ingest(Uint8List bytes) {
    for (final frame in _assembler.add(bytes)) {
      final parsed = _parser.parse(frame);
      if (parsed == null) continue;
      final stable = parsed.stable ?? _stability.update(parsed.weight);
      if (_lastFrameAt == null) {
        _hangLoggedAt = null;
        AppLog.write('[đầu cân] có tín hiệu trở lại: ${parsed.weight} ${parsed.unit}');
      }
      _lastFrameAt = DateTime.now();
      _setReading(ScaleReading(
        stationCode: stationCode,
        weight: parsed.weight,
        unit: parsed.unit,
        stable: stable,
        at: DateTime.now(),
        raw: parsed.raw,
        connected: true,
      ));
    }
  }

  void _setReading(ScaleReading reading) {
    _current = reading;
    final last = _lastBroadcast;
    // Mất/khôi phục kết nối là thông tin quan trọng, đẩy đi ngay không chờ nhịp.
    if (last == null || last.connected != reading.connected) {
      _broadcast();
      return;
    }
    if (last.weight != reading.weight || last.stable != reading.stable) {
      _pendingBroadcast = true;
    }
  }

  /// Nhịp đẩy dữ liệu: gửi khi số cân đổi, và mỗi giây gửi một lần dù không đổi
  /// để client biết đường truyền vẫn thông.
  int _idleTicks = 0;

  void _flush() {
    _checkReaderHang();
    _checkDataTimeout();
    final ticksPerSecond = (1000 / config.broadcastIntervalMs).ceil();
    if (_pendingBroadcast) {
      _broadcast();
      return;
    }
    if (++_idleTicks >= ticksPerSecond) {
      _broadcast();
    }
  }

  /// Phát hiện tiến trình đọc cổng mở được cổng nhưng treo bên trong.
  ///
  /// Khi driver USB-COM bị kẹt (hay gặp sau khi tiến trình bị tắt đột ngột lúc
  /// cổng đang mở), lời gọi thiết lập tham số cổng của Windows có thể không bao
  /// giờ trả về. Khi đó cổng đã bị chiếm nhưng không có "đã mở" cũng không có
  /// báo lỗi — màn hình sẽ treo mãi ở "đang kết nối" mà không ai biết vì sao.
  /// Cố tình KHÔNG tự dựng lại tiến trình đọc ở đây. Isolate đang kẹt trong lời
  /// gọi Windows nên `Isolate.kill` chưa có tác dụng ngay, sinh isolate mới sẽ
  /// thành hai bên tranh nhau cùng một cổng COM và số cân chập chờn liên tục.
  /// Vòng lặp trong isolate vốn đã tự mở lại cổng mỗi 3 giây, nên khi driver
  /// hồi phục (cắm lại cáp) thì nó tự đọc tiếp.
  void _checkReaderHang() {
    if (_readerReported || _hangReported) return;
    final startedAt = _readerStartedAt;
    if (startedAt == null) return;
    if (DateTime.now().difference(startedAt) < const Duration(seconds: 15)) return;

    _hangReported = true;
    final message = 'Cổng ${config.port} mở được nhưng không phản hồi. '
        'Hãy rút cáp USB–COM ra cắm lại — hệ thống sẽ tự nhận lại, '
        'không cần khởi động lại gì.';
    // Vòng tự phục hồi thử lại mỗi ~18 giây; ghi log mỗi lần thử sẽ làm đầy
    // file trong vài ngày mất kết nối, nên chỉ ghi lại tối đa 5 phút một lần.
    final lastLogged = _hangLoggedAt;
    if (lastLogged == null ||
        DateTime.now().difference(lastLogged) > const Duration(minutes: 5)) {
      _hangLoggedAt = DateTime.now();
      AppLog.error('[đầu cân] $message');
    }
    _setReading(ScaleReading.disconnected(stationCode, error: message));
  }

  /// Phát hiện đầu cân ngừng gửi dù cổng COM vẫn mở.
  ///
  /// Tắt nguồn đầu cân hay tuột dây tín hiệu không làm cổng COM báo lỗi, nên nếu
  /// không có đồng hồ canh này thì màn hình sẽ đứng nguyên ở số cân cuối cùng và
  /// nhân viên tưởng đó là số thật — sai số kiểu này không ai phát hiện ra được.
  void _checkDataTimeout() {
    final last = _lastFrameAt;
    if (last == null || !_current.connected) return;
    if (DateTime.now().difference(last).inSeconds < config.dataTimeoutSeconds) {
      return;
    }
    AppLog.error('[đầu cân] mất tín hiệu: không nhận được khung nào trong '
        '${config.dataTimeoutSeconds} giây');
    _lastFrameAt = null;
    _stability.reset();
    _assembler.reset();
    _setReading(ScaleReading.disconnected(
      stationCode,
      error: 'Đầu cân không gửi dữ liệu trong ${config.dataTimeoutSeconds} giây. '
          'Kiểm tra nguồn đầu cân và dây tín hiệu.',
    ));
  }

  void _broadcast() {
    _pendingBroadcast = false;
    _idleTicks = 0;
    _lastBroadcast = _current;
    if (!_controller.isClosed) _controller.add(_current);
  }

  // ------------------------------------------------------------- giả lập

  /// Giả lập một chu kỳ cân xe để chạy thử toàn hệ thống khi chưa đấu đầu cân:
  /// xe lên bàn cân → số nhảy dần → đứng yên → xe xuống.
  void _startSimulator() {
    final random = Random();
    var phase = 0; // 0 trống, 1 đang lên, 2 đứng yên, 3 đang xuống
    var target = 0.0;
    var value = 0.0;
    var holdTicks = 0;

    _simulatorTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      switch (phase) {
        case 0:
          value = random.nextDouble() * 4 - 2;
          if (--holdTicks <= 0) {
            target = 8000 + random.nextInt(20000).toDouble();
            phase = 1;
          }
        case 1:
          value += (target - value) * 0.18 + (random.nextDouble() * 60 - 30);
          if ((target - value).abs() < 25) {
            phase = 2;
            holdTicks = 40;
          }
        case 2:
          value = target + (random.nextDouble() * 4 - 2);
          if (--holdTicks <= 0) phase = 3;
        case 3:
          value *= 0.7;
          if (value < 30) {
            phase = 0;
            holdTicks = 30;
          }
      }
      final rounded = (value / 10).round() * 10.0;
      _setReading(ScaleReading(
        stationCode: stationCode,
        weight: rounded,
        unit: config.unit,
        stable: _stability.update(rounded),
        at: DateTime.now(),
        raw: 'SIM ${rounded.toStringAsFixed(0)} ${config.unit}',
        connected: true,
      ));
    });
  }

  Future<void> dispose() async {
    _running = false;
    _flushTimer?.cancel();
    _simulatorTimer?.cancel();
    _isolateControl?.send('stop');
    // Cho isolate 500ms tự đóng cổng COM; quá hạn thì cưỡng chế, nếu không
    // cổng sẽ bị giữ lại và lần khởi động sau không mở được.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _isolate?.kill(priority: Isolate.immediate);
    await _isolateSub?.cancel();
    _fromIsolate?.close();
    await _controller.close();
  }
}

/// Tham số gửi sang isolate đọc cổng COM (chỉ chứa kiểu gửi được qua isolate).
class _SerialReaderArgs {
  const _SerialReaderArgs({
    required this.sendPort,
    required this.port,
    required this.baudRate,
    required this.dataBits,
    required this.stopBits,
    required this.parity,
  });

  final SendPort sendPort;
  final String port;
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final String parity;
}

/// Vòng lặp đọc cổng COM, chạy trong isolate riêng.
Future<void> _serialReaderEntry(_SerialReaderArgs args) async {
  final send = args.sendPort;
  final control = ReceivePort();
  var stop = false;
  control.listen((message) {
    if (message == 'stop') stop = true;
  });
  send.send({'type': 'ready', 'control': control.sendPort});

  Win32SerialPort? port;
  while (!stop) {
    if (port == null) {
      try {
        port = Win32SerialPort.open(
          args.port,
          baudRate: args.baudRate,
          dataBits: args.dataBits,
          stopBits: args.stopBits,
          parity: args.parity,
        );
        send.send({'type': 'open'});
      } catch (e) {
        send.send({'type': 'error', 'message': '$e'});
        // Thử lại sau vài giây: cáp có thể được cắm lại mà không cần khởi động
        // lại server.
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
    }
    try {
      final data = port.read();
      if (data.isNotEmpty) {
        send.send({'type': 'data', 'bytes': data});
      }
    } catch (e) {
      send.send({'type': 'error', 'message': '$e'});
      port.close();
      port = null;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // Nhường một vòng event loop để nhận được lệnh dừng.
    await Future<void>.delayed(Duration.zero);
  }
  port?.close();
  control.close();
}
