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

  group('Định mức chi phí khi bán', () {
    setUp(() async {
      await dungMayChu(ServerRole.central);
      // Trấu: mua 1.500 + điện 2.500 + xe 1.700 + công 1.500 = 7.200 đ/kg.
      await post('/api/goods-types', {
        'id': idCaNhan,
        'name': 'Trấu',
        'default_yield_ratio': 100,
        'cost_items': [
          {'name': 'Mua trấu', 'per_kg': 1500},
          {'name': 'Tiền điện', 'per_kg': 2500},
          {'name': 'Tiền xe', 'per_kg': 1700},
          {'name': 'Công', 'per_kg': 1500},
        ],
      });
    });

    test('bán ra tự chép định mức và tính ra lãi', () async {
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'ban_ra',
        'goods_type_id': idCaNhan,
        'quantity': 10000,
        'unit_price': 8000,
        'amount': 80000000,
      });

      final t = Trade.fromJson(gd);
      expect(t.costPerKg, 7200, reason: '1.500 + 2.500 + 1.700 + 1.500');
      expect(t.totalCost, 72000000);
      expect(t.profit, 8000000, reason: '80 triệu thu về trừ 72 triệu chi phí');
      expect(t.costItems.length, 4);
      expect(t.costItems.first.name, 'Mua trấu');
    });

    test('mua vào thì không gắn chi phí, lãi để trống', () async {
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'mua_vao',
        'goods_type_id': idCaNhan,
        'quantity': 10000,
        'amount': 15000000,
      });
      final t = Trade.fromJson(gd);
      expect(t.costItems, isEmpty);
      expect(t.profit, isNull, reason: 'mua vào thì chưa có gì để so');
    });

    test('sửa định mức không làm đổi lãi của lần bán cũ', () async {
      final cu = Trade.fromJson(await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'ban_ra',
        'goods_type_id': idCaNhan,
        'quantity': 10000,
        'amount': 80000000,
      }));
      expect(cu.profit, 8000000);

      // Điện tăng gấp đôi.
      await post('/api/goods-types', {
        'id': idCaNhan,
        'name': 'Trấu',
        'cost_items': [
          {'name': 'Mua trấu', 'per_kg': 1500},
          {'name': 'Tiền điện', 'per_kg': 5000},
        ],
      });

      final doc = Trade.fromJson(
          ((await soMuaBan())['items'] as List).first as Map<String, Object?>);
      expect(doc.costPerKg, 7200, reason: 'bảng chi phí đã chép, không tra lại');
      expect(doc.profit, 8000000);
    });

    test('gửi kèm bảng chi phí riêng thì dùng bảng đó', () async {
      // Chuyến này thuê xe xa hơn nên chi phí khác định mức.
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 6),
        'kind': 'ban_ra',
        'goods_type_id': idCaNhan,
        'quantity': 1000,
        'amount': 8000000,
        'cost_items': [
          {'name': 'Mua trấu', 'per_kg': 1500},
          {'name': 'Tiền xe đường xa', 'per_kg': 3000},
        ],
      });
      final t = Trade.fromJson(gd);
      expect(t.costPerKg, 4500);
      expect(t.profit, 8000000 - 4500000);
    });

    test('khoản chi âm thì bị từ chối', () async {
      await post('/api/goods-types', {
        'name': 'Hàng lỗi',
        'cost_items': [
          {'name': 'Sai', 'per_kg': -100},
        ],
      }, expectStatus: 400);
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

    test('tìm chữ kèm lọc ngày cùng lúc', () async {
      // Câu truy vấn từng trộn `?` với `?1` nên SQLite đếm sai số tham số và
      // vỡ ngay khi có cả hai bộ lọc — mà giao diện thì luôn gửi kèm khoảng
      // ngày của tháng đang xem, nên ô tìm hỏng mọi lúc.
      final res = await call(
        'GET',
        '/api/giao-dich?from=${ngay(2026, 9, 1)}&to=${ngay(2026, 9, 30)}&q=ca',
        token: tokenChu,
      );
      expect(res.statusCode, 200, reason: await res.readAsString());
    });

    test('gõ không dấu vẫn tìm ra', () async {
      // Người ta gõ nhanh thường không bật bộ gõ tiếng Việt.
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 8),
        'amount': 500000,
        'goods_name': 'Cà phê nhân xô',
        'partner_name': 'Nguyễn Văn Bảy',
      });
      for (final tu in ['ca phe', 'nhan xo', 'nguyen van bay', 'BAY']) {
        expect(((await soMuaBan('?q=$tu'))['items'] as List).length, 1,
            reason: 'tìm "$tu" phải ra');
      }
    });

    test('lọc theo loại hàng và theo đối tác', () async {
      final loaiKhac = (await post('/api/goods-types',
          {'name': 'Trấu', 'default_yield_ratio': 100}))['id'] as String;
      final khachKhac =
          (await post('/api/customers', {'name': 'Trần Thị Hoa'}))['id'] as String;
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 9),
        'amount': 800000,
        'goods_type_id': loaiKhac,
        'partner_id': khachKhac,
      });

      // Bốn dòng dựng sẵn đều là cà nhân và không có đối tác.
      expect(((await soMuaBan('?goods_type_id=$idCaNhan'))['items'] as List).length, 4);
      expect(((await soMuaBan('?goods_type_id=$loaiKhac'))['items'] as List).length, 1);
      expect(((await soMuaBan('?partner_id=$khachKhac'))['items'] as List).length, 1);

      // Số tổng phải theo đúng phần đang lọc.
      final t = TradeSummary.fromJson(
          (await soMuaBan('?goods_type_id=$loaiKhac'))['summary']! as Map<String, Object?>);
      expect(t.amountIn, 800000);
    });

    test('tổng quan cộng dồn cả sổ, không cắt theo tháng', () async {
      // Bốn dòng dựng sẵn: tháng 9 có 3, tháng 10 có 1 — tồn phải gộp cả hai.
      final tq = TradeStock.fromJson(
          (await body(await call('GET', '/api/giao-dich/tong-quan', token: tokenChu)))
              as Map<String, Object?>);

      expect(tq.summary.quantityIn, 10000);
      expect(tq.summary.quantityOut, 6000);
      expect(tq.summary.quantityBalance, 4000);

      // Cả bốn dòng cùng loại hàng nên gộp thành một dòng tồn.
      expect(tq.lines.length, 1);
      final d = tq.lines.single;
      expect(d.goodsName, 'Cà nhân');
      expect(d.quantityBalance, 4000);
      expect(d.count, 4);
      expect(d.averageCost, 100000, reason: '1.000.000.000 chia 10.000 kg');

      expect(tq.firstDate!.day, 5);
      expect(tq.lastDate!.month, 10);
    });

    test('mua gõ tay và bán chọn danh mục vẫn là một dòng', () async {
      // Cùng một mặt hàng mà tách hai dòng thì tồn ra số âm vô lý.
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 12),
        'kind': 'mua_vao',
        'goods_name': 'cà nhân',
        'quantity': 500,
        'amount': 50000000,
      });
      final tq = TradeStock.fromJson(
          (await body(await call('GET', '/api/giao-dich/tong-quan', token: tokenChu)))
              as Map<String, Object?>);
      final ca = tq.lines.where((e) => e.goodsName.toLowerCase().contains('cà nhân'));
      expect(ca.length, 1, reason: 'gõ tay và chọn danh mục phải gộp làm một');
      expect(ca.single.quantityIn, 10500);
    });

    test('mặt hàng gõ tay gộp theo tên bỏ dấu', () async {
      for (final ten in ['Phân bón', 'phan bon']) {
        await post('/api/giao-dich', {
          'date': ngay(2026, 9, 11),
          'kind': 'mua_vao',
          'goods_name': ten,
          'quantity': 100,
          'amount': 1000000,
        });
      }
      final tq = TradeStock.fromJson(
          (await body(await call('GET', '/api/giao-dich/tong-quan', token: tokenChu)))
              as Map<String, Object?>);

      final phan = tq.lines.where((e) => e.goodsTypeId == null).toList();
      expect(phan.length, 1, reason: 'hai cách viết phải là một dòng');
      expect(phan.single.quantityIn, 200);
    });

    test('xuất được file Excel của phần đang lọc', () async {
      final res = await call(
        'GET',
        '/api/giao-dich/xuat-excel?from=${ngay(2026, 9, 1)}&to=${ngay(2026, 9, 30)}',
        token: tokenChu,
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('spreadsheetml.sheet'));
      expect(res.headers['content-disposition'], contains('so-mua-ban-2026-09.xlsx'));

      final bytes = await res.read().expand((e) => e).toList();
      expect(bytes.length, greaterThan(1000));
      // .xlsx là một file zip: hai byte đầu luôn là 'PK'.
      expect(bytes.take(2).toList(), [0x50, 0x4B]);
    });

    test('xuất được file tồn kho', () async {
      final res =
          await call('GET', '/api/giao-dich/tong-quan/xuat-excel', token: tokenChu);
      expect(res.statusCode, 200);
      expect(res.headers['content-disposition'], contains('ton-kho.xlsx'));
      final bytes = await res.read().expand((e) => e).toList();
      expect(bytes.take(2).toList(), [0x50, 0x4B]);
    });

    test('xuất Excel cũng chỉ dành cho tài khoản chủ', () async {
      expect((await call('GET', '/api/giao-dich/xuat-excel', token: tokenTong)).statusCode,
          403);
      expect((await call('GET', '/api/giao-dich/xuat-excel')).statusCode, 401);
    });

    test('tổng quan cũng chỉ dành cho tài khoản chủ', () async {
      expect((await call('GET', '/api/giao-dich/tong-quan', token: tokenTong)).statusCode,
          403);
      expect((await call('GET', '/api/giao-dich/tong-quan')).statusCode, 401);
    });

    test('mới nhất đứng đầu', () async {
      final items = (await soMuaBan())['items']! as List;
      final dau = Trade.fromJson((items.first as Map).cast<String, Object?>());
      expect(dau.date.month, 10, reason: 'giao dịch tháng 10 mới nhất');
    });
  });

  group('Trên máy trạm', () {
    setUp(() => dungMayChu(ServerRole.station));

    test('mở được như ở trung tâm, vẫn chỉ chủ mới vào', () async {
      // Máy chủ nào cũng thấy sổ; dữ liệu đi kèm gói đồng bộ nên trung tâm và
      // các kho dùng chung một quyển.
      expect((await call('GET', '/api/giao-dich', token: tokenChu)).statusCode, 200);
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'mua_vao',
        'goods_name': 'Cà tươi',
        'amount': 5000000,
      });
      expect(((await soMuaBan())['items'] as List).length, 1);

      expect((await call('GET', '/api/giao-dich', token: tokenTong)).statusCode, 403);
      expect((await call('GET', '/api/giao-dich', token: tokenTram)).statusCode, 403);
    });
  });

  group('Đồng bộ', () {
    setUp(() => dungMayChu(ServerRole.central));

    test('giao dịch đi kèm gói đồng bộ và đếm vào số chờ đẩy', () async {
      await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'kind': 'mua_vao',
        'goods_name': 'Cà nhân',
        'amount': 724850000,
        'has_invoice': true,
      });

      final goi = repo.changesSince(null);
      expect(goi.trades.length, 1);
      expect(goi.trades.single.amount, 724850000);
      expect(goi.trades.single.hasInvoice, isTrue);

      // Ghi ở máy này thì phải chờ đẩy sang bên kia.
      expect(repo.dirtyChanges().trades.length, 1);
      expect(repo.pendingPushCount(), greaterThan(0));
    });

    test('nhận gói từ bên kia thì ghi vào sổ và không đẩy ngược lại', () async {
      final goiDen = SyncPayload(trades: [
        Trade.create(
          date: DateTime(2026, 9, 6),
          kind: TradeKind.banRa,
          goodsName: 'Cà khô',
          amount: 310000000,
        ),
      ]);

      expect(repo.applyPayload(goiDen), 1);
      expect(((await soMuaBan())['items'] as List).length, 1);
      // Bản vừa nhận không được đánh dấu chờ đẩy, nếu không hai máy đẩy qua
      // đẩy lại mãi.
      expect(repo.dirtyChanges().trades, isEmpty);
    });

    test('xoá rồi thì việc xoá cũng đi sang bên kia', () async {
      final gd = await post('/api/giao-dich', {
        'date': ngay(2026, 9, 5),
        'goods_name': 'Nhầm',
        'amount': 1000,
      });
      repo.clearDirty(repo.dirtyChanges());
      expect(repo.dirtyChanges().trades, isEmpty);

      await call('DELETE', '/api/giao-dich/${gd['id']}', token: tokenChu);

      final choDay = repo.dirtyChanges().trades;
      expect(choDay.length, 1, reason: 'xoá xong phải đẩy đi, không thì bên kia vẫn giữ');
      expect(choDay.single.deleted, isTrue);
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
