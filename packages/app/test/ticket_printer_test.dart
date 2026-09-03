import 'package:canxe_app/core/ticket_printer.dart';
import 'package:canxe_shared/canxe_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

WeighTicket sampleTicket({
  double? second = 9000,
  TicketStatus status = TicketStatus.hoanThanh,
  String? note,
}) {
  final now = DateTime(2026, 9, 3, 14, 30);
  return WeighTicket(
    id: 'id',
    ticketNo: 'KHO01-260903-0001',
    stationCode: 'KHO01',
    direction: WeighDirection.nhap,
    status: status,
    customerName: 'Nguyễn Văn Đức — Đắk Lắk',
    plateNo: '51C-12345',
    driverName: 'Trần Thị Hường',
    goodsName: 'Cà tươi',
    yieldRatio: 20,
    firstWeight: 21640,
    firstWeightAt: now,
    secondWeight: second,
    secondWeightAt: second == null ? null : now.add(const Duration(minutes: 25)),
    note: note,
    createdBy: 'Lê Quốc Vũ',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('vi_VN');
  });

  group('TicketPrinter', () {
    test('dựng được file PDF hợp lệ từ phiếu đã hoàn thành', () async {
      final bytes = await TicketPrinter.build(sampleTicket());

      expect(bytes.length, greaterThan(1000));
      // Bốn byte đầu của mọi file PDF là "%PDF".
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nhúng được font có dấu tiếng Việt', () async {
      final bytes = await TicketPrinter.build(sampleTicket());
      final content = String.fromCharCodes(bytes);

      // Font nhúng phải xuất hiện trong file; thiếu nó là phiếu in ra mất dấu.
      expect(content.contains('Roboto'), isTrue);
      expect(content.contains('FontFile2'), isTrue);
    });

    test('in được cả phiếu chưa cân lần 2 mà không lỗi bố cục', () async {
      final bytes = await TicketPrinter.build(
        sampleTicket(second: null, status: TicketStatus.choLan2),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('ghi chú dài không làm vỡ trang', () async {
      final bytes = await TicketPrinter.build(
        sampleTicket(note: 'Hàng ẩm, trừ bì 2%. ' * 12),
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('nhận tên đơn vị in trên đầu phiếu', () async {
      final bytes = await TicketPrinter.build(
        sampleTicket(),
        companyName: 'Công ty Cà phê Sang NQ',
      );
      expect(bytes.length, greaterThan(1000));
    });
  });
}
