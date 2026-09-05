import 'package:canxe_app/screens/trade_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kiểm thử luật điền ba ô khối lượng — đơn giá — thành tiền.
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

  group('Nhập hai ô thì ra ô thứ ba', () {
    test('khối lượng và đơn giá ra thành tiền', () {
      final r = tinh(kl: 7630, gia: 95000, vuaGo: TradeField.donGia);
      expect(r.amount, 724850000);
      expect(r.quantity, 7630);
      expect(r.unitPrice, 95000);
    });

    test('khối lượng và thành tiền ra đơn giá', () {
      final r = tinh(kl: 7630, tien: 724850000, vuaGo: TradeField.thanhTien);
      expect(r.unitPrice, 95000);
    });

    test('đơn giá và thành tiền ra khối lượng', () {
      final r = tinh(gia: 95000, tien: 724850000, vuaGo: TradeField.thanhTien);
      expect(r.quantity, 7630);
    });
  });

  group('Đã đủ cả ba ô', () {
    test('sửa khối lượng thì thành tiền tính lại, đơn giá giữ nguyên', () {
      final r = tinh(kl: 8000, gia: 95000, tien: 724850000, vuaGo: TradeField.khoiLuong);
      expect(r.amount, 760000000);
      expect(r.unitPrice, 95000);
      expect(r.quantity, 8000, reason: 'ô vừa gõ không bao giờ bị ghi đè');
    });

    test('sửa đơn giá thì thành tiền tính lại', () {
      final r = tinh(kl: 7630, gia: 90000, tien: 724850000, vuaGo: TradeField.donGia);
      expect(r.amount, 686700000);
      expect(r.quantity, 7630);
    });

    test('sửa thành tiền thì đơn giá tính lại, khối lượng giữ nguyên', () {
      // Bớt giá cho khách: cân được bao nhiêu là chuyện đã rồi, chỉ có giá
      // thực nhận thay đổi.
      final r = tinh(kl: 7630, gia: 95000, tien: 720000000, vuaGo: TradeField.thanhTien);
      expect(r.quantity, 7630, reason: 'khối lượng là số cân được, không suy từ tiền');
      expect(r.unitPrice, closeTo(720000000 / 7630, 1e-9));
      expect(r.amount, 720000000);
    });
  });

  group('Không đủ dữ kiện thì không tính bừa', () {
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

    test('xoá trắng ô đang gõ thì không tự điền lại vào chính nó', () {
      // Đang xoá để gõ số khác mà máy điền lại ngay thì không nhập nổi.
      final r = tinh(kl: 7630, gia: 95000, vuaGo: TradeField.thanhTien);
      expect(r.amount, isNull);
    });

    test('số 0 coi như chưa nhập, không chia cho 0', () {
      final r = tinh(kl: 0, tien: 724850000, vuaGo: TradeField.thanhTien);
      expect(r.unitPrice, isNull);
      expect(r.quantity, 0);
    });

    test('số âm cũng coi như chưa nhập', () {
      final r = tinh(kl: -5, gia: 95000, vuaGo: TradeField.donGia);
      expect(r.amount, isNull);
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
