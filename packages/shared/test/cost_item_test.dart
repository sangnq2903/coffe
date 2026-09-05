import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

/// Kiểm thử định mức chi phí và lãi của một lần bán.
///
/// Đây là chỗ trả lời câu "bán ký này lãi hay lỗ", nên sai một luật là quyết
/// định giá bán dựa trên con số sai.
void main() {
  /// Trấu: mua 1.500 + điện 2.500 + xe 1.700 + công 1.500 = 7.200 đ/kg.
  const dinhMucTrau = [
    CostItem(name: 'Mua trấu', perKg: 1500),
    CostItem(name: 'Tiền điện', perKg: 2500),
    CostItem(name: 'Tiền xe', perKg: 1700),
    CostItem(name: 'Công', perKg: 1500),
  ];

  Trade banTrau({
    double kl = 10000,
    double gia = 8000,
    List<CostItem> chiPhi = dinhMucTrau,
    TradeKind kind = TradeKind.banRa,
  }) =>
      Trade.create(
        date: DateTime(2026, 9, 5),
        kind: kind,
        goodsName: 'Trấu',
        quantity: kl,
        unitPrice: gia,
        amount: kl * gia,
        costItems: chiPhi,
      );

  group('Cộng định mức', () {
    test('tổng đúng bằng tổng các khoản', () {
      expect(CostItem.perKgTotal(dinhMucTrau), 7200);
    });

    test('danh sách rỗng thì bằng 0', () {
      expect(CostItem.perKgTotal(const []), 0);
    });
  });

  group('Lãi của một lần bán', () {
    test('ví dụ đã chốt: 10.000 kg bán 8.000, chi phí 7.200', () {
      final t = banTrau();
      expect(t.costPerKg, 7200);
      expect(t.totalCost, 72000000);
      expect(t.amount, 80000000);
      expect(t.profit, 8000000, reason: '800 đ/kg × 10.000 kg');
    });

    test('bán rẻ hơn chi phí thì lãi ra số âm', () {
      final t = banTrau(gia: 7000);
      expect(t.profit, 70000000 - 72000000);
      expect(t.profit! < 0, isTrue);
    });

    test('mua vào thì không có lãi để nói, trả null', () {
      // Số 0 dễ đọc nhầm thành hoà vốn, nên phải là "chưa có gì để so".
      expect(banTrau(kind: TradeKind.muaVao).profit, isNull);
    });

    test('chưa khai định mức thì cũng trả null chứ không coi là lãi trọn', () {
      final t = banTrau(chiPhi: const []);
      expect(t.totalCost, 0);
      expect(t.profit, isNull);
    });

    test('khối lượng 0 thì chi phí 0, lãi bằng đúng tiền thu', () {
      // Bán một khoản không cân ký (bán lô, bán xô).
      final t = banTrau(kl: 0);
      expect(t.totalCost, 0);
      expect(t.profit, 0);
    });
  });

  group('Cất và đọc lại', () {
    test('đi qua JSON vẫn nguyên định mức', () {
      final lai = Trade.fromJson(banTrau().toJson());
      expect(lai.costItems.length, 4);
      expect(lai.costPerKg, 7200);
      expect(lai.profit, 8000000);
    });

    test('chuỗi rỗng hay hỏng thì đọc ra danh sách rỗng, không nổ', () {
      for (final xau in [null, '', '   ', '[]', 'không phải json']) {
        expect(() => CostItem.listFromJson(xau), returnsNormally, reason: '$xau');
      }
      expect(CostItem.listFromJson(''), isEmpty);
      expect(CostItem.listFromJson('[]'), isEmpty);
    });

    test('bỏ qua khoản không có tên', () {
      // Người dùng bấm "Thêm khoản" rồi bỏ trống — đừng cất dòng rỗng vào sổ.
      final list = CostItem.listFromJson('[{"name":"","per_kg":100},'
          '{"name":"Điện","per_kg":2500}]');
      expect(list.length, 1);
      expect(list.single.name, 'Điện');
    });

    test('định mức của loại hàng cũng cộng ra đ/kg', () {
      final hang = GoodsType.create(
        code: 'TRAU',
        name: 'Trấu',
        costItems: dinhMucTrau,
      );
      expect(hang.costPerKg, 7200);
      expect(GoodsType.fromJson(hang.toJson()).costPerKg, 7200);
    });
  });
}
