import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/window/window_backdrop.dart';

import 'app_colors.dart';
import 'app_semantics.dart';

const Loggers _logger = Loggers(name: '主题');

/// 全局度量快捷方式。
///
/// 必须写成 getter：历史上它是一个 `static final` 快照，而 [AppTheme.resetMetrics]
/// 只替换 `AppTheme.metrics`，导致 310 处 `appMetrics.x` 在窗口缩放后仍使用旧值。
ThemeMetrics get appMetrics => AppTheme.metrics;

class AppTheme {
  AppTheme._();

  static ThemeMode themeMode = ThemeMode.system;

  // ── 响应式主题状态（ThemeSettingsTab 写入，MyApp.build 读取）──────────────
  static final Rx<ThemeMode> themeModeObs = ThemeMode.system.obs;

  /// 「跟随主题」这一档强调色：设置页的默认选项。
  ///
  /// 它不是一个真颜色——明暗两档的近黑不同值，只能由语义层分别给，
  /// 所以这个值只当哨兵用，见 `_applyCustomization` 里的短路。
  static const Color kFollowThemeAccent = AppBrand.ink;

  static final Rx<Color> accentColorObs = kFollowThemeAccent.obs;
  static final RxDouble fontScaleObs = 1.0.obs;

  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _fontScaleKey = 'font_scale';

  /// 界面主字体族名（西文）。
  ///
  /// ThemeData.fontFamily 只喂给 ThemeData 自己生成的那份 textTheme；一旦
  /// copyWith 换成手写 TextTheme 就会丢，全站静默回退到系统字体。所以字阶
  /// 构建完必须显式 apply 一次。
  static const String _fontFamily = 'Inter';

  /// Inter 不含 CJK 字形，中文/日文/韩文按这份顺序落到系统字。
  ///
  /// 不写这份清单也能显示（引擎自己兜底找系统字），但找到的字重和 Inter 对不上，
  /// 中英混排会跳粗细，所以显式钉住。末尾再挂一份项目自带的中文字体：系统字
  /// 一个都没匹配上时（headless 出图、精简过的 Android 字库）由它兜底，否则
  /// 整页中文会变成豆腐块。
  static const List<String> _fontFamilyFallback = [
    'PingFang SC',
    'Hiragino Sans GB',
    'Microsoft YaHei',
    'Noto Sans SC',
    'FZLanTingYuanS-EB-GB',
    'sans-serif',
  ];

  /// 等宽字族（日志/路径/代码）。
  ///
  /// 项目没打包等宽字体，只能按平台各自的内置名点：主点是 macOS 的 Menlo，Windows
  /// 走 Consolas、Linux 常见 DejaVu Sans Mono——主点在这些平台上不存在，由回退清单
  /// 顶上；写死单值就等于让另两个平台落到引擎兜底字上。末尾再接一份中文字族：
  /// 日志里混着中文，等宽字没有 CJK 字形，不接就变豆腐块。
  static const String _monoFontFamily = 'Menlo';
  static const List<String> _monoFontFamilyFallback = [
    'Consolas',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'monospace',
    ..._fontFamilyFallback,
  ];

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

  /// 把用户自选的强调色与字号缩放套用回基础主题。
  ///
  /// 重点：自定义色必须同步注入 [AppSemantic]，否则所有走语义层的组件
  /// 仍然显示默认紫，只有老代码跟随——这正是"改了主题色但很多地方不变"的成因。
  static ThemeData _applyCustomization(ThemeData base, Color accent, double scale) {
    final isDark = base.brightness == Brightness.dark;
    final semantic = base.extension<AppSemantic>() ?? (isDark ? AppSemantic.dark : AppSemantic.light);

    // 用户可能选到一个很浅（或很深）的颜色。规则统一为：强调色必须先在其所属
    // 模式的表面上足够醒目，再据此决定它上面放黑字还是白字。
    // 若反过来固定用白字，暗色模式下会被压成一个发黑的紫块——正是原来的表现问题。
    //
    // 「跟随主题」例外：近黑在明暗两档是两个值（浅色压黑、深色提到浅灰），
    // 自选色只有一个值，硬把 #171717 送进 _ensureContrast 会在暗色档被提成中灰。
    final followTheme = accent.toARGB32() == kFollowThemeAccent.toARGB32();
    final fill = followTheme
        ? semantic.accent
        : _ensureContrast(accent, semantic.surface);
    final onAccent = _contrastColor(fill);
    final accentText = fill;

    final cs = base.colorScheme.copyWith(
      primary: fill,
      secondary: fill,
      onPrimary: onAccent,
      surface: semantic.surface,
    );

    final themed = base.copyWith(
      colorScheme: cs,
      primaryColor: fill,
      extensions: [
        ...base.extensions.values,
        semantic.copyWith(
          accent: fill,
          accentOn: onAccent,
          accentText: accentText,
          accentContainer: Color.alphaBlend(fill.withValues(alpha: isDark ? 0.18 : 0.10), cs.surface),
          accentContainerBorder: fill.withValues(alpha: isDark ? 0.34 : 0.26),
        ),
      ],
    );

    return themed.copyWith(
      appBarTheme: themed.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: themed.tabBarTheme.copyWith(
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: fill, width: AppTheme.metrics.strokeEmphasis),
        ),
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurface.withValues(alpha: 0.55),
      ),
      textTheme: _scaleTextTheme(base.textTheme, scale),
      primaryTextTheme: _scaleTextTheme(base.primaryTextTheme, scale),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(fill, onAccent)),
      filledButtonTheme: FilledButtonThemeData(style: _filledButton(fill, onAccent)),
      textButtonTheme: TextButtonThemeData(style: _textButton(accentText)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedButton(accentText, semantic.border),
      ),
      sliderTheme: themed.sliderTheme.copyWith(thumbColor: fill, activeTrackColor: fill),
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

  static Color _contrastColor(Color c) =>
      c.computeLuminance() > 0.52 ? Colors.black : Colors.white;

  /// 调整 [c] 的明度，直到它与 [background] 的对比度达到 [target]（默认 4.5:1）。
  ///
  /// 用户自选主题色时这是必需的：软紫 #A89FEE 铺在白底上对比度只有 1.9，
  /// 直接当文字色或按钮底色就会"看着发灰、看不清"。
  static Color _ensureContrast(Color c, Color background, {double target = 4.5}) {
    // 背景偏亮则把 c 往黑压，偏暗则往白提。
    final towardWhite = background.computeLuminance() < 0.5;
    var result = c;
    for (var i = 0; i < 12; i++) {
      if (_contrastRatio(result, background) >= target) return result;
      result = Color.lerp(
        result,
        towardWhite ? Colors.white : Colors.black,
        0.1,
      )!;
    }
    return result;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (la + 0.05) / (lb + 0.05) < 1 ? (lb + 0.05) / (la + 0.05) : (la + 0.05) / (lb + 0.05);
  }

  // ── 度量 ──
  static ThemeMetrics metrics = ThemeMetrics();
  static RxInt metricsVersion = 0.obs;

  // ── 组件主题片段（明暗共用同一套结构，只有颜色不同） ──────────────
  // 历史上明暗两份主题是各写一遍的，暗色 OutlinedButton 里出现 LightColors.primary
  // 就是这么来的。改为单一定义、颜色从语义层取，结构上杜绝此类漂移。

  /// 按钮文字样式。
  ///
  /// 字族必须写全：ButtonStyle.textStyle 是整条替换而不是叠加，裸 TextStyle
  /// 会把主题字阶里的 fontFamily/fontFamilyFallback 顶掉，按钮中文就成了
  /// 引擎兜底字（出图环境里直接是豆腐块）。
  static TextStyle _buttonTextStyle() => TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFamilyFallback,
    fontSize: scaleS(13),
    fontWeight: FontWeight.w500,
    height: 1.2,
    letterSpacing: 0.2,
  );

  /// 给组件主题里手写的样式补上字族。
  ///
  /// 组件主题（按钮/对话框/菜单/列表项…）的 textStyle 是整条替换而不是叠加，
  /// 裸 TextStyle 拿不到主题字阶的 fontFamily 与回退清单，中文会静默落到
  /// 引擎兜底字上——出图环境里就是豆腐块。
  static TextStyle _font(TextStyle t) =>
      t.apply(fontFamily: _fontFamily, fontFamilyFallback: _fontFamilyFallback);

  /// 输入框正文的字号档：控件档 13、行高 1.4。
  ///
  /// 为什么只能从这里发出去：Material 3 的输入正文固定继承 `textTheme.bodyLarge`
  /// （本项目 14 / 行高 1.7），而 `InputDecorationTheme` **没有** `style` 这一档，
  /// 主题层根本管不到它——只有 `TextField.style` 能改。于是正文由 [AppTextField]
  /// 统一发出这一条，主题的 hint/label 也用它，打字前后才是同一个字号。
  ///
  /// 字号必须走 metrics.fontSize*（含用户字号）而不是 scaleS：bodyLarge 已经被
  /// _scaleTextTheme 乘过用户字号，scaleS 没有——字号滑杆一拉，打进去的字跟着变大、
  /// 占位符原地不动。行高压到 1.4 是为了让 contentPadding 反推出的框高与同排按钮齐平。
  static TextStyle get fieldTextStyle => _font(
    TextStyle(
      fontSize: metrics.fontSize13,
      height: 1.4,
      fontWeight: FontWeight.w400,
    ),
  );

  /// 输入框的占位/标签样式：与 [fieldTextStyle] 同档，只换颜色。
  static TextStyle _fieldLabelStyle(AppSemantic s, Color color) =>
      fieldTextStyle.apply(color: color);

  static ButtonStyle _elevatedButton(Color fill, Color on) => ElevatedButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: on,
    elevation: 0,
    padding: EdgeInsets.symmetric(
      horizontal: metrics.kSpace18,
      vertical: metrics.kSpace10,
    ),
    minimumSize: Size(scaleW(0), metrics.kSpace32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: metrics.radiusControl),
    textStyle: _buttonTextStyle(),
  );

  static ButtonStyle _filledButton(Color fill, Color on) => FilledButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: on,
    elevation: 0,
    padding: EdgeInsets.symmetric(
      horizontal: metrics.kSpace18,
      vertical: metrics.kSpace10,
    ),
    minimumSize: Size(scaleW(0), metrics.kSpace32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: metrics.radiusControl),
    textStyle: _buttonTextStyle(),
  );

  static ButtonStyle _textButton(Color accentText) => TextButton.styleFrom(
    foregroundColor: accentText,
    // 注意：文字按钮不应带描边，历史上这里加了 side 导致 134 处看起来像线框按钮。
    padding: EdgeInsets.symmetric(
      horizontal: metrics.kSpace12,
      vertical: metrics.kSpace8,
    ),
    minimumSize: Size(scaleW(0), metrics.kSpace32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: metrics.radiusControl),
    textStyle: _buttonTextStyle(),
  );

  static ButtonStyle _outlinedButton(Color accentText, Color borderColor) =>
      OutlinedButton.styleFrom(
        foregroundColor: accentText,
        side: BorderSide(color: borderColor, width: metrics.strokeHairline),
        padding: EdgeInsets.symmetric(
          horizontal: metrics.kSpace18,
          vertical: metrics.kSpace10,
        ),
        minimumSize: Size(scaleW(0), metrics.kSpace32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: metrics.radiusControl),
        textStyle: _buttonTextStyle(),
      );

  /// 亮色主题
  static ThemeData get lightTheme => _buildBase(AppSemantic.light);

  /// 暗色主题
  static ThemeData get darkTheme => _buildBase(AppSemantic.dark);

  // ── 系统状态栏配色（移动端）──────────────────────────────────────────
  // 必须显式钉住主题，不能交给 Material 去猜：本项目的 AppBar 底色是
  // transparent，AppBar 会用 `estimateBrightnessForColor(transparent)` 推断
  // 背景明暗，透明色亮度为 0 → 当成深色背景 → 无论亮色还是暗色主题都发白色
  // 图标，亮色主题下时间/电量直接糊在白底上看不见。
  // 只声明 statusBar* 三项，导航条字段留空，免得 AppBar 的 AnnotatedRegion
  // 顺手把底部导航条刷成不透明白/黑。

  /// 亮色主题：浅色页面配近黑图标。
  static const SystemUiOverlayStyle _statusBarLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  /// 暗色主题：深色页面配白色图标。
  static const SystemUiOverlayStyle _statusBarDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  );

  /// 唯一的主题构建入口：明暗只在 [AppSemantic] 里不同，结构完全一致。
  static ThemeData _buildBase(AppSemantic s) {
    final m = metrics;
    final accent = s.accent;
    final onAccent = s.accentOn;

    final base = ThemeData(
      useMaterial3: true,
      brightness: s.isDark ? Brightness.dark : Brightness.light,
      fontFamily: _fontFamily,
    );

    return base.copyWith(
      primaryColor: accent,
      scaffoldBackgroundColor: s.canvas,
      // canvasColor 是"没有显式声明颜色的 Material 的默认底色"。本项目所有表面
      // 都必须走 AppSemantic 显式取色，所以这里留透明：任何漏配颜色的 Material
      // 只会画不出来，不会像之前那样在窗口最底下铺一层不透明白，把 macOS 的
      // 窗口透出/磨砂彻底挡死（flutter_easyloading 的根 Material 就是受害者）。
      canvasColor: Colors.transparent,
      splashColor: accent.withValues(alpha: 0.06),
      highlightColor: accent.withValues(alpha: 0.04),
      shadowColor: s.isDark ? DarkColors.black100 : LightColors.black100,
      hoverColor: s.surfaceHover,
      focusColor: accent.withValues(alpha: 0.18),
      disabledColor: s.textDisabled,
      hintColor: s.textTertiary,
      dividerColor: s.hairline,
      // InkRipple 比 InkSparkle 安静，适合工具类界面
      splashFactory: InkRipple.splashFactory,

      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: s.isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        surface: s.surface,
        onSurface: s.textPrimary,
        surfaceContainerLowest: s.surfaceSunken,
        surfaceContainerLow: s.surface,
        surfaceContainer: s.surface,
        surfaceContainerHigh: s.surfaceRaised,
        surfaceContainerHighest: s.surfaceRaised,
        outline: s.border,
        outlineVariant: s.hairline,
        error: s.danger.color,
        onError: Colors.white,
        errorContainer: s.danger.container,
        onErrorContainer: s.danger.onContainer,
        scrim: s.scrim,
      ),

      extensions: [s],

      // ── 应用栏：底色交给页面自己控制，避免与磨砂层叠加出双层背景 ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: s.textPrimary,
        // 状态栏图标配色跟着主题走：亮色压黑、暗色提白（见 _statusBarLight 注释）
        systemOverlayStyle: s.isDark ? _statusBarDark : _statusBarLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: _font(TextStyle(
          fontSize: scaleS(16),
          fontWeight: FontWeight.w600,
          color: s.textPrimary,
          height: 1.4,
        )),
        iconTheme: IconThemeData(color: s.textSecondary, size: m.iconSize20),
      ),

      // ── 卡片：修复原先"白底 + white80 描边"不可见 / 暗色刺眼的问题 ──
      cardTheme: CardThemeData(
        color: s.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: m.radiusCard,
          side: BorderSide(color: s.hairline, width: m.strokeHairline),
        ),
      ),

      // ── 排版：明暗共用同一份定义，字重不再两边不一致 ──
      textTheme: _textTheme(s),

      // ── 按钮：四档（主/填充/文字/线框）共用同一圆角与内距，只差配色 ──
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedButton(accent, onAccent)),
      filledButtonTheme: FilledButtonThemeData(style: _filledButton(accent, onAccent)),
      textButtonTheme: TextButtonThemeData(style: _textButton(s.accentText)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedButton(s.accentText, s.border),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: s.textSecondary,
          highlightColor: s.surfaceHover,
          hoverColor: s.surfaceHover,
          padding: EdgeInsets.all(m.kSpace6),
          shape: RoundedRectangleBorder(borderRadius: m.radiusControl),
        ),
      ),

      // ── 输入框 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceSunken,
        isDense: true,
        hintStyle: _fieldLabelStyle(s, s.textTertiary),
        labelStyle: _fieldLabelStyle(s, s.textSecondary),
        // 浮起的标签会被 Flutter 再乘一档 0.75 缩放矩阵，所以这里给 16：
        // 落到边框上的实际字号才是基准的 12 一档（配 scaleS(12) 会缩成 9）。
        floatingLabelStyle: _fieldLabelStyle(s, s.accentText).copyWith(
          fontSize: m.fontSize16,
        ),
        border: OutlineInputBorder(
          borderRadius: m.radiusField,
          borderSide: BorderSide(color: s.border, width: m.strokeHairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: m.radiusField,
          borderSide: BorderSide(color: s.hairline, width: m.strokeHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: m.radiusField,
          borderSide: BorderSide(color: s.accent, width: m.strokeThin),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: m.radiusField,
          borderSide: BorderSide(color: s.danger.color, width: m.strokeHairline),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: m.radiusField,
          borderSide: BorderSide(color: s.danger.color, width: m.strokeThin),
        ),
        // 框高 = 上下内距 ×2 + 行高(fontSize13 × 1.4) + 两条边框 ≈ 38，
        // 和同排按钮的自然高（kSpace10 ×2 + fontSize13 × 1.2）落在同一档。
        // 原先这里配 kSpace10，正文却又继承 bodyLarge 的 1.7 行高，实际撑到 ~46，
        // 输入框永远比它旁边的按钮高出一截。
        contentPadding: EdgeInsets.symmetric(
          horizontal: m.kSpace12,
          vertical: m.kSpace8,
        ),
      ),

      // ── 图标 ──
      iconTheme: IconThemeData(color: s.textSecondary, size: m.iconSize20),
      primaryIconTheme: IconThemeData(color: s.textPrimary, size: m.iconSize20),

      // ── 分割线 ──
      dividerTheme: DividerThemeData(
        color: s.hairline,
        thickness: m.strokeHairline,
        space: scaleW(1),
      ),

      // ── 浮层 / 弹窗 ──
      // 浮层统一按 WindowGlass.overlayAlpha 留一点透明度：完全实心就没有任何层次，
      // 但也不能太透——菜单/对话框底下就是页面的文字，糊在一起读不了。
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceRaised.withAlpha(WindowGlass.overlayAlpha),
        surfaceTintColor: Colors.transparent,
        // 和菜单同一个道理：对话框是压在整页之上的最高一层，靠投影而不是亮度分层。
        elevation: scaleW(16),
        shadowColor: s.shadowKey,
        shape: RoundedRectangleBorder(
          borderRadius: m.radiusOverlay,
          side: BorderSide(color: s.glassBorder, width: m.strokeHairline),
        ),
        titleTextStyle: _font(TextStyle(
          fontSize: scaleS(16),
          fontWeight: FontWeight.w600,
          color: s.textPrimary,
        )),
        contentTextStyle: _font(TextStyle(
          fontSize: scaleS(13),
          height: 1.6,
          color: s.textSecondary,
        )),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceRaised.withAlpha(WindowGlass.overlayAlpha),
        surfaceTintColor: Colors.transparent,
        elevation: scaleW(10),
        shadowColor: s.shadowKey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(m.radiusOverlay.topLeft.x),
          ),
          side: BorderSide(color: s.glassBorder, width: m.strokeHairline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.surfaceRaised.withAlpha(WindowGlass.overlayAlpha),
        surfaceTintColor: Colors.transparent,
        // 菜单原来 elevation 0，贴在页面上像一个被裁出来的洞，完全分不出前后层次。
        // 浮层要靠自己那层投影站起来，而不是靠自己变亮。
        elevation: scaleW(8),
        shadowColor: s.shadowKey,
        shape: RoundedRectangleBorder(
          borderRadius: m.radiusPanel,
          side: BorderSide(color: s.glassBorder, width: m.strokeHairline),
        ),
        // M3 下菜单项文字走 labelTextStyle，textStyle 只参与旧渲染路径；两处都写，
        // 免得一改 useMaterial3 就发现菜单字号又飘回 SDK 默认值。
        // 字族由 _font 统一补，见其注释。
        // 字号必须走 metrics 而不是裸 scaleS：右键菜单挂在资源卡上，卡片标题是
        // metrics.fontSize13（含用户字号），这里用 scaleS(13) 的话字号滑杆一拉，
        // 菜单文字就比它服务的那张卡小一圈。行高同理是下限，不会挤。
        textStyle: _font(TextStyle(
          fontSize: m.fontSize13,
          color: s.textPrimary,
        )),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => _font(TextStyle(
            fontSize: m.fontSize13,
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: states.contains(WidgetState.disabled)
                ? s.textDisabled
                : s.textPrimary,
          )),
        ),
        // 默认只有 vertical:8，高亮条会一路顶到圆角边缘。四周留一圈，菜单立刻
        // 像"卡片里装着条目"而不是"一块色皮"。
        menuPadding: EdgeInsets.symmetric(
          horizontal: m.kSpace4,
          vertical: m.kSpace4,
        ),
        iconColor: s.textSecondary,
        iconSize: m.iconSize16,
        // 桌面端菜单项一律手型指针；原来是个别调用点自己裹 MouseRegion，漏一处就不一致。
        mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: s.isDark ? AppSurfaces.darkSurfaceRaised : AppSurfaces.lightTextPrimary,
          borderRadius: m.radius6,
        ),
        textStyle: _font(TextStyle(
          fontSize: scaleS(11),
          color: s.isDark ? AppSurfaces.darkTextPrimary : Colors.white,
        )),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
        waitDuration: const Duration(milliseconds: 500),
      ),

      // ── 导航 ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: s.accentContainer,
        selectedIconTheme: IconThemeData(color: s.accent),
        unselectedIconTheme: IconThemeData(color: s.textTertiary),
        selectedLabelTextStyle: _font(TextStyle(
          fontSize: scaleS(12),
          fontWeight: FontWeight.w600,
          color: s.accentText,
        )),
        unselectedLabelTextStyle: _font(TextStyle(fontSize: scaleS(12), color: s.textTertiary)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.accentContainer,
        elevation: 0,
        height: m.kSpace56,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => _font(TextStyle(
            fontSize: scaleS(11),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? s.accentText : s.textTertiary,
          )),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        labelColor: s.textPrimary,
        unselectedLabelColor: s.textTertiary,
        labelStyle: _font(TextStyle(fontSize: scaleS(13), fontWeight: FontWeight.w600)),
        unselectedLabelStyle: _font(TextStyle(fontSize: scaleS(13), fontWeight: FontWeight.w500)),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: s.accentContainer,
          borderRadius: m.radiusControl,
          border: Border.all(color: s.accentContainerBorder, width: m.strokeHairline),
        ),
      ),

      // ── 列表 ──
      listTileTheme: ListTileThemeData(
        iconColor: s.textSecondary,
        textColor: s.textPrimary,
        titleTextStyle: _font(TextStyle(
          fontSize: scaleS(13),
          fontWeight: FontWeight.w500,
          color: s.textPrimary,
        )),
        subtitleTextStyle: _font(TextStyle(fontSize: scaleS(12), color: s.textSecondary)),
        shape: RoundedRectangleBorder(borderRadius: m.radiusControl),
        contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
      ),

      // ── 选择控件 ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : s.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : s.surfaceSunken,
        ),
        trackOutlineColor: WidgetStatePropertyAll(s.hairline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(onAccent),
        side: BorderSide(color: s.borderStrong, width: m.strokeThin),
        shape: RoundedRectangleBorder(borderRadius: m.radius4),
        splashRadius: 0,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : s.textTertiary,
        ),
      ),
      sliderTheme: SliderThemeData(
        thumbColor: accent,
        activeTrackColor: accent,
        inactiveTrackColor: s.surfaceSunken,
        overlayColor: accent.withValues(alpha: 0.12),
        trackHeight: scaleW(4),
      ),

      // ── 标签 / 进度 ──
      chipTheme: ChipThemeData(
        backgroundColor: s.surfaceSunken,
        selectedColor: s.accentContainer,
        side: BorderSide(color: s.hairline, width: m.strokeHairline),
        shape: RoundedRectangleBorder(borderRadius: m.radiusPill),
        labelStyle: _font(TextStyle(
          fontSize: scaleS(12),
          fontWeight: FontWeight.w500,
          color: s.textSecondary,
        )),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: s.surfaceSunken,
        circularTrackColor: s.surfaceSunken,
      ),

      // ── 滚动条 ──
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(s.textTertiary.withValues(alpha: 0.28)),
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
        mainAxisMargin: 4,
        crossAxisMargin: 3,
      ),

      // ── 其它 ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: s.isDark ? AppSurfaces.darkSurfaceRaised : AppSurfaces.lightTextPrimary,
        contentTextStyle: _font(TextStyle(
          fontSize: scaleS(13),
          color: s.isDark ? s.textPrimary : Colors.white,
        )),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: m.radiusControl),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? s.accentContainer : Colors.transparent,
          ),
          foregroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? s.accentText : s.textSecondary,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: s.hairline, width: m.strokeHairline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: m.radiusControl),
          ),
          textStyle: WidgetStatePropertyAll(
            _font(TextStyle(fontSize: scaleS(12), fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }

  /// 单一来源的字阶定义（明暗共用，只换色）
  static TextTheme _textTheme(AppSemantic s) {
    return TextTheme(
      displayLarge: TextStyle(
        fontSize: scaleS(32),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.25,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: scaleS(26),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.3,
      ),
      displaySmall: TextStyle(
        fontSize: scaleS(22),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.35,
      ),
      headlineLarge: TextStyle(
        fontSize: scaleS(20),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.4,
      ),
      headlineMedium: TextStyle(
        fontSize: scaleS(18),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.45,
      ),
      headlineSmall: TextStyle(
        fontSize: scaleS(16),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.5,
      ),
      titleLarge: TextStyle(
        fontSize: scaleS(15),
        fontWeight: FontWeight.w600,
        color: s.textPrimary,
        height: 1.5,
      ),
      titleMedium: TextStyle(
        fontSize: scaleS(14),
        fontWeight: FontWeight.w500,
        color: s.textPrimary,
        height: 1.55,
      ),
      titleSmall: TextStyle(
        fontSize: scaleS(13),
        fontWeight: FontWeight.w600,
        color: s.textSecondary,
        height: 1.5,
      ),
      bodyLarge: TextStyle(
        fontSize: scaleS(14),
        fontWeight: FontWeight.w400,
        color: s.textPrimary,
        height: 1.7,
      ),
      bodyMedium: TextStyle(
        fontSize: scaleS(13),
        fontWeight: FontWeight.w400,
        color: s.textSecondary,
        height: 1.65,
      ),
      bodySmall: TextStyle(
        fontSize: scaleS(12),
        fontWeight: FontWeight.w400,
        color: s.textTertiary,
        height: 1.6,
      ),
      labelLarge: TextStyle(
        fontSize: scaleS(13),
        fontWeight: FontWeight.w500,
        color: s.textPrimary,
        height: 1.2,
        letterSpacing: 0.2,
      ),
      labelMedium: TextStyle(
        fontSize: scaleS(12),
        fontWeight: FontWeight.w500,
        color: s.textSecondary,
        height: 1.4,
      ),
      labelSmall: TextStyle(
        fontSize: scaleS(11),
        fontWeight: FontWeight.w600,
        color: s.textTertiary,
        height: 1.5,
        letterSpacing: 0.6,
      ),
    ).apply(fontFamily: _fontFamily, fontFamilyFallback: _fontFamilyFallback);
  }

  static bool isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }

  /// 侧边栏底色。
  ///
  /// 不用玻璃 tint：它在浅色模式合成后接近纯白，和卡片同色，侧栏读不出是
  /// 一个独立面板。保留 LinearGradient 返回类型是为了兼容调用方，两帧同色即纯色。
  static LinearGradient sideBarTheme(BuildContext context, {int alpha = 255}) {
    final s = AppSemantic.of(context);
    // 侧栏与内容区同底（画布色），只靠一条发丝线分栏；选中项抬成 surface 白卡，
    // 对比关系才成立——用 sunken 底会让白卡和栏底糊成一片。
    final tint = s.canvas.withAlpha(alpha);
    return LinearGradient(
      colors: [tint, tint],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  static void resetMetrics() {
    _logger.info('[主题] 重新计算界面尺寸中...');
    metrics = ThemeMetrics();
    metricsVersion.value++;
  }
}

/// 语义化文本样式（供共享组件与业务页面复用）
///
/// 项目规范文档一直引用 `AppTextStyles`，但此前并不存在——各页面因此各自
/// 手搭字号/字重组合，形成 12 种"小节标题"。这里补齐，作为唯一的文本角色来源。
class AppTextStyles {
  AppTextStyles._();

  /// 页面主标题
  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium!;

  /// 所有手写样式的统一出口。
  ///
  /// 必须从主题字阶派生而不是裸 `TextStyle(...)`：裸构造会丢 fontFamily，
  /// 项目自带字体就不生效了（历史上正是这个原因全站静默回退到系统字体）。
  static TextStyle _role(
    BuildContext context, {
    required double fontSize,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) => Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontSize: fontSize,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
  );

  /// 页面里"不属于那 9 个固定角色"的手写样式出口。
  ///
  /// 和 [_role] 一样从字阶派生，因此一定带上 fontFamily 与中文回退清单；
  /// 字号一律传 `AppTheme.metrics.fontSizeN`，颜色传 `AppSemantic.of(context)` 的角色。
  ///
  /// `decoration` 是给"划掉/下划线"这类只改修饰的调用点留的：以前只能
  /// `role(...).copyWith(decoration: ...)`，多写一次 copyWith 就多一个能跑偏的地方。
  static TextStyle role(
    BuildContext context, {
    required double fontSize,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) => _role(
    context,
    fontSize: fontSize,
    color: color,
    weight: weight,
    height: height,
    letterSpacing: letterSpacing,
    decoration: decoration,
  );

  /// 小节标题（原 12 种变体统一到此）
  static TextStyle sectionTitle(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize15,
    weight: FontWeight.w600,
    color: AppSemantic.of(context).textPrimary,
    height: 1.45,
    letterSpacing: 0.1,
  );

  /// 卡片标题
  static TextStyle cardTitle(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize13,
    weight: FontWeight.w600,
    color: AppSemantic.of(context).textPrimary,
    height: 1.45,
  );

  /// 列表行标题
  ///
  /// 和 cardTitle 差一档字重：整页卡片标题需要撑住区块，列表行里几十条同名行
  /// 用 w600 会糊成一片黑。数值与 listTileTheme.titleTextStyle 保持同档。
  static TextStyle rowTitle(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize13,
    weight: FontWeight.w500,
    color: AppSemantic.of(context).textPrimary,
    height: 1.4,
  );

  /// 正文
  static TextStyle body(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize13,
    color: AppSemantic.of(context).textSecondary,
    height: 1.6,
  );

  /// 次要说明文字
  static TextStyle caption(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize11,
    color: AppSemantic.of(context).textTertiary,
    height: 1.5,
  );

  /// 分组标签 / 全大写小字（原侧边栏分组标题风格）
  static TextStyle overline(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize10,
    weight: FontWeight.w600,
    color: AppSemantic.of(context).textTertiary,
    height: 1.4,
    letterSpacing: 0.9,
  );

  /// 数据大屏数字
  static TextStyle metric(BuildContext context) => _role(
    context,
    fontSize: AppTheme.metrics.fontSize28,
    weight: FontWeight.w600,
    color: AppSemantic.of(context).textPrimary,
    height: 1.15,
    letterSpacing: -0.4,
  );

  /// 等宽（日志/路径/代码）
  ///
  /// 字族走 [AppTheme] 那套平台等宽清单，颜色默认次要字，控制台这类
  /// 需要自带配色的地方传 `color`。
  static TextStyle mono(BuildContext context, {double? size, Color? color}) {
    return TextStyle(
      fontFamily: AppTheme._monoFontFamily,
      fontFamilyFallback: AppTheme._monoFontFamilyFallback,
      fontSize: size ?? AppTheme.metrics.fontSize12,
      fontWeight: FontWeight.w400,
      color: color ?? AppSemantic.of(context).textSecondary,
      height: 1.55,
    );
  }
}

class ThemeMetrics {
  final BorderRadius radius2;
  final BorderRadius radius3;
  final BorderRadius radius4;
  final BorderRadius radius6;
  final BorderRadius radius8;
  final BorderRadius radius10;
  final BorderRadius radius12;
  final BorderRadius radius14;
  final BorderRadius radius16;
  final BorderRadius radius18;
  final BorderRadius radius20;
  final BorderRadius radius22;
  final BorderRadius radius24;
  final BorderRadius radius25;
  final BorderRadius radius28;
  final BorderRadius radius32;
  final BorderRadius radius40;
  final BorderRadius radius100;
  final BorderRadius radius999;

  // ── 语义圆角：调用点应优先使用这一组，而不是记数字 ──
  /// 按钮 / 输入框等控件
  final BorderRadius radiusControl;

  /// 文本输入框
  final BorderRadius radiusField;

  /// 卡片 / 列表项
  final BorderRadius radiusCard;

  /// 面板 / 分栏容器
  final BorderRadius radiusPanel;

  /// 弹窗 / 抽屉等浮层
  final BorderRadius radiusOverlay;

  /// 胶囊（标签、徽标）
  final BorderRadius radiusPill;

  final double fontSize9;
  final double fontSize10;
  final double fontSize11;
  final double fontSize12;
  final double fontSize13;
  final double fontSize14;
  final double fontSize15;
  final double fontSize16;
  final double fontSize17;
  final double fontSize18;
  final double fontSize20;
  final double fontSize22;
  final double fontSize24;
  final double fontSize28;
  final double fontSize32;
  final double fontSize36;
  final double fontSize48;
  final double fontSize72;

  final double kSpace1;
  final double kSpace2;
  final double kSpace3;
  final double kSpace4;
  final double kSpace5;
  final double kSpace6;
  final double kSpace8;
  final double kSpace10;
  final double kSpace12;
  final double kSpace14;
  final double kSpace16;
  final double kSpace18;
  final double kSpace20;
  final double kSpace24;
  final double kSpace32;
  final double kSpace40;
  final double kSpace44;
  final double kSpace48;
  final double kSpace56;
  final double kSpace64;
  final double kSpace80;

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

  final double iconSize12;
  final double iconSize13;
  final double iconSize14;
  final double iconSize15;
  final double iconSize16;
  final double iconSize18;
  final double iconSize20;
  final double iconSize22;
  final double iconSize24;
  final double iconSize28;
  final double iconSize32;
  final double iconSize40;
  final double iconSize44;
  final double iconSize48;
  final double iconSize64;
  final double iconSize96;

  // ── 描边宽度：一律固定值，不吃窗口缩放（DESIGN.md §3.3）──
  /// 发丝线：缩放后不足 1 物理像素就会被抗锯齿冲淡成灰边，所以钉死 1
  final double strokeHairline;

  /// 半根发丝：Retina 上正好 1 物理像素，用于 Divider 这类极细分隔
  final double strokeUltraThin;

  /// 细描边：小尺寸进度环、图标底板描边
  final double strokeThin;

  /// 常规描边：进度环、选中环
  final double strokeRegular;

  /// 加重描边：要压在画面上仍然看得清的环与条（2.0 在封面上会细成一条线）
  final double strokeEmphasis;

  /// 粗描边：需要压住画面的环形/条形指示
  final double strokeBold;

  final BoxShadow boxShadow10;

  ThemeMetrics()
    : radius2 = BorderRadius.all(Radius.circular(scaleW(2.r))),
      radius3 = BorderRadius.all(Radius.circular(scaleW(3.r))),
      radius4 = BorderRadius.all(Radius.circular(scaleW(4.r))),
      radius6 = BorderRadius.all(Radius.circular(scaleW(6.r))),
      radius8 = BorderRadius.all(Radius.circular(scaleW(8.r))),
      radius10 = BorderRadius.all(Radius.circular(scaleW(10.r))),
      radius12 = BorderRadius.all(Radius.circular(scaleW(12.r))),
      radius14 = BorderRadius.all(Radius.circular(scaleW(14.r))),
      radius16 = BorderRadius.all(Radius.circular(scaleW(16.r))),
      radius18 = BorderRadius.all(Radius.circular(scaleW(18.r))),
      radius20 = BorderRadius.all(Radius.circular(scaleW(20.r))),
      radius22 = BorderRadius.all(Radius.circular(scaleW(22.r))),
      radius24 = BorderRadius.all(Radius.circular(scaleW(24.r))),
      radius25 = BorderRadius.all(Radius.circular(scaleW(25.r))),
      radius28 = BorderRadius.all(Radius.circular(scaleW(28.r))),
      radius32 = BorderRadius.all(Radius.circular(scaleW(32.r))),
      radius40 = BorderRadius.all(Radius.circular(scaleW(40.r))),
      radius100 = BorderRadius.all(Radius.circular(scaleW(100.r))),
      radius999 = BorderRadius.all(Radius.circular(scaleW(999.r))),

      // 语义圆角整体收小：控件与输入框同为一档，卡片只比控件多两像素。
      // 圆角一大，小尺寸控件就变成一颗颗胶囊，列表也读不出边界。
      radiusControl = BorderRadius.all(Radius.circular(scaleW(8.r))),
      radiusField = BorderRadius.all(Radius.circular(scaleW(8.r))),
      radiusCard = BorderRadius.all(Radius.circular(scaleW(10.r))),
      radiusPanel = BorderRadius.all(Radius.circular(scaleW(14.r))),
      radiusOverlay = BorderRadius.all(Radius.circular(scaleW(14.r))),
      radiusPill = BorderRadius.all(Radius.circular(scaleW(999.r))),

      iconSize12 = scaleSWithUserFont(12),
      iconSize13 = scaleSWithUserFont(13),
      iconSize14 = scaleSWithUserFont(14),
      iconSize15 = scaleSWithUserFont(15),
      iconSize16 = scaleSWithUserFont(16),
      iconSize18 = scaleSWithUserFont(18),
      iconSize20 = scaleSWithUserFont(20),
      iconSize22 = scaleSWithUserFont(22),
      iconSize24 = scaleSWithUserFont(24),
      iconSize28 = scaleSWithUserFont(28),
      iconSize32 = scaleSWithUserFont(32),
      iconSize40 = scaleSWithUserFont(40),
      iconSize44 = scaleSWithUserFont(44),
      iconSize48 = scaleSWithUserFont(48),
      iconSize64 = scaleSWithUserFont(64),
      iconSize96 = scaleSWithUserFont(96),

      fontSize9 = scaleSWithUserFont(9),
      fontSize10 = scaleSWithUserFont(10),
      fontSize11 = scaleSWithUserFont(11),
      fontSize12 = scaleSWithUserFont(12),
      fontSize13 = scaleSWithUserFont(13),
      fontSize14 = scaleSWithUserFont(14),
      fontSize15 = scaleSWithUserFont(15),
      fontSize16 = scaleSWithUserFont(16),
      fontSize17 = scaleSWithUserFont(17),
      fontSize18 = scaleSWithUserFont(18),
      fontSize20 = scaleSWithUserFont(20),
      fontSize22 = scaleSWithUserFont(22),
      fontSize24 = scaleSWithUserFont(24),
      fontSize28 = scaleSWithUserFont(28),
      fontSize32 = scaleSWithUserFont(32),
      fontSize36 = scaleSWithUserFont(36),
      fontSize48 = scaleSWithUserFont(48),
      fontSize72 = scaleSWithUserFont(72),

      kSpace1 = scaleW(1),
      kSpace2 = scaleW(2),
      kSpace3 = scaleW(3),
      kSpace4 = scaleW(4),
      kSpace5 = scaleW(5),
      kSpace6 = scaleW(6),
      kSpace8 = scaleW(8),
      kSpace10 = scaleW(10),
      kSpace12 = scaleW(12),
      kSpace14 = scaleW(14),
      kSpace16 = scaleW(16),
      kSpace18 = scaleW(18),
      kSpace20 = scaleW(20),
      kSpace24 = scaleW(24),
      kSpace32 = scaleW(32),
      kSpace40 = scaleW(40),
      kSpace44 = scaleW(44),
      kSpace48 = scaleW(48),
      kSpace56 = scaleW(56),
      kSpace64 = scaleW(64),
      kSpace80 = scaleW(80),

      // 描边宽度钉死为常量：这组值一旦走 scaleW，窗口拉大时 1 逻辑像素会被
      // 折算成不足 1 物理像素，发丝线直接糊成灰边（§3.3）。
      strokeHairline = 1.0,
      strokeUltraThin = 0.5,
      strokeThin = 1.5,
      strokeRegular = 2.0,
      strokeEmphasis = 2.5,
      strokeBold = 3.0,

      boxShadow10 = (() {
        final ctx = navigatorKey.currentContext;
        final s = ctx == null
            ? AppSemantic.light
            : AppSemantic.of(ctx);
        return BoxShadow(
          color: s.shadowKey,
          blurRadius: scaleW(8),
          offset: Offset(0, scaleH(4)),
        );
      })();
}
