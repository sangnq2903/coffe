import 'package:canxe_app/core/ticket_filter.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter_test/flutter_test.dart';

WeighTicket _phieu(String so, WeighDirection chieu) => WeighTicket.create(
      ticketNo: so,
      stationCode: 'KHO02',
      direction: chieu,
      plateNo: '51C-12345',
      firstWeight: 1000,
    );

void main() {
  final danhSach = [
    _phieu('A1', WeighDirection.nhap),
    _phieu('A2', WeighDirection.xuat),
    _phieu('A3', WeighDirection.canThue),
    _phieu('A4', WeighDirection.canThue),
  ];

  group('Lọc phiếu theo loại', () {
    test('không chọn loại thì giữ đủ phiếu', () {
      expect(locTheoLoai(danhSach, null), hasLength(4));
    });

    test('chọn từng loại thì chỉ còn phiếu loại đó', () {
      expect(locTheoLoai(danhSach, WeighDirection.nhap).map((t) => t.ticketNo), ['A1']);
      expect(locTheoLoai(danhSach, WeighDirection.xuat).map((t) => t.ticketNo), ['A2']);
      expect(locTheoLoai(danhSach, WeighDirection.canThue).map((t) => t.ticketNo),
          ['A3', 'A4']);
    });

    test('máy chủ cũ trả về đủ mọi loại thì app vẫn lọc đúng', () {
      // Máy chủ bỏ qua tham số direction nên danh sách nhận về lẫn đủ ba loại.
      final tuMayChuCu = List.of(danhSach);
      final hienThi = locTheoLoai(tuMayChuCu, WeighDirection.canThue);
      expect(hienThi.every((t) => t.direction == WeighDirection.canThue), isTrue);
      expect(hienThi, hasLength(2));
    });

    test('loại không có phiếu nào thì ra danh sách rỗng', () {
      final chiNhap = [_phieu('B1', WeighDirection.nhap)];
      expect(locTheoLoai(chiNhap, WeighDirection.xuat), isEmpty);
    });

    test('không làm đổi danh sách gốc', () {
      locTheoLoai(danhSach, WeighDirection.xuat);
      expect(danhSach, hasLength(4));
    });
  });

  group('Bộ lọc sau khi lưu phiếu', () {
    test('đang lọc một loại thì chuyển theo loại phiếu vừa lưu', () {
      expect(loaiLocSauKhiLuu(WeighDirection.xuat, WeighDirection.canThue),
          WeighDirection.canThue);
      expect(loaiLocSauKhiLuu(WeighDirection.nhap, WeighDirection.nhap),
          WeighDirection.nhap);
    });

    test('đang xem tất cả thì vẫn xem tất cả', () {
      expect(loaiLocSauKhiLuu(null, WeighDirection.canThue), isNull);
    });

    test('lọc theo loại cũ làm phiếu mới biến mất, lọc theo loại mới thì hiện', () {
      final moi = _phieu('C1', WeighDirection.canThue);
      final sauKhiLuu = [...danhSach, moi];
      expect(locTheoLoai(sauKhiLuu, WeighDirection.xuat).contains(moi), isFalse);
      final boLocMoi = loaiLocSauKhiLuu(WeighDirection.xuat, moi.direction);
      expect(locTheoLoai(sauKhiLuu, boLocMoi).contains(moi), isTrue);
    });
  });
}
