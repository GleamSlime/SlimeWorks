import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/pages/lan_transfer/components/transfer_actions.dart';
import 'package:slime_works/pages/lan_transfer/components/transfer_chat.dart';
import 'package:slime_works/view_models/lan_transfer_viewmodel.dart';

/// 与指定设备的局域网传输聊天页面。
/// 通过 [LanChatRoute] TypedGoRoute 进入，不再依赖 Navigator.push。
class LanChatScreen extends StatefulWidget {
  /// 对端设备 ID
  final String peerDeviceId;

  /// 对端设备名称（显示用）
  final String peerDeviceName;

  const LanChatScreen({super.key, required this.peerDeviceId, required this.peerDeviceName});

  @override
  State<LanChatScreen> createState() => _LanChatScreenState();
}

class _LanChatScreenState extends State<LanChatScreen> {
  /// 通过 GetX 获取已注册的 ViewModel 单例，无需由父路由传入
  LanTransferViewModel get _vm => Get.find<LanTransferViewModel>();

  @override
  void initState() {
    super.initState();
    // 进入聊天页时，如果对端在线则自动选中以便发送文件
    final device = _vm.discoveredDevices.firstWhereOrNull((d) => d.deviceId == widget.peerDeviceId);
    if (device != null) {
      _vm.selectDevice(device);
    }
  }

  @override
  void dispose() {
    _vm.unselectDevice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final bg = isDark ? DarkColors.background5 : LightColors.background5;
    return ScreenChrome(
      data: ScreenChromeData(
        titleWidget: _buildChatTitleWidget(context),
        toolbarHeight: AppTheme.metrics.kSpace48,
        leading: IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: scaleW(32), minHeight: scaleW(32)),
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: scaleW(18),
            color: isDark ? DarkColors.white80 : LightColors.black80,
          ),
          // GoRouter 返回，支持 iOS 左滑还原
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      child: Container(
        color: bg,
        child: Column(
          children: [
            Expanded(
              child: Obx(() {
                final localId = _vm.localDevice.value?.deviceId ?? '';
                final localName = _vm.localDevice.value?.deviceName ?? '我';
                final items = _vm.transferHistoryForPeer(widget.peerDeviceId);
                return TransferChatView(
                  items: items,
                  localDeviceId: localId,
                  localDeviceName: localName,
                  peerDeviceId: widget.peerDeviceId,
                  onCancel: (id) => _vm.cancelTransfer(id),
                  onDelete: (id) => _vm.deleteTransferItem(id),
                  onDeleteWithFile: (id) => _vm.deleteTransferItem(id, deleteFile: true),
                  onRetry: (id) => _vm.retryTransfer(id),
                );
              }),
            ),
            // 发送底栏：始终显示（即使对端离线也支持排队发送）
            TransferActions(
              viewModel: _vm,
              peerDeviceId: widget.peerDeviceId,
              peerDeviceName: widget.peerDeviceName,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTitleWidget(BuildContext context) {
    return Obx(() {
      final isOnline = _vm.discoveredDevices.any((d) => d.deviceId == widget.peerDeviceId);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.peerDeviceName,
            style: TextStyle(fontSize: 15.0, height: 1.5, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(width: AppTheme.metrics.kSpace8),
          // 在线状态指示点
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.green : Colors.grey,
            ),
          ),
        ],
      );
    });
  }
}
