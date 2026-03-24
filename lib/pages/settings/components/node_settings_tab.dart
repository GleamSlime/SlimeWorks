import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
          title: Text(initial == null ? '添加节点' : '编辑节点'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '节点名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiCtrl,
                  decoration: const InputDecoration(
                    labelText: '请求节点API',
                    hintText: 'http://127.0.0.1:17888',
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
    if (api.isEmpty) {
      _showSnack('API 不能为空');
      return;
    }

    try {
      if (initial == null) {
        await _service!.addRemoteNode(name: name, apiBaseUrl: api);
      } else {
        await _service!.updateRemoteNode(
          initial.copyWith(
            name: name.isEmpty ? initial.name : name,
            apiBaseUrl: api,
          ),
        );
      }
      await _service!.refreshNodeConnectivity();
      _showSnack('保存成功');
    } catch (e) {
      _showSnack('保存节点失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (_loading || service == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Obx(
      () => Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(appMetrics.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本机节点', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: EdgeInsets.all(appMetrics.kSpace12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('开启本机为节点'),
                        value: service.localNodeEnabled.value,
                        onChanged: _saveLocalSettings,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _localNameCtrl,
                        decoration: const InputDecoration(labelText: 'API节点名'),
                        onSubmitted: (_) => _saveLocalSettings(service.localNodeEnabled.value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _localPortCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '节点端口'),
                        onSubmitted: (_) => _saveLocalSettings(service.localNodeEnabled.value),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => _saveLocalSettings(service.localNodeEnabled.value),
                          child: const Text('保存本机节点设置'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('本机API地址', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      if (service.localNodeApiList.isEmpty)
                        const Text('暂无可用地址')
                      else
                        ...service.localNodeApiList.map(
                          (api) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SelectableText(api, style: Theme.of(context).textTheme.bodyMedium),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Text('远程节点', style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                    onPressed: service.refreshNodeConnectivity,
                    icon: const Icon(Icons.sync),
                    tooltip: '刷新连通状态',
                  ),
                  IconButton(
                    onPressed: () => _showNodeEditor(),
                    icon: const Icon(Icons.add),
                    tooltip: '添加节点',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (service.remoteNodes.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无远程节点，点击右上角添加。'),
                  ),
                )
              else
                ...service.remoteNodes.map(
                  (node) {
                    final ok = service.nodeConnectivity[node.id];
                    final dotColor = ok == null
                        ? Colors.grey
                        : ok
                        ? Colors.green
                        : Colors.red;
                    final tip = service.nodeConnectivityError[node.id] ?? '';
                    return Card(
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(node.name)),
                          Tooltip(
                            message: ok == true ? '可连通' : (tip.isEmpty ? '不可连通' : tip),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        node.apiBaseUrl,
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
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => service.removeRemoteNode(node.id),
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
