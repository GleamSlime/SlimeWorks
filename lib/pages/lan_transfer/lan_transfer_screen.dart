import 'dart:math';
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
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

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

  /// 防止「授权码」对话框被多次创建
  bool _isAccessCodeSheetOpen = false;

  /// 网络重连：保持手动启停语义，仅当服务已在运行时刷新设备
  @override
  Future<void> onNetworkReconnected() async {
    if (viewModel.isServiceRunning.value) {
      await viewModel.refreshDevices();
    }
  }

  ScreenChromeData _buildScreenChromeData(BuildContext context) {
    // 取色只走语义层：isDark 三元分支与裸 Colors.* 一律收敛到 AppSemantic
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final primaryColor = s.accent;

    return ScreenChromeData(
      title: '互传',
      toolbarHeight: m.kSpace48,
      toolbar: Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Obx(() {
            final isRunning = viewModel.isServiceRunning.value;

            return GestureDetector(
              onTap: isRunning ? viewModel.stopService : viewModel.startService,
              child: AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.decelerate,
                padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace6),
                decoration: BoxDecoration(
                  gradient: isRunning
                      ? null
                      : LinearGradient(
                          colors: [
                            s.success.color.withValues(alpha: 0.25),
                            s.success.color.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: isRunning ? s.danger.container : null,
                  borderRadius: m.radius8,
                  border: Border.all(
                    color: isRunning ? s.danger.containerBorder : s.success.containerBorder,
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
                        color: isRunning ? s.danger.color : s.success.color,
                        boxShadow: [
                          BoxShadow(
                            color: (isRunning ? s.danger.color : s.success.color).withValues(alpha: 0.4),
                            blurRadius: scaleW(4),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: m.kSpace6),
                    Text(
                      isRunning ? '停止服务' : '启动服务',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize11,
                        height: 1.4,
                        weight: FontWeight.w600,
                        color: isRunning ? s.danger.onContainer : s.success.onContainer,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
      actions: [
        // 接入授权码配置
        GestureDetector(
          onTap: _showAccessCodeDialog,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
            decoration: BoxDecoration(
              color: s.surfaceSunken,
              borderRadius: m.radius8,
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DrawIcon(StrokeIcons.key,
                  size: m.iconSize14,
                  color: primaryColor.withValues(alpha: 0.8),
                ),
                SizedBox(width: m.kSpace4),
                Text(
                  '授权码',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize11,
                    height: 1.4,
                    color: s.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                border: Border.all(color: primaryColor.withValues(alpha: 0.15), width: AppTheme.metrics.strokeHairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isScanning)
                    SizedBox(
                      width: m.kSpace10,
                      height: m.kSpace10,
                      child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeThin, color: primaryColor),
                    )
                  else
                    DrawIcon(StrokeIcons.radar, size: m.iconSize14, color: primaryColor),
                  SizedBox(width: m.kSpace6),
                  Text(
                    deviceCount > 0 ? '$deviceCount 台设备' : '附近设备',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize11,
                      height: 1.4,
                      weight: FontWeight.w500,
                      color: s.textSecondary,
                    ),
                  ),
                  SizedBox(width: m.kSpace4),
                  DrawIcon(StrokeIcons.expandMore,
                    size: m.iconSize14,
                    color: s.textTertiary,
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
            color: s.surfaceSunken,
            borderRadius: m.radius8,
            border: Border.all(color: s.border, width: AppTheme.metrics.strokeHairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: m.kSpace8,
                height: m.kSpace8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? s.success.color : s.neutral.color,
                  boxShadow: isRunning
                      ? [
                          BoxShadow(
                            color: s.success.color.withValues(alpha: 0.4),
                            blurRadius: scaleW(4),
                          ),
                        ]
                      : null,
                ),
              ),
              SizedBox(width: m.kSpace6),
              Text(
                local != null ? local.ipAddress : '未连接',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize11,
                  height: 1.4,
                  color: s.textSecondary,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  /// 弹出接入授权码配置对话框
  Future<void> _showAccessCodeDialog() async {
    if (_isAccessCodeSheetOpen) return;
    _isAccessCodeSheetOpen = true;
    // 读取当前授权码
    final current = await viewModel.getAccessCode();
    if (!mounted) return;
    final TextEditingController controller = TextEditingController(text: current ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final s = AppSemantic.of(ctx);
        final m = AppTheme.metrics;
        return AlertDialog(
          backgroundColor: s.surface,
          shape: RoundedRectangleBorder(borderRadius: m.radius16),
          title: const Text('接入授权码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '其他设备需输入与本机相同的授权码才能向你发起传输；信任设备不受限制。',
                style: AppTextStyles.role(
                  ctx,
                  fontSize: m.fontSize12,
                  height: 1.5,
                  color: s.textSecondary,
                ),
              ),
              SizedBox(height: m.kSpace16),
              AppTextField(
                controller: controller,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: '授权码',
                  hintText: '留空则关闭授权校验',
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: m.radius10),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('disable'),
              child: const Text('关闭校验'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('regenerate'),
              child: const Text('随机生成'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    _isAccessCodeSheetOpen = false;
    if (result == null || !mounted) return;

    if (result == 'disable') {
      await viewModel.setAccessCode(null);
      viewModel.showSuccess('已关闭接入授权校验');
    } else if (result == 'regenerate') {
      // 复用服务层的随机生成逻辑
      final newCode = _generateAccessCode();
      await viewModel.setAccessCode(newCode);
      viewModel.showSuccess('已生成新的授权码：$newCode');
    } else {
      await viewModel.setAccessCode(result);
      viewModel.showSuccess('接入授权码已更新');
    }
  }

  /// 生成 6 位可读随机授权码（与服务层一致）
  String _generateAccessCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
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
      backgroundColor: AppSemantic.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius20.topLeft),
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
    final s = AppSemantic.of(context);
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
                DrawIcon(
                  isPinned ? StrokeIcons.pushPin : StrokeIcons.pushPin,
                  size: AppTheme.metrics.iconSize16,
                  color: s.accent,
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
                DrawIcon(StrokeIcons.deleteOutline, size: AppTheme.metrics.iconSize16, color: s.warning.color),
                SizedBox(width: AppTheme.metrics.kSpace8),
                Text('删除历史', style: AppTextStyles.rowTitle(context).copyWith(color: s.warning.onContainer)),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete_all',
            child: Row(
              children: [
                DrawIcon(StrokeIcons.deleteSweep,
                  size: AppTheme.metrics.iconSize16,
                  color: s.danger.color,
                ),
                SizedBox(width: AppTheme.metrics.kSpace8),
                Text('删除会话及文件', style: AppTextStyles.rowTitle(context).copyWith(color: s.danger.onContainer)),
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
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace16,
                vertical: AppTheme.metrics.kSpace12,
              ),
              child: Text(deviceName, style: AppTextStyles.cardTitle(context)),
            ),
            Divider(height: 1, color: s.hairline),
            // 置顶 / 取消置顶
            ListTile(
              leading: DrawIcon(
                isPinned ? StrokeIcons.pushPin : StrokeIcons.pushPin,
                color: s.accent,
              ),
              title: Text(
                isPinned ? '取消置顶' : '置顶会话',
                style: AppTextStyles.rowTitle(context).copyWith(color: s.textSecondary),
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
              leading: DrawIcon(StrokeIcons.deleteOutline, color: s.warning.color),
              title: Text('删除历史', style: AppTextStyles.rowTitle(context).copyWith(color: s.warning.onContainer)),
              onTap: () {
                Navigator.of(ctx).pop();
                viewModel.deleteHistoryForPeer(deviceId);
              },
            ),
            // 删除会话及文件
            ListTile(
              leading: DrawIcon(StrokeIcons.deleteSweep,
                color: s.danger.color,
              ),
              title: Text('删除会话及文件', style: AppTextStyles.rowTitle(context).copyWith(color: s.danger.onContainer)),
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
      backgroundColor: AppSemantic.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppTheme.metrics.radius20.topLeft),
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
    final s = AppSemantic.of(context);

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
              color: s.surfaceSunken,
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
                    color: isRunning ? s.success.color : s.neutral.color,
                  ),
                ),
                SizedBox(width: AppTheme.metrics.kSpace4),
                Text(
                  local != null ? local.ipAddress : '未连接',
                  style: AppTextStyles.role(
                    context,
                    fontSize: AppTheme.metrics.fontSize11,
                    height: 1.4,
                    color: s.textSecondary,
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
                color: s.surfaceSunken,
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
                        strokeWidth: AppTheme.metrics.strokeThin,
                        color: s.accent,
                      ),
                    )
                  else
                    DrawIcon(StrokeIcons.devices,
                      size: AppTheme.metrics.iconSize14,
                      color: s.textSecondary,
                    ),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  Text(
                    deviceCount > 0 ? '$deviceCount 台设备' : '附近设备',
                    style: AppTextStyles.role(
                      context,
                      fontSize: AppTheme.metrics.fontSize11,
                      height: 1.4,
                      color: s.textSecondary,
                    ),
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace4),
                  DrawIcon(StrokeIcons.expandMore,
                    size: AppTheme.metrics.iconSize14,
                    color: s.textTertiary,
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
                color: isRunning ? s.danger.container : s.success.container,
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: Text(
                isRunning ? '停止' : '启动',
                style: AppTextStyles.role(
                  context,
                  fontSize: AppTheme.metrics.fontSize11,
                  height: 1.4,
                  color: isRunning ? s.danger.onContainer : s.success.onContainer,
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
    final s = AppSemantic.of(context);

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
              width: scaleW(36),
              height: AppTheme.metrics.kSpace4,
              margin: EdgeInsets.only(top: AppTheme.metrics.kSpace12),
              decoration: BoxDecoration(
                color: s.textDisabled,
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
                Text('附近设备', style: AppTextStyles.sectionTitle(context)),
                if (devices.isNotEmpty) ...[
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.metrics.kSpace8,
                      vertical: AppTheme.metrics.kSpace2,
                    ),
                    decoration: BoxDecoration(
                      color: s.surfaceSunken,
                      borderRadius: AppTheme.metrics.radius10,
                    ),
                    child: Text(
                      '${devices.length}',
                      style: AppTextStyles.role(
                        context,
                        fontSize: AppTheme.metrics.fontSize11,
                        height: 1.4,
                        color: s.textPrimary,
                      ),
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
                      color: isScanning ? s.warning.container : s.accentContainer,
                      borderRadius: AppTheme.metrics.radius8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isScanning)
                          SizedBox(
                            width: scaleW(12),
                            height: scaleW(12),
                            child: CircularProgressIndicator(
                              strokeWidth: AppTheme.metrics.strokeThin,
                              color: s.warning.color,
                            ),
                          )
                        else
                          DrawIcon(StrokeIcons.radar,
                            size: scaleW(14),
                            color: s.accent,
                          ),
                        SizedBox(width: AppTheme.metrics.kSpace4),
                        Text(
                          isScanning ? '搜索中' : '搜索',
                          style: AppTextStyles.role(
                            context,
                            fontSize: AppTheme.metrics.fontSize11,
                            height: 1.4,
                            color: isScanning ? s.warning.onContainer : s.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: s.hairline),

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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final primaryColor = s.accent;

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
            child: DrawIcon(StrokeIcons.wifiTethering,
              size: scaleW(36),
              color: primaryColor.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: m.kSpace16),
          Text(
            '发现附近设备',
            textAlign: TextAlign.center,
            style: AppTextStyles.sectionTitle(context),
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '搜索同一局域网下的设备，快速互传文件',
            textAlign: TextAlign.center,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize13,
              height: 1.5,
              color: s.textSecondary,
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
                border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: AppTheme.metrics.strokeHairline),
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
                  DrawIcon(StrokeIcons.radar, size: m.iconSize18, color: primaryColor),
                  SizedBox(width: m.kSpace8),
                  Text(
                    '开始搜索',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize13,
                      height: 1.4,
                      weight: FontWeight.w600,
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
    final m = AppTheme.metrics;

    return Obx(() {
      final peers = viewModel.transferHistoryPeers;

      if (peers.isEmpty) {
        return _buildEmptyState(context, m);
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

  Widget _buildEmptyState(BuildContext context, ThemeMetrics m) {
    final s = AppSemantic.of(context);
    final primaryColor = s.accent;

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
            child: DrawIcon(StrokeIcons.forum,
              size: scaleW(40),
              color: primaryColor.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(height: m.kSpace20),
          Text(
            '暂无会话',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize15,
              height: 1.5,
              weight: FontWeight.w600,
              letterSpacing: 0.5,
              color: s.textPrimary,
            ),
          ),
          SizedBox(height: m.kSpace6),
          Text(
            '点击「附近设备」开始互传',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize13,
              height: 1.5,
              color: s.textSecondary,
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
  final VoidCallback onTap;
  final void Function({Offset? tapPosition}) onContextMenu;

  const _PeerListItem({
    required this.deviceId,
    required this.deviceName,
    required this.lastItem,
    required this.isPinned,
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
    // 取色只走语义层；悬停底是"状态层"，用水洗而不是实心表面（§2.2）
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final primaryColor = s.accent;
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
          duration: AppMotion.fast,
          curve: AppMotion.decelerate,
          padding: EdgeInsets.symmetric(horizontal: m.kSpace14, vertical: m.kSpace12),
          decoration: BoxDecoration(
            color: _isHovered ? s.surfaceHover : Colors.transparent,
            borderRadius: m.radius14,
            border: _isHovered
                ? Border.all(color: primaryColor.withValues(alpha: 0.08), width: AppTheme.metrics.strokeHairline)
                : null,
            boxShadow: _isHovered ? s.elevation(Elevation.raised) : null,
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
                // 身份色头像底深浅两档都是中低亮度，图标固定用不透明的 on-dark 白，
                // 换成 accentOn 会在暗色档变成深墨、在头像上消失
                // 令牌取 onStatusBadge：它才是"实心色块上恒白墨"这一职（头像不是 art，别拿 onMedia 顶）
                child: DrawIcon(deviceIcon, size: scaleW(22), color: s.onStatusBadge.withValues(alpha: 0.9)),
              ),
              SizedBox(width: m.kSpace14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.isPinned) ...[
                          DrawIcon(StrokeIcons.pushPin,
                            size: scaleW(12),
                            color: primaryColor.withValues(alpha: 0.6),
                          ),
                          SizedBox(width: m.kSpace4),
                        ],
                        Expanded(
                          child: Text(
                            widget.deviceName,
                            style: AppTextStyles.cardTitle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: m.kSpace8),
                        Text(
                          timeStr,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize11,
                            height: 1.4,
                            color: s.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: m.kSpace4),
                    Text(
                      preview,
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize11,
                        height: 1.4,
                        color: s.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: m.kSpace8),
              AnimatedOpacity(
                duration: AppMotion.fast,
                opacity: _isHovered ? 1.0 : 0.3,
                child: DrawIcon(StrokeIcons.chevronRight,
                  size: scaleW(18),
                  color: s.textDisabled,
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
