import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/node/node_switcher_button.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/pages/sentry_log/components/app_log_terminal.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_filter_bar.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_list.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_stats_panel.dart';
import 'package:slime_works/view_models/sentry_log/app_log_viewmodel.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

const Loggers _logger = Loggers(name: 'Sentry日志');

/// 日志中心页面
class SentryLogScreen extends StatefulWidget {
  const SentryLogScreen({super.key});

  @override
  State<SentryLogScreen> createState() => _SentryLogScreenState();
}

class _SentryLogScreenState extends State<SentryLogScreen> with TickerProviderStateMixin {
  late SentryLogViewModel _viewModel;
  late AppLogViewModel _appLogViewModel;
  late TabController _tabController;
  SentrySettingsService? _sentrySettings;
  NodeSettingsService? _nodeService;

  bool _showAppLogs = false;

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
    _appLogViewModel = Get.put(AppLogViewModel());
    _tabController = TabController(length: 2, vsync: this);
    _sentrySettings = GetIt.instance.get<SentrySettingsService>();
    _nodeService = GetIt.instance.get<NodeSettingsService>();

    // 入场动画：淡入 + 上滑
    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: AppMotion.decelerate);

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
    try {
      Get.delete<AppLogViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);

    return ScreenChrome(
      data: ScreenChromeData(
        title: _showAppLogs ? '应用日志' : '日志中心',
        actions: [
          if (!_showAppLogs) ...[
            _buildNodeSwitcher(context, theme, m, s),
            SizedBox(width: m.kSpace8),
          ],
          _buildAppLogToggle(context, theme, m, s),
          SizedBox(width: m.kSpace4),
          if (!_showAppLogs) ...[
            _buildActionButton(
              context: context,
              icon: StrokeIcons.refresh,
              tooltip: '刷新',
              onPressed: () => _viewModel.reloadData(),
            ),
            _buildActionButton(
              context: context,
              icon: StrokeIcons.download,
              tooltip: '导出',
              onPressed: () => _exportLogs(context),
            ),
          ],
        ],
      ),
      child: Container(
        // color: Colors.red,
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _entranceAnimation,
          builder: (context, _) {
            return Opacity(
              opacity: _entranceAnimation.value.clamp(0.0, 1.0),
              child: Transform.translate(
                // 位移走宽度族：窗口拖大时上浮距离要跟着长
                offset: Offset(0, scaleW(16) * (1 - _entranceAnimation.value)),
                child: _showAppLogs
                    ? AppLogTerminal(viewModel: _appLogViewModel)
                    : Column(
                        children: [
                          SentryLogFilterBar(
                            viewModel: _viewModel,
                            onFilterChanged: () => _viewModel.applyFilter(),
                          ),
                          _buildTabBar(context, theme, m, s),
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
  Widget _buildTabBar(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: m.kSpace16),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
          child: Container(
            decoration: BoxDecoration(
              color: s.glassTint,
              borderRadius: m.radius12,
              border: Border.all(color: s.glassBorder, width: AppTheme.metrics.strokeUltraThin),
              boxShadow: [
                m.boxShadow10,
                BoxShadow(
                  color: s.accent.withAlpha(6),
                  blurRadius: scaleW(20),
                  offset: Offset(0, scaleW(4)),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: s.accent, width: 3),
                insets: EdgeInsets.symmetric(horizontal: -m.kSpace8),
              ),
              labelColor: s.accent,
              unselectedLabelColor: s.textTertiary,
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
                      DrawIcon(StrokeIcons.listAlt, size: m.iconSize16),
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
                      DrawIcon(StrokeIcons.insights, size: m.iconSize16),
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

  Widget _buildAppLogToggle(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    final activeRole = s.success;
    final activeColor = activeRole.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _appLogToggleHovered = true),
      onExit: (_) => setState(() => _appLogToggleHovered = false),
      child: GestureDetector(
        onTap: () {
          setState(() => _showAppLogs = !_showAppLogs);
          if (_showAppLogs) {
            _appLogViewModel.loadLogs();
          }
        },
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
          decoration: BoxDecoration(
            gradient: _showAppLogs
                ? LinearGradient(
                    colors: [activeColor.withAlpha(30), s.accent.withAlpha(15)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: _showAppLogs ? null : s.surfaceSunken.withAlpha(200),
            borderRadius: m.radiusControl,
            border: Border.all(
              color: _showAppLogs
                  ? activeRole.containerBorder
                  : (_appLogToggleHovered
                        ? s.accent.withAlpha(40)
                        : s.border),
              width: _showAppLogs ? 1 : 0.5,
            ),
            boxShadow: _showAppLogs
                ? [
                    BoxShadow(
                      color: activeColor.withAlpha(20),
                      blurRadius: scaleW(12),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: s.accent.withAlpha(6),
                      blurRadius: scaleW(8),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.base,
                child: DrawIcon(
                  _showAppLogs ? StrokeIcons.terminal : StrokeIcons.smartToy,
                  key: ValueKey(_showAppLogs),
                  size: m.iconSize16,
                  color: _showAppLogs ? activeColor : s.textPrimary,
                ),
              ),
              SizedBox(width: m.kSpace6),
              AnimatedDefaultTextStyle(
                duration: AppMotion.base,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: _showAppLogs ? activeColor : s.textPrimary,
                  fontWeight: _showAppLogs ? FontWeight.w600 : FontWeight.w400,
                ),
                child: const Text('应用日志'),
              ),
              if (_showAppLogs) ...[
                SizedBox(width: m.kSpace4),
                Container(
                  width: m.kSpace6,
                  height: m.kSpace6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor,
                    boxShadow: [BoxShadow(color: activeColor.withAlpha(50), blurRadius: scaleW(4))],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _appLogToggleHovered = false;

  /// 构建节点切换器
  Widget _buildNodeSwitcher(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    if (_sentrySettings == null || _nodeService == null) return const SizedBox.shrink();

    return Obx(
      () => NodeSwitcherButton(
        nodeService: _nodeService!,
        currentNodeId: _viewModel.currentNodeId.value,
        onNodeSelected: (nodeId) => _viewModel.switchNode(nodeId),
      ),
    );
  }

  /// 构建操作按钮（带悬停发光效果）
  Widget _buildActionButton({
    required BuildContext context,
    required StrokeIcon icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return _ActionButtonWidget(icon: icon, tooltip: tooltip, onPressed: onPressed);
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
      _logger.error('导出日志失败: $e');
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
  final StrokeIcon icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionButtonWidget({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ActionButtonWidget> createState() => _ActionButtonWidgetState();
}

class _ActionButtonWidgetState extends State<_ActionButtonWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          margin: EdgeInsets.only(right: m.kSpace4),
          padding: EdgeInsets.all(m.kSpace8),
          decoration: BoxDecoration(
            // 悬停用水洗层，方向由语义角色决定，不再自己判明暗
            color: _hovered ? s.surfaceHover : Colors.transparent,
            borderRadius: m.radiusControl,
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: s.accent.withAlpha(15),
                      blurRadius: scaleW(12),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ]
                : null,
          ),
          child: AnimatedScale(
            scale: _hovered ? 1.08 : 1.0,
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            child: DrawIcon(widget.icon, size: m.iconSize18, color: s.textPrimary),
          ),
        ),
      ),
    );
  }
}
