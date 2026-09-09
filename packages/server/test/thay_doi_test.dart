import 'dart:async';
import 'dart:io';

import 'package:canxe_server/canxe_server.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

/// Kiểm thử kênh báo "dữ liệu vừa đổi".
///
/// Hai chỗ dễ hỏng nhất: gom tín hiệu (không gom thì một lượt đồng bộ làm cả
/// kho tải lại hàng trăm lần) và lọc bảng nội bộ (không lọc thì cứ 15 giây một
/// lần mọi máy tải lại dù chẳng có gì mới để xem).
void main() {
  group('Gom tín hiệu', () {
    late ChangeBroker broker;

    setUp(() => broker = ChangeBroker(gom: const Duration(milliseconds: 40)));
    tearDown(() => broker.dispose());

    test('nhiều lần ghi cùng một bảng chỉ ra một tín hiệu', () async {
      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      for (var i = 0; i < 500; i++) {
        broker.ghiNhan('tickets');
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu.length, 1, reason: '500 dòng ghi mà bắt tải lại 500 lần thì kho đứng');
      expect(thu.first, {'tickets'});
    });

    test('nhiều bảng khác nhau gộp vào cùng một tín hiệu', () async {
      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      broker.ghiNhan('tickets');
      broker.ghiNhan('customers');
      broker.ghiNhan('vehicles');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu.length, 1);
      expect(thu.first, {'tickets', 'customers', 'vehicles'});
    });

    test('hai trận ghi cách xa nhau thì ra hai tín hiệu', () async {
      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      broker.ghiNhan('tickets');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      broker.ghiNhan('giao_dich');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu.map((e) => e.single), ['tickets', 'giao_dich']);
    });

    test('bảng nội bộ không làm ai phải tải lại', () async {
      // Ba bảng này đổi liên tục theo nhịp đồng bộ mà không màn hình nào hiện.
      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      broker.ghiNhan('sync_state');
      broker.ghiNhan('ticket_counters');
      broker.ghiNhan('cai_dat');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu, isEmpty);
    });

    test('bảng nội bộ lẫn với bảng thật thì chỉ báo bảng thật', () async {
      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      broker.ghiNhan('sync_state');
      broker.ghiNhan('tickets');
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu.single, {'tickets'});
    });

    test('đóng rồi thì không phát nữa', () async {
      await broker.dispose();
      broker.ghiNhan('tickets');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Không ném lỗi là đạt: máy chủ đang tắt mà còn ghi vài dòng cuối là
      // chuyện thường.
    });
  });

  group('Móc báo của SQLite', () {
    late Directory tempDir;
    late AppDatabase db;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('canxe-thay-doi'));
    tearDown(() {
      db.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('ghi bảng nào thì báo đúng tên bảng đó', () async {
      db = AppDatabase.open('${tempDir.path}/thu.db');
      final repo = Repository(db);
      final broker = ChangeBroker(gom: const Duration(milliseconds: 40));
      final sub = db.db.updatesSync.listen((u) => broker.ghiNhan(u.tableName));

      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      repo.upsertCustomer(Customer.create(name: 'Nguyễn Văn Bảy'));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(thu.single, contains('customers'));

      await sub.cancel();
      await broker.dispose();
    });

    test('một giao dịch nhiều bảng vẫn chỉ một tín hiệu', () async {
      // Đây là hình dạng của một lượt đồng bộ thật: nhiều bảng, một transaction.
      db = AppDatabase.open('${tempDir.path}/thu2.db');
      final repo = Repository(db);
      final broker = ChangeBroker(gom: const Duration(milliseconds: 40));
      final sub = db.db.updatesSync.listen((u) => broker.ghiNhan(u.tableName));

      final thu = <Set<String>>[];
      broker.thayDoi.listen(thu.add);

      final kh = Customer.create(name: 'Lê Thị Chín');
      repo.applyPayload(SyncPayload(customers: [kh], vehicles: [
        Vehicle.create(plateNo: '47C-1234'),
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(thu.length, 1, reason: 'cả transaction gộp thành một tín hiệu');
      expect(thu.single, containsAll(<String>['customers', 'vehicles']));

      await sub.cancel();
      await broker.dispose();
    });
  });
}
