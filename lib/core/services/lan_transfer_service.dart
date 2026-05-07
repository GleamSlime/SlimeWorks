import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/lan_transfer.dart' as rust_api;
import 'package:slime_works/src/rust/frb_generated.dart';

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
enum TransferStatus {
  pending,
  accepted,
  rejected,
  transferring,
  completed,
  failed,
  cancelled,
  queued,
}

/// 传输项模�?
class TransferItem {
  final String transferId;
  final String senderDeviceId;
  final String senderDeviceName;
  final String receiverDeviceId;

  /// 接收方设备名称（本地队列发送时保存，Rust 侧无此字段）
  final String? receiverDeviceName;
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
    this.receiverDeviceName,
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

  /// 浅拷贝，只替换指定字段
  TransferItem copyWith({
    String? transferId,
    String? senderDeviceId,
    String? senderDeviceName,
    String? receiverDeviceId,
    String? receiverDeviceName,
    TransferType? transferType,
    Object? fileName = _sentinel,
    Object? fileSize = _sentinel,
    Object? textContent = _sentinel,
    Object? filePath = _sentinel,
    TransferStatus? status,
    double? progress,
    String? createdAt,
    String? updatedAt,
    Object? errorMessage = _sentinel,
  }) {
    return TransferItem(
      transferId: transferId ?? this.transferId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      senderDeviceName: senderDeviceName ?? this.senderDeviceName,
      receiverDeviceId: receiverDeviceId ?? this.receiverDeviceId,
      receiverDeviceName: receiverDeviceName ?? this.receiverDeviceName,
      transferType: transferType ?? this.transferType,
      fileName: fileName == _sentinel ? this.fileName : fileName as String?,
      fileSize: fileSize == _sentinel ? this.fileSize : fileSize as int?,
      textContent: textContent == _sentinel ? this.textContent : textContent as String?,
      filePath: filePath == _sentinel ? this.filePath : filePath as String?,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage == _sentinel ? this.errorMessage : errorMessage as String?,
    );
  }

  static const Object _sentinel = Object();

  factory TransferItem.fromJson(Map<String, dynamic> json) {
    return TransferItem(
      transferId: json['transfer_id'] as String,
      senderDeviceId: json['sender_device_id'] as String,
      senderDeviceName: json['sender_device_name'] as String,
      receiverDeviceId: json['receiver_device_id'] as String,
      receiverDeviceName: json['receiver_device_name'] as String?,
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
      case 'Queued':
        return TransferStatus.queued;
      default:
        return TransferStatus.pending;
    }
  }

  static String _transferTypeToString(TransferType type) {
    switch (type) {
      case TransferType.file:
        return 'File';
      case TransferType.text:
        return 'Text';
      case TransferType.image:
        return 'Image';
      case TransferType.video:
        return 'Video';
    }
  }

  static String _transferStatusToString(TransferStatus status) {
    switch (status) {
      case TransferStatus.pending:
        return 'Pending';
      case TransferStatus.accepted:
        return 'Accepted';
      case TransferStatus.rejected:
        return 'Rejected';
      case TransferStatus.transferring:
        return 'Transferring';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Cancelled';
      case TransferStatus.queued:
        return 'Queued';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'transfer_id': transferId,
      'sender_device_id': senderDeviceId,
      'sender_device_name': senderDeviceName,
      'receiver_device_id': receiverDeviceId,
      'receiver_device_name': receiverDeviceName,
      'transfer_type': _transferTypeToString(transferType),
      'file_name': fileName,
      'file_size': fileSize,
      'text_content': textContent,
      'file_path': filePath,
      'status': _transferStatusToString(status),
      'progress': progress,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'error_message': errorMessage,
    };
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
  bool _isRefreshing = false; // 防止定时器回调堆积
  Future<void>? _pendingStart;
  Future<void>? _pendingStop;
  Future<void>? _rustInitFuture;
  DateTime? _lastEmptyDevicesSelfCheckAt;

  Future<void> _ensureRustReady() async {
    // Already initialized by main.dart (or a prior call); skip to avoid "init twice" error.
    if (RustLib.instance.initialized) return;

    final existing = _rustInitFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = RustLib.init();
    _rustInitFuture = future;
    try {
      await future;
    } catch (_) {
      if (identical(_rustInitFuture, future)) {
        _rustInitFuture = null;
      }
      rethrow;
    }
  }

  /// 启动服务
  ///
  /// [preTrustedJson] 为已持久化的信任设备 JSON 列表（每项形如 `{"device_id":"…","device_name":"…"}`），
  /// 在 TCP 监听开始前注入 Rust，避免连接请求在信任设备尚未注册时到达的竞态问题。
  Future<void> startService({
    int port = kDefaultPort,
    List<String> preTrustedJson = const [],
  }) async {
    if (_isRunning) {
      logger.d('LAN Transfer service already running');
      return;
    }

    if (_pendingStart != null) {
      await _pendingStart;
      return;
    }

    _pendingStart = _startServiceInternal(port: port, preTrustedJson: preTrustedJson);
    try {
      await _pendingStart;
    } finally {
      _pendingStart = null;
    }
  }

  Future<void> _startServiceInternal({
    required int port,
    List<String> preTrustedJson = const [],
  }) async {
    if (_pendingStop != null) {
      await _pendingStop;
    }

    try {
      await _ensureRustReady();
      logger.i('LAN Transfer start begin, port=$port');
      rust_api.lanTransferInit();
      // 获取 documents 目录才能在 iOS 等移动端保存文件
      final docsDir = await getApplicationDocumentsDirectory();
      final saveDir = '${docsDir.path}/LanTransfer';
      await rust_api.lanTransferStart(port: port, saveDir: saveDir, preTrustedJson: preTrustedJson);
      _isRunning = true;

      // 定期刷新设备列表
      _startDeviceRefresh();

      logger.i('LAN Transfer service started on port $port');
      await runSelfCheck(reason: 'start-service-success');
    } catch (e) {
      if (_isAddressInUseError(e)) {
        logger.i('Port $port is in use, try restart with stop + retry');
        try {
          await rust_api.lanTransferStop();
        } catch (_) {}

        // 移动端 OS 释放端口可能需要更长时间，多次重试并递增等待间隔
        final retryDelays = const [400, 800, 1500];
        final docsDir = await getApplicationDocumentsDirectory();
        final saveDir = '${docsDir.path}/LanTransfer';
        for (int attempt = 0; attempt < retryDelays.length; attempt++) {
          await Future<void>.delayed(Duration(milliseconds: retryDelays[attempt]));
          try {
            await rust_api.lanTransferStart(
              port: port,
              saveDir: saveDir,
              preTrustedJson: preTrustedJson,
            );
            _isRunning = true;
            _startDeviceRefresh();
            logger.i('LAN Transfer service restarted on port $port (attempt ${attempt + 1})');
            await runSelfCheck(reason: 'start-service-restarted');
            return;
          } catch (retryErr) {
            if (!_isAddressInUseError(retryErr) || attempt >= retryDelays.length - 1) {
              logger.e('LAN Transfer restart attempt ${attempt + 1} failed: $retryErr');
              rethrow;
            }
            logger.info('Port $port still in use, retrying (attempt ${attempt + 1})...');
          }
        }
        return;
      }

      if (_isManagerAlreadyStartedError(e)) {
        _isRunning = true;
        _startDeviceRefresh();
        logger.i('LAN Transfer manager already started, sync local running state');
        await runSelfCheck(reason: 'manager-already-started');
        return;
      }

      logger.e('Failed to start LAN Transfer service: $e');
      rethrow;
    }
  }

  /// 停止服务
  Future<void> stopService() async {
    if (_pendingStop != null) {
      await _pendingStop;
      return;
    }

    if (!_isRunning) {
      return;
    }

    _pendingStop = _stopServiceInternal();
    try {
      await _pendingStop;
    } finally {
      _pendingStop = null;
    }
  }

  Future<void> _stopServiceInternal() async {
    try {
      await _ensureRustReady();
      logger.i('LAN Transfer stop begin');
      _stopDeviceRefresh();
      await rust_api.lanTransferStop();
      _isRunning = false;
      logger.i('LAN Transfer service stopped');
    } catch (e) {
      logger.e('Failed to stop LAN Transfer service: $e');
      rethrow;
    }
  }

  bool _isAddressInUseError(Object error) {
    final message = error.toString();
    return message.contains('Address already in use') || message.contains('os error 48');
  }

  bool _isManagerAlreadyStartedError(Object error) {
    return error.toString().contains('Manager already started');
  }

  /// 获取本机设备信息
  Future<DeviceInfo> getLocalDevice({int port = kDefaultPort}) async {
    try {
      await _ensureRustReady();
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
      await _ensureRustReady();
      final jsonStrList = await rust_api.lanTransferGetDevices();
      final devices = jsonStrList
          .map((jsonStr) => DeviceInfo.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>))
          .toList();
      logger.i('LAN Transfer discovered devices count=${devices.length}');
      return devices;
    } catch (e) {
      logger.e('Failed to get devices: $e');
      return [];
    }
  }

  /// 自检日志（用于排查设备发现和服务状态问题）
  Future<Map<String, dynamic>> runSelfCheck({String reason = 'manual'}) async {
    final DateTime now = DateTime.now();
    final List<ConnectivityResult> connectivityResults = await Connectivity().checkConnectivity();
    final bool connected = connectivityResults.any((result) => result != ConnectivityResult.none);

    DeviceInfo? local;
    String? localError;
    try {
      local = await getLocalDevice();
    } catch (e) {
      localError = e.toString();
    }

    final List<DeviceInfo> devices = await getDevices();

    final Map<String, dynamic> report = <String, dynamic>{
      'reason': reason,
      'timestamp': now.toIso8601String(),
      'platform': Platform.operatingSystem,
      'is_running_local': _isRunning,
      'default_port': kDefaultPort,
      'connectivity': connectivityResults.map((e) => e.name).toList(),
      'is_connected': connected,
      'local_device': local?.toJson(),
      'local_device_error': localError,
      'discovered_count': devices.length,
      'discovered_devices': devices.map((d) => d.toJson()).toList(),
    };

    logger.i('LAN Transfer self-check: ${jsonEncode(report)}');
    return report;
  }

  bool shouldRunEmptyDevicesSelfCheck() {
    final DateTime now = DateTime.now();
    if (_lastEmptyDevicesSelfCheckAt == null) {
      _lastEmptyDevicesSelfCheckAt = now;
      return true;
    }

    final Duration delta = now.difference(_lastEmptyDevicesSelfCheckAt!);
    if (delta.inSeconds >= 15) {
      _lastEmptyDevicesSelfCheckAt = now;
      return true;
    }

    return false;
  }

  /// 发送文本消�?
  Future<String> sendText({
    required String targetIp,
    required int targetPort,
    required String targetDeviceId,
    required String text,
  }) async {
    try {
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
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
      await _ensureRustReady();
      return await rust_api.lanTransferIsTrusted(deviceId: deviceId);
    } catch (e) {
      logger.e('Failed to check trusted device: $e');
      return false;
    }
  }

  /// 获取信任设备列表
  Future<List<TrustedDevice>> getTrustedDevices() async {
    try {
      await _ensureRustReady();
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
      // 上次刷新仍在进行中则跳过本次，防止慢网络下请求无限堆积
      if (_isRefreshing) return;
      _isRefreshing = true;
      getDevices().whenComplete(() {
        _isRefreshing = false;
      });
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
