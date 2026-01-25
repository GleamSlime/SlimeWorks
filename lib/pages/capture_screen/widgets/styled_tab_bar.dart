import 'package:flutter/material.dart';

/// 优化的标签栏
class StyledTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<StyledTab> tabs;

  const StyledTabBar({super.key, required this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        indicator: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        dividerColor: Colors.transparent,
        tabs: tabs.map((tab) => _buildTab(context, tab)).toList(),
      ),
    );
  }

  Widget _buildTab(BuildContext context, StyledTab tab) {
    return Tab(
      height: 56,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tab.icon, size: 20),
            const SizedBox(width: 8),
            Text(tab.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            if (tab.badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: tab.badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  tab.badge.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
