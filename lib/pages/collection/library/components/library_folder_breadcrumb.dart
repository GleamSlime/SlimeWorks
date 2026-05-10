import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';

/// 文件夹内导航面包屑
class FolderBreadcrumb extends StatelessWidget {
  final String folderName;
  final VoidCallback onBack;

  const FolderBreadcrumb({super.key, required this.folderName, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace16, vertical: appMetrics.kSpace8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withAlpha(30))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_left,
                  size: appMetrics.fontSize18,
                  color: theme.colorScheme.primary,
                ),
                Text(
                  '返回',
                  style: TextStyle(
                    fontSize: appMetrics.fontSize13,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: appMetrics.kSpace8),
          Icon(Icons.chevron_right, size: appMetrics.fontSize13, color: theme.hintColor),
          SizedBox(width: appMetrics.kSpace8),
          Text(
            folderName,
            style: TextStyle(
              fontSize: appMetrics.fontSize13,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }
}
