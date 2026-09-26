import 'package:flutter/material.dart';

/// 设计令牌：色彩角色、圆角、阴影、字号、间距。
///
/// 数值为规范值，刻意不做窗口缩放——令牌样本必须所见即所定。
class DesignPalette {
  const DesignPalette({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.success,
    required this.successForeground,
    required this.warning,
    required this.warningForeground,
    required this.info,
    required this.infoForeground,
    required this.invert,
    required this.invertForeground,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarBorder,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
    required this.series,
  });

  final Brightness brightness;

  // 基底与文字
  final Color background;
  final Color foreground;

  // 三层容器：卡片 / 浮层
  final Color card;
  final Color cardForeground;
  final Color popover;
  final Color popoverForeground;

  // 反相主按钮
  final Color primary;
  final Color primaryForeground;

  // 次级与弱化面
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color accentForeground;

  // 破坏性操作
  final Color destructive;
  final Color destructiveForeground;

  // 描边与输入底
  final Color border;
  final Color input;

  /// 焦点环
  final Color ring;

  // 状态色族
  final Color success;
  final Color successForeground;
  final Color warning;
  final Color warningForeground;
  final Color info;
  final Color infoForeground;

  // 反转配色（tooltip / toast）
  final Color invert;
  final Color invertForeground;

  // 侧边栏独立一档，允许与主背景不同色相
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarBorder;

  /// 图表主色相：两套主题同色相、不同明度，保证同一序列换肤后不跳色
  final Color series;

  // 图表配色
  final Color chart1;
  final Color chart2;
  final Color chart3;
  final Color chart4;
  final Color chart5;

  static const DesignPalette light = DesignPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF0A0A0A),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0A0A0A),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF0A0A0A),
    primary: Color(0xFF171717),
    primaryForeground: Color(0xFFFAFAFA),
    secondary: Color(0xFFF5F5F5),
    secondaryForeground: Color(0xFF171717),
    muted: Color(0xFFF5F5F5),
    mutedForeground: Color(0xFF737373),
    accent: Color(0xFFF5F5F5),
    accentForeground: Color(0xFF171717),
    destructive: Color(0xFFE40014),
    destructiveForeground: Color(0xFF9F0712),
    border: Color(0xFFE5E5E5),
    input: Color(0xFFE5E5E5),
    ring: Color(0xFFA1A1A1),
    success: Color(0xFF00BB7F),
    successForeground: Color(0xFF004E3B),
    warning: Color(0xFFEDB200),
    warningForeground: Color(0xFF733E0A),
    info: Color(0xFF8D54FF),
    infoForeground: Color(0xFF4D179A),
    invert: Color(0xFF18181B),
    invertForeground: Color(0xFFFAFAFA),
    sidebar: Color(0xFFFAFAFA),
    sidebarForeground: Color(0xFF0A0A0A),
    sidebarPrimary: Color(0xFF171717),
    sidebarPrimaryForeground: Color(0xFFFAFAFA),
    sidebarAccent: Color(0xFFF5F5F5),
    sidebarBorder: Color(0xFFE5E5E5),
    chart1: Color(0xFFF05100),
    chart2: Color(0xFF009588),
    chart3: Color(0xFF104E64),
    chart4: Color(0xFFFCBB00),
    chart5: Color(0xFFF99C00),
    series: Color(0xFF0075FF),
  );

  static const DesignPalette dark = DesignPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0A0A0A),
    foreground: Color(0xFFFAFAFA),
    card: Color(0xFF171717),
    cardForeground: Color(0xFFFAFAFA),
    popover: Color(0xFF262626),
    popoverForeground: Color(0xFFFAFAFA),
    primary: Color(0xFFE5E5E5),
    primaryForeground: Color(0xFF171717),
    secondary: Color(0xFF262626),
    secondaryForeground: Color(0xFFFAFAFA),
    muted: Color(0xFF262626),
    mutedForeground: Color(0xFFA1A1A1),
    accent: Color(0xFF404040),
    accentForeground: Color(0xFFFAFAFA),
    destructive: Color(0xFFFF6568),
    destructiveForeground: Color(0xFFE40014),
    border: Color(0x1AFFFFFF),
    input: Color(0x26FFFFFF),
    ring: Color(0xFF737373),
    success: Color(0xFF00BB7F),
    successForeground: Color(0xFF009767),
    warning: Color(0xFFEDB200),
    warningForeground: Color(0xFFCD8900),
    info: Color(0xFF8D54FF),
    infoForeground: Color(0xFF7F22FE),
    invert: Color(0xFF3F3F46),
    invertForeground: Color(0xFFFAFAFA),
    sidebar: Color(0xFF171717),
    sidebarForeground: Color(0xFFFAFAFA),
    sidebarPrimary: Color(0xFF1447E6),
    sidebarPrimaryForeground: Color(0xFFFAFAFA),
    sidebarAccent: Color(0xFF262626),
    sidebarBorder: Color(0x1AFFFFFF),
    chart1: Color(0xFF1447E6),
    chart2: Color(0xFF00BB7F),
    chart3: Color(0xFFF99C00),
    chart4: Color(0xFFAC4BFF),
    chart5: Color(0xFFFF2357),
    series: Color(0xFF1447E6),
  );

  bool get isDark => brightness == Brightness.dark;

  /// 状态色的容器底与描边由主色派生
  Color container(Color base) => base.withValues(alpha: isDark ? 0.16 : 0.10);

  Color containerBorder(Color base) =>
      base.withValues(alpha: isDark ? 0.30 : 0.22);

  /// 悬停/按压的水洗层
  Color get hover => isDark ? const Color(0x14FFFFFF) : const Color(0x0A000000);

  Color get pressed =>
      isDark ? const Color(0x1FFFFFFF) : const Color(0x12000000);

  /// 骨架块
  Color get skeleton =>
      isDark ? const Color(0xFF282828) : const Color(0xFFF2F2F2);
}

class DesignRadius {
  DesignRadius._();

  static const double xs = 2;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 14;
  static const double xxl = 16;
  static const double xxxl = 24;
  static const double xxxxl = 32;
  static const double full = 9999;

  static BorderRadius br(double v) => BorderRadius.circular(v);
  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rXxl = BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius rXxxl = BorderRadius.all(Radius.circular(xxxl));
  static const BorderRadius rXxxxl = BorderRadius.all(Radius.circular(xxxxl));
  static const BorderRadius rFull = BorderRadius.all(Radius.circular(full));
}

class DesignShadow {
  DesignShadow._();

  static List<BoxShadow> of(DesignShadowLevel level, {required bool isDark}) {
    final spec = switch (level) {
      DesignShadowLevel.xs => const _Spec(1, 2, 0, 0.05),
      DesignShadowLevel.sm => const _Spec(1, 3, 0, 0.10),
      DesignShadowLevel.md => const _Spec(4, 6, -1, 0.10),
      DesignShadowLevel.lg => const _Spec(10, 15, -3, 0.10),
      DesignShadowLevel.xl => const _Spec(20, 25, -5, 0.10),
      DesignShadowLevel.xxl => const _Spec(25, 50, -12, 0.25),
    };
    final opacity = isDark ? spec.opacity * 2.2 : spec.opacity;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: opacity),
        blurRadius: spec.blur,
        offset: Offset(0, spec.y),
        spreadRadius: spec.spread,
      ),
      if (level != DesignShadowLevel.xs && level != DesignShadowLevel.xxl)
        BoxShadow(
          color: Colors.black.withValues(alpha: opacity * 0.8),
          blurRadius: level == DesignShadowLevel.sm ? 2 : spec.blur / 2,
          offset: Offset(0, spec.y <= 1 ? -1 : spec.y / 2),
          spreadRadius: spec.blur > 6 ? -2 : -1,
        ),
    ];
  }
}

enum DesignShadowLevel { xs, sm, md, lg, xl, xxl }

class _Spec {
  const _Spec(this.y, this.blur, this.spread, this.opacity);
  final double y;
  final double blur;
  final double spread;
  final double opacity;
}

/// 字号 / 行高（行高为逻辑像素，不用倍数，避免继承链上被二次放大）
class DesignType {
  DesignType._();

  static const double xs = 12;
  static const double sm = 14;
  static const double base = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 30;
  static const double xxxxl = 36;

  static const Map<String, Size> ladder = {
    'xs': Size(xs, 16),
    'sm': Size(sm, 20),
    'base': Size(base, 24),
    'lg': Size(lg, 28),
    'xl': Size(xl, 28),
    '2xl': Size(xxl, 32),
    '3xl': Size(xxxl, 36),
    '4xl': Size(xxxxl, 40),
  };
}

/// 间距以 4 为单位
class DesignSpace {
  DesignSpace._();

  static const double u1 = 4;
  static const double u1_5 = 6;
  static const double u2 = 8;
  static const double u3 = 12;
  static const double u4 = 16;
  static const double u5 = 20;
  static const double u6 = 24;
  static const double u8 = 32;
  static const double u10 = 40;
  static const double u12 = 48;
  static const double u16 = 64;
}

class DesignFont {
  DesignFont._();

  static const String family = 'Inter';

  /// 中文与符号由系统字体兜底，系统字全落空时轮到项目自带的中文体
  static const List<String> fallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans SC',
    'FZLanTingYuanS-EB-GB',
    'sans-serif',
  ];
}

/// 由令牌生成一份完整 ThemeData
ThemeData designThemeData(DesignPalette p) {
  final fg = p.foreground;
  final radius = OutlineInputBorder(
    borderRadius: DesignRadius.rMd,
    borderSide: BorderSide(color: p.input),
  );

  /// [height] 传的是行高像素值，这里换算成 Flutter 需要的倍数
  TextStyle t(
    double size, {
    Color? color,
    FontWeight? weight,
    double? height,
  }) => TextStyle(
    fontFamily: DesignFont.family,
    fontFamilyFallback: DesignFont.fallback,
    fontSize: size,
    color: color ?? fg,
    fontWeight: weight,
    height: height == null ? null : height / size,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    fontFamily: DesignFont.family,
    fontFamilyFallback: DesignFont.fallback,
    colorScheme: ColorScheme.light(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.primaryForeground,
      secondary: p.secondary,
      onSecondary: p.secondaryForeground,
      error: p.destructive,
      onError: p.destructiveForeground,
      surface: p.background,
      onSurface: fg,
      surfaceContainerHighest: p.muted,
      onSurfaceVariant: p.mutedForeground,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    textTheme: TextTheme(
      displayLarge: t(DesignType.xxxl, weight: FontWeight.w600, height: 36),
      headlineMedium: t(DesignType.xl, weight: FontWeight.w600, height: 28),
      titleLarge: t(DesignType.base, weight: FontWeight.w600, height: 24),
      titleMedium: t(DesignType.sm, weight: FontWeight.w600, height: 20),
      bodyLarge: t(DesignType.base, height: 24),
      bodyMedium: t(DesignType.sm, color: p.mutedForeground, height: 20),
      bodySmall: t(DesignType.xs, color: p.mutedForeground, height: 16),
      labelLarge: t(DesignType.sm, weight: FontWeight.w500, height: 20),
      labelSmall: t(DesignType.xs, weight: FontWeight.w500, height: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(p.primary),
        foregroundColor: WidgetStatePropertyAll(p.primaryForeground),
        overlayColor: WidgetStatePropertyAll(
          p.isDark ? Colors.white24 : Colors.white30,
        ),
        textStyle: WidgetStatePropertyAll(
          t(DesignType.sm, weight: FontWeight.w500),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: DesignRadius.rMd),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(p.card),
        foregroundColor: WidgetStatePropertyAll(fg),
        overlayColor: WidgetStatePropertyAll(p.hover),
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        textStyle: WidgetStatePropertyAll(
          t(DesignType.sm, weight: FontWeight.w500),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: DesignRadius.rMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(fg),
        overlayColor: WidgetStatePropertyAll(p.hover),
        textStyle: WidgetStatePropertyAll(
          t(DesignType.sm, weight: FontWeight.w500),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: DesignRadius.rMd),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.mutedForeground),
        overlayColor: WidgetStatePropertyAll(p.hover),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: DesignRadius.rMd),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.background,
      hintStyle: t(DesignType.sm, color: p.mutedForeground),
      prefixIconColor: p.mutedForeground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      enabledBorder: radius,
      focusedBorder: radius.copyWith(
        borderSide: BorderSide(color: p.ring, width: 1.5),
      ),
      border: radius,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? p.primaryForeground
            : (p.isDark ? const Color(0xFFA1A1A1) : Colors.white),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? p.primary
            : (p.isDark ? const Color(0xFF404040) : const Color(0xFFE5E5E5)),
      ),
      trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (st) =>
            st.contains(WidgetState.selected) ? p.primary : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(p.primaryForeground),
      side: BorderSide(color: p.isDark ? p.mutedForeground : p.input),
      shape: RoundedRectangleBorder(borderRadius: DesignRadius.rXs),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: p.primary,
      inactiveTrackColor: p.muted,
      thumbColor: p.primary,
      overlayColor: p.primary.withValues(alpha: 0.14),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) =>
              st.contains(WidgetState.selected) ? p.card : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => _isSelected(st) ? fg : p.mutedForeground,
        ),
        overlayColor: WidgetStatePropertyAll(p.hover),
        textStyle: WidgetStatePropertyAll(
          t(DesignType.sm, weight: FontWeight.w500),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: DesignRadius.rSm),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: DesignRadius.rLg,
        side: BorderSide(color: p.border),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: DesignRadius.rXl,
        side: BorderSide(color: p.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: DesignRadius.rMd,
        side: BorderSide(color: p.border),
      ),
      textStyle: t(DesignType.sm),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.mutedForeground,
      textColor: fg,
      titleTextStyle: t(DesignType.sm, weight: FontWeight.w500, height: 20),
      subtitleTextStyle: t(DesignType.xs, color: p.mutedForeground, height: 16),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.invert,
        borderRadius: DesignRadius.rSm,
      ),
      textStyle: t(DesignType.xs, color: p.invertForeground),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.primary,
      linearTrackColor: p.muted,
    ),
  );
}

bool _isSelected(Set<WidgetState> st) => st.contains(WidgetState.selected);
