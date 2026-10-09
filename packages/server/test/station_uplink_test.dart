import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_server/src/sync/central_session.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

void main() {
  group('Kênh đẩy số cân lên máy chủ', () {
    test('máy chủ từ chối nâng cấp WebSocket thì trạm vẫn sống, chỉ nối lại sau', () async {
      // Máy chủ cũ chưa có đường /ws/station trả 404 cho yêu cầu nâng cấp. Lỗi này
      // từng rơi ra ngoài không ai bắt và làm sập cả tiến trình trạm đang cân.
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) {
        request.response
          ..statusCode = 404
          ..write('khong co')
          ..close();
      });

      final config = ServerConfig.fromJson({
        'role': 'station',
        'station': {'code': 'KHO02'},
        'central': {
          'url': 'http://127.0.0.1:${server.port}',
          'username': 'a',
          'password': 'b',
        },
      });
      final client = ApiClient(baseUrl: config.centralUri!)..authToken = 'phieu-gia';
      final uplink = StationUplink(
        config: config,
        readings: const Stream<ScaleReading>.empty(),
        session: CentralSession(config: config, client: client),
      )..start();

      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(uplink.connected, isFalse);

      await uplink.dispose();
      await server.close(force: true);
    });
  });
}
