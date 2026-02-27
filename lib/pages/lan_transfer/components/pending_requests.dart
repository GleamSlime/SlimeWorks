import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 待处理请求组件
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

    return ListView.separated(
      shrinkWrap: true,
      itemCount: requests.length,
      separatorBuilder: (context, index) => SizedBox(height: AppTheme.metrics.kSpace12),
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
    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: widget.isDark ? DarkColors.background1 : LightColors.background1,
        border: Border.all(color: widget.isDark ? DarkColors.white10 : LightColors.black10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getTypeIcon(widget.request.transferType),
                size: scaleW(32),
                color: widget.isDark ? DarkColors.primary : LightColors.primary,
              ),

              SizedBox(width: AppTheme.metrics.kSpace12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.senderDeviceName,
                      style: AppTextStyles.body1(fontWeight: AppFontWeights.semiBold),
                    ),
                    SizedBox(height: AppTheme.metrics.kSpace4),
                    Text(
                      '请求发送${_getTypeText(widget.request.transferType)}',
                      style: AppTextStyles.caption(
                        color: widget.isDark ? DarkColors.white80 : LightColors.black80,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: AppTheme.metrics.kSpace12),

          // 内容信息
          if (widget.request.fileName != null)
            Text('文件: ${widget.request.fileName}', style: AppTextStyles.body2())
          else if (widget.request.textContent != null)
            Container(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
              decoration: BoxDecoration(
                color: widget.isDark ? DarkColors.white20 : LightColors.black20,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.request.textContent!,
                style: AppTextStyles.body2(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // 文件大小
          if (widget.request.fileSize != null) ...[
            SizedBox(height: AppTheme.metrics.kSpace4),
            Text(
              '大小: ${_formatFileSize(widget.request.fileSize!)}',
              style: AppTextStyles.caption(
                color: widget.isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ],

          SizedBox(height: AppTheme.metrics.kSpace16),

          // 信任选项
          CheckboxListTile(
            value: _trustDevice,
            onChanged: (value) => setState(() => _trustDevice = value ?? false),
            title: Text('信任此设备', style: AppTextStyles.body2()),
            subtitle: Text(
              '自动接受来自此设备的传输',
              style: AppTextStyles.caption(
                color: widget.isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          SizedBox(height: AppTheme.metrics.kSpace12),

          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  widget.onReject();
                },
                child: const Text('拒绝'),
              ),

              SizedBox(width: AppTheme.metrics.kSpace8),

              ElevatedButton(
                onPressed: () {
                  if (_trustDevice) {
                    widget.onTrust();
                  }
                  widget.onAccept();
                },
                child: const Text('接受'),
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
        return Icons.insert_drive_file;
      case TransferType.text:
        return Icons.text_fields;
      case TransferType.image:
        return Icons.image;
      case TransferType.video:
        return Icons.video_library;
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
