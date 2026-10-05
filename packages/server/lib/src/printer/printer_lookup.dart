import 'dart:io';

import 'package:path/path.dart' as p;

class PrinterInfo {
  const PrinterInfo({required this.name, required this.isDefault});

  final String name;
  final bool isDefault;

  Map<String, Object?> toJson() => {'name': name, 'default': isDefault};
}

/// Danh sách máy in đã cài trên Windows, kèm máy mặc định. Rỗng nếu không phải Windows.
Future<List<PrinterInfo>> listPrinters() async {
  if (!Platform.isWindows) return const [];
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r'Get-CimInstance -ClassName Win32_Printer | ForEach-Object { '
            r'if ($_.Default) { "D|" + $_.Name } else { "N|" + $_.Name } }',
      ],
      stdoutEncoding: SystemEncoding(),
    );
    if (result.exitCode != 0) return const [];
    return (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .where((line) => line.length > 2)
        .map((line) => PrinterInfo(name: line.substring(2), isDefault: line.startsWith('D|')))
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<PrinterInfo?> defaultPrinter() async {
  final all = await listPrinters();
  for (final printer in all) {
    if (printer.isDefault) return printer;
  }
  return null;
}

/// In một file PDF ra máy in đã chỉ định qua verb PrintTo của trình xem PDF
/// (Acrobat trên trạm). Tên máy in phải nằm trong danh sách máy đã cài, không
/// nhận chuỗi tuỳ ý từ client.
Future<void> printPdfTo(List<int> pdf, String printerName) async {
  if (!Platform.isWindows) {
    throw StateError('Chỉ in trực tiếp được trên máy trạm Windows.');
  }
  final installed = await listPrinters();
  if (!installed.any((printer) => printer.name == printerName)) {
    throw ArgumentError('Không có máy in "$printerName" trên máy chủ này.');
  }

  final dir = Directory(p.join(Directory.systemTemp.path, 'canxe-in'));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, 'phieu-${DateTime.now().microsecondsSinceEpoch}.pdf'));
  await file.writeAsBytes(pdf, flush: true);

  final result = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-Command',
      r'Start-Process -FilePath $env:CANXE_PDF -Verb PrintTo -ArgumentList $env:CANXE_MAY_IN -WindowStyle Hidden',
    ],
    environment: {'CANXE_PDF': file.path, 'CANXE_MAY_IN': '"$printerName"'},
  );
  if (result.exitCode != 0) {
    throw StateError('Không gửi được lệnh in tới "$printerName": ${result.stderr}');
  }
  Future<void>.delayed(const Duration(minutes: 2), () {
    if (file.existsSync()) file.deleteSync();
  });
}
