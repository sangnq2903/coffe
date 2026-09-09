import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../logging.dart';
import '../service/ticket_service.dart' show BusinessException;
import 'backup_archive.dart';
import 'data_transfer.dart';

/// Thiết lập tự động sao lưu của **riêng máy này**.
class AutoBackupSettings {
  const AutoBackupSettings({
    this.bat = false,
    this.thuMuc = '',
    this.giuBan = 2,
    this.matKhau = '',
  });

  factory AutoBackupSettings.fromJson(Map<String, Object?> json) =>
      AutoBackupSettings(
        bat: asBool(json['bat']),
        thuMuc: asString(json['thu_muc']).trim(),
        // Người dùng chọn giữ mấy bản; ít nhất phải là 1, nếu không thì bật
        // tính năng lên mà chẳng giữ được gì.
        giuBan: asInt(json['giu_ban'], fallback: 2).clamp(1, 50),
        matKhau: asString(json['mat_khau']),
      );

  /// Bật/tắt. Tắt thì máy chủ chạy y như trước, không đụng gì tới ổ đĩa.
  final bool bat;

  /// Thư mục trên ổ đĩa **của máy chạy máy chủ** để cất bản sao.
  final String thuMuc;

  /// Giữ tối đa mấy bản; quá số này thì bản cũ nhất bị xoá.
  final int giuBan;

  /// Mật khẩu mã hoá, để trống thì ghi ra file SQLite trần.
  ///
  /// Có tác dụng thật khi thư mục là USB hay ổ đĩa chung: mất cái USB thì kẻ
  /// nhặt được không có mật khẩu, vì mật khẩu nằm trong cơ sở dữ liệu trên máy
  /// chủ. Nó **không** bảo vệ được gì nếu chính máy chủ bị chiếm.
  final String matKhau;

  bool get sanSang => bat && thuMuc.isNotEmpty;

  Map<String, Object?> toJson() => {
        'bat': bat,
        'thu_muc': thuMuc,
        'giu_ban': giuBan,
        // Không trả mật khẩu ra ngoài, chỉ nói là đã đặt hay chưa.
        'co_mat_khau': matKhau.isNotEmpty,
      };
}

/// Tình trạng lần chạy gần nhất, để màn hình biết nó có đang chạy thật không.
class AutoBackupState {
  const AutoBackupState({
    this.dangChay = false,
    this.dangCho = false,
    this.lanCuoi,
    this.tenFileCuoi,
    this.bytesCuoi,
    this.loi,
    this.soLanChay = 0,
    this.file = const [],
  });

  final bool dangChay;

  /// Có thay đổi chưa được sao lưu, đang chờ tới lượt.
  final bool dangCho;

  final DateTime? lanCuoi;
  final String? tenFileCuoi;
  final int? bytesCuoi;
  final String? loi;
  final int soLanChay;

  /// Danh sách file đang có trong thư mục, mới nhất trước.
  final List<({String ten, int bytes, DateTime luc})> file;

  Map<String, Object?> toJson() => {
        'dang_chay': dangChay,
        'dang_cho': dangCho,
        'lan_cuoi': lanCuoi == null ? null : timeToMillis(lanCuoi!),
        'ten_file_cuoi': tenFileCuoi,
        'bytes_cuoi': bytesCuoi,
        'loi': loi,
        'so_lan_chay': soLanChay,
        'file': [
          for (final f in file)
            {'ten': f.ten, 'bytes': f.bytes, 'luc': timeToMillis(f.luc)},
        ],
      };
}

/// Tự sao lưu ra thư mục người dùng chọn, mỗi khi dữ liệu có thay đổi.
///
/// **Vì sao không sao lưu ngay sau từng lần lưu.** Một lượt đồng bộ từ máy trạm
/// ghi hàng trăm dòng; chụp lại cả cơ sở dữ liệu sau từng dòng thì máy chủ chỉ
/// còn làm mỗi việc đó, và bàn cân đứng chờ. Tệ hơn: chỉ giữ 2 bản, nên hai bản
/// ấy sẽ cách nhau vài giây — mất dữ liệu lúc 10 giờ sáng thì bản gần nhất là
/// 9 giờ 59, chẳng cứu được gì.
///
/// Nên cách làm là: **ghi nhận có thay đổi, rồi chờ lặng**. Hết một quãng không
/// ai ghi gì nữa mới chụp một bản. Cả trận nhập liệu dồn thành một file. Và để
/// phòng trường hợp kho bận cả ngày không lúc nào ngơi, có thêm mốc chặn trên:
/// quá [_toiDaCho] mà vẫn còn thay đổi treo thì chụp luôn, không chờ nữa.
class AutoBackupService {
  AutoBackupService({
    required this.database,
    required this.duLieu,
    required this.may,
  });

  final AppDatabase database;
  final DataTransferService duLieu;
  final String may;

  /// Chờ bao lâu không có thay đổi mới thì chụp.
  static const Duration _choLang = Duration(seconds: 30);

  /// Dù bận tới đâu, quá quãng này mà còn thay đổi treo là phải chụp.
  static const Duration _toiDaCho = Duration(minutes: 10);

  /// Nhịp soi. Chỉ so vài mốc thời gian nên rẻ, không đụng vào ổ đĩa.
  static const Duration _nhip = Duration(seconds: 5);

  /// Bảng không tính là "có thay đổi" cần sao lưu.
  ///
  /// `sync_state` được trạm ghi lại mỗi vòng đồng bộ (mặc định 20 giây một
  /// lần, kể cả khi không kéo được gì mới) và `stations` được trung tâm ghi
  /// lại mỗi lần một trạm báo còn sống. Cả hai đều nhặt hơn mốc [_choLang] 30
  /// giây, nên nếu tính luôn thì đồng hồ chờ "yên lặng" không bao giờ chạm
  /// tới — sao lưu chỉ còn trông vào mốc chặn trên 10 phút, trong khi màn
  /// hình lại hứa "hết nửa phút không ai ghi gì".
  static const _bangBoQua = {'sync_state', 'stations'};

  StreamSubscription<void>? _theoDoi;
  Timer? _dongHo;

  DateTime? _thayDoiLuc;
  DateTime? _treoTu;
  AutoBackupSettings _caiDat = const AutoBackupSettings();
  AutoBackupState _state = const AutoBackupState();

  AutoBackupSettings get caiDat => _caiDat;

  AutoBackupState get state => AutoBackupState(
        dangChay: _state.dangChay,
        dangCho: _thayDoiLuc != null,
        lanCuoi: _state.lanCuoi,
        tenFileCuoi: _state.tenFileCuoi,
        bytesCuoi: _state.bytesCuoi,
        loi: _state.loi,
        soLanChay: _state.soLanChay,
        file: _caiDat.thuMuc.isEmpty ? const [] : _dsFile(),
      );

  // ================================================================ vòng đời

  void start() {
    _caiDat = docCaiDat();

    // Bắt thay đổi bằng chính móc báo của SQLite chứ không cắm vào từng hàm
    // lưu. Cắm tay thì lần sau thêm một đường ghi mới là quên, và tính năng
    // hỏng trong im lặng. Móc này thì mọi câu INSERT/UPDATE/DELETE đều qua.
    //
    // Dùng bản đồng bộ để một giao dịch ghi 500 dòng không dồn 500 sự kiện vào
    // hàng đợi. Việc trong này chỉ là gán một mốc thời gian — không đụng cơ sở
    // dữ liệu, đúng như tài liệu của gói yêu cầu.
    _theoDoi = database.db.updatesSync.listen((u) {
      if (_bangBoQua.contains(u.tableName)) return;
      _thayDoiLuc = DateTime.now();
      _treoTu ??= _thayDoiLuc;
    });

    _dongHo = Timer.periodic(_nhip, (_) => _soi());
  }

  void dispose() {
    _dongHo?.cancel();
    _theoDoi?.cancel();
  }

  void _soi() {
    if (!_caiDat.sanSang || _state.dangChay) return;
    final luc = _thayDoiLuc;
    if (luc == null) return;

    final now = DateTime.now();
    final daLang = now.difference(luc) >= _choLang;
    final choQuaLau =
        _treoTu != null && now.difference(_treoTu!) >= _toiDaCho;
    if (!daLang && !choQuaLau) return;

    // Không `await`: đây là nhịp đồng hồ, không phải yêu cầu của ai. Lỗi được
    // ghi vào trạng thái để màn hình thấy, chứ không ném ra ngoài.
    unawaited(chayNgay());
  }

  // =================================================================== chạy

  /// Chụp một bản ngay. Ném [BusinessException] nếu chưa đủ điều kiện.
  Future<String> chayNgay() async {
    if (!_caiDat.sanSang) {
      throw BusinessException('Chưa bật tự động sao lưu, hoặc chưa chọn thư mục.');
    }
    if (_state.dangChay) {
      throw BusinessException('Đang có một lượt sao lưu chạy dở.');
    }

    _state = AutoBackupState(
      dangChay: true,
      lanCuoi: _state.lanCuoi,
      tenFileCuoi: _state.tenFileCuoi,
      bytesCuoi: _state.bytesCuoi,
      soLanChay: _state.soLanChay,
    );
    // Xoá mốc treo NGAY, trước khi chụp. Đặt sau khi chụp xong thì mọi thay đổi
    // xảy ra trong lúc đang chụp sẽ bị xoá theo, và bản sau thiếu đúng những
    // dòng ấy.
    _thayDoiLuc = null;
    _treoTu = null;

    try {
      final ten = await _chup();
      final f = File(p.join(_caiDat.thuMuc, ten));
      _state = AutoBackupState(
        lanCuoi: DateTime.now(),
        tenFileCuoi: ten,
        bytesCuoi: f.existsSync() ? f.lengthSync() : 0,
        soLanChay: _state.soLanChay + 1,
      );
      AppLog.write('[tu-dong-sao-luu] $ten');
      return ten;
    } catch (e) {
      // Chụp hỏng thì coi như vẫn còn thay đổi treo, để nhịp sau thử lại —
      // quên đi là dữ liệu từ đó tới giờ không bao giờ được sao lưu nữa.
      _thayDoiLuc = DateTime.now();
      _treoTu ??= _thayDoiLuc;
      _state = AutoBackupState(
        lanCuoi: DateTime.now(),
        loi: e is BusinessException ? e.message : '$e',
        tenFileCuoi: _state.tenFileCuoi,
        bytesCuoi: _state.bytesCuoi,
        soLanChay: _state.soLanChay,
      );
      AppLog.error('[tu-dong-sao-luu] HỎNG: $e');
      rethrow;
    }
  }

  /// Chụp một bản ra file.
  ///
  /// Việc này **chặn vòng lặp sự kiện**: `VACUUM INTO` của SQLite chỉ có bản
  /// đồng bộ, và phần mã hoá cũng là tính toán thuần. Với cỡ dữ liệu ở kho thì
  /// hết vài chục mili giây nên không ai thấy; nếu sau này dữ liệu lớn tới mức
  /// vài chục MB, cân xe có thể khựng một nhịp lúc đang chụp. Sở dĩ tạm chấp
  /// nhận được là vì lịch chụp chỉ nổ ra sau [_choLang] không ai ghi gì —
  /// nghĩa là đúng lúc kho đang rảnh.
  Future<String> _chup() async {
    final thuMuc = Directory(_caiDat.thuMuc);
    if (!thuMuc.existsSync()) thuMuc.createSync(recursive: true);

    final luc = DateTime.now();
    final ten = 'canxe-${may.toLowerCase()}-${_dauThoiGian(luc)}';
    final coMk = _caiDat.matKhau.isNotEmpty;
    final dich = File(p.join(_caiDat.thuMuc, '$ten${coMk ? '.canxe' : '.db'}'));

    // Ghi ra tên tạm rồi mới đổi tên. Ghi thẳng vào tên thật thì mất điện giữa
    // chừng để lại một file cụt mang đúng tên một bản sao lưu hợp lệ — và nó
    // còn đẩy bản tốt ra khỏi hạn giữ 2 file.
    final tam = File('${dich.path}.dangghi');
    try {
      if (coMk) {
        final chup = duLieu.chupNhanh();
        try {
          tam.writeAsBytesSync(BackupArchive.dongGoi(
            duLieu: chup.readAsBytesSync(),
            matKhau: _caiDat.matKhau,
            tenGoc: p.basename(database.path),
            may: may,
            luc: luc,
          ));
        } finally {
          try {
            if (chup.existsSync()) chup.deleteSync();
          } catch (_) {}
        }
      } else {
        duLieu.chupNhanh(vao: tam.path);
      }
      if (dich.existsSync()) dich.deleteSync();
      tam.renameSync(dich.path);
    } finally {
      try {
        if (tam.existsSync()) tam.deleteSync();
      } catch (_) {}
    }

    _don();
    return p.basename(dich.path);
  }

  /// Giữ [giuBan] bản mới nhất, xoá phần còn lại.
  void _don() {
    final ds = _dsFile();
    for (final f in ds.skip(_caiDat.giuBan)) {
      try {
        File(p.join(_caiDat.thuMuc, f.ten)).deleteSync();
      } catch (_) {
        // File đang bị mở ở nơi khác thì để nhịp sau dọn, không phải lỗi nặng.
      }
    }
  }

  /// Bản sao lưu đang có trong thư mục, mới nhất đứng đầu.
  ///
  /// Sắp theo **tên** chứ không theo ngày sửa file: tên bắt đầu bằng dấu thời
  /// gian nên xếp đúng thứ tự, còn ngày sửa thì chép file qua USB một cái là
  /// đảo lộn hết.
  List<({String ten, int bytes, DateTime luc})> _dsFile() {
    final thuMuc = Directory(_caiDat.thuMuc);
    if (!thuMuc.existsSync()) return const [];
    try {
      final ds = thuMuc
          .listSync()
          .whereType<File>()
          .where((f) => _cuaMayNay(p.basename(f.path)))
          .toList()
        ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      return [
        for (final f in ds)
          (ten: p.basename(f.path), bytes: f.lengthSync(), luc: f.lastModifiedSync()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Chỉ nhận file do chính máy này sinh ra.
  ///
  /// Thư mục có thể là chỗ chung, người ta để cả bản xuất tay hay file khác vào
  /// đó. Dọn nhầm file của người ta là chuyện không sửa lại được.
  bool _cuaMayNay(String ten) =>
      ten.startsWith('canxe-${may.toLowerCase()}-') &&
      (ten.endsWith('.db') || ten.endsWith('.canxe'));

  // ============================================================== thiết lập

  static const _khoa = 'tu_dong_sao_luu';

  AutoBackupSettings docCaiDat() {
    final rows = database.db
        .select('SELECT gia_tri FROM cai_dat WHERE khoa = ?', [_khoa]);
    if (rows.isEmpty) return const AutoBackupSettings();
    try {
      final raw = jsonDecode(rows.first.values.first?.toString() ?? '');
      if (raw is! Map) return const AutoBackupSettings();
      final m = raw.cast<String, Object?>();
      return AutoBackupSettings(
        bat: asBool(m['bat']),
        thuMuc: asString(m['thu_muc']),
        giuBan: asInt(m['giu_ban'], fallback: 2),
        matKhau: asString(m['mat_khau']),
      );
    } catch (_) {
      return const AutoBackupSettings();
    }
  }

  /// Ghi thiết lập mới. Kiểm thư mục ghi được **trước khi** lưu.
  ///
  /// Không kiểm thì một đường dẫn gõ sai sẽ được nhận, màn hình báo đã bật, mà
  /// thật ra chẳng bản nào được ghi ra cả — cho tới hôm cần dùng mới biết.
  AutoBackupSettings luuCaiDat(Map<String, Object?> body) {
    final moi = AutoBackupSettings(
      bat: asBool(body['bat']),
      thuMuc: asString(body['thu_muc']).trim(),
      giuBan: asInt(body['giu_ban'], fallback: 2).clamp(1, 50),
      // Không gửi trường mật khẩu thì giữ nguyên cái đang có: màn hình không
      // đọc được mật khẩu cũ nên không thể gửi lại nó.
      matKhau: body.containsKey('mat_khau')
          ? asString(body['mat_khau'])
          : _caiDat.matKhau,
    );

    if (moi.bat) {
      if (moi.thuMuc.isEmpty) {
        throw BusinessException('Chưa chọn thư mục để cất bản sao lưu.');
      }
      if (!p.isAbsolute(moi.thuMuc)) {
        throw BusinessException(
          'Phải ghi đường dẫn đầy đủ, ví dụ D:\\SaoLuuCanXe — đường dẫn tương '
          'đối tính từ chỗ máy chủ đang chạy nên rất dễ ra nhầm chỗ.',
        );
      }
      _thuGhi(moi.thuMuc);
    }

    database.db.execute(
      'INSERT INTO cai_dat (khoa, gia_tri, sua_luc) VALUES (?, ?, ?) '
      'ON CONFLICT(khoa) DO UPDATE SET gia_tri = excluded.gia_tri, '
      'sua_luc = excluded.sua_luc',
      [
        _khoa,
        jsonEncode({
          'bat': moi.bat,
          'thu_muc': moi.thuMuc,
          'giu_ban': moi.giuBan,
          'mat_khau': moi.matKhau,
        }),
        timeToMillis(DateTime.now()),
      ],
    );
    _caiDat = moi;
    return moi;
  }

  /// Thử tạo thư mục và ghi một file nhỏ vào đó.
  ///
  /// Thư mục tồn tại chưa đủ: ổ mạng và USB rất hay cho đọc mà không cho ghi.
  static void _thuGhi(String duong) {
    final thuMuc = Directory(duong);
    try {
      if (!thuMuc.existsSync()) thuMuc.createSync(recursive: true);
    } catch (e) {
      throw BusinessException('Không tạo được thư mục "$duong": $e');
    }
    final thu = File(p.join(duong, '.canxe-thu-ghi'));
    try {
      thu.writeAsStringSync('thu');
      thu.deleteSync();
    } catch (e) {
      throw BusinessException('Thư mục "$duong" có nhưng không ghi vào được: $e');
    }
  }

  static String _dauThoiGian(DateTime v) {
    String hai(int x) => x.toString().padLeft(2, '0');
    return '${v.year}${hai(v.month)}${hai(v.day)}'
        '-${hai(v.hour)}${hai(v.minute)}${hai(v.second)}';
  }
}
