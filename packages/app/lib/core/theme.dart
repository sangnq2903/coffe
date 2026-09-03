import 'package:flutter/material.dart';

/// Hệ thống thiết kế của app.
///
/// Màn hình cân đặt ở nhà kho: ánh sáng mạnh, người dùng đứng xa, thao tác
/// nhanh giữa lúc xe chờ. Vì vậy giao diện chọn nền sáng trung tính cho phần
/// nhập liệu (đỡ chói khi in phiếu, dễ đọc ban ngày) và một bảng số nền tối
/// tương phản cao cho số cân — thứ duy nhất cần nhìn thấy từ xa.
abstract final class AppTheme {
  // Màu chủ đạo
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF115E59);
  static const Color accent = Color(0xFFD97706);

  // Màu trạng thái
  static const Color stable = Color(0xFF16A34A);
  static const Color unstable = Color(0xFFF59E0B);
  static const Color offline = Color(0xFFDC2626);

  // Nền và bề mặt
  static const Color canvas = Color(0xFFF1F5F9);
  static const Color surface = Colors.white;
  static const Color panel = Color(0xFF0B1220);
  static const Color panelEdge = Color(0xFF1E293B);
  static const Color line = Color(0xFFE2E8F0);
  static const Color textMuted = Color(0xFF64748B);

  // Khoảng cách chuẩn — dùng thay cho số lẻ rải rác khắp nơi
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 16;
  static const double gapLg = 24;
  static const double radius = 14;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: surface,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(color: textMuted, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: primary, fontWeight: FontWeight.w600),
        helperStyle: const TextStyle(fontSize: 11.5, color: textMuted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: const BorderSide(color: line),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primary,
          selectedForegroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      listTileTheme: const ListTileThemeData(
        titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
        subtitleTextStyle: TextStyle(fontSize: 12.5, color: textMuted, height: 1.35),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }

  /// Kiểu chữ cho số cân: bảng số đều chiều rộng để chữ số không nhảy ngang khi
  /// giá trị thay đổi liên tục.
  static TextStyle digits(double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: 1,
        letterSpacing: -1.5,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Tiêu đề nhỏ phía trên mỗi nhóm nội dung.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.0,
    color: textMuted,
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ];
}

/// Khung nội dung có tiêu đề — dùng lại cho mọi khối trên các màn hình để bố
/// cục nhất quán, không mỗi chỗ một kiểu.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.padded = true,
    this.accentColor,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  /// Đặt `false` khi nội dung là danh sách tự quản lề của riêng nó.
  final bool padded;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppTheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.line),
        boxShadow: AppTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.line)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: AppTheme.gapSm),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: padded ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Thông báo trống, thay cho khoảng trắng không giải thích gì.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 34, color: AppTheme.line),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
            ),
          ],
        ),
      );
}

/// Nhãn trạng thái phiếu cân, dùng chung ở danh sách và ở phiếu chi tiết.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.compact = false});

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 3 : 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 11 : 12.5,
          ),
        ),
      );
}
