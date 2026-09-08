import '../json_utils.dart';

/// Vài con số mô tả một cơ sở dữ liệu — của máy đang chạy, hoặc của một file
/// vừa chọn để nhập.
class DuLieuTomTat {
  const DuLieuTomTat({
    this.bang = const {},
    this.bytes = 0,
    this.moiNhat,
  });

  factory DuLieuTomTat.fromJson(Map<String, Object?> json) => DuLieuTomTat(
        bang: {
          for (final e in ((json['bang'] as Map?) ?? const {}).entries)
            e.key.toString(): asInt(e.value),
        },
        bytes: asInt(json['bytes']),
        moiNhat: asTimeOrNull(json['moi_nhat']),
      );

  /// Số dòng từng bảng, khoá đã là tên tiếng Việt để hiện thẳng ra.
  final Map<String, int> bang;

  /// Cỡ file cơ sở dữ liệu.
  final int bytes;

  /// Bản ghi được sửa gần đây nhất — trả lời câu "dữ liệu này mới tới đâu".
  final DateTime? moiNhat;

  int get tongDong => bang.values.fold(0, (t, e) => t + e);

  /// Chỉ những bảng có dữ liệu. Bảng rỗng bày ra chỉ làm loãng màn hình.
  Map<String, int> get bangCoDuLieu =>
      {for (final e in bang.entries) if (e.value > 0) e.key: e.value};

  String get coFile {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }
}

/// Kết quả một lần nhập dữ liệu.
class KetQuaNhapDuLieu {
  const KetQuaNhapDuLieu({
    this.nguon = const DuLieuTomTat(),
    this.sau = const DuLieuTomTat(),
    this.themMoi = const {},
    this.duongDanAnToan = '',
  });

  factory KetQuaNhapDuLieu.fromJson(Map<String, Object?> json) => KetQuaNhapDuLieu(
        nguon: DuLieuTomTat.fromJson(
            ((json['nguon'] as Map?) ?? const {}).cast<String, Object?>()),
        sau: DuLieuTomTat.fromJson(
            ((json['sau'] as Map?) ?? const {}).cast<String, Object?>()),
        themMoi: {
          for (final e in ((json['them_moi'] as Map?) ?? const {}).entries)
            e.key.toString(): asInt(e.value),
        },
        duongDanAnToan: asString(json['duong_dan_an_toan']),
      );

  /// Tóm tắt file vừa nhập vào.
  final DuLieuTomTat nguon;

  /// Tình trạng máy này sau khi gộp.
  final DuLieuTomTat sau;

  /// Số dòng thật sự tăng thêm, theo từng bảng.
  ///
  /// Thường nhỏ hơn số dòng trong file, vì bản ghi nào cũ hơn thứ đang có thì
  /// bị bỏ qua. Bằng 0 hết nghĩa là file không có gì mới — không phải lỗi.
  final Map<String, int> themMoi;

  /// Nơi máy chủ cất bản chụp tự động trước khi gộp.
  final String duongDanAnToan;

  int get tongThemMoi => themMoi.values.fold(0, (t, e) => t + e);
}

/// Một bản sao lưu đang nằm trong thư mục tự động.
class BanTuDong {
  const BanTuDong({required this.ten, required this.bytes, required this.luc});

  factory BanTuDong.fromJson(Map<String, Object?> json) => BanTuDong(
        ten: asString(json['ten']),
        bytes: asInt(json['bytes']),
        luc: asTimeOrNull(json['luc']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  final String ten;
  final int bytes;
  final DateTime luc;

  String get coFile => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';
}

/// Thiết lập và tình trạng của phần tự động sao lưu trên máy chủ.
class TuDongSaoLuu {
  const TuDongSaoLuu({
    this.bat = false,
    this.thuMuc = '',
    this.giuBan = 2,
    this.coMatKhau = false,
    this.dangChay = false,
    this.dangCho = false,
    this.lanCuoi,
    this.tenFileCuoi,
    this.loi,
    this.soLanChay = 0,
    this.file = const [],
  });

  factory TuDongSaoLuu.fromJson(Map<String, Object?> json) => TuDongSaoLuu(
        bat: asBool(json['bat']),
        thuMuc: asString(json['thu_muc']),
        giuBan: asInt(json['giu_ban'], fallback: 2),
        coMatKhau: asBool(json['co_mat_khau']),
        dangChay: asBool(json['dang_chay']),
        dangCho: asBool(json['dang_cho']),
        lanCuoi: asTimeOrNull(json['lan_cuoi']),
        tenFileCuoi: asStringOrNull(json['ten_file_cuoi']),
        loi: asStringOrNull(json['loi']),
        soLanChay: asInt(json['so_lan_chay']),
        file: asMapList(json['file']).map(BanTuDong.fromJson).toList(),
      );

  final bool bat;

  /// Thư mục trên ổ đĩa **của máy chạy máy chủ**, không phải máy đang mở app.
  final String thuMuc;
  final int giuBan;

  /// Đã đặt mật khẩu hay chưa. Máy chủ không bao giờ trả mật khẩu về.
  final bool coMatKhau;

  final bool dangChay;

  /// Có thay đổi chưa kịp sao lưu, đang chờ tới lượt.
  final bool dangCho;

  final DateTime? lanCuoi;
  final String? tenFileCuoi;
  final String? loi;
  final int soLanChay;
  final List<BanTuDong> file;
}
