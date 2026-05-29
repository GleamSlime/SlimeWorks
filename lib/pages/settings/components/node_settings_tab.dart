import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class NodeSettingsTab extends StatefulWidget {
  const NodeSettingsTab({super.key});

  @override
  State<NodeSettingsTab> createState() => _NodeSettingsTabState();
}

class _NodeSettingsTabState extends State<NodeSettingsTab> {
  NodeSettingsService? _service;
  bool _loading = true;

  final TextEditingController _localNameCtrl = TextEditingController();
  final TextEditingController _localPortCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final service = getIt.get<NodeSettingsService>();
    await service.init();
    await service.refreshNodeConnectivity();
    if (!mounted) {
      return;
    }

    setState(() {
      _service = service;
      _loading = false;
    });

    _localNameCtrl.text = service.localNodeName.value;
    _localPortCtrl.text = service.localNodePort.value.toString();
  }

  @override
  void dispose() {
    _localNameCtrl.dispose();
    _localPortCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _saveLocalSettings(bool enabled) async {
    final service = _service;
    if (service == null) {
      return;
    }

    final port = int.tryParse(_localPortCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      _showSnack('端口范围应为 1-65535');
      return;
    }

    try {
      await service.updateLocalSettings(
        enabled: enabled,
        nodeName: _localNameCtrl.text.trim(),
        port: port,
      );
      _showSnack(enabled ? '节点服务已开启' : '节点服务已关闭');
    } catch (e) {
      _showSnack('保存节点设置失败: $e');
    }
  }

  Future<void> _showNodeEditor({NodeEndpoint? initial}) async {
    final nameCtrl = TextEditingController(text: initial?.name ?? '');
    final apiCtrl = TextEditingController(text: initial?.apiBaseUrl ?? 'http://127.0.0.1:17888');
    final lanApiCtrl = TextEditingController(text: initial?.lanApiBaseUrl ?? '');
    final m = AppTheme.metrics;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial == null ? '添加节点' : '编辑节点'),
        content: SizedBox(
          width: scaleW(420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '节点名'),
              ),
              SizedBox(height: m.kSpace12),
              TextField(
                controller: apiCtrl,
                decoration: const InputDecoration(
                  labelText: '外网API',
                  hintText: 'http://公网IP:17888',
                ),
              ),
              SizedBox(height: m.kSpace12),
              TextField(
                controller: lanApiCtrl,
                decoration: const InputDecoration(
                  labelText: '内网API（可选，优先使用）',
                  hintText: 'http://192.168.x.x:17888',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('保存')),
        ],
      ),
    );

    if (confirmed != true || _service == null) {
      return;
    }

    final name = nameCtrl.text.trim();
    final api = apiCtrl.text.trim();
    final lanApi = lanApiCtrl.text.trim();
    if (api.isEmpty) {
      _showSnack('外网API 不能为空');
      return;
    }

    try {
      if (initial == null) {
        await _service!.addRemoteNode(
          name: name,
          apiBaseUrl: api,
          lanApiBaseUrl: lanApi.isEmpty ? null : lanApi,
        );
      } else {
        await _service!.updateRemoteNode(
          initial.copyWith(
            name: name.isEmpty ? initial.name : name,
            apiBaseUrl: api,
            lanApiBaseUrl: lanApi.isEmpty ? null : lanApi,
            clearLanApiBaseUrl: lanApi.isEmpty,
          ),
        );
      }
      await _service!.refreshNodeConnectivity();
      _showSnack('保存成功');
    } catch (e) {
      _showSnack('保存节点失败: $e');
    }
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

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (_loading || service == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = AppTheme.metrics;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColor = isDark ? DarkColors.primary : LightColors.primary;

    return Obx(
      () => Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('本机节点', Icons.dns_outlined),
              SizedBox(height: m.kSpace12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(m.kSpace16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: m.radius12,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: m.kSpace32,
                          height: m.kSpace32,
                          decoration: BoxDecoration(
                            color: brandColor.withAlpha(25),
                            borderRadius: m.radius8,
                          ),
                          child: Icon(
                            Icons.computer_outlined,
                            size: m.iconSize16,
                            color: brandColor,
                          ),
                        ),
                        SizedBox(width: m.kSpace10),
                        Expanded(
                          child: Text(
                            '本机节点服务',
                            style: TextStyle(
                              fontSize: m.fontSize13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: service.localNodeEnabled.value,
                          onChanged: _saveLocalSettings,
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace12),
                    TextField(
                      controller: _localNameCtrl,
                      decoration: const InputDecoration(labelText: 'API节点名'),
                      onSubmitted: (_) => _saveLocalSettings(service.localNodeEnabled.value),
                    ),
                    SizedBox(height: m.kSpace8),
                    TextField(
                      controller: _localPortCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '节点端口'),
                      onSubmitted: (_) => _saveLocalSettings(service.localNodeEnabled.value),
                    ),
                    SizedBox(height: m.kSpace12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => _saveLocalSettings(service.localNodeEnabled.value),
                        child: const Text('保存本机节点设置'),
                      ),
                    ),
                    SizedBox(height: m.kSpace12),
                    Text('本机API地址', style: Theme.of(context).textTheme.titleSmall),
                    SizedBox(height: m.kSpace6),
                    if (service.localNodeApiList.isEmpty)
                      Text(
                        '暂无可用地址',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      )
                    else
                      ...service.localNodeApiList.map(
                        (api) => Padding(
                          padding: EdgeInsets.only(bottom: m.kSpace4),
                          child: Row(
                            children: [
                              Icon(Icons.link_rounded, size: m.iconSize12, color: brandColor),
                              SizedBox(width: m.kSpace6),
                              SelectableText(
                                api,
                                style: TextStyle(
                                  fontSize: m.fontSize12,
                                  color: Theme.of(context).colorScheme.onSurface.withAlpha(180),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: m.kSpace24),
              Row(
                children: [
                  _buildSectionTitle('远程节点', Icons.cloud_outlined),
                  Spacer(),
                  IconButton(
                    onPressed: service.refreshNodeConnectivity,
                    icon: const Icon(Icons.sync),
                    tooltip: '刷新连通状态',
                    iconSize: m.iconSize18,
                  ),
                  IconButton(
                    onPressed: () => _showNodeEditor(),
                    icon: const Icon(Icons.add),
                    tooltip: '添加节点',
                    iconSize: m.iconSize18,
                  ),
                ],
              ),
              SizedBox(height: m.kSpace12),
              if (service.remoteNodes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
                    borderRadius: m.radius12,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: m.kSpace40,
                        height: m.kSpace40,
                        decoration: BoxDecoration(
                          color: brandColor.withAlpha(20),
                          borderRadius: m.radius10,
                        ),
                        child: Icon(
                          Icons.cloud_off_outlined,
                          size: m.iconSize20,
                          color: brandColor,
                        ),
                      ),
                      SizedBox(height: m.kSpace12),
                      Text(
                        '暂无远程节点',
                        style: TextStyle(
                          fontSize: m.fontSize13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: m.kSpace4),
                      Text(
                        '点击右上角 + 添加远程节点',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...service.remoteNodes.map((node) {
                  final ok = service.nodeConnectivity[node.id];
                  final dotColor = ok == null
                      ? Colors.grey
                      : ok
                      ? Colors.green
                      : Colors.red;
                  final statusLabel = ok == null
                      ? '检测中'
                      : ok
                      ? '已连接'
                      : '不可达';
                  return Container(
                    margin: EdgeInsets.only(bottom: m.kSpace8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                      borderRadius: m.radius12,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: m.radius12,
                      child: Row(
                        children: [
                          Container(width: 4, height: 72, color: dotColor),
                          Expanded(
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(child: Text(node.name)),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: m.kSpace8,
                                      vertical: m.kSpace2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: dotColor.withAlpha(25),
                                      borderRadius: m.radius999,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: m.kSpace6,
                                          height: m.kSpace6,
                                          decoration: BoxDecoration(
                                            color: dotColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        SizedBox(width: m.kSpace4),
                                        Text(
                                          statusLabel,
                                          style: TextStyle(
                                            fontSize: m.fontSize10,
                                            fontWeight: FontWeight.w600,
                                            color: dotColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(node.apiBaseUrl, style: TextStyle(fontSize: m.fontSize11)),
                                  if (node.lanApiBaseUrl != null && node.lanApiBaseUrl!.isNotEmpty)
                                    Text(
                                      '内网: ${node.lanApiBaseUrl}',
                                      style: TextStyle(fontSize: m.fontSize10, color: Colors.teal),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              leading: Switch(
                                value: node.enabled,
                                onChanged: (v) => service.setRemoteNodeEnabled(node.id, v),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _showNodeEditor(initial: node),
                                    iconSize: m.iconSize18,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => service.removeRemoteNode(node.id),
                                    iconSize: m.iconSize18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
