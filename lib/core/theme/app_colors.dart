import 'package:flutter/material.dart';

/// 原始调色板（Raw Palette）
///
/// 这里只存放「不加解释的原始色值」：透明度梯度、品牌色相、背景层。
/// 业务代码不应直接依赖本文件做语义判断（例如"这是成功色"），
/// 请使用 [AppSemantic.of(context)] 获取随明暗主题自动解析的语义角色。
///
/// 参考：[app_semantics.dart]

// ─────────────────────────────────────────────────────────────
// 发丝线梯度修正说明：
// 历史上 black1 / white1 与 black10 / white10 取值相同（均为 0x1A），
// 导致 195 处"极细描边/分割线"实际以 10% 不透明度绘制，视觉上偏重。
// 现将其收敛为真正的发丝线（约 4%），使层次区分重新成立。
// ─────────────────────────────────────────────────────────────

/// 亮色主题颜色定义
class LightColors {
  LightColors._();

  // 黑色系列
  static const Color black100 = Color(0xFF000000);
  static const Color black80 = Color(0xCC000000);
  static const Color black60 = Color(0x99000000);
  static const Color black40 = Color(0x66000000);
  static const Color black20 = Color(0x33000000);
  static const Color black10 = Color(0x1A000000);
  static const Color black6 = Color(0x0F000000);
  static const Color black5 = Color(0x0D000000);
  static const Color black4 = Color(0x0A000000);
  static const Color black1 = Color(0x0A000000);

  // 白色系列
  static const Color white100 = Color(0xFFFFFFFF);
  static const Color white80 = Color(0xCCFFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white20 = Color(0x33FFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white6 = Color(0x0FFFFFFF);
  static const Color white5 = Color(0x0DFFFFFF);
  static const Color white4 = Color(0x0AFFFFFF);
  static const Color white1 = Color(0x0AFFFFFF);

  // 主色调（品牌软紫，用于装饰/渐变/大面积铺底，不建议直接承载白字）
  static const Color primary = Color(0xFFA89FEE);

  // 强调色（加深的同色相，用于按钮填充与文字，满足白字对比度）
  static const Color accentStrong = Color(0xFF6F5FD9);

  // 次要颜色
  static const Color purple = Color(0xFFBBA8F6);
  static const Color indigo = Color(0xFFA8B8F6);
  static const Color blue = Color(0xFF6FB8E8);
  static const Color cyan = Color(0xFF9AC8DD);
  static const Color mint = Color(0xFF82D7BB);
  static const Color green = Color(0xFF7EDB7E);
  static const Color yellow = Color(0xFFFFCB3A);
  static const Color orange = Color(0xFFF5A569);
  static const Color red = Color(0xFFFF6C74);

  // 背景色（历史命名，保留兼容）
  static const Color background1 = Color(0xFFFFFFFF);
  static const Color background2 = Color(0xFFF5F5F5);
  static const Color background3 = Color(0xFFF6F6F6);
  static const Color background4 = Color(0xFFEEEEEE);
  static const Color background5 = Color(0xFFE8E5F8);
  static const Color background6 = Color(0xFFE5F3FB);
  static const Color background7 = Color(0xFF424242);

  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color overlay = Color(0xB3000000);
  static const Color overlayLight = Color(0x66000000);
}

/// 暗色主题颜色定义
class DarkColors {
  DarkColors._();

  // 白色系列 (暗色主题)
  static const Color white100 = Color(0xFFFFFFFF);
  static const Color white80 = Color(0xCCFFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white20 = Color(0x33FFFFFF);
  static const Color white15 = Color(0x26FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white6 = Color(0x0FFFFFFF);
  static const Color white5 = Color(0x0DFFFFFF);
  static const Color white4 = Color(0x0AFFFFFF);
  static const Color white1 = Color(0x0AFFFFFF);

  // 黑色系列 (暗色主题)
  static const Color black100 = Color(0xFF000000);
  static const Color black80 = Color(0xCC000000);
  static const Color black60 = Color(0x99000000);
  static const Color black40 = Color(0x66000000);
  static const Color black20 = Color(0x33000000);
  static const Color black10 = Color(0x1A000000);
  static const Color black6 = Color(0x0F000000);
  static const Color black4 = Color(0x0A000000);
  static const Color black5 = Color(0x0D000000);
  static const Color black1 = Color(0x0A000000);

  // 主色调（暗色下软紫本身即为可读的强调色，直接承载黑字）
  static const Color primary = Color(0xFFA89FEE);

  // 强调色（暗色下与主色一致，保持调用点写法统一）
  static const Color accentStrong = Color(0xFFA89FEE);

  // 次要颜色
  static const Color purple = Color(0xFFBBA8F6);
  static const Color indigo = Color(0xFFA8B8F6);
  static const Color blue = Color(0xFF6FB8E8);
  static const Color cyan = Color(0xFF9AC8DD);
  static const Color mint = Color(0xFF82D7BB);
  static const Color green = Color(0xFF7EDB7E);
  static const Color yellow = Color(0xFFFFCB3A);
  static const Color orange = Color(0xFFF5A569);
  static const Color red = Color(0xFFFF6C74);

  // 背景色（历史命名，保留兼容）
  static const Color background1 = Color(0xFF1E1F1C);
  static const Color background2 = Color(0xFF383838);
  static const Color background3 = Color(0xFF2E2E2E);
  static const Color background4 = Color(0xFF524A66);
  static const Color background5 = Color(0xFF2B4A5E);
  static const Color background6 = Color(0xFFFFFFFF);
  static const Color background7 = Color(0xFF424242);

  static const Color success = Color(0xFF66BB6A);
  static const Color warning = Color(0xFFFFA726);
  static const Color overlay = Color(0xB3000000);
  static const Color overlayLight = Color(0x66000000);
}

/// 中性表面层次（Surface Ramps）
///
/// 纯灰、不带任何色温偏移：一旦掺进暖调，卡片和画布的分层就会发"糊"，
/// 状态色也跟着串味。层次靠明度阶梯 + 1px 实心描边拉开，不靠彩色染色。
class AppSurfaces {
  AppSurfaces._();

  // ── 亮色 ──
  /// 窗口画布（最外层底色）
  ///
  /// 必须与 surface 拉开：历史上画布与卡片都是接近 #FFF 的白，
  /// 卡片只能靠描边勉强分辨，整页显得"平、糊、没有浮起感"。
  static const Color lightCanvas = Color(0xFFFAFAFA);

  /// 一级表面：卡片 / 面板
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// 二级表面：卡片内嵌区块 / 浮起菜单
  static const Color lightSurfaceRaised = Color(0xFFFFFFFF);

  /// 下沉表面：输入框底 / 分组背景
  static const Color lightSurfaceSunken = Color(0xFFF5F5F5);

  /// 交互态
  ///
  /// 悬停是"状态层"，必须用水洗而不是实心色：实心底一压上去，底下那层窗口磨砂就
  /// 断了（实测表现为鼠标移到侧栏分组标题上出现一块不透的白斑）。
  ///
  /// 水洗的方向必须跟着底色走：亮色侧的表面是白（#FFFFFF 卡片 / #FAFAFA 画布），
  /// 再往上叠白色就是零反馈——原来那颗 0x2DFFFFFF 正是这个问题，卡片、列表行、
  /// 菜单在亮色模式下全都没有悬停。改成半透明黑，压白得 #F5F5F5、压画布得 #F0F0F0，
  /// 依旧透得下去。暗色侧表面本来就比白暗，继续用提亮的白水洗。
  static const Color lightSurfaceHover = Color(0x0A000000);
  static const Color lightSurfaceActive = Color(0x14000000);

  /// 亮色下极轻的分隔（用于相邻表面几乎无接缝处）
  static const Color lightHairline = Color(0x0D000000);

  /// 亮色下常规描边
  ///
  /// 这套语言里描边是实心灰阶（#E5E5E5），不是半透明黑：描边要能独立成立，
  /// 卡片压在画布上才有那一条干脆的分界线。
  static const Color lightBorder = Color(0xFFE5E5E5);

  /// 亮色下强描边（输入框聚焦前 / 需要边界感处）
  static const Color lightBorderStrong = Color(0xFFA3A3A3);

  // ── 暗色 ──
  /// 窗口画布
  static const Color darkCanvas = Color(0xFF0A0A0A);

  /// 一级表面
  static const Color darkSurface = Color(0xFF171717);

  /// 二级表面
  static const Color darkSurfaceRaised = Color(0xFF262626);

  /// 下沉表面
  ///
  /// 不能等于 darkCanvas：否则"下沉"控件（输入框/图标底板/侧栏）贴在画布上时
  /// 完全隐形，落在卡片上又像一个挖空的洞。
  static const Color darkSurfaceSunken = Color(0xFF0F0F0F);

  /// 交互态
  ///
  /// 暗色侧的表面比白暗，所以这里继续用**提亮**的白水洗。方向与亮色相反是
  /// 有意为之：水洗永远朝"看得见"那侧走。
  static const Color darkSurfaceHover = Color(0x14FFFFFF);
  static const Color darkSurfaceActive = Color(0x1FFFFFFF);

  static const Color darkHairline = Color(0x14FFFFFF);
  static const Color darkBorder = Color(0x1AFFFFFF);
  static const Color darkBorderStrong = Color(0x33FFFFFF);

  // ── 文字层级 ──
  static const Color lightTextPrimary = Color(0xFF0A0A0A);
  static const Color lightTextSecondary = Color(0xFF525252);
  static const Color lightTextTertiary = Color(0xFF737373);
  static const Color lightTextDisabled = Color(0xFFA3A3A3);

  static const Color darkTextPrimary = Color(0xFFFAFAFA);
  static const Color darkTextSecondary = Color(0xFFA3A3A3);
  static const Color darkTextTertiary = Color(0xFF737373);
  static const Color darkTextDisabled = Color(0xFF525252);
}

/// 品牌与强调色（Brand Ramp）
///
/// 品牌紫现在只是点缀（info、图表、装饰）；主色位由 [inkLight] / [inkDark] 这对
/// 反相墨色接管。渐变字段仍保留，因为渐变标题的老签名还吃 LinearGradient，
/// 两端同色即纯色。
class AppBrand {
  AppBrand._();

  /// 反相主按钮底色（亮色：近黑）
  static const Color ink = Color(0xFF171717);

  /// 反相主按钮文字（亮色）
  static const Color inkOn = Color(0xFFFAFAFA);

  /// 反相主按钮底色（暗色：近白）
  static const Color inkInverse = Color(0xFFE5E5E5);

  /// 两端同色的"渐变"：只为还吃 LinearGradient 的老签名（渐变标题）保留
  static const LinearGradient inkLight = LinearGradient(
    colors: [ink, ink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient inkDark = LinearGradient(
    colors: [inkInverse, inkInverse],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 品牌软紫（装饰、渐变、大面积铺底）
  static const Color soft = Color(0xFFA89FEE);
  static const Color softLight = Color(0xFFC4BDF5);
  /// 主品牌色（浅色模式下的强调色）。
  ///
  /// 取值以"在画布上文字对比度 >=4.5"为下限：#6F5FD9 只有 4.30，
  /// 小字号链接/标签会发灰，故压深到 4.89。
  static const Color deep = Color(0xFF6656CF);
  static const Color deepLight = Color(0xFF8577E4);

  /// 亮色下主标题/主按钮渐变。
  /// 两端都要足够深：渐变标题（ShaderMask）若尾端太浅，白底上会糊成一片。
  static const LinearGradient lightGradient = LinearGradient(
    colors: [Color(0xFF5D4BC9), Color(0xFF8577E4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// 暗色下主按钮渐变
  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFFC4BDF5), Color(0xFF8F82E8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// 状态色家族（语义化，取代散落的 Colors.green / orange / red）
///
/// 每个状态提供两档：主色（点、图标、图表线）和容器上的文字色。
/// 文字必须单独压深/提亮：状态主色本身是给"点"用的，直接拿它当小字号文字，
/// 亮色下 #00BB7F 这种饱和绿在白底上只有 2.4:1，读起来是一片糊。
class AppStatus {
  AppStatus._();

  static const Color lightSuccess = Color(0xFF00BB7F);
  static const Color lightSuccessText = Color(0xFF004E3B);
  static const Color lightWarning = Color(0xFFEDB200);
  static const Color lightWarningText = Color(0xFF733E0A);
  static const Color lightDanger = Color(0xFFE40014);
  static const Color lightDangerText = Color(0xFF9F0712);
  static const Color lightInfo = Color(0xFF8D54FF);
  static const Color lightInfoText = Color(0xFF4D179A);
  static const Color lightNeutral = Color(0xFF737373);
  static const Color lightNeutralText = Color(0xFF404040);

  static const Color darkSuccess = Color(0xFF00BB7F);
  static const Color darkSuccessText = Color(0xFF5EEAD4);
  static const Color darkWarning = Color(0xFFEDB200);
  static const Color darkWarningText = Color(0xFFFCD34D);
  static const Color darkDanger = Color(0xFFFF6568);
  static const Color darkDangerText = Color(0xFFFFB4B6);
  static const Color darkInfo = Color(0xFFAC4BFF);
  static const Color darkInfoText = Color(0xFFD6BBFE);
  static const Color darkNeutral = Color(0xFFA1A1A1);
  static const Color darkNeutralText = Color(0xFFD4D4D4);

  /// 容器底色统一用主色 + 低透明度，避免再手写 withAlpha
  static Color container(Color base, {bool dark = false}) =>
      base.withValues(alpha: dark ? 0.16 : 0.10);

  /// 容器内描边
  static Color containerBorder(Color base, {bool dark = false}) =>
      base.withValues(alpha: dark ? 0.28 : 0.22);
}

/// 磨砂玻璃材质参数（Glass Material）
class AppGlass {
  AppGlass._();

  /// 背景模糊半径（BackdropFilter sigma）
  static const double blurSoft = 12;
  static const double blurMedium = 24;
  static const double blurStrong = 40;

  /// 玻璃上的着色叠加层透明度：亮色下需要更多白，暗色下更多黑
  static const double tintLight = 0.72;
  static const double tintDark = 0.55;

  /// 侧边栏这类常驻面板的着色透明度（比卡片更透，以便透出桌面）
  static const double panelTintLight = 0.55;
  static const double panelTintDark = 0.42;
}
