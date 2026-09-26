import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 语义角色令牌（Semantic Tokens）
///
/// 以 [ThemeExtension] 形式注册进 [ThemeData]，因此：
/// 1. 随明暗主题自动切换，调用点不需要再写 `brightness == Brightness.dark`；
/// 2. 主题切换时能正确参与颜色过渡动画；
/// 3. 只依赖 `Theme.of(context)`，不需要额外的 InheritedWidget。
///
/// 用法：`final s = AppSemantic.of(context);` 然后用 `s.surface` / `s.textSecondary` …
///
/// 这是本次 UI 统一的**唯一取色入口**。历史代码里的
/// `isDark ? DarkColors.x : LightColors.y` 分支应逐步收敛到这里。
class AppSemantic extends ThemeExtension<AppSemantic> {
  const AppSemantic({
    required this.isDark,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.surfaceHover,
    required this.surfaceActive,
    required this.hairline,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentOn,
    required this.accentText,
    required this.accentContainer,
    required this.accentContainerBorder,
    required this.accentGradient,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.scrim,
    required this.shadowKey,
    required this.shadowAmbient,
    required this.glassTint,
    required this.glassBorder,
    required this.glassBlur,
    required this.glassPanelTint,
  });

  // ── 亮色解析 ──
  static const AppSemantic light = AppSemantic(
    isDark: false,
    canvas: AppSurfaces.lightCanvas,
    surface: AppSurfaces.lightSurface,
    surfaceRaised: AppSurfaces.lightSurfaceRaised,
    surfaceSunken: AppSurfaces.lightSurfaceSunken,
    surfaceHover: AppSurfaces.lightSurfaceHover,
    surfaceActive: AppSurfaces.lightSurfaceActive,
    hairline: AppSurfaces.lightHairline,
    border: AppSurfaces.lightBorder,
    borderStrong: AppSurfaces.lightBorderStrong,
    textPrimary: AppSurfaces.lightTextPrimary,
    textSecondary: AppSurfaces.lightTextSecondary,
    textTertiary: AppSurfaces.lightTextTertiary,
    textDisabled: AppSurfaces.lightTextDisabled,
    // 主按钮/选中态走"反相墨色"：全站只留这一种实心强调底，
    // 品牌紫退出主色位，只活在 info 与图表里当点缀。
    accent: AppBrand.ink,
    accentOn: AppBrand.inkOn,
    accentText: AppSurfaces.lightTextPrimary,
    accentContainer: Color(0xFFF5F5F5),
    accentContainerBorder: AppSurfaces.lightBorder,
    accentGradient: AppBrand.inkLight,
    success: AppStatusRole(
      color: AppStatus.lightSuccess,
      onContainer: AppStatus.lightSuccessText,
    ),
    warning: AppStatusRole(
      color: AppStatus.lightWarning,
      onContainer: AppStatus.lightWarningText,
    ),
    danger: AppStatusRole(
      color: AppStatus.lightDanger,
      onContainer: AppStatus.lightDangerText,
    ),
    info: AppStatusRole(
      color: AppStatus.lightInfo,
      onContainer: AppStatus.lightInfoText,
    ),
    neutral: AppStatusRole(
      color: AppStatus.lightNeutral,
      onContainer: AppStatus.lightNeutralText,
    ),
    scrim: LightColors.overlay,
    shadowKey: Color(0x0F000000),
    shadowAmbient: Color(0x07000000),
    glassTint: Color(0xB8FFFFFF),
    glassBorder: AppSurfaces.lightBorder,
    glassBlur: AppGlass.blurMedium,
    glassPanelTint: Color(0x8CFFFFFF),
  );

  // ── 暗色解析 ──
  static const AppSemantic dark = AppSemantic(
    isDark: true,
    canvas: AppSurfaces.darkCanvas,
    surface: AppSurfaces.darkSurface,
    surfaceRaised: AppSurfaces.darkSurfaceRaised,
    surfaceSunken: AppSurfaces.darkSurfaceSunken,
    surfaceHover: AppSurfaces.darkSurfaceHover,
    surfaceActive: AppSurfaces.darkSurfaceActive,
    hairline: AppSurfaces.darkHairline,
    border: AppSurfaces.darkBorder,
    borderStrong: AppSurfaces.darkBorderStrong,
    textPrimary: AppSurfaces.darkTextPrimary,
    textSecondary: AppSurfaces.darkTextSecondary,
    textTertiary: AppSurfaces.darkTextTertiary,
    textDisabled: AppSurfaces.darkTextDisabled,
    // 暗色下"反相"就是提亮到近白：主按钮是一块亮底 + 墨色字，
    // 而不是又回到一层面料般的紫。
    accent: AppBrand.inkInverse,
    accentOn: AppBrand.ink,
    accentText: AppSurfaces.darkTextPrimary,
    accentContainer: Color(0xFF262626),
    accentContainerBorder: Color(0xFF404040),
    accentGradient: AppBrand.inkDark,
    success: AppStatusRole(
      color: AppStatus.darkSuccess,
      onContainer: AppStatus.darkSuccessText,
      dark: true,
    ),
    warning: AppStatusRole(
      color: AppStatus.darkWarning,
      onContainer: AppStatus.darkWarningText,
      dark: true,
    ),
    danger: AppStatusRole(
      color: AppStatus.darkDanger,
      onContainer: AppStatus.darkDangerText,
      dark: true,
    ),
    info: AppStatusRole(
      color: AppStatus.darkInfo,
      onContainer: AppStatus.darkInfoText,
      dark: true,
    ),
    neutral: AppStatusRole(
      color: AppStatus.darkNeutral,
      onContainer: AppStatus.darkNeutralText,
      dark: true,
    ),
    scrim: DarkColors.overlay,
    shadowKey: Color(0x66000000),
    shadowAmbient: Color(0x33000000),
    glassTint: Color(0x9E171717),
    glassBorder: AppSurfaces.darkBorder,
    glassBlur: AppGlass.blurMedium,
    glassPanelTint: Color(0x6B171717),
  );

  static AppSemantic of(BuildContext context) {
    final s = Theme.of(context).extension<AppSemantic>();
    // 理论上一定注册了；兜底按亮度选，避免任何情况下取不到语义色。
    if (s != null) return s;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  final bool isDark;

  // 表面层次
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color surfaceHover;
  final Color surfaceActive;

  // 描边
  final Color hairline;
  final Color border;
  final Color borderStrong;

  // 文字
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  // 强调色
  final Color accent;
  final Color accentOn;
  final Color accentText;
  final Color accentContainer;
  final Color accentContainerBorder;
  final LinearGradient accentGradient;

  // 状态
  final AppStatusRole success;
  final AppStatusRole warning;
  final AppStatusRole danger;
  final AppStatusRole info;
  final AppStatusRole neutral;

  // 遮罩与投影
  final Color scrim;
  final Color shadowKey;
  final Color shadowAmbient;

  // 磨砂玻璃
  final Color glassTint;
  final Color glassBorder;
  final double glassBlur;
  final Color glassPanelTint;

  /// 统一的悬浮抬升投影：key + ambient 双层，替代散落的 95 处手写 BoxShadow
  List<BoxShadow> elevation(Elevation level, {Color? tint}) {
    final base = switch (level) {
      Elevation.none => const _ShadowSpec(0, 0, 0),
      // 抬升量整体压小：这套语言里层次主要靠 1px 实心描边拉开，
      // 投影只负责"离地一点点"，投得越重越像贴了张纸上去。
      Elevation.raised => const _ShadowSpec(1, 2, 0),
      Elevation.card => const _ShadowSpec(1, 3, 0),
      Elevation.floating => const _ShadowSpec(10, 15, -3),
      Elevation.overlay => const _ShadowSpec(20, 25, -5),
    };
    if (base.blur == 0) return const [];
    return [
      BoxShadow(
        color: tint ?? shadowKey,
        blurRadius: base.blur,
        offset: Offset(0, base.y),
        spreadRadius: base.spread,
      ),
      BoxShadow(
        color: shadowAmbient,
        blurRadius: base.blur * 2,
        offset: Offset(0, base.y * 2),
        spreadRadius: 0,
      ),
    ];
  }

  /// 玻璃面板装饰：着色 + 发丝描边 + 抬升投影
  BoxDecoration glass({bool panel = false, Elevation level = Elevation.card}) {
    return BoxDecoration(
      color: panel ? glassPanelTint : glassTint,
      border: Border.all(color: glassBorder, width: 1),
      boxShadow: elevation(level),
    );
  }

  @override
  AppSemantic copyWith({
    bool? isDark,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? surfaceHover,
    Color? surfaceActive,
    Color? hairline,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? accent,
    Color? accentOn,
    Color? accentText,
    Color? accentContainer,
    Color? accentContainerBorder,
    LinearGradient? accentGradient,
    AppStatusRole? success,
    AppStatusRole? warning,
    AppStatusRole? danger,
    AppStatusRole? info,
    AppStatusRole? neutral,
    Color? scrim,
    Color? shadowKey,
    Color? shadowAmbient,
    Color? glassTint,
    Color? glassBorder,
    double? glassBlur,
    Color? glassPanelTint,
  }) {
    return AppSemantic(
      isDark: isDark ?? this.isDark,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      surfaceActive: surfaceActive ?? this.surfaceActive,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      accent: accent ?? this.accent,
      accentOn: accentOn ?? this.accentOn,
      accentText: accentText ?? this.accentText,
      accentContainer: accentContainer ?? this.accentContainer,
      accentContainerBorder: accentContainerBorder ?? this.accentContainerBorder,
      accentGradient: accentGradient ?? this.accentGradient,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      scrim: scrim ?? this.scrim,
      shadowKey: shadowKey ?? this.shadowKey,
      shadowAmbient: shadowAmbient ?? this.shadowAmbient,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBlur: glassBlur ?? this.glassBlur,
      glassPanelTint: glassPanelTint ?? this.glassPanelTint,
    );
  }

  @override
  AppSemantic lerp(AppSemantic? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppSemantic(
      isDark: t < 0.5 ? isDark : other.isDark,
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      surfaceActive: c(surfaceActive, other.surfaceActive),
      hairline: c(hairline, other.hairline),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      accent: c(accent, other.accent),
      accentOn: c(accentOn, other.accentOn),
      accentText: c(accentText, other.accentText),
      accentContainer: c(accentContainer, other.accentContainer),
      accentContainerBorder: c(accentContainerBorder, other.accentContainerBorder),
      accentGradient: t < 0.5 ? accentGradient : other.accentGradient,
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      info: info.lerp(other.info, t),
      neutral: neutral.lerp(other.neutral, t),
      scrim: c(scrim, other.scrim),
      shadowKey: c(shadowKey, other.shadowKey),
      shadowAmbient: c(shadowAmbient, other.shadowAmbient),
      glassTint: c(glassTint, other.glassTint),
      glassBorder: c(glassBorder, other.glassBorder),
      glassBlur: _lerpDouble(glassBlur, other.glassBlur, t),
      glassPanelTint: c(glassPanelTint, other.glassPanelTint),
    );
  }
}

/// 状态色角色：主色 / 容器底 / 容器描边 / 容器上文字
class AppStatusRole {
  const AppStatusRole({
    required this.color,
    required this.onContainer,
    this.dark = false,
  });

  final Color color;
  final Color onContainer;

  /// 是否暗色主题：决定容器底浓度（暗色下需更高 alpha 才看得出层次）
  final bool dark;

  /// 半透明容器底（标签、徽章、告警条背景）
  Color get container => AppStatus.container(color, dark: dark);

  /// 容器内描边
  ///
  /// 必须跟着 `dark` 走：暗色档要更浓才压得住深灰表面，漏传就等于这条规则白写。
  Color get containerBorder => AppStatus.containerBorder(color, dark: dark);

  AppStatusRole lerp(AppStatusRole other, double t) => AppStatusRole(
    color: Color.lerp(color, other.color, t)!,
    onContainer: Color.lerp(onContainer, other.onContainer, t)!,
    dark: t < 0.5 ? dark : other.dark,
  );
}

/// 投影层级
enum Elevation { none, raised, card, floating, overlay }

class _ShadowSpec {
  const _ShadowSpec(this.y, this.blur, this.spread);
  final double y;
  final double blur;
  final double spread;
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// 便捷访问：`context.semantic.surface`
extension AppSemanticContext on BuildContext {
  AppSemantic get semantic => AppSemantic.of(this);
  bool get isDarkTheme => AppSemantic.of(this).isDark;
}
