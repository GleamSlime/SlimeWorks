import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_atmosphere.dart';
import 'package:slime_works/core/theme/app_semantics.dart';

/// 电力统计页的取色别名
///
/// 本页是"柔彩底 + 玻璃卡"的试验田，验收通过后颜色本体已经上收进全局的
/// [AppAtmosphere]（材质）与 [AppSemantic]（角色）。这里只剩一层**转发**：
/// 页面里 100 多个 `p.xxx` 取点不用改，而色值只有一个出处。
///
/// 不要再往这个类里加新的字面值——需要新颜色就说明全局氛围层缺一个角色，
/// 补到 `AppAtmosphere` 去，否则试验田和全站又会分叉。
@immutable
class PowerStatsPalette {
  const PowerStatsPalette(this._s, this._a);

  final AppSemantic _s;
  final AppAtmosphere _a;

  static PowerStatsPalette of(BuildContext context) => PowerStatsPalette(
    AppSemantic.of(context),
    AppAtmosphere.of(context),
  );

  bool get isDark => _s.isDark;

  /// 主墨字：大数字、卡标题
  Color get ink => _s.textPrimary;

  Color get accent => _a.accent;
  Color get violet => _a.violet;

  /// 涨 / 跌方向色
  Color get green => _a.rise;
  Color get rose => _a.fall;

  /// 轨道起点、被越过的档位
  Color get orange => _a.warm;

  /// 横幅渐变起点
  Color get teal => _a.cool;

  Color get glassTint => _s.glassTint;
  Color get glassBorder => _s.glassBorder;
  Color get glassHighlight => _a.glassHighlight;

  Color get trackRest => _a.trackRest;
  Color get chipRest => _a.chipRest;
  Color get chipRestBorder => _a.chipRestBorder;
  Color get slotRest => _a.slotRest;
  Color get baseline => _a.baseline;

  // ── 成对渐变：直接转调氛围层，端点不在本页现拼 ──

  LinearGradient trackFill() => _a.trackFill();
  LinearGradient banner() => _a.banner();
  LinearGradient progress() => _a.progress();
  LinearGradient spark() => _a.spark();
  LinearGradient peakBar() => _a.peakBar();
  LinearGradient underline() => _a.underline();
}
