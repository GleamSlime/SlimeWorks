import 'package:flutter/material.dart';

import 'package:slime_works/core/index.dart';

class MediaSelectionBar extends StatelessWidget {
  const MediaSelectionBar({
    super.key,
    required this.selectedCount,
    required this.onDelete,
    required this.onCancel,
  });

  final int selectedCount;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: appMetrics.kSpace16, vertical: appMetrics.kSpace12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Text('已选择 $selectedCount 个集合'),
          const Spacer(),
          TextButton(onPressed: onCancel, child: const Text('取消选择')),
          SizedBox(width: appMetrics.kSpace8),
          FilledButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('移出媒体库'),
          ),
        ],
      ),
    );
  }
}
