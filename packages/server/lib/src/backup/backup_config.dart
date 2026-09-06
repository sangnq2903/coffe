import 'dart:convert';
import 'dart:io';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;

/// Cấu hình sao lưu lên đám mây.
///
/// **Nằm ở file riêng** `config.sao-luu.json` chứ không nằm trong file cấu hình
/// chính, và file đó đã bị gitignore. Lý do: `config.central.json` và
/// `config.station.json` đang được đưa lên git, mà khối này chứa chìa khoá kho
/// lưu trữ và mật khẩu mã hoá — lỡ tay commit một lần là chìa khoá nằm vĩnh
/// viễn trong lịch sử kho mã, đổi mật khẩu cũng không xoá được vết.
class BackupConfig {
  const BackupConfig({
    this.bat = false,
    this.url = '',
    this.token = '',
    this.matKhau = '',
    this.gioChay = 1,
    this.phutChay = 30,
    this.giuBan = 30,
    this.thuMucTam = 'data/sao-luu',
    this.giuBanTaiCho = 7,
  });

  factory BackupConfig.fromJson(Map<String, Object?> json) => BackupConfig(
        bat: asBool(json['bat']),
        url: asString(json['url']).trim(),
        token: asString(json['token']).trim(),
        matKhau: asString(json['mat_khau']),
        gioChay: asInt(json['gio_chay'], fallback: 1),
        phutChay: asInt(json['phut_chay'], fallback: 30),
        giuBan: asInt(json['giu_ban'], fallback: 30),
        thuMucTam: asString(json['thu_muc_tam'], fallback: 'data/sao-luu'),
        giuBanTaiCho: asInt(json['giu_ban_tai_cho'], fallback: 7),
      );

  /// Bật/tắt việc tự sao lưu. Tắt thì server chạy y như trước.
  final bool bat;

  /// Địa chỉ hàm nhận sao lưu, ví dụ `https://canxe-sao-luu.vercel.app/api/sao-luu`.
  final String url;

  /// Chìa khoá để hàm đó biết đúng máy mình gửi lên.
  final String token;

  /// Câu mật khẩu mã hoá gói sao lưu.
  ///
  /// **Mất câu này là mất luôn dữ liệu đã sao lưu** — không có cửa sau nào mở
  /// được, kể cả tôi. Chép ra giấy cất chỗ khác với cái máy chạy server.
  final String matKhau;

  /// Giờ và phút chạy sao lưu hằng ngày, giờ máy.
  final int gioChay;
  final int phutChay;

  /// Giữ bao nhiêu bản trên đám mây; quá số này thì bản cũ nhất bị xoá.
  final int giuBan;

  /// Thư mục chứa bản chụp tạm và bản giữ tại chỗ.
  final String thuMucTam;

  /// Giữ bao nhiêu bản ngay trên ổ đĩa máy chủ.
  ///
  /// Vẫn giữ tại chỗ dù đã đẩy lên mây: hỏng cơ sở dữ liệu lúc 8 giờ sáng mà
  /// mạng đứt thì bản ở ổ đĩa là thứ duy nhất dùng được ngay.
  final int giuBanTaiCho;

  /// Đủ điều kiện chạy chưa — thiếu một trong ba thứ này thì không đẩy được.
  bool get sanSang => bat && url.isNotEmpty && token.isNotEmpty && matKhau.isNotEmpty;

  List<String> thieuGi() {
    final t = <String>[];
    if (url.isEmpty) t.add('url');
    if (token.isEmpty) t.add('token');
    if (matKhau.isEmpty) t.add('mat_khau');
    return t;
  }

  String thuMucTamTuyetDoi(String goc) => p.isAbsolute(thuMucTam)
      ? thuMucTam
      : p.normalize(p.join(goc, thuMucTam));

  /// Đọc cấu hình sao lưu đặt cạnh file cấu hình chính.
  ///
  /// Không có file thì trả về cấu hình tắt — sao lưu là phần thêm, thiếu nó
  /// server vẫn phải cân xe bình thường.
  static BackupConfig load(String duongDanConfigChinh) {
    final file = File(p.join(p.dirname(duongDanConfigChinh), 'config.sao-luu.json'));
    var cfg = const BackupConfig();
    if (file.existsSync()) {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) {
        throw StateError('File "${file.path}" không phải đối tượng JSON hợp lệ.');
      }
      cfg = BackupConfig.fromJson(raw.cast<String, Object?>());
    }
    return cfg.voiBienMoiTruong();
  }

  /// Biến môi trường ghi đè file, để chạy thử hoặc để khai chìa khoá mà không
  /// phải viết nó xuống đĩa.
  BackupConfig voiBienMoiTruong() {
    final env = Platform.environment;
    String lay(String ten, String cu) {
      final v = env[ten];
      return v == null || v.isEmpty ? cu : v;
    }

    final urlMoi = lay('CANXE_SAO_LUU_URL', url);
    return BackupConfig(
      bat: bat || urlMoi != url,
      url: urlMoi,
      token: lay('CANXE_SAO_LUU_TOKEN', token),
      matKhau: lay('CANXE_SAO_LUU_MAT_KHAU', matKhau),
      gioChay: gioChay,
      phutChay: phutChay,
      giuBan: giuBan,
      thuMucTam: thuMucTam,
      giuBanTaiCho: giuBanTaiCho,
    );
  }
}
