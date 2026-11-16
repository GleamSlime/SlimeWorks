import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/routes/app_sidebars.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 侧栏「节点」菜单：显示当前全局节点，点开后切换「本机」或任一启用节点。
///
/// 只在配置了远程节点时出现（由调用方判断），没有节点时整行不占位。
class SidebarNodeSelector extends StatelessWidget {
  /// 侧栏是否展开：展开态显示文案，收起态只留一枚图标。
  final bool isExpanded;

  /// 文字是否已揭示（侧栏宽度动画结束）；false 时先只显示图标位。
  final bool showExtends;

  const SidebarNodeSelector({
    super.key,
    required this.isExpanded,
    required this.showExtends,
  });

  @override
  Widget build(BuildContext context) {
    final nodeService = getIt<NodeSettingsService>();
    final m = AppTheme.metrics;

    return Obx(() {
      final nodes = nodeService.enabledRemoteNodes;
      if (nodes.isEmpty) {
        return const SizedBox.shrink();
      }
      final active = nodeService.activeNode;
      final label = active?.name ?? '本机';
      final s = AppSemantic.of(context);
      final isRemote = active != null;

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isExpanded ? m.kSpace10 : m.kSpace12,
          vertical: m.kSpace2,
        ),
        child: PopupMenuButton<String>(
          tooltip: '切换节点',
          padding: EdgeInsets.zero,
          initialValue: nodeService.activeNodeId.value,
          onSelected: (nodeId) async {
            await nodeService.selectActiveNode(nodeId);
            // 切到远程节点时，当前页可能是不支持远程的入口：直接回概览，
            // 避免停在一个"数据还是本机"的页面上。
            if (nodeService.isRemoteMode) {
              final path = goRouter.state.uri.path;
              if (remoteUnsupportedPath(path)) {
                goRouter.go('/dashboard');
              }
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _buildOption(context, id: '', name: '本机', selected: !isRemote),
            for (final node in nodes)
              _buildOption(
                context,
                id: node.id,
                name: node.name,
                selected: active?.id == node.id,
              ),
          ],
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: m.kSpace8,
              vertical: m.kSpace8,
            ),
            decoration: BoxDecoration(
              color: isRemote ? s.accentContainer : Colors.transparent,
              borderRadius: m.radius8,
            ),
            child: Row(
              mainAxisAlignment:
                  isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                DrawIcon(
                  StrokeIcons.dns,
                  size: isExpanded ? m.fontSize18 : 18,
                  color: isRemote ? s.accent : s.textTertiary,
                  duration: AppMotion.emphasis,
                ),
                if (isExpanded && showExtends) ...[
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: AppMotion.base,
                      opacity: showExtends ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '节点',
                            style: TextStyle(
                              fontSize: m.fontSize11,
                              color: s.textTertiary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: m.fontSize13,
                              color: isRemote ? s.accent : s.textPrimary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  DrawIcon(
                    StrokeIcons.expandMore,
                    size: m.iconSize14,
                    color: s.textTertiary,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }

  PopupMenuItem<String> _buildOption(
    BuildContext context, {
    required String id,
    required String name,
    required bool selected,
  }) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return PopupMenuItem<String>(
      value: id,
      child: Row(
        children: [
          DrawIcon(
            id.isEmpty ? StrokeIcons.computer : StrokeIcons.dns,
            size: m.iconSize16,
            color: selected ? s.accent : s.textTertiary,
          ),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: m.fontSize13,
                color: selected ? s.accent : s.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (selected) DrawIcon(StrokeIcons.check, size: m.iconSize16, color: s.accent),
        ],
      ),
    );
  }
}
