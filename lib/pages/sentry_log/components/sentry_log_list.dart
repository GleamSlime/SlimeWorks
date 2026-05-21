import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_event_detail.dart';

/// 日志列表组件
class SentryLogList extends StatelessWidget {
  final SentryLogViewModel viewModel;

  const SentryLogList({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      if (viewModel.isLoading.value && viewModel.events.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: m.iconSize32,
                height: m.iconSize32,
                child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
              ),
              SizedBox(height: m.kSpace12),
              Text('加载中...', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
            ],
          ),
        );
      }

      if (viewModel.events.isEmpty) {
        return _buildEmptyState(theme, m, isDark);
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
                    color: theme.colorScheme.primary.withAlpha(15),
                    borderRadius: m.radius4,
                  ),
                  child: Text(
                    '${viewModel.totalEvents.value} 条日志',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (viewModel.totalEvents.value > viewModel.events.length)
                  TextButton.icon(
                    onPressed: () => viewModel.loadMore(),
                    icon: Icon(Icons.expand_more_rounded, size: m.iconSize16),
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
                  child: _buildEventCard(context, theme, m, event, isDark),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// 构建空状态提示
  Widget _buildEmptyState(ThemeData theme, ThemeMetrics m, bool isDark) {
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
                  theme.colorScheme.primary.withAlpha(30),
                  theme.colorScheme.primary.withAlpha(10),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withAlpha(15),
                  blurRadius: scaleW(20),
                  offset: Offset(0, scaleW(4)),
                ),
              ],
            ),
            child: Icon(
              Icons.radar_rounded,
              size: m.iconSize32,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '等待日志接入',
            style: theme.textTheme.titleMedium?.copyWith(
              color: isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '配置 Sentry DSN 为 http://<IP>:17888/<project_id>',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '其他项目发送的日志将实时显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
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
    bool isDark,
  ) {
    final level = event['level']?.toString() ?? 'info';
    final eventId = event['event_id']?.toString() ?? '';
    final message = _extractMessage(event);
    final timestamp = viewModel.formatTimestamp(event['timestamp']?.toString());
    final culprit = event['culprit']?.toString() ?? event['transaction']?.toString() ?? '';
    final environment = event['environment']?.toString() ?? '';
    final platform = event['platform']?.toString() ?? '';
    final levelColor = viewModel.getLevelColor(level);

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace6),
      child: _EventCardHover(
        levelColor: levelColor,
        isDark: isDark,
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
                    topLeft: Radius.circular(scaleW(2)),
                    bottomLeft: Radius.circular(scaleW(2)),
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
                          _buildLevelBadge(theme, m, level, levelColor),
                          if (environment.isNotEmpty) ...[
                            SizedBox(width: m.kSpace6),
                            _buildEnvBadge(theme, m, environment, isDark),
                          ],
                          if (platform.isNotEmpty) ...[
                            SizedBox(width: m.kSpace6),
                            Icon(
                              _getPlatformIcon(platform),
                              size: m.iconSize12,
                              color: theme.hintColor,
                            ),
                            SizedBox(width: m.kSpace2),
                            Text(
                              platform,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            timestamp,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.hintColor,
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
                            Icon(Icons.source_rounded, size: m.iconSize12, color: theme.hintColor),
                            SizedBox(width: m.kSpace4),
                            Expanded(
                              child: Text(
                                culprit,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.hintColor,
                                  fontFamily: 'monospace',
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
                  icon: Icon(Icons.close_rounded, size: m.iconSize14, color: theme.hintColor),
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
  Widget _buildLevelBadge(ThemeData theme, ThemeMetrics m, String level, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: m.radius4,
        border: Border.all(color: color.withAlpha(50), width: 0.5),
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
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(60),
                  blurRadius: scaleW(4),
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          SizedBox(width: m.kSpace4),
          Text(
            level.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建环境标签
  Widget _buildEnvBadge(ThemeData theme, ThemeMetrics m, String env, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.white10 : LightColors.background5,
        borderRadius: m.radius4,
      ),
      child: Text(
        env,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isDark ? DarkColors.white80 : LightColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 获取平台对应图标
  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'javascript':
      case 'node':
        return Icons.javascript;
      case 'python':
        return Icons.code_rounded;
      case 'rust':
        return Icons.memory_rounded;
      case 'java':
        return Icons.coffee_rounded;
      case 'go':
        return Icons.speed_rounded;
      default:
        return Icons.terminal_rounded;
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
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: m.radius12),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: m.iconSize20),
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
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: m.radius8),
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
  final Color levelColor;
  final bool isDark;
  final VoidCallback onTap;
  final Widget child;

  const _EventCardHover({
    required this.levelColor,
    required this.isDark,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.isDark
                ? DarkColors.background1.withAlpha(_hovered ? 240 : 200)
                : LightColors.background1.withAlpha(_hovered ? 250 : 230),
            borderRadius: m.radius10,
            border: Border.all(
              color: _hovered
                  ? widget.levelColor.withAlpha(40)
                  : (widget.isDark ? DarkColors.white10 : LightColors.black10).withAlpha(30),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isDark ? DarkColors.black10 : LightColors.black10,
                blurRadius: _hovered ? 8 : 4,
                offset: Offset(0, _hovered ? 3 : 1),
              ),
              if (_hovered)
                BoxShadow(
                  color: widget.levelColor.withAlpha(15),
                  blurRadius: scaleW(16),
                  offset: Offset(0, scaleW(4)),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: m.radius10,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    Future.delayed(Duration(milliseconds: 60 * (widget.index % 15)), () {
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
            offset: Offset(0, 8 * (1 - _animation.value)),
            child: widget.child,
          ),
        );
      },
    );
  }
}
