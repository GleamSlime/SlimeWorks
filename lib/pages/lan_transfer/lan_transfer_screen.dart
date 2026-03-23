import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/lan_transfer/components/device_list.dart';
import 'package:slime_works/pages/lan_transfer/components/transfer_actions.dart';
import 'package:slime_works/pages/lan_transfer/components/transfer_history.dart';
import 'package:slime_works/pages/lan_transfer/components/pending_requests.dart';
import 'package:slime_works/pages/lan_transfer/components/scanning_animation.dart';
import 'package:slime_works/view_models/lan_transfer_viewmodel.dart';

/// 局域网传输页面
class LanTransferScreen extends BasePage<LanTransferViewModel> {
  const LanTransferScreen({super.key});

  @override
  State<LanTransferScreen> createState() => _LanTransferScreenState();
}

class _LanTransferScreenState extends BasePageState<LanTransferViewModel, LanTransferScreen> {
  @override
  String get title => '局域网传输';

  @override
  LanTransferViewModel createViewModel() => LanTransferViewModel();

  @override
  bool get enableNetworkMonitoring => true;

  @override
  Future<void> onNetworkReconnected() async {
    await viewModel.startService();
    await viewModel.refreshDevices();
  }

  @override
  Widget buildContent(BuildContext context) {
    return Obx(() {
      // 待处理的请求弹窗
      if (viewModel.pendingRequests.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPendingRequestDialog(context);
        });
      }

      return SingleChildScrollView(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和状态
            _buildHeader(context),

            SizedBox(height: AppTheme.metrics.kSpace24),

            // 扫描动画和设备列表
            _buildDeviceSection(context),

            SizedBox(height: AppTheme.metrics.kSpace24),

            // 传输操作区域（选中设备后显示）
            if (viewModel.selectedDevice.value != null) ...[
              TransferActions(viewModel: viewModel),
              SizedBox(height: AppTheme.metrics.kSpace24),
            ],

            // 传输历史
            _buildTransferHistorySection(context),
          ],
        ),
      );
    });
  }

  /// 构建页面头部
  Widget _buildHeader(BuildContext context) {
    final isDark = Get.isDarkMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '局域网传输',
              style: AppTextStyles.h4(color: isDark ? DarkColors.white100 : LightColors.black100),
            ),
            SizedBox(height: AppTheme.metrics.kSpace8),
            Obx(() {
              final localDevice = viewModel.localDevice.value;
              if (localDevice == null) {
                return Text(
                  '正在初始化...',
                  style: AppTextStyles.body2(
                    color: isDark ? DarkColors.white80 : LightColors.black80,
                  ),
                );
              }

              return Text(
                '本机: ${localDevice.deviceName} (${localDevice.deviceType})',
                style: AppTextStyles.body2(
                  color: isDark ? DarkColors.white80 : LightColors.black80,
                ),
              );
            }),
          ],
        ),

        // 服务控制按钮
        Obx(() {
          final isRunning = viewModel.isServiceRunning.value;
          return ElevatedButton.icon(
            onPressed: isRunning ? viewModel.stopService : viewModel.startService,
            icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
            label: Text(isRunning ? '停止服务' : '启动服务'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRunning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
          );
        }),
      ],
    );
  }

  /// 构建设备区域
  Widget _buildDeviceSection(BuildContext context) {
    return Obx(() {
      final isScanning = viewModel.isScanning.value;
      final devices = viewModel.discoveredDevices;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('发现的设备 (${devices.length})', style: AppTextStyles.h5()),
              if (isScanning)
                TextButton.icon(
                  onPressed: viewModel.stopScanning,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止扫描'),
                )
              else
                TextButton.icon(
                  onPressed: viewModel.startScanning,
                  icon: const Icon(Icons.search),
                  label: const Text('开始扫描'),
                ),
            ],
          ),

          SizedBox(height: AppTheme.metrics.kSpace16),

          // 扫描动画
          if (isScanning && devices.isEmpty)
            const ScanningAnimation()
          // 设备列表
          else if (devices.isNotEmpty)
            DeviceList(
              devices: devices,
              selectedDevice: viewModel.selectedDevice.value,
              onDeviceSelected: viewModel.selectDevice,
              onDeviceTrust: viewModel.addTrustedDevice,
              isTrustedDevice: viewModel.isTrustedDevice,
            )
          else
            Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
                child: Text(
                  '未发现设备\n请确保设备在同一局域网内',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body2(
                    color: Get.isDarkMode ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  /// 构建传输历史区域
  Widget _buildTransferHistorySection(BuildContext context) {
    return Obx(() {
      final history = viewModel.transferHistory;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('传输历史 (${history.length})', style: AppTextStyles.h5()),

          SizedBox(height: AppTheme.metrics.kSpace16),

          if (history.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.metrics.kSpace32),
                child: Text(
                  '暂无传输记录',
                  style: AppTextStyles.body2(
                    color: Get.isDarkMode ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ),
            )
          else
            TransferHistory(items: history, onCancel: viewModel.cancelTransfer),
        ],
      );
    });
  }

  /// 显示待处理请求对话框
  void _showPendingRequestDialog(BuildContext context) {
    if (viewModel.pendingRequests.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('收到传输请求'),
        content: SizedBox(
          width: double.maxFinite,
          child: PendingRequests(
            requests: viewModel.pendingRequests,
            onAccept: viewModel.acceptTransfer,
            onReject: viewModel.rejectTransfer,
            onTrust: viewModel.addTrustedDevice,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }
}
