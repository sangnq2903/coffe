import 'package:canxe_app/screens/trade_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kiểm thử luật tính thành tiền trong sổ mua bán.
///
/// Đây là chỗ ra con số tiền ghi vào sổ, nên sai một luật là ghi sai tiền mà
/// không ai phát hiện cho tới lúc đối chiếu cuối kỳ.
void main() {
  ({double? quantity, double? unitPrice, double? amount}) tinh({
    double? kl,
    double? gia,
    double? tien,
    required TradeField vuaGo,
  }) =>
      fillTradeMath(
        quantity: kl,
        unitPrice: gia,
        amount: tien,
        justEdited: vuaGo,
      );

  group('Thành tiền = đơn giá × khối lượng', () {
    test('có đủ hai ô thì tính ra tiền', () {
      final r = tinh(kl: 7630, gia: 95000, vuaGo: TradeField.donGia);
      expect(r.amount, 724850000);
      expect(r.quantity, 7630);
      expect(r.unitPrice, 95000);
    });

    test('sửa khối lượng thì tiền tính lại', () {
      final r = tinh(kl: 8000, gia: 95000, tien: 724850000, vuaGo: TradeField.khoiLuong);
      expect(r.amount, 760000000);
      expect(r.unitPrice, 95000, reason: 'đơn giá là số người ta nhập, không tự đổi');
    });

    test('sửa đơn giá thì tiền tính lại', () {
      final r = tinh(kl: 7630, gia: 90000, tien: 724850000, vuaGo: TradeField.donGia);
      expect(r.amount, 686700000);
      expect(r.quantity, 7630);
    });

    test('tiền luôn tròn đồng, không có phần lẻ', () {
      final r = tinh(kl: 1.5, gia: 95001, vuaGo: TradeField.khoiLuong);
      expect(r.amount, 142502, reason: '142.501,5 làm tròn thành 142.502');
      expect(r.amount! % 1, 0);
    });
  });

  group('Không tính ngược, không đoán', () {
    test('sửa thành tiền thì không đụng khối lượng lẫn đơn giá', () {
      // Bớt giá cho khách hay làm tròn lúc chốt: người ta cố ý ghi số khác
      // phép nhân, tự sửa hai ô kia là ghi đè lên số họ vừa nhập.
      final r = tinh(kl: 7630, gia: 95000, tien: 720000000, vuaGo: TradeField.thanhTien);
      expect(r.quantity, 7630);
      expect(r.unitPrice, 95000);
      expect(r.amount, 720000000);
    });

    test('có tiền và khối lượng cũng không suy ra đơn giá', () {
      // Chia ngược ra số lẻ tới hào, không ai ghi đơn giá cà phê như vậy.
      final r = tinh(kl: 7630, tien: 720000000, vuaGo: TradeField.thanhTien);
      expect(r.unitPrice, isNull);
    });

    test('có tiền và đơn giá cũng không suy ra khối lượng', () {
      final r = tinh(gia: 95000, tien: 720000000, vuaGo: TradeField.thanhTien);
      expect(r.quantity, isNull);
    });

    test('mới có một ô thì giữ nguyên', () {
      final r = tinh(kl: 7630, vuaGo: TradeField.khoiLuong);
      expect(r.unitPrice, isNull);
      expect(r.amount, isNull);
    });

    test('trống trơn thì giữ nguyên', () {
      final r = tinh(vuaGo: TradeField.khoiLuong);
      expect(r.quantity, isNull);
      expect(r.unitPrice, isNull);
      expect(r.amount, isNull);
    });

    test('số 0 và số âm coi như chưa nhập', () {
      expect(tinh(kl: 0, gia: 95000, vuaGo: TradeField.donGia).amount, isNull);
      expect(tinh(kl: -5, gia: 95000, vuaGo: TradeField.donGia).amount, isNull);
    });
  });

  test('khoản không có khối lượng vẫn ghi được thành tiền', () {
    // Tiền dầu, tiền công bốc vác: chỉ có số tiền, không nhân ra từ đâu.
    final r = tinh(tien: 12000000, vuaGo: TradeField.thanhTien);
    expect(r.amount, 12000000);
    expect(r.quantity, isNull);
    expect(r.unitPrice, isNull);
  });
}
