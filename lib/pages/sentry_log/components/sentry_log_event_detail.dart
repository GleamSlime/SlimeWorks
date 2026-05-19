import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';

class SentryLogEventDetail extends StatelessWidget {
  final Map<String, dynamic> event;
  final SentryLogViewModel viewModel;

  const SentryLogEventDetail({super.key, required this.event, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final level = event['level']?.toString() ?? 'info';
    final levelColor = viewModel.getLevelColor(level);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: m.radius16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, theme, m, isDark, level, levelColor),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(m.kSpace16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoGrid(theme, m, isDark),
                    if (_hasExceptions()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.bug_report_rounded,
                        '异常信息',
                        const Color(0xFFE53935),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildExceptions(theme, m, isDark),
                    ],
                    if (_hasBreadcrumbs()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.timeline_rounded,
                        '面包屑',
                        const Color(0xFF1E88E5),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildBreadcrumbs(theme, m, isDark),
                    ],
                    if (_hasTags()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.label_rounded,
                        '标签',
                        const Color(0xFFFB8C00),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildTags(theme, m, isDark),
                    ],
                    if (_hasExtra()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.data_object_rounded,
                        '额外数据',
                        const Color(0xFF43A047),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildExtra(theme, m, isDark),
                    ],
                    if (_hasUser()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.person_rounded,
                        '用户信息',
                        const Color(0xFF8E24AA),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildUser(theme, m, isDark),
                    ],
                    if (_hasRequest()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.http_rounded,
                        '请求信息',
                        const Color(0xFF00897B),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildRequest(theme, m, isDark),
                    ],
                    if (_hasContexts()) ...[
                      SizedBox(height: m.kSpace16),
                      _buildSectionTitle(
                        theme,
                        m,
                        Icons.devices_rounded,
                        '上下文',
                        const Color(0xFF546E7A),
                      ),
                      SizedBox(height: m.kSpace8),
                      _buildContexts(theme, m, isDark),
                    ],
                    SizedBox(height: m.kSpace16),
                    _buildSectionTitle(
                      theme,
                      m,
                      Icons.code_rounded,
                      '原始数据',
                      theme.colorScheme.primary,
                    ),
                    SizedBox(height: m.kSpace8),
                    _buildRawJson(theme, m, isDark),
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
    bool isDark,
    String level,
    Color levelColor,
  ) {
    final message = _extractMessage();
    return Container(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace14, m.kSpace8, m.kSpace14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [levelColor.withAlpha(30), levelColor.withAlpha(8)],
        ),
        border: Border(
          bottom: BorderSide(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: m.kSpace40,
            height: m.kSpace40,
            decoration: BoxDecoration(
              color: levelColor.withAlpha(25),
              borderRadius: m.radius8,
              border: Border.all(color: levelColor.withAlpha(50), width: 0.5),
            ),
            child: Icon(_getLevelIcon(level), color: levelColor, size: m.iconSize18),
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
                        color: levelColor.withAlpha(25),
                        borderRadius: m.radius4,
                      ),
                      child: Text(
                        level.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: levelColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    SizedBox(width: m.kSpace6),
                    if (event['environment'] != null)
                      Text(
                        event['environment'].toString(),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: m.iconSize20, color: theme.hintColor),
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
    IconData icon,
    String title,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: m.iconSize14, color: color),
        SizedBox(width: m.kSpace6),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(ThemeData theme, ThemeMetrics m, bool isDark) {
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
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
      ),
      child: Column(
        children: entries.map((e) => _buildInfoRow(theme, m, isDark, e.label, e.value)).toList(),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, ThemeMetrics m, bool isDark, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExceptions(ThemeData theme, ThemeMetrics m, bool isDark) {
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
            color: isDark ? DarkColors.background1 : LightColors.background1,
            borderRadius: m.radius10,
            border: Border.all(
              color: isDark ? DarkColors.white10 : LightColors.black10,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withAlpha(15),
                  borderRadius: m.radius6,
                ),
                child: Text(
                  '$type: $value',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFE53935),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
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
                          width: 3,
                          height: m.kSpace14,
                          margin: EdgeInsets.only(top: m.kSpace4),
                          decoration: BoxDecoration(
                            color: inApp ? const Color(0xFFE53935) : theme.hintColor.withAlpha(80),
                            borderRadius: m.radius2,
                          ),
                        ),
                        SizedBox(width: m.kSpace6),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                color: isDark ? DarkColors.white80 : LightColors.black80,
                              ),
                              children: [
                                TextSpan(
                                  text: function,
                                  style: TextStyle(
                                    fontWeight: inApp ? FontWeight.w700 : FontWeight.w400,
                                    color: inApp ? theme.colorScheme.primary : null,
                                  ),
                                ),
                                TextSpan(text: '  '),
                                TextSpan(
                                  text: '$filename:$lineno',
                                  style: TextStyle(color: theme.hintColor),
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

  Widget _buildBreadcrumbs(ThemeData theme, ThemeMetrics m, bool isDark) {
    final breadcrumbs = event['breadcrumbs'] as Map<String, dynamic>?;
    if (breadcrumbs == null) return const SizedBox.shrink();
    final values = breadcrumbs['values'] as List<dynamic>? ?? [];

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
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
                Icon(_getBreadcrumbIcon(type), size: m.iconSize12, color: theme.hintColor),
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
                                color: theme.hintColor,
                                fontFeatures: [const FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                      if (message.isNotEmpty)
                        Text(
                          message,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontFamily: 'monospace',
                          ),
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

  Widget _buildTags(ThemeData theme, ThemeMetrics m, bool isDark) {
    final tags = event['tags'] as Map<String, dynamic>? ?? {};
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: m.kSpace6,
      runSpacing: m.kSpace6,
      children: tags.entries.map((e) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace4),
          decoration: BoxDecoration(
            color: const Color(0xFFFB8C00).withAlpha(12),
            borderRadius: m.radius6,
            border: Border.all(color: const Color(0xFFFB8C00).withAlpha(30), width: 0.5),
          ),
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.labelSmall,
              children: [
                TextSpan(
                  text: '${e.key}: ',
                  style: TextStyle(color: const Color(0xFFFB8C00), fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: e.value.toString(),
                  style: TextStyle(color: isDark ? DarkColors.white80 : LightColors.black80),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildExtra(ThemeData theme, ThemeMetrics m, bool isDark) {
    final extra = event['extra'] as Map<String, dynamic>? ?? {};
    if (extra.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
      ),
      child: Column(
        children: extra.entries
            .map((e) => _buildInfoRow(theme, m, isDark, e.key, e.value.toString()))
            .toList(),
      ),
    );
  }

  Widget _buildUser(ThemeData theme, ThemeMetrics m, bool isDark) {
    final user = event['user'] as Map<String, dynamic>? ?? {};
    if (user.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: m.kSpace16,
            backgroundColor: const Color(0xFF8E24AA).withAlpha(25),
            child: Icon(Icons.person_rounded, size: m.iconSize16, color: const Color(0xFF8E24AA)),
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
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                if (user['id'] != null)
                  Text(
                    'ID: ${user['id']}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequest(ThemeData theme, ThemeMetrics m, bool isDark) {
    final request = event['request'] as Map<String, dynamic>? ?? {};
    if (request.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
      ),
      child: Column(
        children: [
          if (request['method'] != null || request['url'] != null)
            _buildInfoRow(
              theme,
              m,
              isDark,
              '请求',
              '${request['method'] ?? ''} ${request['url'] ?? ''}',
            ),
          if (request['headers'] != null)
            _buildInfoRow(theme, m, isDark, 'Headers', request['headers'].toString()),
        ],
      ),
    );
  }

  Widget _buildContexts(ThemeData theme, ThemeMetrics m, bool isDark) {
    final contexts = event['contexts'] as Map<String, dynamic>? ?? {};
    if (contexts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
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
                      color: const Color(0xFF546E7A),
                    ),
                  ),
                ),
                ...value.entries.map(
                  (item) => _buildInfoRow(theme, m, isDark, item.key, item.value.toString()),
                ),
              ],
            );
          }
          return _buildInfoRow(theme, m, isDark, e.key, value.toString());
        }).toList(),
      ),
    );
  }

  Widget _buildRawJson(ThemeData theme, ThemeMetrics m, bool isDark) {
    final raw = const JsonEncoder.withIndent('  ').convert(event);
    return Container(
      constraints: BoxConstraints(maxHeight: 200),
      padding: EdgeInsets.all(m.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5F5),
        borderRadius: m.radius10,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 0.5),
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
                      color: theme.colorScheme.primary.withAlpha(15),
                      borderRadius: m.radius4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: m.iconSize12,
                          color: theme.colorScheme.primary,
                        ),
                        SizedBox(width: m.kSpace4),
                        Text(
                          '复制',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
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
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: isDark ? DarkColors.white80 : LightColors.black80,
                height: 1.5,
              ),
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

  IconData _getLevelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'fatal':
        return Icons.new_releases_rounded;
      case 'error':
        return Icons.error_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'info':
        return Icons.info_rounded;
      case 'debug':
        return Icons.bug_report_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  IconData _getBreadcrumbIcon(String type) {
    switch (type) {
      case 'navigation':
        return Icons.navigation_rounded;
      case 'http':
        return Icons.http_rounded;
      case 'console':
        return Icons.terminal_rounded;
      case 'user':
        return Icons.touch_app_rounded;
      default:
        return Icons.circle_rounded;
    }
  }
}

class _InfoEntry {
  final String label;
  final String value;
  const _InfoEntry(this.label, this.value);
}
