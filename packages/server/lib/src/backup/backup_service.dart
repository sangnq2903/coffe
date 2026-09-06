import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../logging.dart';
import 'backup_archive.dart';
import 'backup_config.dart';
import 'backup_store.dart';

/// Kết quả lần sao lưu gần nhất, để hiện ra và để biết có đang hỏng ngầm không.
class BackupState {
  const BackupState({
    this.dangChay = false,
    this.lanCuoi,
    this.thanhCong,
    this.tenBan,
    this.bytes,
    this.loi,
    this.lanKe,
  });

  final bool dangChay;
  final DateTime? lanCuoi;
  final bool? thanhCong;
  final String? tenBan;
  final int? bytes;
  final String? loi;
  final DateTime? lanKe;

  Map<String, Object?> toJson() => {
        'dang_chay': dangChay,
        'lan_cuoi': lanCuoi?.millisecondsSinceEpoch,
        'thanh_cong': thanhCong,
        'ten_ban': tenBan,
        'bytes': bytes,
        'loi': loi,
        'lan_ke': lanKe?.millisecondsSinceEpoch,
      };
}

/// Chụp cơ sở dữ liệu, đóng gói, đẩy lên đám mây — và hẹn giờ làm việc đó mỗi ngày.
class BackupService {
  BackupService({
    required this.config,
    required this.database,
    required this.may,
    required this.thuMucGoc,
    BackupStore? store,
  }) : _store = store;

  final BackupConfig config;
  final AppDatabase database;

  /// Mã máy tạo bản sao — trung tâm hay mã trạm.
  final String may;

  /// Thư mục gốc để quy đổi đường dẫn tương đối trong cấu hình.
  final String thuMucGoc;

  final BackupStore? _store;
  Timer? _hen;
  BackupState _state = const BackupState();

  BackupState get state => _state;

  BackupStore _moStore() =>
      _store ?? BackupStore(url: config.url, token: config.token);

  String get _thuMuc => config.thuMucTamTuyetDoi(thuMucGoc);

  /// Bật lịch sao lưu hằng ngày.
  ///
  /// **Không** sao lưu ngay lúc khởi động: máy chủ ở kho hay bị cúp điện rồi
  /// bật lại vài lần liên tiếp, mỗi lần lại đẩy một bản lên thì chỉ ít lâu là
  /// mấy bản của hôm nay đùn hết bản cũ ra khỏi hạn giữ.
  void start() {
    // Thiếu cấu hình thì im lặng không hẹn giờ; bảng khởi động của server đã
    // nói rõ thiếu thứ gì rồi, báo thêm ở đây thành ra hai dòng cùng một ý.
    if (!config.bat || !config.sanSang) return;
    _henLanKe();
  }

  void _henLanKe() {
    final gio = _lanKeTiepTheo();
    _state = BackupState(
      dangChay: _state.dangChay,
      lanCuoi: _state.lanCuoi,
      thanhCong: _state.thanhCong,
      tenBan: _state.tenBan,
      bytes: _state.bytes,
      loi: _state.loi,
      lanKe: gio,
    );
    _hen?.cancel();
    _hen = Timer(gio.difference(DateTime.now()), () async {
      await chayNgay();
      _henLanKe();
    });
  }

  DateTime _lanKeTiepTheo() {
    final now = DateTime.now();
    var moc = DateTime(now.year, now.month, now.day, config.gioChay, config.phutChay);
    if (!moc.isAfter(now)) moc = moc.add(const Duration(days: 1));
    return moc;
  }

  /// Chạy một lượt sao lưu đầy đủ. Trả về tên bản đã đẩy lên.
  Future<String> chayNgay({void Function(String)? baoCao}) async {
    void noi(String s) {
      baoCao?.call(s);
      AppLog.write('[sao-luu] $s');
    }

    if (_state.dangChay) {
      throw BackupException('Đang có một lượt sao lưu chạy dở.');
    }
    if (!config.sanSang) {
      throw BackupException(
        'Chưa đủ cấu hình sao lưu, còn thiếu: ${config.thieuGi().join(", ")}.',
      );
    }

    _state = BackupState(dangChay: true, lanKe: _state.lanKe);
    final store = _moStore();
    File? chup;
    try {
      chup = chupNhanh();
      final goc = await chup.readAsBytes();
      noi('Đã chụp ${_mb(goc.length)} MB từ ${p.basename(database.path)}.');

      final luc = DateTime.now();
      final goi = BackupArchive.dongGoi(
        duLieu: goc,
        matKhau: config.matKhau,
        tenGoc: p.basename(database.path),
        may: may,
        luc: luc,
      );
      final meta = BackupArchive.docMeta(goi);
      noi('Đã nén và mã hoá còn ${_mb(goi.length)} MB.');

      await _giuTaiCho(meta.tenGoi, goi);

      await store.day(
        ten: meta.tenGoi,
        meta: meta,
        goi: goi,
        giuBan: config.giuBan,
        tienDo: (i, n) => n > 1 ? noi('Đang đẩy phần $i/$n...') : null,
      );
      noi('Xong: ${meta.tenGoi}');

      _state = BackupState(
        lanCuoi: luc,
        thanhCong: true,
        tenBan: meta.tenGoi,
        bytes: goi.length,
        lanKe: _state.lanKe,
      );
      return meta.tenGoi;
    } catch (e) {
      _state = BackupState(
        lanCuoi: DateTime.now(),
        thanhCong: false,
        loi: e.toString(),
        lanKe: _state.lanKe,
      );
      AppLog.error('[sao-luu] HỎNG: $e');
      rethrow;
    } finally {
      // Bản chụp thô là bản sao đầy đủ không khoá — không để nó nằm lại trên
      // đĩa sau khi đã có gói mã hoá.
      try {
        if (chup != null && chup.existsSync()) chup.deleteSync();
      } catch (_) {}
      if (_store == null) store.dispose();
    }
  }

  /// Chụp một bản sao **nhất quán** của cơ sở dữ liệu trong lúc server vẫn chạy.
  ///
  /// Dùng `VACUUM INTO` chứ không chép file. Cơ sở dữ liệu đang bật WAL: những
  /// thay đổi mới nhất còn nằm ở file `-wal` bên cạnh, nên chép mỗi file `.db`
  /// là ra một bản thiếu giao dịch gần đây, mà lại mở lên bình thường không báo
  /// lỗi gì. Chép cả ba file thì lại có nguy cơ chộp đúng lúc đang ghi dở.
  /// `VACUUM INTO` để chính SQLite ghi ra một file hoàn chỉnh, đã dọn gọn.
  File chupNhanh() {
    final thuMuc = Directory(_thuMuc);
    if (!thuMuc.existsSync()) thuMuc.createSync(recursive: true);

    final dich = File(p.join(_thuMuc, 'chup-tam.db'));
    // VACUUM INTO từ chối ghi đè file đã có.
    if (dich.existsSync()) dich.deleteSync();

    database.db.execute('VACUUM INTO ?', [dich.path]);
    return dich;
  }

  /// Giữ một bản ngay trên ổ đĩa, và dọn bớt bản cũ.
  Future<void> _giuTaiCho(String ten, Uint8List goi) async {
    if (config.giuBanTaiCho <= 0) return;
    final thuMuc = Directory(_thuMuc);
    if (!thuMuc.existsSync()) thuMuc.createSync(recursive: true);

    await File(p.join(_thuMuc, '$ten.canxe')).writeAsBytes(goi);

    final cu = thuMuc
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.canxe'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in cu.skip(config.giuBanTaiCho)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

  void dispose() => _hen?.cancel();
}
