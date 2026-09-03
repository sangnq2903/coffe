import 'package:canxe_shared/canxe_shared.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Truy cập dữ liệu cho cả hai vai trò server. Cùng một lược đồ chạy ở trạm cân
/// lẫn máy chủ trung tâm, chỉ khác nhau ở việc ai đồng bộ cho ai.
class Repository {
  Repository(this._appDb);

  final AppDatabase _appDb;

  Database get _db => _appDb.db;

  // ============================================================== khách hàng

  List<Customer> customers({String? query, bool includeInactive = false}) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (!includeInactive) where.add('active = 1');
    if (query != null && query.trim().isNotEmpty) {
      where.add('(lower(name) LIKE ?1 OR lower(code) LIKE ?1 OR ifnull(phone, "") LIKE ?1)');
      args.add('%${query.trim().toLowerCase()}%');
    }
    final rows = _db.select(
      'SELECT * FROM customers WHERE ${where.join(" AND ")} ORDER BY name COLLATE NOCASE LIMIT 500',
      args,
    );
    return rows.map((r) => Customer.fromJson(r)).toList();
  }

  Customer? customerById(String id) {
    final rows = _db.select('SELECT * FROM customers WHERE id = ?', [id]);
    return rows.isEmpty ? null : Customer.fromJson(rows.first);
  }

  Customer upsertCustomer(Customer customer, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO customers (id, code, name, phone, address, tax_code, note, active, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        code = excluded.code, name = excluded.name, phone = excluded.phone,
        address = excluded.address, tax_code = excluded.tax_code, note = excluded.note,
        active = excluded.active, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= customers.updated_at
    ''', [
      customer.id,
      customer.code,
      customer.name,
      customer.phone,
      customer.address,
      customer.taxCode,
      customer.note,
      customer.active ? 1 : 0,
      timeToMillis(customer.updatedAt),
      customer.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return customerById(customer.id) ?? customer;
  }

  void softDeleteCustomer(String id) => _softDelete('customers', id);

  // ===================================================================== xe

  List<Vehicle> vehicles({String? query, bool includeInactive = false}) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (!includeInactive) where.add('active = 1');
    if (query != null && query.trim().isNotEmpty) {
      where.add('(lower(plate_no) LIKE ?1 OR lower(ifnull(driver_name, "")) LIKE ?1)');
      args.add('%${query.trim().toLowerCase()}%');
    }
    final rows = _db.select(
      'SELECT * FROM vehicles WHERE ${where.join(" AND ")} ORDER BY plate_no LIMIT 500',
      args,
    );
    return rows.map((r) => Vehicle.fromJson(r)).toList();
  }

  Vehicle? vehicleById(String id) {
    final rows = _db.select('SELECT * FROM vehicles WHERE id = ?', [id]);
    return rows.isEmpty ? null : Vehicle.fromJson(rows.first);
  }

  Vehicle? vehicleByPlate(String plateNo) {
    final rows = _db.select(
      'SELECT * FROM vehicles WHERE plate_no = ? AND deleted = 0 LIMIT 1',
      [Vehicle.normalizePlate(plateNo)],
    );
    return rows.isEmpty ? null : Vehicle.fromJson(rows.first);
  }

  Vehicle upsertVehicle(Vehicle vehicle, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO vehicles (id, plate_no, customer_id, driver_name, driver_phone, tare_weight, note, active, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        plate_no = excluded.plate_no, customer_id = excluded.customer_id,
        driver_name = excluded.driver_name, driver_phone = excluded.driver_phone,
        tare_weight = excluded.tare_weight, note = excluded.note,
        active = excluded.active, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= vehicles.updated_at
    ''', [
      vehicle.id,
      vehicle.plateNo,
      vehicle.customerId,
      vehicle.driverName,
      vehicle.driverPhone,
      vehicle.tareWeight,
      vehicle.note,
      vehicle.active ? 1 : 0,
      timeToMillis(vehicle.updatedAt),
      vehicle.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return vehicleById(vehicle.id) ?? vehicle;
  }

  void softDeleteVehicle(String id) => _softDelete('vehicles', id);

  // ============================================================== loại hàng

  List<GoodsType> goodsTypes({bool includeInactive = false}) {
    final where = includeInactive ? 'deleted = 0' : 'deleted = 0 AND active = 1';
    final rows = _db.select(
      'SELECT * FROM goods_types WHERE $where ORDER BY sort_order, name COLLATE NOCASE',
    );
    return rows.map((r) => GoodsType.fromJson(r)).toList();
  }

  GoodsType? goodsTypeById(String id) {
    final rows = _db.select('SELECT * FROM goods_types WHERE id = ?', [id]);
    return rows.isEmpty ? null : GoodsType.fromJson(rows.first);
  }

  GoodsType upsertGoodsType(GoodsType goods, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO goods_types (id, code, name, unit, default_yield_ratio, sort_order, active, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        code = excluded.code, name = excluded.name, unit = excluded.unit,
        default_yield_ratio = excluded.default_yield_ratio, sort_order = excluded.sort_order,
        active = excluded.active, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= goods_types.updated_at
    ''', [
      goods.id,
      goods.code,
      goods.name,
      goods.unit,
      goods.defaultYieldRatio,
      goods.sortOrder,
      goods.active ? 1 : 0,
      timeToMillis(goods.updatedAt),
      goods.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return goodsTypeById(goods.id) ?? goods;
  }

  void softDeleteGoodsType(String id) => _softDelete('goods_types', id);

  /// Nạp danh mục loại hàng mặc định cho lần chạy đầu tiên.
  void seedGoodsTypesIfEmpty() {
    final count = _db.select('SELECT COUNT(*) AS c FROM goods_types').first['c'] as int;
    if (count > 0) return;
    for (final goods in GoodsType.seed()) {
      upsertGoodsType(goods);
    }
  }

  // ================================================================== trạm

  List<Station> stations({bool includeDeleted = false}) {
    final rows = _db.select(
      'SELECT * FROM stations ${includeDeleted ? "" : "WHERE deleted = 0"} ORDER BY code',
    );
    return rows.map((r) => Station.fromJson(r)).toList();
  }

  Station? stationByCode(String code) {
    final rows = _db.select('SELECT * FROM stations WHERE code = ?', [code]);
    return rows.isEmpty ? null : Station.fromJson(rows.first);
  }

  Station upsertStation(Station station) {
    _db.execute('''
      INSERT INTO stations (code, name, warehouse_name, address, base_url, online, last_seen_at, scale_connected, scale_port, updated_at, deleted)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(code) DO UPDATE SET
        name = excluded.name, warehouse_name = excluded.warehouse_name,
        address = excluded.address, base_url = excluded.base_url,
        online = excluded.online, last_seen_at = excluded.last_seen_at,
        scale_connected = excluded.scale_connected, scale_port = excluded.scale_port,
        updated_at = excluded.updated_at, deleted = excluded.deleted
    ''', [
      station.code,
      station.name,
      station.warehouseName,
      station.address,
      station.baseUrl,
      station.online ? 1 : 0,
      timeToMillisOrNull(station.lastSeenAt),
      station.scaleConnected ? 1 : 0,
      station.scalePort,
      timeToMillis(station.updatedAt),
      station.deleted ? 1 : 0,
    ]);
    return stationByCode(station.code) ?? station;
  }

  void markStationOffline(String code) {
    _db.execute(
      'UPDATE stations SET online = 0, updated_at = ? WHERE code = ?',
      [timeToMillis(DateTime.now()), code],
    );
  }

  // ============================================================= phiếu cân

  List<WeighTicket> tickets({
    String? stationCode,
    TicketStatus? status,
    String? query,
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
  }) {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (stationCode != null && stationCode.isNotEmpty) {
      where.add('station_code = ?');
      args.add(stationCode);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status.value);
    }
    if (query != null && query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      where.add('(lower(plate_no) LIKE ? OR lower(customer_name) LIKE ? OR lower(ticket_no) LIKE ?)');
      args.addAll([like, like, like]);
    }
    if (from != null) {
      where.add('created_at >= ?');
      args.add(timeToMillis(from));
    }
    if (to != null) {
      where.add('created_at <= ?');
      args.add(timeToMillis(to));
    }
    args.addAll([limit.clamp(1, 1000), offset.clamp(0, 1 << 30)]);
    final rows = _db.select(
      'SELECT * FROM tickets WHERE ${where.join(" AND ")} '
      'ORDER BY created_at DESC LIMIT ? OFFSET ?',
      args,
    );
    return rows.map((r) => WeighTicket.fromJson(r)).toList();
  }

  WeighTicket? ticketById(String id) {
    final rows = _db.select('SELECT * FROM tickets WHERE id = ?', [id]);
    return rows.isEmpty ? null : WeighTicket.fromJson(rows.first);
  }

  /// Phiếu đang chờ cân lần 2 của một biển số — dùng để tự nhận diện xe quay
  /// lại bàn cân mà nhân viên không phải tìm tay.
  WeighTicket? pendingTicketForPlate(String plateNo, {String? stationCode}) {
    final rows = _db.select(
      'SELECT * FROM tickets WHERE plate_no = ? AND status = ? AND deleted = 0 '
      '${stationCode != null ? "AND station_code = ?" : ""} '
      'ORDER BY created_at DESC LIMIT 1',
      [
        Vehicle.normalizePlate(plateNo),
        TicketStatus.choLan2.value,
        if (stationCode != null) stationCode,
      ],
    );
    return rows.isEmpty ? null : WeighTicket.fromJson(rows.first);
  }

  WeighTicket upsertTicket(WeighTicket ticket, {bool dirty = true}) {
    _db.execute('''
      INSERT INTO tickets (
        id, ticket_no, station_code, direction, status, customer_id, customer_name,
        vehicle_id, plate_no, driver_name, goods_type_id, goods_name, yield_ratio,
        first_weight, first_weight_at, second_weight, second_weight_at,
        net_weight, product_weight, note, created_by, created_at, updated_at, deleted, dirty)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        ticket_no = excluded.ticket_no, direction = excluded.direction,
        status = excluded.status, customer_id = excluded.customer_id,
        customer_name = excluded.customer_name, vehicle_id = excluded.vehicle_id,
        plate_no = excluded.plate_no, driver_name = excluded.driver_name,
        goods_type_id = excluded.goods_type_id, goods_name = excluded.goods_name,
        yield_ratio = excluded.yield_ratio, first_weight = excluded.first_weight,
        first_weight_at = excluded.first_weight_at, second_weight = excluded.second_weight,
        second_weight_at = excluded.second_weight_at, net_weight = excluded.net_weight,
        product_weight = excluded.product_weight, note = excluded.note,
        created_by = excluded.created_by, updated_at = excluded.updated_at,
        deleted = excluded.deleted, dirty = excluded.dirty
      WHERE excluded.updated_at >= tickets.updated_at
    ''', [
      ticket.id,
      ticket.ticketNo,
      ticket.stationCode,
      ticket.direction.value,
      ticket.status.value,
      ticket.customerId,
      ticket.customerName,
      ticket.vehicleId,
      ticket.plateNo,
      ticket.driverName,
      ticket.goodsTypeId,
      ticket.goodsName,
      ticket.yieldRatio,
      ticket.firstWeight,
      timeToMillisOrNull(ticket.firstWeightAt),
      ticket.secondWeight,
      timeToMillisOrNull(ticket.secondWeightAt),
      ticket.netWeight,
      ticket.productWeight,
      ticket.note,
      ticket.createdBy,
      timeToMillis(ticket.createdAt),
      timeToMillis(ticket.updatedAt),
      ticket.deleted ? 1 : 0,
      dirty ? 1 : 0,
    ]);
    return ticketById(ticket.id) ?? ticket;
  }

  void softDeleteTicket(String id) => _softDelete('tickets', id);

  /// Cấp số phiếu kế tiếp dạng `KHO01-260903-0001`.
  ///
  /// Bộ đếm nằm trong cùng một transaction với lệnh đọc nên hai phiếu lập cùng
  /// lúc không thể nhận trùng số.
  String nextTicketNo(String stationCode, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final day = '${at.year % 100}'.padLeft(2, '0') +
        '${at.month}'.padLeft(2, '0') +
        '${at.day}'.padLeft(2, '0');
    late int seq;
    _transaction(() {
      _db.execute('''
        INSERT INTO ticket_counters (station_code, day, seq) VALUES (?, ?, 1)
        ON CONFLICT(station_code, day) DO UPDATE SET seq = seq + 1
      ''', [stationCode, day]);
      seq = _db.select(
        'SELECT seq FROM ticket_counters WHERE station_code = ? AND day = ?',
        [stationCode, day],
      ).first['seq'] as int;
    });
    return '$stationCode-$day-${seq.toString().padLeft(4, '0')}';
  }

  // =============================================================== đồng bộ

  /// Lấy các bản ghi thay đổi sau mốc [since] để đẩy sang bên kia.
  SyncPayload changesSince(DateTime? since, {String? stationCode, int limit = 500}) {
    final ms = timeToMillis(since ?? DateTime.fromMillisecondsSinceEpoch(0));
    List<T> load<T>(String table, T Function(Map<String, Object?>) parse, {bool byStation = false}) {
      final filter = byStation && stationCode != null && stationCode.isNotEmpty
          ? 'AND station_code = ?'
          : '';
      final rows = _db.select(
        'SELECT * FROM $table WHERE updated_at > ? $filter ORDER BY updated_at LIMIT ?',
        [ms, if (filter.isNotEmpty) stationCode, limit],
      );
      return rows.map((r) => parse(r)).toList();
    }

    return SyncPayload(
      customers: load('customers', Customer.fromJson),
      vehicles: load('vehicles', Vehicle.fromJson),
      goodsTypes: load('goods_types', GoodsType.fromJson),
      tickets: load('tickets', WeighTicket.fromJson),
      serverTime: DateTime.now(),
    );
  }

  /// Các bản ghi do máy này tạo/sửa mà chưa đẩy lên trung tâm.
  SyncPayload dirtyChanges({int limit = 300}) {
    List<T> load<T>(String table, T Function(Map<String, Object?>) parse) => _db
        .select('SELECT * FROM $table WHERE dirty = 1 ORDER BY updated_at LIMIT ?', [limit])
        .map((r) => parse(r))
        .toList();

    return SyncPayload(
      customers: load('customers', Customer.fromJson),
      vehicles: load('vehicles', Vehicle.fromJson),
      goodsTypes: load('goods_types', GoodsType.fromJson),
      tickets: load('tickets', WeighTicket.fromJson),
    );
  }

  int pendingPushCount() {
    var total = 0;
    for (final table in ['customers', 'vehicles', 'goods_types', 'tickets']) {
      total += _db.select('SELECT COUNT(*) AS c FROM $table WHERE dirty = 1').first['c'] as int;
    }
    return total;
  }

  /// Ghi dữ liệu nhận được từ bên kia vào cơ sở dữ liệu.
  ///
  /// [markDirty] = false khi áp dụng dữ liệu đến từ đồng bộ: bản ghi vừa nhận
  /// không được đánh dấu "cần đẩy đi", nếu không hai bên sẽ đẩy qua đẩy lại mãi.
  int applyPayload(SyncPayload payload, {bool markDirty = false}) {
    var applied = 0;
    _transaction(() {
      for (final c in payload.customers) {
        upsertCustomer(c, dirty: markDirty);
        applied++;
      }
      for (final v in payload.vehicles) {
        upsertVehicle(v, dirty: markDirty);
        applied++;
      }
      for (final g in payload.goodsTypes) {
        upsertGoodsType(g, dirty: markDirty);
        applied++;
      }
      for (final t in payload.tickets) {
        upsertTicket(t, dirty: markDirty);
        applied++;
      }
    });
    return applied;
  }

  /// Xoá cờ "cần đẩy" sau khi trung tâm đã xác nhận nhận đủ.
  void clearDirty(SyncPayload pushed) {
    _transaction(() {
      void clear(String table, Iterable<String> ids) {
        for (final id in ids) {
          _db.execute('UPDATE $table SET dirty = 0 WHERE id = ?', [id]);
        }
      }

      clear('customers', pushed.customers.map((e) => e.id));
      clear('vehicles', pushed.vehicles.map((e) => e.id));
      clear('goods_types', pushed.goodsTypes.map((e) => e.id));
      clear('tickets', pushed.tickets.map((e) => e.id));
    });
  }

  DateTime? syncMark(String key) {
    final rows = _db.select('SELECT value FROM sync_state WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    final ms = int.tryParse('${rows.first['value']}');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }

  void setSyncMark(String key, DateTime value) {
    _db.execute(
      'INSERT INTO sync_state (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, timeToMillis(value).toString()],
    );
  }

  // ================================================================= nội bộ

  void _softDelete(String table, String id) {
    _db.execute(
      'UPDATE $table SET deleted = 1, dirty = 1, updated_at = ? WHERE id = ?',
      [timeToMillis(DateTime.now()), id],
    );
  }

  void _transaction(void Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }
}
