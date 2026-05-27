import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'app_colors.dart';

const Loggers _logger = Loggers(name: '主题');

ThemeMetrics appMetrics = AppTheme.metrics;

class AppTheme {
  AppTheme._();

  static ThemeMode themeMode = ThemeMode.system;

  // ── 响应式主题状态（ThemeSettingsTab 写入，MyApp.build 读取）──────────────
  static final Rx<ThemeMode> themeModeObs = ThemeMode.system.obs;
  static final Rx<Color> accentColorObs = LightColors.primary.obs;
  static final RxDouble fontScaleObs = 1.0.obs;

  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _fontScaleKey = 'font_scale';

  /// 启动时从持久化存储加载主题配置（仅加载输入参数，不触发 ScreenUtil）。
  static Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIdx = (prefs.getInt(_themeModeKey) ?? ThemeMode.system.index).clamp(
        0,
        ThemeMode.values.length - 1,
      );
      themeModeObs.value = ThemeMode.values[modeIdx];
      final accentValue = prefs.getInt(_accentColorKey);
      if (accentValue != null) accentColorObs.value = Color(accentValue);
      fontScaleObs.value = (prefs.getDouble(_fontScaleKey) ?? 1.0).clamp(0.5, 2.0);
    } catch (_) {}
  }

  /// 根据当前 accent 和 fontScale 构建亮色主题（须在 ScreenUtil 初始化后调用）。
  static ThemeData buildCustomLight(Color accent, double fontScale) =>
      _applyCustomization(lightTheme, accent, fontScale);

  /// 根据当前 accent 和 fontScale 构建暗色主题（须在 ScreenUtil 初始化后调用）。
  static ThemeData buildCustomDark(Color accent, double fontScale) =>
      _applyCustomization(darkTheme, accent, fontScale);

  static ThemeData _applyCustomization(ThemeData base, Color accent, double scale) {
    final scaledText = _scaleTextTheme(base.textTheme, scale);
    final scaledPrimary = _scaleTextTheme(base.primaryTextTheme, scale);
    final cs = base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      onPrimary: _contrastColor(accent),
    );
    return base.copyWith(
      colorScheme: cs,
      primaryColor: accent,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        indicator: UnderlineTabIndicator(borderSide: BorderSide(color: accent, width: 3)),
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.55),
      ),
      textTheme: scaledText,
      primaryTextTheme: scaledPrimary,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _contrastColor(accent),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(thumbColor: accent, activeTrackColor: accent),
    );
  }

  static TextTheme _scaleTextTheme(TextTheme t, double scale) {
    return t.copyWith(
      displayLarge: _scaleStyle(t.displayLarge, scale),
      displayMedium: _scaleStyle(t.displayMedium, scale),
      displaySmall: _scaleStyle(t.displaySmall, scale),
      headlineLarge: _scaleStyle(t.headlineLarge, scale),
      headlineMedium: _scaleStyle(t.headlineMedium, scale),
      headlineSmall: _scaleStyle(t.headlineSmall, scale),
      titleLarge: _scaleStyle(t.titleLarge, scale),
      titleMedium: _scaleStyle(t.titleMedium, scale),
      titleSmall: _scaleStyle(t.titleSmall, scale),
      bodyLarge: _scaleStyle(t.bodyLarge, scale),
      bodyMedium: _scaleStyle(t.bodyMedium, scale),
      bodySmall: _scaleStyle(t.bodySmall, scale),
      labelLarge: _scaleStyle(t.labelLarge, scale),
      labelMedium: _scaleStyle(t.labelMedium, scale),
      labelSmall: _scaleStyle(t.labelSmall, scale),
    );
  }

  static TextStyle? _scaleStyle(TextStyle? s, double scale) {
    if (s?.fontSize == null) return s;
    return s!.copyWith(fontSize: s.fontSize! * scale);
  }

  static Color _contrastColor(Color c) => c.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  static ThemeMetrics metrics = ThemeMetrics();
  static RxInt metricsVersion = 0.obs;

  /// 亮色主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: LightColors.primary,
      scaffoldBackgroundColor: LightColors.background3,
      fontFamily: 'FZLanTingYuanS-EB-GB',

      // 颜色方案
      colorScheme: const ColorScheme.light(
        primary: LightColors.primary,
        secondary: LightColors.purple,
        tertiary: LightColors.overlayLight,
        surface: LightColors.background1,
        error: LightColors.red,
        onPrimary: LightColors.white100,
        onSecondary: LightColors.white100,
        onSurface: LightColors.black100,
        onError: LightColors.white100,
        outlineVariant: LightColors.black1,
      ),

      // 应用栏主题
      appBarTheme: AppBarTheme(
        backgroundColor: LightColors.background1,
        foregroundColor: LightColors.black100,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: scaleS(18),
          fontWeight: FontWeight.w600,
          color: LightColors.black100,
          height: 1.4,
        ),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: LightColors.background1,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: metrics.radius12,
          side: BorderSide(color: LightColors.white80, width: scaleW(0.5)),
        ),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: scaleS(72),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          fontSize: scaleS(48),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
        ),
        displaySmall: TextStyle(
          fontSize: scaleS(36),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.3,
        ),
        headlineLarge: TextStyle(
          fontSize: scaleS(28),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.3,
        ),
        headlineMedium: TextStyle(
          fontSize: scaleS(22),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.4,
        ),
        headlineSmall: TextStyle(
          fontSize: scaleS(18),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          fontSize: scaleS(15),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.5,
        ),
        titleMedium: TextStyle(
          fontSize: scaleS(13),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.5,
        ),
        bodyLarge: TextStyle(
          fontSize: scaleS(15),
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: scaleS(13),
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: scaleS(11),
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: scaleS(13),
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          fontSize: scaleS(11),
          fontWeight: FontWeight.w500,
          color: LightColors.black40,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: scaleS(9),
          fontWeight: FontWeight.w500,
          color: LightColors.black40,
          height: 1.5,
          letterSpacing: 1.5,
        ),
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LightColors.primary,
          foregroundColor: LightColors.white100,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace24, vertical: metrics.kSpace12),
          shape: RoundedRectangleBorder(borderRadius: metrics.radius8),
          textStyle: TextStyle(
            fontSize: scaleS(13),
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // 文本按钮主题
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LightColors.primary,
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16, vertical: metrics.kSpace8),
          textStyle: TextStyle(
            fontSize: scaleS(13),
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: LightColors.background2,
        border: OutlineInputBorder(borderRadius: metrics.radius8, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: const BorderSide(color: LightColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: const BorderSide(color: LightColors.red, width: 1),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.kSpace16,
          vertical: metrics.kSpace12,
        ),
      ),

      // 图标主题
      iconTheme: const IconThemeData(color: LightColors.black80, size: 24),

      // 分割线主题
      dividerTheme: DividerThemeData(color: LightColors.black10, thickness: scaleW(0.5), space: 1),

      hintColor: LightColors.black40,

      dividerColor: LightColors.black10,
    );
  }

  /// 暗色主题
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: DarkColors.primary,
      scaffoldBackgroundColor: DarkColors.background1,
      fontFamily: 'FZLanTingYuanS-EB-GB',

      // 颜色方案
      colorScheme: const ColorScheme.dark(
        primary: DarkColors.primary,
        secondary: DarkColors.purple,
        surface: DarkColors.background1,
        error: DarkColors.red,
        onPrimary: DarkColors.black100,
        onSecondary: DarkColors.black100,
        onSurface: DarkColors.white100,
        onError: DarkColors.black100,
      ),

      // 应用栏主题
      appBarTheme: AppBarTheme(
        backgroundColor: DarkColors.background1,
        foregroundColor: DarkColors.white100,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: scaleS(18),
          fontWeight: FontWeight.w600,
          color: DarkColors.white100,
          height: 1.4,
        ),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: DarkColors.background2,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: metrics.radius12,
          side: BorderSide(color: DarkColors.white80, width: scaleW(0.5)),
        ),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: scaleS(72), color: DarkColors.white100, height: 1.2),
        displayMedium: TextStyle(fontSize: scaleS(48), color: DarkColors.white100, height: 1.2),
        displaySmall: TextStyle(fontSize: scaleS(36), color: DarkColors.white100, height: 1.3),
        headlineLarge: TextStyle(fontSize: scaleS(28), color: DarkColors.white100, height: 1.3),
        headlineMedium: TextStyle(fontSize: scaleS(22), color: DarkColors.white100, height: 1.4),
        headlineSmall: TextStyle(fontSize: scaleS(18), color: DarkColors.white100, height: 1.4),
        titleLarge: TextStyle(fontSize: scaleS(15), color: DarkColors.white100, height: 1.5),
        titleMedium: TextStyle(fontSize: scaleS(13), color: DarkColors.white100, height: 1.5),
        bodyLarge: TextStyle(fontSize: scaleS(15), color: DarkColors.white80, height: 1.5),
        bodyMedium: TextStyle(fontSize: scaleS(13), color: DarkColors.white80, height: 1.5),
        bodySmall: TextStyle(fontSize: scaleS(11), color: DarkColors.white80, height: 1.5),
        labelLarge: TextStyle(
          fontSize: scaleS(13),
          color: DarkColors.white100,
          height: 1.2,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(fontSize: scaleS(11), color: DarkColors.white40, height: 1.4),
        labelSmall: TextStyle(
          fontSize: scaleS(9),
          color: DarkColors.white40,
          height: 1.5,
          letterSpacing: 1.5,
        ),
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primary,
          foregroundColor: DarkColors.black100,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace24, vertical: metrics.kSpace12),
          shape: RoundedRectangleBorder(borderRadius: metrics.radius8),
          textStyle: TextStyle(
            fontSize: scaleS(13),
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // 文本按钮主题
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DarkColors.primary,
          padding: EdgeInsets.symmetric(horizontal: metrics.kSpace16, vertical: metrics.kSpace8),
          textStyle: TextStyle(
            fontSize: scaleS(13),
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DarkColors.background2,
        border: OutlineInputBorder(borderRadius: metrics.radius8, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: const BorderSide(color: DarkColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: metrics.radius8,
          borderSide: const BorderSide(color: DarkColors.red, width: 1),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: metrics.kSpace16,
          vertical: metrics.kSpace12,
        ),
      ),

      // 图标主题
      iconTheme: const IconThemeData(color: DarkColors.white80, size: 24),

      // 分割线主题
      dividerTheme: const DividerThemeData(color: DarkColors.white10, thickness: 1, space: 1),

      hintColor: DarkColors.white40,
    );
  }

  static bool isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  static LinearGradient sideBarTheme(BuildContext context, {int alpha = 255}) {
    return LinearGradient(
      colors: isLight(context)
          ? [const Color(0xFFF8F9FB).withAlpha(alpha), const Color(0xFFF8F9FB).withAlpha(alpha)]
          : [const Color(0xFF20201E).withAlpha(alpha), const Color(0xFF1F1F1D).withAlpha(alpha)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  static void resetMetrics() {
    _logger.info('[主题] 重新计算界面尺寸中...');
    metrics = ThemeMetrics();
    metricsVersion.value++;
  }
}

class ThemeMetrics {
  final BorderRadius radius2;
  final BorderRadius radius3;
  final BorderRadius radius4;
  final BorderRadius radius6;
  final BorderRadius radius8;
  final BorderRadius radius10;
  final BorderRadius radius12;
  final BorderRadius radius14;
  final BorderRadius radius16;
  final BorderRadius radius18;
  final BorderRadius radius20;
  final BorderRadius radius22;
  final BorderRadius radius24;
  final BorderRadius radius25;
  final BorderRadius radius32;
  final BorderRadius radius100;
  final BorderRadius radius999;

  final double fontSize9;
  final double fontSize10;
  final double fontSize11;
  final double fontSize12;
  final double fontSize13;
  final double fontSize15;
  final double fontSize18;
  final double fontSize20;
  final double fontSize22;
  final double fontSize28;
  final double fontSize36;
  final double fontSize48;
  final double fontSize72;

  final double kSpace1;
  final double kSpace2;
  final double kSpace3;
  final double kSpace4;
  final double kSpace5;
  final double kSpace6;
  final double kSpace8;
  final double kSpace10;
  final double kSpace12;
  final double kSpace14;
  final double kSpace16;
  final double kSpace18;
  final double kSpace20;
  final double kSpace24;
  final double kSpace32;
  final double kSpace40;
  final double kSpace44;
  final double kSpace48;
  final double kSpace80;

  // Padding aliases
  double get paddingSmall => kSpace8;
  double get paddingMedium => kSpace16;
  double get paddingLarge => kSpace24;
  double get paddingXLarge => kSpace32;

  // Spacing aliases
  double get spacingSmall => kSpace8;
  double get spacingMedium => kSpace16;
  double get spacingLarge => kSpace24;
  double get spacingXLarge => kSpace32;

  final double iconSize12;
  final double iconSize13;
  final double iconSize14;
  final double iconSize15;
  final double iconSize16;
  final double iconSize18;
  final double iconSize20;
  final double iconSize22;
  final double iconSize24;
  final double iconSize28;
  final double iconSize32;
  final double iconSize40;
  final double iconSize44;
  final double iconSize48;
  final double iconSize64;
  final double iconSize96;

  final BoxShadow boxShadow10;

  ThemeMetrics()
    : radius2 = BorderRadius.all(Radius.circular(scaleW(2.r))),
      radius3 = BorderRadius.all(Radius.circular(scaleW(3.r))),
      radius4 = BorderRadius.all(Radius.circular(scaleW(4.r))),
      radius6 = BorderRadius.all(Radius.circular(scaleW(6.r))),
      radius8 = BorderRadius.all(Radius.circular(scaleW(8.r))),
      radius10 = BorderRadius.all(Radius.circular(scaleW(10.r))),
      radius12 = BorderRadius.all(Radius.circular(scaleW(12.r))),
      radius14 = BorderRadius.all(Radius.circular(scaleW(14.r))),
      radius16 = BorderRadius.all(Radius.circular(scaleW(16.r))),
      radius18 = BorderRadius.all(Radius.circular(scaleW(18.r))),
      radius20 = BorderRadius.all(Radius.circular(scaleW(20.r))),
      radius22 = BorderRadius.all(Radius.circular(scaleW(22.r))),
      radius24 = BorderRadius.all(Radius.circular(scaleW(24.r))),
      radius25 = BorderRadius.all(Radius.circular(scaleW(25.r))),
      radius32 = BorderRadius.all(Radius.circular(scaleW(32.r))),
      radius100 = BorderRadius.all(Radius.circular(scaleW(100.r))),
      radius999 = BorderRadius.all(Radius.circular(scaleW(999.r))),

      iconSize12 = scaleSWithUserFont(12),
      iconSize13 = scaleSWithUserFont(13),
      iconSize14 = scaleSWithUserFont(14),
      iconSize15 = scaleSWithUserFont(15),
      iconSize16 = scaleSWithUserFont(16),
      iconSize18 = scaleSWithUserFont(18),
      iconSize20 = scaleSWithUserFont(20),
      iconSize22 = scaleSWithUserFont(22),
      iconSize24 = scaleSWithUserFont(24),
      iconSize28 = scaleSWithUserFont(28),
      iconSize32 = scaleSWithUserFont(32),
      iconSize40 = scaleSWithUserFont(40),
      iconSize44 = scaleSWithUserFont(44),
      iconSize48 = scaleSWithUserFont(48),
      iconSize64 = scaleSWithUserFont(64),
      iconSize96 = scaleSWithUserFont(96),

      fontSize9 = scaleSWithUserFont(9),
      fontSize10 = scaleSWithUserFont(10),
      fontSize11 = scaleSWithUserFont(11),
      fontSize12 = scaleSWithUserFont(12),
      fontSize13 = scaleSWithUserFont(13),
      fontSize15 = scaleSWithUserFont(15),
      fontSize18 = scaleSWithUserFont(18),
      fontSize20 = scaleSWithUserFont(20),
      fontSize22 = scaleSWithUserFont(22),
      fontSize28 = scaleSWithUserFont(28),
      fontSize36 = scaleSWithUserFont(36),
      fontSize48 = scaleSWithUserFont(48),
      fontSize72 = scaleSWithUserFont(72),

      kSpace1 = scaleW(1),
      kSpace2 = scaleW(2),
      kSpace3 = scaleW(3),
      kSpace4 = scaleW(4),
      kSpace5 = scaleW(5),
      kSpace6 = scaleW(6),
      kSpace8 = scaleW(8),
      kSpace10 = scaleW(10),
      kSpace12 = scaleW(12),
      kSpace14 = scaleW(14),
      kSpace16 = scaleW(16),
      kSpace18 = scaleW(18),
      kSpace20 = scaleW(20),
      kSpace24 = scaleW(24),
      kSpace32 = scaleW(32),
      kSpace40 = scaleW(40),
      kSpace44 = scaleW(44),
      kSpace48 = scaleW(48),
      kSpace80 = scaleW(80),

      boxShadow10 = (() {
        final ctx = navigatorKey.currentContext;
        final isDark = ctx != null && Theme.of(ctx).brightness == Brightness.dark;
        return BoxShadow(
          color: isDark ? DarkColors.black10 : LightColors.black10,
          blurRadius: scaleW(8),
          offset: Offset(0, scaleH(4)),
        );
      })();
}
