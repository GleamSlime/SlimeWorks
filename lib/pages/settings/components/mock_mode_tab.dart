import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/mock/mock_mode.dart';

/// Mock 演示模式开关（仅 debug 可见）。
class MockModeTab extends StatefulWidget {
  const MockModeTab({super.key});

  @override
  State<MockModeTab> createState() => _MockModeTabState();
}

class _MockModeTabState extends State<MockModeTab> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    await MockMode.setRuntimeEnabled(value);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(value ? '已开启 Mock 演示数据，返回列表页刷新即可看到' : '已关闭 Mock，刷新页面恢复真实数据')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: EdgeInsets.all(m.kSpace16),
      children: [
        Text('Mock 演示模式', style: textTheme.titleMedium),
        SizedBox(height: m.kSpace8),
        Text(
          '开启后媒体库、小说、游戏、漫画、流水账、电力统计、Sentry 日志等模块使用内置演示数据，'
          '图片由本地实时生成，无需节点与网络。',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: m.kSpace16),
        if (MockMode.forcedByBuild)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.science_outlined, color: scheme.primary),
            title: const Text('已由编译参数强制开启'),
            subtitle: const Text('MOCK_MODE=true，关闭需重新构建'),
          )
        else if (kDebugMode)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: MockMode.runtimeEnabled,
            onChanged: _busy ? null : _toggle,
            title: const Text('启用演示数据'),
            subtitle: const Text('仅 debug 构建可见，切换后刷新页面生效'),
          )
        else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('当前构建不可用'),
            subtitle: Text('请使用 --dart-define=MOCK_MODE=true 重新构建'),
          ),
        Divider(height: m.kSpace32),
        Text('已覆盖模块', style: textTheme.labelLarge),
        SizedBox(height: m.kSpace8),
        Text(
          '媒体库与封面\n小说书架与阅读\n漫画列表/详情/章节\n游戏库与统计\n'
          '流水账与月度明细\n电力统计采样与图表\nSentry 日志与多级别样本\n'
          '局域网设备与传输记录\nOllama 翻译',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
