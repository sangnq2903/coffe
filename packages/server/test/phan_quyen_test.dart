import 'dart:convert';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kiểm thử phân quyền ở tầng máy chủ.
///
/// Đây là chỗ đáng kiểm nhất của toàn hệ thống: lỗi phân quyền không làm gì đổ
/// vỡ ầm ĩ, nó chỉ lặng lẽ cho người kho 1 xem được sổ sách kho 2 mà không ai
/// biết. Test chạy thẳng vào handler HTTP thật, không giả lập, nên đúng những
/// gì trình duyệt gọi cũng là những gì test gọi.
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Repository repo;
  late AuthService auth;
  late Handler handler;

  late String tokenTong;
  late String tokenTram;
  late WeighTicket phieuKho1;
  late WeighTicket phieuKho2;

  Future<Response> call(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? body,
  }) async {
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

  Future<Object?> json(Response response) async =>
      jsonDecode(await response.readAsString());

  Future<String> login(String username, String password) async {
    final res = await call('POST', '/api/auth/login',
        body: {'username': username, 'password': password});
    expect(res.statusCode, 200, reason: 'đăng nhập "$username" phải thành công');
    return ((await json(res)) as Map)['token'] as String;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('canxe-phan-quyen');
    database = AppDatabase.open('${tempDir.path}/thu.db');
    repo = Repository(database);
    // Hạ số vòng băm để test chạy trong vài giây thay vì vài phút.
    auth = AuthService(repo, iterations: 500);

    const config = ServerConfig(role: ServerRole.central, stationCode: 'TRUNGTAM');
    final router = ApiRouter(
      config: config,
      repo: repo,
      broker: ReadingBroker(),
      tickets: TicketService(repo, defaultStationCode: 'TRUNGTAM'),
      auth: auth,
    );
    handler = const Pipeline().addMiddleware(authMiddleware(auth)).addHandler(router.handler);

    // Tài khoản quản lý tổng đầu tiên.
    final setup = await call('POST', '/api/auth/setup', body: {
      'username': 'chu',
      'full_name': 'Nguyễn Văn Chủ',
      'password': 'matkhau123',
    });
    expect(setup.statusCode, 200);
    tokenTong = ((await json(setup)) as Map)['token'] as String;

    // Mỗi kho một phiếu, để kiểm xem ai nhìn thấy phiếu nào.
    Future<WeighTicket> lapPhieu(String kho, String bienSo) async {
      final res = await call('POST', '/api/tickets', token: tokenTong, body: {
        'station_code': kho,
        'plate_no': bienSo,
        'goods_name': 'Cà tươi',
        'first_weight': 10000,
      });
      expect(res.statusCode, 200, reason: 'lập phiếu cho $kho');
      return WeighTicket.fromJson(((await json(res)) as Map).cast<String, Object?>());
    }

    phieuKho1 = await lapPhieu('KHO01', '51C-11111');
    phieuKho2 = await lapPhieu('KHO02', '51C-22222');

    // Tài khoản trạm, chỉ được gán kho 1.
    final tao = await call('POST', '/api/users', token: tokenTong, body: {
      'username': 'tram01',
      'full_name': 'Nhân viên kho 1',
      'password': 'matkhau123',
      'role': 'tram',
      'station_scope': 'KHO01',
    });
    expect(tao.statusCode, 200);
    tokenTram = await login('tram01', 'matkhau123');
  });

  tearDown(() {
    database.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('Cửa đăng nhập', () {
    test('không có phiếu phiên thì mọi API đều bị chặn', () async {
      for (final path in [
        '/api/tickets',
        '/api/stations',
        '/api/customers',
        '/api/scale/current',
        '/api/users',
        '/api/sync/pull?since=0',
      ]) {
        final res = await call('GET', path);
        expect(res.statusCode, 401, reason: 'phải chặn $path');
      }
    });

    test('phiếu phiên giả mạo bị từ chối', () async {
      final res = await call('GET', '/api/tickets', token: 'toi.tu.ky');
      expect(res.statusCode, 401);
    });

    test('trang trạng thái và đăng nhập vẫn mở khi chưa đăng nhập', () async {
      // Nếu chặn cả hai đường này thì không ai đăng nhập được nữa.
      expect((await call('GET', '/api/auth/status')).statusCode, 200);
      expect((await call('GET', '/api/health')).statusCode, 200);
    });

    test('sai mật khẩu bị từ chối, và không tiết lộ tên đăng nhập nào có thật', () async {
      final saiMatKhau = await call('POST', '/api/auth/login',
          body: {'username': 'chu', 'password': 'sai-be-bet'});
      final khongCoNguoi = await call('POST', '/api/auth/login',
          body: {'username': 'khong-ton-tai', 'password': 'sai-be-bet'});

      expect(saiMatKhau.statusCode, 401);
      expect(khongCoNguoi.statusCode, 401);
      expect(
        ((await json(saiMatKhau)) as Map)['error'],
        ((await json(khongCoNguoi)) as Map)['error'],
        reason: 'hai thông báo phải giống hệt nhau',
      );
    });

    test('tạo tài khoản chủ lần thứ hai bị chặn', () async {
      final res = await call('POST', '/api/auth/setup', body: {
        'username': 'ke-gian',
        'full_name': 'X',
        'password': 'matkhau123',
      });
      expect(res.statusCode, 403);
    });

    test('tên đăng nhập không phân biệt hoa thường', () async {
      expect(await login('CHU', 'matkhau123'), isNotEmpty);
    });
  });

  group('Tài khoản quản lý tổng', () {
    test('thấy phiếu của mọi kho', () async {
      final list = (await json(await call('GET', '/api/tickets', token: tokenTong))) as List;
      final khos = list.map((e) => (e as Map)['station_code']).toSet();
      expect(khos, containsAll(['KHO01', 'KHO02']));
    });

    test('vào được phần quản lý tài khoản', () async {
      final res = await call('GET', '/api/users', token: tokenTong);
      expect(res.statusCode, 200);
    });

    test('không tự xoá được chính mình', () async {
      final me = AppUser.fromJson(
          ((await json(await call('GET', '/api/auth/me', token: tokenTong))) as Map)
              .cast<String, Object?>());
      final res = await call('DELETE', '/api/users/${me.id}', token: tokenTong);
      // Xoá được thì không còn ai quản trị, hệ thống thành khoá chết.
      expect(res.statusCode, 400);
    });
  });

  group('Tài khoản trạm cân — chỉ thấy kho của mình', () {
    test('danh sách phiếu chỉ có kho được gán', () async {
      final list = (await json(await call('GET', '/api/tickets', token: tokenTram))) as List;
      expect(list, isNotEmpty);
      for (final item in list) {
        expect((item as Map)['station_code'], 'KHO01');
      }
    });

    test('danh sách kho chỉ có kho được gán', () async {
      final list = (await json(await call('GET', '/api/stations', token: tokenTram))) as List;
      for (final item in list) {
        expect((item as Map)['code'], 'KHO01');
      }
    });

    test('mở phiếu của kho khác bị chặn', () async {
      final res = await call('GET', '/api/tickets/${phieuKho2.id}', token: tokenTram);
      expect(res.statusCode, 403);
    });

    test('vẫn mở được phiếu của kho mình', () async {
      final res = await call('GET', '/api/tickets/${phieuKho1.id}', token: tokenTram);
      expect(res.statusCode, 200);
    });

    test('lọc thẳng sang kho khác cũng bị chặn', () async {
      // Giấu trên giao diện là chưa đủ: gõ tay tham số vẫn phải bị từ chối.
      final res = await call('GET', '/api/tickets?station=KHO02', token: tokenTram);
      expect(res.statusCode, 403);
    });

    test('xem số cân của kho khác bị chặn', () async {
      final res = await call('GET', '/api/scale/current?station=KHO02', token: tokenTram);
      expect(res.statusCode, 403);
    });

    test('lập phiếu cho kho khác bị chặn', () async {
      final res = await call('POST', '/api/tickets', token: tokenTram, body: {
        'station_code': 'KHO02',
        'plate_no': '51C-99999',
        'first_weight': 5000,
      });
      expect(res.statusCode, 403);
    });

    test('sửa và huỷ phiếu của kho khác đều bị chặn', () async {
      expect(
        (await call('POST', '/api/tickets/${phieuKho2.id}', token: tokenTram, body: {'note': 'x'}))
            .statusCode,
        403,
      );
      expect(
        (await call('POST', '/api/tickets/${phieuKho2.id}/cancel',
                token: tokenTram, body: {'reason': 'x'}))
            .statusCode,
        403,
      );
      expect(
        (await call('POST', '/api/tickets/${phieuKho2.id}/second-weigh',
                token: tokenTram, body: {'second_weight': 3000}))
            .statusCode,
        403,
      );
      expect(
        (await call('DELETE', '/api/tickets/${phieuKho2.id}', token: tokenTram)).statusCode,
        403,
      );
    });

    test('vẫn làm được việc của kho mình', () async {
      final res = await call('POST', '/api/tickets', token: tokenTram, body: {
        'station_code': 'KHO01',
        'plate_no': '51C-77777',
        'goods_name': 'Trấu',
        'first_weight': 9000,
      });
      expect(res.statusCode, 200);
    });

    test('không vào được phần quản lý tài khoản', () async {
      expect((await call('GET', '/api/users', token: tokenTram)).statusCode, 403);
      expect(
        (await call('POST', '/api/users', token: tokenTram, body: {
          'username': 'tu-phong',
          'full_name': 'X',
          'password': 'matkhau123',
          'role': 'tong',
        }))
            .statusCode,
        403,
      );
    });

    test('vẫn dùng chung được danh mục khách hàng và loại hàng', () async {
      // Danh mục là của cả hệ thống: chặn ở đây thì xe lạ vào kho lúc nửa đêm
      // là nhân viên không lập nổi phiếu.
      expect((await call('GET', '/api/customers', token: tokenTram)).statusCode, 200);
      expect((await call('GET', '/api/goods-types', token: tokenTram)).statusCode, 200);
      expect(
        (await call('POST', '/api/customers', token: tokenTram, body: {'name': 'Khách mới'}))
            .statusCode,
        200,
      );
    });
  });

  group('Đồng bộ cũng bị giới hạn theo phạm vi', () {
    test('gói kéo về của tài khoản trạm không chứa phiếu kho khác', () async {
      // Nếu thiếu chỗ này thì ổ cứng máy ở kho 1 vẫn lưu đủ dữ liệu kho 2,
      // chỉ là màn hình không hiện — ai mở file cơ sở dữ liệu là đọc được hết.
      final payload = SyncPayload.fromJson(
        ((await json(await call('GET', '/api/sync/pull?since=0', token: tokenTram))) as Map)
            .cast<String, Object?>(),
      );
      expect(payload.tickets, isNotEmpty);
      for (final ticket in payload.tickets) {
        expect(ticket.stationCode, 'KHO01');
      }
    });

    test('tài khoản tổng kéo về đủ mọi kho', () async {
      final payload = SyncPayload.fromJson(
        ((await json(await call('GET', '/api/sync/pull?since=0', token: tokenTong))) as Map)
            .cast<String, Object?>(),
      );
      expect(payload.tickets.map((e) => e.stationCode).toSet(), containsAll(['KHO01', 'KHO02']));
    });

    test('tài khoản trạm không đẩy lên được phiếu của kho khác', () async {
      final gaiMao = phieuKho2.copyWith(note: 'sửa trộm');
      final res = await call('POST', '/api/sync/push', token: tokenTram, body: {
        'tickets': [gaiMao.toJson()],
      });
      expect(res.statusCode, 403);
    });
  });

  group('Người lập phiếu', () {
    test('lấy từ tài khoản đang đăng nhập, không nhận từ client', () async {
      final res = await call('POST', '/api/tickets', token: tokenTram, body: {
        'station_code': 'KHO01',
        'plate_no': '51C-88888',
        'first_weight': 7000,
        // Cố tình khai tên người khác — máy chủ phải bỏ qua.
        'created_by': 'Người Khác',
      });
      final ticket =
          WeighTicket.fromJson(((await json(res)) as Map).cast<String, Object?>());
      expect(ticket.createdBy, 'Nhân viên kho 1');
    });
  });

  group('Chuỗi băm mật khẩu', () {
    test('không bao giờ lọt ra ngoài qua API', () async {
      final res = await call('GET', '/api/users', token: tokenTong);
      final body = await res.readAsString();
      expect(body.contains('password_hash'), isFalse);
      expect(body.contains('salt'), isFalse);
    });

    test('nhưng vẫn đi kèm trong gói đồng bộ để trạm đăng nhập offline được', () async {
      final payload = SyncPayload.fromJson(
        ((await json(await call('GET', '/api/sync/pull?since=0', token: tokenTong))) as Map)
            .cast<String, Object?>(),
      );
      expect(payload.users, isNotEmpty);
      expect(payload.users.first.passwordHash, isNotNull);
      expect(payload.users.first.passwordHash, isNotEmpty);
    });
  });
}
