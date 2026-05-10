import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class StyledTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<StyledTab> tabs;

  const StyledTabBar({super.key, required this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8),
        indicator: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8),
        dividerColor: Colors.transparent,
        tabs: tabs.map((tab) => _buildTab(context, tab)).toList(),
      ),
    );
  }

  Widget _buildTab(BuildContext context, StyledTab tab) {
    final theme = Theme.of(context);
    return Tab(
      height: 56,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace16, vertical: AppTheme.metrics.kSpace8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: AppTheme.metrics.iconSize20),
            SizedBox(width: AppTheme.metrics.kSpace8),
            Text(tab.label, style: TextStyle(fontSize: AppTheme.metrics.fontSize13, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
            if (tab.badge != null) ...[
              SizedBox(width: AppTheme.metrics.kSpace8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace6, vertical: AppTheme.metrics.kSpace2),
                decoration: BoxDecoration(color: tab.badgeColor ?? theme.colorScheme.error, borderRadius: AppTheme.metrics.radius10),
                child: Text(
                  tab.badge.toString(),
                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: AppTheme.metrics.fontSize11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StyledTab {
  final IconData icon;
  final String label;
  final int? badge;
  final Color? badgeColor;

  const StyledTab({required this.icon, required this.label, this.badge, this.badgeColor});
}
