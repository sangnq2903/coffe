import 'package:canxe_server/canxe_server.dart';
import 'package:test/test.dart';

void main() {
  group('relay_uplinks trong cấu hình trạm', () {
    test('đọc được danh sách máy chủ nhận thêm số cân', () {
      final config = ServerConfig.fromJson({
        'role': 'station',
        'station': {'code': 'KHO02'},
        'central': {'url': 'http://100.76.81.118:9080', 'username': 'a', 'password': 'b'},
        'relay_uplinks': [
          {'url': 'http://100.76.81.118:9081', 'username': 'admin2', 'password': 'mk'},
        ],
      });
      expect(config.relayUplinks, hasLength(1));
      expect(config.relayUplinks.single.url, 'http://100.76.81.118:9081');
      expect(config.relayUplinks.single.username, 'admin2');
    });

    test('bỏ qua mục thiếu địa chỉ hoặc tài khoản, không làm hỏng cấu hình', () {
      final config = ServerConfig.fromJson({
        'role': 'station',
        'relay_uplinks': [
          {'url': 'http://may-khac:9081'},
          {'url': '', 'username': 'a', 'password': 'b'},
          'khong-phai-doi-tuong',
        ],
      });
      expect(config.relayUplinks, isEmpty);
    });

    test('không khai thì là danh sách rỗng', () {
      final config = ServerConfig.fromJson({'role': 'central'});
      expect(config.relayUplinks, isEmpty);
    });

    test('copyWith giữ danh sách và đổi được tài khoản đăng nhập', () {
      final config = ServerConfig.fromJson({
        'role': 'station',
        'central': {'url': 'http://trung-tam:9080', 'username': 'a', 'password': 'b'},
        'relay_uplinks': [
          {'url': 'http://may-khac:9081', 'username': 'x', 'password': 'y'},
        ],
      });
      final copy = config.copyWith(
        centralUrl: 'http://may-khac:9081',
        centralUsername: 'x',
        centralPassword: 'y',
      );
      expect(copy.centralUsername, 'x');
      expect(copy.centralPassword, 'y');
      expect(copy.relayUplinks, hasLength(1));
      expect(config.centralUsername, 'a', reason: 'bản gốc không bị đổi');
    });
  });
}
