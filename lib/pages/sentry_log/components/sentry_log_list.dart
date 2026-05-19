import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/pages/sentry_log/components/sentry_log_event_detail.dart';

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
                return _buildEventCard(context, theme, m, event, isDark);
              },
            ),
          ),
        ],
      );
    });
  }

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
      child: Material(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        elevation: isDark ? 0 : 1,
        child: InkWell(
          borderRadius: m.radius10,
          onTap: () => _showEventDetail(context, event),
          child: ClipRRect(
            borderRadius: m.radius10,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? DarkColors.white10 : LightColors.black10,
                  width: 0.5,
                ),
                borderRadius: m.radius10,
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [levelColor, levelColor.withAlpha(120)],
                        ),
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
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.hintColor,
                                    ),
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
                                  Icon(
                                    Icons.source_rounded,
                                    size: m.iconSize12,
                                    color: theme.hintColor,
                                  ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBadge(ThemeData theme, ThemeMetrics m, String level, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: m.radius4,
        border: Border.all(color: color.withAlpha(50), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

  void _showEventDetail(BuildContext context, Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (_) => SentryLogEventDetail(event: event, viewModel: viewModel),
    );
  }

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
