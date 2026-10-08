import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/node/node_inline_selector.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

class AliyunSettingsTab extends StatefulWidget {
  const AliyunSettingsTab({super.key});

  @override
  State<AliyunSettingsTab> createState() => _AliyunSettingsTabState();
}

class _AliyunSettingsTabState extends State<AliyunSettingsTab> {
  AliyunDdnsService? _service;
  NodeSettingsService? _nodeService;
  bool _loading = true;
  bool _obscureSecret = true;

  final _accessKeyIdCtrl = TextEditingController();
  final _accessKeySecretCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service = getIt.get<AliyunDdnsService>();
    await service.ensureInitialized();
    final nodeService = getIt.get<NodeSettingsService>();
    await nodeService.init();
    _accessKeyIdCtrl.text = service.accessKeyId.value;
    _accessKeySecretCtrl.text = service.accessKeySecret.value;
    if (!mounted) return;
    setState(() {
      _service = service;
      _nodeService = nodeService;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _accessKeyIdCtrl.dispose();
    _accessKeySecretCtrl.dispose();
    super.dispose();
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
        Text(
          title,
          style: AppTextStyles.sectionTitle(context),
        ),
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
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return Obx(
      () => SingleChildScrollView(
        padding: EdgeInsets.all(m.kSpace24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('数据来源', StrokeIcons.swapHoriz),
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
                              '阿里云数据节点',
                              style: AppTextStyles.cardTitle(context),
                            ),
                            SizedBox(height: m.kSpace2),
                            Text(
                              service.isLocal ? '本机' : '远程节点',
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize12,
                                color: s.textSecondary,
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
                      moduleName: '阿里云DDNS',
                      availabilityChecker: (baseUrl) => service.checkNodeAliyunAvailable(baseUrl),
                      onNodeSelected: (nodeId) async {
                        await service.setSelectedNodeId(nodeId);
                        _showSnack(nodeId.isEmpty ? '已切换到本机' : '已切换到节点');
                      },
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: m.kSpace24),
            _buildSectionTitle('AccessKey 配置', StrokeIcons.key),
            SizedBox(height: m.kSpace12),
            _buildSettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '配置阿里云 AccessKey 用于域名解析 API 调用',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.textTertiary,
                    ),
                  ),
                  SizedBox(height: m.kSpace16),
                  Row(
                    children: [
                      Container(
                        width: m.kSpace32,
                        height: m.kSpace32,
                        decoration: BoxDecoration(
                          color: s.accentContainer,
                          borderRadius: m.radius8,
                        ),
                        child: DrawIcon(StrokeIcons.vpnKey,
                          size: m.iconSize16,
                          color: s.accent,
                        ),
                      ),
                      SizedBox(width: m.kSpace10),
                      Expanded(
                        child: Text(
                          'AccessKey ID',
                          style: AppTextStyles.cardTitle(context),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace8),
                  AppTextField(
                    controller: _accessKeyIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'LTAI5t...',
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _accessKeyIdCtrl.text));
                          _showSnack('已复制');
                        },
                        icon: DrawIcon(StrokeIcons.copy, size: m.iconSize16),
                      ),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onChanged: (v) async {
                      await service.setAccessKeyId(v);
                      await service.updateConfig();
                    },
                  ),
                  SizedBox(height: m.kSpace16),
                  Row(
                    children: [
                      Container(
                        width: m.kSpace32,
                        height: m.kSpace32,
                        decoration: BoxDecoration(
                          color: s.accentContainer,
                          borderRadius: m.radius8,
                        ),
                        child: DrawIcon(StrokeIcons.lock, size: m.iconSize16, color: s.accent),
                      ),
                      SizedBox(width: m.kSpace10),
                      Expanded(
                        child: Text(
                          'AccessKey Secret',
                          style: AppTextStyles.cardTitle(context),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                        icon: DrawIcon(
                          _obscureSecret ? StrokeIcons.visibilityOff : StrokeIcons.visibility,
                          size: m.iconSize16,
                          color: s.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace8),
                  AppTextField(
                    controller: _accessKeySecretCtrl,
                    obscureText: _obscureSecret,
                    decoration: InputDecoration(
                      hintText: 'Wq8xYz...',
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _accessKeySecretCtrl.text));
                          _showSnack('已复制');
                        },
                        icon: DrawIcon(StrokeIcons.copy, size: m.iconSize16),
                      ),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onChanged: (v) async {
                      await service.setAccessKeySecret(v);
                      await service.updateConfig();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: m.kSpace24),
            _buildSectionTitle('检查间隔', StrokeIcons.timer),
            SizedBox(height: m.kSpace12),
            _buildSettingsCard(
              child: Obx(
                () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置 DDNS 自动检查的时间间隔',
                      style: AppTextStyles.caption(context),
                    ),
                    SizedBox(height: m.kSpace12),
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: s.accentContainer,
                            borderRadius: m.radius8,
                          ),
                          child: DrawIcon(StrokeIcons.schedule,
                            size: m.iconSize16,
                            color: s.accent,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Text(
                            '检查间隔',
                            style: AppTextStyles.cardTitle(context),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace10,
                            vertical: m.kSpace4,
                          ),
                          decoration: BoxDecoration(
                            color: s.accentContainer,
                            borderRadius: m.radius6,
                          ),
                          child: Text(
                            _formatInterval(service.intervalSecs.value),
                            style: AppTextStyles.role(
                              context,
                              fontSize: m.fontSize12,
                              color: s.accentText,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace12),
                    Wrap(
                      spacing: m.kSpace8,
                      runSpacing: m.kSpace8,
                      children: _presetIntervals.map((secs) {
                        final isSelected = service.intervalSecs.value == secs;
                        return InkWell(
                          onTap: () async {
                            await service.setIntervalSecs(secs);
                            await service.updateConfig();
                          },
                          borderRadius: m.radius8,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: m.kSpace12,
                              vertical: m.kSpace6,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? s.accentContainer
                                  : s.surfaceSunken,
                              borderRadius: m.radius8,
                              border: Border.all(
                                color: isSelected
                                    ? s.accentContainerBorder
                                    : s.hairline,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              _formatInterval(secs),
                              style: AppTextStyles.role(
                                context,
                                fontSize: m.fontSize12,
                                color: isSelected ? s.accentText : s.textSecondary,
                                weight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _presetIntervals = [10, 20, 30, 50, 60, 120, 300, 600, 1800, 3600];

  String _formatInterval(int secs) {
    if (secs < 60) return '$secs秒';
    if (secs < 3600) return '${secs ~/ 60}分钟';
    if (secs % 3600 == 0) return '${secs ~/ 3600}小时';
    return '${secs ~/ 3600}小时${(secs % 3600) ~/ 60}分钟';
  }
}
