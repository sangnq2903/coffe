import 'dart:io';
import 'dart:typed_data';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../db/repository.dart';
import '../logging.dart';
import '../service/ticket_service.dart' show BusinessException;
import 'backup_archive.dart';

/// Vài con số mô tả cơ sở dữ liệu, để trước khi xuất/nhập còn biết mình đang
/// cầm cái gì.
class DataSummary {
  const DataSummary({
    required this.bang,
    required this.bytes,
    this.moiNhat,
  });

  /// Số dòng từng bảng, theo tên tiếng Việt để hiện thẳng ra màn hình.
  final Map<String, int> bang;

  /// Cỡ file cơ sở dữ liệu.
  final int bytes;

  /// Bản ghi được sửa gần đây nhất — trả lời câu "file này mới tới đâu".
  final DateTime? moiNhat;

  int get tongDong => bang.values.fold(0, (t, e) => t + e);

  Map<String, Object?> toJson() => {
        'bang': bang,
        'bytes': bytes,
        'tong_dong': tongDong,
        'moi_nhat': moiNhat == null ? null : timeToMillis(moiNhat!),
      };
}

/// Kết quả một lần nhập dữ liệu.
class KetQuaNhap {
  const KetQuaNhap({
    required this.nguon,
    required this.truoc,
    required this.sau,
    required this.duongDanAnToan,
  });

  /// Tóm tắt file vừa nhập vào.
  final DataSummary nguon;

  /// Số dòng của máy này, trước và sau khi gộp.
  final DataSummary truoc;
  final DataSummary sau;

  /// Nơi cất bản chụp tự động trước khi gộp.
  final String duongDanAnToan;

  /// Số dòng thật sự tăng thêm, theo từng bảng. Bản ghi cũ hơn bị bỏ qua nên
  /// con số này thường nhỏ hơn số dòng trong file.
  Map<String, int> get themMoi => {
        for (final k in sau.bang.keys)
          if ((sau.bang[k] ?? 0) - (truoc.bang[k] ?? 0) > 0)
            k: (sau.bang[k] ?? 0) - (truoc.bang[k] ?? 0),
      };

  int get tongThemMoi => themMoi.values.fold(0, (t, e) => t + e);

  Map<String, Object?> toJson() => {
        'nguon': nguon.toJson(),
        'truoc': truoc.toJson(),
        'sau': sau.toJson(),
        'them_moi': themMoi,
        'tong_them_moi': tongThemMoi,
        'duong_dan_an_toan': duongDanAnToan,
      };
}

/// Xuất cơ sở dữ liệu ra file, và nhập một file đã xuất trở lại.
class DataTransferService {
  DataTransferService({
    required this.database,
    required this.repo,
    required this.may,
  });

  final AppDatabase database;
  final Repository repo;

  /// Mã máy — đi vào tên file để nhìn là biết bản của máy nào.
  final String may;

  /// Tên bảng trong SQLite, kèm tên tiếng Việt để hiện ra màn hình.
  static const Map<String, String> _bang = {
    'tickets': 'Phiếu cân',
    'customers': 'Khách hàng',
    'vehicles': 'Xe',
    'goods_types': 'Loại hàng',
    'giao_dich': 'Sổ mua bán',
    'nguoi_dung': 'Tài khoản',
    'nhan_vien': 'Nhân viên',
    'cham_cong': 'Chấm công',
    'so_tien': 'Bảng lương',
    'doan': 'Đoàn',
    'giai_doan_luong': 'Giai đoạn lương',
    'muc_luong': 'Mức lương',
    'gia_luong': 'Giá lương',
  };

  String get _thuMucDuLieu => p.dirname(database.path);

  // ===================================================================== xuất

  /// Đọc vài con số của cơ sở dữ liệu đang chạy.
  DataSummary tomTat() => _tomTat(database.db, database.path);

  /// Chụp cơ sở dữ liệu ra một mảng byte để tải về.
  ///
  /// Có [matKhau] thì gói lại và mã hoá; để trống thì trả về đúng file SQLite,
  /// mở được bằng bất kỳ công cụ nào và chép đè lại được khi cần cứu máy.
  ({Uint8List duLieu, String tenFile}) xuat({String? matKhau}) {
    // Dọn cả thư mục tạm chứ không riêng file bên trong: xoá mỗi file thì mỗi
    // lần xuất lại bỏ lại một thư mục rỗng, vài năm là hàng nghìn cái.
    final tam = _thuMucTam();
    try {
      final goc = chupNhanh(vao: p.join(tam.path, 'chup.db')).readAsBytesSync();
      final luc = DateTime.now();
      final ten = 'canxe-${may.toLowerCase()}-${_dauThoiGian(luc)}';

      if (matKhau == null || matKhau.isEmpty) {
        return (duLieu: goc, tenFile: '$ten.db');
      }
      return (
        duLieu: BackupArchive.dongGoi(
          duLieu: goc,
          matKhau: matKhau,
          tenGoc: p.basename(database.path),
          may: may,
          luc: luc,
        ),
        tenFile: '$ten.canxe',
      );
    } finally {
      _xoaLang(tam);
    }
  }

  /// Chụp một bản sao **nhất quán** trong lúc máy chủ vẫn đang chạy.
  ///
  /// Dùng `VACUUM INTO` chứ không chép file. Cơ sở dữ liệu đang bật WAL: những
  /// thay đổi mới nhất còn nằm ở file `-wal` bên cạnh, nên chép mỗi file `.db`
  /// là ra bản thiếu giao dịch gần đây — mà mở lên vẫn bình thường, không báo
  /// lỗi gì. Chép cả ba file thì lại có nguy cơ chộp đúng lúc đang ghi dở.
  File chupNhanh({String? vao}) {
    final dich = File(vao ?? p.join(_thuMucTam().path, 'chup.db'));
    dich.parent.createSync(recursive: true);
    // VACUUM INTO từ chối ghi đè file đã có.
    if (dich.existsSync()) dich.deleteSync();

    database.db.execute('VACUUM INTO ?', [dich.path]);
    return dich;
  }

  // ====================================================================== nhập

  /// Gộp dữ liệu từ một file đã xuất vào cơ sở dữ liệu đang chạy.
  ///
  /// **Gộp chứ không đè.** Mỗi bản ghi chỉ ghi đè bản hiện có khi nó mới hơn
  /// (so theo `updated_at`), đúng luật đang dùng cho việc đồng bộ giữa trạm và
  /// trung tâm. Nhờ vậy nhập nhầm một bản cũ không xoá mất việc làm hôm nay —
  /// thứ mà một nút "khôi phục toàn bộ" sẽ làm mất sạch.
  ///
  /// Đổi lại, cách này **không xoá được** bản ghi đang có mà file không có.
  /// Muốn quay về đúng nguyên trạng một ngày nào đó thì phải dừng máy chủ rồi
  /// chép đè file — xem hướng dẫn trong README.
  ///
  /// [uuTienFile]: coi mọi bản ghi trong file là vừa sửa lúc nhập, nên file
  /// thắng mọi bản đang có trên máy. Dùng khi biết chắc file là bản đúng — ví
  /// dụ chấm công trên trạm đúng mà trung tâm lại giữ bản sửa sau nhưng sai.
  /// Gộp thường thì bản sai đó mới hơn nên thắng, nhập bao nhiêu lần cũng vậy.
  /// Đóng dấu giờ mới còn để máy khác kéo về được: máy trạm chỉ hỏi trung tâm
  /// những gì sửa sau lần kéo trước, bản ghi mang giờ cũ sẽ không bao giờ tới.
  KetQuaNhap nhap(List<int> duLieu, {String? matKhau, bool uuTienFile = false}) {
    final bytes = _moNeuMaHoa(duLieu, matKhau);
    final tam = _thuMucTam();
    try {
      final file = File(p.join(tam.path, 'nhap.db'))..writeAsBytesSync(bytes);
      final nguon = _kiemTraVaDoc(file.path);

      // Chụp lại hiện trạng TRƯỚC khi động vào. Gộp thì an toàn hơn đè, nhưng
      // "an toàn hơn" không phải là "không hỏng được": file có đồng hồ chạy
      // nhanh sẽ mang bản ghi sai đè lên bản đúng, và lúc đó phải có đường lui.
      final anToan = File(p.join(
        _thuMucDuLieu,
        'sao-luu',
        'truoc-khi-nhap-${_dauThoiGian(DateTime.now())}.db',
      ));
      chupNhanh(vao: anToan.path);

      final truoc = tomTat();
      AppLog.write('[nhap-du-lieu] gộp ${nguon.tongDong} dòng từ file'
          '${uuTienFile ? ', ưu tiên bản trong file' : ''} '
          '(đã cất bản chụp ở ${anToan.path})');

      // markDirty: true để dữ liệu vừa cứu được còn chảy tiếp sang máy khác.
      // Không sợ nó đè bậy lên trung tâm: luật ghi đè vẫn là bản mới hơn thắng.
      repo.applyPayload(_docToanBo(file.path, uuTienFile: uuTienFile), markDirty: true);

      final sau = tomTat();
      AppLog.write('[nhap-du-lieu] xong, thêm mới ${sau.tongDong - truoc.tongDong} dòng');

      return KetQuaNhap(
        nguon: nguon,
        truoc: truoc,
        sau: sau,
        duongDanAnToan: anToan.path,
      );
    } finally {
      _xoaLang(tam);
    }
  }

  /// Chỉ đọc và kiểm tra một file, **không ghi gì vào cơ sở dữ liệu**.
  ///
  /// Để màn hình cho xem trước file có gì rồi mới hỏi có nhập không. Nhập dữ
  /// liệu là việc khó lùi, không nên bấm một nút là xong.
  DataSummary xemTruoc(List<int> duLieu, {String? matKhau}) {
    final bytes = _moNeuMaHoa(duLieu, matKhau);
    final tam = _thuMucTam();
    try {
      final file = File(p.join(tam.path, 'xem.db'))..writeAsBytesSync(bytes);
      return _kiemTraVaDoc(file.path);
    } finally {
      _xoaLang(tam);
    }
  }

  // ------------------------------------------------------------- bên trong

  /// File có chữ ký của gói mã hoá thì mở ra; không thì coi là file SQLite trần.
  Uint8List _moNeuMaHoa(List<int> duLieu, String? matKhau) {
    final bytes = duLieu is Uint8List ? duLieu : Uint8List.fromList(duLieu);
    if (!_laGoiMaHoa(bytes)) {
      if (matKhau != null && matKhau.isNotEmpty) {
        throw BusinessException(
          'File này không mã hoá nên không cần mật khẩu — bỏ trống ô mật khẩu rồi thử lại.',
        );
      }
      return bytes;
    }
    if (matKhau == null || matKhau.isEmpty) {
      throw BusinessException('File này có mã hoá, phải nhập mật khẩu lúc xuất ra.');
    }
    try {
      return BackupArchive.moGoi(goi: bytes, matKhau: matKhau).$2;
    } on BackupException catch (e) {
      throw BusinessException(e.message);
    }
  }

  static bool _laGoiMaHoa(Uint8List bytes) {
    if (bytes.length < BackupArchive.magic.length) return false;
    for (var i = 0; i < BackupArchive.magic.length; i++) {
      if (bytes[i] != BackupArchive.magic[i]) return false;
    }
    return true;
  }

  /// Mở file bằng SQLite và soi kỹ trước khi cho phép gộp vào dữ liệu thật.
  DataSummary _kiemTraVaDoc(String duongDan) {
    Database? db;
    try {
      // Mở file và soi nó nằm chung một khối bắt lỗi. `sqlite3.open` gần như
      // không bao giờ ném ngay cả với file rác — nó chỉ ánh xạ file rồi để đó,
      // mãi tới câu lệnh đầu tiên mới vỡ. Bắt lỗi quanh riêng lời gọi `open`
      // thì file rác đi lọt, rồi nổ thành lỗi SQLite thô ở tận màn hình người
      // dùng, kèm nguyên vết gọi hàm.
      db = sqlite3.open(duongDan);

      final toanVen = db.select('PRAGMA integrity_check;').first.values.first;
      if (toanVen != 'ok') {
        throw BusinessException('File bị hỏng, SQLite báo: $toanVen');
      }

      // So phiên bản lược đồ với chính máy này thay vì với một con số viết
      // cứng: viết cứng thì thêm một bước nâng cấp là quên sửa, rồi bản xuất
      // của hôm nay bị chính phần mềm của hôm nay từ chối.
      final cuaFile = db.select('PRAGMA user_version;').first.values.first as int;
      final cuaMay =
          database.db.select('PRAGMA user_version;').first.values.first as int;
      if (cuaFile == 0) {
        throw BusinessException(
          'File này là cơ sở dữ liệu SQLite nhưng không phải của phần mềm cân xe.',
        );
      }
      if (cuaFile > cuaMay) {
        throw BusinessException(
          'File được tạo bởi bản phần mềm mới hơn (lược đồ $cuaFile, máy này $cuaMay). '
          'Hãy cập nhật máy chủ rồi nhập lại.',
        );
      }

      final thieu = _bang.keys.where((t) => !_coBang(db!, t)).toList();
      if (thieu.isNotEmpty) {
        throw BusinessException(
          'File thiếu bảng: ${thieu.join(", ")} — không phải bản sao lưu của phần mềm này.',
        );
      }
      return _tomTat(db, duongDan);
    } on BusinessException {
      rethrow;
    } catch (_) {
      throw BusinessException(
        'Không đọc được file này: không phải cơ sở dữ liệu SQLite hợp lệ, '
        'hoặc file đã hỏng.',
      );
    } finally {
      db?.dispose();
    }
  }

  static bool _coBang(Database db, String ten) => db
      .select("SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?", [ten])
      .isNotEmpty;

  /// Mở file bằng [AppDatabase] để bản cũ được nâng cấp lược đồ trước khi đọc,
  /// rồi đọc hết ra một gói.
  SyncPayload _docToanBo(String duongDan, {bool uuTienFile = false}) {
    final db = AppDatabase.open(duongDan);
    try {
      if (uuTienFile) {
        // Sửa trên bản sao tạm của file, không đụng gì tới dữ liệu thật.
        // Chừa bảng tài khoản ra: để file thắng ở đó là mật khẩu vừa đổi trên
        // máy này bị mật khẩu cũ trong file đè mất, khoá luôn người đang dùng.
        // Lấy mốc sau cả bản mới nhất đang có trên máy chứ không chỉ "bây giờ":
        // máy nào từng chạy đồng hồ nhanh thì có bản ghi mang giờ tương lai, và
        // file vẫn thua đúng những bản đó.
        var luc = timeToMillis(DateTime.now());
        for (final t in _bang.keys) {
          final m = database.db.select('SELECT MAX(updated_at) AS m FROM $t').first['m'];
          if (m is int && m >= luc) luc = m + 1;
        }
        for (final t in _bang.keys.where((t) => t != 'nguoi_dung')) {
          db.db.execute('UPDATE $t SET updated_at = ?', [luc]);
        }
      }
      return Repository(db).toanBoDuLieu();
    } finally {
      db.dispose();
    }
  }

  static DataSummary _tomTat(Database db, String duongDan) {
    final bang = <String, int>{};
    for (final e in _bang.entries) {
      if (!_coBang(db, e.key)) continue;
      final co = db
          .select("SELECT 1 FROM pragma_table_info(?) WHERE name = 'deleted'", [e.key])
          .isNotEmpty;
      final sql = co
          ? 'SELECT COUNT(*) AS c FROM ${e.key} WHERE deleted = 0'
          : 'SELECT COUNT(*) AS c FROM ${e.key}';
      bang[e.value] = db.select(sql).first['c'] as int;
    }

    DateTime? moiNhat;
    for (final t in _bang.keys) {
      if (!_coBang(db, t)) continue;
      final v = db.select('SELECT MAX(updated_at) AS m FROM $t').first['m'];
      if (v is int && v > 0) {
        final luc = DateTime.fromMillisecondsSinceEpoch(v);
        if (moiNhat == null || luc.isAfter(moiNhat)) moiNhat = luc;
      }
    }

    return DataSummary(bang: bang, bytes: _coDuLieu(db, duongDan), moiNhat: moiNhat);
  }

  /// Thư mục tạm, đặt cạnh cơ sở dữ liệu chứ không dùng thư mục tạm của
  /// Windows: file ở đây là bản sao đầy đủ, nên nên nằm cùng ổ đĩa với dữ liệu
  /// thật để không vô tình chép nguyên cơ sở dữ liệu sang một ổ khác.
  /// Cỡ dữ liệu thật, hỏi thẳng SQLite chứ không đo file trên đĩa.
  ///
  /// Cơ sở dữ liệu đang bật WAL: những thay đổi mới nhất còn nằm ở file `-wal`
  /// bên cạnh, nên file `.db` chính có thể chỉ 4 KB trong khi dữ liệu đã hàng
  /// chục MB. Đo file chính là hiện ra một con số vô nghĩa ngay trên màn hình.
  static int _coDuLieu(Database db, String duongDan) {
    try {
      final trang = db.select('PRAGMA page_count;').first.values.first as int;
      final coTrang = db.select('PRAGMA page_size;').first.values.first as int;
      return trang * coTrang;
    } catch (_) {
      final f = File(duongDan);
      return f.existsSync() ? f.lengthSync() : 0;
    }
  }

  Directory _thuMucTam() {
    final cha = Directory(p.join(_thuMucDuLieu, 'tam'));
    // `createTempSync` đòi thư mục cha có sẵn, không tự tạo giúp.
    if (!cha.existsSync()) cha.createSync(recursive: true);
    return cha.createTempSync('canxe-');
  }

  /// Dọn file tạm. Bản chụp thô là cơ sở dữ liệu đầy đủ không khoá — không để
  /// nó nằm lại trên đĩa sau khi đã dùng xong.
  static void _xoaLang(FileSystemEntity f) {
    try {
      if (f.existsSync()) f.deleteSync(recursive: true);
    } catch (_) {}
  }

  static String _dauThoiGian(DateTime v) {
    String hai(int x) => x.toString().padLeft(2, '0');
    return '${v.year}${hai(v.month)}${hai(v.day)}-${hai(v.hour)}${hai(v.minute)}';
  }
}
