import 'package:canxe_shared/canxe_shared.dart';

/// Giữ lại phiếu đúng [loai]; `null` là xem tất cả.
///
/// Máy chủ đã lọc theo loại, nhưng app lọc lại một lần nữa: máy chủ chạy bản cũ
/// bỏ qua tham số này và trả về đủ mọi loại, khi đó bộ lọc trên màn hình trông như hỏng.
List<WeighTicket> locTheoLoai(List<WeighTicket> phieu, WeighDirection? loai) =>
    loai == null ? phieu : phieu.where((t) => t.direction == loai).toList();

/// Bộ lọc loại sau khi lưu một phiếu: đang lọc một loại thì chuyển sang loại của
/// phiếu vừa lưu để phiếu đó hiện ngay trong bảng; đang xem tất cả thì giữ nguyên.
WeighDirection? loaiLocSauKhiLuu(WeighDirection? dangLoc, WeighDirection daLuu) =>
    dangLoc == null ? null : daLuu;
