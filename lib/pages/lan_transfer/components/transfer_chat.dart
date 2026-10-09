import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:gal/gal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

/// 聊天风格传输记录视图（微信/QQ 气泡样式）
/// - 左侧：对方发来的消息/文件
/// - 右侧：自己发出的消息/文件
class TransferChatView extends StatefulWidget {
  final List<TransferItem> items;
  final String localDeviceId;
  final String localDeviceName;

  /// 对端设备 ID（用于查找在线状态）
  final String peerDeviceId;
  final Function(String transferId) onCancel;
  final Function(String transferId) onDelete;
  final Function(String transferId) onDeleteWithFile;

  /// 失败消息的重试回调
  final Function(String transferId)? onRetry;

  const TransferChatView({
    super.key,
    required this.items,
    required this.localDeviceId,
    required this.localDeviceName,
    required this.peerDeviceId,
    required this.onCancel,
    required this.onDelete,
    required this.onDeleteWithFile,
    this.onRetry,
  });

  @override
  State<TransferChatView> createState() => _TransferChatViewState();
}

class _TransferChatViewState extends State<TransferChatView> {
  final ScrollController _scrollController = ScrollController();

  /// 用户是否手动向上滚动（此时不自动滚到底部）
  bool _isUserScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 首次渲染后立即跳转到底部（不动画）
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialScrollToBottom());
  }

  void _initialScrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // 距底部超过 80px 则认为用户向上滚动
    final isAtBottom = pos.maxScrollExtent - pos.pixels <= 80;
    if (_isUserScrolledUp != !isAtBottom) {
      setState(() => _isUserScrolledUp = !isAtBottom);
    }
  }

  @override
  void didUpdateWidget(TransferChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新消息到来时，只有用户处于底部（没有手动向上滚动）才自动滚到底部
    if (widget.items.length != oldWidget.items.length && !_isUserScrolledUp) {
      // 等内容布局完成后再滚动，避免 maxScrollExtent 还未更新导致弹起
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: AppMotion.base,
            curve: AppMotion.decelerate,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 取色只走语义层：isDark 三元分支与裸 Colors.* 一律收敛到 AppSemantic
    final s = AppSemantic.of(context);

    if (widget.items.isEmpty) {
      return _buildEmpty(context);
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace16,
            vertical: AppTheme.metrics.kSpace12,
          ),
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final isSelf = item.senderDeviceId == widget.localDeviceId;
            final showDateHeader = _shouldShowDate(index);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateHeader) _buildDateHeader(context, item.createdAt),
                _ChatBubble(
                  key: ValueKey(item.transferId),
                  item: item,
                  isSelf: isSelf,
                  localDeviceName: widget.localDeviceName,
                  onCancel: () => widget.onCancel(item.transferId),
                  onDelete: () => widget.onDelete(item.transferId),
                  onDeleteWithFile: () => widget.onDeleteWithFile(item.transferId),
                  onRetry: widget.onRetry != null ? () => widget.onRetry!(item.transferId) : null,
                ),
              ],
            );
          },
        ),
        // 返回底部按鈕（手动向上滚动时显示）
        if (_isUserScrolledUp)
          Positioned(
            right: AppTheme.metrics.kSpace16,
            bottom: AppTheme.metrics.kSpace16,
            child: GestureDetector(
              onTap: () {
                setState(() => _isUserScrolledUp = false);
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: AppMotion.base,
                    curve: AppMotion.decelerate,
                  );
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace12,
                  vertical: AppTheme.metrics.kSpace8,
                ),
                decoration: BoxDecoration(
                  color: s.accent,
                  borderRadius: AppTheme.metrics.radius20,
                  boxShadow: s.elevation(Elevation.floating),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DrawIcon(StrokeIcons.keyboardDoubleArrowDown, size: scaleW(16), color: s.accentOn),
                    SizedBox(width: AppTheme.metrics.kSpace4),
                    Text(
                      '返回底部',
                      style: AppTextStyles.role(
                        context,
                        fontSize: AppTheme.metrics.fontSize11,
                        height: 1.4,
                        color: s.accentOn,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    final prev = widget.items[index - 1];
    final cur = widget.items[index];
    final prevTime = DateTime.tryParse(prev.createdAt);
    final curTime = DateTime.tryParse(cur.createdAt);
    if (prevTime == null || curTime == null) return false;
    return curTime.difference(prevTime).inMinutes >= 5;
  }

  Widget _buildDateHeader(BuildContext context, String dateStr) {
    final s = AppSemantic.of(context);
    final dt = DateTime.tryParse(dateStr);
    final label = dt != null ? _formatDateTime(dt) : dateStr;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace12),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace12,
            vertical: AppTheme.metrics.kSpace4,
          ),
          decoration: BoxDecoration(
            color: s.surfaceSunken,
            borderRadius: AppTheme.metrics.radius12,
          ),
          child: Text(
            label,
            style: AppTextStyles.role(
              context,
              fontSize: AppTheme.metrics.fontSize11,
              height: 1.4,
              color: s.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final s = AppSemantic.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrawIcon(StrokeIcons.chatBubbleOutline,
            size: scaleW(48),
            color: s.textDisabled,
          ),
          SizedBox(height: AppTheme.metrics.kSpace12),
          Text(
            '暂无传输记录',
            style: AppTextStyles.role(
              context,
              fontSize: AppTheme.metrics.fontSize13,
              height: 1.5,
              color: s.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (day == today) return hm;
    if (day == today.subtract(const Duration(days: 1))) return '昨天 $hm';
    return '${dt.month}/${dt.day} $hm';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 单条气泡
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatefulWidget {
  final TransferItem item;
  final bool isSelf;
  final String localDeviceName;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onDeleteWithFile;

  /// 失败消息的重试回调（仅自己发出的失败消息展示）
  final VoidCallback? onRetry;

  const _ChatBubble({
    super.key,
    required this.item,
    required this.isSelf,
    required this.localDeviceName,
    required this.onCancel,
    required this.onDelete,
    required this.onDeleteWithFile,
    this.onRetry,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: AppMotion.slow);
    _scaleAnim = CurvedAnimation(parent: _animController, curve: AppMotion.springCurve);
    _slideAnim = Tween<Offset>(
      begin: Offset(widget.isSelf ? 0.3 : -0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: AppMotion.decelerate));
    _animController.forward();
  }

  @override
  void didUpdateWidget(covariant _ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果是视频并且路径变了，重新初始化视频（handled by VideoPreviewPage instead)
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final isSelf = widget.isSelf;

    return SlideTransition(
      position: _slideAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        alignment: isSelf ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
          child: Row(
            mainAxisAlignment: isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isSelf) ...[
                _buildAvatar(isSelf),
                SizedBox(width: AppTheme.metrics.kSpace8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: isSelf ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // 昵称（仅对方显示）
                    if (!isSelf)
                      Padding(
                        padding: EdgeInsets.only(
                          left: AppTheme.metrics.kSpace4,
                          bottom: AppTheme.metrics.kSpace4,
                        ),
                        child: Text(
                          widget.item.senderDeviceName,
                          style: AppTextStyles.role(
                            context,
                            fontSize: AppTheme.metrics.fontSize11,
                            height: 1.4,
                            color: s.textTertiary,
                          ),
                        ),
                      ),
                    // 气泡内容
                    _buildBubble(context, isSelf),
                    // 时间 + 状态
                    Padding(
                      padding: EdgeInsets.only(
                        top: AppTheme.metrics.kSpace4,
                        left: AppTheme.metrics.kSpace4,
                        right: AppTheme.metrics.kSpace4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 失败时显示重试按鈕
                          if (isSelf &&
                              widget.item.status == TransferStatus.failed &&
                              widget.onRetry != null)
                            GestureDetector(
                              onTap: widget.onRetry,
                              child: Padding(
                                padding: EdgeInsets.only(right: AppTheme.metrics.kSpace4),
                                child: DrawIcon(StrokeIcons.refresh, size: scaleW(14), color: s.warning.color),
                              ),
                            ),
                          if (isSelf) _buildStatusIcon(),
                          if (isSelf) SizedBox(width: AppTheme.metrics.kSpace4),
                          Text(
                            _formatTime(widget.item.createdAt),
                            style: AppTextStyles.role(
                              context,
                              fontSize: AppTheme.metrics.fontSize11,
                              height: 1.4,
                              color: s.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelf) ...[
                SizedBox(width: AppTheme.metrics.kSpace8),
                _buildAvatar(isSelf),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool isSelf) {
    final s = AppSemantic.of(context);
    return Container(
      width: scaleW(36),
      height: scaleW(36),
      decoration: BoxDecoration(
        color: isSelf ? s.accentContainer : s.surfaceSunken,
        shape: BoxShape.circle,
      ),
      child: DrawIcon(
        _deviceIcon(widget.item.senderDeviceName),
        size: scaleW(18),
        color: isSelf ? s.accent : s.textSecondary,
      ),
    );
  }

  Widget _buildBubble(BuildContext context, bool isSelf) {
    final s = AppSemantic.of(context);
    final item = widget.item;
    // 我方气泡走唯一的实心强调底（accent + accentOn），
    // 对方气泡走半透明表面洗色，层次靠透明度而非第二种灰
    // 上面那条已被品牌水洗取代：气泡要认的是"我说的"那层紫（底是紫、字恒白），
    // 用全局 accent 当底时，暗色档会翻成白底深字，品牌色相整个丢掉。
    final bubbleColor = isSelf ? s.bubbleSelf : s.surfaceHover;
    final textColor = isSelf ? s.bubbleSelfOn : s.textPrimary;
    final radius = BorderRadius.only(
      topLeft: AppTheme.metrics.radius16.topLeft,
      topRight: AppTheme.metrics.radius16.topRight,
      bottomLeft: isSelf
          ? AppTheme.metrics.radius16.bottomLeft
          : AppTheme.metrics.radius4.bottomLeft,
      bottomRight: isSelf
          ? AppTheme.metrics.radius4.bottomRight
          : AppTheme.metrics.radius16.bottomRight,
    );

    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Container(
        constraints: BoxConstraints(maxWidth: scaleW(260)),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
        child: item.transferType == TransferType.text
            ? _buildTextBubble(item, textColor)
            : _buildFileBubble(item, textColor, isSelf),
      ),
    );
  }

  Widget _buildTextBubble(TransferItem item, Color textColor) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace12,
        vertical: AppTheme.metrics.kSpace10,
      ),
      child: SelectableText(
        item.textContent ?? '',
        style: AppTextStyles.role(
          context,
          fontSize: AppTheme.metrics.fontSize13,
          height: 1.5,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildFileBubble(TransferItem item, Color textColor, bool isSelf) {
    // 缩略图上压的是视频画面本身：播放键属媒体层 chrome，不跟明暗反相
    final s = AppSemantic.of(context);
    final iconData = _typeIcon(item.transferType);
    final name = item.fileName ?? '未知文件';
    final size = item.fileSize != null ? _formatFileSize(item.fileSize!) : '';
    final isTransferring = item.status == TransferStatus.transferring;
    // 如果是图片或视频且已完成，展示预览
    final hasLocal = item.filePath != null && item.status == TransferStatus.completed;

    Widget content() {
      if (hasLocal && item.transferType == TransferType.image) {
        final file = File(item.filePath!);
        if (!file.existsSync()) {
          // 发送方才显示"文件已移除"；接收方如果路径无效则回落到默认文件气泡
          if (isSelf) return _buildMissingFileHint(textColor);
          // Fall through to default file row for received items
        } else {
          return ClipRRect(
            borderRadius: AppTheme.metrics.radius12,
            child: GestureDetector(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _ImagePreviewPage(filePath: file.path, title: item.fileName ?? '图片'),
                ),
              ),
              child: Image.file(file, fit: BoxFit.cover, width: scaleW(220), height: scaleW(160)),
            ),
          );
        }
      }

      if (hasLocal && item.transferType == TransferType.video) {
        final file = File(item.filePath!);
        if (!file.existsSync()) {
          if (isSelf) return _buildMissingFileHint(textColor);
          // Fall through to default file row for received items
        } else {
          return ClipRRect(
            borderRadius: AppTheme.metrics.radius12,
            child: GestureDetector(
              onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _VideoPreviewPage(filePath: file.path, title: item.fileName ?? '视频'),
                ),
              ),
              child: Stack(
                children: [
                  // thumbnail: let VideoPlayer build first frame lazily
                  SizedBox(
                    width: scaleW(220),
                    height: scaleW(140),
                    child: VideoPlayerWidgetThumbnail(path: file.path),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: DrawIcon(StrokeIcons.playCircleOutline,
                        size: scaleW(48),
                        color: s.onMediaSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // 默认文件行（可点击分享）
      return GestureDetector(
        onTap: () {
          if (hasLocal) {
            final box = context.findRenderObject() as RenderBox?;
            final origin = box != null && box.hasSize
                ? box.localToGlobal(Offset.zero) & box.size
                : Rect.fromCenter(
                    center: Offset(
                      MediaQuery.of(context).size.width / 2,
                      MediaQuery.of(context).size.height * 0.7,
                    ),
                    width: MediaQuery.of(context).size.width / 2,
                    height: 50,
                  );
            SharePlus.instance.share(
              ShareParams(
                files: [XFile(item.filePath!)],
                subject: item.fileName ?? '互传文件',
                sharePositionOrigin: origin,
              ),
            );
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(iconData, size: scaleW(28), color: textColor.withValues(alpha: 0.8)),
            SizedBox(width: AppTheme.metrics.kSpace8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTextStyles.role(
                      context,
                      fontSize: AppTheme.metrics.fontSize13,
                      height: 1.5,
                      color: textColor,
                      weight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: AppTextStyles.role(
                        context,
                        fontSize: AppTheme.metrics.fontSize11,
                        height: 1.4,
                        color: textColor.withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content(),
          if (isTransferring) ...[
            SizedBox(height: AppTheme.metrics.kSpace8),
            ClipRRect(
              borderRadius: AppTheme.metrics.radius4,
              child: LinearProgressIndicator(
                value: item.progress / 100,
                minHeight: scaleW(3),
                backgroundColor: textColor.withValues(alpha: 0.2),
                color: textColor,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              '${item.progress.toStringAsFixed(1)}%',
              style: AppTextStyles.role(
                context,
                fontSize: AppTheme.metrics.fontSize11,
                height: 1.4,
                color: textColor.withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 文件不存在时显示的占位提示
  Widget _buildMissingFileHint(Color textColor) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DrawIcon(StrokeIcons.brokenImage,
            size: scaleW(20),
            color: textColor.withValues(alpha: 0.5),
          ),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Text(
            '文件已移除',
            style: AppTextStyles.role(
              context,
              fontSize: AppTheme.metrics.fontSize11,
              height: 1.4,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    final s = AppSemantic.of(context);
    final item = widget.item;
    return switch (item.status) {
      TransferStatus.completed => DrawIcon(StrokeIcons.doneAll, size: scaleW(14), color: s.info.color),
      TransferStatus.failed => GestureDetector(
        onTap: () {
          final errMsg = (item.errorMessage != null && item.errorMessage!.isNotEmpty)
              ? item.errorMessage!
              : '发送失败（原因未知，可能是对方离线或网络异常）';
          Get.snackbar(
            '发送失败',
            errMsg,
            duration: AppMotion.dwellNotice,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: s.danger.color.withValues(alpha: 0.85),
            // 底色是实心状态色本身，墨只能是恒白（onStatusBadge），不能用 onContainer
            colorText: s.onStatusBadge,
          );
        },
        child: DrawIcon(StrokeIcons.errorOutline,
          size: scaleW(14),
          color: s.danger.color,
        ),
      ),
      TransferStatus.rejected => DrawIcon(StrokeIcons.block,
        size: scaleW(14),
        color: s.danger.color,
      ),
      TransferStatus.cancelled => DrawIcon(StrokeIcons.cancel,
        size: scaleW(14),
        color: s.border,
      ),
      TransferStatus.transferring => SizedBox(
        width: scaleW(14),
        height: scaleW(14),
        child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeThin, color: s.info.color),
      ),
      TransferStatus.queued => SizedBox(
        width: scaleW(14),
        height: scaleW(14),
        child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeThin, color: s.warning.color),
      ),
      _ => DrawIcon(StrokeIcons.schedule, size: scaleW(14), color: s.border),
    };
  }

  void _showContextMenu(BuildContext context) {
    final s = AppSemantic.of(context);
    final item = widget.item;
    final canCopy =
        item.status == TransferStatus.completed && item.transferType == TransferType.text;
    final canOpen =
        item.status == TransferStatus.completed &&
        item.filePath != null &&
        (Platform.isIOS || Platform.isAndroid);
    final canCancel = item.status == TransferStatus.transferring;
    final hasFile =
        item.filePath != null &&
        (item.status == TransferStatus.completed || item.status == TransferStatus.failed);

    // Pre-capture share rect while context is still attached and rendered
    final box = context.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.of(context).size;
    final Rect shareOrigin;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      final pos = box.localToGlobal(Offset.zero);
      shareOrigin = pos & box.size;
    } else {
      shareOrigin = Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height * 0.7),
        width: screenSize.width / 2,
        height: 50,
      );
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: s.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius20.topLeft),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: scaleW(36),
              height: AppTheme.metrics.kSpace4,
              margin: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: s.textDisabled,
                borderRadius: AppTheme.metrics.radius2,
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace8),
            if (canCopy)
              _menuItem(
                ctx,
                icon: StrokeIcons.copy,
                label: '复制文本',
                color: s.textSecondary,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: item.textContent ?? ''));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板'), duration: AppMotion.dwell),
                  );
                },
              ),
            if (canOpen)
              _menuItem(
                ctx,
                icon: StrokeIcons.iosShare,
                label: '用其他应用打开',
                color: s.textSecondary,
                onTap: () {
                  Navigator.of(ctx).pop();
                  SharePlus.instance.share(
                    ShareParams(
                      files: [XFile(item.filePath!)],
                      subject: item.fileName ?? '互传文件',
                      sharePositionOrigin: shareOrigin,
                    ),
                  );
                },
              ),
            if (canCancel)
              _menuItem(
                ctx,
                icon: StrokeIcons.cancel,
                label: '取消传输',
                color: s.warning.color,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onCancel();
                },
              ),
            if (hasFile)
              _menuItem(
                ctx,
                icon: StrokeIcons.deleteSweep,
                label: '删除记录和文件',
                color: s.danger.color,
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onDeleteWithFile();
                },
              ),
            _menuItem(
              ctx,
              icon: StrokeIcons.deleteOutline,
              label: '删除记录',
              color: s.danger.onContainer,
              onTap: () {
                Navigator.of(ctx).pop();
                widget.onDelete();
              },
            ),
            SizedBox(height: AppTheme.metrics.kSpace8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext ctx, {
    required StrokeIcon icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: DrawIcon(icon, color: color),
      title: Text(label, style: AppTextStyles.rowTitle(ctx).copyWith(color: color)),
      onTap: onTap,
    );
  }

  String _formatTime(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  StrokeIcon _typeIcon(TransferType type) {
    return switch (type) {
      TransferType.text => StrokeIcons.textSnippet,
      TransferType.image => StrokeIcons.image,
      TransferType.video => StrokeIcons.videoFile,
      TransferType.file => StrokeIcons.insertDriveFile,
    };
  }

  StrokeIcon _deviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('iphone') || lower.contains('ios')) return StrokeIcons.phoneIphone;
    if (lower.contains('ipad')) return StrokeIcons.tabletMac;
    if (lower.contains('mac')) return StrokeIcons.laptopMac;
    if (lower.contains('android')) return StrokeIcons.phoneAndroid;
    if (lower.contains('windows')) return StrokeIcons.desktopWindows;
    return StrokeIcons.devices;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 图片预览页（支持保存到相册）
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePreviewPage extends StatefulWidget {
  final String filePath;
  final String title;

  const _ImagePreviewPage({required this.filePath, required this.title});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  Future<void> _saveToGallery() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final permission = Platform.isIOS ? Permission.photosAddOnly : Permission.photos;
      var status = await permission.status;
      if (status.isDenied) status = await permission.request();
      if (!status.isGranted && !status.isLimited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('相册权限被拒绝')));
        }
        return;
      }
    }

    EasyLoading.show(status: '正在保存...');
    try {
      await Gal.putImage(widget.filePath);
      EasyLoading.showSuccess('已保存到相册');
    } catch (e) {
      EasyLoading.showError('保存失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 媒体预览页沿用系统级"黑底看图"惯例：Scaffold 黑底与图标白色属平台约定，
    // 弹层与其余色一律回到语义令牌
    final s = AppSemantic.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      // 舞台底与看图墨字都取自媒体令牌：值仍是恒黑/恒白，只是不再各写一份
      backgroundColor: s.mediaStage,
      body: Stack(
        children: [
          // 图片内容
          Center(child: InteractiveViewer(child: Image.file(File(widget.filePath)))),
          // 顶部操作栏（透明叠加）
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: Row(
              children: [
                IconButton(
                  color: s.onMedia,
                  icon: DrawIcon(StrokeIcons.arrowBackIosNew),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                IconButton(
                  color: s.onMedia,
                  icon: DrawIcon(StrokeIcons.moreHoriz),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: s.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius12.topLeft),
                      ),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: DrawIcon(StrokeIcons.download),
                              title: const Text('保存到相册'),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                await _saveToGallery();
                              },
                            ),
                            ListTile(
                              leading: DrawIcon(StrokeIcons.share),
                              title: const Text('分享到...'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                SharePlus.instance.share(
                                  ShareParams(
                                    files: [XFile(widget.filePath)],
                                    subject: widget.title,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 视频预览页（简单播放 + 分享）
// ─────────────────────────────────────────────────────────────────────────────

class _VideoPreviewPage extends StatefulWidget {
  final String filePath;
  final String title;

  const _VideoPreviewPage({required this.filePath, required this.title});

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.fromCenter(
            center: Offset(
              MediaQuery.of(context).size.width / 2,
              MediaQuery.of(context).size.height * 0.7,
            ),
            width: MediaQuery.of(context).size.width / 2,
            height: 50,
          );
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(widget.filePath)],
        subject: widget.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 同上：视频预览页保留黑底看图惯例，弹层回到语义令牌
    final s = AppSemantic.of(context);
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: s.mediaStage,
      body: Stack(
        children: [
          // 视频内容
          Center(
            child: _initialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const CircularProgressIndicator(),
          ),
          // 顶部操作栏（透明叠加）
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: Row(
              children: [
                IconButton(
                  color: s.onMedia,
                  icon: DrawIcon(StrokeIcons.arrowBackIosNew),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                IconButton(
                  color: s.onMedia,
                  icon: DrawIcon(StrokeIcons.moreHoriz),
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: s.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius12.topLeft),
                      ),
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: DrawIcon(StrokeIcons.download),
                              title: const Text('保存到相册'),
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                // 暂不支持视频直接保存，回退到分享
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(const SnackBar(content: Text('视频保存暂不支持，请使用分享')));
                              },
                            ),
                            ListTile(
                              leading: DrawIcon(StrokeIcons.share),
                              title: const Text('分享到...'),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _share();
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // 播放/暂停按钮（右下角）
          if (_initialized)
            Positioned(
              bottom: AppTheme.metrics.kSpace24 + MediaQuery.of(context).padding.bottom,
              right: AppTheme.metrics.kSpace16,
              child: FloatingActionButton(
                onPressed: () => setState(
                  () => _controller.value.isPlaying ? _controller.pause() : _controller.play(),
                ),
                child: DrawIcon(_controller.value.isPlaying ? StrokeIcons.pause : StrokeIcons.playArrow),
              ),
            ),
        ],
      ),
    );
  }
}

/// 视频缩略图占位（用 VideoPlayer 的第一帧作为缩略图）
class VideoPlayerWidgetThumbnail extends StatefulWidget {
  final String path;
  const VideoPlayerWidgetThumbnail({super.key, required this.path});

  @override
  State<VideoPlayerWidgetThumbnail> createState() => _VideoPlayerWidgetThumbnailState();
}

class _VideoPlayerWidgetThumbnailState extends State<VideoPlayerWidgetThumbnail> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
        // don't autoplay
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 首帧就绪前的媒体占位底：走下沉表面而非裸黑色
    if (!_ready) return Container(color: AppSemantic.of(context).surfaceSunken);
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _ctrl.value.size.width,
        height: _ctrl.value.size.height,
        child: VideoPlayer(_ctrl),
      ),
    );
  }
}
