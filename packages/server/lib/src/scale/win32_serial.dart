// ignore_for_file: non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Khai báo FFI tối thiểu cho API cổng COM của Windows.
///
/// Gọi thẳng `kernel32.dll` thay vì dùng thư viện serial của bên thứ ba: máy ở
/// kho chỉ cần chép thư mục chương trình sang là chạy, không phải kèm DLL nào.

/// Cấu trúc DCB (28 byte) mô tả tham số truyền của cổng COM.
final class _Dcb extends Struct {
  @Uint32()
  external int DCBlength;
  @Uint32()
  external int BaudRate;

  /// Gộp toàn bộ cờ bit (fBinary, fParity, fDtrControl, fRtsControl...).
  @Uint32()
  external int flags;
  @Uint16()
  external int wReserved;
  @Uint16()
  external int XonLim;
  @Uint16()
  external int XoffLim;
  @Uint8()
  external int ByteSize;
  @Uint8()
  external int Parity;
  @Uint8()
  external int StopBits;
  @Int8()
  external int XonChar;
  @Int8()
  external int XoffChar;
  @Int8()
  external int ErrorChar;
  @Int8()
  external int EofChar;
  @Int8()
  external int EvtChar;
  @Uint16()
  external int wReserved1;
}

final class _CommTimeouts extends Struct {
  @Uint32()
  external int ReadIntervalTimeout;
  @Uint32()
  external int ReadTotalTimeoutMultiplier;
  @Uint32()
  external int ReadTotalTimeoutConstant;
  @Uint32()
  external int WriteTotalTimeoutMultiplier;
  @Uint32()
  external int WriteTotalTimeoutConstant;
}

// Kiểu FFI phải khai riêng cho từng hàm: `lookupFunction` không nhận typedef
// có tham số kiểu (generic), và phía Dart luôn dùng `int` cho HANDLE/DWORD.
typedef _CreateFileWNative = IntPtr Function(
    Pointer<Utf16>, Uint32, Uint32, Pointer<Void>, Uint32, Uint32, IntPtr);
typedef _CreateFileWDart = int Function(
    Pointer<Utf16>, int, int, Pointer<Void>, int, int, int);

typedef _CommStateNative = Int32 Function(IntPtr, Pointer<_Dcb>);
typedef _CommStateDart = int Function(int, Pointer<_Dcb>);

typedef _CommTimeoutsNative = Int32 Function(IntPtr, Pointer<_CommTimeouts>);
typedef _CommTimeoutsDart = int Function(int, Pointer<_CommTimeouts>);

typedef _ReadFileNative = Int32 Function(
    IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>);
typedef _ReadFileDart = int Function(
    int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>);

typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

typedef _PurgeCommNative = Int32 Function(IntPtr, Uint32);
typedef _PurgeCommDart = int Function(int, int);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

class _Kernel32 {
  _Kernel32._(DynamicLibrary lib)
      : createFileW = lib.lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW'),
        getCommState =
            lib.lookupFunction<_CommStateNative, _CommStateDart>('GetCommState'),
        setCommState =
            lib.lookupFunction<_CommStateNative, _CommStateDart>('SetCommState'),
        setCommTimeouts =
            lib.lookupFunction<_CommTimeoutsNative, _CommTimeoutsDart>('SetCommTimeouts'),
        readFile = lib.lookupFunction<_ReadFileNative, _ReadFileDart>('ReadFile'),
        closeHandle = lib.lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle'),
        purgeComm = lib.lookupFunction<_PurgeCommNative, _PurgeCommDart>('PurgeComm'),
        getLastError =
            lib.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');

  static final _Kernel32 instance = _Kernel32._(DynamicLibrary.open('kernel32.dll'));

  final _CreateFileWDart createFileW;
  final _CommStateDart getCommState;
  final _CommStateDart setCommState;
  final _CommTimeoutsDart setCommTimeouts;
  final _ReadFileDart readFile;
  final _CloseHandleDart closeHandle;
  final _PurgeCommDart purgeComm;
  final _GetLastErrorDart getLastError;
}

const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _openExisting = 3;
const int _invalidHandleValue = -1;
const int _purgeRxClear = 0x0008;
const int _purgeTxClear = 0x0004;

/// Lỗi mở/đọc cổng COM, đã dịch sang thông điệp người dùng hiểu được.
class SerialPortException implements Exception {
  SerialPortException(this.message, {this.errorCode});

  final String message;
  final int? errorCode;

  @override
  String toString() => message;
}

/// Cổng COM đang mở, đọc theo kiểu chặn (blocking) — phải chạy trong Isolate
/// riêng để không làm treo vòng lặp sự kiện của server.
class Win32SerialPort {
  Win32SerialPort._(this._handle, this.portName);

  final int _handle;
  final String portName;
  bool _closed = false;

  /// Mở cổng COM với tham số truyền cho trước.
  ///
  /// Tên cổng luôn được viết dưới dạng `\\.\COMx`: dạng ngắn `COM10` trở lên
  /// không mở được bằng CreateFile.
  static Win32SerialPort open(
    String portName, {
    int baudRate = 9600,
    int dataBits = 8,
    int stopBits = 1,
    String parity = 'none',
  }) {
    if (!Platform.isWindows) {
      throw SerialPortException('Đọc cổng COM hiện chỉ hỗ trợ trên Windows.');
    }
    final k = _Kernel32.instance;
    final normalized = portName.toUpperCase().startsWith(r'\\.\')
        ? portName
        : r'\\.\' + portName.toUpperCase();
    final namePtr = normalized.toNativeUtf16();
    try {
      final handle = k.createFileW(
        namePtr,
        _genericRead | _genericWrite,
        0, // không chia sẻ: chỉ một tiến trình được giữ cổng COM
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (handle == _invalidHandleValue) {
        final code = k.getLastError();
        throw SerialPortException(
          _describeOpenError(code, portName),
          errorCode: code,
        );
      }
      final port = Win32SerialPort._(handle, portName.toUpperCase());
      try {
        port._configure(
          baudRate: baudRate,
          dataBits: dataBits,
          stopBits: stopBits,
          parity: parity,
        );
      } catch (_) {
        port.close();
        rethrow;
      }
      return port;
    } finally {
      calloc.free(namePtr);
    }
  }

  static String _describeOpenError(int code, String portName) {
    switch (code) {
      case 2:
        return 'Không tìm thấy cổng $portName. Kiểm tra lại cáp và Device Manager.';
      case 5:
        return 'Cổng $portName đang bị chương trình khác chiếm giữ '
            '(phần mềm cân cũ, PuTTY...). Hãy đóng chương trình đó rồi thử lại.';
      default:
        return 'Không mở được cổng $portName (mã lỗi Windows $code).';
    }
  }

  void _configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required String parity,
  }) {
    final k = _Kernel32.instance;
    final dcb = calloc<_Dcb>();
    final timeouts = calloc<_CommTimeouts>();
    try {
      dcb.ref.DCBlength = sizeOf<_Dcb>();
      if (k.getCommState(_handle, dcb) == 0) {
        throw SerialPortException(
          'Không đọc được cấu hình cổng $portName (mã lỗi ${k.getLastError()}).',
        );
      }
      dcb.ref.BaudRate = baudRate;
      dcb.ref.ByteSize = dataBits;
      dcb.ref.Parity = _parityCode(parity);
      dcb.ref.StopBits = _stopBitsCode(stopBits);
      // fBinary = 1, fDtrControl = ENABLE (bit 4), fRtsControl = ENABLE (bit 12).
      // Nhiều đầu cân lấy nguồn tín hiệu từ DTR/RTS nên phải bật, và không dùng
      // bắt tay phần cứng vì đầu cân chỉ phát một chiều.
      dcb.ref.flags = 0x00000001 | (1 << 4) | (1 << 12);

      if (k.setCommState(_handle, dcb) == 0) {
        throw SerialPortException(
          'Không đặt được tham số cho cổng $portName '
          '(baud $baudRate, ${dataBits}${parity[0].toUpperCase()}$stopBits) — '
          'mã lỗi ${k.getLastError()}.',
        );
      }

      // Chờ tối đa 200ms mỗi lần đọc: đủ ngắn để dừng server nhanh, đủ dài để
      // không quay vòng tốn CPU khi đầu cân im lặng.
      timeouts.ref.ReadIntervalTimeout = 30;
      timeouts.ref.ReadTotalTimeoutMultiplier = 0;
      timeouts.ref.ReadTotalTimeoutConstant = 200;
      timeouts.ref.WriteTotalTimeoutMultiplier = 0;
      timeouts.ref.WriteTotalTimeoutConstant = 200;
      if (k.setCommTimeouts(_handle, timeouts) == 0) {
        throw SerialPortException(
          'Không đặt được thời gian chờ cho cổng $portName (mã lỗi ${k.getLastError()}).',
        );
      }
      k.purgeComm(_handle, _purgeRxClear | _purgeTxClear);
    } finally {
      calloc.free(dcb);
      calloc.free(timeouts);
    }
  }

  static int _parityCode(String parity) {
    switch (parity.toLowerCase()) {
      case 'odd':
        return 1;
      case 'even':
        return 2;
      case 'mark':
        return 3;
      case 'space':
        return 4;
      default:
        return 0; // none
    }
  }

  static int _stopBitsCode(int stopBits) => stopBits == 2 ? 2 : 0; // 0 = 1 bit, 2 = 2 bit

  /// Đọc dữ liệu có sẵn. Trả về mảng rỗng khi hết thời gian chờ mà không có byte
  /// nào — đó là trạng thái bình thường, không phải lỗi.
  Uint8List read({int maxBytes = 512}) {
    if (_closed) return Uint8List(0);
    final k = _Kernel32.instance;
    final buffer = calloc<Uint8>(maxBytes);
    final readCount = calloc<Uint32>();
    try {
      final ok = k.readFile(_handle, buffer, maxBytes, readCount, nullptr);
      if (ok == 0) {
        throw SerialPortException(
          'Mất kết nối với cổng $portName (mã lỗi ${k.getLastError()}).',
        );
      }
      final n = readCount.value;
      if (n == 0) return Uint8List(0);
      return Uint8List.fromList(buffer.asTypedList(n));
    } finally {
      calloc.free(buffer);
      calloc.free(readCount);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _Kernel32.instance.closeHandle(_handle);
  }
}

/// Liệt kê cổng COM đang có trên máy, đọc từ registry SERIALCOMM.
///
/// Dùng `reg query` thay vì FFI registry cho gọn — đây là thao tác hiếm, chỉ
/// chạy khi người dùng mở màn hình cấu hình để chọn cổng.
Future<List<String>> listSerialPorts() async {
  if (!Platform.isWindows) return const [];
  try {
    final result = await Process.run(
      'reg',
      ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
      stdoutEncoding: SystemEncoding(),
    );
    if (result.exitCode != 0) return const [];
    final ports = <String>[];
    for (final line in (result.stdout as String).split('\n')) {
      final match = RegExp(r'REG_SZ\s+(COM\d+)').firstMatch(line);
      if (match != null) ports.add(match.group(1)!);
    }
    ports.sort((a, b) =>
        int.parse(a.substring(3)).compareTo(int.parse(b.substring(3))));
    return ports;
  } catch (_) {
    return const [];
  }
}
