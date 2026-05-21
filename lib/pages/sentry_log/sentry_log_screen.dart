import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_filter_bar.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_list.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_stats_panel.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';

/// 日志中心页面
class SentryLogScreen extends StatefulWidget {
  const SentryLogScreen({super.key});

  @override
  State<SentryLogScreen> createState() => _SentryLogScreenState();
}

class _SentryLogScreenState extends State<SentryLogScreen> with TickerProviderStateMixin {
  late SentryLogViewModel _viewModel;
  late TabController _tabController;
  SentrySettingsService? _sentrySettings;
  NodeSettingsService? _nodeService;

  // 节点状态监听
  StreamSubscription? _nodeListSub;
  StreamSubscription? _nodeConnectivitySub;
  StreamSubscription? _currentNodeSub;

  // 入场动画控制器
  late final AnimationController _entranceController;
  late final Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _viewModel = Get.put(SentryLogViewModel());
    _tabController = TabController(length: 2, vsync: this);
    _sentrySettings = GetIt.instance.get<SentrySettingsService>();
    _nodeService = GetIt.instance.get<NodeSettingsService>();

    // 入场动画：淡入 + 上滑
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic);

    _nodeListSub = _nodeService!.remoteNodes.listen((_) {
      if (mounted) setState(() {});
    });
    _nodeConnectivitySub = _nodeService!.nodeConnectivity.listen((_) {
      if (mounted) setState(() {});
    });
    _currentNodeSub = _viewModel.currentNodeId.listen((_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.loadInitialData();
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _nodeListSub?.cancel();
    _nodeConnectivitySub?.cancel();
    _currentNodeSub?.cancel();
    _tabController.dispose();
    _entranceController.dispose();
    try {
      Get.delete<SentryLogViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '日志中心',
        actions: [
          _buildNodeSwitcher(context, theme, m, isDark),
          SizedBox(width: m.kSpace8),
          _buildActionButton(
            context: context,
            icon: Icons.refresh_rounded,
            tooltip: '刷新',
            onPressed: () => _viewModel.reloadData(),
            isDark: isDark,
          ),
          _buildActionButton(
            context: context,
            icon: Icons.download_outlined,
            tooltip: '导出',
            onPressed: () => _exportLogs(context),
            isDark: isDark,
          ),
        ],
      ),
      child: Container(
        color: isDark ? DarkColors.background3 : LightColors.background3,
        child: AnimatedBuilder(
          animation: _entranceAnimation,
          builder: (context, _) {
            return Opacity(
              opacity: _entranceAnimation.value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - _entranceAnimation.value)),
                child: Column(
                  children: [
                    SentryLogFilterBar(
                      viewModel: _viewModel,
                      onFilterChanged: () => _viewModel.applyFilter(),
                    ),
                    _buildTabBar(context, theme, m, isDark),
                    SizedBox(height: m.kSpace12),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          SentryLogList(viewModel: _viewModel),
                          SentryLogStatsPanel(viewModel: _viewModel),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建毛玻璃风格 TabBar
  Widget _buildTabBar(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? DarkColors.background1.withAlpha(200)
                  : LightColors.background1.withAlpha(220),
              borderRadius: m.radius12,
              border: Border.all(
                color: isDark
                    ? DarkColors.white10.withAlpha(40)
                    : LightColors.black10.withAlpha(30),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? DarkColors.black10 : LightColors.black10,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: (isDark ? DarkColors.primary : LightColors.primary).withAlpha(6),
                  blurRadius: scaleW(20),
                  offset: Offset(0, scaleW(4)),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 3),
                insets: EdgeInsets.symmetric(horizontal: -m.kSpace8),
              ),
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.hintColor,
              labelStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
              dividerColor: Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24),
              tabs: [
                Tab(
                  height: m.kSpace40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.list_alt_rounded, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      const Text('日志列表'),
                    ],
                  ),
                ),
                Tab(
                  height: m.kSpace40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.insights_rounded, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      const Text('统计'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建节点切换器
  Widget _buildNodeSwitcher(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    if (_sentrySettings == null || _nodeService == null) return const SizedBox.shrink();

    final currentNodeId = _viewModel.currentNodeId.value;
    final remoteNodes = _nodeService!.enabledRemoteNodes;

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: '',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.computer, size: m.iconSize16, color: theme.hintColor),
            SizedBox(width: m.kSpace4),
            const Text('本机'),
          ],
        ),
      ),
      ...remoteNodes.map((node) {
        final ok = _nodeService!.nodeConnectivity[node.id] == true;
        return DropdownMenuItem<String>(
          value: node.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined, size: m.iconSize16, color: ok ? Colors.green : Colors.red),
              SizedBox(width: m.kSpace4),
              Text(node.name, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }),
    ];

    return Container(
      height: m.kSpace32,
      decoration: BoxDecoration(
        color: isDark
            ? DarkColors.background2.withAlpha(180)
            : LightColors.background2.withAlpha(200),
        borderRadius: m.radius8,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: (isDark ? DarkColors.primary : LightColors.primary).withAlpha(8),
            blurRadius: scaleW(8),
            offset: Offset(0, scaleW(2)),
          ),
        ],
      ),
      child: DropdownButton<String>(
        value: currentNodeId.isEmpty ? '' : currentNodeId,
        icon: Icon(Icons.swap_horiz, size: m.iconSize16, color: theme.hintColor),
        style: theme.textTheme.bodySmall,
        underline: const SizedBox.shrink(),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace8),
        items: items,
        onChanged: (value) async {
          if (value != null && value != currentNodeId) {
            await _viewModel.switchNode(value);
          }
        },
      ),
    );
  }

  /// 构建操作按钮（带悬停发光效果）
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return _ActionButtonWidget(icon: icon, tooltip: tooltip, onPressed: onPressed, isDark: isDark);
  }

  /// 导出日志到本地文件
  void _exportLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await _viewModel.exportLogs();
      if (json.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('没有可导出的日志'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppTheme.metrics.radius8),
          ),
        );
        return;
      }

      final directory = await _getExportDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('$directory/sentry_log_export_$timestamp.json');
      await file.writeAsString(json);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('日志已导出到: $directory/sentry_log_export_$timestamp.json'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppTheme.metrics.radius8),
        ),
      );
    } catch (e) {
      logger.e('导出日志失败: $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppTheme.metrics.radius8),
        ),
      );
    }
  }

  /// 获取导出目录路径
  Future<String> _getExportDirectory() async {
    if (Platform.isMacOS || Platform.isWindows) {
      return '${Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.'}/Downloads';
    }
    return '.';
  }
}

/// 操作按钮组件（带悬停发光 + 缩放动画）
class _ActionButtonWidget extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDark;

  const _ActionButtonWidget({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.isDark,
  });

  @override
  State<_ActionButtonWidget> createState() => _ActionButtonWidgetState();
}

class _ActionButtonWidgetState extends State<_ActionButtonWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.only(right: m.kSpace4),
          padding: EdgeInsets.all(m.kSpace8),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.isDark ? DarkColors.white10 : LightColors.black10).withAlpha(
                    widget.isDark ? 40 : 30,
                  )
                : Colors.transparent,
            borderRadius: m.radius8,
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: (widget.isDark ? DarkColors.primary : LightColors.primary).withAlpha(
                        15,
                      ),
                      blurRadius: scaleW(12),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: _hovered ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Icon(
              widget.icon,
              size: m.iconSize18,
              color: widget.isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
        ),
      ),
    );
  }
}
