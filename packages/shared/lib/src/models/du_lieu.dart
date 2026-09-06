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
