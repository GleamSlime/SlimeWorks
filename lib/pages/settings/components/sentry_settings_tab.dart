import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/node/node_inline_selector.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

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

  Widget _buildSectionTitle(String title, StrokeIcon icon) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: s.accentContainer,
            borderRadius: m.radius6,
          ),
          child: DrawIcon(icon, size: m.iconSize12, color: s.accent),
        ),
        SizedBox(width: m.kSpace8),
        Text(title, style: AppTextStyles.sectionTitle(context)),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radius12,
        border: Border.all(color: s.border),
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
    final s = AppSemantic.of(context);

    return Obx(
      () => Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('Sentry 日志收集', StrokeIcons.radar),
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
                            color: s.accentContainer,
                            borderRadius: m.radius8,
                          ),
                          child: DrawIcon(StrokeIcons.radar,
                            size: m.iconSize16,
                            color: s.accent,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Text(
                            'Sentry 日志收集',
                            style: AppTextStyles.cardTitle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize12,
                        color: s.textTertiary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('日志来源', StrokeIcons.swapHoriz),
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
                            color: s.accentContainer,
                            borderRadius: m.radius8,
                          ),
                          child: DrawIcon(StrokeIcons.swapHoriz,
                            size: m.iconSize16,
                            color: s.accent,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '日志来源节点',
                                style: AppTextStyles.cardTitle(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                service.isLocal ? '本机' : '远程节点',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize12,
                                  color: s.textTertiary,
                                  height: 1.6,
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
                    _buildDsnInfo(service),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('自动刷新', StrokeIcons.autorenew),
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
                                (service.autoRefresh.value ? s.accent : s.textTertiary)
                                    .withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: DrawIcon(StrokeIcons.autorenew,
                            size: m.iconSize16,
                            color: service.autoRefresh.value ? s.accent : s.textTertiary,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '自动刷新',
                                style: AppTextStyles.cardTitle(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                '每隔 ${service.refreshIntervalSeconds.value} 秒自动刷新日志',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize12,
                                  color: s.textTertiary,
                                  height: 1.6,
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
                      _buildRefreshIntervalSlider(service),
                    ],
                  ],
                ),
              ),
              SizedBox(height: m.kSpace16),
              _buildSectionTitle('DSN 配置', StrokeIcons.infoOutline),
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
                            color: s.accentContainer,
                            borderRadius: m.radius8,
                          ),
                          child: DrawIcon(StrokeIcons.infoOutline,
                            size: m.iconSize16,
                            color: s.accent,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sentry DSN 配置说明',
                                style: AppTextStyles.cardTitle(context),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: m.kSpace2),
                              Text(
                                '在其他项目的 Sentry SDK 中配置以下 DSN 地址',
                                style: AppTextStyles.role(
                                  context,
                                  fontSize: m.fontSize12,
                                  color: s.textTertiary,
                                  height: 1.6,
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
                        color: s.surfaceSunken,
                        borderRadius: m.radius8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DSN 格式',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize12,
                              weight: FontWeight.w600,
                              color: s.textSecondary,
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            service.currentDsn,
                            style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                              color: s.accent,
                            ),
                          ),
                          SizedBox(height: m.kSpace8),
                          Text(
                            'Sentry SDK 初始化示例 (Python)',
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize12,
                              weight: FontWeight.w600,
                              color: s.textSecondary,
                            ),
                          ),
                          SizedBox(height: m.kSpace4),
                          SelectableText(
                            'sentry_sdk.init(\n'
                            '  dsn="${service.currentDsn}",\n'
                            '  traces_sample_rate=1.0,\n'
                            ')',
                            style: AppTextStyles.mono(context, size: m.fontSize12),
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

  Widget _buildDsnInfo(SentrySettingsService service) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace10),
      decoration: BoxDecoration(
        color: s.surfaceSunken,
        borderRadius: m.radius8,
      ),
      child: Row(
        children: [
          DrawIcon(StrokeIcons.link, size: m.iconSize16, color: s.textTertiary),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: SelectableText(
              service.currentDsn,
              style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                color: s.accent,
              ),
            ),
          ),
          IconButton(
            icon: DrawIcon(StrokeIcons.copy, size: m.iconSize16, color: s.textTertiary),
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

  Widget _buildRefreshIntervalSlider(SentrySettingsService service) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '刷新间隔',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.textSecondary,
              ),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
