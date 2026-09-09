import 'dart:async';
import 'dart:convert';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Kênh giả để đẩy khung vào và cắt kết nối theo ý muốn.
class _KenhGia implements WebSocketChannel {
  _KenhGia() : _tu = StreamController<dynamic>();

  final StreamController<dynamic> _tu;
  final _guiDi = <dynamic>[];
  bool daDong = false;

  void nhan(Object khung) => _tu.add(jsonEncode(khung));

  void ngat() {
    if (!_tu.isClosed) _tu.close();
  }

  @override
  Stream<dynamic> get stream => _tu.stream;

  @override
  WebSocketSink get sink => _SinkGia(this);

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SinkGia implements WebSocketSink {
  _SinkGia(this.kenh);

  final _KenhGia kenh;

  @override
  void add(dynamic data) => kenh._guiDi.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    kenh.daDong = true;
    kenh.ngat();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final diaChi = Uri.parse('ws://vi-du.test/ws/thay-doi');

  test('đọc được tên bảng máy chủ gửi về', () async {
    final kenh = _KenhGia();
    final client = LiveChangeClient(wsUrl: diaChi, connector: (_) => kenh)..start();

    final thu = <ThayDoiDuLieu>[];
    client.thayDoi.listen(thu.add);

    kenh.nhan({'bang': ['tickets', 'customers'], 'luc': 1});
    await Future<void>.delayed(Duration.zero);

    expect(thu.single.bang, {'tickets', 'customers'});
    expect(thu.single.noiLai, isFalse);
    await client.dispose();
  });

  test('lọc đúng bảng mình quan tâm', () async {
    const tin = ThayDoiDuLieu({'tickets'});
    expect(tin.coBang(['tickets']), isTrue);
    expect(tin.coBang(['cham_cong']), isFalse);
    expect(tin.coBang(['cham_cong', 'tickets']), isTrue);
  });

  test('tín hiệu nối lại thì màn hình nào cũng phải tải lại', () {
    // Lúc mất kết nối máy chủ vẫn ghi tiếp mà không ai nghe, nên nối lại là
    // phải coi như mọi thứ đều có thể đã đổi.
    const tin = ThayDoiDuLieu({}, noiLai: true);
    expect(tin.coBang(['tickets']), isTrue);
    expect(tin.coBang(['cham_cong']), isTrue);
    expect(tin.coBang([]), isTrue);
  });

  test('khung lạ không làm rớt kết nối', () async {
    final kenh = _KenhGia();
    final client = LiveChangeClient(wsUrl: diaChi, connector: (_) => kenh)..start();

    final thu = <ThayDoiDuLieu>[];
    client.thayDoi.listen(thu.add);

    kenh._tu.add('day khong phai json');
    kenh._tu.add(jsonEncode({'khong_co_truong_bang': 1}));
    kenh.nhan({'bang': ['tickets']});
    await Future<void>.delayed(Duration.zero);

    expect(thu.single.bang, {'tickets'}, reason: 'vẫn nhận được khung hợp lệ sau đó');
    expect(client.dangNoi, isTrue);
    await client.dispose();
  });

  test('rớt thì tự nối lại, và nối lại xong thì báo tải lại toàn bộ', () async {
    final daMo = <_KenhGia>[];
    final client = LiveChangeClient(
      wsUrl: diaChi,
      reconnectDelay: const Duration(milliseconds: 20),
      connector: (_) {
        final k = _KenhGia();
        daMo.add(k);
        return k;
      },
    )..start();

    final thu = <ThayDoiDuLieu>[];
    client.thayDoi.listen(thu.add);

    expect(daMo.length, 1);
    expect(thu, isEmpty, reason: 'lần nối đầu tiên không bắt tải lại — vừa tải xong rồi');

    daMo.first.ngat();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(daMo.length, greaterThan(1), reason: 'phải tự mở lại');
    expect(thu.where((e) => e.noiLai).length, greaterThanOrEqualTo(1),
        reason: 'nối lại phải báo tải lại toàn bộ, nếu không màn hình đứng ở dữ liệu cũ');

    await client.dispose();
  });

  test('đóng rồi thì thôi không nối lại nữa', () async {
    final daMo = <_KenhGia>[];
    final client = LiveChangeClient(
      wsUrl: diaChi,
      reconnectDelay: const Duration(milliseconds: 20),
      connector: (_) {
        final k = _KenhGia();
        daMo.add(k);
        return k;
      },
    )..start();

    await client.dispose();
    final soLan = daMo.length;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(daMo.length, soLan, reason: 'đóng app rồi mà còn gõ cửa máy chủ thì phiền');
    expect(client.dangNoi, isFalse);
  });
}
