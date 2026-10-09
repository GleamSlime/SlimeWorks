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

  /// 封面/ artwork 之上那种"化成一团"的重模糊，超出上面三档的量程
  static const double blurArtwork = 50;

  /// 玻璃上的着色叠加层透明度：亮色下需要更多白，暗色下更多黑
  static const double tintLight = 0.72;
  static const double tintDark = 0.55;

  /// 侧边栏这类常驻面板的着色透明度（比卡片更透，以便透出桌面）
  static const double panelTintLight = 0.55;
  static const double panelTintDark = 0.42;
}

/// 媒体层 chrome（Media Chrome）
///
/// 封面卡、看图器、播放器、朗读页这几层压的是照片/视频/专辑图，底色由内容自己
/// 决定、跟应用主题无关，所以这套墨字**故意不随明暗切换**：暗色下它是白，亮色
/// 下它还是白。业务侧一律走 [AppSemantic] 上的 `onMedia*` 角色，别在这里加分支，
/// 也别拿主题的 textPrimary 去顶封面——白底卡片一压上去就变成白字白底。
class AppMediaChrome {
  AppMediaChrome._();

  /// 主字/主图标（恒白）
  static const Color ink = Color(0xFFFFFFFF);

  /// 次要字（约 70%）
  static const Color inkSecondary = Color(0xB3FFFFFF);

  /// 弱化字与轨道（约 60%）
  ///
  /// 这里刻意把 54% 与 60% 两档并成一条：两者只差 5 个透明度单位，肉眼分不出，
  /// 留着两档只会让每个调用点各自猜该用哪个。
  static const Color inkTertiary = Color(0x99FFFFFF);

  /// 更弱的提示与角标（约 38%）
  static const Color inkFaint = Color(0x61FFFFFF);

  /// 悬停/选中水洗（约 12%，压在任何画面上都只是"亮一点点"）
  static const Color inkWash = Color(0x1FFFFFFF);

  /// 恒白输入框上的深色墨字（看图器改名框那类：底是白的，字只能是黑的）
  static const Color inkOnLight = Color(0xFF0A0A0A);

  /// 看图/播放舞台底：画面之外的 letterbox
  static const Color stage = Color(0xFF000000);

  /// 封面顶部极弱压暗（渐变起点，只为让白字先有个依托）
  static const Color scrimTrace = Color(0x18000000);

  /// 弱遮罩
  static const Color scrimSoft = Color(0x22000000);

  /// 常规遮罩（黑 54% 档）
  static const Color scrimMedium = Color(0x8A000000);

  /// 强遮罩（黑 87% 档：徽标、浮层按钮底）
  static const Color scrimStrong = Color(0xDE000000);

  /// 渐变收口的两块实心暗底（封面底部字区 / 全屏控制条）
  static const Color scrimFoot = Color(0xAA000000);
  static const Color scrimVeil = Color(0xBB000000);

  /// 沉浸式查看器的黑玻璃面板底
  static const Color immersivePanel = Color(0x6B000000);

  /// 沉浸式面板描边：白 15%，在黑玻璃上才看得出边界
  static const Color immersiveBorder = Color(0x26FFFFFF);
}

/// 品牌紫水洗（Brand Wash）
///
/// 品牌紫退出主色位以后只剩"点缀"这一职：头像/图标底板那层紫洗、以及我方消息
/// 气泡那种要把气泡本身认成"我说的"的量。这类底色必须按主题分档——同一条 12%
/// 水洗压在白卡上刚好、压在暗色表面上几乎看不见，写死单值必坏一边。
class AppBrandWash {
  AppBrandWash._();

  /// 图标/头像底板的紫洗
  static const Color iconLight = Color(0x1FA89FEE);
  static const Color iconDark = Color(0x29A89FEE);

  /// 我方聊天气泡：紫底白字，透明度要压得住画面之外的聊天背景
  static const Color bubbleLight = Color(0xD9A89FEE);
  static const Color bubbleDark = Color(0xE0A89FEE);
}

/// 日志控制台配色（Terminal Chrome）
///
/// 这块区域是一整套"代码编辑器"配色：自己的深底/浅底、自己的语法高亮成套。
/// 故意不并进 [AppSemantic]：界面语义色一改（比如 textSecondary 调灰），
/// 日志正文会跟着失去层次，终端也不再像终端。但字面量不许留在 widget 里——
/// 成套关系只有集中定义才看得出"这三档是一组"。
///
/// 用法：`final t = s.terminal;` 然后 `t.body` / `t.keyword` …
class AppTerminalPalette {
  const AppTerminalPalette({
    required this.screen,
    required this.chromeBorder,
    required this.titleBar,
    required this.titleText,
    required this.timestamp,
    required this.body,
    required this.sourceRust,
    required this.sourceDart,
    required this.keyword,
    required this.path,
    required this.number,
  });

  /// 终端底色
  final Color screen;

  /// 终端外框描边
  final Color chromeBorder;

  /// 标题栏底
  final Color titleBar;

  /// 标题栏路径文字
  final Color titleText;

  /// 时间戳与分隔空格
  final Color timestamp;

  /// 正文
  final Color body;

  /// Rust 侧来源标记
  final Color sourceRust;

  /// Dart 侧来源标记
  final Color sourceDart;

  /// 关键词高亮
  final Color keyword;

  /// 路径高亮
  final Color path;

  /// 数字高亮
  final Color number;

  static const AppTerminalPalette light = AppTerminalPalette(
    screen: Color(0xFFFAFAFA),
    chromeBorder: Color(0xFFE0E0E0),
    titleBar: Color(0xFFE8E8E8),
    titleText: Color(0xFF888888),
    timestamp: Color(0xFFA0A0A0),
    body: Color(0xFF383A42),
    sourceRust: Color(0xFFBE5046),
    sourceDart: Color(0xFF4078F2),
    keyword: Color(0xFF986801),
    path: Color(0xFF50A14F),
    number: Color(0xFFA45200),
  );

  static const AppTerminalPalette dark = AppTerminalPalette(
    screen: Color(0xFF0A0E14),
    chromeBorder: Color(0xFF1A1F29),
    titleBar: Color(0xFF1A1F29),
    titleText: Color(0xFF6C7A89),
    timestamp: Color(0xFF5C6370),
    body: Color(0xFFABB2BF),
    sourceRust: Color(0xFFE06C75),
    sourceDart: Color(0xFF61AFEF),
    keyword: Color(0xFFE5C07B),
    path: Color(0xFF98C379),
    number: Color(0xFFD19A66),
  );

  /// 标题栏那三颗仿终端窗饰灯：恒为红/黄/绿，不跟主题反相
  static const Color windowDotClose = Color(0xFFFF5F56);
  static const Color windowDotMinimize = Color(0xFFFFBD2E);
  static const Color windowDotZoom = Color(0xFF27C93F);
}

/// 阅读页正文的"纸张"预设（Reader Paper）
///
/// 这是用户在阅读设置里自己选的内容底色，属于内容主题而不是界面语义色：
/// 选了羊皮纸就一直是羊皮纸，不该被明暗主题翻成黑。两处阅读器（本机页与
/// 远程弹窗）共用这一份清单，预设与默认值只能有一个出处。
class AppReaderPaper {
  AppReaderPaper._();

  /// 羊皮纸（默认）
  static const Color parchment = Color(0xFFF6F0E7);

  /// 雪纸
  static const Color snow = Color(0xFFFFFFFF);

  /// 淡薄荷
  static const Color mint = Color(0xFFEAF4E8);

  /// 淡天蓝
  static const Color sky = Color(0xFFEAF1F8);

  /// 石墨（深读档）
  static const Color graphite = Color(0xFF1F1F1F);

  /// 选择器铺的这一排，顺序即 UI 顺序
  static const List<Color> presets = [parchment, snow, mint, sky, graphite];
}

