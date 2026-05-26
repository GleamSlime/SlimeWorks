import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/app_log_viewmodel.dart';

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
    final isDark = Get.isDarkMode;

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
                  strokeWidth: 2,
                  color: isDark ? DarkColors.primary : LightColors.primary,
                ),
              ),
              SizedBox(height: m.kSpace12),
              Text(
                '加载日志...',
                style: TextStyle(
                  fontSize: m.fontSize13,
                  height: 1.5,
                  color: isDark ? DarkColors.white80 : LightColors.black80,
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        children: [
          _buildToolbar(context, m, isDark),
          SizedBox(height: m.kSpace8),
          Expanded(child: _buildTerminalView(context, m, isDark)),
        ],
      );
    });
  }

  Widget _buildToolbar(BuildContext context, ThemeMetrics m, bool isDark) {
    final vm = widget.viewModel;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isDark ? DarkColors.background1.withAlpha(220) : LightColors.background1.withAlpha(240),
            isDark ? DarkColors.background2.withAlpha(160) : LightColors.background2.withAlpha(200),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: m.radius10,
        border: Border.all(
          color: isDark ? DarkColors.white10.withAlpha(40) : LightColors.black10.withAlpha(30),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? DarkColors.black10 : LightColors.black10,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: primaryColor.withAlpha(8),
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
          Icon(Icons.terminal_rounded, size: m.iconSize18, color: primaryColor),
          Container(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
            decoration: BoxDecoration(color: primaryColor.withAlpha(15), borderRadius: m.radius4),
            child: Text(
              '${vm.entries.length}',
              style: TextStyle(
                fontSize: m.fontSize11,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Container(
              height: m.kSpace24,
              decoration: BoxDecoration(
                color: isDark
                    ? DarkColors.background3.withAlpha(120)
                    : LightColors.background3.withAlpha(100),
                borderRadius: m.radius6,
                border: Border.all(
                  color: isDark ? DarkColors.white10 : LightColors.black10,
                  width: 0.5,
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: m.fontSize11, height: 1.4, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '搜索关键词...',
                  hintStyle: TextStyle(
                    fontSize: m.fontSize11,
                    color: isDark ? DarkColors.white40 : LightColors.black40,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: m.iconSize14,
                    color: isDark ? DarkColors.white40 : LightColors.black40,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
                  isDense: true,
                ),
                onChanged: vm.setSearchQuery,
              ),
            ),
          ),
          _buildLevelChip('ALL', '', vm, m, isDark),
          _buildLevelChip('ERR', 'ERROR', vm, m, isDark),
          _buildLevelChip('WRN', 'WARN', vm, m, isDark),
          _buildLevelChip('INF', 'INFO', vm, m, isDark),
          _buildLevelChip('DBG', 'DEBUG', vm, m, isDark),
          GestureDetector(
            onTap: vm.isWatching.value ? vm.stopWatching : vm.startWatching,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace4),
              decoration: BoxDecoration(
                gradient: vm.isWatching.value
                    ? LinearGradient(
                        colors: [Colors.green.withAlpha(40), Colors.green.withAlpha(15)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: vm.isWatching.value
                    ? null
                    : (isDark ? DarkColors.background2 : LightColors.background2),
                borderRadius: m.radius6,
                border: Border.all(
                  color: vm.isWatching.value
                      ? Colors.green.withAlpha(60)
                      : (isDark ? DarkColors.white10 : LightColors.black10),
                  width: 0.5,
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
                      color: vm.isWatching.value
                          ? Colors.green
                          : (isDark ? DarkColors.white40 : LightColors.black40),
                      boxShadow: vm.isWatching.value
                          ? [BoxShadow(color: Colors.green.withAlpha(40), blurRadius: scaleW(4))]
                          : null,
                    ),
                  ),
                  SizedBox(width: m.kSpace6),
                  Text(
                    vm.isWatching.value ? '实时' : '静态',
                    style: TextStyle(
                      fontSize: m.fontSize11,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ActionButton(
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            isDark: isDark,
            onPressed: () => vm.loadLogs(),
          ),
          _ActionButton(
            icon: Icons.clear_all_rounded,
            tooltip: '清除筛选',
            isDark: isDark,
            onPressed: () {
              _searchController.clear();
              vm.clearFilters();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLevelChip(
    String label,
    String level,
    AppLogViewModel vm,
    ThemeMetrics m,
    bool isDark,
  ) {
    final isActive = vm.selectedLevel.value == level;
    final color = level.isEmpty
        ? (isDark ? DarkColors.primary : LightColors.primary)
        : vm.getLevelColor(level);

    return GestureDetector(
      onTap: () => vm.setLevelFilter(level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
        decoration: BoxDecoration(
          color: isActive ? color.withAlpha(25) : Colors.transparent,
          borderRadius: m.radius4,
          border: Border.all(
            color: isActive
                ? color.withAlpha(80)
                : (isDark ? DarkColors.white10 : LightColors.black10),
            width: isActive ? 1 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: m.fontSize10,
            height: 1.4,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            color: isActive ? color : (isDark ? DarkColors.white40 : LightColors.black40),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalView(BuildContext context, ThemeMetrics m, bool isDark) {
    final vm = widget.viewModel;
    final entries = vm.entries;

    if (entries.isEmpty) {
      return _buildEmptyState(m, isDark);
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0E14) : const Color(0xFFFAFAFA),
        borderRadius: m.radius12,
        border: Border.all(
          color: isDark ? const Color(0xFF1A1F29) : const Color(0xFFE0E0E0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : Colors.grey).withAlpha(40),
            blurRadius: scaleW(12),
            offset: Offset(0, scaleW(4)),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1F29) : const Color(0xFFE8E8E8),
                borderRadius: BorderRadius.only(
                  topLeft: m.radius12.topLeft,
                  topRight: m.radius12.topRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5F56),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFBD2E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  Container(
                    width: scaleW(10),
                    height: scaleW(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF27C93F),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: Text(
                      'slime_works — log terminal',
                      style: TextStyle(
                        fontSize: m.fontSize11,
                        height: 1.4,
                        color: isDark ? const Color(0xFF6C7A89) : const Color(0xFF888888),
                        fontFamily: 'monospace',
                      ),
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
                    return _buildLogLine(entry, m, isDark);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogLine(AppLogEntry entry, ThemeMetrics m, bool isDark) {
    final levelColor = _getTerminalLevelColor(entry.level, isDark);
    final sourceColor = entry.source == 'rust'
        ? (isDark ? const Color(0xFFE06C75) : const Color(0xFFBE5046))
        : (isDark ? const Color(0xFF61AFEF) : const Color(0xFF4078F2));
    final timestampColor = isDark ? const Color(0xFF5C6370) : const Color(0xFFA0A0A0);
    final messageColor = isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42);

    final keywords = _extractKeywords(entry.message);

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: m.fontSize11,
            height: 1.6,
            fontFamily: 'monospace',
            color: messageColor,
          ),
          children: [
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
            ..._buildMessageSpans(entry.message, keywords, messageColor, isDark, m),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _buildMessageSpans(
    String message,
    Set<String> keywords,
    Color baseColor,
    bool isDark,
    ThemeMetrics m,
  ) {
    if (keywords.isEmpty) {
      return [
        TextSpan(
          text: message,
          style: TextStyle(color: baseColor),
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

    final kwColor = isDark ? const Color(0xFFE5C07B) : const Color(0xFF986801);
    final pathColor = isDark ? const Color(0xFF98C379) : const Color(0xFF50A14F);
    final numColor = isDark ? const Color(0xFFD19A66) : const Color(0xFFA45200);

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: message.substring(lastEnd, match.start),
            style: TextStyle(color: baseColor),
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
          style: TextStyle(color: baseColor),
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

  Color _getTerminalLevelColor(String level, bool isDark) {
    switch (level) {
      case 'ERROR':
        return isDark ? const Color(0xFFE06C75) : const Color(0xFFBE5046);
      case 'WARN':
        return isDark ? const Color(0xFFE5C07B) : const Color(0xFF986801);
      case 'DEBUG':
        return isDark ? const Color(0xFFC678DD) : const Color(0xFFA626A4);
      case 'INFO':
        return isDark ? const Color(0xFF98C379) : const Color(0xFF50A14F);
      default:
        return isDark ? const Color(0xFF56B6C2) : const Color(0xFF0184BC);
    }
  }

  Widget _buildEmptyState(ThemeMetrics m, bool isDark) {
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: scaleW(80),
            height: scaleW(80),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [primaryColor.withAlpha(15), primaryColor.withAlpha(4), Colors.transparent],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Icon(
              Icons.terminal_rounded,
              size: scaleW(36),
              color: primaryColor.withAlpha(60),
            ),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '暂无应用日志',
            style: TextStyle(fontSize: m.fontSize15, height: 1.5, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '点击「实时」按钮开始收集',
            style: TextStyle(
              fontSize: m.fontSize13,
              height: 1.5,
              color: isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.isDark,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(m.kSpace6),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDark ? DarkColors.white10 : LightColors.black10).withAlpha(40)
                : Colors.transparent,
            borderRadius: m.radius6,
          ),
          child: AnimatedScale(
            scale: _hovered ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              widget.icon,
              size: m.iconSize16,
              color: widget.isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
        ),
      ),
    );
  }
}
