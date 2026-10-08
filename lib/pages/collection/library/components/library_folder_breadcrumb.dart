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
    final s = AppSemantic.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace16, vertical: appMetrics.kSpace8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: s.hairline)),
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
                  color: s.accent,
                ),
                Text(
                  '返回',
                  style: AppTextStyles.role(
                    context,
                    fontSize: appMetrics.fontSize13,
                    color: s.accent,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: appMetrics.kSpace8),
          DrawIcon(StrokeIcons.chevronRight, size: appMetrics.fontSize13, color: s.textTertiary),
          SizedBox(width: appMetrics.kSpace8),
          Text(
            folderName,
            style: AppTextStyles.role(
              context,
              fontSize: appMetrics.fontSize13,
              weight: FontWeight.w600,
              color: s.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
