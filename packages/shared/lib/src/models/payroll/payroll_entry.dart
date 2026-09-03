import '../../ids.dart';
import '../../json_utils.dart';

/// Loại khoản tiền trong sổ.
enum PayrollEntryType {
  /// Ứng lương trước — khoản bị chặn bởi trần 50%.
  ungLuong('ung_luong', 'Ứng lương', false),

  /// Tăng ca — cộng vào thu nhập.
  tangCa('tang_ca', 'Tăng ca', true),

  /// Thưởng / phụ cấp — cộng vào thu nhập.
  phuCap('phu_cap', 'Phụ cấp', true),

  /// Phạt / trừ tiền — giảm thu nhập.
  truTien('tru_tien', 'Trừ tiền', true),

  /// Thanh toán quyết toán, thường chỉ có vào cuối mùa.
  thanhToan('thanh_toan', 'Thanh toán', false);

  const PayrollEntryType(this.value, this.label, this.affectsEarnings);

  final String value;
  final String label;

  /// Khoản này có làm thay đổi **thu nhập** hay không.
  ///
  /// Tăng ca, phụ cấp, trừ tiền làm đổi số tiền người đó được hưởng — nên cũng
  /// làm đổi trần ứng. Còn ứng lương và thanh toán chỉ là **trả tiền ra**,
  /// không sinh thêm thu nhập; lẫn hai nhóm này là tính trần sai ngay.
  final bool affectsEarnings;

  static PayrollEntryType parse(Object? raw) => values.firstWhere(
        (e) => e.value == raw?.toString(),
        orElse: () => PayrollEntryType.ungLuong,
      );
}

/// Một dòng trong sổ tiền của một người.
///
/// Mọi khoản tiền — ứng, tăng ca, phụ cấp, trừ, thanh toán — nằm chung một bảng
/// và phân biệt bằng [type]. Nhờ vậy số dư công nợ luôn là một phép cộng trên
/// một bảng duy nhất, thay vì ghép từ năm chỗ rồi sai một chỗ là lệch sổ.
class PayrollEntry {
  const PayrollEntry({
    required this.id,
    required this.crewId,
    required this.workerId,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.overCapReason,
    this.createdBy,
    required this.updatedAt,
    this.deleted = false,
  });

  factory PayrollEntry.create({
    required String crewId,
    required String workerId,
    required PayrollEntryType type,
    required double amount,
    DateTime? date,
    String? note,
    String? overCapReason,
    String? createdBy,
  }) =>
      PayrollEntry(
        id: newUuid(),
        crewId: crewId,
        workerId: workerId,
        type: type,
        amount: amount,
        date: date ?? DateTime.now(),
        note: note,
        overCapReason: overCapReason,
        createdBy: createdBy,
        updatedAt: DateTime.now(),
      );

  factory PayrollEntry.fromJson(Map<String, Object?> json) => PayrollEntry(
        id: asString(json['id']),
        crewId: asString(json['crew_id']),
        workerId: asString(json['worker_id']),
        type: PayrollEntryType.parse(json['type']),
        amount: asDouble(json['amount']),
        date: asTime(json['date']),
        note: asStringOrNull(json['note']),
        overCapReason: asStringOrNull(json['over_cap_reason']),
        createdBy: asStringOrNull(json['created_by']),
        updatedAt: asTime(json['updated_at']),
        deleted: asBool(json['deleted']),
      );

  final String id;
  final String crewId;
  final String workerId;
  final PayrollEntryType type;

  /// Số tiền, luôn dương. Ý nghĩa cộng hay trừ do [type] quyết định.
  final double amount;
  final DateTime date;
  final String? note;

  /// Lý do khi khoản ứng này vượt trần 50%.
  ///
  /// Có giá trị nghĩa là lần ứng đó đã phá luật có chủ đích — giữ lại để tra
  /// lại sau, vì đây đúng là chỗ dễ sinh thất thoát nhất.
  final String? overCapReason;
  final String? createdBy;
  final DateTime updatedAt;
  final bool deleted;

  bool get isOverCap => (overCapReason ?? '').isNotEmpty;

  /// Khoá gộp theo tháng, dạng `2026-09`.
  String get monthKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  Map<String, Object?> toJson() => {
        'id': id,
        'crew_id': crewId,
        'worker_id': workerId,
        'type': type.value,
        'amount': amount,
        'date': timeToMillis(date),
        'note': note,
        'over_cap_reason': overCapReason,
        'created_by': createdBy,
        'updated_at': timeToMillis(updatedAt),
        'deleted': deleted ? 1 : 0,
      };

  PayrollEntry copyWith({
    double? amount,
    DateTime? date,
    String? note,
    String? overCapReason,
    bool? deleted,
  }) =>
      PayrollEntry(
        id: id,
        crewId: crewId,
        workerId: workerId,
        type: type,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
        overCapReason: overCapReason ?? this.overCapReason,
        createdBy: createdBy,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );
}
