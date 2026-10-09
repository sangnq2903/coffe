import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

void main() {
  group('ServerInfo — máy chủ có hiểu loại phiếu không', () {
    Map<String, Object?> status([List<String>? directions]) => {
          'role': 'station',
          'station_code': 'KHO01',
          'station_name': 'Kho 1',
          'version': '0.1.0',
          if (directions != null) 'directions': directions,
        };

    test('máy chủ mới khai báo cân thuê thì hỗ trợ', () {
      final info = ServerInfo.fromJson(status(['nhap', 'xuat', 'can_thue']));
      expect(info.supportsDirection(WeighDirection.canThue), isTrue);
    });

    test('máy chủ cũ không khai báo thì không hỗ trợ cân thuê, nhưng vẫn nhập và xuất', () {
      // Bản cũ gặp "can_thue" sẽ lưu thầm thành "nhap" nên app phải tránh gửi.
      final info = ServerInfo.fromJson(status());
      expect(info.supportsDirection(WeighDirection.canThue), isFalse);
      expect(info.supportsDirection(WeighDirection.nhap), isTrue);
      expect(info.supportsDirection(WeighDirection.xuat), isTrue);
    });

    test('máy chủ khai thiếu cân thuê thì không hỗ trợ', () {
      final info = ServerInfo.fromJson(status(['nhap', 'xuat']));
      expect(info.supportsDirection(WeighDirection.canThue), isFalse);
    });
  });
}
