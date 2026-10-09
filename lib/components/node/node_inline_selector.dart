import 'package:flutter/material.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

typedef NodeSelectorAvailabilityChecker = Future<bool> Function(String baseUrl);

class NodeInlineSelector extends StatelessWidget {
  final NodeSettingsService nodeService;
  final String selectedNodeId;
  final ValueChanged<String> onNodeSelected;
  final NodeSelectorAvailabilityChecker? availabilityChecker;
  final String moduleName;

  const NodeInlineSelector({
    super.key,
    required this.nodeService,
    required this.selectedNodeId,
    required this.onNodeSelected,
    this.availabilityChecker,
    this.moduleName = '此功能',
  });

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final localNodeEnabled = nodeService.localNodeEnabled.value;
    final remoteNodes = nodeService.enabledRemoteNodes;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
      decoration: BoxDecoration(
        // 面板底色是中性半透明水洗（原先按明暗手写 black@4 / white@8），
        // 语义层里对应的就是永远朝"看得见"一侧走的 surfaceHover。
        color: s.surfaceHover,
        borderRadius: m.radius8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOption(
            context: context,
            nodeId: '',
            label: '本机',
            subtitle: localNodeEnabled ? '本机节点服务运行中' : '本机节点未启用',
            icon: StrokeIcons.computer,
            isSelected: selectedNodeId.isEmpty,
            isAvailable: true,
          ),
          if (remoteNodes.isNotEmpty)
            ...remoteNodes.map((node) {
              final ok = nodeService.nodeConnectivity[node.id] == true;
              return _buildOption(
                context: context,
                nodeId: node.id,
                label: node.name,
                subtitle: '${node.effectiveApiBaseUrl}${ok ? '' : ' (不可达)'}',
                icon: StrokeIcons.dns,
                isSelected: selectedNodeId == node.id,
                isAvailable: ok,
              );
            }),
          if (!localNodeEnabled && remoteNodes.isEmpty)
            Padding(
              padding: EdgeInsets.all(m.kSpace12),
              child: Text(
                '暂无可用节点，请在节点设置中添加或启用节点',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  color: s.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required String nodeId,
    required String label,
    required String subtitle,
    required StrokeIcon icon,
    required bool isSelected,
    required bool isAvailable,
  }) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final accent = s.accent;

    return InkWell(
      borderRadius: m.radius8,
      onTap: () async {
        if (nodeId == selectedNodeId) return;
        if (!isAvailable) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: const Text('节点不可达，请检查节点设置'), behavior: SnackBarBehavior.floating),
            );
          return;
        }
        if (nodeId.isNotEmpty && availabilityChecker != null) {
          final node = nodeService.getNodeById(nodeId);
          if (node == null) return;
          // 探的是"这台设备此刻真能用的那一路地址"：effectiveApiBaseUrl 是配置里的
          // 内网优先，手机出了局域网就压死在够不着的内网地址上，节点明明开着这个
          // 功能也会被回一句「该节点不支持」。走服务层的最近应答地址，和真实请求同路。
          final available = await availabilityChecker!(
            nodeService.getNodeEffectiveBaseUrl(nodeId),
          );
          if (!available) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text('该节点不支持$moduleName'), behavior: SnackBarBehavior.floating),
              );
            return;
          }
        }
        onNodeSelected(nodeId);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
        decoration: BoxDecoration(
          border: isSelected ? Border.all(color: accent, width: AppTheme.metrics.strokeThin) : null,
          borderRadius: m.radius8,
          // 选中底走低浓度强调容器，不再手搓 accent@alpha
          color: isSelected ? s.accentContainer : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                // 选中时图标底板要比行底更实一档，否则两者同色就等于抹平了层次；
                // 未选中走图标占位底（surfaceSunken 的既定用途）
                color: isSelected ? accent.withAlpha(28) : s.surfaceSunken,
                borderRadius: m.radius8,
              ),
              child: DrawIcon(icon,
                size: m.iconSize16,
                color: isSelected ? accent : (isAvailable ? s.textTertiary : s.textDisabled),
              ),
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize13,
                      weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isAvailable ? s.textPrimary : s.textDisabled,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      color: isAvailable ? s.textTertiary : s.textDisabled,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected) DrawIcon(StrokeIcons.check, size: m.iconSize18, color: accent),
          ],
        ),
      ),
    );
  }
}
