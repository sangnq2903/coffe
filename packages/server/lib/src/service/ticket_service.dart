import 'package:canxe_shared/canxe_shared.dart';

import '../db/repository.dart';

/// Lỗi nghiệp vụ — router dịch thành HTTP 400 kèm thông điệp tiếng Việt.
class BusinessException implements Exception {
  BusinessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Nghiệp vụ lập phiếu cân.
///
/// Tách khỏi router để cùng một logic dùng được cho cả API và các luồng khác
/// (đồng bộ, nhập liệu hàng loạt) mà không nhân bản quy tắc tính toán.
class TicketService {
  TicketService(this._repo, {required this.defaultStationCode});

  final Repository _repo;

  /// Mã trạm của chính máy này — dùng khi client không nói rõ lập phiếu cho kho nào.
  final String defaultStationCode;

  /// Tạo phiếu và ghi cân lần 1.
  WeighTicket create(Map<String, Object?> body) {
    final stationCode =
        asString(body['station_code'], fallback: defaultStationCode).toUpperCase();
    if (stationCode.isEmpty) {
      throw BusinessException('Thiếu mã trạm cân khi lập phiếu.');
    }

    final plateNo = Vehicle.normalizePlate(asString(body['plate_no']));
    if (plateNo.isEmpty) {
      throw BusinessException('Chưa nhập biển số xe.');
    }

    final firstWeight = asDoubleOrNull(body['first_weight']);
    if (firstWeight == null) {
      throw BusinessException('Chưa có số cân lần 1.');
    }
    if (firstWeight <= 0) {
      throw BusinessException('Cân lần 1 phải lớn hơn 0 (đang là $firstWeight kg).');
    }

    // Một xe chỉ được có một phiếu dở dang tại một trạm: nếu không, cân lần 2
    // sẽ không biết khớp vào phiếu nào.
    final pending = _repo.pendingTicketForPlate(plateNo, stationCode: stationCode);
    if (pending != null) {
      throw BusinessException(
        'Xe $plateNo đang có phiếu ${pending.ticketNo} chờ cân lần 2. '
        'Hãy hoàn tất hoặc huỷ phiếu đó trước.',
      );
    }

    final vehicle = _resolveVehicle(plateNo, body);
    final customer = _resolveCustomer(body);
    final goods = _resolveGoods(body);

    final yieldRatio = asDoubleOrNull(body['yield_ratio']) ??
        goods?.defaultYieldRatio ??
        100;
    _validateYieldRatio(yieldRatio);

    final ticket = WeighTicket.create(
      ticketNo: _repo.nextTicketNo(stationCode),
      stationCode: stationCode,
      direction: WeighDirection.parse(body['direction']),
      customerId: customer?.id,
      customerName: customer?.name ?? asString(body['customer_name']),
      vehicleId: vehicle?.id,
      plateNo: plateNo,
      driverName: asStringOrNull(body['driver_name']) ?? vehicle?.driverName,
      goodsTypeId: goods?.id,
      goodsName: goods?.name ?? asString(body['goods_name']),
      yieldRatio: yieldRatio,
      firstWeight: firstWeight,
      note: asStringOrNull(body['note']),
      createdBy: asStringOrNull(body['created_by']),
    );
    return _repo.upsertTicket(ticket);
  }

  /// Ghi cân lần 2 và chốt phiếu.
  WeighTicket completeSecondWeigh(String id, Map<String, Object?> body) {
    final ticket = _repo.ticketById(id);
    if (ticket == null || ticket.deleted) {
      throw BusinessException('Không tìm thấy phiếu cân.');
    }
    if (ticket.status == TicketStatus.huy) {
      throw BusinessException('Phiếu ${ticket.ticketNo} đã bị huỷ.');
    }
    if (ticket.status == TicketStatus.hoanThanh) {
      throw BusinessException(
        'Phiếu ${ticket.ticketNo} đã cân lần 2 xong. Muốn sửa hãy dùng chức năng chỉnh phiếu.',
      );
    }

    final secondWeight = asDoubleOrNull(body['second_weight']);
    if (secondWeight == null) {
      throw BusinessException('Chưa có số cân lần 2.');
    }
    if (secondWeight <= 0) {
      throw BusinessException('Cân lần 2 phải lớn hơn 0 (đang là $secondWeight kg).');
    }
    final first = ticket.firstWeight ?? 0;
    if ((first - secondWeight).abs() < 0.0001) {
      throw BusinessException(
        'Cân lần 2 bằng cân lần 1 ($first kg) nên khối lượng hàng bằng 0. '
        'Kiểm tra lại xe đã lên/xuống bàn cân chưa.',
      );
    }

    final updated = ticket.copyWith(
      secondWeight: secondWeight,
      secondWeightAt: DateTime.now(),
      status: TicketStatus.hoanThanh,
      note: asStringOrNull(body['note']) ?? ticket.note,
      updatedAt: DateTime.now(),
    );
    return _repo.upsertTicket(updated);
  }

  /// Sửa thông tin phiếu (khách hàng, loại hàng, tỷ lệ, ghi chú, số cân).
  WeighTicket update(String id, Map<String, Object?> body) {
    final ticket = _repo.ticketById(id);
    if (ticket == null || ticket.deleted) {
      throw BusinessException('Không tìm thấy phiếu cân.');
    }

    final goods = _resolveGoods(body);
    final customer = _resolveCustomer(body);
    final yieldRatio = asDoubleOrNull(body['yield_ratio']) ?? ticket.yieldRatio;
    _validateYieldRatio(yieldRatio);

    // Cho sửa biển số vì gõ sai biển là lỗi hay gặp nhất, nhưng vẫn giữ luật
    // "một xe chỉ có một phiếu chờ cân lần 2 tại một trạm": sửa thành biển
    // đang có phiếu dở dang khác thì cân lần 2 không biết khớp vào phiếu nào.
    var plateNo = ticket.plateNo;
    if (body.containsKey('plate_no')) {
      plateNo = Vehicle.normalizePlate(asString(body['plate_no']));
      if (plateNo.isEmpty) throw BusinessException('Biển số xe không được để trống.');
      if (plateNo != ticket.plateNo) {
        final pending =
            _repo.pendingTicketForPlate(plateNo, stationCode: ticket.stationCode);
        if (pending != null && pending.id != ticket.id) {
          throw BusinessException(
            'Xe $plateNo đang có phiếu ${pending.ticketNo} chờ cân lần 2. '
            'Hãy hoàn tất hoặc huỷ phiếu đó trước.',
          );
        }
      }
    }

    final firstWeight = asDoubleOrNull(body['first_weight']) ?? ticket.firstWeight;
    final secondWeight = asDoubleOrNull(body['second_weight']) ?? ticket.secondWeight;

    final updated = ticket.copyWith(
      direction: body.containsKey('direction')
          ? WeighDirection.parse(body['direction'])
          : ticket.direction,
      plateNo: plateNo,
      vehicleId: plateNo == ticket.plateNo
          ? ticket.vehicleId
          : _resolveVehicle(plateNo, body)?.id,
      customerId: customer?.id ?? ticket.customerId,
      customerName: customer?.name ?? asStringOrNull(body['customer_name']) ?? ticket.customerName,
      driverName: asStringOrNull(body['driver_name']) ?? ticket.driverName,
      goodsTypeId: goods?.id ?? ticket.goodsTypeId,
      goodsName: goods?.name ?? asStringOrNull(body['goods_name']) ?? ticket.goodsName,
      yieldRatio: yieldRatio,
      firstWeight: firstWeight,
      secondWeight: secondWeight,
      status: secondWeight != null ? TicketStatus.hoanThanh : ticket.status,
      secondWeightAt: secondWeight != null
          ? (ticket.secondWeightAt ?? DateTime.now())
          : ticket.secondWeightAt,
      note: asStringOrNull(body['note']) ?? ticket.note,
      updatedAt: DateTime.now(),
    );
    return _repo.upsertTicket(updated);
  }

  WeighTicket cancel(String id, {String? reason}) {
    final ticket = _repo.ticketById(id);
    if (ticket == null || ticket.deleted) {
      throw BusinessException('Không tìm thấy phiếu cân.');
    }
    final note = reason == null || reason.isEmpty
        ? ticket.note
        : '${ticket.note ?? ''}\n[Huỷ] $reason'.trim();
    return _repo.upsertTicket(ticket.copyWith(
      status: TicketStatus.huy,
      note: note,
      updatedAt: DateTime.now(),
    ));
  }

  void _validateYieldRatio(double value) {
    if (value < 0 || value > 100) {
      throw BusinessException('Tỷ lệ thành phẩm phải nằm trong khoảng 0–100% (đang là $value).');
    }
  }

  /// Tìm xe theo id hoặc biển số; chưa có thì tạo mới ngay để nhân viên không
  /// phải rời màn hình cân đi khai báo danh mục khi xe lạ vào kho.
  Vehicle? _resolveVehicle(String plateNo, Map<String, Object?> body) {
    final id = asStringOrNull(body['vehicle_id']);
    if (id != null) {
      final existing = _repo.vehicleById(id);
      if (existing != null) return existing;
    }
    final byPlate = _repo.vehicleByPlate(plateNo);
    if (byPlate != null) return byPlate;
    return _repo.upsertVehicle(Vehicle.create(
      plateNo: plateNo,
      driverName: asStringOrNull(body['driver_name']),
      customerId: asStringOrNull(body['customer_id']),
    ));
  }

  Customer? _resolveCustomer(Map<String, Object?> body) {
    final id = asStringOrNull(body['customer_id']);
    if (id != null) {
      final existing = _repo.customerById(id);
      if (existing != null) return existing;
    }
    final name = asString(body['customer_name']).trim();
    if (name.isEmpty) return null;
    final match = _repo
        .customers(query: name)
        .where((c) => c.name.toLowerCase() == name.toLowerCase())
        .toList();
    if (match.isNotEmpty) return match.first;
    return _repo.upsertCustomer(Customer.create(name: name));
  }

  GoodsType? _resolveGoods(Map<String, Object?> body) {
    final id = asStringOrNull(body['goods_type_id']);
    if (id != null) {
      final existing = _repo.goodsTypeById(id);
      if (existing != null) return existing;
    }
    final name = asString(body['goods_name']).trim();
    if (name.isEmpty) return null;
    final match = _repo
        .goodsTypes(includeInactive: true)
        .where((g) => g.name.toLowerCase() == name.toLowerCase() || g.code == name.toUpperCase())
        .toList();
    return match.isEmpty ? null : match.first;
  }
}
