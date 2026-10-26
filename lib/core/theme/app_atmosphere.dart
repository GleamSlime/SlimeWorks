import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_semantics.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 氛围层材质档（Atmosphere Tier）
///
/// 回答的是"这块东西**是什么做的**"：柔彩底、玻璃顶缘高光、轨道未填充段、
/// 空槽、成对渐变。[AppSemantic] 回答的是"这块区域**报告了什么**"（表面/文字/
/// 状态/身份），两层的判据不同，所以分成两个入口：
///
/// ```dart
/// final s = AppSemantic.of(context);   // 角色
/// final a = AppAtmosphere.of(context); // 材质
/// ```
///
/// **为什么不并进 AppSemantic**：这一档的主体是 `LinearGradient` / `RadialGradient`，
/// Flutter 没有可插值的渐变对。角色层每帧走 [ThemeExtension.lerp]，把渐变塞进去
/// 只会在明暗切换的动画里整段跳变。所以渐变只能待在这层，且 [lerp] 里按 t 取半、
/// 不做补间。
///
/// **只画一次**：背景层由外壳消费（`AtmosphereBackdrop`），页面不得再叠一层自己的
/// 渐变——两张氛围皮叠着，滚动时色差会漂。
@immutable
class AppAtmosphere extends ThemeExtension<AppAtmosphere> {
  const AppAtmosphere({
    required this.isDark,
    required this.accent,
    required this.violet,
    required this.rise,
    required this.fall,
    required this.warm,
    required this.cool,
    required this.glassHighlight,
    required this.trackRest,
    required this.chipRest,
    required this.chipRestBorder,
    required this.slotRest,
    required this.baseline,
    required this.canvas,
    required this.washes,
  });

  static const AppAtmosphere light = AppAtmosphere(
    isDark: false,
    accent: AppBrand.accentLight,
    violet: AppAtmosphereColors.violetLight,
    rise: AppAtmosphereColors.riseLight,
    fall: AppAtmosphereColors.fallLight,
    warm: AppAtmosphereColors.warmLight,
    cool: AppAtmosphereColors.coolLight,
    glassHighlight: AppAtmosphereColors.glassHighlightLight,
    trackRest: AppAtmosphereColors.trackRestLight,
    chipRest: AppAtmosphereColors.chipRestLight,
    chipRestBorder: AppAtmosphereColors.chipRestBorderLight,
    slotRest: AppAtmosphereColors.slotRestLight,
    baseline: AppAtmosphereColors.baselineLight,
    canvas: AppAtmosphereColors.canvasLight,
    washes: AppAtmosphereColors.washesLight,
  );

  static const AppAtmosphere dark = AppAtmosphere(
    isDark: true,
    accent: AppBrand.accentDark,
    violet: AppAtmosphereColors.violetDark,
    rise: AppAtmosphereColors.riseDark,
    fall: AppAtmosphereColors.fallDark,
    warm: AppAtmosphereColors.warmDark,
    cool: AppAtmosphereColors.coolDark,
    glassHighlight: AppAtmosphereColors.glassHighlightDark,
    trackRest: AppAtmosphereColors.trackRestDark,
    chipRest: AppAtmosphereColors.chipRestDark,
    chipRestBorder: AppAtmosphereColors.chipRestBorderDark,
    slotRest: AppAtmosphereColors.slotRestDark,
    baseline: AppAtmosphereColors.baselineDark,
    canvas: AppAtmosphereColors.canvasDark,
    washes: AppAtmosphereColors.washesDark,
  );

  static AppAtmosphere of(BuildContext context) {
    final a = Theme.of(context).extension<AppAtmosphere>();
    if (a != null) return a;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static AppAtmosphere forBrightness(bool isDark) => isDark ? dark : light;

  final bool isDark;

  /// 渐变端点用的强调色。与 [AppSemantic.accent] 同源（同一个 `AppBrand` 常量），
  /// 用户自选强调色时由 `AppTheme._applyCustomization` 一并顶掉，两处不会分叉。
  final Color accent;

  /// 渐变中间档 / 峰值徽章
  final Color violet;

  /// 方向色：涨 / 跌。是"往哪走"，不是"好不好"（那归状态色）
  final Color rise;
  final Color fall;

  /// 轨道起点、被越过的档位
  final Color warm;

  /// 横幅渐变起点
  final Color cool;

  /// 玻璃顶缘那道高光（比下沿亮的一线，去掉"塑料贴片"感）
  final Color glassHighlight;

  /// 轨道未填充段
  final Color trackRest;

  /// 未选中档位胶囊的底色与描边
  final Color chipRest;
  final Color chipRestBorder;

  /// 空槽（榜单未填满那几格）
  final Color slotRest;

  /// 柱状带基线
  final Color baseline;

  /// 页面底：对角基色 + 四团径向色斑
  final LinearGradient canvas;
  final List<RadialGradient> washes;

  // ── 成对渐变：全是"同一个动作的起收点"，端点不许在页面里现拼 ──

  /// 轨道填充：暖 → 紫 → 蓝，档位越高越冷
  LinearGradient trackFill() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [warm, violet, accent],
  );

  /// 事件横幅：青 → 蓝 → 紫（端点是实测值，不归并到 `cool`/`accent`，见 [AppAtmosphereColors.bannerStops]）
  LinearGradient banner() => const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: AppAtmosphereColors.bannerStops,
  );

  /// 进度条：涨 → 蓝
  LinearGradient progress() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [rise, accent],
  );

  /// 迷你趋势线：暖 → 冷，跟"越涨越值钱"的直觉一致
  LinearGradient spark() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [warm, violet, accent],
  );

  /// 峰值柱：蓝 → 紫
  LinearGradient peakBar() => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [accent, violet],
  );

  /// 卡片底缘那条身份下划线：暖 → 蓝
  LinearGradient underline() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [warm, accent],
  );

  /// 背景分层：`BoxDecoration` 只吃一个 gradient，所以基色与色团分开给，
  /// 由外壳叠成 Stack（越靠后越浮在上面）。
  List<BoxDecoration> get backgroundLayers => [
    BoxDecoration(gradient: canvas),
    for (final w in washes) BoxDecoration(gradient: w),
  ];

  /// 玻璃卡投影：精致双层弥散立体投影（主投影 + 环境接触投影），兼顾悬浮与扎实贴地质感
  List<BoxShadow> cardShadow({bool lifted = false}) {
    final keyColor = isDark ? AppSemantic.dark.shadowKey : AppSemantic.light.shadowKey;
    final ambientColor = isDark ? AppSemantic.dark.shadowAmbient : AppSemantic.light.shadowAmbient;
    return [
      BoxShadow(
        color: keyColor,
        blurRadius: lifted ? scaleW(24) : scaleW(14),
        spreadRadius: lifted ? scaleW(1) : 0,
        offset: Offset(0, scaleW(lifted ? 10 : 4)),
      ),
      BoxShadow(
        color: ambientColor,
        blurRadius: lifted ? scaleW(8) : scaleW(4),
        spreadRadius: 0,
        offset: Offset(0, scaleW(lifted ? 3 : 1)),
      ),
    ];
  }

  @override
  AppAtmosphere copyWith({
    bool? isDark,
    Color? accent,
    Color? violet,
    Color? rise,
    Color? fall,
    Color? warm,
    Color? cool,
    Color? glassHighlight,
    Color? trackRest,
    Color? chipRest,
    Color? chipRestBorder,
    Color? slotRest,
    Color? baseline,
    LinearGradient? canvas,
    List<RadialGradient>? washes,
  }) {
    return AppAtmosphere(
      isDark: isDark ?? this.isDark,
      accent: accent ?? this.accent,
      violet: violet ?? this.violet,
      rise: rise ?? this.rise,
      fall: fall ?? this.fall,
      warm: warm ?? this.warm,
      cool: cool ?? this.cool,
      glassHighlight: glassHighlight ?? this.glassHighlight,
      trackRest: trackRest ?? this.trackRest,
      chipRest: chipRest ?? this.chipRest,
      chipRestBorder: chipRestBorder ?? this.chipRestBorder,
      slotRest: slotRest ?? this.slotRest,
      baseline: baseline ?? this.baseline,
      canvas: canvas ?? this.canvas,
      washes: washes ?? this.washes,
    );
  }

  @override
  AppAtmosphere lerp(AppAtmosphere? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    // 渐变没有可插值的形态，只能按半程硬切：主题切换动画里背景会在中点换一次，
    // 而前景角色色是连续过渡的——这正是渐变不进 AppSemantic 的原因。
    final bool takeOther = t >= 0.5;
    return AppAtmosphere(
      isDark: takeOther ? other.isDark : isDark,
      accent: c(accent, other.accent),
      violet: c(violet, other.violet),
      rise: c(rise, other.rise),
      fall: c(fall, other.fall),
      warm: c(warm, other.warm),
      cool: c(cool, other.cool),
      glassHighlight: c(glassHighlight, other.glassHighlight),
      trackRest: c(trackRest, other.trackRest),
      chipRest: c(chipRest, other.chipRest),
      chipRestBorder: c(chipRestBorder, other.chipRestBorder),
      slotRest: c(slotRest, other.slotRest),
      baseline: c(baseline, other.baseline),
      canvas: takeOther ? other.canvas : canvas,
      washes: takeOther ? other.washes : washes,
    );
  }
}

/// 便捷访问：`context.atmosphere.warm`
extension AppAtmosphereContext on BuildContext {
  AppAtmosphere get atmosphere => AppAtmosphere.of(this);
}
