import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backup_archive.dart';

/// Một bản sao lưu đang nằm trên đám mây.
class BackupRemote {
  const BackupRemote({
    required this.ten,
    required this.soPhan,
    required this.bytes,
    this.meta,
  });

  factory BackupRemote.fromJson(Map<String, Object?> json) => BackupRemote(
        ten: json['ten']?.toString() ?? '',
        soPhan: (json['so_phan'] as num?)?.toInt() ?? 0,
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        meta: json['meta'] is Map
            ? BackupMeta.fromJson((json['meta'] as Map).cast<String, Object?>())
            : null,
      );

  final String ten;
  final int soPhan;
  final int bytes;
  final BackupMeta? meta;

  String get moTa {
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(2);
    final luc = meta?.luc.toLocal();
    final ngay = luc == null
        ? '?'
        : '${luc.day.toString().padLeft(2, '0')}/'
            '${luc.month.toString().padLeft(2, '0')}/${luc.year} '
            '${luc.hour.toString().padLeft(2, '0')}:'
            '${luc.minute.toString().padLeft(2, '0')}';
    return '$ten  •  $ngay  •  $mb MB';
  }
}

/// Nói chuyện với hàm nhận sao lưu đặt trên Vercel.
///
/// Gói sao lưu được **cắt thành nhiều phần** rồi đẩy lần lượt. Hàm không máy
/// chủ (serverless) của Vercel chỉ nhận thân yêu cầu tối đa 4,5 MB; gửi nguyên
/// gói thì hôm nay chạy được, nhưng vài năm nữa dữ liệu lớn lên là sao lưu
/// lặng lẽ hỏng — đúng kiểu hỏng tệ nhất, vì không ai để ý cho tới lúc cần.
///
/// Mỗi phần được mã hoá base64 rồi bọc trong JSON thay vì gửi byte thô: byte
/// thô phải phụ thuộc vào việc Vercel có bật bộ đọc thân yêu cầu hay không,
/// còn JSON thì chạy y nhau ở mọi cấu hình. Tốn thêm một phần ba dung lượng,
/// đổi lấy một đường đi không có chỗ nào để hỏng vặt.
class BackupStore {
  BackupStore({
    required this.url,
    required this.token,
    http.Client? client,
    this.coPhan = 2 * 1024 * 1024,
  }) : _http = client ?? http.Client();

  final String url;
  final String token;
  final http.Client _http;

  /// Cỡ mỗi phần, tính trên byte thô trước khi mã hoá base64.
  final int coPhan;

  Map<String, String> get _dau => {
        'authorization': 'Bearer $token',
        'content-type': 'application/json; charset=utf-8',
      };

  Uri _uri(Map<String, String> q) => Uri.parse(url).replace(queryParameters: q);

  /// Hỏi xem hàm trên Vercel đã sống và đã nối được kho lưu trữ chưa.
  Future<Map<String, Object?>> kiemTra() async =>
      _doc(await _http.get(_uri({'viec': 'suc-khoe'}), headers: _dau));

  /// Đẩy một gói lên, cắt thành nhiều phần. Phần mô tả được ghi **sau cùng**.
  ///
  /// Thứ tự đó là cố ý: bản nào chưa có phần mô tả thì coi như chưa xong và bị
  /// bỏ qua khi liệt kê. Nhờ vậy mất mạng giữa chừng chỉ để lại rác vô hại,
  /// chứ không tạo ra một bản sao lưu thiếu ruột mà trông vẫn lành lặn.
  Future<BackupRemote> day({
    required String ten,
    required BackupMeta meta,
    required Uint8List goi,
    int giuBan = 30,
    void Function(int phan, int tong)? tienDo,
  }) async {
    final tong = (goi.length / coPhan).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < tong; i++) {
      final tu = i * coPhan;
      final den = (tu + coPhan) > goi.length ? goi.length : tu + coPhan;
      tienDo?.call(i + 1, tong);
      _doc(await _http.post(
        _uri({'viec': 'phan', 'ban': ten, 'so': '$i'}),
        headers: _dau,
        body: jsonEncode({'du_lieu': base64.encode(goi.sublist(tu, den))}),
      ));
    }

    _doc(await _http.post(
      _uri({'viec': 'xong', 'ban': ten}),
      headers: _dau,
      body: jsonEncode({
        'so_phan': tong,
        'bytes': goi.length,
        'giu_ban': giuBan,
        'meta': meta.toJson(),
      }),
    ));

    return BackupRemote(ten: ten, soPhan: tong, bytes: goi.length, meta: meta);
  }

  /// Danh sách bản sao lưu hoàn chỉnh, mới nhất đứng đầu.
  Future<List<BackupRemote>> lietKe() async {
    final data = _doc(await _http.get(_uri({'viec': 'danh-sach'}), headers: _dau));
    final ds = data['ban'];
    if (ds is! List) return const [];
    return ds
        .whereType<Map>()
        .map((e) => BackupRemote.fromJson(e.cast<String, Object?>()))
        .toList();
  }

  /// Tải một bản về và ghép lại thành gói nguyên vẹn.
  ///
  /// Lấy từng phần qua chính hàm trên Vercel chứ không qua địa chỉ kho: gói
  /// được cất ở chế độ riêng tư nên không có địa chỉ công khai nào để mà tải.
  Future<Uint8List> tai(String ten, {void Function(int phan, int tong)? tienDo}) async {
    final data = _doc(await _http.get(_uri({'viec': 'tai', 'ban': ten}), headers: _dau));
    final soPhan = (data['so_phan'] as num?)?.toInt() ?? 0;
    if (soPhan < 1) {
      throw BackupException('Bản sao lưu "$ten" không có phần nào để tải.');
    }

    final bb = BytesBuilder(copy: false);
    for (var i = 0; i < soPhan; i++) {
      tienDo?.call(i + 1, soPhan);
      final res = await _http.get(
        _uri({'viec': 'phan', 'ban': ten, 'so': '$i'}),
        headers: {'authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) {
        // Thân phản hồi lúc lỗi là JSON, còn lúc thành công là byte thô — nên
        // chỉ đưa qua bộ đọc lỗi khi đã biết chắc là hỏng.
        _doc(res);
        throw BackupException('Tải phần ${i + 1}/$soPhan của "$ten" hỏng.');
      }
      bb.add(res.bodyBytes);
    }

    final goi = bb.takeBytes();
    final mong = (data['bytes'] as num?)?.toInt() ?? 0;
    if (mong > 0 && goi.length != mong) {
      throw BackupException(
        'Ghép lại được ${goi.length} byte nhưng phần mô tả ghi $mong byte.',
      );
    }
    return goi;
  }

  Future<void> xoa(String ten) async =>
      _doc(await _http.delete(_uri({'ban': ten}), headers: _dau));

  void dispose() => _http.close();

  /// Đọc phản hồi, biến lỗi HTTP thành câu tiếng Việt đọc được.
  Map<String, Object?> _doc(http.Response res) {
    Map<String, Object?> data = const {};
    try {
      final raw = jsonDecode(utf8.decode(res.bodyBytes));
      if (raw is Map) data = raw.cast<String, Object?>();
    } catch (_) {
      // Vercel trả trang HTML khi sai đường dẫn hoặc dự án chưa triển khai.
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final loi = data['loi']?.toString();
    throw BackupException(switch (res.statusCode) {
      401 || 403 => 'Máy chủ sao lưu từ chối: sai token. ${loi ?? ''}'.trim(),
      404 => 'Không tìm thấy hàm sao lưu ở "$url" — kiểm tra lại địa chỉ.',
      413 => 'Phần gửi lên quá cỡ Vercel cho phép. ${loi ?? ''}'.trim(),
      _ => 'Máy chủ sao lưu báo lỗi HTTP ${res.statusCode}. '
          '${loi ?? utf8.decode(res.bodyBytes).trim()}',
    });
  }
}
