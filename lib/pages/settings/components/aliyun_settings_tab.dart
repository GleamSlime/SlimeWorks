import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/node/node_inline_selector.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';

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

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: LightColors.orange.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(icon, size: m.iconSize12, color: LightColors.orange),
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
      padding: EdgeInsets.all(m.kSpace16),
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
    final m = AppTheme.metrics;
    final theme = Theme.of(context);

    return Obx(
      () => SingleChildScrollView(
        padding: EdgeInsets.all(m.kSpace24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('数据来源', Icons.swap_horiz),
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
                          color: LightColors.orange.withAlpha(25),
                          borderRadius: m.radius8,
                        ),
                        child: Icon(
                          Icons.swap_horiz,
                          size: m.iconSize16,
                          color: LightColors.orange,
                        ),
                      ),
                      SizedBox(width: m.kSpace10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '阿里云数据节点',
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
            _buildSectionTitle('AccessKey 配置', Icons.key_rounded),
            SizedBox(height: m.kSpace12),
            _buildSettingsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '配置阿里云 AccessKey 用于域名解析 API 调用',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                  SizedBox(height: m.kSpace16),
                  Row(
                    children: [
                      Container(
                        width: m.kSpace32,
                        height: m.kSpace32,
                        decoration: BoxDecoration(
                          color: LightColors.orange.withAlpha(15),
                          borderRadius: m.radius8,
                        ),
                        child: Icon(
                          Icons.vpn_key_rounded,
                          size: m.iconSize16,
                          color: LightColors.orange,
                        ),
                      ),
                      SizedBox(width: m.kSpace10),
                      Expanded(
                        child: Text(
                          'AccessKey ID',
                          style: TextStyle(
                            fontSize: m.fontSize13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace8),
                  TextField(
                    controller: _accessKeyIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'LTAI5t...',
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _accessKeyIdCtrl.text));
                          _showSnack('已复制');
                        },
                        icon: Icon(Icons.copy_rounded, size: m.iconSize16),
                      ),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
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
                          color: LightColors.red.withAlpha(15),
                          borderRadius: m.radius8,
                        ),
                        child: Icon(Icons.lock_rounded, size: m.iconSize16, color: LightColors.red),
                      ),
                      SizedBox(width: m.kSpace10),
                      Expanded(
                        child: Text(
                          'AccessKey Secret',
                          style: TextStyle(
                            fontSize: m.fontSize13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                        icon: Icon(
                          _obscureSecret ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: m.iconSize16,
                          color: theme.colorScheme.onSurface.withAlpha(60),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace8),
                  TextField(
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
                        icon: Icon(Icons.copy_rounded, size: m.iconSize16),
                      ),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    onChanged: (v) async {
                      await service.setAccessKeySecret(v);
                      await service.updateConfig();
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: m.kSpace24),
            _buildSectionTitle('检查间隔', Icons.timer_rounded),
            SizedBox(height: m.kSpace12),
            _buildSettingsCard(
              child: Obx(
                () => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置 DDNS 自动检查的时间间隔',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(150),
                      ),
                    ),
                    SizedBox(height: m.kSpace12),
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: LightColors.cyan.withAlpha(15),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: m.iconSize16,
                            color: LightColors.cyan,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Text(
                            '检查间隔',
                            style: TextStyle(
                              fontSize: m.fontSize13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace10,
                            vertical: m.kSpace4,
                          ),
                          decoration: BoxDecoration(
                            color: LightColors.cyan.withAlpha(15),
                            borderRadius: m.radius6,
                          ),
                          child: Text(
                            _formatInterval(service.intervalSecs.value),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: LightColors.cyan,
                              fontWeight: FontWeight.w600,
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
                                  ? LightColors.cyan.withAlpha(20)
                                  : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                              borderRadius: m.radius8,
                              border: Border.all(
                                color: isSelected
                                    ? LightColors.cyan.withAlpha(80)
                                    : theme.colorScheme.outlineVariant.withAlpha(40),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              _formatInterval(secs),
                              style: TextStyle(
                                fontSize: m.fontSize12,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected
                                    ? LightColors.cyan
                                    : theme.colorScheme.onSurface.withAlpha(120),
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
