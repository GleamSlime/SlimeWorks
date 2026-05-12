import 'package:flutter/material.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/settings/components/extract_settings_tab.dart';
import 'package:slime_works/pages/settings/components/game_settings_tab.dart';
import 'package:slime_works/pages/settings/components/media_settings_tab.dart';
import 'package:slime_works/pages/settings/components/node_settings_tab.dart';
import 'package:slime_works/pages/settings/components/ollama_settings_tab.dart';
import 'package:slime_works/pages/settings/components/picacg_settings_tab.dart';
import 'package:slime_works/pages/settings/components/settings_tab_placeholder.dart';
import 'package:slime_works/pages/settings/components/theme_settings_tab.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  late final List<_SettingsTab> _tabs;
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
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
      const _SettingsTab(label: '工具设置', content: _ToolsSettingsWrapper()),
      const _SettingsTab(label: '其他设置', content: _OtherSettingsWrapper()),
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
        toolbar: TabBar(
          tabAlignment: TabAlignment.start,
          controller: _controller,
          isScrollable: true,
          dividerHeight: 0,
          tabs: _tabs.map((tab) => Tab(text: tab.label)).toList(),
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
          return SizedBox(
            height: constraints.maxHeight,
            child: const Column(
              crossAxisAlignment: .start,
              children: [
                TabBar(
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  tabs: [
                    Tab(text: '设置'),
                    Tab(text: 'Ollama 设置'),
                  ],
                  dividerHeight: 0,
                ),
                Expanded(child: TabBarView(children: [NodeSettingsTab(), OllamaSettingsTab()])),
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
    return DefaultTabController(
      length: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: constraints.maxHeight,
            child: const Column(
              crossAxisAlignment: .start,
              children: [
                TabBar(
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  tabs: [
                    Tab(text: '资源库'),
                    Tab(text: 'PicACG'),
                    Tab(text: '游戏设置'),
                  ],
                  dividerHeight: 0,
                ),
                Expanded(
                  child: TabBarView(
                    children: [_ResourcesSettingsTab(), PicAcgSettingsTab(), GameSettingsTab()],
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
    return DefaultTabController(
      length: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: constraints.maxHeight,
            child: const Column(
              crossAxisAlignment: .start,
              children: [
                TabBar(
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  tabs: [Tab(text: '解压设置')],
                  dividerHeight: 0,
                ),
                Expanded(child: TabBarView(children: [ExtractSettingsTab()])),
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
