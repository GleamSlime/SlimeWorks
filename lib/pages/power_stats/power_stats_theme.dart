import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_semantics.dart';

import 'package:slime_works/core/utils/size_utils.dart';

/// 电力统计页的柔彩配色（试验田）
///
/// 全站取色层仍是 [AppSemantic]，这一档是**故意**为本页单开的一块：柔彩渐变底 +
/// 玻璃卡需要一组带饱和度的装饰色，语义层里没有它们的位置（它们既不是状态色，
/// 也不是身份色，是"氛围"）。本页验收通过后再决定上收进 AppVizSet 还是新建一档，
/// 在此之前不要引到别的页面去。
///
/// 明暗两套：暗色不是把亮色反一下，柔彩底压暗后饱和度必须跟着降，
/// 否则桃红和薰衣草会在深底上变成两块荧光斑。
@immutable
class PowerStatsPalette {
  const PowerStatsPalette({
    required this.isDark,
    required this.ink,
    required this.accent,
    required this.violet,
    required this.green,
    required this.rose,
    required this.orange,
    required this.teal,
    required this.glassTint,
    required this.glassBorder,
    required this.glassHighlight,
    required this.shadow,
    required this.trackRest,
    required this.chipRest,
    required this.chipRestBorder,
    required this.slotRest,
    required this.baseline,
    required this.bgBase,
    required this.bgWashes,
  });

  final bool isDark;

  /// 主墨字：大数字、卡标题
  final Color ink;

  /// 强调蓝：数值刷新时的闪烁色、峰值柱、进度条终点
  final Color accent;

  /// 紫：渐变里的中间档，以及峰值徽章
  final Color violet;

  /// 绿：正向增量（多花电费时的"涨"、上涨柱）
  final Color green;

  /// 粉：负向（下降柱、空头侧徽标）
  final Color rose;

  /// 橙：轨道起点、被越过的档位 chip
  final Color orange;

  /// 青：横幅渐变起点
  final Color teal;

  /// 玻璃卡三层：着色底、描边、顶缘那道高光
  final Color glassTint;
  final Color glassBorder;
  final Color glassHighlight;

  /// 卡片投影色
  final Color shadow;

  /// 轨道未填充段
  final Color trackRest;

  /// 未选中档位胶囊的底色与描边
  final Color chipRest;
  final Color chipRestBorder;

  /// TOP5 空槽底色
  final Color slotRest;

  /// 柱状带基线
  final Color baseline;

  /// 页面底：一层对角渐变 + 若干角上的径向色团叠出柔彩mesh感
  final LinearGradient bgBase;
  final List<RadialGradient> bgWashes;

  static final PowerStatsPalette light = PowerStatsPalette(
    isDark: false,
    ink: const Color(0xFF261A3A),
    accent: const Color(0xFF2F65DE),
    violet: const Color(0xFF715FFD),
    green: const Color(0xFF0CA678),
    rose: const Color(0xFFF06E81),
    orange: const Color(0xFFFF855A),
    teal: const Color(0xFF1B8FB5),
    glassTint: Colors.white.withAlpha(150),
    glassBorder: Colors.white.withAlpha(160),
    glassHighlight: Colors.white.withAlpha(200),
    shadow: const Color(0xFF5B4A7F).withAlpha(38),
    trackRest: const Color(0xFF261A3A).withAlpha(22),
    chipRest: Colors.white.withAlpha(170),
    chipRestBorder: Colors.white.withAlpha(200),
    slotRest: Colors.white.withAlpha(70),
    baseline: const Color(0xFF261A3A).withAlpha(40),
    bgBase: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFF9DAC4),
        Color(0xFFF3E7E4),
        Color(0xFFD4D1E9),
        Color(0xFFD3E4F6),
      ],
      stops: [0.0, 0.38, 0.72, 1.0],
    ),
    bgWashes: [
      RadialGradient(
        center: const Alignment(-0.9, -0.85),
        radius: 0.75,
        colors: [const Color(0xFFFFC9A8).withAlpha(150), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(0.95, -0.55),
        radius: 0.7,
        colors: [const Color(0xFFBFDFFB).withAlpha(150), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(-0.75, 0.95),
        radius: 0.8,
        colors: [const Color(0xFFD9CBF3).withAlpha(150), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(0.85, 0.8),
        radius: 0.7,
        colors: [const Color(0xFFF6D3DF).withAlpha(140), Colors.transparent],
      ),
    ],
  );

  static final PowerStatsPalette dark = PowerStatsPalette(
    isDark: true,
    ink: const Color(0xFFF1EEFA),
    accent: const Color(0xFF7C9BFF),
    violet: const Color(0xFF9C8CFF),
    green: const Color(0xFF3FD19C),
    rose: const Color(0xFFFF8DA0),
    orange: const Color(0xFFFFA07A),
    teal: const Color(0xFF5AC8E0),
    glassTint: const Color(0xFF221C38).withAlpha(165),
    glassBorder: Colors.white.withAlpha(34),
    glassHighlight: Colors.white.withAlpha(26),
    shadow: const Color(0xFF000000).withAlpha(70),
    trackRest: Colors.white.withAlpha(28),
    chipRest: Colors.white.withAlpha(24),
    chipRestBorder: Colors.white.withAlpha(38),
    slotRest: Colors.white.withAlpha(16),
    baseline: Colors.white.withAlpha(46),
    bgBase: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF241C33),
        Color(0xFF1B1826),
        Color(0xFF1A1E2E),
        Color(0xFF221B31),
      ],
      stops: [0.0, 0.38, 0.72, 1.0],
    ),
    bgWashes: [
      RadialGradient(
        center: const Alignment(-0.9, -0.85),
        radius: 0.75,
        colors: [const Color(0xFF7A4A2E).withAlpha(80), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(0.95, -0.55),
        radius: 0.7,
        colors: [const Color(0xFF2F4E7A).withAlpha(85), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(-0.75, 0.95),
        radius: 0.8,
        colors: [const Color(0xFF4A3A75).withAlpha(85), Colors.transparent],
      ),
      RadialGradient(
        center: const Alignment(0.85, 0.8),
        radius: 0.7,
        colors: [const Color(0xFF6E3A52).withAlpha(75), Colors.transparent],
      ),
    ],
  );

  static PowerStatsPalette of(BuildContext context) =>
      AppSemantic.of(context).isDark ? dark : light;

  // ── 渐变（都是"同一个动作的起收点"，成对给，别在页面里现拼色标）──

  /// 轨道填充：橙 → 紫 → 蓝，档位越高越冷
  LinearGradient trackFill() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [orange, violet, accent],
  );

  /// 事件横幅：青 → 蓝 → 紫
  LinearGradient banner() => const LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF1897A9), Color(0xFF466DFD), Color(0xFF715FFD)],
  );

  /// 进度条：绿 → 蓝
  LinearGradient progress() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [green, accent],
  );

  /// 迷你趋势线：暖 → 冷，跟"越涨越值钱"的直觉一致
  LinearGradient spark() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [orange, violet, accent],
  );

  /// 峰值柱：蓝 → 紫
  LinearGradient peakBar() => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [accent, violet],
  );

  /// 卡片底缘那条身份下划线：橙 → 蓝
  LinearGradient underline() => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [orange, accent],
  );

  /// 页面底：BoxDecoration 只吃一个 gradient，所以对角基色 + 四角色团分层给，
  /// 由页面自己叠成 Stack（越靠后的层越浮在上面）
  List<BoxDecoration> get backgroundLayers => [
    BoxDecoration(gradient: bgBase),
    for (final w in bgWashes) BoxDecoration(gradient: w),
  ];

  /// 玻璃卡投影
  List<BoxShadow> cardShadow({bool lifted = false}) => [
    BoxShadow(
      color: shadow,
      blurRadius: lifted ? scaleW(28) : scaleW(16),
      spreadRadius: lifted ? scaleW(2) : 0,
      offset: Offset(0, scaleW(lifted ? 12 : 6)),
    ),
  ];
}
