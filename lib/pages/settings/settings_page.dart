import 'package:flutter/material.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/settings/components/media_settings_tab.dart';
import 'package:slime_works/pages/settings/components/node_settings_tab.dart';
import 'package:slime_works/pages/settings/components/settings_tab_placeholder.dart';
import 'package:slime_works/pages/settings/components/theme_settings_tab.dart';
import 'package:slime_works/pages/settings/components/ollama_settings_tab.dart';
import 'package:slime_works/pages/settings/components/picacg_settings_tab.dart';

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
      _SettingsTab(label: '主体设置', content: const ThemeSettingsTab()),
      _SettingsTab(label: '节点设置', content: const NodeSettingsTab()),
      _SettingsTab(label: '资源库', content: const _ResourcesSettingsTab()),
      _SettingsTab(label: 'Ollama 设置', content: const OllamaSettingsTab()),
      _SettingsTab(
        label: '账户设置',
        content: const SettingsTabPlaceholder(title: '账户设置'),
      ),
      _SettingsTab(
        label: '通知设置',
        content: const SettingsTabPlaceholder(title: '通知设置'),
      ),
      _SettingsTab(label: 'PicACG', content: const PicacgSettingsTab()),
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

/// 「资源库」二级设置页，包含「媒体设置」和「书籍设置」两个嵌套 Tab。
class _ResourcesSettingsTab extends StatelessWidget {
  const _ResourcesSettingsTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: '媒体设置'),
              Tab(text: '书籍设置'),
            ],
            dividerHeight: 0,
          ),
          const Expanded(
            child: TabBarView(
              children: [
                MediaSettingsTab(),
                SettingsTabPlaceholder(title: '书籍设置'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab {
  final String label;
  final Widget content;

  const _SettingsTab({required this.label, required this.content});
}
