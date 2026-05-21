import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/sentry_log/sentry_log_viewmodel.dart';

/// 日志筛选栏组件
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
      child: ClipRRect(
        borderRadius: m.radius12,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
            decoration: BoxDecoration(
              color: isDark
                  ? DarkColors.background1.withAlpha(120)
                  : LightColors.background1.withAlpha(160),
              borderRadius: m.radius12,
              border: Border.all(
                color: isDark
                    ? DarkColors.white10.withAlpha(30)
                    : LightColors.black10.withAlpha(20),
                width: 0.5,
              ),
            ),
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
          ),
        ),
      ),
    );
  }

  /// 构建项目筛选下拉框
  Widget _buildProjectFilter(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return Obx(() {
      final items = <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(
          value: '',
          child: Text('全部项目', overflow: TextOverflow.ellipsis),
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

      return SizedBox(
        width: scaleW(120),
        child: DropdownButtonFormField<String>(
          initialValue: viewModel.selectedProjectId.value.isEmpty
              ? null
              : viewModel.selectedProjectId.value,
          hint: Text(
            '全部项目',
            style: TextStyle(color: theme.hintColor, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? DarkColors.background2 : LightColors.background2,
            contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace6),
            border: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: m.radius8, borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: m.radius8,
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
            ),
          ),
          icon: Icon(Icons.unfold_more, size: m.iconSize16, color: theme.hintColor),
          style: theme.textTheme.bodySmall,
          items: items,
          onChanged: (value) {
            viewModel.selectedProjectId.value = value ?? '';
            onFilterChanged();
          },
        ),
      );
    });
  }

  /// 构建日志级别筛选标签组
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
          border: Border.all(
            color: isDark ? DarkColors.white10.withAlpha(20) : LightColors.black10.withAlpha(15),
            width: 0.5,
          ),
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
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(horizontal: m.kSpace8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (color ?? theme.colorScheme.primary).withAlpha(40)
                        : Colors.transparent,
                    borderRadius: m.radius6,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: (color ?? theme.colorScheme.primary).withAlpha(30),
                              blurRadius: scaleW(6),
                              offset: Offset(0, scaleW(2)),
                            ),
                          ]
                        : null,
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

  /// 构建环境筛选输入框
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

  /// 构建搜索输入框
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

  /// 构建筛选按钮（渐变 + 发光阴影）
  Widget _buildFilterButton(BuildContext context, ThemeData theme, ThemeMetrics m, bool isDark) {
    return _FilterButtonWidget(
      onFilterChanged: onFilterChanged,
      isDark: isDark,
    );
  }
}

/// 筛选按钮组件（带悬停发光效果）
class _FilterButtonWidget extends StatefulWidget {
  final VoidCallback onFilterChanged;
  final bool isDark;

  const _FilterButtonWidget({
    required this.onFilterChanged,
    required this.isDark,
  });

  @override
  State<_FilterButtonWidget> createState() => _FilterButtonWidgetState();
}

class _FilterButtonWidgetState extends State<_FilterButtonWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onFilterChanged,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          height: m.kSpace32,
          padding: EdgeInsets.symmetric(horizontal: m.kSpace12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withAlpha(200),
                    ]
                  : [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withAlpha(180),
                    ],
            ),
            borderRadius: m.radius8,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withAlpha(_hovered ? 80 : 60),
                blurRadius: _hovered ? scaleW(12) : scaleW(6),
                offset: Offset(0, _hovered ? scaleW(3) : scaleW(2)),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _hovered ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Icon(Icons.tune_rounded, size: m.iconSize16, color: Colors.white),
              ),
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
    );
  }
}
