import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

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

  /// 复制本机授权码到剪切板，供在另一台设备的「远程节点」里粘贴。
  Future<void> _copyLocalAuthCode() async {
    final code = _service?.localNodeAuthCode.value ?? '';
    if (code.isEmpty) {
      _showSnack('授权码为空，请先保存本机节点设置');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    _showSnack('授权码已复制到剪切板');
  }

  Future<void> _regenerateLocalAuthCode() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置授权码'),
        content: const Text('重置后旧授权码立即失效，所有已配置该节点的客户端都需要重新填写。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('重置')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await service.regenerateLocalAuthCode();
      _showSnack('已生成新授权码');
    } catch (e) {
      _showSnack('重置授权码失败: $e');
    }
  }

  Future<void> _showNodeEditor({NodeEndpoint? initial}) async {
    // 表单 controller 交给弹窗自己的 State 管理：showDialog 返回时退场动画还在跑，
    // 这时在外面 dispose 会让仍在重建的 TextField 撞上「used after being disposed」。
    final result = await showDialog<_NodeEditorValue>(
      context: context,
      builder: (_) => _NodeEditorDialog(initial: initial),
    );
    if (result == null || _service == null) {
      return;
    }

    if (result.apiBaseUrl.isEmpty) {
      _showSnack('外网API 不能为空');
      return;
    }

    try {
      if (initial == null) {
        await _service!.addRemoteNode(
          name: result.name,
          apiBaseUrl: result.apiBaseUrl,
          lanApiBaseUrl: result.lanApiBaseUrl.isEmpty ? null : result.lanApiBaseUrl,
          authCode: result.authCode,
        );
      } else {
        await _service!.updateRemoteNode(
          initial.copyWith(
            name: result.name.isEmpty ? initial.name : result.name,
            apiBaseUrl: result.apiBaseUrl,
            lanApiBaseUrl: result.lanApiBaseUrl.isEmpty ? null : result.lanApiBaseUrl,
            authCode: result.authCode,
            clearLanApiBaseUrl: result.lanApiBaseUrl.isEmpty,
          ),
        );
      }
      await _service!.refreshNodeConnectivity();
      _showSnack('保存成功');
    } catch (e) {
      _showSnack('保存节点失败: $e');
    }
  }

  Widget _buildSectionTitle(String title, StrokeIcon icon) {
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
          child: DrawIcon(icon, size: m.iconSize12, color: theme.colorScheme.primary),
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
              _buildSectionTitle('本机节点', StrokeIcons.dns),
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
                          child: DrawIcon(StrokeIcons.computer,
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
                    // 开启节点后展示本机授权码：其他设备添加节点时需要它
                    if (service.localNodeEnabled.value) ...[
                      SizedBox(height: m.kSpace12),
                      Row(
                        children: [
                          Text('本机授权码', style: Theme.of(context).textTheme.titleSmall),
                          SizedBox(width: m.kSpace8),
                          Expanded(
                            child: SelectableText(
                              service.localNodeAuthCode.value.isEmpty
                                  ? '未设置'
                                  : service.localNodeAuthCode.value,
                              style: TextStyle(
                                fontSize: m.fontSize13,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _copyLocalAuthCode,
                            icon: DrawIcon(StrokeIcons.copy),
                            iconSize: m.iconSize16,
                            tooltip: '复制授权码到剪切板',
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            onPressed: _regenerateLocalAuthCode,
                            icon: DrawIcon(StrokeIcons.autorenew),
                            iconSize: m.iconSize16,
                            tooltip: '重置授权码（旧码立即失效）',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      Text(
                        '其他设备添加本节点时填写它；请求头 X-SW-Auth 携带其 sha256 摘要',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
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
                              DrawIcon(StrokeIcons.link, size: m.iconSize12, color: brandColor),
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
                  _buildSectionTitle('远程节点', StrokeIcons.cloud),
                  Spacer(),
                  IconButton(
                    onPressed: service.refreshNodeConnectivity,
                    icon: DrawIcon(StrokeIcons.sync),
                    tooltip: '刷新连通状态',
                    iconSize: m.iconSize18,
                  ),
                  IconButton(
                    onPressed: () => _showNodeEditor(),
                    icon: DrawIcon(StrokeIcons.add),
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
                        child: DrawIcon(StrokeIcons.cloudOff,
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
                                            fontSize: m.fontSize12,
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
                                  Text(node.apiBaseUrl, style: TextStyle(fontSize: m.fontSize12)),
                                  if (node.lanApiBaseUrl != null && node.lanApiBaseUrl!.isNotEmpty)
                                    Text(
                                      '内网: ${node.lanApiBaseUrl}',
                                      style: TextStyle(fontSize: m.fontSize12, color: Colors.teal),
                                    ),
                                  // 连通失败时给出原因（授权码错误 / 不可达 / 已禁用）
                                  if (ok == false)
                                    Text(
                                      service.nodeConnectivityError[node.id] ?? '',
                                      style: TextStyle(
                                        fontSize: m.fontSize12,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                              // 内容行数会随错误提示变化，交由 ListTile 自适应高度
                              isThreeLine: false,
                              leading: Switch(
                                value: node.enabled,
                                onChanged: (v) => service.setRemoteNodeEnabled(node.id, v),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: DrawIcon(StrokeIcons.edit),
                                    onPressed: () => _showNodeEditor(initial: node),
                                    iconSize: m.iconSize18,
                                  ),
                                  IconButton(
                                    icon: DrawIcon(StrokeIcons.deleteOutline),
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

/// 节点编辑弹窗回传的表单值（已去首尾空白）。
class _NodeEditorValue {
  const _NodeEditorValue({
    required this.name,
    required this.apiBaseUrl,
    required this.lanApiBaseUrl,
    required this.authCode,
  });

  final String name;
  final String apiBaseUrl;
  final String lanApiBaseUrl;
  final String authCode;
}

/// 添加/编辑远程节点弹窗：表单 controller 由本 State 持有并释放。
///
/// 外层 await 在 pop 当帧就返回，而退场动画期间 TextField 仍在重建，
/// 在外层 dispose 会触发「A TextEditingController was used after being disposed」。
class _NodeEditorDialog extends StatefulWidget {
  const _NodeEditorDialog({this.initial});

  final NodeEndpoint? initial;

  @override
  State<_NodeEditorDialog> createState() => _NodeEditorDialogState();
}

class _NodeEditorDialogState extends State<_NodeEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _apiCtrl;
  late final TextEditingController _lanApiCtrl;
  late final TextEditingController _authCodeCtrl;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameCtrl = TextEditingController(text: initial?.name ?? '');
    _apiCtrl = TextEditingController(text: initial?.apiBaseUrl ?? 'http://127.0.0.1:17888');
    _lanApiCtrl = TextEditingController(text: initial?.lanApiBaseUrl ?? '');
    _authCodeCtrl = TextEditingController(text: initial?.authCode ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiCtrl.dispose();
    _lanApiCtrl.dispose();
    _authCodeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      _NodeEditorValue(
        name: _nameCtrl.text.trim(),
        apiBaseUrl: _apiCtrl.text.trim(),
        lanApiBaseUrl: _lanApiCtrl.text.trim(),
        authCode: _authCodeCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return AlertDialog(
      title: Text(widget.initial == null ? '添加节点' : '编辑节点'),
      content: SizedBox(
        width: scaleW(420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '节点名'),
            ),
            SizedBox(height: m.kSpace12),
            TextField(
              controller: _apiCtrl,
              decoration: const InputDecoration(
                labelText: '外网API',
                hintText: 'http://公网IP:17888',
              ),
            ),
            SizedBox(height: m.kSpace12),
            TextField(
              controller: _lanApiCtrl,
              decoration: const InputDecoration(
                labelText: '内网API（可选，优先使用）',
                hintText: 'http://192.168.x.x:17888',
              ),
            ),
            SizedBox(height: m.kSpace12),
            TextField(
              controller: _authCodeCtrl,
              obscureText: true,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: '授权码（节点侧提供）',
                hintText: '与对端「本机授权码」一致',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
