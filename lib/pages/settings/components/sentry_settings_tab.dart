import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/node/node_inline_selector.dart';
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

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(icon, size: m.iconSize12, color: theme.colorScheme.primary),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: TextStyle(
            fontSize: m.fontSize15,
            height: 1.4,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: m.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: child,
    );
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

    return Obx(
      () => Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Sentry 日志收集', Icons.radar_rounded),
              SizedBox(height: m.kSpace12),
              _buildSettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.radar_rounded,
                            size: m.iconSize16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Text(
                            'Sentry 日志收集',
                            style: TextStyle(
                              fontSize: m.fontSize13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: service.enabled.value,
                          onChanged: (v) async {
                            await service.setEnabled(v);
                            _showSnack(v ? 'Sentry 日志收集已启用' : 'Sentry 日志收集已禁用');
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace4),
                    Text(
                      '接收并存储 Sentry SDK 发送的事件日志',
                      style: TextStyle(
                        fontSize: m.fontSize12,
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('日志来源', Icons.swap_horiz),
              SizedBox(height: m.kSpace12),
              _buildSettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.swap_horiz,
                            size: m.iconSize16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '日志来源节点',
                                style: TextStyle(
                                  fontSize: m.fontSize13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                service.isLocal ? '本机' : '远程节点',
                                style: TextStyle(
                                  fontSize: m.fontSize12,
                                  color: theme.colorScheme.onSurface.withAlpha(120),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace8),
                    Obx(
                      () => NodeInlineSelector(
                        nodeService: nodeService,
                        selectedNodeId: service.selectedNodeId.value,
                        moduleName: 'Sentry日志',
                        availabilityChecker: (baseUrl) => service.checkNodeSentryAvailable(baseUrl),
                        onNodeSelected: (nodeId) async {
                          await service.setSelectedNodeId(nodeId);
                          _showSnack(nodeId.isEmpty ? '已切换到本机日志' : '已切换到节点');
                        },
                      ),
                    ),
                    SizedBox(height: m.kSpace12),
                    _buildDsnInfo(service, theme, m),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('自动刷新', Icons.autorenew),
              SizedBox(height: m.kSpace12),
              _buildSettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color:
                                (service.autoRefresh.value
                                        ? theme.colorScheme.primary
                                        : theme.hintColor)
                                    .withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.autorenew,
                            size: m.iconSize16,
                            color: service.autoRefresh.value
                                ? theme.colorScheme.primary
                                : theme.hintColor,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '自动刷新',
                                style: TextStyle(
                                  fontSize: m.fontSize13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                '每隔 ${service.refreshIntervalSeconds.value} 秒自动刷新日志',
                                style: TextStyle(
                                  fontSize: m.fontSize12,
                                  color: theme.colorScheme.onSurface.withAlpha(120),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: service.autoRefresh.value,
                          onChanged: (v) async {
                            await service.setAutoRefresh(v);
                          },
                        ),
                      ],
                    ),
                    if (service.autoRefresh.value) ...[
                      SizedBox(height: m.kSpace8),
                      _buildRefreshIntervalSlider(service, theme, m),
                    ],
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('DSN 配置', Icons.info_outline),
              SizedBox(height: m.kSpace12),
              _buildSettingsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.info_outline,
                            size: m.iconSize16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sentry DSN 配置说明',
                                style: TextStyle(
                                  fontSize: m.fontSize13,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                '在其他项目的 Sentry SDK 中配置以下 DSN 地址',
                                style: TextStyle(
                                  fontSize: m.fontSize12,
                                  color: theme.colorScheme.onSurface.withAlpha(120),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                            style: TextStyle(
                              fontSize: m.fontSize12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withAlpha(180),
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            service.currentDsn,
                            style: TextStyle(
                              fontSize: m.fontSize12,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          SizedBox(height: m.kSpace8),
                          Text(
                            'Sentry SDK 初始化示例 (Python)',
                            style: TextStyle(
                              fontSize: m.fontSize12,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withAlpha(180),
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            'sentry_sdk.init(\n'
                            '  dsn="${service.currentDsn}",\n'
                            '  traces_sample_rate=1.0,\n'
                            ')',
                            style: TextStyle(
                              fontSize: m.fontSize12,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurface.withAlpha(180),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDsnInfo(SentrySettingsService service, ThemeData theme, ThemeMetrics m) {
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
              style: TextStyle(
                fontSize: m.fontSize12,
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
          Text('刷新间隔', style: TextStyle(fontSize: m.fontSize12)),
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
              style: TextStyle(fontSize: m.fontSize12),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
