import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_event_detail.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 日志列表组件
class SentryLogList extends StatelessWidget {
  final SentryLogViewModel viewModel;

  const SentryLogList({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);

    return Obx(() {
      if (viewModel.isLoading.value && viewModel.events.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: m.iconSize32,
                height: m.iconSize32,
                child: CircularProgressIndicator(strokeWidth: m.kSpace2, color: s.accent),
              ),
              SizedBox(height: m.kSpace12),
              Text('加载中...', style: theme.textTheme.bodySmall?.copyWith(color: s.textTertiary)),
            ],
          ),
        );
      }

      if (viewModel.events.isEmpty) {
        return _buildEmptyState(context, theme, m, s);
      }

      return Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace16),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
                  decoration: BoxDecoration(
                    color: s.accentContainer,
                    borderRadius: m.radius4,
                  ),
                  child: Text(
                    '${viewModel.totalEvents.value} 条日志',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: s.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (viewModel.totalEvents.value > viewModel.events.length)
                  TextButton.icon(
                    onPressed: () => viewModel.loadMore(),
                    icon: DrawIcon(StrokeIcons.expandMore, size: m.iconSize16),
                    label: const Text('加载更多'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace4),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16),
              itemCount: viewModel.events.length,
              itemBuilder: (context, index) {
                final event = viewModel.events[index];
                return _EventCardAnimation(
                  index: index,
                  child: _buildEventCard(context, theme, m, event, s),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// 构建空状态提示
  Widget _buildEmptyState(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: m.iconSize64,
            height: m.iconSize64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  s.accent.withAlpha(30),
                  s.accent.withAlpha(10),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: s.accent.withAlpha(15),
                  blurRadius: scaleW(20),
                  offset: Offset(0, scaleW(4)),
                ),
              ],
            ),
            child: DrawIcon(StrokeIcons.radar, size: m.iconSize32, color: s.accent.withAlpha(120)),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '等待日志接入',
            style: theme.textTheme.titleMedium?.copyWith(color: s.textPrimary),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '配置 Sentry DSN 为 http://<IP>:17888/<project_id>',
            style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
              color: s.textTertiary,
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '其他项目发送的日志将实时显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(color: s.textTertiary),
          ),
        ],
      ),
    );
  }

  /// 构建事件卡片（毛玻璃 + 悬停发光）
  Widget _buildEventCard(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    Map<String, dynamic> event,
    AppSemantic s,
  ) {
    final level = event['level']?.toString() ?? 'info';
    final eventId = event['event_id']?.toString() ?? '';
    final message = _extractMessage(event);
    final timestamp = viewModel.formatTimestamp(event['timestamp']?.toString());
    final culprit = event['culprit']?.toString() ?? event['transaction']?.toString() ?? '';
    final environment = event['environment']?.toString() ?? '';
    final platform = event['platform']?.toString() ?? '';
    final levelRole = _levelRole(s, level);
    final levelColor = levelRole.color;

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace6),
      child: _EventCardHover(
        levelRole: levelRole,
        onTap: () => _showEventDetail(context, event),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // 左侧级别指示条（渐变 + 发光）
              Container(
                width: scaleW(4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [levelColor, levelColor.withAlpha(120)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: m.radius2.topLeft,
                    bottomLeft: m.radius2.bottomLeft,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: levelColor.withAlpha(40),
                      blurRadius: scaleW(6),
                      offset: Offset(scaleW(2), 0),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(m.kSpace12, m.kSpace10, m.kSpace8, m.kSpace10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildLevelBadge(context, theme, m, level, levelRole),
                          if (environment.isNotEmpty) ...[
                            SizedBox(width: m.kSpace6),
                            _buildEnvBadge(theme, m, environment, s),
                          ],
                          if (platform.isNotEmpty) ...[
                            SizedBox(width: m.kSpace6),
                            DrawIcon(
                              _getPlatformIcon(platform),
                              size: m.iconSize12,
                              color: s.textTertiary,
                            ),
                            SizedBox(width: m.kSpace2),
                            Text(
                              platform,
                              style: theme.textTheme.labelSmall?.copyWith(color: s.textTertiary),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            timestamp,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: s.textTertiary,
                              fontFeatures: [const FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: m.kSpace4),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (culprit.isNotEmpty) ...[
                        SizedBox(height: m.kSpace2),
                        Row(
                          children: [
                            DrawIcon(StrokeIcons.source, size: m.iconSize12, color: s.textTertiary),
                            SizedBox(width: m.kSpace4),
                            Expanded(
                              child: Text(
                                culprit,
                                style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                                  color: s.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(right: m.kSpace4),
                child: IconButton(
                  icon: DrawIcon(StrokeIcons.close, size: m.iconSize14, color: s.textTertiary),
                  onPressed: () => _confirmDelete(context, eventId),
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  constraints: BoxConstraints(minWidth: m.kSpace24, minHeight: m.kSpace24),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建日志级别标签
  Widget _buildLevelBadge(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    String level,
    AppStatusRole role,
  ) {
    final color = role.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
      decoration: BoxDecoration(
        // 容器底与描边由角色派生，不手写 withAlpha
        color: role.container,
        borderRadius: m.radius4,
        border: Border.all(color: role.containerBorder, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(20),
            blurRadius: scaleW(4),
            offset: Offset(0, scaleW(1)),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: m.kSpace6,
            height: m.kSpace6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(60),
                  blurRadius: scaleW(4),
                  offset: Offset(0, m.kSpace1),
                ),
              ],
            ),
          ),
          SizedBox(width: m.kSpace4),
          Text(
            level.toUpperCase(),
            // 容器上的文字走 onContainer：状态主色是给"点"用的，直接当小字会糊
            style: theme.textTheme.labelSmall?.copyWith(
              color: role.onContainer,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建环境标签
  Widget _buildEnvBadge(ThemeData theme, ThemeMetrics m, String env, AppSemantic s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
      decoration: BoxDecoration(
        color: s.neutral.container,
        borderRadius: m.radius4,
      ),
      child: Text(
        env,
        style: theme.textTheme.labelSmall?.copyWith(
          color: s.neutral.onContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 级别 → 状态角色：语义层没有"致命"这一档，fatal 与 error 同归 danger
  AppStatusRole _levelRole(AppSemantic s, String level) {
    switch (level) {
      case 'fatal':
      case 'error':
        return s.danger;
      case 'warning':
        return s.warning;
      case 'info':
        return s.info;
      default:
        return s.neutral;
    }
  }

  /// 获取平台对应图标
  StrokeIcon _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'javascript':
      case 'node':
        return StrokeIcons.javascript;
      case 'python':
        return StrokeIcons.code;
      case 'rust':
        return StrokeIcons.memory;
      case 'java':
        return StrokeIcons.coffee;
      case 'go':
        return StrokeIcons.speed;
      default:
        return StrokeIcons.terminal;
    }
  }

  /// 提取事件消息文本
  String _extractMessage(Map<String, dynamic> event) {
    if (event['message'] != null && event['message'].toString().isNotEmpty) {
      return event['message'].toString();
    }
    if (event['title'] != null && event['title'].toString().isNotEmpty) {
      return event['title'].toString();
    }
    final exception = event['exception'] as Map<String, dynamic>?;
    if (exception != null) {
      final values = exception['values'] as List<dynamic>?;
      if (values != null && values.isNotEmpty) {
        final first = values[0] as Map<String, dynamic>?;
        if (first != null) {
          final type = first['type']?.toString() ?? '';
          final value = first['value']?.toString() ?? '';
          if (type.isNotEmpty || value.isNotEmpty) {
            return '$type: $value';
          }
        }
      }
    }
    if (event['culprit'] != null) {
      return event['culprit'].toString();
    }
    return '未知事件';
  }

  /// 显示事件详情弹窗
  void _showEventDetail(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (_) => SentryLogEventDetail(event: event, viewModel: viewModel),
    );
  }

  /// 确认删除弹窗
  void _confirmDelete(BuildContext context, String eventId) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: m.radius12),
        title: Row(
          children: [
            DrawIcon(StrokeIcons.warningAmber, color: s.warning.color, size: m.iconSize20),
            SizedBox(width: m.kSpace8),
            const Text('确认删除'),
          ],
        ),
        content: const Text('确定要删除这条日志吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              navigator.pop();
              await viewModel.deleteEvent(eventId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: s.danger.color,
              foregroundColor: s.accentOn,
              shape: RoundedRectangleBorder(borderRadius: m.radiusControl),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 事件卡片悬停效果组件（毛玻璃 + 发光阴影）
class _EventCardHover extends StatefulWidget {
  final AppStatusRole levelRole;
  final VoidCallback onTap;
  final Widget child;

  const _EventCardHover({
    required this.levelRole,
    required this.onTap,
    required this.child,
  });

  @override
  State<_EventCardHover> createState() => _EventCardHoverState();
}

class _EventCardHoverState extends State<_EventCardHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: s.surface.withAlpha(_hovered ? 250 : 230),
            borderRadius: m.radiusCard,
            border: Border.all(
              color: _hovered ? widget.levelRole.containerBorder : s.border,
              width: 0.5,
            ),
            boxShadow: [
              ...s.elevation(_hovered ? Elevation.card : Elevation.raised),
              if (_hovered)
                BoxShadow(
                  color: widget.levelRole.color.withAlpha(15),
                  blurRadius: scaleW(16),
                  offset: Offset(0, scaleW(4)),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: m.radiusCard,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 事件卡片入场动画组件
class _EventCardAnimation extends StatefulWidget {
  final int index;
  final Widget child;

  const _EventCardAnimation({required this.index, required this.child});

  @override
  State<_EventCardAnimation> createState() => _EventCardAnimationState();
}

class _EventCardAnimationState extends State<_EventCardAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    _animation = CurvedAnimation(parent: _controller, curve: AppMotion.decelerate);
    Future.delayed(AppMotion.stagger * (widget.index % 15), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Opacity(
          opacity: _animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, AppMotion.travelBase * (1 - _animation.value)),
            child: widget.child,
          ),
        );
      },
    );
  }
}
