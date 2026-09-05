import '../ids.dart';
import '../json_utils.dart';
import 'cost_item.dart';

/// Chiều của một giao dịch mua bán.
enum TradeKind {
  /// Mua vào — hàng và tiền đi vào kho.
  muaVao('mua_vao', 'Mua vào', 'Nhập'),

  /// Bán ra — hàng rời kho, tiền thu về.
  banRa('ban_ra', 'Bán ra', 'Xuất');

  const TradeKind(this.value, this.label, this.shortLabel);

  final String value;
  final String label;

  /// Nhãn ngắn dùng trong bảng và các ô tổng: "Nhập" / "Xuất".
  final String shortLabel;

  static TradeKind parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => TradeKind.muaVao,
      );
}

/// Một dòng trong **sổ mua bán**.
///
/// Sổ này tách hẳn khỏi phiếu cân: ghi được cả thứ không qua bàn cân (mua phân
/// bón, tiền dầu, bán lẻ), và mỗi dòng tự khai khối lượng chứ không lấy từ
/// phiếu.
///
/// Đây là **dữ liệu riêng của chủ**: giá mua vào là thứ nhạy cảm nhất trong cả
/// hệ thống, nên nó chỉ nằm trên máy chủ trung tâm và không đi kèm gói đồng bộ
/// xuống các kho.
class Trade {
  const Trade({
    required this.id,
    required this.date,
    required this.kind,
    this.goodsTypeId,
    this.goodsName = '',
    this.partnerId,
    this.partnerName = '',
    this.quantity = 0,
    this.unit = 'kg',
    this.unitPrice = 0,
    required this.amount,
    this.hasInvoice = false,
    this.invoiceNo,
    this.costItems = const [],
    this.note,
    this.createdBy,
    required this.updatedAt,
    this.deleted = false,
  });

  factory Trade.create({
    required DateTime date,
    required TradeKind kind,
    String? goodsTypeId,
    String goodsName = '',
    String? partnerId,
    String partnerName = '',
    double quantity = 0,
    String unit = 'kg',
    double unitPrice = 0,
    required double amount,
    bool hasInvoice = false,
    String? invoiceNo,
    List<CostItem> costItems = const [],
    String? note,
    String? createdBy,
  }) =>
      Trade(
        id: newUuid(),
        date: dateOnly(date),
        kind: kind,
        goodsTypeId: goodsTypeId,
        goodsName: goodsName,
        partnerId: partnerId,
        partnerName: partnerName,
        quantity: quantity,
        unit: unit,
        unitPrice: unitPrice,
        amount: amount,
        hasInvoice: hasInvoice,
        invoiceNo: invoiceNo,
        costItems: costItems,
        note: note,
        createdBy: createdBy,
        updatedAt: DateTime.now(),
      );

  factory Trade.fromJson(Map<String, Object?> json) => Trade(
        id: asString(json['id']),
        date: asTime(json['date']),
        kind: TradeKind.parse(json['kind']),
        goodsTypeId: asStringOrNull(json['goods_type_id']),
        goodsName: asString(json['goods_name']),
        partnerId: asStringOrNull(json['partner_id']),
        partnerName: asString(json['partner_name']),
        quantity: asDouble(json['quantity']),
        unit: asString(json['unit'], fallback: 'kg'),
        unitPrice: asDouble(json['unit_price']),
        amount: asDouble(json['amount']),
        hasInvoice: asBool(json['has_invoice']),
        invoiceNo: asStringOrNull(json['invoice_no']),
        costItems: CostItem.listFromJson(json['cost_items']),
        note: asStringOrNull(json['note']),
        createdBy: asStringOrNull(json['created_by']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Bỏ phần giờ phút: sổ mua bán tính theo ngày, giữ giờ lại chỉ làm lệch khi
  /// lọc theo khoảng thời gian.
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  final String id;
  final DateTime date;
  final TradeKind kind;

  final String? goodsTypeId;
  final String goodsName;

  /// Bên mua hoặc bên bán. Dùng lại danh mục khách hàng cho khỏi nhập hai lần.
  final String? partnerId;
  final String partnerName;

  final double quantity;
  final String unit;
  final double unitPrice;

  /// Số tiền của giao dịch — **đây mới là con số tính vào tổng**.
  ///
  /// [quantity] và [unitPrice] chỉ là cách người ta tính ra nó. Màn hình tự
  /// nhân hai số đó điền vào đây, nhưng sửa lại được: bớt giá cho khách hay
  /// mua một khoản không có khối lượng (tiền dầu) thì không nhân ra được.
  final double amount;

  /// Giao dịch này **có xuất hoá đơn** hay không.
  ///
  /// Không phải để in ra, mà để tra được hàng nào đã ra hoá đơn, hàng nào chưa.
  final bool hasInvoice;

  /// Số hoá đơn, nếu có ghi lại.
  final String? invoiceNo;

  /// Bảng chi phí **chép lại lúc ghi giao dịch**.
  ///
  /// Chép chứ không tra lại định mức của loại hàng: sửa định mức hôm nay không
  /// được làm đổi lãi của lần bán tháng trước. Giống cách ngày chấm công giữ
  /// mức lương lúc chấm.
  final List<CostItem> costItems;

  /// Chi phí định mức cho một ký, đ/kg.
  double get costPerKg => CostItem.perKgTotal(costItems);

  /// Tổng chi phí của cả chuyến: đ/kg nhân khối lượng.
  double get totalCost => costPerKg * quantity;

  /// Lãi của một lần **bán ra**: tiền thu về trừ chi phí.
  ///
  /// `null` khi là lần mua vào hoặc chưa khai chi phí — không có gì để so thì
  /// đừng bịa ra số 0, dễ đọc nhầm thành hoà vốn.
  double? get profit =>
      kind == TradeKind.banRa && costItems.isNotEmpty ? amount - totalCost : null;

  final String? note;
  final String? createdBy;
  final DateTime updatedAt;
  final bool deleted;

  /// Khoá gộp theo tháng, dạng `2026-09`.
  String get monthKey => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// Số tiền nhân ra từ khối lượng và đơn giá, `null` nếu thiếu một trong hai.
  ///
  /// Màn hình dùng để tự điền và để báo khi số tiền đã ghi lệch với phép nhân.
  double? get computedAmount =>
      quantity > 0 && unitPrice > 0 ? quantity * unitPrice : null;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': timeToMillis(date),
        'kind': kind.value,
        'goods_type_id': goodsTypeId,
        'goods_name': goodsName,
        'partner_id': partnerId,
        'partner_name': partnerName,
        'quantity': quantity,
        'unit': unit,
        'unit_price': unitPrice,
        'amount': amount,
        'has_invoice': hasInvoice ? 1 : 0,
        'invoice_no': invoiceNo,
        'cost_items': CostItem.listToJson(costItems),
        'note': note,
        'created_by': createdBy,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  Trade copyWith({
    DateTime? date,
    TradeKind? kind,
    String? goodsTypeId,
    String? goodsName,
    String? partnerId,
    String? partnerName,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? amount,
    bool? hasInvoice,
    String? invoiceNo,
    List<CostItem>? costItems,
    String? note,
    bool? deleted,
  }) =>
      Trade(
        id: id,
        date: date == null ? this.date : dateOnly(date),
        kind: kind ?? this.kind,
        goodsTypeId: goodsTypeId ?? this.goodsTypeId,
        goodsName: goodsName ?? this.goodsName,
        partnerId: partnerId ?? this.partnerId,
        partnerName: partnerName ?? this.partnerName,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        unitPrice: unitPrice ?? this.unitPrice,
        amount: amount ?? this.amount,
        hasInvoice: hasInvoice ?? this.hasInvoice,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        costItems: costItems ?? this.costItems,
        note: note ?? this.note,
        createdBy: createdBy,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}

/// Tồn kho của **một mặt hàng**, cộng dồn từ đầu chứ không cắt theo tháng.
///
/// Hàng nhập tháng này bán sang tháng sau là chuyện thường, nên hỏi "còn bao
/// nhiêu trong kho" mà chỉ nhìn một tháng thì ra số vô nghĩa.
class StockLine {
  const StockLine({
    this.goodsTypeId,
    required this.goodsName,
    this.quantityIn = 0,
    this.quantityOut = 0,
    this.amountIn = 0,
    this.amountOut = 0,
    this.count = 0,
  });

  factory StockLine.fromJson(Map<String, Object?> json) => StockLine(
        goodsTypeId: asStringOrNull(json['goods_type_id']),
        goodsName: asString(json['goods_name']),
        quantityIn: asDouble(json['quantity_in']),
        quantityOut: asDouble(json['quantity_out']),
        amountIn: asDouble(json['amount_in']),
        amountOut: asDouble(json['amount_out']),
        count: asInt(json['count']),
      );

  final String? goodsTypeId;
  final String goodsName;
  final double quantityIn;
  final double quantityOut;
  final double amountIn;
  final double amountOut;

  /// Số lần mua bán mặt hàng này.
  final int count;

  /// Còn lại trong kho theo sổ: nhập trừ xuất.
  double get quantityBalance => quantityIn - quantityOut;

  /// Bán ra trừ mua vào. Âm nghĩa là đang bỏ tiền ôm hàng.
  double get amountBalance => amountOut - amountIn;

  /// Giá vốn bình quân một ký của phần đã nhập.
  double? get averageCost => quantityIn > 0 ? amountIn / quantityIn : null;

  Map<String, Object?> toJson() => {
        'goods_type_id': goodsTypeId,
        'goods_name': goodsName,
        'quantity_in': quantityIn,
        'quantity_out': quantityOut,
        'amount_in': amountIn,
        'amount_out': amountOut,
        'count': count,
      };
}

/// Trang tổng quan: tồn kho từng mặt hàng kèm số tổng của cả sổ.
class TradeStock {
  const TradeStock({
    this.lines = const [],
    this.summary = const TradeSummary(),
    this.firstDate,
    this.lastDate,
  });

  factory TradeStock.fromJson(Map<String, Object?> json) => TradeStock(
        lines: asMapList(json['lines']).map(StockLine.fromJson).toList(),
        summary: json['summary'] is Map
            ? TradeSummary.fromJson((json['summary']! as Map).cast<String, Object?>())
            : const TradeSummary(),
        firstDate: asTimeOrNull(json['first_date']),
        lastDate: asTimeOrNull(json['last_date']),
      );

  final List<StockLine> lines;
  final TradeSummary summary;

  /// Khoảng thời gian sổ đang có dữ liệu, để ghi rõ "tính từ lúc nào tới giờ".
  final DateTime? firstDate;
  final DateTime? lastDate;
}

/// Số tổng của một khoảng thời gian trong sổ mua bán.
///
/// Tách khối lượng ra khỏi tiền, và tách tiếp phần **có hoá đơn** với phần
/// **không hoá đơn** — đó là hai câu hỏi khác nhau mà chủ cần trả lời riêng.
class TradeSummary {
  const TradeSummary({
    this.quantityIn = 0,
    this.quantityOut = 0,
    this.amountIn = 0,
    this.amountOut = 0,
    this.amountInvoiced = 0,
    this.amountNotInvoiced = 0,
    this.countInvoiced = 0,
    this.countNotInvoiced = 0,
  });

  factory TradeSummary.of(Iterable<Trade> trades) {
    var qIn = 0.0, qOut = 0.0, aIn = 0.0, aOut = 0.0, aHd = 0.0, aKhong = 0.0;
    var nHd = 0, nKhong = 0;

    for (final t in trades) {
      if (t.deleted) continue;
      if (t.kind == TradeKind.muaVao) {
        qIn += t.quantity;
        aIn += t.amount;
      } else {
        qOut += t.quantity;
        aOut += t.amount;
      }
      if (t.hasInvoice) {
        aHd += t.amount;
        nHd++;
      } else {
        aKhong += t.amount;
        nKhong++;
      }
    }

    return TradeSummary(
      quantityIn: qIn,
      quantityOut: qOut,
      amountIn: aIn,
      amountOut: aOut,
      amountInvoiced: aHd,
      amountNotInvoiced: aKhong,
      countInvoiced: nHd,
      countNotInvoiced: nKhong,
    );
  }

  factory TradeSummary.fromJson(Map<String, Object?> json) => TradeSummary(
        quantityIn: asDouble(json['quantity_in']),
        quantityOut: asDouble(json['quantity_out']),
        amountIn: asDouble(json['amount_in']),
        amountOut: asDouble(json['amount_out']),
        amountInvoiced: asDouble(json['amount_invoiced']),
        amountNotInvoiced: asDouble(json['amount_not_invoiced']),
        countInvoiced: asInt(json['count_invoiced']),
        countNotInvoiced: asInt(json['count_not_invoiced']),
      );

  final double quantityIn;
  final double quantityOut;
  final double amountIn;
  final double amountOut;
  final double amountInvoiced;
  final double amountNotInvoiced;
  final int countInvoiced;
  final int countNotInvoiced;

  /// Khối lượng còn lại trong kho theo sổ này: nhập trừ xuất.
  double get quantityBalance => quantityIn - quantityOut;

  /// Tiền bán ra trừ tiền mua vào. Âm nghĩa là kỳ này đang bỏ tiền ra mua.
  double get amountBalance => amountOut - amountIn;

  Map<String, Object?> toJson() => {
        'quantity_in': quantityIn,
        'quantity_out': quantityOut,
        'amount_in': amountIn,
        'amount_out': amountOut,
        'amount_invoiced': amountInvoiced,
        'amount_not_invoiced': amountNotInvoiced,
        'count_invoiced': countInvoiced,
        'count_not_invoiced': countNotInvoiced,
      };
}
