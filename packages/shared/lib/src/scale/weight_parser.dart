import 'dart:convert';
import 'dart:typed_data';

/// Giao thức truyền số cân của đầu cân (indicator).
enum ScaleProtocol {
  /// Tự dò: thử Keli, rồi Toledo, không khớp thì rơi về đọc dòng ASCII.
  auto('auto'),

  /// Đầu cân gửi từng dòng chữ, ví dụ `ST,GS,+  1234.5 kg`.
  ascii('ascii'),

  /// Khung nhị phân Toledo/METTLER continuous output (STX + 3 status + 12 số).
  toledo('toledo'),

  /// Keli D2008FA (và các đầu cân cùng họ) ở chế độ truyền liên tục TF=0:
  /// `STX + dấu + 6 chữ số + số chữ số thập phân + checksum XOR + ETX`.
  keli('keli'),

  /// Người dùng tự khai regex trong cấu hình khi đầu cân dùng giao thức lạ.
  custom('custom');

  const ScaleProtocol(this.value);

  final String value;

  static ScaleProtocol parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString().toLowerCase(),
        orElse: () => ScaleProtocol.auto,
      );
}

/// Kết quả giải mã một khung dữ liệu.
class WeightFrame {
  const WeightFrame({
    required this.weight,
    required this.unit,
    required this.raw,
    this.stable,
  });

  final double weight;
  final String unit;

  /// Chuỗi thô đã nhận, để hiển thị khi cần dò lỗi đấu nối.
  final String raw;

  /// `null` khi giao thức không báo trạng thái ổn định — khi đó
  /// [StabilityTracker] sẽ tự suy ra.
  final bool? stable;

  @override
  String toString() => 'WeightFrame($weight $unit, stable=$stable)';
}

/// Cấu hình giải mã, đọc từ file cấu hình của trạm cân.
class WeightParserConfig {
  const WeightParserConfig({
    this.protocol = ScaleProtocol.auto,
    this.unit = 'kg',
    this.divisor = 1,
    this.customPattern,
    this.customGroup = 1,
  });

  final ScaleProtocol protocol;

  /// Đơn vị mặc định khi khung dữ liệu không kèm đơn vị.
  final String unit;

  /// Hệ số chia: nhiều đầu cân gửi `0001234` với ý nghĩa 123.4 kg (divisor=10).
  final double divisor;

  /// Regex tự khai khi [protocol] là [ScaleProtocol.custom].
  final String? customPattern;
  final int customGroup;

  WeightParserConfig copyWith({
    ScaleProtocol? protocol,
    String? unit,
    double? divisor,
    String? customPattern,
    int? customGroup,
  }) =>
      WeightParserConfig(
        protocol: protocol ?? this.protocol,
        unit: unit ?? this.unit,
        divisor: divisor ?? this.divisor,
        customPattern: customPattern ?? this.customPattern,
        customGroup: customGroup ?? this.customGroup,
      );
}

/// Giải mã khung dữ liệu số cân.
class WeightParser {
  WeightParser(this.config)
      : _customRegex = config.customPattern == null
            ? null
            : RegExp(config.customPattern!);

  final WeightParserConfig config;
  final RegExp? _customRegex;

  static final RegExp _numberRegex = RegExp(r'[+-]?\d+(?:[.,]\d+)?');
  static final RegExp _unitRegex =
      RegExp(r'\b(kgs?|lbs?|tons?|t|g)\b', caseSensitive: false);

  /// Trả về `null` khi khung không đọc được (nhiễu, khung vỡ, dòng trạng thái).
  WeightFrame? parse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    switch (config.protocol) {
      case ScaleProtocol.toledo:
        return _parseToledo(bytes);
      case ScaleProtocol.keli:
        return _parseKeli(bytes);
      case ScaleProtocol.ascii:
        return _parseAscii(bytes);
      case ScaleProtocol.custom:
        return _parseCustom(bytes);
      case ScaleProtocol.auto:
        // Keli đứng đầu vì khung của nó có checksum: nhận đúng thì gần như
        // không thể nhầm, mà nếu để ASCII chạy trước sẽ đọc bừa cả chữ số
        // thập phân lẫn checksum thành một con số sai.
        return _parseKeli(bytes) ?? _parseToledo(bytes) ?? _parseAscii(bytes);
    }
  }

  /// Khung Keli liên tục: `STX + dấu(1) + 6 chữ số + vị trí thập phân(1) +
  /// checksum XOR dạng hex(2) + ETX`.
  ///
  /// Ví dụ 70,0 kg: `STX +0007001 <checksum> ETX` — chữ số thứ 8 là số chữ số
  /// thập phân chứ không phải phần của số cân, nên bắt buộc phải giải mã riêng.
  WeightFrame? _parseKeli(List<int> bytes) {
    final start = bytes.indexOf(0x02);
    if (start < 0 || bytes.length - start < 11) return null;
    final body = bytes.sublist(start + 1, start + 11);

    final sign = body[0];
    if (sign != 0x2b && sign != 0x2d) return null; // '+' hoặc '-'

    for (var i = 1; i <= 7; i++) {
      if (body[i] < 0x30 || body[i] > 0x39) return null;
    }
    final decimals = body[7] - 0x30;
    if (decimals > 4) return null;

    // Checksum là XOR của 8 byte đầu, viết bằng hai ký tự hex. Nhờ nó mà chế độ
    // tự dò nhận diện được khung Keli mà không sợ nhầm với giao thức khác.
    var checksum = 0;
    for (var i = 0; i < 8; i++) {
      checksum ^= body[i];
    }
    final expected = checksum.toRadixString(16).padLeft(2, '0').toUpperCase();
    final actual = String.fromCharCodes(body.sublist(8, 10)).toUpperCase();
    if (actual != expected) return null;

    final digits = String.fromCharCodes(body.sublist(1, 7));
    final magnitude = (int.tryParse(digits) ?? 0) / _pow10(decimals);

    return WeightFrame(
      weight: sign == 0x2d ? -magnitude : magnitude,
      unit: config.unit,
      raw: _decode(bytes.sublist(start, start + 11)),
      // Khung này không mang cờ ổn định, để StabilityTracker tự suy ra.
      stable: null,
    );
  }

  WeightFrame? _parseCustom(List<int> bytes) {
    final regex = _customRegex;
    if (regex == null) return null;
    final text = _decode(bytes);
    final match = regex.firstMatch(text);
    if (match == null || match.groupCount < config.customGroup) return null;
    final value = _toDouble(match.group(config.customGroup));
    if (value == null) return null;
    return WeightFrame(
      weight: value / config.divisor,
      unit: _unitOf(text),
      raw: text,
      stable: _stableFlagOf(text),
    );
  }

  WeightFrame? _parseAscii(List<int> bytes) {
    final text = _decode(bytes);
    if (text.trim().isEmpty) return null;
    final match = _numberRegex.firstMatch(text);
    if (match == null) return null;
    final value = _toDouble(match.group(0));
    if (value == null) return null;
    // Chỉ áp dụng hệ số chia cho số nguyên: khung đã có sẵn dấu thập phân thì
    // đầu cân đã tự chia, chia thêm lần nữa sẽ sai 10 lần.
    final hasDecimal = match.group(0)!.contains(RegExp(r'[.,]'));
    final weight = hasDecimal ? value : value / config.divisor;
    return WeightFrame(
      weight: weight,
      unit: _unitOf(text),
      raw: text,
      stable: _stableFlagOf(text),
    );
  }

  /// Khung Toledo continuous: `STX SWA SWB SWC d5..d0 t5..t0 CR`.
  ///
  /// Ba byte trạng thái luôn nằm trong dải in được (bit 5 và 6 bật) nên có thể
  /// dùng chính đặc điểm này để nhận diện khung, tránh nhận nhầm chuỗi ASCII.
  WeightFrame? _parseToledo(List<int> bytes) {
    final start = bytes.indexOf(0x02);
    if (start < 0 || bytes.length - start < 16) return null;
    final f = bytes.sublist(start, start + 16);

    final swa = f[1], swb = f[2], swc = f[3];
    final isStatus = [swa, swb, swc].every((b) => (b & 0x60) == 0x60);
    if (!isStatus) return null;

    final digits = String.fromCharCodes(f.sublist(4, 10));
    if (!RegExp(r'^[0-9 ]{6}$').hasMatch(digits)) return null;
    final rawValue = int.tryParse(digits.trim().isEmpty ? '0' : digits.trim());
    if (rawValue == null) return null;

    // SWA bit 0..2: vị trí dấu thập phân, 2 = số nguyên, 3 = X.X, 4 = X.XX...
    final dpCode = swa & 0x07;
    final decimals = dpCode >= 2 ? dpCode - 2 : 0;
    // dpCode 0 và 1 là bội số 100 và 10 (đầu cân bỏ bớt chữ số cuối).
    final multiplier = dpCode == 0 ? 100.0 : (dpCode == 1 ? 10.0 : 1.0);

    final negative = (swb & 0x02) != 0;
    final inMotion = (swb & 0x08) != 0;
    final isPound = (swb & 0x10) != 0;

    var weight = rawValue * multiplier / _pow10(decimals);
    if (negative) weight = -weight;

    return WeightFrame(
      weight: weight,
      unit: isPound ? 'lb' : 'kg',
      raw: _decode(f),
      stable: !inMotion,
    );
  }

  static double _pow10(int n) {
    var r = 1.0;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  String _unitOf(String text) {
    final m = _unitRegex.firstMatch(text);
    if (m == null) return config.unit;
    final u = m.group(1)!.toLowerCase();
    if (u.startsWith('kg')) return 'kg';
    if (u.startsWith('lb')) return 'lb';
    if (u.startsWith('t')) return 'tấn';
    return u;
  }

  /// Quy ước phổ biến: `ST`/`S` = ổn định, `US`/`U`/`MO` = đang dao động.
  bool? _stableFlagOf(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('US') || upper.contains('MO')) return false;
    if (upper.contains('ST')) return true;
    return null;
  }

  double? _toDouble(String? s) =>
      s == null ? null : double.tryParse(s.replaceAll(',', '.').replaceAll('+', ''));

  String _decode(List<int> bytes) =>
      const Latin1Decoder(allowInvalid: true).convert(Uint8List.fromList(bytes));
}

/// Cắt luồng byte liên tục từ cổng COM thành từng khung dữ liệu.
///
/// Đầu cân gửi không ngừng nghỉ và không có ranh giới gói ở tầng serial, nên
/// phải tự gom byte cho tới khi gặp dấu kết thúc khung (CR, LF hoặc ETX).
class FrameAssembler {
  FrameAssembler({this.maxFrameLength = 128});

  /// Khung dài bất thường nghĩa là đang nhiễu hoặc sai baudrate — bỏ để bộ đệm
  /// không phình vô hạn.
  final int maxFrameLength;

  final List<int> _buffer = [];

  static const _terminators = {0x0d, 0x0a, 0x03};

  List<List<int>> add(List<int> chunk) {
    final frames = <List<int>>[];
    for (final byte in chunk) {
      if (_terminators.contains(byte)) {
        if (_buffer.isNotEmpty) {
          frames.add(List<int>.from(_buffer));
          _buffer.clear();
        }
        continue;
      }
      // STX mở khung mới: dữ liệu dở dang trước đó là rác.
      if (byte == 0x02) {
        _buffer.clear();
      }
      _buffer.add(byte);
      if (_buffer.length > maxFrameLength) {
        _buffer.clear();
      }
    }
    return frames;
  }

  void reset() => _buffer.clear();
}

/// Suy ra trạng thái "số cân đã đứng yên" khi đầu cân không tự báo.
class StabilityTracker {
  StabilityTracker({this.tolerance = 5, this.requiredSamples = 5});

  /// Sai lệch tối đa (kg) vẫn coi là đứng yên.
  final double tolerance;

  /// Số mẫu liên tiếp phải nằm trong [tolerance] thì mới coi là ổn định.
  final int requiredSamples;

  double? _reference;
  int _count = 0;

  bool update(double weight) {
    final ref = _reference;
    if (ref == null || (weight - ref).abs() > tolerance) {
      _reference = weight;
      _count = 1;
      return false;
    }
    _count++;
    return _count >= requiredSamples;
  }

  void reset() {
    _reference = null;
    _count = 0;
  }
}
