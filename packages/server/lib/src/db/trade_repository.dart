import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Truy cập **sổ mua bán**.
///
/// Tách khỏi [Repository] cho mỗi file một việc, nhưng vẫn **đi kèm luồng đồng
/// bộ**: mở app ở máy nào cũng phải thấy chung một quyển sổ, chứ ghi ở kho rồi
/// mở trung tâm không thấy thì thành mỗi máy một quyển.
///
/// Quyền xem chặn ở API (chỉ tài khoản chủ), không phải ở chỗ dữ liệu nằm đâu.
class TradeRepository {
  TradeRepository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  /// Danh sách giao dịch, mới nhất trước.
  ///
  /// [hasInvoice] để `null` nghĩa là không lọc theo hoá đơn; `true`/`false` thì
  /// chỉ lấy phần có hoặc phần không — đó là câu hỏi hay dùng nhất của sổ này.
  List<Trade> trades({
    DateTime? from,
    DateTime? to,
    TradeKind? kind,
    bool? hasInvoice,
    String? goodsTypeId,
    String? partnerId,
    String? query,
    int? limit,
  }) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(timeToMillis(Trade.dateOnly(from)));
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(timeToMillis(Trade.dateOnly(to)));
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.value);
    }
    if (hasInvoice != null) {
      where.add('has_invoice = ?');
      args.add(hasInvoice ? 1 : 0);
    }
    if (goodsTypeId != null && goodsTypeId.isNotEmpty) {
      where.add('goods_type_id = ?');
      args.add(goodsTypeId);
    }
    if (partnerId != null && partnerId.isNotEmpty) {
      where.add('partner_id = ?');
      args.add(partnerId);
    }
    final tim = normalizeForSearch(query);
    if (tim.isNotEmpty) {
      // Bỏ dấu cả hai vế: gõ "ca nhan" phải ra "Cà nhân", gõ "bay" ra
      // "Nguyễn Văn Bảy".
      // Mỗi cột một dấu `?` riêng chứ không dùng `?1` dùng lại: `?1` chỉ đúng khi
      // không có tham số nào khác đứng trước, mà ở đây còn bộ lọc khác nữa —
      // trộn hai kiểu thì SQLite đếm sai số tham số và câu truy vấn vỡ.
      where.add('(khong_dau(goods_name) LIKE ? OR khong_dau(partner_name) LIKE ? '
          'OR khong_dau(ifnull(invoice_no, \'\')) LIKE ? '
          'OR khong_dau(ifnull(note, \'\')) LIKE ?)');
      args.addAll(List.filled(4, '%$tim%'));
    }

    final sql = 'SELECT * FROM giao_dich WHERE ${where.join(" AND ")} '
        'ORDER BY date DESC, updated_at DESC${limit == null ? '' : ' LIMIT $limit'}';
    return _db.select(sql, args).map((r) => Trade.fromJson(r)).toList();
  }

  Trade? tradeById(String id) {
    final rows = _db.select('SELECT * FROM giao_dich WHERE id = ? LIMIT 1', [id]);
    return rows.isEmpty ? null : Trade.fromJson(rows.first);
  }

  Trade upsertTrade(Trade trade, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO giao_dich (id, date, kind, goods_type_id, goods_name, partner_id,
        partner_name, quantity, unit, unit_price, amount, has_invoice, invoice_no,
        note, created_by, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        date = excluded.date, kind = excluded.kind,
        goods_type_id = excluded.goods_type_id, goods_name = excluded.goods_name,
        partner_id = excluded.partner_id, partner_name = excluded.partner_name,
        quantity = excluded.quantity, unit = excluded.unit,
        unit_price = excluded.unit_price, amount = excluded.amount,
        has_invoice = excluded.has_invoice, invoice_no = excluded.invoice_no,
        note = excluded.note, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= giao_dich.updated_at
    ''', [
      trade.id,
      timeToMillis(trade.date),
      trade.kind.value,
      trade.goodsTypeId,
      trade.goodsName,
      trade.partnerId,
      trade.partnerName,
      trade.quantity,
      trade.unit,
      trade.unitPrice,
      trade.amount,
      trade.hasInvoice ? 1 : 0,
      trade.invoiceNo,
      trade.note,
      trade.createdBy,
      timeToMillis(trade.updatedAt),
      trade.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return tradeById(trade.id) ?? trade;
  }

  /// Xoá mềm — sổ tiền không xoá hẳn bao giờ, còn phải tra lại được.
  ///
  /// Đánh dấu chờ đẩy luôn, nếu không thì bên kia vẫn giữ bản chưa xoá.
  void softDelete(String id) {
    _db.execute(
      'UPDATE giao_dich SET deleted = 1, dirty = 1, updated_at = ? WHERE id = ?',
      [timeToMillis(DateTime.now()), id],
    );
  }
}
