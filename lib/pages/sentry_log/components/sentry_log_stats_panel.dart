import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 日志统计面板组件
class SentryLogStatsPanel extends StatelessWidget {
  final SentryLogViewModel viewModel;

  const SentryLogStatsPanel({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);

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
                      s.accent.withAlpha(20),
                      s.accent.withAlpha(8),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: s.accent.withAlpha(10),
                      blurRadius: scaleW(16),
                      offset: Offset(0, scaleW(4)),
                    ),
                  ],
                ),
                child: DrawIcon(StrokeIcons.barChart,
                  size: m.iconSize32,
                  color: s.accent.withAlpha(100),
                ),
              ),
              SizedBox(height: m.kSpace12),
              Text(
                '暂无统计数据',
                style: theme.textTheme.bodyMedium?.copyWith(color: s.textTertiary),
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
            _buildOverviewRow(theme, m, s, totalEvents, projects.length),
            SizedBox(height: m.kSpace16),
            if (levelCounts.isNotEmpty) ...[
              _buildSectionTitle(theme, m, s, '级别分布'),
              SizedBox(height: m.kSpace8),
              _buildLevelDistribution(theme, m, s, levelCounts),
              SizedBox(height: m.kSpace16),
            ],
            if (projects.isNotEmpty) ...[
              _buildSectionTitle(theme, m, s, '项目列表'),
              SizedBox(height: m.kSpace8),
              _buildProjectGrid(context, theme, m, s, projects),
            ],
          ],
        ),
      );
    });
  }

  /// 构建分区标题
  Widget _buildSectionTitle(ThemeData theme, ThemeMetrics m, AppSemantic s, String title) {
    return Row(
      children: [
        Container(
          width: m.kSpace3,
          height: m.kSpace14,
          decoration: BoxDecoration(
            color: s.accent,
            borderRadius: m.radius2,
            boxShadow: [
              BoxShadow(
                color: s.accent.withAlpha(40),
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
    AppSemantic s,
    int totalEvents,
    int projectCount,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            theme,
            m,
            s,
            icon: StrokeIcons.crisisAlert,
            label: '总事件数',
            value: _formatNumber(totalEvents),
            accentColor: s.danger.color,
          ),
        ),
        SizedBox(width: m.kSpace12),
        Expanded(
          child: _buildStatCard(
            theme,
            m,
            s,
            icon: StrokeIcons.folder,
            label: '接入项目',
            value: projectCount.toString(),
            accentColor: s.info.color,
          ),
        ),
      ],
    );
  }

  /// 构建统计卡片（毛玻璃 + 悬停发光）
  Widget _buildStatCard(
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s, {
    required StrokeIcon icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return _StatCardHover(
      accentColor: accentColor,
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
                borderRadius: m.radiusCard,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withAlpha(20),
                    blurRadius: scaleW(8),
                    offset: Offset(0, scaleW(2)),
                  ),
                ],
              ),
              child: DrawIcon(icon, color: accentColor, size: m.iconSize20),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(color: s.textTertiary),
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
    AppSemantic s,
    List<Map<String, dynamic>> levelCounts,
  ) {
    final total = levelCounts.fold<int>(0, (sum, lc) => sum + ((lc['count'] as num?)?.toInt() ?? 0));

    return Container(
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.glassTint,
        borderRadius: m.radiusPanel,
        border: Border.all(color: s.glassBorder, width: AppTheme.metrics.strokeUltraThin),
        boxShadow: [
          ...s.elevation(Elevation.raised),
          BoxShadow(
            color: s.accent.withAlpha(6),
            blurRadius: scaleW(16),
            offset: Offset(0, scaleW(4)),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: m.radiusPanel,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
          child: Column(
            children: [
              _buildStackedBar(theme, m, s, levelCounts, total),
              SizedBox(height: m.kSpace12),
              Divider(color: s.hairline, height: 1),
              SizedBox(height: m.kSpace12),
              ...levelCounts.map((lc) {
                final level = lc['level']?.toString() ?? 'unknown';
                final count = (lc['count'] as num?)?.toInt() ?? 0;
                final percentage = total > 0 ? (count / total * 100) : 0.0;
                final color = _levelColor(s, level);

                return Padding(
                  padding: EdgeInsets.only(bottom: m.kSpace8),
                  child: Row(
                    children: [
                      Container(
                        width: m.kSpace10,
                        height: m.kSpace10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withAlpha(80),
                              blurRadius: scaleW(4),
                              offset: Offset(0, m.kSpace1),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      SizedBox(
                        width: m.kSpace56,
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
                                height: m.kSpace8,
                                decoration: BoxDecoration(
                                  color: s.surfaceSunken,
                                  borderRadius: m.radius4,
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: percentage / 100,
                                child: Container(
                                  height: m.kSpace8,
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
                        width: scaleW(70),
                        child: Text(
                          '${_formatNumber(count)} (${percentage.toStringAsFixed(1)}%)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: s.textTertiary,
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
    AppSemantic s,
    List<Map<String, dynamic>> levelCounts,
    int total,
  ) {
    if (total == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: m.radius6,
      child: SizedBox(
        height: m.kSpace12,
        child: Row(
          children: levelCounts.map((lc) {
            final count = (lc['count'] as num?)?.toInt() ?? 0;
            final color = _levelColor(s, lc['level']?.toString() ?? 'unknown');
            return Expanded(
              flex: count,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(30),
                      blurRadius: scaleW(4),
                      offset: Offset(0, m.kSpace1),
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

  /// 级别 → 状态色：语义层没有"致命"这一档，fatal 与 error 同归 danger
  Color _levelColor(AppSemantic s, String level) {
    switch (level) {
      case 'fatal':
      case 'error':
        return s.danger.color;
      case 'warning':
        return s.warning.color;
      case 'info':
        return s.info.color;
      default:
        return s.neutral.color;
    }
  }

  /// 构建项目网格
  Widget _buildProjectGrid(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
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
          child: Container(
            width: scaleW(240),
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
                            s.accent.withAlpha(30),
                            s.accent.withAlpha(10),
                          ],
                        ),
                        borderRadius: m.radiusControl,
                        boxShadow: [
                          BoxShadow(
                            color: s.accent.withAlpha(15),
                            blurRadius: scaleW(6),
                            offset: Offset(0, scaleW(2)),
                          ),
                        ],
                      ),
                      child: DrawIcon(StrokeIcons.dns, size: m.iconSize16, color: s.accent),
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
                      icon: DrawIcon(StrokeIcons.deleteSweep,
                        size: m.iconSize16,
                        color: s.danger.color,
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
                      style: theme.textTheme.labelSmall?.copyWith(color: s.textTertiary),
                    ),
                    const Spacer(),
                    if (lastEventAt != null)
                      Text(
                        viewModel.formatTimestamp(lastEventAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: s.textTertiary,
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
              backgroundColor: s.danger.color,
              foregroundColor: s.accentOn,
              shape: RoundedRectangleBorder(borderRadius: m.radiusControl),
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
  final Widget child;

  const _StatCardHover({
    required this.accentColor,
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
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: s.surface.withAlpha(_hovered ? 250 : 230),
          borderRadius: m.radiusPanel,
          border: Border.all(
            color: _hovered ? widget.accentColor.withAlpha(30) : s.border,
            width: 0.5,
          ),
          boxShadow: [
            ...s.elevation(_hovered ? Elevation.card : Elevation.raised),
            if (_hovered)
              BoxShadow(
                color: widget.accentColor.withAlpha(15),
                blurRadius: scaleW(20),
                offset: Offset(0, scaleW(4)),
              ),
            BoxShadow(
              color: s.accent.withAlpha(6),
              blurRadius: scaleW(16),
              offset: Offset(0, scaleW(4)),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: m.radiusPanel,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 项目卡片悬停效果组件
class _ProjectCardHover extends StatefulWidget {
  final Widget child;

  const _ProjectCardHover({
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
    final s = AppSemantic.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standard,
        width: scaleW(240),
        decoration: BoxDecoration(
          color: s.surface.withAlpha(_hovered ? 250 : 230),
          borderRadius: m.radiusPanel,
          border: Border.all(
            color: _hovered ? s.accent.withAlpha(25) : s.border,
            width: 0.5,
          ),
          boxShadow: [
            ...s.elevation(_hovered ? Elevation.card : Elevation.raised),
            if (_hovered)
              BoxShadow(
                color: s.accent.withAlpha(12),
                blurRadius: scaleW(16),
                offset: Offset(0, scaleW(4)),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: m.radiusPanel,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
