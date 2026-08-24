import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';

class MediaSelectionBar extends StatelessWidget {
  const MediaSelectionBar({
    super.key,
    required this.selectedCount,
    required this.onDelete,
    required this.onCancel,
    this.onSelectUnfavorited,
  });

  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  /// 可选：一键选中当前文件夹内未收藏的集合（仅浏览层提供）
  final VoidCallback? onSelectUnfavorited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: appMetrics.kSpace16,
            vertical: appMetrics.kSpace12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: appMetrics.kSpace10,
                  vertical: appMetrics.kSpace4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: appMetrics.radius999,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: scaleW(16),
                      color: theme.colorScheme.primary,
                    ),
                    SizedBox(width: appMetrics.kSpace4),
                    Text(
                      '已选择 $selectedCount 个项目',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (onSelectUnfavorited != null) ...[
                TextButton(
                  onPressed: onSelectUnfavorited,
                  child: const Text('选择未收藏集合'),
                ),
                SizedBox(width: appMetrics.kSpace8),
              ],
              TextButton(onPressed: onCancel, child: const Text('取消选择')),
              SizedBox(width: appMetrics.kSpace8),
              FilledButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('移出媒体库'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
