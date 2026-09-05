import '../json_utils.dart';
import '../models/trade.dart';
import 'api_client.dart';

/// Một trang sổ mua bán: danh sách giao dịch kèm số tổng của **đúng bộ lọc đó**.
class TradePage {
  const TradePage({this.items = const [], this.summary = const TradeSummary()});

  factory TradePage.fromJson(Map<String, Object?> json) => TradePage(
        items: asMapList(json['items']).map(Trade.fromJson).toList(),
        summary: json['summary'] is Map
            ? TradeSummary.fromJson((json['summary']! as Map).cast<String, Object?>())
            : const TradeSummary(),
      );

  final List<Trade> items;

  /// Số tổng tính trên chính bộ lọc đang xem, máy chủ gửi kèm luôn để màn hình
  /// không phải gọi thêm một lượt và không sợ hai bên lệch nhau.
  final TradeSummary summary;
}

/// Các lời gọi API của sổ mua bán. Chỉ tài khoản chủ dùng được.
extension TradeApi on ApiClient {
  Future<TradePage> trades({
    DateTime? from,
    DateTime? to,
    TradeKind? kind,
    bool? hasInvoice,
    String? goodsTypeId,
    String? partnerId,
    String? query,
    int? limit,
  }) async =>
      TradePage.fromJson(await getMap('/api/giao-dich', {
        if (from != null) 'from': timeToMillis(from).toString(),
        if (to != null) 'to': timeToMillis(to).toString(),
        if (kind != null) 'kind': kind.value,
        if (hasInvoice != null) 'hoa_don': hasInvoice ? '1' : '0',
        if (goodsTypeId != null && goodsTypeId.isNotEmpty) 'goods_type_id': goodsTypeId,
        if (partnerId != null && partnerId.isNotEmpty) 'partner_id': partnerId,
        if (query != null && query.isNotEmpty) 'q': query,
        if (limit != null) 'limit': '$limit',
      }));

  /// Trang tổng quan: tồn kho từng mặt hàng, cộng dồn cả sổ.
  ///
  /// Bỏ trống [from]/[to] là tính từ giao dịch đầu tiên tới giờ.
  Future<TradeStock> tradeStock({DateTime? from, DateTime? to}) async =>
      TradeStock.fromJson(await getMap('/api/giao-dich/tong-quan', {
        if (from != null) 'from': timeToMillis(from).toString(),
        if (to != null) 'to': timeToMillis(to).toString(),
      }));

  Future<Trade> saveTrade({
    String? id,
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
    String? note,
  }) async =>
      Trade.fromJson(await postMap(
        id == null ? '/api/giao-dich' : '/api/giao-dich/$id',
        {
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
          'has_invoice': hasInvoice,
          'invoice_no': invoiceNo,
          'note': note,
        },
      ));

  Future<void> deleteTrade(String id) => deletePath('/api/giao-dich/$id');
}
