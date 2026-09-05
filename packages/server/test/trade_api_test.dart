import 'dart:convert';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kiểm thử sổ mua bán.
///
/// Hai thứ phải giữ bằng mọi giá: **chỉ tài khoản chủ xem được**, và **dữ liệu
/// không rời máy chủ trung tâm**. Giá mua vào lọt ra ngoài là chuyện không sửa
/// lại được.
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late Handler handler;
  late AuthService auth;

  late String tokenChu;
  late String tokenTong;
  late String tokenTram;
  late String idCaNhan;
  late String idKhach;

  Future<Response> call(String method, String path,
          {String? token, Map<String, Object?>? body}) async =>
      handler(Request(
        method,
        Uri.parse('http://may-chu$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: body == null ? null : jsonEncode(body),
      ));

  Future<Object?> body(Response r) async => jsonDecode(await r.readAsString());

  Future<Map<String, Object?>> post(String path, Map<String, Object?> data,
      {String? token, int expectStatus = 200}) async {
    final res = await call('POST', path, token: token ?? tokenChu, body: data);
    final text = await res.readAsString();
    expect(res.statusCode, expectStatus, reason: '$path -> $text');
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
  }

  Future<Map<String, Object?>> soMuaBan([String query = '']) async =>
      (await body(await call('GET', '/api/giao-dich$query', token: tokenChu)))
          as Map<String, Object?>;

  /// Dựng máy chủ với vai trò cho trước rồi lập sẵn ba loại tài khoản.
  Future<void> dungMayChu(ServerRole role) async {
    tempDir = Directory.systemTemp.createTempSync('canxe-trade');
    database = AppDatabase.open('${tempDir.path}/thu.db');
    repo = Repository(database);
    auth = AuthService(repo, iterations: 500);

    final config = ServerRole.central == role
        ? const ServerConfig(role: ServerRole.central, stationCode: 'TRUNGTAM')
        : const ServerConfig(
            role: ServerRole.station,
            stationCode: 'KHO01',
            centralUrl: 'http://127.0.0.1:1',
          );

    final router = ApiRouter(
      config: config,
      repo: repo,
      broker: ReadingBroker(),
      tickets: TicketService(repo, defaultStationCode: config.effectiveStationCode),
      payroll: PayrollService(repo.payroll),
      trades: TradeService(repo.trades, repo),
      auth: auth,
    );
    handler = const Pipeline().addMiddleware(authMiddleware(auth)).addHandler(router.handler);

    final setup = await call('POST', '/api/auth/setup', body: {
      'username': 'chu',
      'full_name': 'Chủ',
      'password': 'matkhau123',
    });
    tokenChu = ((await body(setup)) as Map)['token'] as String;

    for (final u in [
      {'username': 'quanly', 'role': 'tong', 'station_scope': ''},
      {'username': 'nvtram', 'role': 'tram', 'station_scope': 'KHO01'},
    ]) {
      await post('/api/users', {
        ...u,
        'full_name': u['username'],
        'password': 'matkhau123',
      });
    }
    tokenTong = ((await body(await call('POST', '/api/auth/login',
            body: {'username': 'quanly', 'password': 'matkhau123'}))) as Map)['token']
        as String;
    tokenTram = ((await body(await call('POST', '/api/auth/login',
            body: {'username': 'nvtram', 'password': 'matkhau123'}))) as Map)['token']
        as String;

    idCaNhan = (await post('/api/goods-types',
        {'name': 'Cà nhân', 'default_yield_ratio': 100}))['id'] as String;
    idKhach = (await post('/api/customers', {'name': 'Nguyễn Văn Bảy'}))['id'] as String;
  }

  tearDown(() {
    database.dispose();
    tempDir.deleteSync(recursive: true);
  });

  int ngay(int y, int m, int d) => DateTime(y, m, d).toUtc().millisecondsSinceEpoch;

  group('Trên máy chủ trung tâm', () {
    setUp(() => dungMayChu(ServerRole.central));

    test('chỉ tài khoản chủ mới vào được, kể cả quản lý tổng cũng không', () async {
      expect((await call('GET', '/api/giao-dich', token: tokenChu)).statusCode, 200);

      // Quản lý tổng làm được mọi việc khác, nhưng giá mua vào là chuyện riêng
      // của chủ — đây là lý do tồn tại của cả tính năng này.
      for (final token in [tokenTong, tokenTram]) {
        expect((await call('GET', '/api/giao-dich', token: token)).statusCode, 403);
        expect(
          (await call('POST', '/api/giao-dich',
                  token: token, body: {'date': ngay(2026, 9, 5), 'amount': 1000}))
              .statusCode,
          403,
        );
      }
    });

    test('chưa đăng nhập thì bị chặn trước cả khi xét quyền chủ', () async {
      expect((await call('GET', '/api/giao-dich')).statusCode, 401);
      expect((await call('DELETE', '/api/giao-dich/bat-ky')).statusCode, 401);
    });

    test('ghi được một lần mua có hoá đơn', () async {
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'mua_vao',
        'goods_type_id': idCaNhan,
        'partner_id': idKhach,
        'quantity': 7630,
        'unit_price': 95000,
        'amount': 724850000,
        'has_invoice': true,
        'invoice_no': 'HD-0012',
      });

      expect(gd['kind'], 'mua_vao');
      expect(gd['amount'], 724850000);
      expect(gd['has_invoice'], 1);
      // Tên lấy từ danh mục chứ không nhận từ client, để không lệch khi đổi tên.
      expect(gd['goods_name'], 'Cà nhân');
      expect(gd['partner_name'], 'Nguyễn Văn Bảy');
      expect(gd['created_by'], 'chu');
    });

    test('ghi được khoản không có khối lượng', () async {
      // Tiền dầu, tiền công bốc vác: không nhân ra được từ đơn giá nên số tiền
      // phải nhập thẳng.
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 4),
        'kind': 'mua_vao',
        'goods_name': 'Dầu chạy máy',
        'amount': 12000000,
      });
      expect(gd['amount'], 12000000);
      expect(gd['quantity'], 0);
    });

    test('thiếu ngày hoặc thiếu số tiền thì bị từ chối', () async {
      await post('/api/giao-dich', {'amount': 1000}, expectStatus: 400);
      await post('/api/giao-dich', {'date': ngay(2026, 9, 5)}, expectStatus: 400);
    });

    test('số âm thì bị từ chối', () async {
      for (final xau in [
        {'amount': -1},
        {'amount': 1000, 'quantity': -5},
        {'amount': 1000, 'unit_price': -5},
      ]) {
        await post('/api/giao-dich', {'date': ngay(2026, 9, 5), ...xau},
            expectStatus: 400);
      }
    });

    test('chọn loại hàng hoặc khách không có thì bị từ chối', () async {
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'amount': 1000,
        'goods_type_id': 'khong-co',
      }, expectStatus: 400);
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'amount': 1000,
        'partner_id': 'khong-co',
      }, expectStatus: 400);
    });

    test('sửa và xoá được, xoá rồi thì không còn trong danh sách', () async {
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'mua_vao',
        'amount': 1000,
        'goods_name': 'Cà tươi',
      });

      final sua = await post('/api/giao-dich/${gd['id']}', {
        'date': ngay(2026, 9, 5),
        'amount': 2000,
        'has_invoice': true,
      });
      expect(sua['amount'], 2000);
      expect(sua['has_invoice'], 1);
      expect(sua['goods_name'], 'Cà tươi', reason: 'không gửi thì giữ nguyên');

      expect(
        (await call('DELETE', '/api/giao-dich/${gd['id']}', token: tokenChu)).statusCode,
        200,
      );
      expect(((await soMuaBan())['items'] as List), isEmpty);
    });

    test('sửa giao dịch không có thì báo lỗi chứ không lặng lẽ tạo mới', () async {
      await post('/api/giao-dich/khong-co',
          {'date': ngay(2026, 9, 5), 'amount': 1000}, expectStatus: 400);
    });
  });

  group('Số tổng và bộ lọc', () {
    setUp(() async {
      await dungMayChu(ServerRole.central);
      final mau = [
        ('mua_vao', 7000.0, 700000000.0, true, 9, 5),
        ('mua_vao', 3000.0, 300000000.0, false, 9, 6),
        ('ban_ra', 5000.0, 600000000.0, true, 9, 7),
        ('ban_ra', 1000.0, 120000000.0, false, 10, 1),
      ];
      for (final (kind, kl, tien, hd, thang, ngayTrong) in mau) {
        await post('/api/giao-dich', {
          'date': ngay(2026, thang, ngayTrong),
          'kind': kind,
          'goods_type_id': idCaNhan,
          'quantity': kl,
          'amount': tien,
          'has_invoice': hd,
        });
      }
    });

    test('tách khối lượng nhập với xuất, và tiền có hoá đơn với không', () async {
      final t = TradeSummary.fromJson(
          (await soMuaBan())['summary']! as Map<String, Object?>);

      expect(t.quantityIn, 10000);
      expect(t.quantityOut, 6000);
      expect(t.quantityBalance, 4000, reason: 'nhập trừ xuất');

      expect(t.amountIn, 1000000000);
      expect(t.amountOut, 720000000);
      expect(t.amountBalance, -280000000, reason: 'kỳ này đang bỏ tiền ra mua');

      expect(t.amountInvoiced, 1300000000);
      expect(t.amountNotInvoiced, 420000000);
      expect(t.countInvoiced, 2);
      expect(t.countNotInvoiced, 2);
    });

    test('lọc theo hoá đơn thì số tổng cũng chỉ tính phần đang xem', () async {
      // Lọc "chưa có hoá đơn" mà ô tổng vẫn là số cả kỳ thì đọc ra kết luận sai.
      final chua = await soMuaBan('?hoa_don=0');
      expect((chua['items'] as List).length, 2);
      final t = TradeSummary.fromJson(chua['summary']! as Map<String, Object?>);
      expect(t.amountNotInvoiced, 420000000);
      expect(t.amountInvoiced, 0);
    });

    test('lọc theo chiều và theo khoảng ngày', () async {
      expect(((await soMuaBan('?kind=ban_ra'))['items'] as List).length, 2);
      expect(
        ((await soMuaBan('?from=${ngay(2026, 9, 1)}&to=${ngay(2026, 9, 30)}'))['items']
                as List)
            .length,
        3,
      );
    });

    test('tìm theo tên hàng, số hoá đơn hay ghi chú', () async {
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 8),
        'amount': 500000,
        'goods_name': 'Phân bón NPK',
        'note': 'mua chịu đại lý Tám',
      });
      expect(((await soMuaBan('?q=npk'))['items'] as List).length, 1);
      expect(((await soMuaBan('?q=đại lý'))['items'] as List).length, 1);
    });

    test('mới nhất đứng đầu', () async {
      final items = (await soMuaBan())['items']! as List;
      final dau = Trade.fromJson((items.first as Map).cast<String, Object?>());
      expect(dau.date.month, 10, reason: 'giao dịch tháng 10 mới nhất');
    });
  });

  group('Trên máy trạm', () {
    setUp(() => dungMayChu(ServerRole.station));

    test('sổ mua bán bị chặn hẳn, kể cả với tài khoản chủ', () async {
      // Sổ này không đồng bộ xuống kho; mở được ở đây thì dữ liệu ghi ra sẽ
      // nằm lại một mình trên máy kho, không ai thấy.
      final res = await call('GET', '/api/giao-dich', token: tokenChu);
      final text = await res.readAsString();
      expect(res.statusCode, 409);
      expect(text, contains('máy chủ trung tâm'));

      expect(
        (await call('POST', '/api/giao-dich',
                token: tokenChu, body: {'date': ngay(2026, 9, 5), 'amount': 1000}))
            .statusCode,
        409,
      );
    });
  });

  group('Cờ tài khoản chủ', () {
    setUp(() => dungMayChu(ServerRole.central));

    test('chỉ tài khoản lập đầu tiên mang cờ chủ', () async {
      final me = (await body(await call('GET', '/api/auth/me', token: tokenChu))) as Map;
      expect(me['is_owner'], 1);

      final khac = (await body(await call('GET', '/api/auth/me', token: tokenTong))) as Map;
      expect(khac['is_owner'], 0);
    });

    test('không cấp được cờ chủ cho người khác qua API tạo tài khoản', () async {
      // Gửi kèm is_owner cũng không ăn thua: cờ chỉ đặt lúc lập tài khoản đầu
      // tiên, nếu không thì ai thêm được người dùng là tự nâng quyền cho mình.
      await post('/api/users', {
        'username': 'kesau',
        'full_name': 'Kẻ sau',
        'password': 'matkhau123',
        'role': 'tong',
        'is_owner': true,
      });
      final dn = await call('POST', '/api/auth/login',
          body: {'username': 'kesau', 'password': 'matkhau123'});
      final token = ((await body(dn)) as Map)['token'] as String;

      expect((await call('GET', '/api/giao-dich', token: token)).statusCode, 403);
    });
  });
}
