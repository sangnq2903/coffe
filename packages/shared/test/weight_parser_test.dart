import 'dart:convert';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

List<int> ascii(String text) => latin1.encode(text);

/// Dựng một khung Toledo continuous để kiểm thử.
///
/// Cấu trúc: STX, ba byte trạng thái, 6 chữ số cân, 6 chữ số bì, CR.
List<int> toledoFrame({
  required String digits,
  int decimalCode = 2,
  bool negative = false,
  bool motion = false,
  bool pound = false,
}) {
  final swa = 0x20 | decimalCode;
  var swb = 0x20;
  if (negative) swb |= 0x02;
  if (motion) swb |= 0x08;
  if (pound) swb |= 0x10;
  const swc = 0x20;
  return [
    0x02,
    swa | 0x40,
    swb | 0x40,
    swc | 0x40,
    ...ascii(digits.padLeft(6, '0')),
    ...ascii('000000'),
    0x0d,
  ];
}

/// Dựng khung Keli D2008FA liên tục để kiểm thử.
List<int> keliFrame(String digits, {int decimals = 1, bool negative = false, String? forceChecksum}) {
  final body = <int>[
    negative ? 0x2d : 0x2b,
    ...ascii(digits.padLeft(6, '0')),
    0x30 + decimals,
  ];
  var checksum = 0;
  for (final b in body) {
    checksum ^= b;
  }
  final hex = forceChecksum ?? checksum.toRadixString(16).padLeft(2, '0').toUpperCase();
  return [0x02, ...body, ...ascii(hex), 0x03];
}

void main() {
  group('WeightParser — khung Keli D2008FA', () {
    final parser = WeightParser(const WeightParserConfig(protocol: ScaleProtocol.keli));

    test('đọc đúng số cân có một chữ số thập phân', () {
      // 70,0 kg gửi thành "0007000" với vị trí thập phân = 1.
      final frame = parser.parse(keliFrame('000700'));
      expect(frame, isNotNull);
      expect(frame!.weight, 70.0);
      expect(frame.unit, 'kg');
    });

    test('không nhầm chữ số thập phân và checksum thành phần của số cân', () {
      // Đây chính là lỗi khi dùng bộ đọc ASCII: 70,0 kg bị đọc thành 7001.
      final ascii = WeightParser(const WeightParserConfig(protocol: ScaleProtocol.ascii));
      final bytes = keliFrame('000700');
      expect(ascii.parse(bytes)!.weight, isNot(70.0));
      expect(parser.parse(bytes)!.weight, 70.0);
    });

    test('đọc được số nguyên và số nhiều chữ số thập phân', () {
      expect(parser.parse(keliFrame('012345', decimals: 0))!.weight, 12345);
      expect(parser.parse(keliFrame('012345', decimals: 2))!.weight, 123.45);
    });

    test('đọc được số âm', () {
      expect(parser.parse(keliFrame('000200', negative: true))!.weight, -20.0);
    });

    test('loại bỏ khung sai checksum thay vì trả về số cân sai', () {
      expect(parser.parse(keliFrame('000700', forceChecksum: 'FF')), isNull);
    });

    test('bỏ qua khung thiếu byte', () {
      expect(parser.parse([0x02, 0x2b, 0x30, 0x30]), isNull);
    });

    test('chế độ tự dò nhận ra khung Keli trước khi rơi về ASCII', () {
      final auto = WeightParser(const WeightParserConfig());
      expect(auto.parse(keliFrame('000700'))!.weight, 70.0);
    });
  });

  group('WeightParser — khung ASCII', () {
    final parser = WeightParser(const WeightParserConfig(protocol: ScaleProtocol.ascii));

    test('đọc được khung có tiền tố trạng thái và đơn vị', () {
      final frame = parser.parse(ascii('ST,GS,+  12345.5 kg'));
      expect(frame, isNotNull);
      expect(frame!.weight, 12345.5);
      expect(frame.unit, 'kg');
      expect(frame.stable, isTrue);
    });

    test('nhận ra trạng thái đang dao động', () {
      expect(parser.parse(ascii('US,GS,+  8000 kg'))!.stable, isFalse);
    });

    test('không có cờ trạng thái thì trả về null để bên gọi tự suy ra', () {
      expect(parser.parse(ascii('+0008000 kg'))!.stable, isNull);
    });

    test('bỏ qua khung không chứa số', () {
      expect(parser.parse(ascii('OVERLOAD')), isNull);
    });

    test('hệ số chia chỉ áp dụng cho số nguyên, không nhân đôi với số đã có dấu thập phân', () {
      final scaled = WeightParser(
        const WeightParserConfig(protocol: ScaleProtocol.ascii, divisor: 10),
      );
      expect(scaled.parse(ascii('0012345'))!.weight, 1234.5);
      expect(scaled.parse(ascii('1234.5'))!.weight, 1234.5);
    });
  });

  group('WeightParser — khung Toledo', () {
    final parser = WeightParser(const WeightParserConfig(protocol: ScaleProtocol.toledo));

    test('đọc số nguyên', () {
      final frame = parser.parse(toledoFrame(digits: '012340'));
      expect(frame!.weight, 12340);
      expect(frame.unit, 'kg');
      expect(frame.stable, isTrue);
    });

    test('đọc đúng vị trí dấu thập phân', () {
      expect(parser.parse(toledoFrame(digits: '012345', decimalCode: 3))!.weight, 1234.5);
      expect(parser.parse(toledoFrame(digits: '012345', decimalCode: 4))!.weight, 123.45);
    });

    test('cờ motion nghĩa là số cân chưa đứng yên', () {
      expect(parser.parse(toledoFrame(digits: '012340', motion: true))!.stable, isFalse);
    });

    test('đọc được số âm', () {
      expect(parser.parse(toledoFrame(digits: '000500', negative: true))!.weight, -500);
    });

    test('không nhận nhầm chuỗi ASCII thường thành khung Toledo', () {
      expect(parser.parse(ascii('ST,GS,+  12345 kg')), isNull);
    });
  });

  group('WeightParser — chế độ tự dò', () {
    final parser = WeightParser(const WeightParserConfig());

    test('nhận cả khung Toledo lẫn khung ASCII', () {
      expect(parser.parse(toledoFrame(digits: '020000'))!.weight, 20000);
      expect(parser.parse(ascii('ST,GS,+  9999 kg'))!.weight, 9999);
    });
  });

  group('WeightParser — regex tự khai', () {
    test('lấy số theo nhóm bắt do người dùng cấu hình', () {
      final parser = WeightParser(const WeightParserConfig(
        protocol: ScaleProtocol.custom,
        customPattern: r'W=(-?\d+)',
      ));
      expect(parser.parse(ascii('##W=15320##'))!.weight, 15320);
      expect(parser.parse(ascii('khong khop')), isNull);
    });
  });

  group('FrameAssembler', () {
    test('cắt khung theo CR/LF và ghép được khung bị chia làm nhiều lần đọc', () {
      final assembler = FrameAssembler();
      expect(assembler.add(ascii('ST,GS,+  100 kg\r\n')).length, 1);

      expect(assembler.add(ascii('ST,GS,+  2')), isEmpty);
      final frames = assembler.add(ascii('00 kg\r\n'));
      expect(frames.length, 1);
      expect(latin1.decode(frames.first), 'ST,GS,+  200 kg');
    });

    test('STX mở khung mới và bỏ phần dở dang trước đó', () {
      final assembler = FrameAssembler();
      final frames = assembler.add([...ascii('rac'), 0x02, ...ascii('ABC'), 0x0d]);
      expect(frames.length, 1);
      expect(frames.first.first, 0x02);
    });

    test('dữ liệu dài bất thường không sinh khung và không làm phình bộ đệm', () {
      final assembler = FrameAssembler(maxFrameLength: 8);
      // Sai baudrate hoặc nhiễu đường truyền: byte chảy về liên tục mà không
      // bao giờ có dấu kết thúc khung.
      expect(assembler.add(ascii('0123456789012345')), isEmpty);

      // Khi đường truyền tốt trở lại, khung hợp lệ vẫn đọc được bình thường.
      assembler.reset();
      final frames = assembler.add(ascii('100 kg\r'));
      expect(latin1.decode(frames.single), '100 kg');
    });
  });

  group('StabilityTracker', () {
    test('chỉ báo ổn định sau đủ số mẫu nằm trong ngưỡng', () {
      final tracker = StabilityTracker(tolerance: 5, requiredSamples: 3);
      expect(tracker.update(1000), isFalse);
      expect(tracker.update(1002), isFalse);
      expect(tracker.update(1004), isTrue);
    });

    test('số nhảy quá ngưỡng thì đếm lại từ đầu', () {
      final tracker = StabilityTracker(tolerance: 5, requiredSamples: 3);
      tracker.update(1000);
      tracker.update(1001);
      expect(tracker.update(2000), isFalse);
      expect(tracker.update(2001), isFalse);
      expect(tracker.update(2002), isTrue);
    });
  });
}
