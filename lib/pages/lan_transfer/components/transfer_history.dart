import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 传输历史组件
class TransferHistory extends StatelessWidget {
  final List<TransferItem> items;
  final Function(String) onCancel;
  final Function(String)? onDelete;
  final Function(String)? onDeleteWithFile;

  const TransferHistory({
    super.key,
    required this.items,
    required this.onCancel,
    this.onDelete,
    this.onDeleteWithFile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TransferHistoryCard(
          item: item,
          isDark: isDark,
          onCancel: () => onCancel(item.transferId),
          onDelete: onDelete != null ? () => onDelete!(item.transferId) : null,
          onDeleteWithFile: onDeleteWithFile != null
              ? () => onDeleteWithFile!(item.transferId)
              : null,
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
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteWithFile;

  const _TransferHistoryCard({
    required this.item,
    required this.isDark,
    required this.onCancel,
    this.onDelete,
    this.onDeleteWithFile,
  });

  @override
  Widget build(BuildContext context) {
    final isReceived =
        item.receiverDeviceId.isNotEmpty && item.senderDeviceId != item.receiverDeviceId;

    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
      decoration: BoxDecoration(
        color: isDark ? DarkColors.background1 : LightColors.background1,
        border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：类型图标 + 文件名 + 状态
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 类型图标
              Container(
                width: scaleW(38),
                height: scaleW(38),
                decoration: BoxDecoration(
                  color: _getStatusColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getTypeIcon(item.transferType),
                  size: scaleW(18),
                  color: _getStatusColor(),
                ),
              ),

              SizedBox(width: AppTheme.metrics.kSpace10),

              // 文件名/内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fileName ?? item.textContent ?? '未知',
                      style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.w600, height: 1.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace2),
                    Row(
                      children: [
                        // 方向徽标
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppTheme.metrics.kSpace8,
                            vertical: AppTheme.metrics.kSpace2,
                          ),
                          decoration: BoxDecoration(
                            color: isReceived
                                ? Colors.blue.withValues(alpha: 0.12)
                                : Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isReceived ? '接收' : '发送',
                            style: TextStyle(fontSize: 11.0, height: 1.4, color: isReceived ? Colors.blue : Colors.orange,
                            ),
                          ),
                        ),
                        SizedBox(width: AppTheme.metrics.kSpace8),
                        Flexible(
                          child: Text(
                            isReceived ? item.senderDeviceName : '→ ${item.receiverDeviceId}',
                            style: TextStyle(fontSize: 11.0, height: 1.4,
                              color: isDark ? DarkColors.white80 : LightColors.black80,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(width: AppTheme.metrics.kSpace8),

              // 状态徽标
              _StatusBadge(status: item.status),
            ],
          ),

          // 文件大小
          if (item.fileSize != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            Text(
              _formatFileSize(item.fileSize!),
              style: TextStyle(fontSize: 11.0, height: 1.4,
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ],

          // 进度条（传输中）
          if (item.status == TransferStatus.transferring) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress / 100,
                minHeight: scaleW(4),
                backgroundColor: isDark ? DarkColors.white10 : LightColors.black10,
                color: isDark ? DarkColors.primary : LightColors.primary,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              '${item.progress.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 11.0, height: 1.4,
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ],

          // 错误信息
          if (item.errorMessage != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            Text(
              item.errorMessage!,
              style: TextStyle(fontSize: 11.0, height: 1.4, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 操作按钮区
          if (_shouldShowActions()) ...[
            SizedBox(height: AppTheme.metrics.kSpace10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 删除记录
                if (onDelete != null) _buildDeleteButton(context),

                SizedBox(width: AppTheme.metrics.kSpace8),

                // iOS/Android 已完成文件传输：用其他应用打开
                if (_canOpenFile()) _buildOpenButton(context),

                // 文本传输已完成：复制到剪贴板
                if (item.status == TransferStatus.completed &&
                    item.transferType == TransferType.text &&
                    item.textContent != null)
                  _buildCopyButton(context),

                // 传输中：取消
                if (item.status == TransferStatus.transferring) _buildCancelButton(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool _shouldShowActions() {
    // 始终显示操作区（至少有删除按钮）
    return true;
  }

  bool _canOpenFile() {
    return item.status == TransferStatus.completed &&
        item.filePath != null &&
        (Platform.isIOS || Platform.isAndroid);
  }

  Widget _buildDeleteButton(BuildContext context) {
    final hasFile =
        item.filePath != null &&
        (item.status == TransferStatus.completed || item.status == TransferStatus.failed);

    return GestureDetector(
      onTap: () async {
        if (hasFile && onDeleteWithFile != null) {
          // 提示是否同时删除文件
          final result = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除记录'),
              content: const Text('是否同时删除已保存的文件？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('仅删除记录'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('删除记录和文件', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (result == true) {
            onDeleteWithFile?.call();
          } else {
            onDelete?.call();
          }
        } else {
          onDelete?.call();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: scaleW(14), color: Colors.red.shade400),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text('删除', style: TextStyle(fontSize: 11.0, height: 1.4, color: Colors.red.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final path = item.filePath;
        if (path == null) return;
        final box = context.findRenderObject() as RenderBox?;
        final screenSize = MediaQuery.of(context).size;
        final Rect origin;
        if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
          origin = box.localToGlobal(Offset.zero) & box.size;
        } else {
          origin = Rect.fromCenter(
            center: Offset(screenSize.width / 2, screenSize.height * 0.7),
            width: screenSize.width / 2,
            height: 50,
          );
        }
        SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            subject: item.fileName ?? '互传文件',
            sharePositionOrigin: origin,
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: (Get.isDarkMode ? DarkColors.primary : LightColors.primary).withValues(
            alpha: 0.12,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ios_share,
              size: scaleW(14),
              color: Get.isDarkMode ? DarkColors.primary : LightColors.primary,
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '用其他应用打开',
              style: TextStyle(fontSize: 11.0, height: 1.4,
                color: Get.isDarkMode ? DarkColors.primary : LightColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: item.textContent ?? ''));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 2)));
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy, size: scaleW(14), color: Colors.green),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text('复制文本', style: TextStyle(fontSize: 11.0, height: 1.4, color: Colors.green)),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return GestureDetector(
      onTap: onCancel,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_outlined, size: scaleW(14), color: Colors.red),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text('取消', style: TextStyle(fontSize: 11.0, height: 1.4, color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (item.status) {
      case TransferStatus.completed:
        return Colors.green;
      case TransferStatus.failed:
        return Colors.red;
      case TransferStatus.rejected:
        return Colors.red;
      case TransferStatus.cancelled:
        return Colors.grey;
      case TransferStatus.transferring:
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  IconData _getTypeIcon(TransferType type) {
    switch (type) {
      case TransferType.file:
        return Icons.insert_drive_file_outlined;
      case TransferType.text:
        return Icons.text_snippet_outlined;
      case TransferType.image:
        return Icons.image_outlined;
      case TransferType.video:
        return Icons.video_file_outlined;
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

/// 状态徽标
class _StatusBadge extends StatelessWidget {
  final TransferStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (status) {
      TransferStatus.pending => (Colors.orange, '等待'),
      TransferStatus.accepted => (Colors.blue, '已接受'),
      TransferStatus.rejected => (Colors.red, '已拒绝'),
      TransferStatus.transferring => (Colors.blue, '传输中'),
      TransferStatus.completed => (Colors.green, '完成'),
      TransferStatus.failed => (Colors.red, '失败'),
      TransferStatus.cancelled => (Colors.grey, '已取消'),
      TransferStatus.queued => (Colors.orange, '排队中'),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.0, height: 1.4, color: color)),
    );
  }
}
