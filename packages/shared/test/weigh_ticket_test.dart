import 'package:canxe_shared/canxe_shared.dart';
import 'package:test/test.dart';

WeighTicket ticketWith({
  double? first,
  double? second,
  double yieldRatio = 100,
  WeighDirection direction = WeighDirection.nhap,
}) {
  final now = DateTime.now();
  return WeighTicket(
    id: 'id',
    ticketNo: 'KHO01-260903-0001',
    stationCode: 'KHO01',
    direction: direction,
    status: TicketStatus.hoanThanh,
    customerName: 'Khách A',
    plateNo: '51C-12345',
    goodsName: 'Cà tươi',
    yieldRatio: yieldRatio,
    firstWeight: first,
    secondWeight: second,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('WeighTicket — tính khối lượng', () {
    test('KL hàng là chênh lệch hai lần cân khi nhập kho', () {
      expect(ticketWith(first: 21640, second: 9000).netWeight, 12640);
    });

    test('KL hàng đúng cả khi xuất kho (lần 2 nặng hơn lần 1)', () {
      final ticket = ticketWith(
        first: 9000,
        second: 21640,
        direction: WeighDirection.xuat,
      );
      expect(ticket.netWeight, 12640);
    });

    test('thiếu một lần cân thì KL hàng bằng 0, không đoán bừa', () {
      expect(ticketWith(first: 21640).netWeight, 0);
      expect(ticketWith(second: 9000).netWeight, 0);
    });

    test('KL thành phẩm quy đổi theo tỷ lệ', () {
      expect(ticketWith(first: 21640, second: 9000, yieldRatio: 20).productWeight, 2528);
    });

    test('KL tổng và KL bì suy ra từ hai lần cân bất kể thứ tự', () {
      final ticket = ticketWith(first: 9000, second: 21640);
      expect(ticket.grossWeight, 21640);
      expect(ticket.tareWeight, 9000);
    });
  });

  group('WeighTicket — chuyển đổi JSON', () {
    test('giữ nguyên dữ liệu qua một vòng mã hoá/giải mã', () {
      final original = ticketWith(first: 21640, second: 9000, yieldRatio: 55);
      final restored = WeighTicket.fromJson(original.toJson());

      expect(restored.ticketNo, original.ticketNo);
      expect(restored.firstWeight, original.firstWeight);
      expect(restored.secondWeight, original.secondWeight);
      expect(restored.yieldRatio, original.yieldRatio);
      expect(restored.netWeight, original.netWeight);
      expect(restored.status, original.status);
      expect(restored.direction, original.direction);
    });

    test('giá trị lạ rơi về mặc định thay vì làm hỏng cả danh sách phiếu', () {
      final ticket = WeighTicket.fromJson({
        'id': 'x',
        'ticket_no': 'A',
        'station_code': 'KHO01',
        'direction': 'khong-ton-tai',
        'status': 'khong-ton-tai',
        'created_at': 0,
        'updated_at': 0,
      });
      expect(ticket.direction, WeighDirection.nhap);
      expect(ticket.status, TicketStatus.choLan2);
      expect(ticket.yieldRatio, 100);
    });
  });

  group('Vehicle — chuẩn hoá biển số', () {
    test('bỏ khoảng trắng, dấu chấm và viết hoa', () {
      expect(Vehicle.normalizePlate('51c-123.45'), '51C-12345');
      expect(Vehicle.normalizePlate(' 51C 123 45 '), '51C12345');
    });
  });

  group('GoodsType — danh mục mặc định', () {
    test('có đủ bốn loại hàng đang dùng và id cố định để không tạo trùng', () {
      final seed = GoodsType.seed();
      expect(seed.map((g) => g.code), containsAll(['TRAU', 'CANHAN', 'CATUOI', 'CAKHO']));
      expect(GoodsType.seed().map((g) => g.id), seed.map((g) => g.id));
    });
  });
}
