import 'dart:io';

/// Tên máy in mặc định của Windows — hiện lên màn hình in phiếu để người dùng
/// biết trước sẽ in ra máy nào, đỡ phải mở Devices and Printers để kiểm tra.
Future<String?> defaultPrinterName() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r'(Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Default }).Name',
      ],
      stdoutEncoding: SystemEncoding(),
    );
    if (result.exitCode != 0) return null;
    final name = (result.stdout as String).trim();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}
