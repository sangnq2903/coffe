import 'dart:convert';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
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

  group('Chấm công', () {
    /// Dựng nền để chấm công được: hai giai đoạn, một mức lương, một người.
    ///
    /// Đầu mùa 8 triệu tới 15/10, mùa rộ 12 triệu từ 16/10 — đúng ví dụ trong
    /// README để đọc test là hiểu luật.
    Future<Map<String, String>> dungNen() async {
      final dauMua = await post('/api/doan/$doanA/giai-doan', {
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
      });
      final muaRo = await post('/api/doan/$doanA/giai-doan', {
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
      });
      final muc = await post('/api/doan/$doanA/muc-luong', {'name': 'Thợ chính'});
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': dauMua['id'],
        'band_id': muc['id'],
        'monthly_amount': 8000000,
      });
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': muaRo['id'],
        'band_id': muc['id'],
        'monthly_amount': 12000000,
      });
      final nv = await post('/api/doan/$doanA/nhan-vien', {
        'name': 'A Tình',
        'band_id': muc['id'],
        'station_code': 'KHO01',
        'join_date': ngay(2026, 9, 1),
      });
      return {
        'dau_mua': dauMua['id']! as String,
        'mua_ro': muaRo['id']! as String,
        'muc': muc['id']! as String,
        'nv': nv['id']! as String,
      };
    }

    Future<Map<String, Object?>> chamCong(
      String workerId,
      List<int> days, {
      int year = 2026,
      int month = 9,
      bool present = true,
    }) async {
      Map<String, Object?> last = const {};
      for (final d in days) {
        last = await post('/api/doan/$doanA/cham-cong', {
          'date': ngay(year, month, d),
          'marks': {workerId: present},
        });
      }
      return last;
    }

    Future<Map<String, Object?>> bangThang({int year = 2026, int month = 9}) async =>
        (await body(await call('GET',
            '/api/doan/$doanA/cham-cong/thang?year=$year&month=$month',
            token: tokenTong))) as Map<String, Object?>;

    test('ngày chưa thuộc giai đoạn nào thì không chấm được', () async {
      final nen = await dungNen();
      // 31/8 nằm ngoài mọi giai đoạn — chấm được thì lấy lương ở đâu ra.
      final res = await call('POST', '/api/doan/$doanA/cham-cong',
          token: tokenTong,
          body: {
            'date': ngay(2026, 8, 31),
            'marks': {nen['nv']!: true},
          });
      final text = await res.readAsString();
      expect(res.statusCode, 400);
      expect(text, contains('chưa thuộc giai đoạn lương nào'));
    });

    test('chưa chấm khác với chấm là nghỉ', () async {
      final nen = await dungNen();

      final truoc = (await body(await call('GET',
          '/api/doan/$doanA/cham-cong?date=${ngay(2026, 9, 10)}',
          token: tokenTong))) as Map;
      final dongTruoc = ((truoc['rows'] as List).single as Map);
      expect(dongTruoc['present'], isNull, reason: 'chưa chấm thì phải là null');
      expect(truoc['marked_count'], 0);

      final sau = await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 10),
        'marks': {nen['nv']!: false},
      });
      final dongSau = ((sau['rows'] as List).single as Map);
      expect(dongSau['present'], false, reason: 'đã chấm là nghỉ thì phải là false');
      expect(sau['marked_count'], 1);
      expect(sau['present_count'], 0);
    });

    test('người chưa gán mức lương thì bị bỏ qua kèm lý do', () async {
      final nen = await dungNen();
      final chuaGan = await post('/api/doan/$doanA/nhan-vien', {'name': 'Người mới'});

      final res = await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 10),
        'marks': {nen['nv']!: true, chuaGan['id']!: true},
      });

      final bo = res['skipped'] as List;
      expect(bo.length, 1);
      expect((bo.single as Map)['name'], 'Người mới');
      expect((bo.single as Map)['reason'], contains('chưa gán mức lương'));
      // Một người thiếu cấu hình không được làm cả đoàn không chấm công được.
      expect(res['present_count'], 1);
    });

    test('người vào làm sau không hiện ở ngày trước đó', () async {
      await dungNen();
      await post('/api/doan/$doanA/nhan-vien', {
        'name': 'Vào giữa tháng',
        'join_date': ngay(2026, 9, 15),
      });

      final ngay10 = (await body(await call('GET',
          '/api/doan/$doanA/cham-cong?date=${ngay(2026, 9, 10)}',
          token: tokenTong))) as Map;
      final ngay20 = (await body(await call('GET',
          '/api/doan/$doanA/cham-cong?date=${ngay(2026, 9, 20)}',
          token: tokenTong))) as Map;

      expect((ngay10['rows'] as List).length, 1);
      expect((ngay20['rows'] as List).length, 2);
    });

    test('đi làm đủ tháng ra đúng lương tháng, không lệch vài đồng', () async {
      final nen = await dungNen();
      // Tháng 9 có 30 ngày; chia 8.000.000 cho 30 ra số lẻ vô hạn, cộng dồn
      // từng ngày sẽ không ra đúng 8.000.000.
      await chamCong(nen['nv']!, [for (var d = 1; d <= 30; d++) d]);

      final thang = await bangThang();
      final dong = ((thang['rows'] as List).single as Map);
      expect(dong['days_worked'], 30);
      expect(dong['wage_earned'], 8000000);
      expect(thang['total_wage'], 8000000);
    });

    test('nghỉ ngày nào mất công ngày đó', () async {
      final nen = await dungNen();
      await chamCong(nen['nv']!, [for (var d = 1; d <= 29; d++) d]);
      await chamCong(nen['nv']!, [30], present: false);

      final dong = (((await bangThang())['rows'] as List).single as Map);
      expect(dong['days_worked'], 29);
      expect(dong['wage_earned'], (8000000 * 29 / 30).round());
    });

    test('tháng vắt qua hai giai đoạn thì cộng hai phần', () async {
      final nen = await dungNen();
      // Tháng 10 có 31 ngày: 15 ngày đầu mùa + 16 ngày mùa rộ.
      await chamCong(nen['nv']!, [for (var d = 1; d <= 31; d++) d], month: 10);

      final dong = (((await bangThang(month: 10))['rows'] as List).single as Map);
      expect(dong['days_worked'], 31);
      expect(
        dong['wage_earned'],
        (8000000 * 15 / 31 + 12000000 * 16 / 31).round(),
        reason: 'gộp theo từng mức lương rồi mới chia',
      );
    });

    test('sửa bảng giá không làm đổi lương ngày đã chấm', () async {
      final nen = await dungNen();
      await chamCong(nen['nv']!, [1, 2, 3]);

      // Tăng giá đầu mùa lên gấp đôi rồi chấm thêm một ngày nữa.
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': nen['dau_mua'],
        'band_id': nen['muc'],
        'monthly_amount': 16000000,
      });
      await chamCong(nen['nv']!, [4]);

      final dong = (((await bangThang())['rows'] as List).single as Map);
      expect(
        dong['wage_earned'],
        (8000000 * 3 / 30 + 16000000 * 1 / 30).round(),
        reason: 'ba ngày cũ giữ giá cũ, ngày mới mới theo giá mới',
      );
    });

    test('chấm lại ngày cũ vẫn giữ mức lương lúc chấm', () async {
      final nen = await dungNen();
      await chamCong(nen['nv']!, [1, 2, 3]);
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': nen['dau_mua'],
        'band_id': nen['muc'],
        'monthly_amount': 16000000,
      });

      // Sửa ngày 3 thành nghỉ rồi cho đi làm lại — không được nhân giá mới.
      await chamCong(nen['nv']!, [3], present: false);
      await chamCong(nen['nv']!, [3]);

      final dong = (((await bangThang())['rows'] as List).single as Map);
      expect(dong['wage_earned'], (8000000 * 3 / 30).round());
    });

    test('nút tính lại mới đổi mức lương của quá khứ', () async {
      final nen = await dungNen();
      await chamCong(nen['nv']!, [1, 2, 3]);
      await post('/api/doan/$doanA/gia-luong', {
        'phase_id': nen['dau_mua'],
        'band_id': nen['muc'],
        'monthly_amount': 16000000,
      });

      final ketQua = await post('/api/doan/$doanA/cham-cong/tinh-lai',
          {'year': 2026, 'month': 9});
      expect(ketQua['count'], 3);
      expect((ketQua['changed'] as List).length, 3);
      expect(((ketQua['changed'] as List).first as Map)['from'], 8000000);
      expect(((ketQua['changed'] as List).first as Map)['to'], 16000000);

      final dong = (((await bangThang())['rows'] as List).single as Map);
      expect(dong['wage_earned'], (16000000 * 3 / 30).round());

      // Bấm lại lần nữa thì không còn gì để đổi.
      final lanHai = await post('/api/doan/$doanA/cham-cong/tinh-lai',
          {'year': 2026, 'month': 9});
      expect(lanHai['count'], 0);
    });

    test('ngày chấm công lưu kèm kho lúc đó', () async {
      final nen = await dungNen();
      await chamCong(nen['nv']!, [10]);

      await post('/api/doan/$doanA/chuyen-kho', {
        'worker_ids': [nen['nv']],
        'station_code': 'KHO02',
      });
      await chamCong(nen['nv']!, [11]);

      final ghi = repo.payroll.attendances(crewId: doanA);
      expect(ghi.firstWhere((a) => a.date.day == 10).stationCode, 'KHO01');
      expect(ghi.firstWhere((a) => a.date.day == 11).stationCode, 'KHO02');
    });

    test('thiếu ngày hoặc thiếu danh sách thì bị từ chối', () async {
      final nen = await dungNen();
      await post('/api/doan/$doanA/cham-cong',
          {'marks': {nen['nv']!: true}}, expectStatus: 400);
      await post('/api/doan/$doanA/cham-cong',
          {'date': ngay(2026, 9, 10)}, expectStatus: 400);
      await post('/api/doan/$doanA/cham-cong',
          {'date': ngay(2026, 9, 10), 'marks': const {}}, expectStatus: 400);
    });

    test('không chấm được cho người của đoàn khác', () async {
      final nen = await dungNen();
      final nguoiDoanB = await post('/api/doan/$doanB/nhan-vien', {'name': 'Người đoàn B'});
      await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 10),
        'marks': {nen['nv']!: true, nguoiDoanB['id']!: true},
      }, expectStatus: 400);
    });

    test('khai giờ làm cho giai đoạn, giờ chuẩn tự tính ra', () async {
      final nen = await dungNen();
      await post('/api/doan/$doanA/giai-doan', {
        'id': nen['mua_ro'],
        'name': 'Mùa rộ',
        'from_date': ngay(2026, 10, 16),
        'work_start': '07:00',
        'work_end': '22:00',
        'break_hours': 3,
      });

      final bang = (await body(await call('GET', '/api/doan/$doanA/bang-luong',
          token: tokenTong))) as Map;
      final phases = (bang['phases'] as List).cast<Map>();
      final muaRo = WagePhase.fromJson(
          phases.firstWhere((p) => p['id'] == nen['mua_ro']).cast<String, Object?>());
      final dauMua = WagePhase.fromJson(
          phases.firstWhere((p) => p['id'] == nen['dau_mua']).cast<String, Object?>());

      expect(muaRo.standardHours, 12, reason: '7h–22h trừ 3 giờ nghỉ trưa và tối');
      expect(dauMua.standardHours, 8.5, reason: 'mặc định 7h–17h trừ 1,5 giờ nghỉ trưa');
    });

    test('giờ làm sai dạng hoặc giờ nghỉ nuốt cả ca thì bị từ chối', () async {
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Sai giờ',
        'from_date': ngay(2026, 9, 1),
        'work_start': '7h',
        'work_end': '17:00',
      }, expectStatus: 400);
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Nghỉ quá ca',
        'from_date': ngay(2026, 9, 1),
        'work_start': '07:00',
        'work_end': '17:00',
        'break_hours': 10,
      }, expectStatus: 400);
      await post('/api/doan/$doanA/giai-doan', {
        'name': 'Về trước khi vào',
        'from_date': ngay(2026, 9, 1),
        'work_start': '17:00',
        'work_end': '07:00',
      }, expectStatus: 400);
    });

    test('nghỉ vài giờ thì công tính theo tỷ lệ trên giờ chuẩn', () async {
      final nen = await dungNen();
      final res = await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 1),
        'marks': {nen['nv']!: true},
        'hours_off': {nen['nv']!: 2},
      });
      final dong = (res['rows'] as List).single as Map;
      expect(dong['hours_off'], 2);
      expect(dong['standard_hours'], 8.5);
      expect(dong['work_unit'], closeTo(6.5 / 8.5, 1e-9));

      final thang = await bangThang();
      final dongThang = (thang['rows'] as List).single as Map;
      expect(dongThang['days_worked'], 1, reason: 'vẫn đếm là một ngày có đi làm');
      expect(dongThang['work_units'], closeTo(6.5 / 8.5, 1e-9));
      expect(dongThang['wage_earned'], (8000000 * (6.5 / 8.5) / 30).round());
      expect((dongThang['partial_days'] as Map)['1'], 6.5);
      expect(thang['total_work_units'], closeTo(6.5 / 8.5, 1e-9));
    });

    test('không gửi giờ nghỉ thì giữ nguyên số đã ghi', () async {
      final nen = await dungNen();
      await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 1),
        'marks': {nen['nv']!: true},
        'hours_off': {nen['nv']!: 2},
      });
      // Bấm "đi làm" lần nữa (ví dụ nút "đi làm hết") không được xoá 2 giờ.
      final res = await chamCong(nen['nv']!, [1]);
      expect(((res['rows'] as List).single as Map)['hours_off'], 2);
    });

    test('chấm là nghỉ cả ngày thì giờ nghỉ tự về 0', () async {
      final nen = await dungNen();
      await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 1),
        'marks': {nen['nv']!: true},
        'hours_off': {nen['nv']!: 2},
      });
      final nghi = await chamCong(nen['nv']!, [1], present: false);
      expect(((nghi['rows'] as List).single as Map)['hours_off'], 0);

      final lamLai = await chamCong(nen['nv']!, [1]);
      expect(((lamLai['rows'] as List).single as Map)['work_unit'], 1,
          reason: 'cho đi làm lại thì bắt đầu từ đủ ngày');
    });

    test('giờ nghỉ bằng hoặc vượt giờ chuẩn thì bị chặn', () async {
      final nen = await dungNen();
      for (final gio in [8.5, 9, -1]) {
        await post('/api/doan/$doanA/cham-cong', {
          'date': ngay(2026, 9, 1),
          'marks': {nen['nv']!: true},
          'hours_off': {nen['nv']!: gio},
        }, expectStatus: 400);
      }
    });

    test('đổi giờ làm hôm nay không đổi công ngày đã chấm, trừ khi bấm tính lại',
        () async {
      final nen = await dungNen();
      await post('/api/doan/$doanA/cham-cong', {
        'date': ngay(2026, 9, 1),
        'marks': {nen['nv']!: true},
        'hours_off': {nen['nv']!: 2},
      });

      // Đầu mùa đổi thành ca 7h–18h (9,5 giờ chuẩn).
      await post('/api/doan/$doanA/giai-doan', {
        'id': nen['dau_mua'],
        'name': 'Đầu mùa',
        'from_date': ngay(2026, 9, 1),
        'to_date': ngay(2026, 10, 15),
        'work_end': '18:00',
      });

      var dong = ((await bangThang())['rows'] as List).single as Map;
      expect(dong['work_units'], closeTo(6.5 / 8.5, 1e-9), reason: 'giữ giờ chuẩn lúc chấm');

      final ketQua = await post('/api/doan/$doanA/cham-cong/tinh-lai',
          {'year': 2026, 'month': 9});
      expect(ketQua['count'], 1);
      expect(((ketQua['changed'] as List).single as Map)['hours_to'], 9.5);

      dong = ((await bangThang())['rows'] as List).single as Map;
      expect(dong['work_units'], closeTo(7.5 / 9.5, 1e-9));
    });

    test('tháng ngoài 1-12 thì bị từ chối', () async {
      await dungNen();
      expect(
        (await call('GET', '/api/doan/$doanA/cham-cong/thang?year=2026&month=13',
                token: tokenTong))
            .statusCode,
        400,
      );
    });
  });

  group('Chưa đăng nhập', () {
    test('mọi đường dẫn chấm công đều bị chặn', () async {
      for (final path in [
        '/api/doan',
        '/api/doan/$doanA',
        '/api/doan/$doanA/bang-luong',
        '/api/doan/$doanA/nhan-vien',
        '/api/doan/$doanA/cham-cong',
        '/api/doan/$doanA/cham-cong/thang',
      ]) {
        expect((await call('GET', path)).statusCode, 401, reason: path);
      }
    });
  });
}
