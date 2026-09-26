import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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
                DrawIcon(StrokeIcons.chevronLeft,
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
          DrawIcon(StrokeIcons.chevronRight, size: appMetrics.fontSize13, color: theme.hintColor),
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
