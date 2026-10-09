import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/app_log_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

class AppLogTerminal extends StatefulWidget {
  final AppLogViewModel viewModel;

  const AppLogTerminal({super.key, required this.viewModel});

  @override
  State<AppLogTerminal> createState() => _AppLogTerminalState();
}

class _AppLogTerminalState extends State<AppLogTerminal> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.viewModel.loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    // 终端内容区自带一套控制台配色（深色底 + 高饱和语法色），明暗两档由语义层
    // 判定后各取自己的色板；页面 chrome（工具条/筛选片/空态）一律走语义角色。

    return Obx(() {
      final vm = widget.viewModel;
      final entries = vm.entries;
      final isLoading = vm.isLoading.value;

      if (isLoading && entries.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: m.iconSize32,
                height: m.iconSize32,
                child: CircularProgressIndicator(
                  strokeWidth: m.kSpace2,
                  color: s.accent,
                ),
              ),
              SizedBox(height: m.kSpace12),
              Text(
                '加载日志...',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize13,
                  color: s.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          _buildToolbar(context, s, m),
          SizedBox(height: m.kSpace8),
          Expanded(child: _buildTerminalView(context, s, m)),
        ],
      );
    });
  }

  Widget _buildToolbar(BuildContext context, AppSemantic s, ThemeMetrics m) {
    final vm = widget.viewModel;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
      decoration: BoxDecoration(
        // 工具条是页面面板，不是终端的一部分：走语义表面层，留一点透明度让出窗口磨砂。
        gradient: LinearGradient(
          colors: [
            s.surfaceRaised.withAlpha(235),
            s.surface.withAlpha(190),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: m.radius10,
        border: Border.all(color: s.hairline, width: AppTheme.metrics.strokeUltraThin),
        boxShadow: [
          ...s.elevation(Elevation.raised),
          BoxShadow(
            color: s.accent.withAlpha(8),
            blurRadius: scaleW(16),
            offset: Offset(0, scaleW(3)),
          ),
        ],
      ),
      child: Wrap(
        spacing: m.kSpace6,
        runSpacing: m.kSpace6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DrawIcon(StrokeIcons.terminal, size: m.iconSize18, color: s.accent),
          Container(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
            decoration: BoxDecoration(color: s.accentContainer, borderRadius: m.radius4),
            child: Text(
              '${vm.entries.length}',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize11,
                color: s.accentText,
                weight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
          SizedBox(
            width: scaleW(160),
            child: Container(
              // 原来这里钉了 height: kSpace24，而框内字号走的是吃用户字号滑杆的
              // fontSize11——字号拉到最大档就会顶出框。改为让输入框按内容自然撑高。
              decoration: BoxDecoration(
                color: s.surfaceSunken,
                borderRadius: m.radius6,
                border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
              ),
              child: AppTextField(
                controller: _searchController,
                style: AppTextStyles.mono(context, size: m.fontSize11).copyWith(height: 1.4),
                decoration: InputDecoration(
                  hintText: '搜索关键词...',
                  hintStyle: AppTextStyles.mono(context, size: m.fontSize11).copyWith(
                    color: s.textTertiary,
                    height: 1.4,
                  ),
                  prefixIcon: DrawIcon(
                    StrokeIcons.search,
                    size: m.iconSize14,
                    color: s.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
                  isDense: true,
                ),
                onChanged: vm.setSearchQuery,
              ),
            ),
          ),
          _buildLevelChip(context, s, 'ALL', '', vm, m),
          _buildLevelChip(context, s, 'ERR', 'ERROR', vm, m),
          _buildLevelChip(context, s, 'WRN', 'WARN', vm, m),
          _buildLevelChip(context, s, 'INF', 'INFO', vm, m),
          _buildLevelChip(context, s, 'DBG', 'DEBUG', vm, m),
          GestureDetector(
            onTap: vm.isWatching.value ? vm.stopWatching : vm.startWatching,
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace4),
              decoration: BoxDecoration(
                // 监听态就是 success 角色：容器底与描边由角色派生，不手写 alpha。
                // 原先在 gradient 与 color 之间来回切，AnimatedContainer 其实动不了
                // 这两种装饰，统一成 color 之后切换才真正是连续的。
                color: vm.isWatching.value ? s.success.container : s.surface,
                borderRadius: m.radius6,
                border: Border.all(
                  color: vm.isWatching.value ? s.success.containerBorder : s.border,
                  width: scaleW(0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: m.kSpace6,
                    height: m.kSpace6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: vm.isWatching.value ? s.success.color : s.textTertiary,
                      boxShadow: vm.isWatching.value
                          ? [
                              BoxShadow(
                                color: s.success.color.withAlpha(40),
                                blurRadius: scaleW(4),
                              )
                            ]
                          : null,
                    ),
                  ),
                  SizedBox(width: m.kSpace6),
                  Text(
                    vm.isWatching.value ? '实时' : '静态',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize11,
                      color: vm.isWatching.value ? s.success.onContainer : s.textSecondary,
                      weight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ActionButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: () => vm.loadLogs(),
          ),
          _ActionButton(
            icon: StrokeIcons.clearAll,
            tooltip: '清除筛选',
            onPressed: () {
              _searchController.clear();
              vm.clearFilters();
            },
          ),
        ],
      ),
    );
  }

  /// 级别 → 状态角色：ALL（空串）与语义层没覆盖到的级别都归 neutral
  AppStatusRole _levelRole(AppSemantic s, String level) {
    switch (level) {
      case 'ERROR':
        return s.danger;
      case 'WARN':
        return s.warning;
      case 'DEBUG':
        return s.info;
      case 'INFO':
        return s.success;
      default:
        return s.neutral;
    }
  }

  Widget _buildLevelChip(
    BuildContext context,
    AppSemantic s,
    String label,
    String level,
    AppLogViewModel vm,
    ThemeMetrics m,
  ) {
    final isActive = vm.selectedLevel.value == level;
    final role = _levelRole(s, level);

    return GestureDetector(
      onTap: () => vm.setLevelFilter(level),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
        decoration: BoxDecoration(
          color: isActive ? role.container : Colors.transparent,
          borderRadius: m.radius4,
          border: Border.all(
            color: isActive ? role.containerBorder : s.border,
            width: isActive ? scaleW(1) : scaleW(0.5),
          ),
        ),
        child: Text(
          label,
          // 筛选片是终端工具条上的小字，保留等宽；选中态文字走 onContainer，
          // 状态主色是给"点"用的，直接当小字号文字会糊。
          style: AppTextStyles.mono(context, size: m.fontSize10).copyWith(
            height: 1.4,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? role.onContainer : s.textTertiary,
          ),
        ),
      ),
    );
  }

  /// 终端内容区
  ///
  /// 这套控制台配色（深底 + 高饱和语法色）是独立的 token 集 [AppTerminalPalette]，
  /// 经 `s.terminal` 按明暗成套取用，而不是并进 `surface`/`textSecondary` 这类界面
  /// 语义角色：语义色一改（比如 textSecondary 调灰），日志正文的语法高亮就会失去
  /// 层次，这块区域也不再像终端。成套关系集中在主题层定义，widget 里不留字面量。
  /// 等级色仍归 [AppStatusRole]。
  Widget _buildTerminalView(
    BuildContext context,
    AppSemantic s,
    ThemeMetrics m,
  ) {
    final t = s.terminal;
    final vm = widget.viewModel;
    final entries = vm.entries;

    if (entries.isEmpty) {
      return _buildEmptyState(context, s, m);
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      decoration: BoxDecoration(
        color: t.screen,
        borderRadius: m.radius12,
        border: Border.all(
          color: t.chromeBorder,
          width: scaleW(1),
        ),
        boxShadow: s.elevation(Elevation.card),
      ),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
              decoration: BoxDecoration(
                color: t.titleBar,
                borderRadius: BorderRadius.only(
                  topLeft: m.radius12.topLeft,
                  topRight: m.radius12.topRight,
                ),
              ),
              child: Row(
                children: [
                  // 仿终端窗饰的三颗灯恒为红/黄/绿、不随主题反相，所以在
                  // AppTerminalPalette 上是单一静态常量，而不是明暗两档的字段
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: AppTerminalPalette.windowDotClose,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: AppTerminalPalette.windowDotMinimize,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: AppTerminalPalette.windowDotZoom,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: Text(
                      'slime_works — log terminal',
                      style: AppTextStyles.mono(context, size: m.fontSize11, color: t.titleText)
                          .copyWith(height: 1.4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.unknown,
                  },
                ),
                child: ListView.builder(
                  controller: vm.scrollController,
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    return _buildLogLine(context, s, entry, m);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogLine(
    BuildContext context,
    AppSemantic s,
    AppLogEntry entry,
    ThemeMetrics m,
  ) {
    final t = s.terminal;
    // 等级色走状态角色：danger/warning/info/success 的明暗两档本身就够了压住
    // 深底和浅底，不需要再手写一套等级色板。
    final levelColor = _levelRole(s, entry.level).color;
    // 来源标记/时间戳/正文属于控制台语法色，与终端底色成套，因此取自
    // AppTerminalPalette（s.terminal），而不是通用 surface/text 语义角色。
    final sourceColor = entry.source == 'rust' ? t.sourceRust : t.sourceDart;
    final timestampColor = t.timestamp;
    final messageColor = t.body;

    final keywords = _extractKeywords(entry.message);

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace2),
      // 日志行不设 maxLines：整行是等宽正文，超长时自动换行而不是被截断，
      // 行内也没有固定宽度容器，字号滑杆拉大只会让行更高。
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.mono(context, size: m.fontSize11, color: messageColor)
              .copyWith(height: 1.6),
          children: [
            // 子 span 只写颜色：TextSpan 的样式与父 span 合并，字族仍然继承上面的等宽
            TextSpan(
              text: entry.rawTimestamp.isNotEmpty ? entry.rawTimestamp : '??',
              style: TextStyle(color: timestampColor),
            ),
            TextSpan(
              text: ' ',
              style: TextStyle(color: timestampColor),
            ),
            TextSpan(
              text: '[${entry.level}]',
              style: TextStyle(color: levelColor, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: ' ',
              style: TextStyle(color: timestampColor),
            ),
            TextSpan(
              text: entry.source == 'rust' ? 'R' : 'D',
              style: TextStyle(
                color: sourceColor,
                fontWeight: FontWeight.w700,
                fontSize: m.fontSize9,
              ),
            ),
            TextSpan(
              text: ' ',
              style: TextStyle(color: timestampColor),
            ),
            ..._buildMessageSpans(entry.message, keywords, t),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _buildMessageSpans(
    String message,
    Set<String> keywords,
    AppTerminalPalette t,
  ) {
    if (keywords.isEmpty) {
      return [
        TextSpan(
          text: message,
          style: TextStyle(color: t.body),
        ),
      ];
    }

    final sortedKeywords = keywords.toList()..sort((a, b) => b.length.compareTo(a.length));

    final pattern = RegExp(
      sortedKeywords.map((k) => RegExp.escape(k)).join('|'),
      caseSensitive: false,
    );
    final spans = <TextSpan>[];
    final matches = pattern.allMatches(message);
    int lastEnd = 0;

    // 关键词/路径/数字三类语法高亮与终端底色成套，同样取自 AppTerminalPalette：
    // 它们是编辑器配色，换成界面 text 角色会随主题串味，故单列 token 集而非角色
    final kwColor = t.keyword;
    final pathColor = t.path;
    final numColor = t.number;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: message.substring(lastEnd, match.start),
            style: TextStyle(color: t.body),
          ),
        );
      }

      final matchedText = match.group(0)!;
      Color highlightColor = kwColor;

      if (_isPath(matchedText)) {
        highlightColor = pathColor;
      } else if (_isNumeric(matchedText)) {
        highlightColor = numColor;
      }

      spans.add(
        TextSpan(
          text: matchedText,
          style: TextStyle(color: highlightColor, fontWeight: FontWeight.w600),
        ),
      );

      lastEnd = match.end;
    }

    if (lastEnd < message.length) {
      spans.add(
        TextSpan(
          text: message.substring(lastEnd),
          style: TextStyle(color: t.body),
        ),
      );
    }

    return spans;
  }

  Set<String> _extractKeywords(String message) {
    final keywords = <String>{};

    final errorPattern = RegExp(
      r'(?:error|Error|ERROR|exception|Exception|fail|Fail|FAIL|crash|Crash|timeout|Timeout|disconnect|Disconnect|abort|Abort|refused|Refused)',
    );
    for (final m in errorPattern.allMatches(message)) {
      keywords.add(m.group(0)!);
    }

    final pathPattern = RegExp(r'[/\\][\w./\\-]+');
    for (final m in pathPattern.allMatches(message)) {
      keywords.add(m.group(0)!);
    }

    final numPattern = RegExp(r'\b\d+\.?\d*\b');
    for (final m in numPattern.allMatches(message)) {
      keywords.add(m.group(0)!);
    }

    final statusPattern = RegExp(
      r'\b(?:success|Success|ok|OK|complete|Complete|start|Start|stop|Stop|connected|Connected|ready|Ready|init|Init)\b',
    );
    for (final m in statusPattern.allMatches(message)) {
      keywords.add(m.group(0)!);
    }

    final urlPattern = RegExp(r'https?://\S+');
    for (final m in urlPattern.allMatches(message)) {
      keywords.add(m.group(0)!);
    }

    final classPattern = RegExp(r'\b[A-Z][a-zA-Z]+\b');
    for (final m in classPattern.allMatches(message)) {
      final word = m.group(0)!;
      if (word.length > 3) keywords.add(word);
    }

    return keywords;
  }

  bool _isPath(String text) {
    return text.contains('/') ||
        text.contains('\\') ||
        text.contains('.dart') ||
        text.contains('.rs');
  }

  bool _isNumeric(String text) {
    return double.tryParse(text) != null;
  }

  Widget _buildEmptyState(BuildContext context, AppSemantic s, ThemeMetrics m) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: m.kSpace80,
            height: m.kSpace80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [s.accent.withAlpha(15), s.accent.withAlpha(4), Colors.transparent],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: DrawIcon(
              StrokeIcons.terminal,
              size: scaleW(36),
              color: s.accent.withAlpha(60),
            ),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '暂无应用日志',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize15,
              color: s.textPrimary,
              weight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '点击「实时」按钮开始收集',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize13,
              color: s.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final StrokeIcon icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: EdgeInsets.all(m.kSpace6),
          decoration: BoxDecoration(
            color: _hovered ? s.surfaceHover : Colors.transparent,
            borderRadius: m.radius6,
          ),
          child: AnimatedScale(
            scale: _hovered ? 1.1 : 1.0,
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            child: DrawIcon(
              widget.icon,
              size: m.iconSize16,
              color: _hovered ? s.textPrimary : s.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
