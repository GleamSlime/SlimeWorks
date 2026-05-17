import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class SentrySettingsTab extends StatefulWidget {
  const SentrySettingsTab({super.key});

  @override
  State<SentrySettingsTab> createState() => _SentrySettingsTabState();
}

class _SentrySettingsTabState extends State<SentrySettingsTab> {
  SentrySettingsService? _service;
  NodeSettingsService? _nodeService;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sentryService = getIt.get<SentrySettingsService>();
    await sentryService.init();
    final nodeService = getIt.get<NodeSettingsService>();
    await nodeService.init();

    if (!mounted) return;
    setState(() {
      _service = sentryService;
      _nodeService = nodeService;
      _loading = false;
    });
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _service == null || _nodeService == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final service = _service!;
    final nodeService = _nodeService!;
    final m = appMetrics;
    final theme = Theme.of(context);

    return Obx(() => Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(m.kSpace12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.radar_rounded,
                        color: service.enabled.value
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                      title: const Text('启用 Sentry 日志收集'),
                      subtitle: const Text('接收并存储 Sentry SDK 发送的事件日志'),
                      value: service.enabled.value,
                      onChanged: (v) async {
                        await service.setEnabled(v);
                        _showSnack(v ? 'Sentry 日志收集已启用' : 'Sentry 日志收集已禁用');
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.kSpace16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(m.kSpace12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.swap_horiz, color: theme.colorScheme.primary),
                      title: const Text('日志来源节点'),
                      subtitle: Text(
                        service.isLocal ? '本机' : '远程节点',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    SizedBox(height: m.kSpace8),
                    _buildNodeSelector(service, nodeService, theme, m),
                    SizedBox(height: m.kSpace12),
                    _buildDsnInfo(service, theme, m),
                  ],
                ),
              ),
            ),
            SizedBox(height: m.kSpace16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(m.kSpace12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.autorenew,
                        color: service.autoRefresh.value
                            ? theme.colorScheme.primary
                            : theme.hintColor,
                      ),
                      title: const Text('自动刷新'),
                      subtitle: Text('每隔 ${service.refreshIntervalSeconds.value} 秒自动刷新日志'),
                      value: service.autoRefresh.value,
                      onChanged: (v) async {
                        await service.setAutoRefresh(v);
                      },
                    ),
                    if (service.autoRefresh.value) ...[
                      SizedBox(height: m.kSpace8),
                      _buildRefreshIntervalSlider(service, theme, m),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: m.kSpace16),
            Card(
              child: Padding(
                padding: EdgeInsets.all(m.kSpace12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
                      title: const Text('Sentry DSN 配置说明'),
                      subtitle: const Text('在其他项目的 Sentry SDK 中配置以下 DSN 地址'),
                    ),
                    SizedBox(height: m.kSpace8),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(m.kSpace12),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withAlpha(8)
                            : Colors.black.withAlpha(4),
                        borderRadius: m.radius8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DSN 格式',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            service.currentDsn,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: m.kSpace8),
                          Text(
                            'Sentry SDK 初始化示例 (Python)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            'sentry_sdk.init(\n'
                            '  dsn="${service.currentDsn}",\n'
                            '  traces_sample_rate=1.0,\n'
                            ')',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildNodeSelector(
    SentrySettingsService service,
    NodeSettingsService nodeService,
    ThemeData theme,
    ThemeMetrics m,
  ) {
    final localNodeEnabled = nodeService.localNodeEnabled.value;
    final remoteNodes = nodeService.enabledRemoteNodes;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withAlpha(8)
            : Colors.black.withAlpha(4),
        borderRadius: m.radius8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNodeOption(
            context: context,
            nodeId: '',
            label: '本机',
            subtitle: localNodeEnabled
                ? '本机节点服务运行中'
                : '本机节点未启用',
            icon: Icons.computer,
            isSelected: service.selectedNodeId.value.isEmpty,
            isAvailable: true,
            onTap: () async {
              await service.setSelectedNodeId('');
              _showSnack('已切换到本机日志');
            },
            theme: theme,
            m: m,
          ),
          if (remoteNodes.isNotEmpty)
            ...remoteNodes.map((node) {
              final ok = nodeService.nodeConnectivity[node.id] == true;
              return _buildNodeOption(
                context: context,
                nodeId: node.id,
                label: node.name,
                subtitle: '${node.apiBaseUrl}${ok ? '' : ' (不可达)'}',
                icon: Icons.dns_outlined,
                isSelected: service.selectedNodeId.value == node.id,
                isAvailable: ok,
                onTap: () async {
                  if (!ok) {
                    _showSnack('节点不可达，请检查节点设置');
                    return;
                  }
                  final available = await service.checkNodeSentryAvailable(node.apiBaseUrl);
                  if (!available) {
                    if (!mounted) return;
                    _showSnack('该节点不支持 Sentry 日志功能');
                    return;
                  }
                  await service.setSelectedNodeId(node.id);
                  _showSnack('已切换到节点: ${node.name}');
                },
                theme: theme,
                m: m,
              );
            }),
          if (!localNodeEnabled && remoteNodes.isEmpty)
            Padding(
              padding: EdgeInsets.all(m.kSpace12),
              child: Text(
                '暂无可用节点，请在节点设置中添加或启用节点',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeOption({
    required BuildContext context,
    required String nodeId,
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isAvailable,
    required VoidCallback onTap,
    required ThemeData theme,
    required ThemeMetrics m,
  }) {
    return InkWell(
      borderRadius: m.radius8,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
          borderRadius: m.radius8,
          color: isSelected
              ? theme.colorScheme.primary.withAlpha(20)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: m.iconSize20,
              color: isSelected
                  ? theme.colorScheme.primary
                  : (isAvailable ? theme.hintColor : theme.disabledColor),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isAvailable ? null : theme.disabledColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isAvailable ? theme.hintColor : theme.disabledColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, size: m.iconSize20, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildDsnInfo(
    SentrySettingsService service,
    ThemeData theme,
    ThemeMetrics m,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withAlpha(8)
            : Colors.black.withAlpha(4),
        borderRadius: m.radius8,
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: m.iconSize16, color: theme.hintColor),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: SelectableText(
              service.currentDsn,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.copy, size: m.iconSize16, color: theme.hintColor),
            tooltip: '复制 DSN',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: service.currentDsn));
              _showSnack('DSN 已复制到剪贴板');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshIntervalSlider(
    SentrySettingsService service,
    ThemeData theme,
    ThemeMetrics m,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
      child: Row(
        children: [
          Text('刷新间隔', style: theme.textTheme.bodySmall),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Slider(
              value: service.refreshIntervalSeconds.value.toDouble(),
              min: 5,
              max: 120,
              divisions: 23,
              label: '${service.refreshIntervalSeconds.value}秒',
              onChanged: (v) async {
                await service.setRefreshInterval(v.round());
              },
            ),
          ),
          SizedBox(
            width: m.kSpace48,
            child: Text(
              '${service.refreshIntervalSeconds.value}秒',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
