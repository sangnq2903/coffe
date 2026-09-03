import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nạp dữ liệu định dạng ngày tháng tiếng Việt trước khi vẽ khung hình đầu
  // tiên, nếu không các hàm format sẽ ném lỗi locale chưa khởi tạo.
  await initializeDateFormatting('vi_VN');
  final settings = await AppSettings.load();
  runApp(CanXeApp(settings: settings));
}
