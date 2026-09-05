import 'package:canxe_shared/canxe_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../config.dart';
import '../service/trade_service.dart';

/// Các đường dẫn API của **sổ mua bán**.
///
/// Hai lớp chặn, cả hai đều nằm ở đây chứ không rải trong từng đường dẫn:
///
/// - **Chỉ tài khoản chủ.** Không phải "quản lý tổng" — giá mua vào là thứ
///   riêng của chủ, quản lý tổng vẫn làm mọi việc khác như cũ.
/// - **Chỉ máy chủ trung tâm.** Sổ này không đi kèm gói đồng bộ, nên nếu mở
///   được ở máy trạm thì dữ liệu ghi ra sẽ nằm lại đó một mình. Chặn thẳng và
///   nói rõ lý do còn hơn để người dùng ghi vào chỗ không ai thấy.
class TradeRouter {
  TradeRouter({
    required this.service,
    required this.config,
    required this.json,
    required this.error,
    required this.guard,
    required this.body,
    required this.user,
  });

  final TradeService service;
  final ServerConfig config;

  final Response Function(Object? data) json;
  final Response Function(String message, int status) error;
  final Response Function(Response Function()) guard;
  final Future<Map<String, Object?>> Function(Request) body;
  final AppUser Function(Request) user;

  void attach(Router router) {
    router.get('/api/giao-dich', (Request request) => guard(() {
          final chan = _chan(request);
          if (chan != null) return chan;

          final q = request.url.queryParameters;
          final loc = _filters(q);
          return json({
            'items': service
                .list(
                  from: loc.from,
                  to: loc.to,
                  kind: loc.kind,
                  hasInvoice: loc.hasInvoice,
                  goodsTypeId: loc.goodsTypeId,
                  partnerId: loc.partnerId,
                  query: loc.query,
                  limit: _limit(q['limit']),
                )
                .map((e) => e.toJson())
                .toList(),
            // Số tổng tính trên đúng bộ lọc đang xem, gửi kèm luôn để màn hình
            // không phải gọi thêm một lượt nữa và không sợ hai bên lệch nhau.
            'summary': service
                .summary(
                  from: loc.from,
                  to: loc.to,
                  kind: loc.kind,
                  hasInvoice: loc.hasInvoice,
                  goodsTypeId: loc.goodsTypeId,
                  partnerId: loc.partnerId,
                  query: loc.query,
                )
                .toJson(),
          });
        }));

    router.post('/api/giao-dich', (Request request) async {
      final data = await body(request);
      return guard(() {
        final chan = _chan(request);
        if (chan != null) return chan;
        return json(service.save(data, createdBy: user(request).username).toJson());
      });
    });

    router.post('/api/giao-dich/<id>', (Request request, String id) async {
      final data = await body(request);
      return guard(() {
        final chan = _chan(request);
        if (chan != null) return chan;
        return json(
            service.save({...data, 'id': id}, createdBy: user(request).username).toJson());
      });
    });

    router.delete('/api/giao-dich/<id>', (Request request, String id) => guard(() {
          final chan = _chan(request);
          if (chan != null) return chan;
          service.delete(id);
          return json({'ok': true});
        }));
  }

  /// Số dòng tối đa; bỏ trống hoặc 0 nghĩa là lấy hết.
  static int? _limit(String? raw) {
    final n = asInt(raw);
    return n > 0 ? n : null;
  }

  /// Trả về phản hồi từ chối nếu không được phép, `null` nếu qua cả hai lớp.
  Response? _chan(Request request) {
    if (config.role != ServerRole.central) {
      return error(
        'Sổ mua bán chỉ có trên máy chủ trung tâm. Dữ liệu này không đồng bộ '
        'xuống kho, nên phải mở app bằng địa chỉ của máy trung tâm.',
        409,
      );
    }
    if (!user(request).isOwner) {
      return error('Sổ mua bán chỉ dành cho tài khoản chủ.', 403);
    }
    return null;
  }

  ({
    DateTime? from,
    DateTime? to,
    TradeKind? kind,
    bool? hasInvoice,
    String? goodsTypeId,
    String? partnerId,
    String? query,
  }) _filters(Map<String, String> q) {
    // `hoa_don` để trống nghĩa là xem cả hai loại; chỉ "1"/"0" mới lọc.
    final hd = q['hoa_don'];
    return (
      from: asTimeOrNull(q['from']),
      to: asTimeOrNull(q['to']),
      kind: q['kind'] == null || q['kind']!.isEmpty ? null : TradeKind.parse(q['kind']),
      hasInvoice: hd == null || hd.isEmpty ? null : (hd == '1' || hd == 'true'),
      goodsTypeId: q['goods_type_id'],
      partnerId: q['partner_id'],
      query: q['q'],
    );
  }
}
