import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_models.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 设备唤醒页
///
/// 魔术包是二层广播，设备不在同一局域网时只能由局域网内的节点代发，
/// 因此这里按设备分别配置「节点中继」或「本机直发」。
class DeviceWakeScreen extends StatefulWidget {
  const DeviceWakeScreen({super.key});

  @override
  State<DeviceWakeScreen> createState() => _DeviceWakeScreenState();
}

class _DeviceWakeScreenState extends State<DeviceWakeScreen> {
  late final NodeSettingsService _service = GetIt.instance.get<NodeSettingsService>();

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  Future<void> _wake(WakeDevice device) async {
    try {
      await _service.wakeDevice(device.id);
      _showSnack('${device.name} 唤醒包已发送');
    } catch (e) {
      _showSnack('唤醒失败: $e');
    }
  }

  Future<void> _showEditor({WakeDevice? initial}) async {
    final value = await showDialog<_WakeEditorValue>(
      context: context,
      builder: (_) => _WakeEditorDialog(
        initial: initial,
        nodes: _service.remoteNodes.toList(),
      ),
    );
    if (value == null) {
      return;
    }

    if (initial == null) {
      await _service.addWakeDevice(
        name: value.name,
        mac: value.mac,
        target: value.target,
        port: value.port,
        mode: value.mode,
        relayNodeId: value.relayNodeId,
        probeNodeId: value.probeNodeId,
      );
    } else {
      await _service.updateWakeDevice(
        initial.copyWith(
          name: value.name,
          mac: value.mac,
          target: value.target,
          port: value.port,
          mode: value.mode,
          relayNodeId: value.relayNodeId,
          probeNodeId: value.probeNodeId,
        ),
      );
    }
  }

  Future<void> _confirmRemove(WakeDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定删除「${device.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.removeWakeDevice(device.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '设备唤醒',
        actions: [
          IconButton(
            onPressed: () => _showEditor(),
            icon: DrawIcon(StrokeIcons.add),
            tooltip: '添加设备',
            iconSize: m.iconSize18,
          ),
          SizedBox(width: m.kSpace8),
        ],
      ),
      child: Obx(() {
        final devices = _service.wakeDevices.toList();
        return SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHintCard(context, m),
              SizedBox(height: m.kSpace16),
              if (devices.isEmpty)
                _buildEmpty(context, m)
              else
                ...devices.map((device) => _buildDeviceCard(context, m, device)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildHintCard(BuildContext context, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: AppCard.glassDecoration(context, borderRadius: m.radius12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DrawIcon(StrokeIcons.infoOutline, size: m.iconSize20, color: s.info.color),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('魔术包只能在同一局域网内生效', style: AppTextStyles.cardTitle(context)),
                SizedBox(height: m.kSpace4),
                Text(
                  '设备不在当前网络时，需由局域网内一台常开的本应用节点代发；'
                  '本机直发仅适用于同网段或路由器已把 UDP 端口映射到广播地址的情况。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textSecondary,
                  ),
                ),
                SizedBox(height: m.kSpace4),
                Text(
                  '目标主机需在 BIOS 开启网络唤醒并关闭 ErP，网卡勾选「魔术包唤醒」与「关机网络唤醒」。',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize12,
                    color: s.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace32),
      decoration: BoxDecoration(
        color: s.surfaceSunken,
        borderRadius: m.radius12,
        border: Border.all(color: s.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: m.kSpace40,
            height: m.kSpace40,
            decoration: BoxDecoration(
              color: s.accentContainer,
              borderRadius: m.radius10,
            ),
            child: DrawIcon(StrokeIcons.deviceDesktop, size: m.iconSize20, color: s.accent),
          ),
          SizedBox(height: m.kSpace12),
          Text('暂无唤醒设备', style: AppTextStyles.cardTitle(context)),
          SizedBox(height: m.kSpace4),
          Text(
            '点击右上角 + 添加设备',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              color: s.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, ThemeMetrics m, WakeDevice device) {
    final s = AppSemantic.of(context);
    final status = _service.wakeStatus[device.id] ?? WakeStatus.idle;
    final tone = _statusTone(s, status);
    final relayName = device.mode == WakeMode.relay
        ? (_service.getNodeById(device.relayNodeId)?.name ?? '未选择中继节点')
        : '本机直发';
    final probeName = device.probeNodeId.isEmpty
        ? ''
        : ' · 检测节点 ${_service.getNodeById(device.probeNodeId)?.name ?? '已删除'}';
    final waking = status == WakeStatus.waking;

    return Container(
      margin: EdgeInsets.only(bottom: m.kSpace8),
      decoration: AppCard.glassDecoration(context, borderRadius: m.radius12),
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace40,
                  height: m.kSpace40,
                  decoration: BoxDecoration(
                    color: s.accentContainer,
                    borderRadius: m.radius10,
                  ),
                  child: DrawIcon(
                    StrokeIcons.deviceDesktop,
                    size: m.iconSize20,
                    color: s.accent,
                  ),
                ),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: AppTextStyles.cardTitle(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: m.kSpace2),
                      Text(
                        relayName,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          color: s.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: m.kSpace8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.kSpace8,
                    vertical: m.kSpace2,
                  ),
                  decoration: BoxDecoration(
                    color: tone.container,
                    borderRadius: m.radius999,
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      weight: FontWeight.w600,
                      color: tone.onContainer,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            Text(
              'MAC  ${device.mac}',
              style: AppTextStyles.mono(
                context,
                size: m.fontSize12,
                color: s.textSecondary,
              ),
            ),
            SizedBox(height: m.kSpace4),
            Text(
              '${device.target.isEmpty ? '广播 255.255.255.255' : '目标 ${device.target}'}'
              ' · UDP ${device.port}$probeName',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.textTertiary,
              ),
            ),
            SizedBox(height: m.kSpace12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: waking ? null : () => _wake(device),
                    icon: waking
                        ? SizedBox(
                            width: m.iconSize18,
                            height: m.iconSize18,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          )
                        : DrawIcon(StrokeIcons.electricBolt, size: m.iconSize18),
                    label: Text(waking ? '唤醒中' : '唤醒'),
                  ),
                ),
                SizedBox(width: m.kSpace4),
                IconButton(
                  onPressed: () => _showEditor(initial: device),
                  icon: DrawIcon(StrokeIcons.edit),
                  iconSize: m.iconSize18,
                  tooltip: '编辑',
                ),
                IconButton(
                  onPressed: () => _confirmRemove(device),
                  icon: DrawIcon(StrokeIcons.deleteOutline),
                  iconSize: m.iconSize18,
                  tooltip: '删除',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  AppStatusRole _statusTone(AppSemantic s, WakeStatus status) {
    switch (status) {
      case WakeStatus.waking:
        return s.warning;
      case WakeStatus.sent:
        return s.info;
      case WakeStatus.online:
        return s.success;
      case WakeStatus.timeout:
      case WakeStatus.failed:
        return s.danger;
      case WakeStatus.idle:
        return s.neutral;
    }
  }

  String _statusLabel(WakeStatus status) {
    switch (status) {
      case WakeStatus.idle:
        return '待唤醒';
      case WakeStatus.waking:
        return '唤醒中';
      case WakeStatus.sent:
        return '已发送';
      case WakeStatus.online:
        return '已上线';
      case WakeStatus.timeout:
        return '未确认上线';
      case WakeStatus.failed:
        return '发送失败';
    }
  }
}

/// 编辑弹窗回传的表单值
class _WakeEditorValue {
  const _WakeEditorValue({
    required this.name,
    required this.mac,
    required this.target,
    required this.port,
    required this.mode,
    required this.relayNodeId,
    required this.probeNodeId,
  });

  final String name;
  final String mac;
  final String target;
  final int port;
  final WakeMode mode;
  final String relayNodeId;
  final String probeNodeId;
}

class _WakeEditorDialog extends StatefulWidget {
  const _WakeEditorDialog({this.initial, required this.nodes});

  final WakeDevice? initial;
  final List<NodeEndpoint> nodes;

  @override
  State<_WakeEditorDialog> createState() => _WakeEditorDialogState();
}

class _WakeEditorDialogState extends State<_WakeEditorDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _macCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _portCtrl;
  late WakeMode _mode;
  late String _relayNodeId;
  late String _probeNodeId;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameCtrl = TextEditingController(text: initial?.name ?? '');
    _macCtrl = TextEditingController(text: initial?.mac ?? '');
    _targetCtrl = TextEditingController(text: initial?.target ?? '');
    _portCtrl = TextEditingController(text: (initial?.port ?? 9).toString());
    _mode = initial?.mode ?? WakeMode.relay;
    _relayNodeId = initial?.relayNodeId ?? '';
    _probeNodeId = initial?.probeNodeId ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _macCtrl.dispose();
    _targetCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9;
    Navigator.of(context).pop(
      _WakeEditorValue(
        name: _nameCtrl.text.trim(),
        mac: _macCtrl.text.trim(),
        target: _targetCtrl.text.trim(),
        port: port <= 0 || port > 65535 ? 9 : port,
        mode: _mode,
        relayNodeId: _relayNodeId,
        probeNodeId: _probeNodeId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final relayMode = _mode == WakeMode.relay;

    return AlertDialog(
      title: Text(widget.initial == null ? '添加设备' : '编辑设备'),
      content: SizedBox(
        width: scaleW(420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: '设备名'),
              ),
              SizedBox(height: m.kSpace12),
              AppTextField(
                controller: _macCtrl,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'MAC 地址',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
              ),
              SizedBox(height: m.kSpace16),
              Text('唤醒方式', style: AppTextStyles.cardTitle(context)),
              SizedBox(height: m.kSpace8),
              Wrap(
                spacing: m.kSpace8,
                children: [
                  ChoiceChip(
                    label: const Text('节点中继'),
                    selected: relayMode,
                    onSelected: (_) => setState(() => _mode = WakeMode.relay),
                  ),
                  ChoiceChip(
                    label: const Text('本机直发'),
                    selected: !relayMode,
                    onSelected: (_) => setState(() => _mode = WakeMode.direct),
                  ),
                ],
              ),
              if (relayMode) ...[
                SizedBox(height: m.kSpace12),
                if (widget.nodes.isEmpty)
                  Text(
                    '暂无远程节点，请先在设置中添加局域网内的常开节点',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: s.danger.color,
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue:
                        widget.nodes.any((n) => n.id == _relayNodeId) ? _relayNodeId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '中继节点'),
                    items: widget.nodes
                        .map(
                          (n) => DropdownMenuItem(
                            value: n.id,
                            child: Text(n.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _relayNodeId = value ?? ''),
                  ),
              ],
              SizedBox(height: m.kSpace12),
              AppTextField(
                controller: _targetCtrl,
                decoration: InputDecoration(
                  labelText: '目标地址（可选）',
                  hintText: relayMode ? '留空为 255.255.255.255' : '公网地址或 192.168.x.255',
                ),
              ),
              SizedBox(height: m.kSpace12),
              AppTextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'UDP 端口', hintText: '9'),
              ),
              if (widget.nodes.isNotEmpty) ...[
                SizedBox(height: m.kSpace12),
                DropdownButtonFormField<String>(
                  initialValue: widget.nodes.any((n) => n.id == _probeNodeId)
                      ? _probeNodeId
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '上线检测节点（可选）'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('不检测')),
                    ...widget.nodes.map(
                      (n) => DropdownMenuItem(
                        value: n.id,
                        child: Text(n.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _probeNodeId = value ?? ''),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
