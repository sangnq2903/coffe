import 'package:flutter/material.dart';

/// Hệ thiết kế của app.
///
/// Ba nguyên tắc, đặt ra vì phần mềm này dùng ở kho chứ không phải để ngắm:
///
/// 1. **Phân cấp bằng độ đậm, không bằng khung.** Chữ có đúng ba cấp — tiêu đề,
///    nội dung, chú thích — và mỗi cấp khác hẳn nhau về cỡ lẫn màu. Trước đây
///    mọi dòng đều xám nhạt cỡ gần bằng nhau nên nhìn vào không biết đọc gì
///    trước.
/// 2. **Viền mảnh, không đổ bóng, ít bo góc.** Bóng đổ và bo góc lớn khắp nơi
///    làm mọi khối trông giống hệt nhau. Một đường viền 1px tách khối gọn hơn
///    mà không gây ồn.
/// 3. **Chạm được bằng ngón cái.** Mọi thứ bấm được đều cao tối thiểu
///    [minTouch]. Máy ở kho dùng chuột, nhưng ngoài vườn thì cầm điện thoại.
abstract final class AppTheme {
  // ------------------------------------------------------------------ màu

  /// Xanh rừng — màu chính, dùng cho hành động và trạng thái tốt.
  static const Color primary = Color(0xFF2D6A4F);
  static const Color primaryDark = Color(0xFF1F4D39);

  /// Nền nhạt của màu chính, cho mục đang chọn và vùng nhấn nhẹ.
  static const Color primarySoft = Color(0xFFE8F0EB);

  /// Cam đất — màu nhấn thứ hai, dành cho thứ cần chú ý nhưng chưa phải lỗi.
  static const Color accent = Color(0xFFC0561F);
  static const Color accentSoft = Color(0xFFFAEDE5);

  // Trạng thái. Đỏ và vàng đều ngả đất cho hợp tông, không dùng đỏ nguyên chất.
  static const Color stable = Color(0xFF2D6A4F);
  static const Color unstable = Color(0xFFB45309);
  static const Color offline = Color(0xFFA8321F);

  // Nền và bề mặt — trắng ngà ấm, không phải xám lam lạnh.
  static const Color canvas = Color(0xFFF7F6F2);
  static const Color surface = Colors.white;

  /// Nền phụ: hàng xen kẽ trong bảng, đầu bảng, ô nhập.
  static const Color surfaceAlt = Color(0xFFFBFAF7);

  static const Color line = Color(0xFFE5E2DA);
  static const Color lineStrong = Color(0xFFD2CEC3);

  /// Bảng số cân: gần đen nhưng ngả ấm, để số sáng nổi hẳn lên.
  static const Color panel = Color(0xFF16181A);
  static const Color panelEdge = Color(0xFF2A2D30);

  // Ba cấp chữ.
  static const Color text = Color(0xFF1B1A17);
  static const Color textSoft = Color(0xFF55534B);
  static const Color textMuted = Color(0xFF8B887E);

  // -------------------------------------------------------- kích thước chuẩn

  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 16;
  static const double gapLg = 24;

  /// Bo góc khối lớn (thẻ, hộp thoại) và khối nhỏ (nút, ô nhập).
  static const double radius = 8;
  static const double radiusSm = 6;

  /// Chiều cao tối thiểu của mọi thứ bấm được.
  static const double minTouch = 44;

  /// Bề rộng tối đa của cột nội dung trên màn hình rộng.
  ///
  /// Không giới hạn thì dòng chữ kéo dài cả mét, mắt phải quét ngang rất mệt.
  /// Bảng nhiều cột thì bỏ qua hằng số này và trải hết bề ngang.
  static const double contentMaxWidth = 1180;

  /// Từ bề rộng này trở lên coi là màn hình rộng (máy tính để bàn).
  static const double wideBreakpoint = 900;

  // ------------------------------------------------------------------- chữ

  /// Font riêng cho số: chữ hẹp nên bảng nhiều cột vẫn đọc được, và số cân
  /// nhìn ra dáng mặt đồng hồ đo chứ không lẫn vào chữ thường.
  static const String numericFont = 'RobotoCondensed';

  /// Cấp 1 — tiêu đề khối.
  static const TextStyle title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: text,
    height: 1.25,
  );

  /// Cấp 2 — nội dung chính, thứ người ta thực sự đọc.
  static const TextStyle body = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    color: text,
    height: 1.3,
  );

  /// Cấp 3 — chú thích, thông tin phụ.
  static const TextStyle meta = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    color: textMuted,
    height: 1.35,
  );

  /// Nhãn nhỏ in hoa phía trên một nhóm nội dung.
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: textMuted,
  );

  /// Kiểu chữ cho số: bảng số đều chiều rộng để chữ số không nhảy ngang khi
  /// giá trị thay đổi liên tục.
  static TextStyle digits(double size, {Color? color, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: numericFont,
        fontSize: size,
        fontWeight: weight,
        height: 1,
        letterSpacing: size > 40 ? -1.0 : 0,
        color: color ?? text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Số trong bảng và trong dòng danh sách — cỡ vừa, luôn thẳng cột.
  static TextStyle number(double size,
          {Color? color, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: numericFont,
        fontSize: size,
        fontWeight: weight,
        color: color ?? text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Giữ lại để mã cũ còn biên dịch được. Thiết kế mới không dùng bóng đổ:
  /// khối được tách bằng viền 1px, thêm bóng chỉ làm màn hình đục đi.
  static List<BoxShadow> get softShadow => const [];

  // ----------------------------------------------------------------- theme

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: surface,
      error: offline,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      visualDensity: VisualDensity.standard,
      // Gợn sóng mặc định của Material 3 loang rất chậm, bấm nhanh liên tục
      // (chấm công cả đoàn) nhìn thành vệt loang chồng nhau.
      splashFactory: InkRipple.splashFactory,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: text,
        displayColor: text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        shape: Border(bottom: BorderSide(color: line)),
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
        fillColor: surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: _inputBorder(line),
        enabledBorder: _inputBorder(line),
        focusedBorder: _inputBorder(primary, width: 1.8),
        errorBorder: _inputBorder(offline),
        focusedErrorBorder: _inputBorder(offline, width: 1.8),
        labelStyle: const TextStyle(color: textMuted, fontSize: 14),
        floatingLabelStyle: const TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        helperStyle: const TextStyle(fontSize: 11.5, color: textMuted, height: 1.3),
        helperMaxLines: 3,
        errorStyle: const TextStyle(fontSize: 11.5, color: offline, height: 1.3),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, minTouch),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, minTouch),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          side: const BorderSide(color: lineStrong),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, minTouch),
          foregroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouch, minTouch),
          foregroundColor: textSoft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: textSoft,
          selectedBackgroundColor: primary,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: lineStrong),
          minimumSize: const Size(0, minTouch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, space: 1, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        side: const BorderSide(color: lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        titleTextStyle: body,
        subtitleTextStyle: meta,
        iconColor: textMuted,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: line,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: line),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: panel,
        contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: primarySoft,
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected) ? primary : textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected) ? primary : textMuted,
          ),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        horizontalMargin: 12,
        columnSpacing: 16,
        dividerThickness: 1,
        headingTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textSoft,
        ),
        dataTextStyle: TextStyle(fontSize: 13.5, color: text),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        linearMinHeight: 2,
        color: primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : lineStrong),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
        side: const BorderSide(color: lineStrong, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// Cột nội dung của một trang.
///
/// Giới hạn bề rộng rồi căn giữa: không có nó thì trên màn hình 1440px một dòng
/// chữ kéo dài hết cỡ, mắt phải quét cả gang tay mới hết một dòng. Bảng nhiều
/// cột thì truyền [wide] để trải hết bề ngang.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.wide = false,
    this.padding,
  });

  final Widget child;
  final bool wide;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? double.infinity : AppTheme.contentMaxWidth,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppTheme.gapMd),
            child: child,
          ),
        ),
      );
}

/// Khung nội dung có tiêu đề — dùng lại cho mọi khối trên các màn hình.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.subtitle,
    this.padded = true,
    this.accentColor,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  /// Dòng phụ dưới tiêu đề, cho con số tổng hay lời giải thích ngắn.
  final String? subtitle;

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
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceAlt,
              border: Border(bottom: BorderSide(color: AppTheme.line)),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: accent),
                  const SizedBox(width: AppTheme.gapSm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: AppTheme.title, overflow: TextOverflow.ellipsis),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: AppTheme.meta, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(
            padding: padded ? const EdgeInsets.all(14) : EdgeInsets.zero,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Thông báo trống, thay cho khoảng trắng không giải thích gì.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;

  /// Nút gợi ý việc nên làm tiếp — màn hình trống mà không chỉ đường thì người
  /// dùng đứng lại ở đó.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.lineStrong),
            const SizedBox(height: AppTheme.gapMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSoft,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: AppTheme.gapMd),
              action!,
            ],
          ],
        ),
      );
}

/// Nhãn trạng thái — chữ nhỏ trên nền màu nhạt, không viền.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool compact;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 10,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 12 : 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 12,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
}

/// Một ô số liệu: nhãn nhỏ ở trên, con số lớn ở dưới.
///
/// Dùng cho các dải tổng đầu trang. Trước đây mỗi ô một kiểu — có ô nền đặc, ô
/// nền trắng — nhìn như đang nhấn mạnh ngẫu nhiên; giờ mọi ô giống nhau và chỉ
/// [tone] quyết định màu con số.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(label.toUpperCase(),
                      style: AppTheme.sectionLabel, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: AppTheme.number(21, color: tone ?? AppTheme.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Text(unit!,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted)),
                ],
              ],
            ),
          ],
        ),
      );
}

/// Dải cảnh báo trong trang: một câu giải thích kèm màu theo mức nghiêm trọng.
class NoticeBar extends StatelessWidget {
  const NoticeBar({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.action,
  });

  final IconData icon;
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          // Vạch màu bên trái đủ để nhận ra mức nghiêm trọng mà không cần viền
          // kín làm nặng màn hình.
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.text),
              ),
            ),
            if (action != null) ...[const SizedBox(width: AppTheme.gapSm), action!],
          ],
        ),
      );
}
