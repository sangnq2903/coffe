import 'dart:convert';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kiểm thử API quản lý đoàn, giai đoạn lương, mức lương và nhân viên.
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late Handler handler;

  late String tokenTong;
  late String tokenKho1;
  late String doanKho1;
  late String doanKho2;

  Future<Response> call(String method, String path,
      {String? token, Map<String, Object?>? body}) async {
    return handler(Request(
      method,
      Uri.parse('http://may-chu$path'),
      headers: {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    ));
  }

  Future<Object?> body(Response r) async => jsonDecode(await r.readAsString());

  Future<Map<String, Object?>> post(String path, Map<String, Object?> data,
      {String? token, int expectStatus = 200}) async {
    final res = await call('POST', path, token: token ?? tokenTong, body: data);
    // Thân phản hồi của shelf chỉ đọc được một lần, nên đọc ra biến rồi mới
    // vừa dùng cho thông báo lỗi vừa giải mã.
    final text = await res.readAsString();
    expect(res.statusCode, expectStatus, reason: '$path -> $text');
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('canxe-payroll-api');
    database = AppDatabase.open('${tempDir.path}/thu.db');
    repo = Repository(database);
    final auth = AuthService(repo, iterations: 500);

    const config = ServerConfig(role: ServerRole.central, stationCode: 'TRUNGTAM');
    final router = ApiRouter(
      config: config,
      repo: repo,
      broker: ReadingBroker(),
      tickets: TicketService(repo, defaultStationCode: 'TRUNGTAM'),
      payroll: PayrollService(repo.payroll),
      auth: auth,
    );
    handler = const Pipeline().addMiddleware(authMiddleware(auth)).addHandler(router.handler);

    final setup = await call('POST', '/api/auth/setup', body: {
      'username': 'chu',
      'full_name': 'Chủ',
      'password': 'matkhau123',
    });
    tokenTong = ((await body(setup)) as Map)['token'] as String;

    doanKho1 = (await post('/api/doan',
        {'name': 'Đoàn hái', 'season': '2025-2026', 'station_code': 'KHO01'}))['id'] as String;
    doanKho2 = (await post('/api/doan',
        {'name': 'Đoàn hái', 'season': '2025-2026', 'station_code': 'KHO02'}))['id'] as String;

    await post('/api/users', {
      'username': 'tram01',
      'full_name': 'NV Kho 1',
      'password': 'matkhau123',
      'role': 'tram',
      'station_scope': 'KHO01',
    });
    final dn = await call('POST', '/api/auth/login',
        body: {'username': 'tram01', 'password': 'matkhau123'});
    tokenKho1 = ((await body(dn)) as Map)['token'] as String;
  });

  tearDown(() {
    database.dispose();
    tempDir.deleteSync(recursive: true);
  });

  int ngay(int y, int m, int d) => DateTime(y, m, d).toUtc().millisecondsSinceEpoch;

  group('Đoàn', () {
    test('lập được đoàn và đọc lại', () async {
      final list = (await body(await call('GET', '/api/doan', token: tokenTong))) as List;
      expect(list.length, 2);
    });

    test('thiếu tên thì bị từ chối', () async {
      await post('/api/doan', {'station_code': 'KHO01'}, expectStatus: 400);
    });

    test('tài khoản trạm chỉ thấy đoàn của kho mình', () async {
      final list = (await body(await call('GET', '/api/doan', token: tokenKho1))) as List;
      expect(list.length, 1);
      expect((list.single as Map)['station_code'], 'KHO01');
    });

    test('tài khoản trạm không mở được đoàn kho khác', () async {
      expect((await call('GET', '/api/doan/$doanKho2', token: tokenKho1)).statusCode, 403);
      expect(
        (await call('POST', '/api/doan/$doanKho2', token: tokenKho1, body: {'name': 'x'}))
            .statusCode,
        403,
      );
    });

    test('tài khoản trạm không lập được đoàn cho kho khác', () async {
      await post('/api/doan', {'name': 'Trộm', 'station_code': 'KHO02'},
          token: tokenKho1, expectStatus: 403);
    });
  });

  group('Giai đoạn lương', () {
    test('khai được hai giai đoạn nối tiếp nhau', () async {
      await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
      });

      final bang = await body(await call('GET', '/api/doan/$doanKho1/bang-luong',
          token: tokenTong)) as Map;
      expect((bang['phases'] as List).length, 2);
    });

    test('hai giai đoạn phủ lên cùng một ngày thì bị chặn', () async {
      // Chồng nhau thì một ngày tra ra hai mức lương, kết quả phụ thuộc thứ tự
      // đọc trong cơ sở dữ liệu — sai lặng lẽ tới lúc trả lương mới lộ.
      await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      final res = await call('POST', '/api/doan/$doanKho1/giai-doan',
          token: tokenTong,
          body: {
            'name': 'Mùa rộ',
            'from_date': ngay(2026, 10, 10),
          });
      final text = await res.readAsString();
      expect(res.statusCode, 400);
      expect(text, contains('trùng với giai đoạn'));
    });

    test('giai đoạn chưa chốt ngày kết thúc cũng bị coi là phủ về sau', () async {
      await post('/api/doan/$doanKho1/giai-doan',
          {'name': 'Mùa rộ', 'from_date': ngay(2026, 10, 16)});
      final res = await call('POST', '/api/doan/$doanKho1/giai-doan',
          token: tokenTong,
          body: {'name': 'Thêm', 'from_date': ngay(2026, 12, 1)});
      expect(res.statusCode, 400);
    });

    test('sửa chính giai đoạn đó thì không tự báo trùng với chính nó', () async {
      final phase = await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      await post('/api/doan/$doanKho1/giai-doan', {
        'id': phase['id'],
        'name': 'Đầu mùa (sửa)',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 20),
      });
    });

    test('ngày kết thúc trước ngày bắt đầu thì bị từ chối', () async {
      await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Sai',
        'from_date': ngay(2026, 10, 1),
        'to_date': ngay(2026, 9, 1),
      }, expectStatus: 400);
    });
  });

  group('Mức lương và giá', () {
    late String phaseDau;
    late String phaseRo;
    late String bandChinh;

    setUp(() async {
      phaseDau = (await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      }))['id'] as String;
      phaseRo = (await post('/api/doan/$doanKho1/giai-doan', {
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
      }))['id'] as String;
      bandChinh = (await post(
          '/api/doan/$doanKho1/muc-luong', {'name': 'Thợ chính'}))['id'] as String;
    });

    test('khai giá cho từng giai đoạn', () async {
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseRo, 'band_id': bandChinh, 'monthly_amount': 12000000});

      final bang = await body(
          await call('GET', '/api/doan/$doanKho1/bang-luong', token: tokenTong)) as Map;
      expect((bang['rates'] as List).length, 2);
      expect(bang['missing'], isEmpty);
    });

    test('sửa giá không đẻ thêm dòng mới', () async {
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8500000});

      final rates = repo.payroll.rates(doanKho1);
      expect(rates.length, 1, reason: 'mỗi cặp giai đoạn × mức chỉ có một giá');
      expect(rates.single.monthlyAmount, 8500000);
    });

    test('ô chưa khai giá được chỉ ra rõ', () async {
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});

      final bang = await body(
          await call('GET', '/api/doan/$doanKho1/bang-luong', token: tokenTong)) as Map;
      final thieu = bang['missing'] as List;
      expect(thieu.length, 1);
      expect((thieu.single as Map)['phase_name'], 'Mùa rộ');
    });

    test('giá phải gắn với mức HOẶC người, không được cả hai', () async {
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'monthly_amount': 8000000}, expectStatus: 400);
      final nv = await post('/api/doan/$doanKho1/nhan-vien', {'name': 'A'});
      await post('/api/doan/$doanKho1/gia-luong', {
        'phase_id': phaseDau,
        'band_id': bandChinh,
        'worker_id': nv['id'],
        'monthly_amount': 8000000,
      }, expectStatus: 400);
    });

    test('lương âm bị từ chối', () async {
      await post('/api/doan/$doanKho1/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': -1},
          expectStatus: 400);
    });

    test('không xoá được mức đang có người hưởng', () async {
      await post('/api/doan/$doanKho1/nhan-vien', {'name': 'A Tình', 'band_id': bandChinh});
      final res = await call('DELETE', '/api/doan/$doanKho1/muc-luong/$bandChinh',
          token: tokenTong);
      final text = await res.readAsString();
      expect(res.statusCode, 400);
      expect(text, contains('đang hưởng mức này'));
    });
  });

  group('Nhân viên', () {
    test('thêm và tra lại được', () async {
      await post('/api/doan/$doanKho1/nhan-vien', {'name': 'A Tình', 'phone': '0900'});
      final list =
          (await body(await call('GET', '/api/doan/$doanKho1/nhan-vien', token: tokenTong)))
              as List;
      expect(list.length, 1);
      expect((list.single as Map)['name'], 'A Tình');
    });

    test('thiếu tên thì bị từ chối', () async {
      await post('/api/doan/$doanKho1/nhan-vien', {'phone': '0900'}, expectStatus: 400);
    });

    test('gán mức lương của đoàn khác bị chặn', () async {
      final bandKho2 =
          await post('/api/doan/$doanKho2/muc-luong', {'name': 'Mức kho 2'});
      await post('/api/doan/$doanKho1/nhan-vien',
          {'name': 'A', 'band_id': bandKho2['id']}, expectStatus: 400);
    });

    test('cho nghỉ làm thì đổi trạng thái chứ không xoá', () async {
      final nv = await post('/api/doan/$doanKho1/nhan-vien', {'name': 'A Tình'});
      await post('/api/nhan-vien/${nv['id']}/nghi-lam', const {});

      final dangLam = (await body(await call(
          'GET', '/api/doan/$doanKho1/nhan-vien?status=dang_lam',
          token: tokenTong))) as List;
      final daNghi = (await body(await call(
          'GET', '/api/doan/$doanKho1/nhan-vien?status=da_nghi',
          token: tokenTong))) as List;

      expect(dangLam, isEmpty);
      expect(daNghi.length, 1, reason: 'lịch sử và công nợ của họ phải giữ nguyên');
    });

    test('cho làm lại được', () async {
      final nv = await post('/api/doan/$doanKho1/nhan-vien', {'name': 'A Tình'});
      await post('/api/nhan-vien/${nv['id']}/nghi-lam', const {});
      await post('/api/nhan-vien/${nv['id']}/lam-lai', const {});
      expect(repo.payroll.workerById(nv['id'] as String)!.isWorking, isTrue);
    });

    test('tài khoản trạm không đụng được nhân viên của kho khác', () async {
      final nvKho2 = await post('/api/doan/$doanKho2/nhan-vien', {'name': 'Người kho 2'});
      await post('/api/nhan-vien/${nvKho2['id']}/nghi-lam', const {},
          token: tokenKho1, expectStatus: 403);
      expect(
        (await call('GET', '/api/doan/$doanKho2/nhan-vien', token: tokenKho1)).statusCode,
        403,
      );
    });
  });

  group('Chưa đăng nhập', () {
    test('mọi đường dẫn chấm công đều bị chặn', () async {
      for (final path in [
        '/api/doan',
        '/api/doan/$doanKho1',
        '/api/doan/$doanKho1/bang-luong',
        '/api/doan/$doanKho1/nhan-vien',
      ]) {
        expect((await call('GET', path)).statusCode, 401, reason: path);
      }
    });
  });
}
