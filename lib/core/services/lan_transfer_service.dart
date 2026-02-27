import 'dart:async';
import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/lan_transfer.dart' as rust_api;

/// 设备信息模型
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String ipAddress;
  final int port;
  final String discoveredAt;
  final bool isOnline;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    required this.port,
    required this.discoveredAt,
    required this.isOnline,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      deviceType: json['device_type'] as String,
      ipAddress: json['ip_address'] as String,
      port: json['port'] as int,
      discoveredAt: json['discovered_at'] as String,
      isOnline: json['is_online'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
      'ip_address': ipAddress,
      'port': port,
      'discovered_at': discoveredAt,
      'is_online': isOnline,
    };
  }
}

/// 传输类型
enum TransferType { file, text, image, video }

/// 传输状�?
enum TransferStatus { pending, accepted, rejected, transferring, completed, failed, cancelled }

/// 传输项模�?
class TransferItem {
  final String transferId;
  final String senderDeviceId;
  final String senderDeviceName;
  final String receiverDeviceId;
  final TransferType transferType;
  final String? fileName;
  final int? fileSize;
  final String? textContent;
  final String? filePath;
  final TransferStatus status;
  final double progress;
  final String createdAt;
  final String updatedAt;
  final String? errorMessage;

  TransferItem({
    required this.transferId,
    required this.senderDeviceId,
    required this.senderDeviceName,
    required this.receiverDeviceId,
    required this.transferType,
    this.fileName,
    this.fileSize,
    this.textContent,
    this.filePath,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
    this.errorMessage,
  });

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      transferId: json['transfer_id'] as String,
      senderDeviceId: json['sender_device_id'] as String,
      senderDeviceName: json['sender_device_name'] as String,
      receiverDeviceId: json['receiver_device_id'] as String,
      transferType: _parseTransferType(json['transfer_type'] as String),
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] as int?,
      textContent: json['text_content'] as String?,
      filePath: json['file_path'] as String?,
      status: _parseTransferStatus(json['status'] as String),
      progress: (json['progress'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      errorMessage: json['error_message'] as String?,
    );
  }

  static TransferType _parseTransferType(String type) {
    switch (type) {
      case 'File':
        return TransferType.file;
      case 'Text':
        return TransferType.text;
      case 'Image':
        return TransferType.image;
      case 'Video':
        return TransferType.video;
      default:
        return TransferType.file;
    }
  }

  static TransferStatus _parseTransferStatus(String status) {
    switch (status) {
      case 'Pending':
        return TransferStatus.pending;
      case 'Accepted':
        return TransferStatus.accepted;
      case 'Rejected':
        return TransferStatus.rejected;
      case 'Transferring':
        return TransferStatus.transferring;
      case 'Completed':
        return TransferStatus.completed;
      case 'Failed':
        return TransferStatus.failed;
      case 'Cancelled':
        return TransferStatus.cancelled;
      default:
        return TransferStatus.pending;
    }
  }
}

/// 信任设备模型
class TrustedDevice {
  final String deviceId;
  final String deviceName;
  final String trustedAt;

  TrustedDevice({required this.deviceId, required this.deviceName, required this.trustedAt});

  factory TrustedDevice.fromJson(Map<String, dynamic> json) {
    return TrustedDevice(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      trustedAt: json['trusted_at'] as String,
    );
  }
}

/// 局域网传输服务
class LanTransferService {
  static const int kDefaultPort = 8889;

  bool _isRunning = false;
  Timer? _deviceRefreshTimer;

  /// 启动服务
  Future<void> startService({int port = kDefaultPort}) async {
    if (_isRunning) {
      logger.d('LAN Transfer service already running');
      return;
    }

    try {
      rust_api.lanTransferInit();
      await rust_api.lanTransferStart(port: port);
      _isRunning = true;

      // 定期刷新设备列表
      _startDeviceRefresh();

      logger.i('LAN Transfer service started on port $port');
    } catch (e) {
      logger.e('Failed to start LAN Transfer service: $e');
      rethrow;
    }
  }

  /// 停止服务
  Future<void> stopService() async {
    if (!_isRunning) {
      return;
    }

    try {
      _stopDeviceRefresh();
      await rust_api.lanTransferStop();
      _isRunning = false;
      logger.i('LAN Transfer service stopped');
    } catch (e) {
      logger.e('Failed to stop LAN Transfer service: $e');
      rethrow;
    }
  }

  /// 获取本机设备信息
  Future<DeviceInfo> getLocalDevice({int port = kDefaultPort}) async {
    try {
      final jsonStr = await rust_api.lanTransferGetLocalDevice(port: port);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return DeviceInfo.fromJson(json);
    } catch (e) {
      logger.e('Failed to get local device: $e');
      rethrow;
    }
  }

  /// 获取已发现的设备列表
  Future<List<DeviceInfo>> getDevices() async {
    try {
      final jsonStrList = await rust_api.lanTransferGetDevices();
      return jsonStrList
          .map((jsonStr) => DeviceInfo.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.e('Failed to get devices: $e');
      return [];
    }
  }

  /// 发送文本消�?
  Future<String> sendText({
    required String targetIp,
    required int targetPort,
    required String targetDeviceId,
    required String text,
  }) async {
    try {
      final transferId = await rust_api.lanTransferSendText(
        targetIp: targetIp,
        targetPort: targetPort,
        targetDeviceId: targetDeviceId,
        text: text,
      );
      logger.i('Started text transfer: $transferId');
      return transferId;
    } catch (e) {
      logger.e('Failed to send text: $e');
      rethrow;
    }
  }

  /// 发送文�?
  Future<String> sendFile({
    required String targetIp,
    required int targetPort,
    required String targetDeviceId,
    required String filePath,
  }) async {
    try {
      final transferId = await rust_api.lanTransferSendFile(
        targetIp: targetIp,
        targetPort: targetPort,
        targetDeviceId: targetDeviceId,
        filePath: filePath,
      );
      logger.i('Started file transfer: $transferId');
      return transferId;
    } catch (e) {
      logger.e('Failed to send file: $e');
      rethrow;
    }
  }

  /// 接受传输
  Future<void> acceptTransfer(String transferId) async {
    try {
      await rust_api.lanTransferAccept(transferId: transferId);
      logger.i('Transfer accepted: $transferId');
    } catch (e) {
      logger.e('Failed to accept transfer: $e');
      rethrow;
    }
  }

  /// 拒绝传输
  Future<void> rejectTransfer(String transferId) async {
    try {
      await rust_api.lanTransferReject(transferId: transferId);
      logger.i('Transfer rejected: $transferId');
    } catch (e) {
      logger.e('Failed to reject transfer: $e');
      rethrow;
    }
  }

  /// 取消传输
  Future<void> cancelTransfer(String transferId) async {
    try {
      await rust_api.lanTransferCancel(transferId: transferId);
      logger.i('Transfer cancelled: $transferId');
    } catch (e) {
      logger.e('Failed to cancel transfer: $e');
      rethrow;
    }
  }

  /// 获取所有传输记�?
  Future<List<TransferItem>> getTransfers() async {
    try {
      final jsonStrList = await rust_api.lanTransferGetTransfers();
      return jsonStrList
          .map((jsonStr) => TransferItem.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.e('Failed to get transfers: $e');
      return [];
    }
  }

  /// 添加信任设备
  Future<void> addTrustedDevice(String deviceId, String deviceName) async {
    try {
      await rust_api.lanTransferAddTrusted(deviceId: deviceId, deviceName: deviceName);
      logger.i('Device trusted: $deviceName');
    } catch (e) {
      logger.e('Failed to trust device: $e');
      rethrow;
    }
  }

  /// 移除信任设备
  Future<void> removeTrustedDevice(String deviceId) async {
    try {
      await rust_api.lanTransferRemoveTrusted(deviceId: deviceId);
      logger.i('Device untrusted: $deviceId');
    } catch (e) {
      logger.e('Failed to untrust device: $e');
      rethrow;
    }
  }

  /// 检查是否为信任设备
  Future<bool> isTrustedDevice(String deviceId) async {
    try {
      return await rust_api.lanTransferIsTrusted(deviceId: deviceId);
    } catch (e) {
      logger.e('Failed to check trusted device: $e');
      return false;
    }
  }

  /// 获取信任设备列表
  Future<List<TrustedDevice>> getTrustedDevices() async {
    try {
      final jsonStrList = await rust_api.lanTransferGetTrustedDevices();
      return jsonStrList
          .map((jsonStr) => TrustedDevice.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.e('Failed to get trusted devices: $e');
      return [];
    }
  }

  /// 启动设备刷新定时�?
  void _startDeviceRefresh() {
    _deviceRefreshTimer?.cancel();
    _deviceRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      getDevices();
    });
  }

  /// 停止设备刷新定时�?
  void _stopDeviceRefresh() {
    _deviceRefreshTimer?.cancel();
    _deviceRefreshTimer = null;
  }

  /// 是否正在运行
  bool get isRunning => _isRunning;

  /// 清理资源
  Future<void> dispose() async {
    await stopService();
  }
}

/// 注册服务�?GetIt
void registerLanTransferService() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<LanTransferService>()) {
    getIt.registerLazySingleton<LanTransferService>(() => LanTransferService());
  }
}
