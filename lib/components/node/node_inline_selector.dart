import 'package:flutter/material.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';

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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
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
          _buildOption(
            context: context,
            nodeId: '',
            label: '本机',
            subtitle: localNodeEnabled ? '本机节点服务运行中' : '本机节点未启用',
            icon: Icons.computer,
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
                subtitle: '${node.apiBaseUrl}${ok ? '' : ' (不可达)'}',
                icon: Icons.dns_outlined,
                isSelected: selectedNodeId == node.id,
                isAvailable: ok,
              );
            }),
          if (!localNodeEnabled && remoteNodes.isEmpty)
            Padding(
              padding: EdgeInsets.all(m.kSpace12),
              child: Text(
                '暂无可用节点，请在节点设置中添加或启用节点',
                style: TextStyle(fontSize: m.fontSize12, color: theme.hintColor),
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
    required IconData icon,
    required bool isSelected,
    required bool isAvailable,
  }) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final accent = theme.colorScheme.primary;

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
          final available = await availabilityChecker!(node.apiBaseUrl);
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
          border: isSelected ? Border.all(color: accent, width: 1.5) : null,
          borderRadius: m.radius8,
          color: isSelected ? accent.withAlpha(20) : Colors.transparent,
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withAlpha(25)
                    : (theme.brightness == Brightness.dark
                          ? DarkColors.white10
                          : LightColors.black5),
                borderRadius: m.radius8,
              ),
              child: Icon(
                icon,
                size: m.iconSize16,
                color: isSelected ? accent : (isAvailable ? theme.hintColor : theme.disabledColor),
              ),
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isAvailable ? theme.colorScheme.onSurface : theme.disabledColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      color: isAvailable ? theme.hintColor : theme.disabledColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, size: m.iconSize18, color: accent),
          ],
        ),
      ),
    );
  }
}
