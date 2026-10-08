import 'package:flutter/material.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

typedef NodeAvailabilityChecker = Future<bool> Function(String baseUrl);

class NodeSwitcherButton extends StatelessWidget {
  final NodeSettingsService nodeService;
  final String currentNodeId;
  final ValueChanged<String> onNodeSelected;
  final NodeAvailabilityChecker? availabilityChecker;

  const NodeSwitcherButton({
    super.key,
    required this.nodeService,
    required this.currentNodeId,
    required this.onNodeSelected,
    this.availabilityChecker,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final isLocal = currentNodeId.isEmpty;
    final accent = s.accent;

    String label;
    StrokeIcon iconData;
    Color dotColor;
    if (isLocal) {
      label = '本机';
      iconData = StrokeIcons.computer;
      dotColor = s.success.color;
    } else {
      final node = nodeService.getNodeById(currentNodeId);
      final ok = nodeService.nodeConnectivity[currentNodeId] == true;
      label = node?.name ?? '未知';
      iconData = StrokeIcons.dns;
      dotColor = ok ? s.success.color : s.danger.color;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radiusPill,
        onTap: () => _showNodePanel(context),
        child: Container(
          height: m.kSpace32,
          padding: EdgeInsets.only(left: m.kSpace10, right: m.kSpace6),
          decoration: BoxDecoration(
            // 胶囊底是半透明浮起面：原先按明暗手挑 DarkColors/LightColors.background2，
            // 语义层里对应 surfaceRaised，透明度只留一档。
            color: s.surfaceRaised.withAlpha(220),
            borderRadius: m.radiusPill,
            border: Border.all(
              color: isLocal ? s.border : accent.withAlpha(60),
              width: isLocal ? 0.5 : 1.2,
            ),
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
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withAlpha(80),
                      blurRadius: scaleW(4),
                      spreadRadius: scaleW(0.5),
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.kSpace6),
              DrawIcon(iconData, size: m.iconSize14, color: isLocal ? s.textTertiary : accent),
              SizedBox(width: m.kSpace4),
              Text(
                label,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  weight: FontWeight.w500,
                  color: isLocal ? s.textSecondary : accent,
                ),
                // 节点名会随界面字号变长，胶囊行宁可截断不许顶破
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(width: m.kSpace2),
              DrawIcon(StrokeIcons.unfoldMore,
                size: m.iconSize12,
                color: s.textTertiary.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodePanel(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final accent = s.accent;
    final remoteNodes = nodeService.enabledRemoteNodes;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: s.scrim,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.55),
          margin: EdgeInsets.all(m.kSpace12),
          // 原来底色按 isDark 手挑 DarkColors/LightColors.background1（实心、和主题脱钩），
          // 投影也是手搓的两层。换成语义层：浮层配色、玻璃描边、投影档位全站一个口径。
          decoration: BoxDecoration(
            color: s.surfaceRaised.withAlpha(WindowGlass.overlayAlpha),
            borderRadius: m.radiusPanel,
            border: Border.all(color: s.glassBorder, width: scaleW(1)),
            boxShadow: s.elevation(Elevation.overlay),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(m.kSpace20, m.kSpace16, m.kSpace20, m.kSpace4),
                child: Row(
                  children: [
                    Container(
                      width: m.kSpace24,
                      height: m.kSpace24,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(20),
                        borderRadius: m.radius8,
                      ),
                      child: DrawIcon(StrokeIcons.hub, size: m.iconSize14, color: accent),
                    ),
                    SizedBox(width: m.kSpace10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择数据节点',
                            style: AppTextStyles.sectionTitle(sheetCtx),
                          ),
                          SizedBox(height: m.kSpace2),
                          Text(
                            '切换后界面数据来自所选节点',
                            style: AppTextStyles.caption(sheetCtx),
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: m.radius10,
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        child: Padding(
                          padding: EdgeInsets.all(m.kSpace4),
                          child: DrawIcon(StrokeIcons.close,
                            size: m.iconSize18,
                            color: s.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: m.kSpace1,
                thickness: 0.5,
                color: s.hairline,
                indent: m.kSpace20,
                endIndent: m.kSpace20,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NodePanelItem(
                        id: '',
                        label: '本机',
                        subtitle: '使用本地数据',
                        icon: StrokeIcons.computer,
                        isSelected: currentNodeId.isEmpty,
                        isAvailable: true,
                        accent: accent,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          onNodeSelected('');
                        },
                      ),
                      if (remoteNodes.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: m.kSpace20,
                            vertical: m.kSpace6,
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: m.kSpace44),
                              Expanded(
                                child: Container(
                                  height: 0.5,
                                  color: s.hairline,
                                ),
                              ),
                              SizedBox(width: m.kSpace44),
                            ],
                          ),
                        ),
                      ...remoteNodes.map((node) {
                        final ok = nodeService.nodeConnectivity[node.id] == true;
                        return _NodePanelItem(
                          id: node.id,
                          label: node.name,
                          subtitle: ok ? '连接正常' : '不可达',
                          icon: StrokeIcons.dns,
                          isSelected: currentNodeId == node.id,
                          isAvailable: ok,
                          accent: accent,
                          onTap: () async {
                            if (!ok) {
                              Navigator.of(sheetCtx).pop();
                              _showSnack('节点不可达，请检查节点设置');
                              return;
                            }
                            if (availabilityChecker != null) {
                              // 用服务层的"最近应答地址"，不用配置里内网优先的那一条：
                              // 手机出了局域网，内网地址根本够不着，探测超时就会被
                              // 误报成「该节点不支持此功能」。
                              final available = await availabilityChecker!(
                                nodeService.getNodeEffectiveBaseUrl(node.id),
                              );
                              if (!sheetCtx.mounted) return;
                              if (!available) {
                                Navigator.of(sheetCtx).pop();
                                _showSnack('该节点不支持此功能');
                                return;
                              }
                            }
                            Navigator.of(sheetCtx).pop();
                            onNodeSelected(node.id);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
              SizedBox(height: m.kSpace8),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _OverlaySnackBar(message: message, onDismissed: () => entry.remove()),
      );
      overlay.insert(entry);
    });
  }
}

class _NodePanelItem extends StatelessWidget {
  final String id;
  final String label;
  final String subtitle;
  final StrokeIcon icon;
  final bool isSelected;
  final bool isAvailable;
  final Color accent;
  final VoidCallback onTap;

  const _NodePanelItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.isAvailable,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    final dotColor = isAvailable ? (isSelected ? accent : s.success.color) : s.danger.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius12,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace2),
          padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
          decoration: BoxDecoration(
            // 选中底走低浓度强调容器，未选中占位底走 surfaceSunken
            color: isSelected ? s.accentContainer : Colors.transparent,
            borderRadius: m.radius12,
            border: isSelected ? Border.all(color: accent.withAlpha(80), width: 1.2) : null,
          ),
          child: Row(
            children: [
              Container(
                width: m.kSpace32,
                height: m.kSpace32,
                decoration: BoxDecoration(
                  // 选中时图标底板比行底更实一档，避免两层同色后失去边界
                color: isSelected ? accent.withAlpha(28) : s.surfaceSunken,
                  borderRadius: m.radius10,
                ),
                child: DrawIcon(icon,
                  size: m.iconSize18,
                  color: isSelected ? accent : (isAvailable ? s.textTertiary : s.textDisabled),
                ),
              ),
              SizedBox(width: m.kSpace12),
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
                    SizedBox(height: m.kSpace1),
                    Text(
                      subtitle,
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize11,
                        color: isAvailable ? s.textTertiary : s.textDisabled,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.kSpace8),
              Container(
                width: m.kSpace8,
                height: m.kSpace8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: dotColor.withAlpha(80),
                            blurRadius: scaleW(4),
                            spreadRadius: scaleW(0.5),
                          ),
                        ]
                      : null,
                ),
              ),
              if (isSelected) ...[
                SizedBox(width: m.kSpace6),
                DrawIcon(StrokeIcons.checkCircle, size: m.iconSize18, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlaySnackBar extends StatefulWidget {
  final String message;
  final VoidCallback onDismissed;

  const _OverlaySnackBar({required this.message, required this.onDismissed});

  @override
  State<_OverlaySnackBar> createState() => _OverlaySnackBarState();
}

class _OverlaySnackBarState extends State<_OverlaySnackBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _opacity = CurvedAnimation(parent: _controller, curve: AppMotion.decelerate);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.decelerate));
    _controller.forward();
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final snackBarContext = navigatorKey.currentContext ?? context;
    final s = AppSemantic.of(snackBarContext);
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + scaleW(16),
      left: m.kSpace16,
      right: m.kSpace16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            elevation: 6,
            borderRadius: m.radius12,
            color: s.surfaceRaised,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
              decoration: BoxDecoration(
                borderRadius: m.radius12,
                border: Border.all(
                  color: s.border,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  DrawIcon(StrokeIcons.infoOutline,
                    size: m.iconSize18,
                    color: s.accent,
                  ),
                  SizedBox(width: m.kSpace10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: AppTextStyles.role(
                        snackBarContext,
                        fontSize: m.fontSize13,
                        color: s.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
