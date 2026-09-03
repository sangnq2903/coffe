import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:canxe_server/canxe_server.dart';

/// Công cụ dò cổng COM: nghe thử đầu cân rồi in ra đúng những gì nhận được.
///
/// Dùng khi đấu đầu cân mới mà màn hình không lên số. Công cụ thử lần lượt các
/// tốc độ truyền thông dụng, in dữ liệu thô kèm mã hex, rồi thử giải mã bằng cả
/// ba giao thức để gợi ý cấu hình đúng — thay vì phải mò từng thông số.
///
///   dart run bin/do_cong.dart COM5
///   dart run bin/do_cong.dart COM5 --baud 9600 --seconds 10
Future<void> main(List<String> arguments) async {
  enableUtf8Console();

  final parser = ArgParser()
    ..addOption('baud', abbr: 'b', help: 'Chỉ thử một tốc độ truyền cụ thể.')
    ..addOption('seconds', abbr: 's', defaultsTo: '4', help: 'Số giây nghe mỗi tốc độ.')
    ..addOption('data-bits', defaultsTo: '8')
    ..addOption('stop-bits', defaultsTo: '1')
    ..addOption('parity', defaultsTo: 'none', allowed: ['none', 'odd', 'even', 'mark', 'space'])
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args.flag('help') || args.rest.isEmpty) {
    stdout
      ..writeln('Dò cổng COM của đầu cân.\n')
      ..writeln('Cách dùng: dart run bin/do_cong.dart <CỔNG> [tuỳ chọn]')
      ..writeln('Ví dụ:     dart run bin/do_cong.dart COM5\n')
      ..writeln(parser.usage)
      ..writeln('\nCổng COM đang có trên máy: ${(await listSerialPorts()).join(", ")}');
    return;
  }

  final portName = args.rest.first.toUpperCase();
  final seconds = int.tryParse(args.option('seconds')!) ?? 4;
  final singleBaud = int.tryParse(args.option('baud') ?? '');

  // Xếp theo mức phổ biến ở đầu cân Việt Nam để tìm ra sớm.
  final bauds = singleBaud != null ? [singleBaud] : const [9600, 4800, 19200, 2400, 38400, 57600, 115200];

  stdout
    ..writeln('')
    ..writeln('  DÒ CỔNG $portName — ${args.option('data-bits')}'
        '${args.option('parity')!.substring(0, 1).toUpperCase()}${args.option('stop-bits')}')
    ..writeln('  ${'=' * 66}');

  final results = <_Result>[];
  for (final baud in bauds) {
    stdout.write('  ${baud.toString().padLeft(6)} baud ... ');
    final result = await _listen(
      portName: portName,
      baudRate: baud,
      dataBits: int.parse(args.option('data-bits')!),
      stopBits: int.parse(args.option('stop-bits')!),
      parity: args.option('parity')!,
      duration: Duration(seconds: seconds),
    );
    results.add(result);
    stdout.writeln(result.headline);
    if (result.openError != null) break; // Không mở được cổng thì thử tiếp cũng vô ích.
  }

  _report(results, portName);
}

class _Result {
  _Result(this.baudRate);

  final int baudRate;
  String? openError;
  final List<int> bytes = [];
  final List<List<int>> frames = [];

  String get headline {
    if (openError != null) return 'LỖI: $openError';
    if (bytes.isEmpty) return 'không nhận được byte nào';
    return '${bytes.length} byte, ${frames.length} khung';
  }

  /// Tỷ lệ byte in được — chỉ dùng để tham khảo khi không giải mã được khung
  /// nào; sai tốc độ thì phần lớn byte sẽ là rác ngoài dải in được.
  double get printableRatio {
    if (bytes.isEmpty) return 0;
    final printable = bytes.where((b) => (b >= 0x20 && b < 0x7f) || b == 0x02 || b == 0x03 || b == 0x0d || b == 0x0a).length;
    return printable / bytes.length;
  }

  /// Giao thức nào giải mã được bao nhiêu khung ở tốc độ này.
  Map<ScaleProtocol, List<double>> get decoded {
    final source = frames.isEmpty ? [bytes] : frames;
    final result = <ScaleProtocol, List<double>>{};
    for (final protocol in const [ScaleProtocol.keli, ScaleProtocol.toledo, ScaleProtocol.ascii]) {
      final parser = WeightParser(WeightParserConfig(protocol: protocol));
      final values =
          source.map(parser.parse).whereType<WeightFrame>().map((f) => f.weight).toList();
      if (values.isNotEmpty) result[protocol] = values;
    }
    return result;
  }

  /// Số khung giải mã được nhiều nhất trong các giao thức.
  ///
  /// Đây mới là thước đo đúng để chọn tốc độ truyền: đường truyền có thể lẫn
  /// nhiễu làm tỷ lệ byte in được thấp, nhưng chỉ tốc độ đúng mới cho ra khung
  /// hợp lệ (giao thức Keli còn có checksum nên gần như không thể ăn may).
  int get bestDecodedCount =>
      decoded.values.fold(0, (best, values) => values.length > best ? values.length : best);

  ScaleProtocol? get bestProtocol {
    ScaleProtocol? best;
    var count = 0;
    decoded.forEach((protocol, values) {
      if (values.length > count) {
        count = values.length;
        best = protocol;
      }
    });
    return best;
  }
}

Future<_Result> _listen({
  required String portName,
  required int baudRate,
  required int dataBits,
  required int stopBits,
  required String parity,
  required Duration duration,
}) async {
  final result = _Result(baudRate);
  Win32SerialPort? port;
  try {
    port = Win32SerialPort.open(
      portName,
      baudRate: baudRate,
      dataBits: dataBits,
      stopBits: stopBits,
      parity: parity,
    );
  } catch (e) {
    result.openError = '$e';
    return result;
  }

  final assembler = FrameAssembler();
  final deadline = DateTime.now().add(duration);
  try {
    while (DateTime.now().isBefore(deadline)) {
      final chunk = port.read();
      if (chunk.isNotEmpty) {
        result.bytes.addAll(chunk);
        result.frames.addAll(assembler.add(chunk));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  } catch (e) {
    result.openError = '$e';
  } finally {
    port.close();
    // Windows cần một nhịp để nhả cổng trước khi mở lại ở tốc độ khác.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return result;
}

void _report(List<_Result> results, String portName) {
  stdout.writeln('  ${'=' * 66}\n');

  final failed = results.where((r) => r.openError != null).toList();
  if (failed.isNotEmpty && results.every((r) => r.bytes.isEmpty)) {
    stdout
      ..writeln('  KHÔNG MỞ ĐƯỢC CỔNG $portName')
      ..writeln('  ${failed.first.openError}')
      ..writeln('')
      ..writeln('  Cần kiểm tra:')
      ..writeln('   1. Máy chủ trạm cân đang chạy có đang giữ cổng này không —')
      ..writeln('      hãy tắt nó rồi chạy lại lệnh dò.')
      ..writeln('   2. Phần mềm cân cũ, PuTTY, Hercules... có đang mở cổng không.')
      ..writeln('   3. Device Manager > Ports (COM & LPT) xem cổng còn đó không.');
    return;
  }

  // Xếp hạng theo số khung giải mã được trước, chỉ khi hoà mới xét tới tỷ lệ
  // byte in được.
  final withData = results.where((r) => r.bytes.isNotEmpty).toList()
    ..sort((a, b) {
      final byDecoded = b.bestDecodedCount.compareTo(a.bestDecodedCount);
      return byDecoded != 0 ? byDecoded : b.printableRatio.compareTo(a.printableRatio);
    });

  if (withData.isEmpty) {
    stdout
      ..writeln('  MỞ ĐƯỢC CỔNG NHƯNG KHÔNG CÓ DỮ LIỆU')
      ..writeln('')
      ..writeln('  Đầu cân không tự phát. Cần kiểm tra:')
      ..writeln('   1. Đầu cân đã bật chế độ truyền liên tục (continuous output)')
      ..writeln('      chưa — nhiều đầu cân mặc định chỉ gửi khi bấm nút PRINT.')
      ..writeln('   2. Cáp có đúng loại không (thẳng / chéo), chân TX-RX có đảo không.')
      ..writeln('   3. Thử bấm nút PRINT trên đầu cân trong lúc lệnh này đang chạy.')
      ..writeln('   4. Thử đảo tham số: --parity even --data-bits 7');
    return;
  }

  for (final result in withData.take(3)) {
    stdout
      ..writeln('  ── ${result.baudRate} baud ${'─' * 48}')
      ..writeln('     Nhận: ${result.bytes.length} byte • ${result.frames.length} khung • '
          'đọc được ${(result.printableRatio * 100).toStringAsFixed(0)}%');

    final samples = result.frames.take(3).toList();
    if (samples.isEmpty && result.bytes.isNotEmpty) {
      samples.add(result.bytes.take(40).toList());
    }
    for (final frame in samples) {
      stdout
        ..writeln('     Chuỗi: "${_printable(frame)}"')
        ..writeln('     Hex  : ${_hex(frame)}');
    }
    _suggest(result);
    stdout.writeln('');
  }

  final best = withData.first;
  if (best.bestDecodedCount == 0) {
    stdout
      ..writeln('  ${'=' * 66}')
      ..writeln('  CÓ DỮ LIỆU NHƯNG KHÔNG GIẢI MÃ ĐƯỢC KHUNG NÀO')
      ..writeln('')
      ..writeln('  Nhiều khả năng chưa đúng tốc độ truyền, hoặc đầu cân dùng giao')
      ..writeln('  thức lạ. Xem chuỗi thô ở trên rồi:')
      ..writeln('   • Thử tham số khác: --parity even --data-bits 7')
      ..writeln('   • Hoặc khai regex riêng: "protocol": "custom", "custom_pattern": "..."')
      ..writeln('   • Đối chiếu chuỗi thô với tài liệu của đầu cân.');
    return;
  }

  stdout
    ..writeln('  ${'=' * 66}')
    ..writeln('  Sửa mục "scale" trong file cấu hình của trạm thành:')
    ..writeln('')
    ..writeln('    "scale": {')
    ..writeln('      "port": "$portName",')
    ..writeln('      "baud_rate": ${best.baudRate},')
    ..writeln('      "protocol": "${best.bestProtocol!.value}",')
    ..writeln('      "simulate": false')
    ..writeln('    }')
    ..writeln('')
    ..writeln('  Số cân đọc thử được: '
        '${best.decoded[best.bestProtocol]!.toSet().take(5).map((v) => v.toStringAsFixed(1)).join(", ")}')
    ..writeln('  Nếu số hiện ra sai 10 lần thì thêm "divisor": 10.');
}

/// In ra giao thức nào đọc được số gì ở tốc độ này.
void _suggest(_Result result) {
  result.decoded.forEach((protocol, values) {
    final unique = values.toSet().toList()..sort();
    stdout.writeln('     → protocol "${protocol.value}": ${values.length} khung, đọc ra '
        '${unique.take(6).map((v) => v.toStringAsFixed(1)).join(", ")}'
        '${unique.length > 6 ? "..." : ""}');
  });
}

String _printable(List<int> bytes) => bytes
    .map((b) => b == 0x02
        ? '<STX>'
        : b == 0x03
            ? '<ETX>'
            : b == 0x0d
                ? '<CR>'
                : b == 0x0a
                    ? '<LF>'
                    : (b >= 0x20 && b < 0x7f)
                        ? latin1.decode([b])
                        : '<${b.toRadixString(16).padLeft(2, '0')}>')
    .join();

String _hex(List<int> bytes) =>
    bytes.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
