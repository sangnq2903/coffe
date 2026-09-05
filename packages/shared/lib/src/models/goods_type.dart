import '../ids.dart';
import '../json_utils.dart';
import 'cost_item.dart';

/// Loại hàng: trấu, cà nhân, cà tươi, cà khô... Danh mục mở, người dùng thêm
/// được loại mới mà không phải sửa code.
class GoodsType {
  const GoodsType({
    required this.id,
    required this.code,
    required this.name,
    this.unit = 'kg',
    this.defaultYieldRatio = 100,
    this.costItems = const [],
    this.sortOrder = 0,
    this.active = true,
    required this.updatedAt,
    this.deleted = false,
  });

  factory GoodsType.create({
    required String code,
    required String name,
    String unit = 'kg',
    double defaultYieldRatio = 100,
    List<CostItem> costItems = const [],
    int sortOrder = 0,
  }) =>
      GoodsType(
        id: newUuid(),
        code: code,
        name: name,
        unit: unit,
        defaultYieldRatio: defaultYieldRatio,
        costItems: costItems,
        sortOrder: sortOrder,
        updatedAt: DateTime.now(),
      );

  factory GoodsType.fromJson(Map<String, Object?> json) => GoodsType(
        id: asString(json['id']),
        code: asString(json['code']),
        name: asString(json['name']),
        unit: asString(json['unit'], fallback: 'kg'),
        defaultYieldRatio: asDouble(json['default_yield_ratio'], fallback: 100),
        costItems: CostItem.listFromJson(json['cost_items']),
        sortOrder: asInt(json['sort_order']),
        active: asBool(json['active'], fallback: true),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  /// Danh mục khởi tạo sẵn theo đúng nghiệp vụ đang dùng.
  ///
  /// Tỷ lệ thành phẩm mặc định chỉ là gợi ý điền nhanh khi lập phiếu; nhân viên
  /// cân vẫn sửa được trên từng phiếu.
  ///
  /// Id được cố định (không sinh ngẫu nhiên): trạm cân và máy chủ trung tâm đều
  /// tự nạp danh mục này khi chạy lần đầu, nếu id khác nhau thì sau khi đồng bộ
  /// sẽ có hai bộ "trấu, cà nhân, cà tươi, cà khô" trùng tên.
  static List<GoodsType> seed() {
    final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return [
      GoodsType(
        id: '00000000-0000-4000-8000-000000000001',
        code: 'TRAU',
        name: 'Trấu',
        defaultYieldRatio: 100,
        sortOrder: 1,
        updatedAt: now,
      ),
      GoodsType(
        id: '00000000-0000-4000-8000-000000000002',
        code: 'CANHAN',
        name: 'Cà nhân',
        defaultYieldRatio: 100,
        sortOrder: 2,
        updatedAt: now,
      ),
      GoodsType(
        id: '00000000-0000-4000-8000-000000000003',
        code: 'CATUOI',
        name: 'Cà tươi',
        defaultYieldRatio: 20,
        sortOrder: 3,
        updatedAt: now,
      ),
      GoodsType(
        id: '00000000-0000-4000-8000-000000000004',
        code: 'CAKHO',
        name: 'Cà khô',
        defaultYieldRatio: 55,
        sortOrder: 4,
        updatedAt: now,
      ),
    ];
  }

  final String id;
  final String code;
  final String name;
  final String unit;

  /// Tỷ lệ thành phẩm mặc định (%), ví dụ cà tươi ~20% ra cà nhân.
  final double defaultYieldRatio;

  /// Định mức chi phí để ra được một ký hàng này: tiền mua nguyên liệu, điện,
  /// xe, công... Dùng để tính lãi thật mỗi khi bán.
  final List<CostItem> costItems;

  /// Tổng chi phí định mức, đ/kg.
  double get costPerKg => CostItem.perKgTotal(costItems);

  final int sortOrder;
  final bool active;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'unit': unit,
        'default_yield_ratio': defaultYieldRatio,
        'cost_items': CostItem.listToJson(costItems),
        'sort_order': sortOrder,
        'active': active ? 1 : 0,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  GoodsType copyWith({
    String? code,
    String? name,
    String? unit,
    double? defaultYieldRatio,
    List<CostItem>? costItems,
    int? sortOrder,
    bool? active,
    bool? deleted,
  }) =>
      GoodsType(
        id: id,
        code: code ?? this.code,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        defaultYieldRatio: defaultYieldRatio ?? this.defaultYieldRatio,
        costItems: costItems ?? this.costItems,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
