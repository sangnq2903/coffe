import 'dart:convert';

import '../json_utils.dart';

/// Một khoản chi phí tính theo **đồng trên mỗi ký**.
///
/// Bán hàng thì phải biết một ký hàng đó tốn bao nhiêu mới ra được: tiền mua
/// nguyên liệu, tiền điện chạy máy, tiền xe chở, tiền công. Ghi theo đ/kg vì đó
/// là cách người làm nghề nhẩm — bán bao nhiêu ký thì nhân lên bấy nhiêu.
class CostItem {
  const CostItem({required this.name, required this.perKg});

  factory CostItem.fromJson(Map<String, Object?> json) => CostItem(
        name: asString(json['name']),
        perKg: asDouble(json['per_kg']),
      );

  final String name;
  final double perKg;

  Map<String, Object?> toJson() => {'name': name, 'per_kg': perKg};

  CostItem copyWith({String? name, double? perKg}) =>
      CostItem(name: name ?? this.name, perKg: perKg ?? this.perKg);

  /// Đọc danh sách khoản chi từ chuỗi JSON lưu trong một cột.
  ///
  /// Lưu thành một cột JSON chứ không thành bảng riêng: số khoản chi chỉ vài
  /// dòng, mà thêm một bảng là phải dựng thêm cả luồng đồng bộ cho nó.
  static List<CostItem> listFromJson(Object? raw) {
    if (raw == null) return const [];

    Object? data = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        data = jsonDecode(raw);
      } catch (_) {
        // Ô trong cơ sở dữ liệu hỏng thì coi như chưa khai khoản nào; làm nổ cả
        // màn hình vì một ô hỏng là mất luôn cả sổ.
        return const [];
      }
    }
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => CostItem.fromJson(e.cast<String, Object?>()))
        .where((e) => e.name.isNotEmpty)
        .toList();
  }

  /// Ghi danh sách ra chuỗi JSON để cất vào một cột.
  static String listToJson(List<CostItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  /// Tổng đ/kg của cả danh sách.
  static double perKgTotal(Iterable<CostItem> items) =>
      items.fold(0, (t, e) => t + e.perKg);
}
