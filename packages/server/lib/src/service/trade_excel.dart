import 'package:canxe_shared/canxe_shared.dart';
import 'package:excel/excel.dart';

/// Dựng file Excel của sổ mua bán để gửi cho kế toán.
///
/// Xuất ra **.xlsx thật** chứ không phải CSV: kế toán mở lên là số ra số, tự
/// cộng và lọc được ngay. CSV thì Excel đọc dấu phân cách theo thiết lập vùng
/// của từng máy — máy này ra đúng cột, máy kia dồn hết vào một cột, và số tiền
/// dễ bị hiểu thành chữ.
abstract final class TradeExcel {
  /// Sổ giao dịch: mỗi dòng một lần mua bán, kèm dòng tổng ở cuối.
  static List<int> transactions({
    required List<Trade> trades,
    required TradeSummary summary,
    DateTime? from,
    DateTime? to,
  }) {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];

    _tieuDe(sheet, 'SỔ MUA BÁN', _khoang(from, to));

    _hang(sheet, [
      'Ngày',
      'Chiều',
      'Mặt hàng',
      'Đối tác',
      'Khối lượng',
      'ĐVT',
      'Đơn giá',
      'Thành tiền',
      'Hoá đơn',
      'Số hoá đơn',
      'Chi phí/kg',
      'Tổng chi phí',
      'Lãi',
      'Chi tiết chi phí',
      'Ghi chú',
      'Người ghi',
    ], dam: true);

    for (final t in trades) {
      _hang(sheet, [
        _ngay(t.date),
        t.kind.label,
        t.goodsName,
        t.partnerName,
        t.quantity == 0 ? null : t.quantity,
        t.quantity == 0 ? '' : t.unit,
        t.unitPrice == 0 ? null : t.unitPrice,
        t.amount,
        // Viết hẳn chữ chứ không để 0/1: kế toán lọc theo cột này.
        t.hasInvoice ? 'Có' : 'Không',
        t.invoiceNo ?? '',
        t.costItems.isEmpty ? null : t.costPerKg,
        t.costItems.isEmpty ? null : t.totalCost,
        t.profit,
        // Gộp thành một ô chữ: mỗi loại hàng một bộ khoản chi khác nhau, tách
        // ra thành cột riêng thì bảng có hàng chục cột hầu hết bỏ trống.
        t.costItems.map((c) => '${c.name} ${c.perKg.round()}').join('; '),
        t.note ?? '',
        t.createdBy ?? '',
      ]);
    }

    _hang(sheet, [
      'TỔNG',
      '',
      '',
      '',
      summary.quantityIn - summary.quantityOut,
      'kg',
      null,
      summary.amountIn + summary.amountOut,
      '',
      '',
      null,
      trades.fold<double>(0, (t, e) => t + (e.costItems.isEmpty ? 0 : e.totalCost)),
      trades.fold<double>(0, (t, e) => t + (e.profit ?? 0)),
      '',
      '',
      '',
    ], dam: true);

    _trong(sheet);
    _hang(sheet, ['Mua vào', summary.amountIn]);
    _hang(sheet, ['Bán ra', summary.amountOut]);
    _hang(sheet, ['Có hoá đơn', summary.amountInvoiced]);
    _hang(sheet, ['Không hoá đơn', summary.amountNotInvoiced]);

    _rong(sheet, [14, 10, 26, 26, 13, 6, 14, 16, 10, 14, 12, 16, 16, 34, 30, 12]);
    return book.save() ?? const [];
  }

  /// Tổng quan tồn kho: mỗi dòng một mặt hàng, cộng dồn cả sổ.
  static List<int> stock(TradeStock ton) {
    final book = Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];

    _tieuDe(
      sheet,
      'TỒN KHO THEO SỔ MUA BÁN',
      ton.firstDate == null
          ? 'Chưa có giao dịch'
          : 'Cộng dồn từ ${_ngay(ton.firstDate!)} đến ${_ngay(ton.lastDate!)}',
    );

    _hang(sheet, [
      'Mặt hàng',
      'Nhập',
      'Xuất',
      'Tồn',
      'Giá vốn TB',
      'Tiền mua',
      'Tiền bán',
    ], dam: true);

    for (final d in ton.lines) {
      _hang(sheet, [
        d.goodsName,
        d.quantityIn,
        d.quantityOut,
        d.quantityBalance,
        d.averageCost,
        d.amountIn,
        d.amountOut,
      ]);
    }

    final s = ton.summary;
    _hang(sheet, [
      'TỔNG',
      s.quantityIn,
      s.quantityOut,
      s.quantityBalance,
      null,
      s.amountIn,
      s.amountOut,
    ], dam: true);

    _rong(sheet, [30, 13, 13, 13, 14, 16, 16]);
    return book.save() ?? const [];
  }

  // ------------------------------------------------------------- tiện ích

  static void _tieuDe(Sheet sheet, String ten, String phu) {
    _hang(sheet, [ten], dam: true);
    _hang(sheet, [phu]);
    _hang(sheet, ['Xuất lúc ${_ngayGio(DateTime.now())}']);
    _trong(sheet);
  }

  /// Thêm một hàng. Số để nguyên kiểu số để Excel còn cộng được; `null` là ô
  /// trống chứ không phải số 0 — 0 và "không có" là hai chuyện khác nhau.
  static void _hang(Sheet sheet, List<Object?> o, {bool dam = false}) {
    final style = dam ? CellStyle(bold: true) : null;
    sheet.appendRow([
      for (final v in o)
        switch (v) {
          null => TextCellValue(''),
          final num n when n == n.roundToDouble() => IntCellValue(n.round()),
          final num n => DoubleCellValue(n.toDouble()),
          _ => TextCellValue(v.toString()),
        }
    ]);
    if (style == null) return;
    final dong = sheet.maxRows - 1;
    for (var i = 0; i < o.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: dong))
          .cellStyle = style;
    }
  }

  static void _trong(Sheet sheet) => sheet.appendRow([TextCellValue('')]);

  static void _rong(Sheet sheet, List<int> cot) {
    for (var i = 0; i < cot.length; i++) {
      sheet.setColumnWidth(i, cot[i].toDouble());
    }
  }

  static String _khoang(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'Toàn bộ sổ';
    return 'Từ ${from == null ? '...' : _ngay(from)} '
        'đến ${to == null ? '...' : _ngay(to)}';
  }

  static String _ngay(DateTime v) => '${_hai(v.day)}/${_hai(v.month)}/${v.year}';

  static String _ngayGio(DateTime v) =>
      '${_ngay(v)} ${_hai(v.hour)}:${_hai(v.minute)}';

  static String _hai(int v) => v.toString().padLeft(2, '0');
}
