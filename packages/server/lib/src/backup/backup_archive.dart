import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Lỗi khi mở một gói sao lưu: sai mật khẩu, file hỏng, hoặc không phải gói.
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Phần mô tả đi kèm mỗi gói sao lưu, để **đọc được mà không cần mật khẩu**.
///
/// Nhờ vậy xem danh sách bản sao lưu trên đám mây vẫn biết bản nào của ngày
/// nào, của máy nào, mà không phải tải cả gói về rồi giải mã.
class BackupMeta {
  const BackupMeta({
    required this.tenGoc,
    required this.luc,
    required this.may,
    required this.kichThuocGoc,
    required this.sha256Goc,
    this.vong = BackupArchive.vongMacDinh,
  });

  factory BackupMeta.fromJson(Map<String, Object?> json) => BackupMeta(
        tenGoc: asString(json['ten_goc'], fallback: 'canxe.db'),
        luc: asTimeOrNull(json['luc']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        may: asString(json['may']),
        kichThuocGoc: asInt(json['kich_thuoc_goc']),
        sha256Goc: asString(json['sha256_goc']),
        vong: asInt(json['vong'], fallback: BackupArchive.vongMacDinh),
      );

  /// Tên file cơ sở dữ liệu gốc, ví dụ `canxe-central.db`.
  final String tenGoc;

  /// Lúc chụp bản sao.
  final DateTime luc;

  /// Máy nào tạo ra bản này — trung tâm hay trạm nào.
  final String may;

  /// Cỡ file gốc tính bằng byte, trước khi nén.
  final int kichThuocGoc;

  /// Mã kiểm tra của file gốc, để lúc khôi phục biết chắc không sai byte nào.
  final String sha256Goc;

  /// Số vòng PBKDF2 đã dùng. Ghi lại để sau này tăng lên vẫn mở được gói cũ.
  final int vong;

  Map<String, Object?> toJson() => {
        'ten_goc': tenGoc,
        'luc': timeToMillis(luc),
        'may': may,
        'kich_thuoc_goc': kichThuocGoc,
        'sha256_goc': sha256Goc,
        'vong': vong,
      };

  /// Tên gói. Đặt theo thời gian trước để sắp xếp theo tên là ra đúng thứ tự
  /// thời gian — kho lưu trữ đám mây trả danh sách theo tên chứ không theo ngày.
  String get tenGoi {
    String hai(int v) => v.toString().padLeft(2, '0');
    final t = luc.toUtc();
    return '${t.year}${hai(t.month)}${hai(t.day)}'
        '-${hai(t.hour)}${hai(t.minute)}${hai(t.second)}'
        '-${may.isEmpty ? 'may' : may.toLowerCase()}';
  }
}

/// Đóng gói cơ sở dữ liệu thành một file **nén và mã hoá**, và mở ngược lại.
///
/// Vì sao phải mã hoá: gói này nằm trên máy chủ của một công ty khác, và địa
/// chỉ tải về của kho lưu trữ đám mây là địa chỉ công khai — ai có đường dẫn là
/// tải được. Trong cơ sở dữ liệu có lương từng người và sổ mua bán (giá vốn,
/// lãi từng chuyến) — thứ mà trong phần mềm chỉ tài khoản chủ mới xem được. Đẩy
/// nguyên bản lên là tự tay phá bỏ chính giới hạn đó.
///
/// Cách làm: nén gzip, mã hoá AES-256-CTR, rồi ký HMAC-SHA256 lên toàn bộ (mã
/// hoá trước, ký sau). Ký để phát hiện file bị sửa hoặc tải thiếu — không ký
/// thì gói hỏng vẫn "giải mã" ra được, chỉ là ra rác, và tới lúc khôi phục mới
/// vỡ lẽ, đúng lúc không còn gì để mà sửa.
abstract final class BackupArchive {
  /// Chữ ký nhận dạng ở đầu file: "CANXE-SL".
  static const List<int> magic = [0x43, 0x41, 0x4E, 0x58, 0x45, 0x2D, 0x53, 0x4C];
  static const int phienBan = 1;
  static const int vongMacDinh = 200000;

  static const int _daiSalt = 16;
  static const int _daiIv = 16;
  static const int _daiTag = 32;

  static final Random _random = Random.secure();

  static Uint8List _nhieuNgauNhien(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  /// Nén và mã hoá [duLieu] thành một gói sao lưu hoàn chỉnh.
  static Uint8List dongGoi({
    required List<int> duLieu,
    required String matKhau,
    required String tenGoc,
    required String may,
    DateTime? luc,
    int vong = vongMacDinh,
  }) {
    if (matKhau.isEmpty) {
      throw BackupException('Chưa đặt mật khẩu sao lưu.');
    }

    final meta = BackupMeta(
      tenGoc: tenGoc,
      luc: luc ?? DateTime.now(),
      may: may,
      kichThuocGoc: duLieu.length,
      sha256Goc: sha256.convert(duLieu).toString(),
      vong: vong,
    );

    final nen = Uint8List.fromList(gzip.encode(duLieu));
    final salt = _nhieuNgauNhien(_daiSalt);
    final iv = _nhieuNgauNhien(_daiIv);
    final (khoaMa, khoaKy) = _sinhKhoa(matKhau, salt, vong);

    final ct = _aesCtr(khoaMa, iv, nen);
    final dau = _dungDau(meta, salt, iv);
    final tag = Hmac(sha256, khoaKy).convert([...dau, ...ct]).bytes;

    return Uint8List.fromList([...dau, ...tag, ...ct]);
  }

  /// Mở một gói sao lưu, trả về phần mô tả và nội dung cơ sở dữ liệu gốc.
  static (BackupMeta, Uint8List) moGoi({
    required List<int> goi,
    required String matKhau,
  }) {
    final bytes = goi is Uint8List ? goi : Uint8List.fromList(goi);
    final meta = docMeta(bytes);

    final viTri = _viTriSauMeta(bytes);
    final dauTag = viTri + _daiSalt + _daiIv;
    if (bytes.length < dauTag + _daiTag) {
      throw BackupException('Gói sao lưu bị cắt cụt.');
    }
    final salt = bytes.sublist(viTri, viTri + _daiSalt);
    final iv = bytes.sublist(viTri + _daiSalt, dauTag);
    final tag = bytes.sublist(dauTag, dauTag + _daiTag);
    final ct = bytes.sublist(dauTag + _daiTag);

    final (khoaMa, khoaKy) = _sinhKhoa(matKhau, salt, meta.vong);
    final tagThat = Hmac(sha256, khoaKy).convert([...bytes.sublist(0, dauTag), ...ct]).bytes;

    // Kiểm chữ ký TRƯỚC khi giải mã. Sai mật khẩu và file hỏng đều dừng ở đây,
    // nên không bao giờ có chuyện ghi đè cơ sở dữ liệu bằng một đống rác.
    if (!_bangNhau(tag, tagThat)) {
      throw BackupException(
        'Không mở được gói sao lưu: sai mật khẩu, hoặc file đã hỏng / tải thiếu.',
      );
    }

    final Uint8List goc;
    try {
      goc = Uint8List.fromList(gzip.decode(_aesCtr(khoaMa, iv, ct)));
    } catch (e) {
      throw BackupException('Gói sao lưu giải nén không được: $e');
    }

    if (sha256.convert(goc).toString() != meta.sha256Goc) {
      throw BackupException('Nội dung sau khi giải mã không khớp mã kiểm tra.');
    }
    return (meta, goc);
  }

  /// Đọc phần mô tả ở đầu gói — **không cần mật khẩu**.
  static BackupMeta docMeta(List<int> goi) {
    final bytes = goi is Uint8List ? goi : Uint8List.fromList(goi);
    if (bytes.length < magic.length + 3) {
      throw BackupException('File quá ngắn, không phải gói sao lưu.');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw BackupException('Đây không phải gói sao lưu của phần mềm cân xe.');
      }
    }
    final ver = bytes[magic.length];
    if (ver != phienBan) {
      throw BackupException(
        'Gói sao lưu phiên bản $ver, phần mềm này chỉ đọc được phiên bản $phienBan.',
      );
    }
    final daiMeta = (bytes[magic.length + 1] << 8) | bytes[magic.length + 2];
    final batDau = magic.length + 3;
    if (bytes.length < batDau + daiMeta) {
      throw BackupException('Gói sao lưu bị cắt cụt ở phần mô tả.');
    }
    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(bytes.sublist(batDau, batDau + daiMeta)));
    } catch (e) {
      throw BackupException('Phần mô tả của gói đọc không được: $e');
    }
    if (raw is! Map) throw BackupException('Phần mô tả của gói không hợp lệ.');
    return BackupMeta.fromJson(raw.cast<String, Object?>());
  }

  // -------------------------------------------------------------- bên trong

  static int _viTriSauMeta(Uint8List bytes) =>
      magic.length + 3 + ((bytes[magic.length + 1] << 8) | bytes[magic.length + 2]);

  static List<int> _dungDau(BackupMeta meta, Uint8List salt, Uint8List iv) {
    final metaBytes = utf8.encode(jsonEncode(meta.toJson()));
    if (metaBytes.length > 0xFFFF) {
      throw BackupException('Phần mô tả của gói dài bất thường.');
    }
    return [
      ...magic,
      phienBan,
      (metaBytes.length >> 8) & 0xFF,
      metaBytes.length & 0xFF,
      ...metaBytes,
      ...salt,
      ...iv,
    ];
  }

  /// Một câu mật khẩu ra hai khoá tách biệt: một để mã hoá, một để ký.
  ///
  /// Dùng chung một khoá cho cả hai việc là lỗi kinh điển — hai thuật toán soi
  /// vào nhau có thể làm lộ khoá. Rút 64 byte rồi cắt đôi thì rẻ ngang rút 32.
  static (Uint8List, Uint8List) _sinhKhoa(String matKhau, List<int> salt, int vong) {
    final k = PasswordHasher.deriveKey(matKhau, salt, iterations: vong, length: 64);
    return (Uint8List.sublistView(k, 0, 32), Uint8List.sublistView(k, 32, 64));
  }

  /// AES-256 chế độ CTR. Cùng một hàm cho cả mã hoá lẫn giải mã: CTR chỉ là XOR
  /// dữ liệu với một dòng byte sinh ra từ khoá và IV.
  static Uint8List _aesCtr(Uint8List khoa, Uint8List iv, Uint8List duLieu) {
    final cipher = CTRStreamCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(khoa), iv));
    return cipher.process(duLieu);
  }

  /// So sánh không phụ thuộc nội dung, để không lộ dần chữ ký đúng qua thời gian.
  static bool _bangNhau(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
