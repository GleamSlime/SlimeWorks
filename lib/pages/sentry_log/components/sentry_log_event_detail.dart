import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

class SentryLogEventDetail extends StatelessWidget {
  final Map<String, dynamic> event;
  final SentryLogViewModel viewModel;

  const SentryLogEventDetail({super.key, required this.event, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);
    final level = event['level']?.toString() ?? 'info';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: m.radiusOverlay),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: scaleW(680),
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, theme, m, s, level),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(m.kSpace16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoGrid(context, theme, m, s),
                    if (_hasExceptions()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.bugReport,
                        '异常信息',
                        s.danger.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildExceptions(context, m, s),
                    ],
                    if (_hasBreadcrumbs()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.timeline,
                        '面包屑',
                        s.info.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildBreadcrumbs(context, theme, m, s),
                    ],
                    if (_hasTags()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.label,
                        '标签',
                        s.warning.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildTags(theme, m, s),
                    ],
                    if (_hasExtra()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.dataObject,
                        '额外数据',
                        s.success.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildExtra(context, theme, m, s),
                    ],
                    if (_hasUser()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.person,
                        '用户信息',
                        s.info.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildUser(context, theme, m, s),
                    ],
                    if (_hasRequest()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.http,
                        '请求信息',
                        s.info.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildRequest(context, theme, m, s),
                    ],
                    if (_hasContexts()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        StrokeIcons.devices,
                        '上下文',
                        s.neutral.color,
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildContexts(context, theme, m, s),
                    ],
                    SizedBox(height: m.kSpace16),
                    _buildSectionTitle(
                      theme,
                      m,
                      StrokeIcons.code,
                      '原始数据',
                      s.accent,
                    ),
                    SizedBox(height: m.kSpace8),
                    _buildRawJson(context, theme, m, s),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
    String level,
  ) {
    final role = _levelRole(s, level);
    final message = _extractMessage();
    return Container(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace14, m.kSpace8, m.kSpace14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [role.color.withAlpha(30), role.color.withAlpha(8)],
        ),
        border: Border(bottom: BorderSide(color: s.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: m.kSpace40,
            height: m.kSpace40,
            decoration: BoxDecoration(
              color: role.container,
              borderRadius: m.radiusControl,
              border: Border.all(color: role.containerBorder, width: AppTheme.metrics.strokeUltraThin),
            ),
            child: DrawIcon(_getLevelIcon(level), color: role.color, size: m.iconSize18),
          ),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: m.kSpace2),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace1),
                      decoration: BoxDecoration(
                        color: role.container,
                        borderRadius: m.radius4,
                      ),
                      child: Text(
                        level.toUpperCase(),
                        // 容器上的文字走 onContainer：状态主色是给"点"用的，直接当小字会糊
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: role.onContainer,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    SizedBox(width: m.kSpace6),
                    if (event['environment'] != null)
                      Text(
                        event['environment'].toString(),
                        style: theme.textTheme.labelSmall?.copyWith(color: s.textTertiary),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: DrawIcon(StrokeIcons.close, size: m.iconSize20, color: s.textTertiary),
            onPressed: () => Navigator.pop(context),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    ThemeData theme,
    ThemeMetrics m,
    StrokeIcon icon,
    String title,
    Color color,
  ) {
    return Row(
      children: [
        DrawIcon(icon, size: m.iconSize14, color: color),
        SizedBox(width: m.kSpace6),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    final entries = <_InfoEntry>[];
    if (event['event_id'] != null) {
      entries.add(_InfoEntry('事件ID', event['event_id'].toString()));
    }
    if (event['timestamp'] != null) {
      entries.add(_InfoEntry('时间', viewModel.formatTimestamp(event['timestamp'].toString())));
    }
    if (event['platform'] != null) {
      entries.add(_InfoEntry('平台', event['platform'].toString()));
    }
    if (event['logger'] != null) {
      entries.add(_InfoEntry('Logger', event['logger'].toString()));
    }
    if (event['culprit'] != null) {
      entries.add(_InfoEntry('来源', event['culprit'].toString()));
    }
    if (event['transaction'] != null) {
      entries.add(_InfoEntry('事务', event['transaction'].toString()));
    }
    if (event['release'] != null) {
      entries.add(_InfoEntry('版本', event['release'].toString()));
    }
    if (event['server_name'] != null) {
      entries.add(_InfoEntry('服务器', event['server_name'].toString()));
    }

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Column(
        children: entries.map((e) => _buildInfoRow(context, theme, m, s, e.label, e.value)).toList(),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
    String label,
    String value,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: m.kSpace64,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: s.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: SelectableText(
              value,
              // 等宽值走 AppTextStyles.mono：字族清单由主题统一定义，不再手写 monospace
              style: AppTextStyles.mono(context, size: m.fontSize12, color: s.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExceptions(BuildContext context, ThemeMetrics m, AppSemantic s) {
    final exception = event['exception'] as Map<String, dynamic>?;
    if (exception == null) return const SizedBox.shrink();
    final values = exception['values'] as List<dynamic>? ?? [];

    return Column(
      children: values.map<Widget>((v) {
        final ex = v as Map<String, dynamic>;
        final type = ex['type']?.toString() ?? '';
        final value = ex['value']?.toString() ?? '';
        final stacktrace = ex['stacktrace'] as Map<String, dynamic>?;
        final frames = stacktrace?['frames'] as List<dynamic>? ?? [];

        return Container(
          margin: EdgeInsets.only(bottom: m.kSpace8),
          padding: EdgeInsets.all(m.kSpace12),
          decoration: BoxDecoration(
            color: s.surface,
            borderRadius: m.radiusCard,
            border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
                decoration: BoxDecoration(
                  color: s.danger.container,
                  borderRadius: m.radius6,
                ),
                child: Text(
                  '$type: $value',
                  // 异常签名等宽展示；字重是原 copyWith 显式声明的，用 copyWith 保留
                  style: AppTextStyles.mono(
                    context,
                    size: m.fontSize12,
                    color: s.danger.onContainer,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (frames.isNotEmpty) ...[
                SizedBox(height: m.kSpace8),
                ...frames.reversed.map<Widget>((f) {
                  final frame = f as Map<String, dynamic>;
                  final filename = frame['filename']?.toString() ?? '';
                  final function = frame['function']?.toString() ?? '';
                  final lineno = frame['lineno']?.toString() ?? '';
                  final inApp = frame['in_app'] == true;

                  return Padding(
                    padding: EdgeInsets.only(bottom: m.kSpace2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: m.kSpace3,
                          height: m.kSpace14,
                          margin: EdgeInsets.only(top: m.kSpace4),
                          decoration: BoxDecoration(
                            color: inApp ? s.danger.color : s.textTertiary,
                            borderRadius: m.radius2,
                          ),
                        ),
                        SizedBox(width: m.kSpace6),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: AppTextStyles.mono(
                                context,
                                size: m.fontSize11,
                                color: s.textPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: function,
                                  style: TextStyle(
                                    fontWeight: inApp ? FontWeight.w700 : FontWeight.w400,
                                    color: inApp ? s.accent : null,
                                  ),
                                ),
                                TextSpan(text: '  '),
                                TextSpan(
                                  text: '$filename:$lineno',
                                  style: TextStyle(color: s.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBreadcrumbs(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
  ) {
    final breadcrumbs = event['breadcrumbs'] as Map<String, dynamic>?;
    if (breadcrumbs == null) return const SizedBox.shrink();
    final values = breadcrumbs['values'] as List<dynamic>? ?? [];

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Column(
        children: values.map<Widget>((b) {
          final crumb = b as Map<String, dynamic>;
          final type = crumb['type']?.toString() ?? 'default';
          final message = crumb['message']?.toString() ?? crumb['data']?.toString() ?? '';
          final category = crumb['category']?.toString() ?? '';
          final timestamp = crumb['timestamp']?.toString() ?? '';

          return Padding(
            padding: EdgeInsets.only(bottom: m.kSpace6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DrawIcon(_getBreadcrumbIcon(type), size: m.iconSize12, color: s.textTertiary),
                SizedBox(width: m.kSpace6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            category,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (timestamp.isNotEmpty)
                            Text(
                              viewModel.formatTimestamp(timestamp),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: s.textTertiary,
                                fontFeatures: [const FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                      if (message.isNotEmpty)
                        Text(
                          message,
                          style: AppTextStyles.mono(context, size: m.fontSize12, color: s.textTertiary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTags(ThemeData theme, ThemeMetrics m, AppSemantic s) {
    final tags = event['tags'] as Map<String, dynamic>? ?? {};
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: m.kSpace6,
      runSpacing: m.kSpace6,
      children: tags.entries.map((e) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
          decoration: BoxDecoration(
            color: s.warning.container,
            borderRadius: m.radius6,
            border: Border.all(color: s.warning.containerBorder, width: AppTheme.metrics.strokeUltraThin),
          ),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.labelSmall,
              children: [
                TextSpan(
                  text: '${e.key}: ',
                  style: TextStyle(color: s.warning.onContainer, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: e.value.toString(),
                  style: TextStyle(color: s.textPrimary),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExtra(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    final extra = event['extra'] as Map<String, dynamic>? ?? {};
    if (extra.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Column(
        children: extra.entries
            .map((e) => _buildInfoRow(context, theme, m, s, e.key, e.value.toString()))
            .toList(),
      ),
    );
  }

  Widget _buildUser(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
  ) {
    final user = event['user'] as Map<String, dynamic>? ?? {};
    if (user.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: m.kSpace16,
            backgroundColor: s.info.container,
            child: DrawIcon(StrokeIcons.person, size: m.iconSize16, color: s.info.color),
          ),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user['username'] != null)
                  Text(
                    user['username'].toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                if (user['email'] != null)
                  Text(
                    user['email'].toString(),
                    style: theme.textTheme.bodySmall?.copyWith(color: s.textTertiary),
                  ),
                if (user['id'] != null)
                  Text(
                    'ID: ${user['id']}',
                    style: AppTextStyles.mono(context, size: m.fontSize11, color: s.textTertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequest(BuildContext context, ThemeData theme, ThemeMetrics m, AppSemantic s) {
    final request = event['request'] as Map<String, dynamic>? ?? {};
    if (request.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Column(
        children: [
          if (request['method'] != null || request['url'] != null)
            _buildInfoRow(
              context,
              theme,
              m,
              s,
              '请求',
              '${request['method'] ?? ''} ${request['url'] ?? ''}',
            ),
          if (request['headers'] != null)
            _buildInfoRow(context, theme, m, s, 'Headers', request['headers'].toString()),
        ],
      ),
    );
  }

  Widget _buildContexts(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
  ) {
    final contexts = event['contexts'] as Map<String, dynamic>? ?? {};
    if (contexts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: Column(
        children: contexts.entries.map((e) {
          final value = e.value;
          if (value is Map<String, dynamic>) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: m.kSpace4),
                  child: Text(
                    e.key,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: s.neutral.onContainer,
                    ),
                  ),
                ),
                ...value.entries.map(
                  (item) => _buildInfoRow(context, theme, m, s, item.key, item.value.toString()),
                ),
              ],
            );
          }
          return _buildInfoRow(context, theme, m, s, e.key, value.toString());
        }).toList(),
      ),
    );
  }

  Widget _buildRawJson(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    AppSemantic s,
  ) {
    final raw = const JsonEncoder.withIndent('  ').convert(event);
    return Container(
      constraints: BoxConstraints(maxHeight: scaleW(200)),
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: s.accentContainer,
        borderRadius: m.radiusCard,
        border: Border.all(color: s.border, width: AppTheme.metrics.strokeUltraThin),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: raw));
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
                    decoration: BoxDecoration(
                      color: s.accentContainer,
                      borderRadius: m.radius4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DrawIcon(StrokeIcons.copy, size: m.iconSize12, color: s.accent),
                        SizedBox(width: m.kSpace4),
                        Text(
                          '复制',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: s.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace8),
            Text(
              raw,
              // 原始 JSON 等宽展示；行高是原 copyWith 显式声明的，用 copyWith 保留
              style: AppTextStyles.mono(context, size: m.fontSize12, color: s.textPrimary)
                  .copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasExceptions() {
    final ex = event['exception'] as Map<String, dynamic>?;
    return ex != null && (ex['values'] as List<dynamic>?)?.isNotEmpty == true;
  }

  bool _hasBreadcrumbs() {
    final bc = event['breadcrumbs'] as Map<String, dynamic>?;
    return bc != null && (bc['values'] as List<dynamic>?)?.isNotEmpty == true;
  }

  bool _hasTags() => (event['tags'] as Map<String, dynamic>?)?.isNotEmpty == true;

  bool _hasExtra() => (event['extra'] as Map<String, dynamic>?)?.isNotEmpty == true;

  bool _hasUser() => (event['user'] as Map<String, dynamic>?)?.isNotEmpty == true;

  bool _hasRequest() => (event['request'] as Map<String, dynamic>?)?.isNotEmpty == true;

  bool _hasContexts() => (event['contexts'] as Map<String, dynamic>?)?.isNotEmpty == true;

  String _extractMessage() {
    if (event['message'] != null && event['message'].toString().isNotEmpty) {
      return event['message'].toString();
    }
    if (event['title'] != null) return event['title'].toString();
    final exception = event['exception'] as Map<String, dynamic>?;
    if (exception != null) {
      final values = exception['values'] as List<dynamic>?;
      if (values != null && values.isNotEmpty) {
        final first = values[0] as Map<String, dynamic>?;
        if (first != null) {
          final type = first['type']?.toString() ?? '';
          final value = first['value']?.toString() ?? '';
          return '$type: $value';
        }
      }
    }
    return '未知事件';
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

  StrokeIcon _getLevelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'fatal':
        return StrokeIcons.newReleases;
      case 'error':
        return StrokeIcons.error;
      case 'warning':
        return StrokeIcons.warning;
      case 'info':
        return StrokeIcons.info;
      case 'debug':
        return StrokeIcons.bugReport;
      default:
        return StrokeIcons.info;
    }
  }

  StrokeIcon _getBreadcrumbIcon(String type) {
    switch (type) {
      case 'navigation':
        return StrokeIcons.navigation;
      case 'http':
        return StrokeIcons.http;
      case 'console':
        return StrokeIcons.terminal;
      case 'user':
        return StrokeIcons.touchApp;
      default:
        return StrokeIcons.circle;
    }
  }
}

class _InfoEntry {
  final String label;
  final String value;
  const _InfoEntry(this.label, this.value);
}
