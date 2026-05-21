import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';

/// 日志统计面板组件
class SentryLogStatsPanel extends StatelessWidget {
  final SentryLogViewModel viewModel;

  const SentryLogStatsPanel({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Obx(() {
      final stats = viewModel.stats;
      if (stats.isEmpty) {
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
                      theme.colorScheme.primary.withAlpha(20),
                      theme.colorScheme.primary.withAlpha(8),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withAlpha(10),
                      blurRadius: scaleW(16),
                      offset: Offset(0, scaleW(4)),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.bar_chart_rounded,
                  size: m.iconSize32,
                  color: theme.colorScheme.primary.withAlpha(100),
                ),
              ),
              SizedBox(height: m.kSpace12),
              Text(
                '暂无统计数据',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        );
      }

      final totalEvents = stats['total_events'] as int? ?? 0;
      final projects = (stats['projects'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final levelCounts = (stats['level_counts'] as List<dynamic>? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();

      return SingleChildScrollView(
        padding: EdgeInsets.all(m.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewRow(theme, m, isDark, totalEvents, projects.length),
            SizedBox(height: m.kSpace16),
            if (levelCounts.isNotEmpty) ...[
              _buildSectionTitle(theme, m, '级别分布'),
              SizedBox(height: m.kSpace8),
              _buildLevelDistribution(theme, m, isDark, levelCounts),
              SizedBox(height: m.kSpace16),
            ],
            if (projects.isNotEmpty) ...[
              _buildSectionTitle(theme, m, '项目列表'),
              SizedBox(height: m.kSpace8),
              _buildProjectGrid(context, theme, m, isDark, projects),
            ],
          ],
        ),
      );
    });
  }

  /// 构建分区标题
  Widget _buildSectionTitle(ThemeData theme, ThemeMetrics m, String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: m.kSpace14,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: m.radius2,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withAlpha(40),
                blurRadius: scaleW(4),
                offset: Offset(scaleW(2), 0),
              ),
            ],
          ),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// 构建概览统计行
  Widget _buildOverviewRow(
    ThemeData theme,
    ThemeMetrics m,
    bool isDark,
    int totalEvents,
    int projectCount,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            theme,
            m,
            isDark,
            icon: Icons.crisis_alert_rounded,
            label: '总事件数',
            value: _formatNumber(totalEvents),
            accentColor: const Color(0xFFE53935),
          ),
        ),
        SizedBox(width: m.kSpace12),
        Expanded(
          child: _buildStatCard(
            theme,
            m,
            isDark,
            icon: Icons.folder_outlined,
            label: '接入项目',
            value: projectCount.toString(),
            accentColor: const Color(0xFF1E88E5),
          ),
        ),
      ],
    );
  }

  /// 构建统计卡片（毛玻璃 + 悬停发光）
  Widget _buildStatCard(
    ThemeData theme,
    ThemeMetrics m,
    bool isDark, {
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return _StatCardHover(
      accentColor: accentColor,
      isDark: isDark,
      child: Padding(
        padding: EdgeInsets.all(m.kSpace16),
        child: Row(
          children: [
            Container(
              width: m.kSpace40,
              height: m.kSpace40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accentColor.withAlpha(40), accentColor.withAlpha(15)],
                ),
                borderRadius: m.radius10,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withAlpha(20),
                    blurRadius: scaleW(8),
                    offset: Offset(0, scaleW(2)),
                  ),
                ],
              ),
              child: Icon(icon, color: accentColor, size: m.iconSize20),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建级别分布图
  Widget _buildLevelDistribution(
    ThemeData theme,
    ThemeMetrics m,
    bool isDark,
    List<Map<String, dynamic>> levelCounts,
  ) {
    final total = levelCounts.fold<int>(0, (sum, lc) => sum + ((lc['count'] as num?)?.toInt() ?? 0));

    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: isDark
            ? DarkColors.background1.withAlpha(200)
            : LightColors.background1.withAlpha(230),
        borderRadius: m.radius12,
        border: Border.all(
          color: isDark ? DarkColors.white10.withAlpha(30) : LightColors.black10.withAlpha(20),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? DarkColors.black10 : LightColors.black10,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: (isDark ? DarkColors.primary : LightColors.primary).withAlpha(6),
            blurRadius: scaleW(16),
            offset: Offset(0, scaleW(4)),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Column(
            children: [
              _buildStackedBar(theme, m, isDark, levelCounts, total),
              SizedBox(height: m.kSpace12),
              Divider(color: isDark ? DarkColors.white10 : LightColors.black10, height: 1),
              SizedBox(height: m.kSpace12),
              ...levelCounts.map((lc) {
                final level = lc['level']?.toString() ?? 'unknown';
                final count = (lc['count'] as num?)?.toInt() ?? 0;
                final percentage = total > 0 ? (count / total * 100) : 0.0;
                final color = viewModel.getLevelColor(level);

                return Padding(
                  padding: EdgeInsets.only(bottom: m.kSpace8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withAlpha(80),
                              blurRadius: scaleW(4),
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      SizedBox(
                        width: 56,
                        child: Text(
                          level.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: m.radius4,
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isDark ? DarkColors.background2 : LightColors.background2,
                                  borderRadius: m.radius4,
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: percentage / 100,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [color, color.withAlpha(180)],
                                    ),
                                    borderRadius: m.radius4,
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withAlpha(40),
                                        blurRadius: scaleW(4),
                                        offset: Offset(0, scaleW(1)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      SizedBox(
                        width: 70,
                        child: Text(
                          '${_formatNumber(count)} (${percentage.toStringAsFixed(1)}%)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建堆叠条形图
  Widget _buildStackedBar(
    ThemeData theme,
    ThemeMetrics m,
    bool isDark,
    List<Map<String, dynamic>> levelCounts,
    int total,
  ) {
    if (total == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: m.radius6,
      child: SizedBox(
        height: 12,
        child: Row(
          children: levelCounts.map((lc) {
            final count = (lc['count'] as num?)?.toInt() ?? 0;
            final color = viewModel.getLevelColor(lc['level']?.toString() ?? 'unknown');
            return Expanded(
              flex: count,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(30),
                      blurRadius: scaleW(4),
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 构建项目网格
  Widget _buildProjectGrid(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isDark,
    List<Map<String, dynamic>> projects,
  ) {
    return Wrap(
      spacing: m.kSpace12,
      runSpacing: m.kSpace12,
      children: projects.map((project) {
        final projectId = project['project_id']?.toString() ?? '';
        final projectName = project['project_name']?.toString() ?? projectId;
        final eventCount = (project['event_count'] as num?)?.toInt() ?? 0;
        final lastEventAt = project['last_event_at']?.toString();

        return _ProjectCardHover(
          isDark: isDark,
          child: Container(
            width: 240,
            padding: EdgeInsets.all(m.kSpace14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: m.kSpace32,
                      height: m.kSpace32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primary.withAlpha(30),
                            theme.colorScheme.primary.withAlpha(10),
                          ],
                        ),
                        borderRadius: m.radius8,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withAlpha(15),
                            blurRadius: scaleW(6),
                            offset: Offset(0, scaleW(2)),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.dns_outlined,
                        size: m.iconSize16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(width: m.kSpace8),
                    Expanded(
                      child: Text(
                        projectName,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_sweep_outlined,
                        size: m.iconSize16,
                        color: Colors.red.shade300,
                      ),
                      tooltip: '清空事件',
                      onPressed: () => _confirmClearProject(context, projectId, projectName),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: m.kSpace24, minHeight: m.kSpace24),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace10),
                Row(
                  children: [
                    Text(
                      _formatNumber(eventCount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(width: m.kSpace4),
                    Text(
                      '事件',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                    ),
                    const Spacer(),
                    if (lastEventAt != null)
                      Text(
                        viewModel.formatTimestamp(lastEventAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.hintColor,
                          fontFeatures: [const FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 确认清空项目弹窗
  void _confirmClearProject(BuildContext context, String projectId, String projectName) {
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
            const Text('确认清空'),
          ],
        ),
        content: Text('确定要清空项目 "$projectName" 的所有事件吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              navigator.pop();
              await viewModel.clearProjectEvents(projectId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: m.radius8),
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  /// 格式化数字（K/M 缩写）
  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

/// 统计卡片悬停效果组件
class _StatCardHover extends StatefulWidget {
  final Color accentColor;
  final bool isDark;
  final Widget child;

  const _StatCardHover({
    required this.accentColor,
    required this.isDark,
    required this.child,
  });

  @override
  State<_StatCardHover> createState() => _StatCardHoverState();
}

class _StatCardHoverState extends State<_StatCardHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.isDark
              ? DarkColors.background1.withAlpha(_hovered ? 240 : 200)
              : LightColors.background1.withAlpha(_hovered ? 250 : 230),
          borderRadius: m.radius12,
          border: Border.all(
            color: _hovered
                ? widget.accentColor.withAlpha(30)
                : (widget.isDark ? DarkColors.white10 : LightColors.black10).withAlpha(30),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isDark ? DarkColors.black10 : LightColors.black10,
              blurRadius: _hovered ? 10 : 6,
              offset: Offset(0, _hovered ? 4 : 2),
            ),
            if (_hovered)
              BoxShadow(
                color: widget.accentColor.withAlpha(15),
                blurRadius: scaleW(20),
                offset: Offset(0, scaleW(4)),
              ),
            BoxShadow(
              color: (widget.isDark ? DarkColors.primary : LightColors.primary).withAlpha(6),
              blurRadius: scaleW(16),
              offset: Offset(0, scaleW(4)),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: m.radius12,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 项目卡片悬停效果组件
class _ProjectCardHover extends StatefulWidget {
  final bool isDark;
  final Widget child;

  const _ProjectCardHover({
    required this.isDark,
    required this.child,
  });

  @override
  State<_ProjectCardHover> createState() => _ProjectCardHoverState();
}

class _ProjectCardHoverState extends State<_ProjectCardHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        width: 240,
        decoration: BoxDecoration(
          color: widget.isDark
              ? DarkColors.background1.withAlpha(_hovered ? 240 : 200)
              : LightColors.background1.withAlpha(_hovered ? 250 : 230),
          borderRadius: m.radius12,
          border: Border.all(
            color: _hovered
                ? theme.colorScheme.primary.withAlpha(25)
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
                color: theme.colorScheme.primary.withAlpha(12),
                blurRadius: scaleW(16),
                offset: Offset(0, scaleW(4)),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: m.radius12,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
