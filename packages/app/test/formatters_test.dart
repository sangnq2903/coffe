import 'package:canxe_app/core/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kiểm thử các hàm định dạng và chuẩn hoá chuỗi.
void main() {
  group('Bỏ dấu khi tìm tên', () {
    test('gõ không dấu vẫn tìm ra tên có dấu', () {
      // Đây là lý do tồn tại của hàm: người chấm công gõ nhanh, không bật bộ gõ.
      expect(normalizeForSearch('Nguyễn Văn Tình'), 'nguyen van tinh');
      expect(normalizeForSearch('Trần Thị Hường'), 'tran thi huong');
      expect(normalizeForSearch('Đỗ Đình Đạt'), 'do dinh dat');
    });

    test('phủ hết các nguyên âm có dấu tiếng Việt', () {
      expect(normalizeForSearch('àáạảãâầấậẩẫăằắặẳẵ'), 'a' * 17);
      expect(normalizeForSearch('èéẹẻẽêềếệểễ'), 'e' * 11);
      expect(normalizeForSearch('ìíịỉĩ'), 'i' * 5);
      expect(normalizeForSearch('òóọỏõôồốộổỗơờớợởỡ'), 'o' * 17);
      expect(normalizeForSearch('ùúụủũưừứựửữ'), 'u' * 11);
      expect(normalizeForSearch('ỳýỵỷỹ'), 'y' * 5);
    });

    test('gộp khoảng trắng và bỏ khoảng trắng hai đầu', () {
      expect(normalizeForSearch('  A   Tình  '), 'a tinh');
    });

    test('chuỗi rỗng và null cho ra chuỗi rỗng', () {
      expect(normalizeForSearch(null), '');
      expect(normalizeForSearch('   '), '');
    });

    test('tên có dấu tìm được bằng cả hai cách gõ', () {
      const ten = 'Lê Thị Hoà';
      for (final go in ['hoa', 'Hoà', 'le thi hoa', 'LÊ']) {
        expect(
          normalizeForSearch(ten).contains(normalizeForSearch(go)),
          isTrue,
          reason: 'gõ "$go" phải tìm ra "$ten"',
        );
      }
    });
  });

  group('Định dạng tiền', () {
    test('làm tròn tới đồng và chấm phân cách hàng nghìn', () {
      // Lương chia theo ngày ra số lẻ; hiện phần thập phân chỉ làm người ta
      // nghi số sai.
      expect(formatMoney(8000000 / 30), '266.667');
      expect(formatMoney(0), '0');
      expect(formatMoney(null), '—');
    });
  });
}
