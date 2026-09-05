import 'package:canxe_shared/canxe_shared.dart';

import '../db/repository.dart';
import '../db/trade_repository.dart';
import 'ticket_service.dart' show BusinessException;

/// Nghiệp vụ của **sổ mua bán**.
///
/// Sổ này ghi cả thứ không qua bàn cân (mua phân bón, tiền dầu), nên khối lượng
/// và đơn giá đều được phép để trống — chỉ **số tiền** là bắt buộc.
class TradeService {
  TradeService(this._trades, this._repo);

  final TradeRepository _trades;
  final Repository _repo;

  List<Trade> list({
    DateTime? from,
    DateTime? to,
    TradeKind? kind,
    bool? hasInvoice,
    String? goodsTypeId,
    String? partnerId,
    String? query,
    int? limit,
  }) =>
      _trades.trades(
        from: from,
        to: to,
        kind: kind,
        hasInvoice: hasInvoice,
        goodsTypeId: goodsTypeId,
        partnerId: partnerId,
        query: query,
        limit: limit,
      );

  /// Số tổng của đúng những giao dịch đang lọc.
  ///
  /// Tính trên cùng bộ lọc với danh sách chứ không tính riêng: nếu không, lọc
  /// "chưa có hoá đơn" mà ô tổng vẫn là số của cả kỳ thì đọc ra kết luận sai.
  TradeSummary summary({
    DateTime? from,
    DateTime? to,
    TradeKind? kind,
    bool? hasInvoice,
    String? goodsTypeId,
    String? partnerId,
    String? query,
  }) =>
      TradeSummary.of(list(
        from: from,
        to: to,
        kind: kind,
        hasInvoice: hasInvoice,
        goodsTypeId: goodsTypeId,
        partnerId: partnerId,
        query: query,
      ));

  /// Tồn kho từng mặt hàng, **cộng dồn cả sổ** chứ không cắt theo tháng.
  ///
  /// Hàng nhập tháng này bán sang tháng sau là chuyện thường, nên hỏi "còn bao
  /// nhiêu trong kho" mà chỉ nhìn một tháng thì ra số vô nghĩa.
  ///
  /// Gộp theo loại hàng trong danh mục; thứ gõ tay không có trong danh mục thì
  /// gộp theo tên đã bỏ dấu, để "Cà nhân" và "ca nhan" không thành hai dòng.
  TradeStock stock({DateTime? from, DateTime? to}) {
    final all = _trades.trades(from: from, to: to);

    final gop = <String, StockLine>{};
    for (final t in all) {
      final khoa = t.goodsTypeId ?? 'ten:${normalizeForSearch(t.goodsName)}';
      final cu = gop[khoa];
      final laNhap = t.kind == TradeKind.muaVao;

      gop[khoa] = StockLine(
        goodsTypeId: t.goodsTypeId,
        goodsName: cu?.goodsName.isNotEmpty ?? false
            ? cu!.goodsName
            : (t.goodsName.isEmpty ? '(không ghi tên hàng)' : t.goodsName),
        quantityIn: (cu?.quantityIn ?? 0) + (laNhap ? t.quantity : 0),
        quantityOut: (cu?.quantityOut ?? 0) + (laNhap ? 0 : t.quantity),
        amountIn: (cu?.amountIn ?? 0) + (laNhap ? t.amount : 0),
        amountOut: (cu?.amountOut ?? 0) + (laNhap ? 0 : t.amount),
        count: (cu?.count ?? 0) + 1,
      );
    }

    // Mặt hàng còn tồn nhiều đứng trước — đó là thứ chủ cần nhìn đầu tiên.
    final lines = gop.values.toList()
      ..sort((a, b) {
        final theoTon = b.quantityBalance.compareTo(a.quantityBalance);
        return theoTon != 0 ? theoTon : a.goodsName.compareTo(b.goodsName);
      });

    final ngay = all.map((e) => e.date).toList()..sort();
    return TradeStock(
      lines: lines,
      summary: TradeSummary.of(all),
      firstDate: ngay.isEmpty ? null : ngay.first,
      lastDate: ngay.isEmpty ? null : ngay.last,
    );
  }

  Trade save(Map<String, Object?> body, {String? createdBy}) {
    final id = asStringOrNull(body['id']);
    final existing = id == null ? null : _trades.tradeById(id);
    if (id != null && (existing == null || existing.deleted)) {
      throw BusinessException('Không tìm thấy giao dịch cần sửa.');
    }

    final date = asTimeOrNull(body['date']) ?? existing?.date;
    if (date == null) throw BusinessException('Chưa chọn ngày giao dịch.');

    final amount = asDoubleOrNull(body['amount']) ?? existing?.amount;
    if (amount == null) throw BusinessException('Chưa nhập số tiền.');
    if (amount < 0) throw BusinessException('Số tiền không được âm.');

    final quantity = asDoubleOrNull(body['quantity']) ?? existing?.quantity ?? 0;
    if (quantity < 0) throw BusinessException('Khối lượng không được âm.');
    final unitPrice = asDoubleOrNull(body['unit_price']) ?? existing?.unitPrice ?? 0;
    if (unitPrice < 0) throw BusinessException('Đơn giá không được âm.');

    // Mặt hàng và đối tác tra từ danh mục để tên luôn khớp; nhập tay cũng được
    // vì có thứ mua bán một lần không đáng lập danh mục.
    final goodsId = asStringOrNull(body['goods_type_id']);
    final goods = goodsId == null ? null : _repo.goodsTypeById(goodsId);
    if (goodsId != null && goods == null) {
      throw BusinessException('Không tìm thấy loại hàng đã chọn.');
    }

    final partnerId = asStringOrNull(body['partner_id']);
    final partner = partnerId == null ? null : _repo.customerById(partnerId);
    if (partnerId != null && partner == null) {
      throw BusinessException('Không tìm thấy khách hàng đã chọn.');
    }

    final hasInvoice = body.containsKey('has_invoice')
        ? asBool(body['has_invoice'])
        : existing?.hasInvoice ?? false;

    final goodsName =
        goods?.name ?? asString(body['goods_name'], fallback: existing?.goodsName ?? '').trim();
    final partnerName = partner?.name ??
        asString(body['partner_name'], fallback: existing?.partnerName ?? '').trim();

    final kind = body.containsKey('kind')
        ? TradeKind.parse(body['kind'])
        : existing?.kind ?? TradeKind.muaVao;

    final trade = existing == null
        ? Trade.create(
            date: date,
            kind: kind,
            goodsTypeId: goods?.id,
            goodsName: goodsName,
            partnerId: partner?.id,
            partnerName: partnerName,
            quantity: quantity,
            unit: asString(body['unit'], fallback: 'kg').trim(),
            unitPrice: unitPrice,
            amount: amount,
            hasInvoice: hasInvoice,
            invoiceNo: asStringOrNull(body['invoice_no']),
            note: asStringOrNull(body['note']),
            createdBy: createdBy,
          )
        : existing.copyWith(
            date: date,
            kind: kind,
            goodsTypeId: goods?.id,
            goodsName: goodsName,
            partnerId: partner?.id,
            partnerName: partnerName,
            quantity: quantity,
            unit: asString(body['unit'], fallback: existing.unit).trim(),
            unitPrice: unitPrice,
            amount: amount,
            hasInvoice: hasInvoice,
            invoiceNo: asStringOrNull(body['invoice_no']),
            note: asStringOrNull(body['note']),
          );

    return _trades.upsertTrade(trade);
  }

  void delete(String id) {
    final trade = _trades.tradeById(id);
    if (trade == null || trade.deleted) {
      throw BusinessException('Không tìm thấy giao dịch.');
    }
    _trades.softDelete(id);
  }
}
