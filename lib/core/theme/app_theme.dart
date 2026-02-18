import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/main.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

ThemeMetrics appMetrics = AppTheme.metrics;

class AppTheme {
  AppTheme._();

  static ThemeMode themeMode = ThemeMode.system;

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
        centerTitle: false,
        titleTextStyle: AppTextStyles.h6(
          color: LightColors.black100,
          fontWeight: AppFontWeights.semiBold,
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
        displayLarge: AppTextStyles.h1(color: LightColors.black100, fontWeight: FontWeight.w500),
        displayMedium: AppTextStyles.h2(color: LightColors.black100, fontWeight: FontWeight.w500),
        displaySmall: AppTextStyles.h3(color: LightColors.black100, fontWeight: FontWeight.w500),
        headlineLarge: AppTextStyles.h4(color: LightColors.black100, fontWeight: FontWeight.w500),
        headlineMedium: AppTextStyles.h5(color: LightColors.black100, fontWeight: FontWeight.w500),
        headlineSmall: AppTextStyles.h6(color: LightColors.black100, fontWeight: FontWeight.w500),
        titleLarge: AppTextStyles.subtitle1(
          color: LightColors.black100,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: AppTextStyles.subtitle2(
          color: LightColors.black100,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: AppTextStyles.body1(color: LightColors.black80, fontWeight: FontWeight.w500),
        bodyMedium: AppTextStyles.body2(color: LightColors.black80, fontWeight: FontWeight.w500),
        bodySmall: AppTextStyles.body3(color: LightColors.black80, fontWeight: FontWeight.w500),
        labelLarge: AppTextStyles.button(color: LightColors.black100, fontWeight: FontWeight.w500),
        labelMedium: AppTextStyles.caption(color: LightColors.black40, fontWeight: FontWeight.w500),
        labelSmall: AppTextStyles.overline(color: LightColors.black40, fontWeight: FontWeight.w500),
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: LightColors.primary,
          foregroundColor: LightColors.white100,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: AppTextStyles.button(),
        ),
      ),

      // 文本按钮主题
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: LightColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTextStyles.button(),
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
        centerTitle: false,
        titleTextStyle: AppTextStyles.h6(
          color: DarkColors.white100,
          fontWeight: AppFontWeights.semiBold,
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
        displayLarge: AppTextStyles.h1(color: DarkColors.white100),
        displayMedium: AppTextStyles.h2(color: DarkColors.white100),
        displaySmall: AppTextStyles.h3(color: DarkColors.white100),
        headlineLarge: AppTextStyles.h4(color: DarkColors.white100),
        headlineMedium: AppTextStyles.h5(color: DarkColors.white100),
        headlineSmall: AppTextStyles.h6(color: DarkColors.white100),
        titleLarge: AppTextStyles.subtitle1(color: DarkColors.white100),
        titleMedium: AppTextStyles.subtitle2(color: DarkColors.white100),
        bodyLarge: AppTextStyles.body1(color: DarkColors.white80),
        bodyMedium: AppTextStyles.body2(color: DarkColors.white80),
        bodySmall: AppTextStyles.body3(color: DarkColors.white80),
        labelLarge: AppTextStyles.button(color: DarkColors.white100),
        labelMedium: AppTextStyles.caption(color: DarkColors.white40),
        labelSmall: AppTextStyles.overline(color: DarkColors.white40),
      ),
      // 按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.primary,
          foregroundColor: DarkColors.black100,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: AppTextStyles.button(),
        ),
      ),

      // 文本按钮主题
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DarkColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTextStyles.button(),
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

  static LinearGradient sideBarTheme(BuildContext context) {
    return LinearGradient(
      colors: isLight(context)
          ? [const Color(0xFFF8F9FB), const Color(0xFFF8F9FB)]
          : [const Color(0xFF20201E), const Color(0xFF1F1F1D)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  static void resetMetrics() {
    print("重新计算界面尺寸中...");
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

  final double fontSize6;
  final double fontSize8;
  final double fontSize10;
  final double fontSize12;
  final double fontSize14;
  final double fontSize16;
  final double fontSize18;
  final double fontSize20;
  final double fontSize24;
  final double fontSize34;
  final double fontSize48;
  final double fontSize60;
  final double fontSize96;

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

      fontSize6 = scaleS(6),
      fontSize8 = scaleS(8),
      fontSize10 = scaleS(10),
      fontSize12 = scaleS(12),
      fontSize14 = scaleS(14),
      fontSize16 = scaleS(16),
      fontSize18 = scaleS(18),
      fontSize20 = scaleS(20),
      fontSize24 = scaleS(24),
      fontSize34 = scaleS(34),
      fontSize48 = scaleS(48),
      fontSize60 = scaleS(60),
      fontSize96 = scaleS(96),

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
