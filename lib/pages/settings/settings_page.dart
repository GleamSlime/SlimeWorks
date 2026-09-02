import 'dart:io';

import 'package:flutter/material.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/settings/components/aliyun_settings_tab.dart';
import 'package:slime_works/pages/settings/components/about_settings_tab.dart';
import 'package:slime_works/pages/settings/components/extract_settings_tab.dart';
import 'package:slime_works/pages/settings/components/game_settings_tab.dart';
import 'package:slime_works/pages/settings/components/media_settings_tab.dart';
import 'package:slime_works/pages/settings/components/music_player_settings_tab.dart';
import 'package:slime_works/pages/settings/components/node_settings_tab.dart';
import 'package:slime_works/pages/settings/components/ollama_settings_tab.dart';
import 'package:slime_works/pages/settings/components/manga_settings_tab.dart';
import 'package:slime_works/pages/settings/components/sentry_settings_tab.dart';
import 'package:slime_works/pages/settings/components/settings_tab_placeholder.dart';
import 'package:slime_works/pages/settings/components/theme_settings_tab.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final List<_SettingsTab> _tabs;
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    final isMobile = Platform.isAndroid || Platform.isIOS;
    _tabs = [
      const _SettingsTab(label: '主体设置', content: ThemeSettingsTab()),
      const _SettingsTab(label: '节点设置', content: _NodeSettingsWrapper()),
      const _SettingsTab(
        label: '账户设置',
        content: SettingsTabPlaceholder(title: '账户设置'),
      ),
      const _SettingsTab(
        label: '通知设置',
        content: SettingsTabPlaceholder(title: '通知设置'),
      ),
      // 移动端隐藏工具设置（解压、阿里云均不可用）
      if (!isMobile)
        const _SettingsTab(label: '工具设置', content: _ToolsSettingsWrapper()),
      const _SettingsTab(label: '其他设置', content: _OtherSettingsWrapper()),
      // 桌面端显示关于（应用版本与自动更新）
      if (!isMobile)
        const _SettingsTab(label: '关于', content: AboutSettingsTab()),
    ];
    _controller = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      data: ScreenChromeData(
        title: '设置',
        toolbarHeight: AppTheme.metrics.kSpace48,
        toolbar: _SettingsTabBar(
          controller: _controller,
          tabs: _tabs.map((tab) => tab.label).toList(),
        ),
      ),
      child: TabBarView(
        controller: _controller,
        children: _tabs.map((tab) => tab.content).toList(),
      ),
    );
  }
}

class _NodeSettingsWrapper extends StatelessWidget {
  const _NodeSettingsWrapper();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controller = DefaultTabController.of(context);
          return SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsTabBar(
                  controller: controller,
                  tabs: const ['设置', 'Ollama 设置'],
                ),
                Expanded(
                  child: TabBarView(
                    children: [NodeSettingsTab(), OllamaSettingsTab()],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OtherSettingsWrapper extends StatelessWidget {
  const _OtherSettingsWrapper();

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final tabLabels = <String>[
      '资源库',
      'Manga',
      '游戏设置',
      if (!isMobile) '播放器设置',
      if (!isMobile) 'Sentry',
    ];
    final children = <Widget>[
      const _ResourcesSettingsTab(),
      const MangaSettingsTab(),
      const GameSettingsTab(),
      if (!isMobile) const MusicPlayerSettingsTab(),
      if (!isMobile) const SentrySettingsTab(),
    ];

    return DefaultTabController(
      length: tabLabels.length,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controller = DefaultTabController.of(context);
          return SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsTabBar(
                  controller: controller,
                  tabs: tabLabels,
                ),
                Expanded(
                  child: TabBarView(
                    children: children,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ToolsSettingsWrapper extends StatelessWidget {
  const _ToolsSettingsWrapper();

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final tabLabels = <String>[
      if (!isMobile) '解压设置',
      if (!isMobile) '阿里云',
    ];
    final children = <Widget>[
      if (!isMobile) const ExtractSettingsTab(),
      if (!isMobile) const AliyunSettingsTab(),
    ];

    if (tabLabels.isEmpty) {
      return const Center(child: Text('当前平台无可用工具设置'));
    }

    return DefaultTabController(
      length: tabLabels.length,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final controller = DefaultTabController.of(context);
          return SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsTabBar(
                  controller: controller,
                  tabs: tabLabels,
                ),
                Expanded(
                  child: TabBarView(
                    children: children,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResourcesSettingsTab extends StatelessWidget {
  const _ResourcesSettingsTab();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(length: 2, child: MediaSettingsTab());
  }
}

class _SettingsTab {
  final String label;
  final Widget content;

  const _SettingsTab({required this.label, required this.content});
}

/// 自定义设置页 TabBar：圆角标签 + hover/按住交互 + 选中动画
class _SettingsTabBar extends StatelessWidget {
  final TabController? controller;
  final List<String> tabs;

  const _SettingsTabBar({
    this.controller,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final tabController = controller ?? DefaultTabController.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (index) {
            return _SettingsTabItem(
              label: tabs[index],
              index: index,
              controller: tabController,
            );
          }),
        ),
      ),
    );
  }
}

class _SettingsTabItem extends StatefulWidget {
  final String label;
  final int index;
  final TabController controller;

  const _SettingsTabItem({
    required this.label,
    required this.index,
    required this.controller,
  });

  @override
  State<_SettingsTabItem> createState() => _SettingsTabItemState();
}

class _SettingsTabItemState extends State<_SettingsTabItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  bool get _isSelected => widget.controller.index == widget.index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;
    final selected = _isSelected;

    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    Color bgColor;
    Color textColor;
    Color? borderColor;
    double borderWidth = 0;
    List<BoxShadow>? shadows;

    if (selected) {
      bgColor = primaryColor.withAlpha(isDark ? 30 : 22);
      textColor = primaryColor;
      borderColor = primaryColor.withAlpha(isDark ? 60 : 40);
      borderWidth = 1.2;
      shadows = [
        BoxShadow(
          color: primaryColor.withAlpha(isDark ? 15 : 10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
    } else if (_pressed) {
      bgColor = theme.colorScheme.onSurface.withAlpha(isDark ? 18 : 12);
      textColor = theme.colorScheme.onSurface.withAlpha(180);
    } else if (_hovered) {
      bgColor = theme.colorScheme.onSurface.withAlpha(isDark ? 12 : 8);
      textColor = theme.colorScheme.onSurface.withAlpha(200);
      shadows = [
        BoxShadow(
          color: theme.colorScheme.onSurface.withAlpha(4),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    } else {
      bgColor = Colors.transparent;
      textColor = theme.colorScheme.onSurface.withAlpha(140);
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.controller.animateTo(widget.index);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOutCubic,
          margin: EdgeInsets.only(right: m.kSpace6),
          padding: EdgeInsets.symmetric(
            horizontal: m.kSpace14,
            vertical: m.kSpace8,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: m.radius10,
            border: borderWidth > 0
                ? Border.all(color: borderColor!, width: borderWidth)
                : null,
            boxShadow: shadows,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: m.fontSize13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
