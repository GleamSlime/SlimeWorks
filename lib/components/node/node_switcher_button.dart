import 'package:flutter/material.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isLocal = currentNodeId.isEmpty;
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;

    String label;
    IconData iconData;
    Color dotColor;
    if (isLocal) {
      label = '本机';
      iconData = Icons.computer_rounded;
      dotColor = LightColors.green;
    } else {
      final node = nodeService.getNodeById(currentNodeId);
      final ok = nodeService.nodeConnectivity[currentNodeId] == true;
      label = node?.name ?? '未知';
      iconData = Icons.dns_rounded;
      dotColor = ok ? LightColors.green : LightColors.red;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius20,
        onTap: () => _showNodePanel(context),
        child: Container(
          height: m.kSpace32,
          padding: EdgeInsets.only(left: m.kSpace10, right: m.kSpace6),
          decoration: BoxDecoration(
            color: isDark
                ? DarkColors.background2.withAlpha(200)
                : LightColors.background2.withAlpha(220),
            borderRadius: m.radius20,
            border: Border.all(
              color: isLocal
                  ? (isDark ? DarkColors.white10 : LightColors.black10)
                  : accent.withAlpha(60),
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
              Icon(iconData, size: m.iconSize14, color: isLocal ? theme.hintColor : accent),
              SizedBox(width: m.kSpace4),
              Text(
                label,
                style: TextStyle(
                  fontSize: m.fontSize12,
                  fontWeight: FontWeight.w500,
                  color: isLocal ? theme.colorScheme.onSurface.withAlpha(180) : accent,
                ),
              ),
              SizedBox(width: m.kSpace2),
              Icon(
                Icons.unfold_more_rounded,
                size: m.iconSize12,
                color: theme.hintColor.withAlpha(120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodePanel(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final remoteNodes = nodeService.enabledRemoteNodes;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: isDark ? DarkColors.overlay : LightColors.overlay.withAlpha(120),
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.55),
          margin: EdgeInsets.all(m.kSpace12),
          decoration: BoxDecoration(
            color: isDark ? DarkColors.background1 : LightColors.background1,
            borderRadius: m.radius16,
            border: Border.all(
              color: isDark ? DarkColors.white10 : LightColors.black10,
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(40),
                blurRadius: scaleW(24),
                offset: Offset(0, scaleW(8)),
              ),
              BoxShadow(
                color: accent.withAlpha(12),
                blurRadius: scaleW(48),
                offset: Offset(0, scaleW(2)),
              ),
            ],
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
                      child: Icon(Icons.hub_rounded, size: m.iconSize14, color: accent),
                    ),
                    SizedBox(width: m.kSpace10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择数据节点',
                            style: TextStyle(
                              fontSize: m.fontSize15,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: m.kSpace2),
                          Text(
                            '切换后界面数据来自所选节点',
                            style: TextStyle(
                              fontSize: m.fontSize11,
                              color: theme.colorScheme.onSurface.withAlpha(100),
                            ),
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
                          child: Icon(
                            Icons.close_rounded,
                            size: m.iconSize18,
                            color: theme.hintColor,
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
                color: theme.colorScheme.outlineVariant.withAlpha(60),
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
                        icon: Icons.computer_rounded,
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
                                  color: theme.colorScheme.outlineVariant.withAlpha(40),
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
                          icon: Icons.dns_rounded,
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
                              final available = await availabilityChecker!(
                                node.effectiveApiBaseUrl,
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
  final IconData icon;
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
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;

    final dotColor = isAvailable ? (isSelected ? accent : LightColors.green) : LightColors.red;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: m.radius12,
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace2),
          padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace10),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(isDark ? 25 : 18) : Colors.transparent,
            borderRadius: m.radius12,
            border: isSelected ? Border.all(color: accent.withAlpha(80), width: 1.2) : null,
          ),
          child: Row(
            children: [
              Container(
                width: m.kSpace32,
                height: m.kSpace32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withAlpha(25)
                      : (isDark ? DarkColors.white10 : LightColors.black5),
                  borderRadius: m.radius10,
                ),
                child: Icon(
                  icon,
                  size: m.iconSize18,
                  color: isSelected
                      ? accent
                      : (isAvailable
                            ? theme.colorScheme.onSurface.withAlpha(120)
                            : theme.disabledColor),
                ),
              ),
              SizedBox(width: m.kSpace12),
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
                    SizedBox(height: m.kSpace1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: m.fontSize11,
                        color: isAvailable
                            ? theme.colorScheme.onSurface.withAlpha(80)
                            : theme.disabledColor.withAlpha(120),
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
                Icon(Icons.check_circle_rounded, size: m.iconSize18, color: accent),
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
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
    final theme = Theme.of(navigatorKey.currentContext ?? context);
    final isDark = theme.brightness == Brightness.dark;
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
            color: isDark ? DarkColors.background2 : LightColors.background2,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
              decoration: BoxDecoration(
                borderRadius: m.radius12,
                border: Border.all(
                  color: isDark ? DarkColors.white10 : LightColors.black10,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: m.iconSize18,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: m.kSpace10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: TextStyle(fontSize: m.fontSize13, color: theme.colorScheme.onSurface),
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
