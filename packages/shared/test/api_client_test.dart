import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

void main() {
  group('ApiClient — dựng địa chỉ', () {
    test('địa chỉ WebSocket không được chứa dấu "#"', () {
      // Trình duyệt từ chối thẳng mọi URL WebSocket có mảnh neo. Lỗi này từng
      // làm màn hình số cân không bao giờ nối được, trong khi các lời gọi HTTP
      // vẫn chạy nên rất khó nhận ra.
      final client = ApiClient(baseUrl: Uri.parse('http://100.76.81.118:9081/'));
      final ws = client.wsUri('/ws/scale', {'station': 'KHO01'});

      expect(ws.hasFragment, isFalse);
      expect(ws.toString(), isNot(contains('#')));
      expect(ws.toString(), 'ws://100.76.81.118:9081/ws/scale?station=KHO01');
    });

    test('bỏ được phần truy vấn và mảnh neo có sẵn trong địa chỉ gốc', () {
      // Trên web, địa chỉ gốc lấy từ thanh địa chỉ nên có thể kèm "?" và "#".
      // Phần đường dẫn thì giữ, để host được dưới một thư mục con.
      final client = ApiClient(baseUrl: Uri.parse('http://may-chu:9080/trang?a=1#muc'));
      final ws = client.wsUri('/ws/scale');

      expect(ws.hasFragment, isFalse);
      expect(ws.hasQuery, isFalse);
      expect(ws.toString(), 'ws://may-chu:9080/trang/ws/scale');
    });

    test('https đổi sang wss', () {
      final client = ApiClient(baseUrl: Uri.parse('https://kho.example.com'));
      expect(client.wsUri('/ws/scale').scheme, 'wss');
    });

    test('giữ nguyên cổng và bỏ dấu gạch chéo thừa ở cuối', () {
      final client = ApiClient(baseUrl: Uri.parse('http://100.76.81.118:9081/'));
      expect(client.baseUrl.toString(), 'http://100.76.81.118:9081');
    });

    test('địa chỉ không khai cổng thì không tự chèn cổng mặc định', () {
      final client = ApiClient(baseUrl: Uri.parse('http://kho-01'));
      expect(client.wsUri('/ws/scale').toString(), 'ws://kho-01/ws/scale');
    });
  });
}
