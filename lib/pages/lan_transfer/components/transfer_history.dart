import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

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
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TransferHistoryCard(
          item: item,
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
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteWithFile;

  const _TransferHistoryCard({
    required this.item,
    required this.onCancel,
    this.onDelete,
    this.onDeleteWithFile,
  });

  @override
  Widget build(BuildContext context) {
    // 取色只走语义层：isDark 三元分支与裸 Colors.* 一律收敛到 AppSemantic
    final s = AppSemantic.of(context);
    final status = _getStatusRole(s);
    final isReceived =
        item.receiverDeviceId.isNotEmpty && item.senderDeviceId != item.receiverDeviceId;

    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
      decoration: BoxDecoration(
        color: s.surface,
        border: Border.all(color: s.border),
        borderRadius: AppTheme.metrics.radius14,
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
                  color: status.container,
                  borderRadius: AppTheme.metrics.radius10,
                ),
                child: DrawIcon(
                  _getTypeIcon(item.transferType),
                  size: scaleW(18),
                  color: status.color,
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
                      style: AppTextStyles.cardTitle(context),
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
                            color: (isReceived ? s.info : s.warning).container,
                            borderRadius: AppTheme.metrics.radius4,
                          ),
                          child: Text(
                            isReceived ? '接收' : '发送',
                            style: AppTextStyles.role(
                              context,
                              fontSize: AppTheme.metrics.fontSize11,
                              height: 1.4,
                              color: (isReceived ? s.info : s.warning).onContainer,
                            ),
                          ),
                        ),
                        SizedBox(width: AppTheme.metrics.kSpace8),
                        Flexible(
                          child: Text(
                            isReceived ? item.senderDeviceName : '→ ${item.receiverDeviceId}',
                            style: AppTextStyles.role(
                              context,
                              fontSize: AppTheme.metrics.fontSize11,
                              height: 1.4,
                              color: s.textSecondary,
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
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.textSecondary,
              ),
            ),
          ],

          // 进度条（传输中）
          if (item.status == TransferStatus.transferring) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            ClipRRect(
              borderRadius: AppTheme.metrics.radius4,
              child: LinearProgressIndicator(
                value: item.progress / 100,
                minHeight: scaleW(4),
                backgroundColor: s.surfaceSunken,
                color: s.accent,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              '${item.progress.toStringAsFixed(1)}%',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.textSecondary,
              ),
            ),
          ],

          // 错误信息
          if (item.errorMessage != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            Text(
              item.errorMessage!,
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.danger.onContainer,
              ),
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
                if (item.status == TransferStatus.transferring) _buildCancelButton(context),
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
    final s = AppSemantic.of(context);
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
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('仅删除记录')),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(
                    '删除记录和文件',
                    style: AppTextStyles.rowTitle(ctx).copyWith(color: s.danger.onContainer),
                  ),
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
          color: s.danger.container,
          borderRadius: AppTheme.metrics.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(StrokeIcons.deleteOutline,
              size: scaleW(14),
              color: s.danger.color,
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '删除',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.danger.onContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenButton(BuildContext context) {
    final s = AppSemantic.of(context);
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
          color: s.accentContainer,
          borderRadius: AppTheme.metrics.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(StrokeIcons.iosShare,
              size: scaleW(14),
              color: s.accent,
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '用其他应用打开',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyButton(BuildContext context) {
    final s = AppSemantic.of(context);
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: item.textContent ?? ''));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), duration: AppMotion.dwell));
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: s.success.container,
          borderRadius: AppTheme.metrics.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(StrokeIcons.copy,
              size: scaleW(14),
              color: s.success.color,
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '复制文本',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.success.onContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton(BuildContext context) {
    final s = AppSemantic.of(context);
    return GestureDetector(
      onTap: onCancel,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.metrics.kSpace10,
          vertical: AppTheme.metrics.kSpace8,
        ),
        decoration: BoxDecoration(
          color: s.danger.container,
          borderRadius: AppTheme.metrics.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(StrokeIcons.cancel,
              size: scaleW(14),
              color: s.danger.color,
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Text(
              '取消',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: s.danger.onContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态语义色：走状态角色令牌（容器底 / 图上色 / 文字色三档一体）
  AppStatusRole _getStatusRole(AppSemantic s) {
    switch (item.status) {
      case TransferStatus.completed:
        return s.success;
      case TransferStatus.failed:
        return s.danger;
      case TransferStatus.rejected:
        return s.danger;
      case TransferStatus.cancelled:
        return s.neutral;
      case TransferStatus.transferring:
        return s.info;
      default:
        return s.warning;
    }
  }

  StrokeIcon _getTypeIcon(TransferType type) {
    switch (type) {
      case TransferType.file:
        return StrokeIcons.insertDriveFile;
      case TransferType.text:
        return StrokeIcons.textSnippet;
      case TransferType.image:
        return StrokeIcons.image;
      case TransferType.video:
        return StrokeIcons.videoFile;
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
    final s = AppSemantic.of(context);
    final (role, text) = switch (status) {
      TransferStatus.pending => (s.warning, '等待'),
      TransferStatus.accepted => (s.info, '已接受'),
      TransferStatus.rejected => (s.danger, '已拒绝'),
      TransferStatus.transferring => (s.info, '传输中'),
      TransferStatus.completed => (s.success, '完成'),
      TransferStatus.failed => (s.danger, '失败'),
      TransferStatus.cancelled => (s.neutral, '已取消'),
      TransferStatus.queued => (s.warning, '排队中'),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace8,
        vertical: AppTheme.metrics.kSpace4,
      ),
      decoration: BoxDecoration(
        color: role.container,
        borderRadius: AppTheme.metrics.radius6,
      ),
      child: Text(
        text,
        style: AppTextStyles.role(
          context,
          fontSize: AppTheme.metrics.fontSize11,
          height: 1.4,
          color: role.onContainer,
        ),
      ),
    );
  }
}
