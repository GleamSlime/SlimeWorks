import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/main.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme extends AppThemeCommon {
  AppTheme._() : super._();

  static bool isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  static LinearGradient sideBarTheme(BuildContext context) {
    return LinearGradient(
      colors: isLight(context) ? [const Color(0xFFF8F9FB), const Color(0xFFF8F9FB)] : [const Color(0xFF20201E), const Color(0xFF1F1F1D)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }
}

/// 应用主题配置
class AppThemeCommon {
  AppThemeCommon._();

  /// 亮色主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: LightColors.primary,
      scaffoldBackgroundColor: LightColors.background1,
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
        titleTextStyle: AppTextStyles.h6(color: LightColors.black100, fontWeight: AppFontWeights.semiBold),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: LightColors.background1,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: AppTextStyles.h1(color: LightColors.black100),
        displayMedium: AppTextStyles.h2(color: LightColors.black100),
        displaySmall: AppTextStyles.h3(color: LightColors.black100),
        headlineLarge: AppTextStyles.h4(color: LightColors.black100),
        headlineMedium: AppTextStyles.h5(color: LightColors.black100),
        headlineSmall: AppTextStyles.h6(color: LightColors.black100),
        titleLarge: AppTextStyles.subtitle1(color: LightColors.black100),
        titleMedium: AppTextStyles.subtitle2(color: LightColors.black100),
        bodyLarge: AppTextStyles.body1(color: LightColors.black80),
        bodyMedium: AppTextStyles.body2(color: LightColors.black80),
        bodySmall: AppTextStyles.body3(color: LightColors.black80),
        labelLarge: AppTextStyles.button(color: LightColors.black100),
        labelMedium: AppTextStyles.caption(color: LightColors.black40),
        labelSmall: AppTextStyles.overline(color: LightColors.black40),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
      dividerTheme: DividerThemeData(color: LightColors.black10, thickness: 1, space: 1),

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
        titleTextStyle: AppTextStyles.h6(color: DarkColors.white100, fontWeight: AppFontWeights.semiBold),
      ),

      // 卡片主题
      cardTheme: CardThemeData(
        color: DarkColors.background2,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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

  static BorderRadius get radius4 => BorderRadius.all(Radius.circular(scaleW(4.r)));
  static BorderRadius get radius8 => BorderRadius.all(Radius.circular(scaleW(8.r)));
  static BorderRadius get radius12 => BorderRadius.all(Radius.circular(scaleW(12.r)));
  static BorderRadius get radius16 => BorderRadius.all(Radius.circular(scaleW(16.r)));
  static BorderRadius get radius24 => BorderRadius.all(Radius.circular(scaleW(24.r)));
  static BorderRadius get radius32 => BorderRadius.all(Radius.circular(scaleW(32.r)));

  static double get fontSize6 => scaleS(6);
  static double get fontSize8 => scaleS(8);
  static double get fontSize10 => scaleS(10);
  static double get fontSize12 => scaleS(12);
  static double get fontSize14 => scaleS(14);
  static double get fontSize16 => scaleS(16);
  static double get fontSize18 => scaleS(18);
  static double get fontSize20 => scaleS(20);
  static double get fontSize24 => scaleS(24);
  static double get fontSize34 => scaleS(34);
  static double get fontSize48 => scaleS(48);
  static double get fontSize60 => scaleS(60);
  static double get fontSize96 => scaleS(96);

  static double get kSpace2 => scaleW(2);
  static double get kSpace4 => scaleW(4);
  static double get kSpace8 => scaleW(8);
  static double get kSpace10 => scaleW(10);
  static double get kSpace12 => scaleW(12);
  static double get kSpace16 => scaleW(16);
  static double get kSpace20 => scaleW(20);
  static double get kSpace24 => scaleW(24);
  static double get kSpace32 => scaleW(32);
  static double get kSpace40 => scaleW(40);
  static double get kSpace48 => scaleW(48);

  static BoxShadow boxShadow10 = BoxShadow(
    color: Theme.of(navigatorKey.currentContext!).brightness == Brightness.dark ? DarkColors.black10 : LightColors.black10,
    blurRadius: scaleW(8),
    offset: Offset(0, scaleH(4)),
  );
}
