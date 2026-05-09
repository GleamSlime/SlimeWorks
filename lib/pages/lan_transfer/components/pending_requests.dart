import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 待处理请求列表（用于 BottomSheet 展示）
class PendingRequests extends StatelessWidget {
  final List<TransferItem> requests;
  final Function(String) onAccept;
  final Function(String) onReject;
  final Function(DeviceInfo) onTrust;

  const PendingRequests({
    super.key,
    required this.requests,
    required this.onAccept,
    required this.onReject,
    required this.onTrust,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部拖拽指示条
        Center(
          child: Container(
            margin: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
            width: scaleW(36),
            height: scaleW(4),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.white20 : LightColors.black20,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.metrics.kSpace20,
            AppTheme.metrics.kSpace16,
            AppTheme.metrics.kSpace20,
            AppTheme.metrics.kSpace8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.download_outlined,
                color: isDark ? DarkColors.primary : LightColors.primary,
                size: scaleW(22),
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Expanded(
                child: Text(
                  '收到传输请求 (${requests.length})',
                  style: TextStyle(fontSize: 18.0, height: 1.4, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              AppTheme.metrics.kSpace16,
              0,
              AppTheme.metrics.kSpace16,
              AppTheme.metrics.kSpace24,
            ),
            itemCount: requests.length,
            separatorBuilder: (_, x) => SizedBox(height: AppTheme.metrics.kSpace8),
            itemBuilder: (context, index) {
              final request = requests[index];
              return _PendingRequestCard(
                request: request,
                isDark: isDark,
                onAccept: () => onAccept(request.transferId),
                onReject: () => onReject(request.transferId),
                onTrust: () {
                  final device = DeviceInfo(
                    deviceId: request.senderDeviceId,
                    deviceName: request.senderDeviceName,
                    deviceType: 'Unknown',
                    ipAddress: '',
                    port: 0,
                    discoveredAt: DateTime.now().toIso8601String(),
                    isOnline: true,
                  );
                  onTrust(device);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 待处理请求卡片
class _PendingRequestCard extends StatefulWidget {
  final TransferItem request;
  final bool isDark;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onTrust;

  const _PendingRequestCard({
    required this.request,
    required this.isDark,
    required this.onAccept,
    required this.onReject,
    required this.onTrust,
  });

  @override
  State<_PendingRequestCard> createState() => _PendingRequestCardState();
}

class _PendingRequestCardState extends State<_PendingRequestCard> {
  bool _trustDevice = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.isDark ? DarkColors.primary : LightColors.primary;

    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: widget.isDark ? DarkColors.background1 : LightColors.background1,
        border: Border.all(color: widget.isDark ? DarkColors.white10 : LightColors.black10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 发送信息头部
          Row(
            children: [
              Container(
                width: scaleW(40),
                height: scaleW(40),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getTypeIcon(widget.request.transferType),
                  size: scaleW(20),
                  color: primaryColor,
                ),
              ),
              SizedBox(width: AppTheme.metrics.kSpace12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.senderDeviceName,
                      style: TextStyle(fontSize: 13.0, height: 1.5, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace2),
                    Text(
                      '请求发送${_getTypeText(widget.request.transferType)}',
                      style: TextStyle(fontSize: 11.0, height: 1.4,
                        color: widget.isDark ? DarkColors.white80 : LightColors.black80,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 内容预览
          if (widget.request.fileName != null || widget.request.textContent != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace10),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace12,
                vertical: AppTheme.metrics.kSpace8,
              ),
              decoration: BoxDecoration(
                color: widget.isDark ? DarkColors.white10 : LightColors.black10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.request.fileName ?? widget.request.textContent ?? '',
                      style: TextStyle(fontSize: 11.0, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.request.fileSize != null) ...[
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    Text(
                      _formatFileSize(widget.request.fileSize!),
                      style: TextStyle(fontSize: 11.0, height: 1.4,
                        color: widget.isDark ? DarkColors.white80 : LightColors.black80,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          SizedBox(height: AppTheme.metrics.kSpace12),

          // 信任选项（精简样式）
          GestureDetector(
            onTap: () => setState(() => _trustDevice = !_trustDevice),
            child: Row(
              children: [
                SizedBox(
                  width: scaleW(20),
                  height: scaleW(20),
                  child: Checkbox(
                    value: _trustDevice,
                    onChanged: (v) => setState(() => _trustDevice = v ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                Text(
                  '信任此设备（下次自动接收）',
                  style: TextStyle(fontSize: 11.0, height: 1.4,
                    color: widget.isDark ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: AppTheme.metrics.kSpace12),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 0.8),
                    padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('拒绝'),
                ),
              ),
              SizedBox(width: AppTheme.metrics.kSpace8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    if (_trustDevice) widget.onTrust();
                    widget.onAccept();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('接受'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  String _getTypeText(TransferType type) {
    switch (type) {
      case TransferType.file:
        return '文件';
      case TransferType.text:
        return '文本';
      case TransferType.image:
        return '图片';
      case TransferType.video:
        return '视频';
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
