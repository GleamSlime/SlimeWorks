import 'package:flutter/material.dart';
import 'package:slime_works/pages/settings/components/media_settings_tab.dart';
import 'package:slime_works/pages/settings/components/node_settings_tab.dart';
import 'package:slime_works/pages/settings/components/settings_tab_placeholder.dart';
import 'package:slime_works/pages/settings/components/theme_settings_tab.dart';
import 'package:slime_works/pages/settings/components/ollama_settings_tab.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = [
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
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          bottom: TabBar(
            isScrollable: true,
            tabs: tabs.map((tab) => Tab(text: tab.label)).toList(),
          ),
        ),
        body: TabBarView(children: tabs.map((tab) => tab.content).toList()),
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
