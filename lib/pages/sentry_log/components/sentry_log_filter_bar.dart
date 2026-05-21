import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';

class SentryLogFilterBar extends StatelessWidget {
  final SentryLogViewModel viewModel;
  final VoidCallback onFilterChanged;

  const SentryLogFilterBar({super.key, required this.viewModel, required this.onFilterChanged});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace12, m.kSpace16, m.kSpace4),
      child: Row(
        children: [
          _buildProjectFilter(context, theme, m, isDark),
          SizedBox(width: m.kSpace8),
          _buildLevelChips(context, theme, m, isDark),
          SizedBox(width: m.kSpace8),
          _buildEnvironmentField(context, theme, m, isDark),
          SizedBox(width: m.kSpace8),
          Expanded(child: _buildSearchField(context, theme, m, isDark)),
          SizedBox(width: m.kSpace8),
          _buildFilterButton(context, theme, m, isDark),
        ],
      ),
    );
  }

  Widget _buildProjectFilter(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Obx(() {
      final items = <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
          value: '',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apps, size: m.iconSize16, color: theme.hintColor),
              SizedBox(width: m.kSpace4),
              const Text('全部项目'),
            ],
          ),
        ),
        ...viewModel.projects.map(
          (p) => DropdownMenuItem<String>(
            value: p['id']?.toString() ?? '',
            child: Text(
              p['name']?.toString() ?? p['id']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ];

      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scaleW(160)),
        child: DropdownButtonFormField<String>(
          initialValue: viewModel.selectedProjectId.value.isEmpty
              ? null
              : viewModel.selectedProjectId.value,
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apps, size: m.iconSize16, color: theme.hintColor),
              SizedBox(width: m.kSpace4),
              Text('全部项目', style: TextStyle(color: theme.hintColor)),
            ],
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? DarkColors.background2 : LightColors.background2,
            contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
            border: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: m.radius8,
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
          ),
          icon: Icon(Icons.unfold_more, size: m.iconSize18, color: theme.hintColor),
          style: theme.textTheme.bodyMedium,
          items: items,
          onChanged: (value) {
            viewModel.selectedProjectId.value = value ?? '';
            onFilterChanged();
          },
        ),
      );
    });
  }

  Widget _buildLevelChips(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    const levels = ['', 'fatal', 'error', 'warning', 'info', 'debug'];
    const levelLabels = ['全部', '致命', '错误', '警告', '信息', '调试'];
    const levelColors = [
      null,
      Color(0xFF9C27B0),
      Color(0xFFE53935),
      Color(0xFFFB8C00),
      Color(0xFF1E88E5),
      Color(0xFF757575),
    ];

    return Obx(
      () => Container(
        height: m.kSpace32,
        decoration: BoxDecoration(
          color: isDark ? DarkColors.background2 : LightColors.background2,
          borderRadius: m.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(levels.length, (i) {
            final isSelected = viewModel.selectedLevel.value == levels[i];
            final color = levelColors[i];
            return Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? m.kSpace4 : m.kSpace2,
                right: i == levels.length - 1 ? m.kSpace4 : 0,
              ),
              child: GestureDetector(
                onTap: () {
                  viewModel.selectedLevel.value = levels[i];
                  onFilterChanged();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (color ?? theme.colorScheme.primary).withAlpha(40)
                        : Colors.transparent,
                    borderRadius: m.radius6,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    levelLabels[i],
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isSelected ? (color ?? theme.colorScheme.primary) : theme.hintColor,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEnvironmentField(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    bool isDark,
  ) {
    return Obx(
      () => SizedBox(
        width: 110,
        height: m.kSpace32,
        child: TextFormField(
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: '环境',
            hintStyle: TextStyle(color: theme.hintColor),
            prefixIcon: Icon(Icons.language_rounded, size: m.iconSize16, color: theme.hintColor),
            contentPadding: EdgeInsets.symmetric(vertical: m.kSpace4),
            filled: true,
            fillColor: isDark ? DarkColors.background2 : LightColors.background2,
            border: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: m.radius8,
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
            suffixIcon: viewModel.selectedEnvironment.value.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      viewModel.selectedEnvironment.value = '';
                      onFilterChanged();
                    },
                    child: Icon(Icons.close, size: m.iconSize14, color: theme.hintColor),
                  )
                : null,
            isDense: true,
          ),
          onChanged: (value) => viewModel.selectedEnvironment.value = value,
          onFieldSubmitted: (_) => onFilterChanged(),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Obx(
      () => SizedBox(
        height: m.kSpace32,
        child: TextFormField(
          style: theme.textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: '搜索事件...',
            hintStyle: TextStyle(color: theme.hintColor),
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: m.kSpace8, right: m.kSpace4),
              child: Icon(Icons.search_rounded, size: m.iconSize18, color: theme.hintColor),
            ),
            contentPadding: EdgeInsets.symmetric(vertical: m.kSpace4),
            filled: true,
            fillColor: isDark ? DarkColors.background2 : LightColors.background2,
            border: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: m.radius8,
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
            suffixIcon: viewModel.searchQuery.value.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      viewModel.searchQuery.value = '';
                      onFilterChanged();
                    },
                    child: Padding(
                      padding: EdgeInsets.only(right: m.kSpace8),
                      child: Icon(Icons.close, size: m.iconSize14, color: theme.hintColor),
                    ),
                  )
                : null,
            isDense: true,
          ),
          onChanged: (value) => viewModel.searchQuery.value = value,
          onFieldSubmitted: (_) => onFilterChanged(),
        ),
      ),
    );
  }

  Widget _buildFilterButton(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Container(
      height: m.kSpace32,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withAlpha(180)],
        ),
        borderRadius: m.radius8,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withAlpha(60),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: m.radius8,
        child: InkWell(
          borderRadius: m.radius8,
          onTap: onFilterChanged,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_rounded, size: m.iconSize16, color: Colors.white),
                SizedBox(width: m.kSpace4),
                Text(
                  '筛选',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
