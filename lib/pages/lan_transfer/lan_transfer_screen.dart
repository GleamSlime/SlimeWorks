import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/pages/lan_transfer/components/device_list.dart';
import 'package:slime_works/pages/lan_transfer/components/pending_requests.dart';
import 'package:slime_works/pages/lan_transfer/components/scanning_animation.dart';
import 'package:slime_works/view_models/lan_transfer_viewmodel.dart';

/// 局域网互传页面
class LanTransferScreen extends BasePage<LanTransferViewModel> {
  const LanTransferScreen({super.key});

  @override
  State<LanTransferScreen> createState() => _LanTransferScreenState();
}

class _LanTransferScreenState extends BasePageState<LanTransferViewModel, LanTransferScreen> {
  @override
  String get title => '互传';

  @override
  LanTransferViewModel createViewModel() => LanTransferViewModel();

  @override
  bool get showAppBar => false;

  @override
  bool get enableNetworkMonitoring => true;

  /// 防止「附近设备」弹层被多次创建
  bool _isDeviceSheetOpen = false;

  @override
  Future<void> onNetworkReconnected() async {
    await viewModel.startService();
    if (viewModel.isScanning.value) await viewModel.refreshDevices();
  }

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    final isDark = Get.isDarkMode;
    final m = AppTheme.metrics;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return ScreenChromeData(
      title: '互传',
      toolbarHeight: m.kSpace48,
      leading: Obx(() {
        final isRunning = viewModel.isServiceRunning.value;

        return GestureDetector(
          onTap: isRunning ? viewModel.stopService : viewModel.startService,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
            decoration: BoxDecoration(
              gradient: isRunning
                  ? null
                  : LinearGradient(
                      colors: [
                        Colors.green.withValues(alpha: 0.25),
                        Colors.green.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: isRunning ? Theme.of(context).colorScheme.error.withValues(alpha: 0.12) : null,
              borderRadius: m.radius8,
              border: Border.all(
                color: isRunning
                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.2)
                    : Colors.green.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: m.kSpace6,
                  height: m.kSpace6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRunning ? Colors.red : Colors.green,
                    boxShadow: [
                      BoxShadow(
                        color: (isRunning ? Colors.red : Colors.green).withValues(alpha: 0.4),
                        blurRadius: scaleW(4),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: m.kSpace6),
                Text(
                  isRunning ? '停止服务' : '启动服务',
                  style: TextStyle(
                    fontSize: m.fontSize11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: isRunning ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
      actions: [
        Obx(() {
          final isScanning = viewModel.isScanning.value;
          final deviceCount = viewModel.discoveredDevices.length;

          return GestureDetector(
            onTap: () => _showDeviceSheet(context),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.12),
                    primaryColor.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: m.radius8,
                border: Border.all(color: primaryColor.withValues(alpha: 0.15), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isScanning)
                    SizedBox(
                      width: m.kSpace10,
                      height: m.kSpace10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: primaryColor),
                    )
                  else
                    Icon(Icons.radar, size: m.iconSize14, color: primaryColor),
                  SizedBox(width: m.kSpace6),
                  Text(
                    deviceCount > 0 ? '$deviceCount 台设备' : '附近设备',
                    style: TextStyle(
                      fontSize: m.fontSize11,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                      color: isDark ? DarkColors.white80 : LightColors.black80,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  Icon(
                    Icons.expand_more,
                    size: m.iconSize14,
                    color: isDark ? DarkColors.white40 : LightColors.black40,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
      bottomBar: Obx(() {
        final isRunning = viewModel.isServiceRunning.value;
        final local = viewModel.localDevice.value;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
          margin: EdgeInsets.only(bottom: m.kSpace4),
          decoration: BoxDecoration(
            color: isDark ? DarkColors.background2 : LightColors.background2,
            borderRadius: m.radius8,
            border: Border.all(color: isDark ? DarkColors.white10 : LightColors.black10, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: m.kSpace8,
                height: m.kSpace8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? Colors.green : Colors.grey,
                  boxShadow: isRunning
                      ? [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.4),
                            blurRadius: scaleW(4),
                          ),
                        ]
                      : null,
                ),
              ),
              SizedBox(width: m.kSpace6),
              Text(
                local != null ? local.ipAddress : '未连接',
                style: TextStyle(
                  fontSize: m.fontSize11,
                  height: 1.4,
                  color: isDark ? DarkColors.white80 : LightColors.black80,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// 弹出「附近设备」浮层面板
  void _showDeviceSheet(BuildContext context) {
    // 防止重复弹出
    if (_isDeviceSheetOpen) return;
    _isDeviceSheetOpen = true;
    // 打开时自动开始搜索
    if (!viewModel.isScanning.value) {
      viewModel.startScanning();
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Get.isDarkMode ? DarkColors.background1 : LightColors.white100,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) => _DeviceSheetContent(
          viewModel: viewModel,
          scrollController: scrollController,
          onDeviceSelected: (device) {
            Navigator.of(ctx).pop();
            _navigateToChat(context, device: device);
          },
        ),
      ),
    ).whenComplete(() => _isDeviceSheetOpen = false);
  }

  /// 进入与指定对端设备的聊天页面（GoRouter TypedGoRoute push）
  void _navigateToChat(
    BuildContext context, {
    DeviceInfo? device,
    String? peerDeviceId,
    String? peerDeviceName,
  }) {
    final id = peerDeviceId ?? device?.deviceId ?? '';
    final name = peerDeviceName ?? device?.deviceName ?? '未知设备';
    // 通过 TypedGoRoute push，支持 iOS 左划返回手势
    LanChatRoute(peerId: id, peerName: name).push<void>(context);
  }

  /// 显示会话列表的长按/右键菜单
  void _showPeerContextMenu(
    BuildContext context, {
    required String deviceId,
    required String deviceName,
    required bool isPinned,
    Offset? tapPosition,
  }) {
    final isDark = Get.isDarkMode;
    // 桌面端（或提供了坐标时）使用弹出式菜单，移动端使用 BottomSheet
    final isDesktopLike =
        tapPosition != null ||
        (!GetPlatform.isMobile && !GetPlatform.isAndroid && !GetPlatform.isIOS);

    if (isDesktopLike && tapPosition != null) {
      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          tapPosition.dx,
          tapPosition.dy,
          tapPosition.dx + 1,
          tapPosition.dy + 1,
        ),
        items: [
          PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: AppTheme.metrics.iconSize16,
                  color: isDark ? DarkColors.primary : LightColors.primary,
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                Text(isPinned ? '取消置顶' : '置顶会话'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete_history',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: AppTheme.metrics.iconSize16, color: Colors.orange),
                SizedBox(width: AppTheme.metrics.kSpace8),
                const Text('删除历史', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete_all',
            child: Row(
              children: [
                Icon(
                  Icons.delete_sweep_outlined,
                  size: AppTheme.metrics.iconSize16,
                  color: Theme.of(context).colorScheme.error,
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                Text('删除会话及文件', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
        ],
      ).then((value) {
        if (value == 'pin') {
          if (isPinned) {
            viewModel.unpinPeer(deviceId);
          } else {
            viewModel.pinPeer(deviceId);
          }
        } else if (value == 'delete_history') {
          viewModel.deleteHistoryForPeer(deviceId);
        } else if (value == 'delete_all') {
          viewModel.deleteConversationForPeer(deviceId);
        }
      });
      return;
    }

    // 移动端 BottomSheet
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? DarkColors.background2 : LightColors.white100,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: AppTheme.metrics.kSpace4,
              margin: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: isDark ? DarkColors.white20 : LightColors.black20,
                borderRadius: AppTheme.metrics.radius2,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace16,
                vertical: AppTheme.metrics.kSpace12,
              ),
              child: Text(
                deviceName,
                style: TextStyle(
                  fontSize: AppTheme.metrics.fontSize13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Divider(height: 1, color: isDark ? DarkColors.white10 : LightColors.black10),
            // 置顶 / 取消置顶
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: isDark ? DarkColors.primary : LightColors.primary,
              ),
              title: Text(
                isPinned ? '取消置顶' : '置顶会话',
                style: TextStyle(color: isDark ? DarkColors.white80 : LightColors.black80),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                if (isPinned) {
                  viewModel.unpinPeer(deviceId);
                } else {
                  viewModel.pinPeer(deviceId);
                }
              },
            ),
            // 删除历史
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.orange),
              title: const Text('删除历史', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.of(ctx).pop();
                viewModel.deleteHistoryForPeer(deviceId);
              },
            ),
            // 删除会话及文件
            ListTile(
              leading: Icon(
                Icons.delete_sweep_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text('删除会话及文件', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.of(ctx).pop();
                viewModel.deleteConversationForPeer(deviceId);
              },
            ),
            SizedBox(height: AppTheme.metrics.kSpace8),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return Obx(() {
      // 有待处理请求时弹出 BottomSheet（防止重复弹出）
      final pending = viewModel.pendingRequests;
      if (pending.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPendingRequestSheet(context);
        });
      }

      return ScreenChrome(
        data: _buildScreenChromeData(context),
        child: _PeerListSection(
          viewModel: viewModel,
          onNavigateToChat: (id, name) =>
              _navigateToChat(context, peerDeviceId: id, peerDeviceName: name),
          onContextMenu: _showPeerContextMenu,
        ),
      );
    });
  }

  /// 展示收到传输请求的 BottomSheet
  void _showPendingRequestSheet(BuildContext context) {
    if (viewModel.pendingRequests.isEmpty) return;
    for (final req in viewModel.pendingRequests) {
      viewModel.markRequestHandled(req.transferId);
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Get.isDarkMode ? DarkColors.background1 : LightColors.white100,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PendingRequests(
        requests: viewModel.pendingRequests.toList(),
        onAccept: (id) {
          viewModel.acceptTransfer(id);
          if (viewModel.pendingRequests.isEmpty) Navigator.of(ctx).pop();
        },
        onReject: (id) {
          viewModel.rejectTransfer(id);
          if (viewModel.pendingRequests.isEmpty) Navigator.of(ctx).pop();
        },
        onTrust: viewModel.addTrustedDevice,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScreenChromeData 工具栏
// ─────────────────────────────────────────────────────────────────────────────

/// 工具栏：显示本机状态 + 设备数量徽章 + 服务开关
// ignore: unused_element
class _LanTransferToolbar extends StatelessWidget {
  final LanTransferViewModel viewModel;
  final VoidCallback onOpenDeviceSheet;

  const _LanTransferToolbar({required this.viewModel, required this.onOpenDeviceSheet});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Obx(() {
      final isRunning = viewModel.isServiceRunning.value;
      final isScanning = viewModel.isScanning.value;
      final local = viewModel.localDevice.value;
      final deviceCount = viewModel.discoveredDevices.length;

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 本机简要信息
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace10,
              vertical: AppTheme.metrics.kSpace4,
            ),
            decoration: BoxDecoration(
              color: isDark ? DarkColors.background2 : LightColors.background2,
              borderRadius: AppTheme.metrics.radius8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: AppTheme.metrics.kSpace8,
                  height: AppTheme.metrics.kSpace8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRunning ? Colors.green : Colors.grey,
                  ),
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Text(
                  local != null ? local.ipAddress : '未连接',
                  style: TextStyle(
                    fontSize: AppTheme.metrics.fontSize11,
                    height: 1.4,
                    color: isDark ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: AppTheme.metrics.kSpace8),

          // 附近设备 → 点击弹出设备浮层
          GestureDetector(
            onTap: onOpenDeviceSheet,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace10,
                vertical: AppTheme.metrics.kSpace4,
              ),
              decoration: BoxDecoration(
                color: isDark ? DarkColors.background2 : LightColors.background2,
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isScanning)
                    SizedBox(
                      width: AppTheme.metrics.kSpace10,
                      height: AppTheme.metrics.kSpace10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: isDark ? DarkColors.primary : LightColors.primary,
                      ),
                    )
                  else
                    Icon(
                      Icons.devices,
                      size: AppTheme.metrics.iconSize14,
                      color: isDark ? DarkColors.white80 : LightColors.black80,
                    ),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  Text(
                    deviceCount > 0 ? '$deviceCount 台设备' : '附近设备',
                    style: TextStyle(
                      fontSize: AppTheme.metrics.fontSize11,
                      height: 1.4,
                      color: isDark ? DarkColors.white80 : LightColors.black80,
                    ),
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  Icon(
                    Icons.expand_more,
                    size: AppTheme.metrics.iconSize14,
                    color: isDark ? DarkColors.white40 : LightColors.black40,
                  ),
                ],
              ),
            ),
          ),

          SizedBox(width: AppTheme.metrics.kSpace8),

          // 服务启停
          GestureDetector(
            onTap: isRunning ? viewModel.stopService : viewModel.startService,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace10,
                vertical: AppTheme.metrics.kSpace4,
              ),
              decoration: BoxDecoration(
                color: isRunning
                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: Text(
                isRunning ? '停止' : '启动',
                style: TextStyle(
                  fontSize: AppTheme.metrics.fontSize11,
                  height: 1.4,
                  color: isRunning ? Colors.red : Colors.green,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 附近设备浮层（BottomSheet 内容）
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceSheetContent extends StatelessWidget {
  final LanTransferViewModel viewModel;
  final ScrollController scrollController;
  final Function(DeviceInfo) onDeviceSelected;

  const _DeviceSheetContent({
    required this.viewModel,
    required this.scrollController,
    required this.onDeviceSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Obx(() {
      final isScanning = viewModel.isScanning.value;
      final devices = viewModel.discoveredDevices;
      // 订阅 trustedDevices 变化，确保信任状态更新后列表重建
      final _ = viewModel.trustedDevices.length;

      return Column(
        children: [
          // 拖拽手柄
          Center(
            child: Container(
              width: 36,
              height: AppTheme.metrics.kSpace4,
              margin: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: isDark ? DarkColors.white20 : LightColors.black20,
                borderRadius: AppTheme.metrics.radius2,
              ),
            ),
          ),

          // 标题行
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.metrics.kSpace16,
              AppTheme.metrics.kSpace12,
              AppTheme.metrics.kSpace12,
              AppTheme.metrics.kSpace8,
            ),
            child: Row(
              children: [
                Text(
                  '附近设备',
                  style: TextStyle(
                    fontSize: AppTheme.metrics.fontSize15,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (devices.isNotEmpty) ...[
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace8,
                      vertical: AppTheme.metrics.kSpace2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? DarkColors.white10 : LightColors.black10,
                      borderRadius: AppTheme.metrics.radius10,
                    ),
                    child: Text(
                      '${devices.length}',
                      style: TextStyle(fontSize: AppTheme.metrics.fontSize11, height: 1.4),
                    ),
                  ),
                ],
                const Spacer(),
                // 扫描控制按钮
                GestureDetector(
                  onTap: viewModel.toggleScanning,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace10,
                      vertical: AppTheme.metrics.kSpace8,
                    ),
                    decoration: BoxDecoration(
                      color: isScanning
                          ? Colors.orange.withValues(alpha: 0.1)
                          : (isDark ? DarkColors.primary : LightColors.primary).withValues(
                              alpha: 0.1,
                            ),
                      borderRadius: AppTheme.metrics.radius8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isScanning)
                          SizedBox(
                            width: scaleW(12),
                            height: scaleW(12),
                            child: const CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.orange,
                            ),
                          )
                        else
                          Icon(
                            Icons.radar,
                            size: scaleW(14),
                            color: isDark ? DarkColors.primary : LightColors.primary,
                          ),
                        SizedBox(width: AppTheme.metrics.kSpace4),
                        Text(
                          isScanning ? '搜索中' : '搜索',
                          style: TextStyle(
                            fontSize: AppTheme.metrics.fontSize11,
                            height: 1.4,
                            color: isScanning
                                ? Colors.orange
                                : (isDark ? DarkColors.primary : LightColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: isDark ? DarkColors.white10 : LightColors.black10),

          // 内容区
          Expanded(
            child: isScanning && devices.isEmpty
                ? const Center(child: ScanningAnimation())
                : devices.isNotEmpty
                ? ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => SizedBox(height: AppTheme.metrics.kSpace8),
                    itemBuilder: (ctx, i) {
                      final device = devices[i];
                      return DeviceList(
                        devices: [device],
                        selectedDevice: viewModel.selectedDevice.value,
                        onDeviceSelected: onDeviceSelected,
                        onDeviceTrust: viewModel.addTrustedDevice,
                        // 同步检查已加载的 trustedDevices，避免 FutureBuilder 每帧重建都先显示未信任
                        isTrustedDevice: (id) =>
                            viewModel.trustedDevices.any((t) => t.deviceId == id),
                      );
                    },
                  )
                : Center(
                    child: _EmptyDevicesPlaceholder(
                      isServiceRunning: viewModel.isServiceRunning.value,
                      onStartScan: viewModel.startScanning,
                    ),
                  ),
          ),
        ],
      );
    });
  }
}

/// 无设备时的占位图
class _EmptyDevicesPlaceholder extends StatelessWidget {
  final bool isServiceRunning;
  final VoidCallback onStartScan;

  const _EmptyDevicesPlaceholder({required this.isServiceRunning, required this.onStartScan});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final m = AppTheme.metrics;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: scaleW(80),
            height: scaleW(80),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.15),
                  primaryColor.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Icon(
              Icons.wifi_tethering,
              size: scaleW(36),
              color: primaryColor.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '发现附近设备',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: m.fontSize15, height: 1.5, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '搜索同一局域网下的设备，快速互传文件',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: m.fontSize13,
              height: 1.5,
              color: isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
          SizedBox(height: m.kSpace20),
          GestureDetector(
            onTap: onStartScan,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.2),
                    primaryColor.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: m.radius12,
                border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.1),
                    blurRadius: scaleW(16),
                    offset: Offset(0, scaleW(4)),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.radar, size: m.iconSize18, color: primaryColor),
                  SizedBox(width: m.kSpace8),
                  Text(
                    '开始搜索',
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 对端设备列表（主屏传输记录入口）
// ─────────────────────────────────────────────────────────────────────────────

class _PeerListSection extends StatelessWidget {
  final LanTransferViewModel viewModel;
  final void Function(String deviceId, String deviceName) onNavigateToChat;
  final void Function(
    BuildContext ctx, {
    required String deviceId,
    required String deviceName,
    required bool isPinned,
    Offset? tapPosition,
  })
  onContextMenu;

  const _PeerListSection({
    required this.viewModel,
    required this.onNavigateToChat,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;
    final m = AppTheme.metrics;

    return Obx(() {
      final peers = viewModel.transferHistoryPeers;

      if (peers.isEmpty) {
        return _buildEmptyState(isDark, m);
      }

      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
        itemCount: peers.length,
        itemBuilder: (ctx, i) {
          final peer = peers[i];
          return Padding(
            padding: EdgeInsets.only(bottom: m.kSpace8),
            child: _PeerListItem(
              deviceId: peer.deviceId,
              deviceName: peer.deviceName,
              lastItem: peer.lastItem,
              isPinned: peer.isPinned,
              isDark: isDark,
              onTap: () => onNavigateToChat(peer.deviceId, peer.deviceName),
              onContextMenu: ({Offset? tapPosition}) => onContextMenu(
                ctx,
                deviceId: peer.deviceId,
                deviceName: peer.deviceName,
                isPinned: peer.isPinned,
                tapPosition: tapPosition,
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildEmptyState(bool isDark, ThemeMetrics m) {
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: scaleW(100),
            height: scaleW(100),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.12),
                  primaryColor.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.08),
                  blurRadius: scaleW(30),
                  spreadRadius: scaleW(10),
                ),
              ],
            ),
            child: Icon(
              Icons.forum_outlined,
              size: scaleW(40),
              color: primaryColor.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: m.kSpace20),
          Text(
            '暂无会话',
            style: TextStyle(
              fontSize: m.fontSize15,
              height: 1.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: m.kSpace6),
          Text(
            '点击「附近设备」开始互传',
            style: TextStyle(
              fontSize: m.fontSize13,
              height: 1.5,
              color: isDark ? DarkColors.white80 : LightColors.black80,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个对端设备行
class _PeerListItem extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final dynamic lastItem; // TransferItem
  final bool isPinned;
  final bool isDark;
  final VoidCallback onTap;
  final void Function({Offset? tapPosition}) onContextMenu;

  const _PeerListItem({
    required this.deviceId,
    required this.deviceName,
    required this.lastItem,
    required this.isPinned,
    required this.isDark,
    required this.onTap,
    required this.onContextMenu,
  });

  @override
  State<_PeerListItem> createState() => _PeerListItemState();
}

class _PeerListItemState extends State<_PeerListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final m = AppTheme.metrics;
    final primaryColor = isDark ? DarkColors.primary : LightColors.primary;
    final String preview = _buildPreview();
    final String timeStr = _formatTime(widget.lastItem.createdAt as String);
    final deviceIcon = _deviceIcon(widget.deviceName);

    final List<Color> avatarColors = _avatarGradient(widget.deviceName);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: (details) => widget.onContextMenu(tapPosition: details.globalPosition),
        onLongPress: () => widget.onContextMenu(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: m.kSpace14, vertical: m.kSpace12),
          decoration: BoxDecoration(
            color: _isHovered
                ? (isDark ? DarkColors.background2 : LightColors.background2)
                : Colors.transparent,
            borderRadius: m.radius14,
            border: _isHovered
                ? Border.all(color: primaryColor.withValues(alpha: 0.08), width: 1)
                : null,
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.04),
                      blurRadius: scaleW(12),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: scaleW(48),
                height: scaleW(48),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: avatarColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: avatarColors.first.withValues(alpha: 0.25),
                      blurRadius: scaleW(8),
                      offset: Offset(0, scaleW(2)),
                    ),
                  ],
                ),
                child: Icon(
                  deviceIcon,
                  size: scaleW(22),
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              SizedBox(width: m.kSpace14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: scaleW(12),
                            color: primaryColor.withValues(alpha: 0.6),
                          ),
                          SizedBox(width: m.kSpace4),
                        ],
                        Expanded(
                          child: Text(
                            widget.deviceName,
                            style: TextStyle(
                              fontSize: m.fontSize13,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: m.kSpace8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: m.fontSize11,
                            height: 1.4,
                            color: isDark ? DarkColors.white40 : LightColors.black40,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace4),
                    Text(
                      preview,
                      style: TextStyle(
                        fontSize: m.fontSize11,
                        height: 1.4,
                        color: isDark ? DarkColors.white40 : LightColors.black40,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.kSpace8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isHovered ? 1.0 : 0.3,
                child: Icon(
                  Icons.chevron_right,
                  size: scaleW(18),
                  color: isDark ? DarkColors.white20 : LightColors.black20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _avatarGradient(String name) {
    final hash = name.hashCode.abs();
    final hue = (hash % 360).toDouble();
    return [
      HSLColor.fromAHSL(1.0, hue, 0.5, 0.45).toColor(),
      HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.6, 0.35).toColor(),
    ];
  }

  String _buildPreview() {
    final item = widget.lastItem;
    try {
      if (item.transferType == TransferType.text && item.textContent != null) {
        return item.textContent as String;
      }
      if (item.fileName != null) return '[文件] ${item.fileName}';
    } catch (_) {}
    return '';
  }

  String _formatTime(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (day == today) return hm;
    if (day == today.subtract(const Duration(days: 1))) return '昨天';
    return '${dt.month}/${dt.day}';
  }

  IconData _deviceIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('iphone') || lower.contains('ios')) return Icons.phone_iphone;
    if (lower.contains('ipad')) return Icons.tablet_mac;
    if (lower.contains('mac')) return Icons.laptop_mac;
    if (lower.contains('android')) return Icons.phone_android;
    if (lower.contains('windows')) return Icons.desktop_windows;
    return Icons.devices;
  }
}
