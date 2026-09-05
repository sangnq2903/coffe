import 'dart:convert';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kiểm thử sửa, huỷ và xoá phiếu cân.
///
/// Phiếu cân là chứng từ giao hàng: sửa được thì phải sửa đúng, và phải phân
/// biệt rõ huỷ (còn trong sổ để tra) với xoá (biến mất).
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late Handler handler;
  // Gán rỗng chứ không dùng `late`: chính lời gọi lập tài khoản đầu tiên
  // cũng đi qua hàm `call`, mà lúc đó chưa có phiếu phiên nào.
  String token = '';

  Future<Response> call(String method, String path,
          {Map<String, Object?>? body}) async =>
      handler(Request(
        method,
        Uri.parse('http://may-chu$path'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: body == null ? null : jsonEncode(body),
      ));

  Future<Map<String, Object?>> post(String path, Map<String, Object?> data,
      {int expectStatus = 200}) async {
    final res = await call('POST', path, body: data);
    final text = await res.readAsString();
    expect(res.statusCode, expectStatus, reason: '$path -> $text');
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
  }

  Future<WeighTicket> lapPhieu({
    String plate = '47C-12345',
    double lan1 = 12000,
  }) async =>
      WeighTicket.fromJson(await post('/api/tickets', {
        'plate_no': plate,
        'goods_name': 'Cà nhân',
        'customer_name': 'Nguyễn Văn Bảy',
        'first_weight': lan1,
      }));

  Future<List<WeighTicket>> danhSach() async {
    final res = await call('GET', '/api/tickets');
    final data = jsonDecode(await res.readAsString());
    final items = data is Map ? data['items'] : data;
    return (items as List)
        .map((e) => WeighTicket.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('canxe-ticket');
    database = AppDatabase.open('${tempDir.path}/thu.db');
    repo = Repository(database);
    final auth = AuthService(repo, iterations: 500);

    const config = ServerConfig(role: ServerRole.central, stationCode: 'KHO01');
    final router = ApiRouter(
      config: config,
      repo: repo,
      broker: ReadingBroker(),
      tickets: TicketService(repo, defaultStationCode: 'KHO01'),
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
    token = (jsonDecode(await setup.readAsString()) as Map)['token'] as String;
  });

  tearDown(() {
    database.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('Sửa phiếu', () {
    test('sửa được biển số gõ sai', () async {
      final p = await lapPhieu(plate: '47C-12345');
      final sua = WeighTicket.fromJson(
          await post('/api/tickets/${p.id}', {'plate_no': '47C-54321'}));
      expect(sua.plateNo, '47C-54321');
    });

    test('sửa hai số cân thì KL hàng tính lại', () async {
      final p = await lapPhieu(lan1: 12000);
      final sua = WeighTicket.fromJson(await post('/api/tickets/${p.id}', {
        'first_weight': 13000,
        'second_weight': 5000,
      }));
      expect(sua.firstWeight, 13000);
      expect(sua.secondWeight, 5000);
      expect(sua.netWeight, 8000, reason: 'máy chủ tự tính, không nhận số sẵn');
      expect(sua.status.value, TicketStatus.hoanThanh.value);
    });

    test('tỷ lệ thành phẩm đổi thì KL thành phẩm đổi theo', () async {
      final p = await lapPhieu();
      final sua = WeighTicket.fromJson(await post('/api/tickets/${p.id}', {
        'second_weight': 4000,
        'yield_ratio': 50,
      }));
      expect(sua.netWeight, 8000);
      expect(sua.productWeight, 4000);
    });

    test('tỷ lệ ngoài 0–100 thì bị từ chối', () async {
      final p = await lapPhieu();
      await post('/api/tickets/${p.id}', {'yield_ratio': 150}, expectStatus: 400);
    });

    test('sửa sang biển đang có phiếu chờ khác thì bị chặn', () async {
      // Hai phiếu dở dang cùng biển thì cân lần 2 không biết khớp vào phiếu nào.
      await lapPhieu(plate: '47C-11111');
      final b = await lapPhieu(plate: '47C-22222');

      final res = await call('POST', '/api/tickets/${b.id}',
          body: {'plate_no': '47C-11111'});
      final text = await res.readAsString();
      expect(res.statusCode, 400);
      expect(text, contains('chờ cân lần 2'));
    });

    test('giữ nguyên biển của chính nó thì không tự báo trùng', () async {
      final p = await lapPhieu(plate: '47C-33333');
      final sua = WeighTicket.fromJson(
          await post('/api/tickets/${p.id}', {'plate_no': '47C-33333', 'note': 'ghi'}));
      expect(sua.plateNo, '47C-33333');
      expect(sua.note, 'ghi');
    });

    test('sửa phiếu không có thì báo lỗi', () async {
      await post('/api/tickets/khong-co', {'note': 'x'}, expectStatus: 400);
    });
  });

  group('Huỷ và xoá', () {
    test('huỷ thì phiếu vẫn còn trong sổ, kèm lý do', () async {
      final p = await lapPhieu();
      final huy = WeighTicket.fromJson(await post(
          '/api/tickets/${p.id}/cancel', {'reason': 'xe quay đầu không giao'}));

      expect(huy.status.value, TicketStatus.huy.value);
      expect(huy.note, contains('xe quay đầu'));
      expect((await danhSach()).map((e) => e.id), contains(p.id),
          reason: 'huỷ chứ không xoá — còn phải tra lại được');
    });

    test('xoá thì biến mất khỏi danh sách', () async {
      final p = await lapPhieu();
      expect((await call('DELETE', '/api/tickets/${p.id}')).statusCode, 200);
      expect((await danhSach()).map((e) => e.id), isNot(contains(p.id)));
    });

    test('xoá rồi thì xe đó lập phiếu mới được ngay', () async {
      // Xoá phiếu lập nhầm mà vẫn bị chặn "đang có phiếu chờ" thì bế tắc.
      final p = await lapPhieu(plate: '47C-99999');
      await call('DELETE', '/api/tickets/${p.id}');
      final moi = await lapPhieu(plate: '47C-99999');
      expect(moi.id, isNot(p.id));
    });

    test('huỷ rồi thì xe đó cũng lập phiếu mới được', () async {
      final p = await lapPhieu(plate: '47C-88888');
      await post('/api/tickets/${p.id}/cancel', {'reason': 'nhầm'});
      final moi = await lapPhieu(plate: '47C-88888');
      expect(moi.id, isNot(p.id));
    });
  });
}
