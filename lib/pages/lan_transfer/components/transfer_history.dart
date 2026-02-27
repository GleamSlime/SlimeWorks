import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 传输历史组件
class TransferHistory extends StatelessWidget {
  final List<TransferItem> items;
  final Function(String) onCancel;

  const TransferHistory({super.key, required this.items, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TransferHistoryCard(
          item: item,
          isDark: isDark,
          onCancel: () => onCancel(item.transferId),
        );
      },
    );
  }
}

/// 传输历史卡片
class _TransferHistoryCard extends StatelessWidget {
  final TransferItem item;
  final bool isDark;
  final VoidCallback onCancel;

  const _TransferHistoryCard({required this.item, required this.isDark, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 类型图标
              Icon(
                _getTypeIcon(item.transferType),
                size: scaleW(24),
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),

              SizedBox(width: AppTheme.metrics.kSpace12),

              // 文件名或内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName ?? item.textContent ?? '未知',
                      style: AppTextStyles.body1(fontWeight: AppFontWeights.semiBold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace4),
                    Text(
                      '${item.senderDeviceName} → ${item.receiverDeviceId}',
                      style: AppTextStyles.caption(
                        color: isDark ? DarkColors.white80 : LightColors.black80,
                      ),
                    ),
                  ],
                ),
              ),

              // 状态标识
              _StatusBadge(status: item.status),
            ],
          ),

          // 文件大小和时间
          if (item.fileSize != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            Text(
              _formatFileSize(item.fileSize!),
              style: AppTextStyles.caption(
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ],

          SizedBox(height: AppTheme.metrics.kSpace8),

          // 进度条（传输中）
          if (item.status == TransferStatus.transferring) ...[
            LinearProgressIndicator(
              value: item.progress / 100,
              backgroundColor: isDark ? DarkColors.white10 : LightColors.black10,
            ),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              '${item.progress.toStringAsFixed(1)}%',
              style: AppTextStyles.caption(
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ],

          // 错误信息
          if (item.errorMessage != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            Text(item.errorMessage!, style: AppTextStyles.caption(color: Colors.red)),
          ],

          // 操作按钮
          if (item.status == TransferStatus.transferring) ...[
            SizedBox(height: AppTheme.metrics.kSpace12),
            TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel, size: 16),
              label: const Text('取消传输'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getTypeIcon(TransferType type) {
    switch (type) {
      case TransferType.file:
        return Icons.insert_drive_file;
      case TransferType.text:
        return Icons.text_fields;
      case TransferType.image:
        return Icons.image;
      case TransferType.video:
        return Icons.video_library;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 状态标识
class _StatusBadge extends StatelessWidget {
  final TransferStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    switch (status) {
      case TransferStatus.pending:
        color = Colors.orange;
        text = '等待';
        break;
      case TransferStatus.accepted:
        color = Colors.blue;
        text = '已接受';
        break;
      case TransferStatus.rejected:
        color = Colors.red;
        text = '已拒绝';
        break;
      case TransferStatus.transferring:
        color = Colors.blue;
        text = '传输中';
        break;
      case TransferStatus.completed:
        color = Colors.green;
        text = '完成';
        break;
      case TransferStatus.failed:
        color = Colors.red;
        text = '失败';
        break;
      case TransferStatus.cancelled:
        color = Colors.grey;
        text = '已取消';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: AppTextStyles.caption(color: color)),
    );
  }
}
