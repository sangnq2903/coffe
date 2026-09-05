import 'package:canxe_app/screens/trade_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kiểm thử phép tính ba ô của sổ mua bán: khối lượng × đơn giá = thành tiền.
///
/// Đây là chỗ ra con số tiền ghi vào sổ, nên sai một luật là ghi sai tiền mà
/// không ai phát hiện cho tới lúc đối chiếu cuối kỳ.
void main() {
  double? tinh(TradeField can, {double? kl, double? gia, double? tien}) =>
      computeTradeField(
        target: can,
        quantity: kl,
        unitPrice: gia,
        amount: tien,
      );

  group('Nhập hai ô thì ra ô thứ ba', () {
    test('khối lượng và đơn giá ra thành tiền', () {
      expect(tinh(TradeField.thanhTien, kl: 7630, gia: 95000), 724850000);
    });

    test('thành tiền và đơn giá ra khối lượng', () {
      // Đúng bộ số từng cho ra 0,03 vì máy tính từ số gõ dở dang.
      expect(tinh(TradeField.khoiLuong, tien: 5243000, gia: 1500), 3495);
    });

    test('thành tiền và khối lượng ra đơn giá', () {
      expect(tinh(TradeField.donGia, tien: 5243000, kl: 3495), 1500);
    });
  });

  group('Luôn ra số tròn', () {
    test('không có phần lẻ dưới đồng hay dưới ký', () {
      for (final v in [
        tinh(TradeField.khoiLuong, tien: 5243000, gia: 1500),
        tinh(TradeField.donGia, tien: 720000000, kl: 7630),
        tinh(TradeField.thanhTien, kl: 1.5, gia: 95001),
      ]) {
        expect(v, isNotNull);
        expect(v! % 1, 0, reason: 'không ai ghi sổ số lẻ tới hào');
      }
    });

    test('5.243.000 chia 1.500 làm tròn thành 3.495', () {
      // 3.495,333… — làm tròn xuống.
      expect(tinh(TradeField.khoiLuong, tien: 5243000, gia: 1500), 3495);
    });

    test('720.000.000 chia 7.630 làm tròn thành 94.364', () {
      // 94.364,3512…
      expect(tinh(TradeField.donGia, tien: 720000000, kl: 7630), 94364);
    });
  });

  group('Thiếu dữ kiện thì không đoán', () {
    test('thiếu một trong hai ô nguồn thì trả null', () {
      expect(tinh(TradeField.thanhTien, kl: 7630), isNull);
      expect(tinh(TradeField.donGia, tien: 5243000), isNull);
      expect(tinh(TradeField.khoiLuong, gia: 1500), isNull);
    });

    test('trống trơn thì trả null', () {
      for (final can in TradeField.values) {
        expect(tinh(can), isNull);
      }
    });

    test('số 0 coi như chưa nhập, không chia cho 0', () {
      expect(tinh(TradeField.khoiLuong, tien: 5243000, gia: 0), isNull);
      expect(tinh(TradeField.donGia, tien: 5243000, kl: 0), isNull);
    });

    test('số âm cũng coi như chưa nhập', () {
      expect(tinh(TradeField.thanhTien, kl: -5, gia: 1500), isNull);
    });
  });

  group('Số viết vào ô nhập', () {
    test('không có dấu phân cách hàng nghìn', () {
      // Điền "5.243.000" rồi gõ thêm một chữ số là thành "5.243.0001", đọc ra
      // 5.243 chứ không phải hơn năm triệu.
      expect(soVaoO(5243000), '5243000');
      expect(soVaoO(3495), '3495');
      expect(soVaoO(724850000), '724850000');
    });

    test('số nguyên không kèm ",0" thừa', () {
      expect(soVaoO(1500), '1500');
      expect(soVaoO(0), '0');
    });

    test('giữ phần lẻ nếu dữ liệu cũ có', () {
      expect(soVaoO(7.5), '7.5');
    });
  });

  group('Quy đổi trấu thành phẩm', () {
    test('đúng ví dụ đã chốt: 10.000 kg, 80%, mua 1.500, bán 8.000', () {
      final r = tinhQuyDoiTrau(klMua: 10000, tyLe: 80, giaMua: 1500, giaBan: 8000);
      expect(r.klThanhPham, 8000);
      expect(r.tienMua, 15000000);
      expect(r.tienBan, 64000000);
      expect(r.lai, 49000000);
    });

    test('tỷ lệ 100% thì thành phẩm bằng đúng số mua', () {
      final r = tinhQuyDoiTrau(klMua: 10000, tyLe: 100, giaMua: 1500, giaBan: 8000);
      expect(r.klThanhPham, 10000);
      expect(r.lai, 65000000);
    });

    test('chưa mua trấu thì mọi số bằng 0, không lỗi chia', () {
      final r = tinhQuyDoiTrau(klMua: 0, tyLe: 80, giaMua: 1500, giaBan: 8000);
      expect(r.klThanhPham, 0);
      expect(r.lai, 0);
    });

    test('bán rẻ hơn mua thì lãi ra số âm chứ không giấu đi', () {
      // Tỷ lệ thành phẩm thấp mà giá bán không bù nổi thì lỗ — phải thấy được.
      final r = tinhQuyDoiTrau(klMua: 10000, tyLe: 10, giaMua: 1500, giaBan: 8000);
      expect(r.klThanhPham, 1000);
      expect(r.lai, 8000000 - 15000000);
      expect(r.lai < 0, isTrue);
    });
  });
}
