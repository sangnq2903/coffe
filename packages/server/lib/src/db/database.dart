import 'dart:ffi';
import 'dart:io';

import 'package:canxe_shared/canxe_shared.dart';
import 'package:path/path.dart' as p;
// Đặt bí danh vì `open` của sqlite3 trùng tên với hàm khởi tạo tĩnh bên dưới.
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

/// Mở cơ sở dữ liệu SQLite và tạo/nâng cấp lược đồ.
///
/// Dùng SQLite vì hệ thống phải chạy được ở kho không có người quản trị: không
/// cần cài đặt dịch vụ, sao lưu chỉ là chép một file.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;
  final String path;

  static bool _openConfigured = false;

  /// Trên Windows không có sẵn `sqlite3.dll` cho ứng dụng Dart, nhưng hệ điều
  /// hành từ Windows 10 có `winsqlite3.dll` trong System32. Ưu tiên DLL đặt
  /// cạnh chương trình (nếu người dùng tự chép vào) rồi mới dùng bản hệ thống.
  static void _configureOpen() {
    if (_openConfigured || !Platform.isWindows) return;
    _openConfigured = true;
    sqlite_open.open.overrideFor(sqlite_open.OperatingSystem.windows, () {
      final candidates = <String>[
        p.join(p.dirname(Platform.resolvedExecutable), 'sqlite3.dll'),
        p.join(Directory.current.path, 'sqlite3.dll'),
        'sqlite3.dll',
        'winsqlite3.dll',
      ];
      Object? lastError;
      for (final candidate in candidates) {
        try {
          return DynamicLibrary.open(candidate);
        } catch (e) {
          lastError = e;
        }
      }
      throw StateError(
        'Không nạp được thư viện SQLite. Đã thử: ${candidates.join(", ")}. '
        'Lỗi cuối: $lastError',
      );
    });
  }

  static AppDatabase open(String path) {
    _configureOpen();
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final db = sqlite3.open(path);
    // WAL cho phép đọc trong lúc đang ghi — màn hình danh sách phiếu không bị
    // khoá khi trạm đang đồng bộ hàng loạt bản ghi.
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA busy_timeout = 5000;');

    // `lower()` của SQLite chỉ biết chữ Latin không dấu, nên "Cà nhân" không
    // bao giờ khớp với "ca nhan". Gắn thẳng hàm bỏ dấu của Dart vào SQLite để
    // lọc ngay trong câu truy vấn — lọc ở đây thì con số tổng vẫn tính đúng
    // trên phần đang xem, còn lọc sau khi đã đọc lên thì tổng một đằng danh
    // sách một nẻo.
    db.createFunction(
      functionName: 'khong_dau',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      directOnly: false,
      function: (args) => normalizeForSearch(args.first?.toString()),
    );

    final instance = AppDatabase._(db, path);
    instance._migrate();
    return instance;
  }

  void dispose() => db.dispose();

  void _migrate() {
    final version = db.select('PRAGMA user_version;').first.values.first as int;
    if (version < 1) {
      _createV1();
      db.execute('PRAGMA user_version = 1;');
    }
    if (version < 2) {
      _createV2();
      db.execute('PRAGMA user_version = 2;');
    }
    if (version < 3) {
      _createV3();
      db.execute('PRAGMA user_version = 3;');
    }
    if (version < 4) {
      _createV4();
      db.execute('PRAGMA user_version = 4;');
    }
    if (version < 5) {
      _createV5();
      db.execute('PRAGMA user_version = 5;');
    }
    if (version < 6) {
      _createV6();
      db.execute('PRAGMA user_version = 6;');
    }
    if (version < 7) {
      _createV7();
      db.execute('PRAGMA user_version = 7;');
    }
  }

  /// Phiên bản 7: định mức chi phí theo đ/kg cho từng loại hàng.
  ///
  /// Bán một ký trấu thì tốn bao nhiêu mới ra được ký đó — tiền mua nguyên
  /// liệu, điện, xe, công. Mỗi lần bán chép lại bảng chi phí lúc đó vào giao
  /// dịch, để sửa định mức hôm nay không làm đổi lãi của lần bán tháng trước.
  void _createV7() {
    for (final sql in [
      'ALTER TABLE goods_types ADD COLUMN cost_items TEXT',
      'ALTER TABLE giao_dich ADD COLUMN cost_items TEXT',
    ]) {
      try {
        db.execute(sql);
      } on SqliteException {
        // Cột đã có sẵn (cơ sở dữ liệu dựng mới bằng lược đồ mới nhất).
      }
    }
  }

  /// Phiên bản 6: sổ mua bán, chỉ chủ mới xem được.
  ///
  /// Bảng này **không nằm trong luồng đồng bộ**: giá mua vào là dữ liệu nhạy
  /// cảm nhất, để nó đi xuống máy ở kho là mỗi kho có một bản sao. Vì vậy sổ
  /// mua bán chỉ sống trên máy chủ trung tâm.
  void _createV6() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS giao_dich (
        id TEXT PRIMARY KEY,
        date INTEGER NOT NULL,
        kind TEXT NOT NULL,
        goods_type_id TEXT,
        goods_name TEXT NOT NULL DEFAULT '',
        partner_id TEXT,
        partner_name TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'kg',
        unit_price REAL NOT NULL DEFAULT 0,
        amount REAL NOT NULL DEFAULT 0,
        has_invoice INTEGER NOT NULL DEFAULT 0,
        invoice_no TEXT,
        note TEXT,
        created_by TEXT,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_giao_dich_ngay ON giao_dich(date);');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_giao_dich_hoa_don ON giao_dich(has_invoice, date);');

    try {
      db.execute('ALTER TABLE nguoi_dung ADD COLUMN is_owner INTEGER NOT NULL DEFAULT 0');
    } on SqliteException {
      // Cột đã có sẵn (cơ sở dữ liệu dựng mới bằng lược đồ mới nhất).
    }

    // Cơ sở dữ liệu đã chạy trước khi có cờ này: tài khoản người thật cũ nhất
    // chính là tài khoản chủ lập lúc cài máy, gắn cờ cho nó.
    db.execute('''
      UPDATE nguoi_dung SET is_owner = 1
      WHERE id = (
        SELECT id FROM nguoi_dung
        WHERE machine_account = 0 AND deleted = 0
        ORDER BY updated_at LIMIT 1
      ) AND NOT EXISTS (SELECT 1 FROM nguoi_dung WHERE is_owner = 1);
    ''');
  }

  /// Phiên bản 5: nghỉ theo giờ trong ngày.
  ///
  /// Giai đoạn lương khai giờ vào ca, giờ tan ca và giờ nghỉ giữa ca; mỗi ngày
  /// chấm công ghi số giờ nghỉ và chép lại giờ chuẩn lúc chấm, để đổi giờ làm
  /// hôm nay không làm đổi công của tháng trước.
  void _createV5() {
    for (final sql in [
      "ALTER TABLE giai_doan_luong ADD COLUMN work_start TEXT NOT NULL DEFAULT '07:00'",
      "ALTER TABLE giai_doan_luong ADD COLUMN work_end TEXT NOT NULL DEFAULT '17:00'",
      'ALTER TABLE giai_doan_luong ADD COLUMN break_hours REAL NOT NULL DEFAULT 1.5',
      'ALTER TABLE cham_cong ADD COLUMN hours_off REAL NOT NULL DEFAULT 0',
      'ALTER TABLE cham_cong ADD COLUMN standard_hours REAL NOT NULL DEFAULT 8.5',
    ]) {
      try {
        db.execute(sql);
      } on SqliteException {
        // Cột đã có sẵn (cơ sở dữ liệu dựng mới bằng lược đồ mới nhất).
      }
    }
  }

  /// Phiên bản 4: người trong đoàn chuyển kho được tuỳ thời điểm.
  ///
  /// Đoàn không còn thuộc về một kho — cột `doan.station_code` giữ lại cho dữ
  /// liệu cũ đọc được nhưng không dùng nữa. Kho giờ là thuộc tính của từng
  /// người, và mỗi ngày chấm công chép lại kho tại thời điểm đó để chuyển kho
  /// hôm nay không làm đổi số liệu tháng trước.
  void _createV4() {
    for (final sql in [
      'ALTER TABLE nhan_vien ADD COLUMN station_code TEXT',
      'ALTER TABLE cham_cong ADD COLUMN station_code TEXT',
    ]) {
      try {
        db.execute(sql);
      } on SqliteException {
        // Cột đã có sẵn (cơ sở dữ liệu dựng mới bằng lược đồ mới nhất).
      }
    }
    db.execute('CREATE INDEX IF NOT EXISTS idx_cham_cong_kho ON cham_cong(station_code, date);');
  }

  /// Phiên bản 3: module chấm công và tính lương mùa vụ.
  ///
  /// Mọi bảng đều gắn với một đoàn, và đoàn thì thuộc về một kho — nhờ vậy phân
  /// quyền theo kho của phần cân xe dùng lại được nguyên vẹn cho phần này.
  void _createV3() {
    // Đoàn = một mùa vụ tại một kho. Mỗi mùa lập đoàn mới với danh sách người
    // riêng; một người chỉ thuộc một đoàn.
    db.execute('''
      CREATE TABLE IF NOT EXISTS doan (
        id           TEXT PRIMARY KEY,
        name         TEXT NOT NULL,
        station_code TEXT NOT NULL,
        season       TEXT NOT NULL DEFAULT '',
        start_date   INTEGER,
        end_date     INTEGER,
        status       TEXT NOT NULL DEFAULT 'dang_dien_ra',
        note         TEXT,
        updated_at   INTEGER NOT NULL,
        deleted      INTEGER NOT NULL DEFAULT 0,
        dirty        INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doan_kho ON doan(station_code);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doan_updated ON doan(updated_at);');

    // Giai đoạn lương: đầu mùa, mùa rộ. Mốc chuyển khai bằng ngày nên một tháng
    // vắt qua hai giai đoạn vẫn tính đúng.
    db.execute('''
      CREATE TABLE IF NOT EXISTS giai_doan_luong (
        id         TEXT PRIMARY KEY,
        crew_id    TEXT NOT NULL,
        name       TEXT NOT NULL,
        from_date  INTEGER NOT NULL,
        to_date    INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted    INTEGER NOT NULL DEFAULT 0,
        dirty      INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_giai_doan_doan ON giai_doan_luong(crew_id);');

    // Mức lương dùng chung, ví dụ "Thợ chính". Nhiều người hưởng cùng một mức.
    db.execute('''
      CREATE TABLE IF NOT EXISTS muc_luong (
        id         TEXT PRIMARY KEY,
        crew_id    TEXT NOT NULL,
        name       TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        deleted    INTEGER NOT NULL DEFAULT 0,
        dirty      INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_muc_luong_doan ON muc_luong(crew_id);');

    // Tiền một tháng của (mức lương × giai đoạn). Đặt riêng cho một người thì
    // worker_id có giá trị và band_id để trống.
    db.execute('''
      CREATE TABLE IF NOT EXISTS gia_luong (
        id             TEXT PRIMARY KEY,
        crew_id        TEXT NOT NULL,
        phase_id       TEXT NOT NULL,
        band_id        TEXT,
        worker_id      TEXT,
        monthly_amount REAL NOT NULL DEFAULT 0,
        updated_at     INTEGER NOT NULL,
        deleted        INTEGER NOT NULL DEFAULT 0,
        dirty          INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_gia_luong_doan ON gia_luong(crew_id);');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gia_luong_tra ON gia_luong(phase_id, band_id, worker_id);',
    );

    db.execute('''
      CREATE TABLE IF NOT EXISTS nhan_vien (
        id           TEXT PRIMARY KEY,
        crew_id      TEXT NOT NULL,
        name         TEXT NOT NULL,
        phone        TEXT,
        station_code TEXT,
        band_id    TEXT,
        join_date  INTEGER,
        leave_date INTEGER,
        status     TEXT NOT NULL DEFAULT 'dang_lam',
        note       TEXT,
        updated_at INTEGER NOT NULL,
        deleted    INTEGER NOT NULL DEFAULT 0,
        dirty      INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_nhan_vien_doan ON nhan_vien(crew_id, status);');

    // Chấm công theo ngày. Mỗi dòng lưu kèm mức lương tháng và số ngày của
    // tháng tại thời điểm chấm, để sửa bảng giá sau này không làm lương tháng
    // trước tự nhảy.
    db.execute('''
      CREATE TABLE IF NOT EXISTS cham_cong (
        id             TEXT PRIMARY KEY,
        crew_id        TEXT NOT NULL,
        worker_id      TEXT NOT NULL,
        date           INTEGER NOT NULL,
        present        INTEGER NOT NULL DEFAULT 1,
        phase_id       TEXT,
        station_code   TEXT,
        monthly_amount REAL NOT NULL DEFAULT 0,
        days_in_month  INTEGER NOT NULL DEFAULT 30,
        note           TEXT,
        created_by     TEXT,
        updated_at     INTEGER NOT NULL,
        deleted        INTEGER NOT NULL DEFAULT 0,
        dirty          INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_cham_cong_nguoi ON cham_cong(worker_id, date);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_cham_cong_doan ON cham_cong(crew_id, date);');
    // Một người một ngày chỉ được một bản ghi: chấm hai lần cùng ngày là tính
    // công gấp đôi mà không ai nhìn ra.
    db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_cham_cong_ngay '
      'ON cham_cong(worker_id, date) WHERE deleted = 0;',
    );

    // Sổ tiền chung: ứng lương, tăng ca, phụ cấp, trừ tiền, thanh toán.
    db.execute('''
      CREATE TABLE IF NOT EXISTS so_tien (
        id              TEXT PRIMARY KEY,
        crew_id         TEXT NOT NULL,
        worker_id       TEXT NOT NULL,
        type            TEXT NOT NULL,
        amount          REAL NOT NULL DEFAULT 0,
        date            INTEGER NOT NULL,
        note            TEXT,
        over_cap_reason TEXT,
        created_by      TEXT,
        updated_at      INTEGER NOT NULL,
        deleted         INTEGER NOT NULL DEFAULT 0,
        dirty           INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_so_tien_nguoi ON so_tien(worker_id, date);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_so_tien_doan ON so_tien(crew_id, type);');
  }

  /// Phiên bản 2: thêm tài khoản đăng nhập.
  ///
  /// Chạy được trên cơ sở dữ liệu đã có sẵn dữ liệu thật, chỉ thêm bảng mới nên
  /// phiếu cân và danh mục hiện có không bị đụng tới.
  void _createV2() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS nguoi_dung (
        id              TEXT PRIMARY KEY,
        username        TEXT NOT NULL,
        full_name       TEXT NOT NULL DEFAULT '',
        role            TEXT NOT NULL DEFAULT 'tram',
        station_scope   TEXT NOT NULL DEFAULT '',
        active          INTEGER NOT NULL DEFAULT 1,
        machine_account INTEGER NOT NULL DEFAULT 0,
        password_hash   TEXT NOT NULL DEFAULT '',
        salt            TEXT NOT NULL DEFAULT '',
        iterations      INTEGER NOT NULL DEFAULT 0,
        updated_at      INTEGER NOT NULL,
        deleted         INTEGER NOT NULL DEFAULT 0,
        dirty           INTEGER NOT NULL DEFAULT 1
      );
    ''');
    // Tên đăng nhập phải là duy nhất trong số tài khoản còn hiệu lực. Không đặt
    // UNIQUE thẳng trên cột vì tài khoản đã xoá vẫn nằm lại để đồng bộ.
    db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_nguoi_dung_username '
      'ON nguoi_dung(username) WHERE deleted = 0;',
    );
    db.execute('CREATE INDEX IF NOT EXISTS idx_nguoi_dung_updated ON nguoi_dung(updated_at);');
  }

  void _createV1() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id          TEXT PRIMARY KEY,
        code        TEXT NOT NULL DEFAULT '',
        name        TEXT NOT NULL,
        phone       TEXT,
        address     TEXT,
        tax_code    TEXT,
        note        TEXT,
        active      INTEGER NOT NULL DEFAULT 1,
        updated_at  INTEGER NOT NULL,
        deleted     INTEGER NOT NULL DEFAULT 0,
        dirty       INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_customers_updated ON customers(updated_at);');

    db.execute('''
      CREATE TABLE IF NOT EXISTS vehicles (
        id           TEXT PRIMARY KEY,
        plate_no     TEXT NOT NULL,
        customer_id  TEXT,
        driver_name  TEXT,
        driver_phone TEXT,
        tare_weight  REAL,
        note         TEXT,
        active       INTEGER NOT NULL DEFAULT 1,
        updated_at   INTEGER NOT NULL,
        deleted      INTEGER NOT NULL DEFAULT 0,
        dirty        INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_vehicles_plate ON vehicles(plate_no);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_vehicles_updated ON vehicles(updated_at);');

    db.execute('''
      CREATE TABLE IF NOT EXISTS goods_types (
        id                  TEXT PRIMARY KEY,
        code                TEXT NOT NULL,
        name                TEXT NOT NULL,
        unit                TEXT NOT NULL DEFAULT 'kg',
        default_yield_ratio REAL NOT NULL DEFAULT 100,
        sort_order          INTEGER NOT NULL DEFAULT 0,
        active              INTEGER NOT NULL DEFAULT 1,
        updated_at          INTEGER NOT NULL,
        deleted             INTEGER NOT NULL DEFAULT 0,
        dirty               INTEGER NOT NULL DEFAULT 1
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS stations (
        code            TEXT PRIMARY KEY,
        name            TEXT NOT NULL,
        warehouse_name  TEXT,
        address         TEXT,
        base_url        TEXT,
        online          INTEGER NOT NULL DEFAULT 0,
        last_seen_at    INTEGER,
        scale_connected INTEGER NOT NULL DEFAULT 0,
        scale_port      TEXT,
        updated_at      INTEGER NOT NULL,
        deleted         INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS tickets (
        id               TEXT PRIMARY KEY,
        ticket_no        TEXT NOT NULL,
        station_code     TEXT NOT NULL,
        direction        TEXT NOT NULL DEFAULT 'nhap',
        status           TEXT NOT NULL DEFAULT 'cho_lan_2',
        customer_id      TEXT,
        customer_name    TEXT NOT NULL DEFAULT '',
        vehicle_id       TEXT,
        plate_no         TEXT NOT NULL DEFAULT '',
        driver_name      TEXT,
        goods_type_id    TEXT,
        goods_name       TEXT NOT NULL DEFAULT '',
        yield_ratio      REAL NOT NULL DEFAULT 100,
        first_weight     REAL,
        first_weight_at  INTEGER,
        second_weight    REAL,
        second_weight_at INTEGER,
        net_weight       REAL NOT NULL DEFAULT 0,
        product_weight   REAL NOT NULL DEFAULT 0,
        note             TEXT,
        created_by       TEXT,
        created_at       INTEGER NOT NULL,
        updated_at       INTEGER NOT NULL,
        deleted          INTEGER NOT NULL DEFAULT 0,
        dirty            INTEGER NOT NULL DEFAULT 1
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_station ON tickets(station_code, created_at DESC);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_plate ON tickets(plate_no);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tickets_updated ON tickets(updated_at);');
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_tickets_no ON tickets(station_code, ticket_no);');

    // Bộ đếm số phiếu theo từng trạm + từng ngày, đảm bảo số phiếu không trùng
    // ngay cả khi nhiều máy trong cùng kho cùng lập phiếu.
    db.execute('''
      CREATE TABLE IF NOT EXISTS ticket_counters (
        station_code TEXT NOT NULL,
        day          TEXT NOT NULL,
        seq          INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (station_code, day)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        key   TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }
}
