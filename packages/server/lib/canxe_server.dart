/// Máy chủ cân xe — chạy được hai vai trò: trung tâm và trạm cân.
library canxe_server;

export 'src/api/api_router.dart' show ApiRouter, appVersion, authMiddleware, corsMiddleware;
export 'src/api/reading_broker.dart';
export 'src/auth/auth_service.dart';
export 'src/config.dart';
export 'src/console.dart';
export 'src/db/database.dart';
export 'src/db/payroll_repository.dart';
export 'src/db/repository.dart';
export 'src/logging.dart';
export 'src/scale/scale_service.dart';
export 'src/scale/win32_serial.dart' show listSerialPorts, SerialPortException, Win32SerialPort;
export 'src/server_app.dart';
export 'src/service/payroll_service.dart';
export 'src/service/ticket_service.dart';
export 'src/sync/station_uplink.dart';
export 'src/sync/sync_worker.dart';
