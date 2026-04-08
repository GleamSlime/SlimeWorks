import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/view_models/lan_transfer_viewmodel.dart';

/// 发送操作底栏（如果对端不在线则会进入离线排队）
class TransferActions extends StatefulWidget {
  final LanTransferViewModel viewModel;

  /// 对端设备 ID
  final String peerDeviceId;

  /// 对端设备名称（用于显示和离线入库）
  final String peerDeviceName;

  const TransferActions({
    super.key,
    required this.viewModel,
    required this.peerDeviceId,
    required this.peerDeviceName,
  });

  @override
  State<TransferActions> createState() => _TransferActionsState();
}

class _TransferActionsState extends State<TransferActions> {
  final TextEditingController _textController = TextEditingController();

  /// 文本框默认展开，避免用户需要额外点击才能输入
  bool _textFieldExpanded = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;
    final bg = isDark ? DarkColors.background1 : LightColors.background1;
    final border = isDark ? DarkColors.white10 : LightColors.black10;

    return Obx(() {
      final isOnline = widget.viewModel.discoveredDevices.any(
        (d) => d.deviceId == widget.peerDeviceId,
      );

      return Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border(top: BorderSide(color: border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 对端在线状态提示条
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.metrics.kSpace16,
                  AppTheme.metrics.kSpace12,
                  AppTheme.metrics.kSpace16,
                  0,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace4),
                    Text(
                      isOnline ? '已连接' : '不在线·发送后排队',
                      style: AppTextStyles.caption(
                        color: isOnline
                            ? Colors.green
                            : (isDark ? DarkColors.white40 : LightColors.black40),
                      ),
                    ),
                  ],
                ),
              ),

              // 文本输入区（带展开/收起）
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.metrics.kSpace16,
                  AppTheme.metrics.kSpace10,
                  AppTheme.metrics.kSpace16,
                  0,
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _textFieldExpanded
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textController,
                                textInputAction: TextInputAction.send,
                                maxLines: 1,
                                minLines: 1,
                                style: AppTextStyles.body2(
                                  color: isDark ? DarkColors.white100 : LightColors.black100,
                                ),
                                decoration: InputDecoration(
                                  hintText: '输入要发送的文本...',
                                  hintStyle: AppTextStyles.body2(
                                    color: isDark ? DarkColors.white40 : LightColors.black40,
                                  ),
                                  filled: true,
                                  fillColor: isDark ? DarkColors.white10 : LightColors.black10,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                                ),
                                onSubmitted: (_) => _sendText(),
                              ),
                            ),
                            SizedBox(width: AppTheme.metrics.kSpace8),
                            // 发送按鈕（单击发送）
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _textController,
                              builder: (_, value, x) {
                                final hasText = value.text.trim().isNotEmpty;
                                return GestureDetector(
                                  onTap: hasText ? _sendText : null,
                                  child: Container(
                                    padding: EdgeInsets.all(AppTheme.metrics.kSpace10),
                                    decoration: BoxDecoration(
                                      color: hasText
                                          ? primaryColor.withValues(alpha: 0.15)
                                          : (isDark ? DarkColors.white10 : LightColors.black10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.send_rounded,
                                      size: scaleW(20),
                                      color: hasText
                                          ? primaryColor
                                          : (isDark ? DarkColors.white40 : LightColors.black40),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),

              // 操作按鈕行
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace12,
                  vertical: AppTheme.metrics.kSpace10,
                ),
                child: Row(
                  children: [
                    // 文本展开/收起
                    _buildActionIcon(
                      icon: Icons.text_fields,
                      label: '文本',
                      isActive: _textFieldExpanded,
                      onPressed: () => setState(() => _textFieldExpanded = !_textFieldExpanded),
                      isDark: isDark,
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    _buildActionIcon(
                      icon: Icons.photo,
                      label: '图片',
                      onPressed: _pickAndSendImage,
                      isDark: isDark,
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    _buildActionIcon(
                      icon: Icons.video_library_outlined,
                      label: '视频',
                      onPressed: _pickAndSendVideo,
                      isDark: isDark,
                    ),
                    SizedBox(width: AppTheme.metrics.kSpace8),
                    _buildActionIcon(
                      icon: Icons.insert_drive_file_outlined,
                      label: '文件',
                      onPressed: _pickAndSendFile,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 构建操作图标按鈕
  Widget _buildActionIcon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isDark,
    bool isActive = false,
  }) {
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace10),
          decoration: BoxDecoration(
            color: isActive
                ? primaryColor.withValues(alpha: 0.12)
                : (isDark ? DarkColors.white10 : LightColors.black10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: scaleW(20),
                color: isActive
                    ? primaryColor
                    : (isDark ? DarkColors.white80 : LightColors.black80),
              ),
              SizedBox(height: AppTheme.metrics.kSpace4),
              Text(
                label,
                style: AppTextStyles.caption(
                  color: isActive
                      ? primaryColor
                      : (isDark ? DarkColors.white80 : LightColors.black80),
                ),
                textScaler: const TextScaler.linear(0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFileToDevice(
        widget.peerDeviceId,
        widget.peerDeviceName,
        result.files.single.path!,
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFileToDevice(
        widget.peerDeviceId,
        widget.peerDeviceName,
        result.files.single.path!,
      );
    }
  }

  Future<void> _pickAndSendVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      await widget.viewModel.sendFileToDevice(
        widget.peerDeviceId,
        widget.peerDeviceName,
        result.files.single.path!,
      );
    }
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await widget.viewModel.sendTextToDevice(widget.peerDeviceId, widget.peerDeviceName, text);
    if (!mounted) return;
    _textController.clear();
  }
}
