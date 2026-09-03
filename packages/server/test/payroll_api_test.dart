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
  late String doanA;
  late String doanB;

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

    doanA = (await post('/api/doan',
        {'name': 'Đoàn hái', 'season': '2025-2026'}))['id'] as String;
    doanB = (await post('/api/doan',
        {'name': 'Đoàn tưới', 'season': '2025-2026'}))['id'] as String;

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
      await post('/api/doan', const {'season': '2025-2026'}, expectStatus: 400);
    });

    test('tài khoản trạm cũng làm được lương của cả công ty', () async {
      // Người trong đoàn chuyển kho qua lại nên bảng lương không cắt theo kho;
      // ai đăng nhập được cũng chấm công và xem lương được.
      final list = (await body(await call('GET', '/api/doan', token: tokenKho1))) as List;
      expect(list.length, 2);

      expect((await call('GET', '/api/doan/$doanB', token: tokenKho1)).statusCode, 200);
      await post('/api/doan', const {'name': 'Đoàn mới'}, token: tokenKho1);
    });
  });

  group('Giai đoạn lương', () {
    test('khai được hai giai đoạn nối tiếp nhau', () async {
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
      });

      final bang = await body(await call('GET', '/api/doan/$doanA/bang-luong',
          token: tokenTong)) as Map;
      expect((bang['phases'] as List).length, 2);
    });

    test('hai giai đoạn phủ lên cùng một ngày thì bị chặn', () async {
      // Chồng nhau thì một ngày tra ra hai mức lương, kết quả phụ thuộc thứ tự
      // đọc trong cơ sở dữ liệu — sai lặng lẽ tới lúc trả lương mới lộ.
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      final res = await call('POST', '/api/doan/$doanA/giai-doan',
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
      await post('/api/doan/$doanA/giai-doan',
          {'name': 'Mùa rộ', 'from_date': ngay(2026, 10, 16)});
      final res = await call('POST', '/api/doan/$doanA/giai-doan',
          token: tokenTong,
          body: {'name': 'Thêm', 'from_date': ngay(2026, 12, 1)});
      expect(res.statusCode, 400);
    });

    test('sửa chính giai đoạn đó thì không tự báo trùng với chính nó', () async {
      final phase = await post('/api/doan/$doanA/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      await post('/api/doan/$doanA/giai-doan', {
        'id': phase['id'],
        'name': 'Đầu mùa (sửa)',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 20),
      });
    });

    test('ngày kết thúc trước ngày bắt đầu thì bị từ chối', () async {
      await post('/api/doan/$doanA/giai-doan', {
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
      phaseDau = (await post('/api/doan/$doanA/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      }))['id'] as String;
      phaseRo = (await post('/api/doan/$doanA/giai-doan', {
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
      }))['id'] as String;
      bandChinh = (await post(
          '/api/doan/$doanA/muc-luong', {'name': 'Thợ chính'}))['id'] as String;
    });

    test('khai giá cho từng giai đoạn', () async {
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseRo, 'band_id': bandChinh, 'monthly_amount': 12000000});

      final bang = await body(
          await call('GET', '/api/doan/$doanA/bang-luong', token: tokenTong)) as Map;
      expect((bang['rates'] as List).length, 2);
      expect(bang['missing'], isEmpty);
    });

    test('sửa giá không đẻ thêm dòng mới', () async {
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8500000});

      final rates = repo.payroll.rates(doanA);
      expect(rates.length, 1, reason: 'mỗi cặp giai đoạn × mức chỉ có một giá');
      expect(rates.single.monthlyAmount, 8500000);
    });

    test('ô chưa khai giá được chỉ ra rõ', () async {
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': 8000000});

      final bang = await body(
          await call('GET', '/api/doan/$doanA/bang-luong', token: tokenTong)) as Map;
      final thieu = bang['missing'] as List;
      expect(thieu.length, 1);
      expect((thieu.single as Map)['phase_name'], 'Mùa rộ');
    });

    test('giá phải gắn với mức HOẶC người, không được cả hai', () async {
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'monthly_amount': 8000000}, expectStatus: 400);
      final nv = await post('/api/doan/$doanA/nhan-vien', {'name': 'A'});
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': phaseDau,
        'band_id': bandChinh,
        'worker_id': nv['id'],
        'monthly_amount': 8000000,
      }, expectStatus: 400);
    });

    test('lương âm bị từ chối', () async {
      await post('/api/doan/$doanA/gia-luong',
          {'phase_id': phaseDau, 'band_id': bandChinh, 'monthly_amount': -1},
          expectStatus: 400);
    });

    test('không xoá được mức đang có người hưởng', () async {
      await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình', 'band_id': bandChinh});
      final res = await call('DELETE', '/api/doan/$doanA/muc-luong/$bandChinh',
          token: tokenTong);
      final text = await res.readAsString();
      expect(res.statusCode, 400);
      expect(text, contains('đang hưởng mức này'));
    });
  });

  group('Nhân viên', () {
    test('thêm và tra lại được', () async {
      await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình', 'phone': '0900'});
      final list =
          (await body(await call('GET', '/api/doan/$doanA/nhan-vien', token: tokenTong)))
              as List;
      expect(list.length, 1);
      expect((list.single as Map)['name'], 'A Tình');
    });

    test('thiếu tên thì bị từ chối', () async {
      await post('/api/doan/$doanA/nhan-vien', {'phone': '0900'}, expectStatus: 400);
    });

    test('gán mức lương của đoàn khác bị chặn', () async {
      final bandKho2 =
          await post('/api/doan/$doanB/muc-luong', {'name': 'Mức kho 2'});
      await post('/api/doan/$doanA/nhan-vien',
          {'name': 'A', 'band_id': bandKho2['id']}, expectStatus: 400);
    });

    test('cho nghỉ làm thì đổi trạng thái chứ không xoá', () async {
      final nv = await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình'});
      await post('/api/nhan-vien/${nv['id']}/nghi-lam', const {});

      final dangLam = (await body(await call(
          'GET', '/api/doan/$doanA/nhan-vien?status=dang_lam',
          token: tokenTong))) as List;
      final daNghi = (await body(await call(
          'GET', '/api/doan/$doanA/nhan-vien?status=da_nghi',
          token: tokenTong))) as List;

      expect(dangLam, isEmpty);
      expect(daNghi.length, 1, reason: 'lịch sử và công nợ của họ phải giữ nguyên');
    });

    test('cho làm lại được', () async {
      final nv = await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình'});
      await post('/api/nhan-vien/${nv['id']}/nghi-lam', const {});
      await post('/api/nhan-vien/${nv['id']}/lam-lai', const {});
      expect(repo.payroll.workerById(nv['id'] as String)!.isWorking, isTrue);
    });

    test('lọc được nhân viên theo kho đang làm', () async {
      await post('/api/doan/$doanA/nhan-vien',
          {'name': 'Ở kho 1', 'station_code': 'KHO01'});
      await post('/api/doan/$doanA/nhan-vien',
          {'name': 'Ở kho 2', 'station_code': 'kho02'});

      final kho1 = (await body(await call(
          'GET', '/api/doan/$doanA/nhan-vien?kho=KHO01',
          token: tokenTong))) as List;
      expect(kho1.map((e) => (e as Map)['name']), ['Ở kho 1']);

      // Viết chữ thường vẫn phải tra ra, không thì lọc trên giao diện sẽ trượt.
      final kho2 = (await body(await call(
          'GET', '/api/doan/$doanA/nhan-vien?kho=kho02',
          token: tokenTong))) as List;
      expect(kho2.map((e) => (e as Map)['name']), ['Ở kho 2']);
    });
  });

  group('Chuyển kho', () {
    test('chuyển được nhiều người một lượt', () async {
      final a = await post('/api/doan/$doanA/nhan-vien',
          {'name': 'A Tình', 'station_code': 'KHO01'});
      final b = await post('/api/doan/$doanA/nhan-vien',
          {'name': 'B Nhớ', 'station_code': 'KHO01'});

      final moved = (await body(await call('POST', '/api/doan/$doanA/chuyen-kho',
          token: tokenKho1,
          body: {
            'worker_ids': [a['id'], b['id']],
            'station_code': 'kho02',
          }))) as List;

      expect(moved.length, 2);
      expect(moved.map((e) => (e as Map)['station_code']).toSet(), {'KHO02'});
    });

    test('chuyển một người thì nhận cả dạng worker_id', () async {
      final a = await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình'});
      final moved = (await body(await call('POST', '/api/doan/$doanA/chuyen-kho',
          token: tokenTong,
          body: {'worker_id': a['id'], 'station_code': 'KHO02'}))) as List;
      expect((moved.single as Map)['station_code'], 'KHO02');
    });

    test('không chuyển được người của đoàn khác', () async {
      final nguoiDoanB = await post('/api/doan/$doanB/nhan-vien', {'name': 'Người đoàn B'});
      await post('/api/doan/$doanA/chuyen-kho', {
        'worker_ids': [nguoiDoanB['id']],
        'station_code': 'KHO02',
      }, expectStatus: 400);
    });

    test('thiếu kho hoặc thiếu người thì bị từ chối', () async {
      final a = await post('/api/doan/$doanA/nhan-vien', {'name': 'A Tình'});
      await post('/api/doan/$doanA/chuyen-kho',
          {'worker_ids': [a['id']]}, expectStatus: 400);
      await post('/api/doan/$doanA/chuyen-kho',
          const {'station_code': 'KHO02'}, expectStatus: 400);
    });
  });

  group('Chưa đăng nhập', () {
    test('mọi đường dẫn chấm công đều bị chặn', () async {
      for (final path in [
        '/api/doan',
        '/api/doan/$doanA',
        '/api/doan/$doanA/bang-luong',
        '/api/doan/$doanA/nhan-vien',
      ]) {
        expect((await call('GET', path)).statusCode, 401, reason: path);
      }
    });
  });
}
