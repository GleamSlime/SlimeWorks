import 'dart:async';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';

/// 局域网传输页面 ViewModel
class LanTransferViewModel extends BaseViewModel {
  final LanTransferService _service = GetIt.instance.get<LanTransferService>();

  // 服务状态
  final RxBool isServiceRunning = false.obs;
  final RxBool isScanning = false.obs;

  // 设备列表
  final RxList<DeviceInfo> discoveredDevices = <DeviceInfo>[].obs;
  final Rx<DeviceInfo?> selectedDevice = Rx<DeviceInfo?>(null);
  final Rx<DeviceInfo?> localDevice = Rx<DeviceInfo?>(null);

  // 传输历史
  final RxList<TransferItem> transferHistory = <TransferItem>[].obs;
  final RxList<TransferItem> pendingRequests = <TransferItem>[].obs;

  // 信任设备
  final RxList<TrustedDevice> trustedDevices = <TrustedDevice>[].obs;

  // 定时器
  Timer? _refreshTimer;

  @override
  Future<void> onInitAsync() async {
    await super.onInitAsync();
    await startService();
  }

  /// 启动服务
  Future<void> startService() async {
    try {
      setLoading(true);

      if (!_service.isRunning) {
        await _service.startService();
      }

      isServiceRunning.value = true;

      // 获取本机设备信息
      localDevice.value = await _service.getLocalDevice();

      // 开始扫描
      await startScanning();

      // 加载信任设备
      await loadTrustedDevices();

      // 加载传输历史
      await loadTransferHistory();

      // 启动定时刷新
      _startAutoRefresh();
    } catch (e) {
      handleError(e, '启动服务失败');
    } finally {
      setLoading(false);
    }
  }

  /// 停止服务
  Future<void> stopService() async {
    try {
      _stopAutoRefresh();
      isScanning.value = false;
      await _service.stopService();
      isServiceRunning.value = false;
      discoveredDevices.clear();
    } catch (e) {
      handleError(e, '停止服务失败');
    }
  }

  /// 开始扫描设备
  Future<void> startScanning() async {
    try {
      isScanning.value = true;
      await refreshDevices();
    } catch (e) {
      handleError(e, '扫描设备失败');
    }
  }

  /// 停止扫描
  void stopScanning() {
    isScanning.value = false;
  }

  /// 刷新设备列表
  Future<void> refreshDevices() async {
    try {
      final devices = await _service.getDevices();
      discoveredDevices.value = devices;
    } catch (e) {
      handleError(e, '刷新设备列表失败');
    }
  }

  /// 选择目标设备
  void selectDevice(DeviceInfo device) {
    selectedDevice.value = device;
  }

  /// 取消选择
  void unselectDevice() {
    selectedDevice.value = null;
  }

  /// 发送文本消息
  Future<void> sendText(String text) async {
    final device = selectedDevice.value;
    if (device == null) {
      showError('请先选择目标设备');
      return;
    }

    try {
      setLoading(true);

      await _service.sendText(
        targetIp: device.ipAddress,
        targetPort: device.port,
        targetDeviceId: device.deviceId,
        text: text,
      );

      showSuccess('文本发送成功');

      // 刷新传输历史
      await loadTransferHistory();
    } catch (e) {
      handleError(e, '发送文本失败');
    } finally {
      setLoading(false);
    }
  }

  /// 发送文件
  Future<void> sendFile(String filePath) async {
    final device = selectedDevice.value;
    if (device == null) {
      showError('请先选择目标设备');
      return;
    }

    try {
      setLoading(true);

      await _service.sendFile(
        targetIp: device.ipAddress,
        targetPort: device.port,
        targetDeviceId: device.deviceId,
        filePath: filePath,
      );

      showSuccess('文件发送成功');

      // 刷新传输历史
      await loadTransferHistory();
    } catch (e) {
      handleError(e, '发送文件失败');
    } finally {
      setLoading(false);
    }
  }

  /// 接受传输
  Future<void> acceptTransfer(String transferId) async {
    try {
      await _service.acceptTransfer(transferId);
      await loadTransferHistory();
      await loadPendingRequests();
      showSuccess('已接受传输');
    } catch (e) {
      handleError(e, '接受传输失败');
    }
  }

  /// 拒绝传输
  Future<void> rejectTransfer(String transferId) async {
    try {
      await _service.rejectTransfer(transferId);
      await loadTransferHistory();
      await loadPendingRequests();
      showSuccess('已拒绝传输');
    } catch (e) {
      handleError(e, '拒绝传输失败');
    }
  }

  /// 取消传输
  Future<void> cancelTransfer(String transferId) async {
    try {
      await _service.cancelTransfer(transferId);
      await loadTransferHistory();
      showSuccess('已取消传输');
    } catch (e) {
      handleError(e, '取消传输失败');
    }
  }

  /// 加载传输历史
  Future<void> loadTransferHistory() async {
    try {
      final transfers = await _service.getTransfers();
      transferHistory.value = transfers;

      // 筛选待处理的请求
      await loadPendingRequests();
    } catch (e) {
      handleError(e, '加载传输历史失败');
    }
  }

  /// 加载待处理的请求
  Future<void> loadPendingRequests() async {
    try {
      final transfers = await _service.getTransfers();
      final localDeviceId = localDevice.value?.deviceId;

      // 筛选发送给本机且状态为pending的请求
      pendingRequests.value = transfers
          .where((t) => t.receiverDeviceId == localDeviceId && t.status == TransferStatus.pending)
          .toList();
    } catch (e) {
      handleError(e, '加载待处理请求失败');
    }
  }

  /// 添加信任设备
  Future<void> addTrustedDevice(DeviceInfo device) async {
    try {
      await _service.addTrustedDevice(device.deviceId, device.deviceName);
      await loadTrustedDevices();
      showSuccess('已添加信任设备');
    } catch (e) {
      handleError(e, '添加信任设备失败');
    }
  }

  /// 移除信任设备
  Future<void> removeTrustedDevice(String deviceId) async {
    try {
      await _service.removeTrustedDevice(deviceId);
      await loadTrustedDevices();
      showSuccess('已移除信任设备');
    } catch (e) {
      handleError(e, '移除信任设备失败');
    }
  }

  /// 检查是否为信任设备
  Future<bool> isTrustedDevice(String deviceId) async {
    try {
      return await _service.isTrustedDevice(deviceId);
    } catch (e) {
      handleError(e, '检查信任设备失败');
      return false;
    }
  }

  /// 加载信任设备列表
  Future<void> loadTrustedDevices() async {
    try {
      final devices = await _service.getTrustedDevices();
      trustedDevices.value = devices;
    } catch (e) {
      handleError(e, '加载信任设备失败');
    }
  }

  /// 启动自动刷新
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      refreshDevices();
      loadPendingRequests();
    });
  }

  /// 停止自动刷新
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 错误处理辅助方法
  void handleError(dynamic error, String message) {
    setError('$message: $error');
    Get.snackbar(
      '错误',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 3),
    );
  }

  /// 显示错误消息
  void showError(String message) {
    Get.snackbar(
      '错误',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  /// 显示成功消息
  void showSuccess(String message) {
    Get.snackbar(
      '成功',
      message,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void onClose() {
    _stopAutoRefresh();
    stopService();
    super.onClose();
  }
}
