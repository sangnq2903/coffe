import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:canxe_server/canxe_server.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Đẩy thư mục `vercel/` lên Vercel bằng API của họ.
///
/// Không cần cài Node.js hay lệnh `vercel` trên máy: chỗ này chỉ gửi nội dung
/// mấy file lên, phần cài đặt gói và biên dịch do Vercel làm ở phía họ.
///
/// Chìa khoá đọc từ thư mục `.secrets/` (đã gitignore) hoặc từ biến môi
/// trường — cố ý không nhận chìa khoá qua tham số dòng lệnh, vì tham số bị ghi
/// lại trong lịch sử lệnh của PowerShell và hiện ra trong danh sách tiến trình.
///
///   dart run bin/trien_khai_vercel.dart
///   dart run bin/trien_khai_vercel.dart --du-an canxe-sao-luu
Future<void> main(List<String> arguments) async {
  enableUtf8Console();

  final parser = ArgParser()
    ..addOption('du-an', defaultsTo: 'canxe-sao-luu', help: 'Tên dự án trên Vercel.')
    ..addOption('goc', help: 'Thư mục gốc kho mã. Mặc định tự dò lên từ chỗ đang đứng.')
    ..addFlag('help', abbr: 'h', negatable: false);
  final args = parser.parse(arguments);

  if (args.flag('help')) {
    stdout.writeln('Triển khai kho sao lưu lên Vercel.\n\n${parser.usage}');
    return;
  }

  final goc = args.option('goc') ?? _timGocKho();
  final biMat = Directory(p.join(goc, '.secrets'));
  final duAn = args.option('du-an')!;

  final vercelToken = _doiChiaKhoa(
    biMat,
    'vercel-token.txt',
    'VERCEL_TOKEN',
    'Chìa khoá Vercel. Lấy ở https://vercel.com/account/tokens',
  );
  if (vercelToken == null) exit(78);

  // Chìa khoá giữa máy chủ ở nhà và hàm trên Vercel. Tự sinh nếu chưa có: để
  // người dùng tự nghĩ ra thì hay ra chuỗi ngắn và đoán được.
  final canxeToken = _docHoacSinh(biMat, 'canxe-token.txt');
  final teamId = _docNeuCo(biMat, 'vercel-team.txt') ??
      Platform.environment['VERCEL_TEAM_ID'];

  final api = _VercelApi(vercelToken, teamId: teamId);
  try {
    final ai = await api.toiLaAi();
    stdout.writeln('Đăng nhập với tài khoản: $ai${teamId == null ? '' : '  (đội $teamId)'}');

    stdout.writeln('\n1/4  Bảo đảm dự án "$duAn" tồn tại...');
    await api.taoDuAnNeuChua(duAn);

    stdout.writeln('2/4  Đặt biến môi trường CANXE_TOKEN...');
    await api.datBien(duAn, 'CANXE_TOKEN', canxeToken);

    stdout.writeln('3/4  Gửi mã nguồn và chờ Vercel dựng...');
    final files = _docThuMuc(p.join(goc, 'vercel'));
    stdout.writeln('     ${files.length} file: '
        '${files.map((f) => f['file']).join(", ")}');
    final url = await api.trienKhai(duAn, files);

    stdout.writeln('4/4  Thử gọi hàm...');
    await _thuGoi('https://$url/api/sao-luu', canxeToken);

    stdout.writeln('''

XONG. Điền vào packages/server/config.sao-luu.json:

  "url":   "https://$url/api/sao-luu"
  "token": "(xem file .secrets/canxe-token.txt)"

Còn một việc phải làm bằng tay trên trang Vercel: mở dự án "$duAn" >
tab Storage > Create Database > Blob, rồi nối vào dự án này. Vercel sẽ tự
thêm biến BLOB_READ_WRITE_TOKEN. Chưa làm bước đó thì hàm chạy nhưng chưa
có chỗ cất.''');
  } on _VercelLoi catch (e) {
    stderr.writeln('\nVercel báo lỗi: ${e.message}');
    exit(1);
  } finally {
    api.dispose();
  }
}

// --------------------------------------------------------------- chìa khoá

String _timGocKho() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (Directory(p.join(dir.path, 'vercel')).existsSync() &&
        Directory(p.join(dir.path, 'packages')).existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return Directory.current.path;
}

String? _docNeuCo(Directory thuMuc, String ten) {
  final f = File(p.join(thuMuc.path, ten));
  if (!f.existsSync()) return null;
  final v = f.readAsStringSync().trim();
  return v.isEmpty ? null : v;
}

String? _doiChiaKhoa(Directory thuMuc, String ten, String bien, String moTa) {
  final v = Platform.environment[bien];
  if (v != null && v.isNotEmpty) return v;
  final tuFile = _docNeuCo(thuMuc, ten);
  if (tuFile != null) return tuFile;

  stderr.writeln('''
Chưa có chìa khoá Vercel.

$moTa

Đặt nó vào file này (thư mục .secrets đã bị gitignore, không lên git):
  ${p.join(thuMuc.path, ten)}

Hoặc đặt biến môi trường $bien.''');
  return null;
}

/// Đọc chìa khoá, chưa có thì sinh một chuỗi ngẫu nhiên đủ dài và ghi lại.
String _docHoacSinh(Directory thuMuc, String ten) {
  final co = _docNeuCo(thuMuc, ten);
  if (co != null) return co;

  final r = Random.secure();
  final moi = base64Url
      .encode(List<int>.generate(32, (_) => r.nextInt(256)))
      .replaceAll('=', '');
  thuMuc.createSync(recursive: true);
  File(p.join(thuMuc.path, ten)).writeAsStringSync(moi);
  stdout.writeln('Đã sinh chìa khoá mới, cất ở ${p.join(thuMuc.path, ten)}');
  return moi;
}

/// Đọc cả thư mục thành danh sách file để gửi lên, bỏ qua thứ không nên gửi.
List<Map<String, String>> _docThuMuc(String goc) {
  // 'kiem-thu' là bộ chạy thử chạy trong trình duyệt ở máy mình, không việc
  // gì phải đem lên máy chủ.
  const boQua = {'node_modules', '.vercel', '.git', 'kiem-thu'};
  final ra = <Map<String, String>>[];
  for (final e in Directory(goc).listSync(recursive: true)) {
    if (e is! File) continue;
    final duong = p.relative(e.path, from: goc).replaceAll(r'\', '/');
    if (duong.split('/').any(boQua.contains)) continue;
    ra.add({
      'file': duong,
      'data': base64.encode(e.readAsBytesSync()),
      'encoding': 'base64',
    });
  }
  ra.sort((a, b) => a['file']!.compareTo(b['file']!));
  return ra;
}

Future<void> _thuGoi(String url, String token) async {
  final client = http.Client();
  try {
    final mo = await client.get(Uri.parse(url));
    stdout.writeln('     GET $url -> ${mo.statusCode} ${mo.body.trim()}');

    final suc = await client.get(
      Uri.parse('$url?viec=suc-khoe'),
      headers: {'authorization': 'Bearer $token'},
    );
    stdout.writeln('     GET ?viec=suc-khoe -> ${suc.statusCode} ${suc.body.trim()}');
    if (suc.statusCode == 500 && suc.body.contains('BLOB_READ_WRITE_TOKEN')) {
      stdout.writeln('     (chưa nối kho Blob — xem hướng dẫn cuối bài)');
    }
  } catch (e) {
    stdout.writeln('     Gọi thử không được: $e');
  } finally {
    client.close();
  }
}

// ------------------------------------------------------------------- API

class _VercelLoi implements Exception {
  _VercelLoi(this.message);

  final String message;
}

class _VercelApi {
  _VercelApi(this._token, {this.teamId});

  final String _token;
  final String? teamId;
  final _http = http.Client();

  Map<String, String> get _dau => {
        'authorization': 'Bearer $_token',
        'content-type': 'application/json',
      };

  Uri _uri(String duong, [Map<String, String> q = const {}]) =>
      Uri.https('api.vercel.com', duong, {
        if (teamId != null) 'teamId': teamId!,
        ...q,
      });

  Future<String> toiLaAi() async {
    final res = await _http.get(_uri('/v2/user'), headers: _dau);
    final data = _doc(res);
    final u = data['user'] as Map?;
    return (u?['username'] ?? u?['email'] ?? '?').toString();
  }

  Future<void> taoDuAnNeuChua(String ten) async {
    final co = await _http.get(_uri('/v9/projects/$ten'), headers: _dau);
    if (co.statusCode == 200) {
      stdout.writeln('     Dự án đã có sẵn.');
      return;
    }
    _doc(await _http.post(
      _uri('/v10/projects'),
      headers: _dau,
      body: jsonEncode({'name': ten, 'framework': null}),
    ));
    stdout.writeln('     Đã tạo dự án mới.');
  }

  /// Đặt biến môi trường; đã có thì sửa lại chứ không tạo trùng.
  Future<void> datBien(String duAn, String khoa, String giaTri) async {
    final res = await _http.post(
      _uri('/v10/projects/$duAn/env', {'upsert': 'true'}),
      headers: _dau,
      body: jsonEncode({
        'key': khoa,
        'value': giaTri,
        'type': 'encrypted',
        'target': ['production', 'preview', 'development'],
      }),
    );
    _doc(res);
  }

  /// Gửi file lên và chờ tới khi Vercel dựng xong. Trả về địa chỉ dùng được.
  Future<String> trienKhai(String duAn, List<Map<String, String>> files) async {
    final data = _doc(await _http.post(
      _uri('/v13/deployments', {'skipAutoDetectionConfirmation': '1'}),
      headers: _dau,
      body: jsonEncode({
        'name': duAn,
        'project': duAn,
        'target': 'production',
        'files': files,
        'projectSettings': {
          'framework': null,
          'buildCommand': null,
          'installCommand': null,
          'outputDirectory': 'public',
        },
      }),
    ));

    final id = data['id']?.toString();
    if (id == null) throw _VercelLoi('Vercel không trả về mã bản triển khai.');

    // Vercel dựng xong mới gọi được. Chờ ở đây thay vì bảo người dùng tự vào
    // trang xem, và để bước gọi thử phía sau nói được điều gì đó có nghĩa.
    for (var i = 0; i < 90; i++) {
      final tt = _doc(await _http.get(_uri('/v13/deployments/$id'), headers: _dau));
      final trangThai = tt['readyState']?.toString() ?? '';
      if (trangThai == 'READY') {
        final url = (tt['alias'] as List?)?.whereType<String>().firstOrNull ??
            tt['url']?.toString() ??
            '';
        stdout.writeln('     Dựng xong sau ${i * 2} giây.');
        return url;
      }
      if (trangThai == 'ERROR' || trangThai == 'CANCELED') {
        throw _VercelLoi(
          'Dựng hỏng ($trangThai). Xem nhật ký: '
          'https://vercel.com/${tt['ownerId']}/$duAn/$id',
        );
      }
      if (i % 5 == 0) stdout.writeln('     ...$trangThai');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw _VercelLoi('Chờ 3 phút vẫn chưa dựng xong — vào trang Vercel xem thử.');
  }

  Map<String, Object?> _doc(http.Response res) {
    Map<String, Object?> data = const {};
    try {
      final raw = jsonDecode(utf8.decode(res.bodyBytes));
      if (raw is Map) data = raw.cast<String, Object?>();
    } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    final loi = data['error'];
    final thongDiep = loi is Map ? loi['message']?.toString() : null;
    throw _VercelLoi(
      'HTTP ${res.statusCode} — ${thongDiep ?? utf8.decode(res.bodyBytes).trim()}',
    );
  }

  void dispose() => _http.close();
}
