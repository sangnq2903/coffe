import 'dart:ffi';
import 'dart:io';

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
