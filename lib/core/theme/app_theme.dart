import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'app_colors.dart';

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
      colorScheme: ColorScheme.light(
        primary: LightColors.primary,
        secondary: LightColors.purple,
        surface: LightColors.background1,
        error: LightColors.red,
        onPrimary: LightColors.white100,
        onSecondary: LightColors.white100,
        onSurface: LightColors.black100,
        onError: LightColors.white100,
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
          fontSize: 18.0,
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
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: LightColors.white80, width: scaleW(0.5)),
        ),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 72.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          fontSize: 48.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
        ),
        displaySmall: TextStyle(
          fontSize: 36.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.3,
        ),
        headlineLarge: TextStyle(
          fontSize: 28.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.3,
        ),
        headlineMedium: TextStyle(
          fontSize: 22.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.4,
        ),
        headlineSmall: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          fontSize: 15.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.5,
        ),
        titleMedium: TextStyle(
          fontSize: 13.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.5,
        ),
        bodyLarge: TextStyle(
          fontSize: 15.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 13.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black80,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontSize: 13.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black100,
          height: 1.2,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(
          fontSize: 11.0,
          fontWeight: FontWeight.w500,
          color: LightColors.black40,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 9.0,
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 13.0,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 13.0,
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: LightColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: LightColors.red, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // 图标主题
      iconTheme: IconThemeData(color: LightColors.black80, size: 24),

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
      colorScheme: ColorScheme.dark(
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
          fontSize: 18.0,
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
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: DarkColors.white80, width: scaleW(0.5)),
        ),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: TextStyle(fontSize: 72.0, color: DarkColors.white100, height: 1.2),
        displayMedium: TextStyle(fontSize: 48.0, color: DarkColors.white100, height: 1.2),
        displaySmall: TextStyle(fontSize: 36.0, color: DarkColors.white100, height: 1.3),
        headlineLarge: TextStyle(fontSize: 28.0, color: DarkColors.white100, height: 1.3),
        headlineMedium: TextStyle(fontSize: 22.0, color: DarkColors.white100, height: 1.4),
        headlineSmall: TextStyle(fontSize: 18.0, color: DarkColors.white100, height: 1.4),
        titleLarge: TextStyle(fontSize: 15.0, color: DarkColors.white100, height: 1.5),
        titleMedium: TextStyle(fontSize: 13.0, color: DarkColors.white100, height: 1.5),
        bodyLarge: TextStyle(fontSize: 15.0, color: DarkColors.white80, height: 1.5),
        bodyMedium: TextStyle(fontSize: 13.0, color: DarkColors.white80, height: 1.5),
        bodySmall: TextStyle(fontSize: 11.0, color: DarkColors.white80, height: 1.5),
        labelLarge: TextStyle(
          fontSize: 13.0,
          color: DarkColors.white100,
          height: 1.2,
          letterSpacing: 0.5,
        ),
        labelMedium: TextStyle(fontSize: 11.0, color: DarkColors.white40, height: 1.4),
        labelSmall: TextStyle(
          fontSize: 9.0,
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 13.0,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 13.0,
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: DarkColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: DarkColors.red, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // 图标主题
      iconTheme: IconThemeData(color: DarkColors.white80, size: 24),

      // 分割线主题
      dividerTheme: DividerThemeData(color: DarkColors.white10, thickness: 1, space: 1),

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
    debugPrint("重新计算界面尺寸中...");
    metrics = ThemeMetrics();
    metricsVersion.value++;
  }
}

class ThemeMetrics {
  final BorderRadius radius4;
  final BorderRadius radius8;
  final BorderRadius radius10;
  final BorderRadius radius12;
  final BorderRadius radius16;
  final BorderRadius radius18;
  final BorderRadius radius24;
  final BorderRadius radius32;

  final double fontSize9;
  final double fontSize11;
  final double fontSize13;
  final double fontSize15;
  final double fontSize18;
  final double fontSize22;
  final double fontSize28;
  final double fontSize36;
  final double fontSize48;
  final double fontSize72;

  final double kSpace2;
  final double kSpace4;
  final double kSpace8;
  final double kSpace10;
  final double kSpace12;
  final double kSpace16;
  final double kSpace20;
  final double kSpace24;
  final double kSpace32;
  final double kSpace40;
  final double kSpace44;
  final double kSpace48;

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

  final BoxShadow boxShadow10;

  ThemeMetrics()
    : radius4 = BorderRadius.all(Radius.circular(scaleW(4.r))),
      radius8 = BorderRadius.all(Radius.circular(scaleW(8.r))),
      radius10 = BorderRadius.all(Radius.circular(scaleW(10.r))),
      radius12 = BorderRadius.all(Radius.circular(scaleW(12.r))),
      radius16 = BorderRadius.all(Radius.circular(scaleW(16.r))),
      radius18 = BorderRadius.all(Radius.circular(scaleW(18.r))),
      radius24 = BorderRadius.all(Radius.circular(scaleW(24.r))),
      radius32 = BorderRadius.all(Radius.circular(scaleW(32.r))),

      fontSize9 = scaleS(9),
      fontSize11 = scaleS(11),
      fontSize13 = scaleS(13),
      fontSize15 = scaleS(15),
      fontSize18 = scaleS(18),
      fontSize22 = scaleS(22),
      fontSize28 = scaleS(28),
      fontSize36 = scaleS(36),
      fontSize48 = scaleS(48),
      fontSize72 = scaleS(72),

      kSpace2 = scaleW(2),
      kSpace4 = scaleW(4),
      kSpace8 = scaleW(8),
      kSpace10 = scaleW(10),
      kSpace12 = scaleW(12),
      kSpace16 = scaleW(16),
      kSpace20 = scaleW(20),
      kSpace24 = scaleW(24),
      kSpace32 = scaleW(32),
      kSpace40 = scaleW(40),
      kSpace44 = scaleW(44),
      kSpace48 = scaleW(48),

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
