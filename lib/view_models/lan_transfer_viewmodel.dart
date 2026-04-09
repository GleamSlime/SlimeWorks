import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/lan_transfer_service.dart';
import 'package:slime_works/core/utils/logger.dart';

/// 局域网传输页面 ViewModel
class LanTransferViewModel extends BaseViewModel {
  final LanTransferService _service = GetIt.instance.get<LanTransferService>();
  final Loggers _logger = const Loggers(name: '局域网互传');

  static const String _kHistoryKey = 'lan_transfer_history';
  static const String _kDeletedIdsKey = 'lan_transfer_deleted_ids';

  /// 设备 ID → 设备名称持久化缓存键
  static const String _kDeviceNamesKey = 'lan_transfer_device_names';

  /// 置顶会话的对端设备 ID 列表
  static const String _kPinnedPeersKey = 'lan_transfer_pinned_peers';

  /// 本机设备 ID 持久化键（跨 session 保持稳定，避免 localDevice 未加载时分组出错）
  static const String _kLocalDeviceIdKey = 'lan_transfer_local_device_id';

  /// 信任设备持久化键（Dart 层备份，防止 Rust 重启后丢失信任状态）
  static const String _kTrustedDevicesKey = 'lan_transfer_trusted_devices';

  // 服务状态
  final RxBool isServiceRunning = false.obs;
  // 默认不扫描，用户手动触发
  final RxBool isScanning = false.obs;

  // 设备列表
  final RxList<DeviceInfo> discoveredDevices = <DeviceInfo>[].obs;
  final Rx<DeviceInfo?> selectedDevice = Rx<DeviceInfo?>(null);
  final Rx<DeviceInfo?> localDevice = Rx<DeviceInfo?>(null);

  // 传输历史（持久化到 SharedPreferences）
  final RxList<TransferItem> transferHistory = <TransferItem>[].obs;
  final RxList<TransferItem> pendingRequests = <TransferItem>[].obs;

  // 信任设备
  final RxList<TrustedDevice> trustedDevices = <TrustedDevice>[].obs;

  // 定时器
  Timer? _refreshTimer;

  // 已弹窗的 transferId，避免同一请求重复弹窗
  final Set<String> _shownRequestIds = {};

  /// 手动删除的 transferId，防止 loadTransferHistory 从 Rust 内存中重新拉回
  final Set<String> _deletedIds = {};

  /// 设备 ID → 设备名称的持久化缓存（在设备不在线时仍能显示名称）
  final Map<String, String> _deviceNames = {};

  /// 置顶会话的对端设备 ID 集合
  final Set<String> _pinnedPeers = {};

  /// 离线发送任务列表：键为本地 localItemId
  final Map<String, _OfflineSendJob> _offlineJobs = {};

  /// 本机设备 ID 的持久化缓存（避免 localDevice 未加载时 transferHistoryPeers 分组出错）
  String _cachedLocalDeviceId = '';

  final Random _random = Random();

  @override
  Future<void> onInitAsync() async {
    if (isInitialized) {
      return;
    }
    await super.onInitAsync();
    await startService();
  }

  /// 启动服务
  Future<void> startService() async {
    try {
      setLoading(true);
      _logger.i('Start LAN service requested');

      // ① 在 Rust 监听器启动之前先从 SharedPreferences 读取持久化的信任设备列表。
      //    通过 preTrustedJson 参数直接传入 lanTransferStart，确保在第一个 TCP 连接到来前
      //    信任设备已注册，完全消除「服务启动 → 信任注入」窗口期的竞态问题。
      final preloadedTrusted = await _readTrustedDevicesFromPrefs();
      final preTrustedJson = preloadedTrusted
          .map((d) => json.encode({'device_id': d.deviceId, 'device_name': d.deviceName}))
          .toList();

      if (!_service.isRunning) {
        await _service.startService(preTrustedJson: preTrustedJson);
      }

      isServiceRunning.value = true;

      // ② 同步 Dart 层信任列表（服务内已注入完毕，仅更新 Dart 内存状态）
      if (preloadedTrusted.isNotEmpty) {
        trustedDevices.value = preloadedTrusted;
        _logger.i('预加载信任设备 ${preloadedTrusted.length} 条（已随 lanTransferStart 注入 Rust）');
      }

      // 获取本机设备信息
      localDevice.value = await _service.getLocalDevice();
      // 持久化本机设备 ID
      if (localDevice.value != null) {
        _cachedLocalDeviceId = localDevice.value!.deviceId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kLocalDeviceIdKey, _cachedLocalDeviceId);
      }

      // 从 Rust 同步最新信任列表（以 Rust 为准，补全可能因并发写入而遗漏的条目）
      await loadTrustedDevices();

      // 如果 Rust 中仍缺少持久化设备，补充注册（Rust 曾因重启清空时的补偿逻辑）
      await _loadPersistedTrustedDevices();

      // 加载持久化的传输历史（先显示缓存数据）
      await _loadPersistedHistory();

      // 加载持久化的已删除 ID（跨 session 删除保护）
      await _loadPersistedDeletedIds();

      // 加载持久化的本机设备 ID（让 transferHistoryPeers 在 localDevice 就绪前也能正确分组）
      await _loadPersistedLocalDeviceId();

      // 加载持久化的设备名称缓存
      await _loadPersistedDeviceNames();

      // 加载持久化的置顶会话
      await _loadPersistedPinnedPeers();

      // 启动定时刷新，并自动开始扫描（确保会话列表中设备在线状态实时更新）
      isScanning.value = true;
      _startAutoRefresh();
      unawaited(refreshDevices()); // 立即执行一次，无需等待首个 3s 定时器

      await _service.runSelfCheck(reason: 'viewmodel-start-service');
    } catch (e) {
      handleError(e, '启动服务失败');
    } finally {
      setLoading(false);
    }
  }

  /// 手动切换扫描状态
  Future<void> toggleScanning() async {
    if (isScanning.value) {
      stopScanning();
    } else {
      await startScanning();
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
    discoveredDevices.clear();
  }

  /// 停止服务
  Future<void> stopService() async {
    try {
      _logger.i('Stop LAN service requested');
      _stopAutoRefresh();
      isScanning.value = false;
      await _service.stopService();
      isServiceRunning.value = false;
      discoveredDevices.clear();
    } catch (e) {
      handleError(e, '停止服务失败');
    }
  }

  /// 刷新设备列表（仅在 isScanning 时有效）
  Future<void> refreshDevices() async {
    if (!isScanning.value) return;
    try {
      final devices = await _service.getDevices();
      // Dart 层额外过滤：排除本机设备（Rust 层已过滤，此处双重保险）
      final localId = localDevice.value?.deviceId;
      discoveredDevices.value = localId != null
          ? devices.where((d) => d.deviceId != localId).toList()
          : devices;
      _logger.i('Refresh devices completed, count=${discoveredDevices.length}');

      // 缓存设备名称（设备在线时更新，离线时依然能显示名称）
      for (final d in discoveredDevices) {
        _deviceNames[d.deviceId] = d.deviceName;
      }
      await _persistDeviceNames();

      if (devices.isEmpty && isServiceRunning.value && _service.shouldRunEmptyDevicesSelfCheck()) {
        await _service.runSelfCheck(reason: 'refresh-empty-devices');
      }
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

  /// 加载传输历史（合并 Rust 内存数据与持久化缓存）
  Future<void> loadTransferHistory() async {
    try {
      // 从 Rust 获取最新传输记录
      final transfers = await _service.getTransfers();

      // 合并到持久化列表（Rust 数据优先覆盖同 transferId 的缓存项）
      final Map<String, TransferItem> merged = {
        for (final item in transferHistory) item.transferId: item,
      };
      for (final item in transfers) {
        // 跳过用户已手动删除的条目（_deletedIds 是唯一可靠的删除标记）
        if (_deletedIds.contains(item.transferId)) continue;
        merged[item.transferId] = item;
      }
      // 同时过滤掉持久化里可能残留的已删除条目
      _deletedIds.forEach(merged.remove);

      // 按创建时间降序排列（使用 DateTime.parse 支持不同时区的正确比较）
      final sorted = merged.values.toList()
        ..sort((a, b) {
          final ta = DateTime.tryParse(a.createdAt);
          final tb = DateTime.tryParse(b.createdAt);
          if (ta == null || tb == null) return b.createdAt.compareTo(a.createdAt);
          return tb.compareTo(ta);
        });

      transferHistory.value = sorted;

      // 持久化
      await _persistHistory();

      // 筛选待处理的请求
      await loadPendingRequests();
    } catch (e) {
      handleError(e, '加载传输历史失败');
    }
  }

  /// 从 SharedPreferences 加载持久化历史
  Future<void> _loadPersistedHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kHistoryKey);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final List<dynamic> jsonList = json.decode(jsonStr) as List<dynamic>;
      final items = jsonList.map((e) => TransferItem.fromJson(e as Map<String, dynamic>)).toList();
      // 按创建时间降序
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      transferHistory.value = items;
      _logger.i('Loaded ${items.length} persisted transfer history items');
    } catch (e) {
      _logger.error('Failed to load persisted history', error: e);
    }
  }

  /// 从 SharedPreferences 加载持久化的已删除 ID
  Future<void> _loadPersistedDeletedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kDeletedIdsKey) ?? [];
      _deletedIds.addAll(list);
      _logger.i('Loaded ${list.length} persisted deleted IDs');
    } catch (e) {
      _logger.error('Failed to load deleted IDs', error: e);
    }
  }

  /// 保存已删除 ID 到 SharedPreferences
  Future<void> _persistDeletedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 最多保留 1000 条（防无限增长）
      final list = _deletedIds.take(1000).toList();
      await prefs.setStringList(_kDeletedIdsKey, list);
    } catch (e) {
      _logger.error('Failed to persist deleted IDs', error: e);
    }
  }

  /// 保存传输历史到 SharedPreferences
  Future<void> _persistHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保存最近 200 条，防止数据无限增长
      final items = transferHistory.take(200).toList();
      final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
      await prefs.setString(_kHistoryKey, jsonStr);
    } catch (e) {
      _logger.error('Failed to persist transfer history', error: e);
    }
  }

  /// 删除单条传输历史（可选同时删除本地文件）
  Future<void> deleteTransferItem(String transferId, {bool deleteFile = false}) async {
    final item = transferHistory.firstWhereOrNull((t) => t.transferId == transferId);
    if (item == null) return;

    if (deleteFile && item.filePath != null) {
      try {
        final f = File(item.filePath!);
        if (await f.exists()) await f.delete();
      } catch (e) {
        _logger.error('Failed to delete file ${item.filePath}', error: e);
      }
    }

    _deletedIds.add(transferId);
    transferHistory.removeWhere((t) => t.transferId == transferId);
    await _persistHistory();
    await _persistDeletedIds();
  }

  /// 清空所有传输历史
  Future<void> clearAllHistory() async {
    for (final item in transferHistory) {
      _deletedIds.add(item.transferId);
    }
    transferHistory.clear();
    await _persistHistory();
  }

  /// 按对端设备分组传输历史（用于侧边/底部设备列表）
  /// 返回 [(peerDeviceId, peerDeviceName, lastItem, isPinned)]
  List<({String deviceId, String deviceName, TransferItem lastItem, bool isPinned})>
  get transferHistoryPeers {
    final localId = localDevice.value?.deviceId ?? _cachedLocalDeviceId;
    // localId 未知时无法正确分组，返回空列表等待加载完成
    if (localId.isEmpty) return [];
    final Map<String, TransferItem> latestByPeer = {};
    for (final item in transferHistory) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      if (peerId.isEmpty) continue;
      final existing = latestByPeer[peerId];
      if (existing == null || item.createdAt.compareTo(existing.createdAt) > 0) {
        latestByPeer[peerId] = item;
      }
    }
    final peers = latestByPeer.entries.map((e) {
      final item = e.value;
      final localId2 = localDevice.value?.deviceId ?? '';
      // 优先使用 item 里的名称，再查缓存，最后回落到在线设备列表
      final peerName = item.senderDeviceId == localId2
          ? (item.receiverDeviceName ??
                _deviceNames[e.key] ??
                discoveredDevices.firstWhereOrNull((d) => d.deviceId == e.key)?.deviceName ??
                e.key)
          : item.senderDeviceName;
      // 更新设备名缓存
      if (peerName != e.key) _deviceNames[e.key] = peerName;
      return (
        deviceId: e.key,
        deviceName: peerName,
        lastItem: item,
        isPinned: _pinnedPeers.contains(e.key),
      );
    }).toList();
    // 置顶会话优先排序
    peers.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.lastItem.createdAt.compareTo(a.lastItem.createdAt);
    });
    return peers;
  }

  /// 获取与指定对端设备的传输历史（时间升序，适合聊天视图）
  List<TransferItem> transferHistoryForPeer(String peerDeviceId) {
    final localId = localDevice.value?.deviceId ?? _cachedLocalDeviceId;
    return transferHistory.where((item) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      return peerId == peerDeviceId;
    }).toList()..sort((a, b) {
      // 使用 DateTime.parse 进行时区感知比较，避免不同设备因时区不同而排序错误
      final ta = DateTime.tryParse(a.createdAt);
      final tb = DateTime.tryParse(b.createdAt);
      if (ta == null || tb == null) return a.createdAt.compareTo(b.createdAt);
      return ta.compareTo(tb);
    });
  }

  /// 加载待处理的请求；来自已信任设备的请求在 Dart 层也自动 accept，不打扰用户
  Future<void> loadPendingRequests() async {
    try {
      final transfers = await _service.getTransfers();
      final localDeviceId = localDevice.value?.deviceId;
      final trustedIds = trustedDevices.map((d) => d.deviceId).toSet();

      // 筛选发送给本机且状态为 pending 的请求
      final allPending = transfers
          .where((t) => t.receiverDeviceId == localDeviceId && t.status == TransferStatus.pending)
          .toList();

      // 自动 accept 来自信任设备的待处理请求（Dart 层兜底，防 Rust 未持久化信任信息）
      for (final t in allPending) {
        if (trustedIds.contains(t.senderDeviceId) && !_shownRequestIds.contains(t.transferId)) {
          _shownRequestIds.add(t.transferId);
          unawaited(_service.acceptTransfer(t.transferId));
        }
      }

      // 只保留尚未弹窗过、且非信任设备的请求，避免重复弹出
      final filtered = allPending
          .where(
            (t) =>
                !_shownRequestIds.contains(t.transferId) && !trustedIds.contains(t.senderDeviceId),
          )
          .toList();
      pendingRequests.value = filtered;
    } catch (e) {
      handleError(e, '加载待处理请求失败');
    }
  }

  /// 标记某个待处理请求已交互（接受/拒绝），防止重复弹窗
  void markRequestHandled(String transferId) {
    _shownRequestIds.add(transferId);
  }

  /// 使用系统分享面板打开已接收的文件（iOS/Android）
  /// [filePath] 文件在本机的绝对路径
  void shareReceivedFile(String filePath) {
    if (Platform.isIOS || Platform.isAndroid) {
      final xFile = XFile(filePath);
      Share.shareXFiles([xFile], subject: '互传文件');
    }
  }

  /// 添加信任设备（同时持久化到 Dart 层，防止 Rust 重启后遗忘）
  Future<void> addTrustedDevice(DeviceInfo device) async {
    try {
      await _service.addTrustedDevice(device.deviceId, device.deviceName);
      await loadTrustedDevices();
      await _persistTrustedDevices();
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
      await _persistTrustedDevices();
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

  /// 检查是否为置顶会话
  bool isPinnedPeer(String deviceId) => _pinnedPeers.contains(deviceId);

  /// 置顶 / 取消置顶会话
  Future<void> pinPeer(String deviceId) async {
    _pinnedPeers.add(deviceId);
    await _persistPinnedPeers();
    transferHistory.refresh();
  }

  Future<void> unpinPeer(String deviceId) async {
    _pinnedPeers.remove(deviceId);
    await _persistPinnedPeers();
    transferHistory.refresh();
  }

  /// 删除与某对端的所有历史记录（不删除文件）
  Future<void> deleteHistoryForPeer(String peerDeviceId) async {
    final localId = localDevice.value?.deviceId ?? _cachedLocalDeviceId;
    // 先从 Rust 拉一次最新记录，确保 Rust 内存中还未加载到 Dart 的条目也被纳入删除集
    try {
      final freshTransfers = await _service.getTransfers();
      for (final item in freshTransfers) {
        final peerId =
            item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
        if (peerId == peerDeviceId) _deletedIds.add(item.transferId);
      }
    } catch (_) {}
    // 清除 Dart 本地缓存
    final toDelete = transferHistory.where((item) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      return peerId == peerDeviceId;
    }).toList();
    for (final item in toDelete) {
      _deletedIds.add(item.transferId);
    }
    transferHistory.removeWhere((item) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      return peerId == peerDeviceId;
    });
    _cancelOfflineJobsForPeer(peerDeviceId);
    await _persistHistory();
    await _persistDeletedIds();
  }

  /// 删除与某对端的所有记录及文件
  Future<void> deleteConversationForPeer(String peerDeviceId) async {
    final localId = localDevice.value?.deviceId ?? _cachedLocalDeviceId;
    // 先从 Rust 拉取最新记录，确保 Rust 内存中未加载条目也被纳入删除集
    try {
      final freshTransfers = await _service.getTransfers();
      for (final item in freshTransfers) {
        final peerId =
            item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
        if (peerId == peerDeviceId) _deletedIds.add(item.transferId);
      }
    } catch (_) {}
    // 删除本地文件并清理 Dart 缓存
    final toDelete = transferHistory.where((item) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      return peerId == peerDeviceId;
    }).toList();
    for (final item in toDelete) {
      if (item.filePath != null) {
        try {
          final f = File(item.filePath!);
          if (await f.exists()) await f.delete();
        } catch (e) {
          _logger.error('删除文件失败 ${item.filePath}', error: e);
        }
      }
      _deletedIds.add(item.transferId);
    }
    transferHistory.removeWhere((item) {
      final peerId = item.senderDeviceId == localId ? item.receiverDeviceId : item.senderDeviceId;
      return peerId == peerDeviceId;
    });
    _pinnedPeers.remove(peerDeviceId);
    _cancelOfflineJobsForPeer(peerDeviceId);
    await _persistHistory();
    await _persistDeletedIds();
    await _persistPinnedPeers();
  }

  /// 向指定对端发送文本（支持离线排队）
  Future<void> sendTextToDevice(String peerDeviceId, String peerDeviceName, String text) async {
    final local = localDevice.value;
    if (local == null) {
      showError('本机设备信息未就绪');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String(); // 使用 UTC，确保跨设备时间戳可比较
    final tempId = _generateLocalId();

    // 立即创建本地记录并持久化
    final device = discoveredDevices.firstWhereOrNull((d) => d.deviceId == peerDeviceId);
    final initialStatus = device != null ? TransferStatus.pending : TransferStatus.queued;
    final item = TransferItem(
      transferId: tempId,
      senderDeviceId: local.deviceId,
      senderDeviceName: local.deviceName,
      receiverDeviceId: peerDeviceId,
      receiverDeviceName: peerDeviceName,
      transferType: TransferType.text,
      textContent: text,
      status: initialStatus,
      progress: 0.0,
      createdAt: now,
      updatedAt: now,
    );
    transferHistory.insert(0, item);
    await _persistHistory();

    if (device != null) {
      // 设备在线：直接发送
      await _doSendTextAndReplaceLocal(tempId, device, text);
    } else {
      // 设备离线：启动搜索任务
      _startOfflineJob(
        _OfflineSendJob(localItemId: tempId, peerDeviceId: peerDeviceId, text: text),
      );
    }
  }

  /// 向指定对端发送文件（支持离线排队）
  Future<void> sendFileToDevice(String peerDeviceId, String peerDeviceName, String filePath) async {
    final local = localDevice.value;
    if (local == null) {
      showError('本机设备信息未就绪');
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String(); // 使用 UTC，确保跨设备时间戳可比较
    final tempId = _generateLocalId();
    final fileName = filePath.split('/').last;
    final file = File(filePath);
    int? fileSize;
    try {
      fileSize = await file.length();
    } catch (_) {}

    // 判断传输类型
    final lower = fileName.toLowerCase();
    TransferType tType = TransferType.file;
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      tType = TransferType.image;
    } else if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv')) {
      tType = TransferType.video;
    }

    final device = discoveredDevices.firstWhereOrNull((d) => d.deviceId == peerDeviceId);
    final initialStatus = device != null ? TransferStatus.pending : TransferStatus.queued;
    final item = TransferItem(
      transferId: tempId,
      senderDeviceId: local.deviceId,
      senderDeviceName: local.deviceName,
      receiverDeviceId: peerDeviceId,
      receiverDeviceName: peerDeviceName,
      transferType: tType,
      fileName: fileName,
      fileSize: fileSize,
      // 发送方保留原始文件路径，以便离线时仍能预览图片/视频
      filePath: filePath,
      status: initialStatus,
      progress: 0.0,
      createdAt: now,
      updatedAt: now,
    );
    transferHistory.insert(0, item);
    await _persistHistory();

    if (device != null) {
      await _doSendFileAndReplaceLocal(tempId, device, filePath);
    } else {
      _startOfflineJob(
        _OfflineSendJob(localItemId: tempId, peerDeviceId: peerDeviceId, filePath: filePath),
      );
    }
  }

  /// 重试失败的发送记录
  Future<void> retryTransfer(String transferId) async {
    final item = transferHistory.firstWhereOrNull((t) => t.transferId == transferId);
    if (item == null) return;
    if (item.transferType == TransferType.text && item.textContent != null) {
      // 删除原失败记录，重新发送
      await deleteTransferItem(transferId);
      await sendTextToDevice(
        item.receiverDeviceId,
        item.receiverDeviceName ?? _deviceNames[item.receiverDeviceId] ?? item.receiverDeviceId,
        item.textContent!,
      );
    } else if (item.filePath != null) {
      await deleteTransferItem(transferId);
      await sendFileToDevice(
        item.receiverDeviceId,
        item.receiverDeviceName ?? _deviceNames[item.receiverDeviceId] ?? item.receiverDeviceId,
        item.filePath!,
      );
    } else {
      showError('无法重试：缺少发送内容信息');
    }
  }

  /// 发送文本到在线设备，成功后删除临时记录让 Rust 的记录取而代之
  Future<void> _doSendTextAndReplaceLocal(String tempId, DeviceInfo device, String text) async {
    try {
      await _service.sendText(
        targetIp: device.ipAddress,
        targetPort: device.port,
        targetDeviceId: device.deviceId,
        text: text,
      );
      // 删除临时记录，后续 loadTransferHistory 会从 Rust 拉取真实记录
      _deletedIds.add(tempId);
      transferHistory.removeWhere((t) => t.transferId == tempId);
      await _persistHistory();
      await _persistDeletedIds();
      await loadTransferHistory();
    } catch (e) {
      _updateLocalItem(tempId, status: TransferStatus.failed, errorMessage: e.toString());
      showError('发送文本失败：${e.toString()}');
      _logger.error('发送文本失败', error: e);
    }
  }

  /// 发送文件到在线设备，成功后删除临时记录
  Future<void> _doSendFileAndReplaceLocal(String tempId, DeviceInfo device, String filePath) async {
    try {
      await _service.sendFile(
        targetIp: device.ipAddress,
        targetPort: device.port,
        targetDeviceId: device.deviceId,
        filePath: filePath,
      );
      _deletedIds.add(tempId);
      transferHistory.removeWhere((t) => t.transferId == tempId);
      await _persistHistory();
      await _persistDeletedIds();
      await loadTransferHistory();
    } catch (e) {
      _updateLocalItem(tempId, status: TransferStatus.failed, errorMessage: e.toString());
      showError('发送文件失败：${e.toString()}');
      _logger.error('发送文件失败', error: e);
    }
  }

  /// 更新本地记录的状态
  void _updateLocalItem(
    String id, {
    TransferStatus? status,
    String? errorMessage,
    double? progress,
  }) {
    final idx = transferHistory.indexWhere((t) => t.transferId == id);
    if (idx < 0) return;
    final updated = transferHistory[idx].copyWith(
      status: status,
      errorMessage: errorMessage,
      progress: progress,
      updatedAt: DateTime.now().toIso8601String(),
    );
    transferHistory[idx] = updated;
    _persistHistory();
  }

  /// 启动离线发送任务（每 5 秒检查设备是否上线，3 分钟超时）
  void _startOfflineJob(_OfflineSendJob job) {
    _offlineJobs[job.localItemId] = job;
    _logger.i('启动离线发送任务 ${job.localItemId} → 目标设备 ${job.peerDeviceId}');

    // 超时定时器（3 分钟）
    job.timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (job.isCompleted) return;
      job.isCompleted = true;
      job.searchTimer?.cancel();
      _offlineJobs.remove(job.localItemId);
      _updateLocalItem(
        job.localItemId,
        status: TransferStatus.failed,
        errorMessage: '附近未发现对端设备（已超时）',
      );
      _logger.i('离线发送任务超时 ${job.localItemId}');
    });

    // 每 5 秒检查一次设备是否上线
    job.searchTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (job.isCompleted) return;
      // 先触发一次设备刷新
      await refreshDevices();
      final device = discoveredDevices.firstWhereOrNull((d) => d.deviceId == job.peerDeviceId);
      if (device == null) return;

      // 找到设备：取消定时器，执行发送
      job.isCompleted = true;
      job.searchTimer?.cancel();
      job.timeoutTimer?.cancel();
      _offlineJobs.remove(job.localItemId);
      _updateLocalItem(job.localItemId, status: TransferStatus.pending);
      _logger.i('离线发送任务找到设备，开始发送 ${job.localItemId}');

      if (job.text != null) {
        await _doSendTextAndReplaceLocal(job.localItemId, device, job.text!);
      } else if (job.filePath != null) {
        await _doSendFileAndReplaceLocal(job.localItemId, device, job.filePath!);
      }
    });
  }

  /// 取消指定对端的所有离线任务
  void _cancelOfflineJobsForPeer(String peerDeviceId) {
    final toRemove = _offlineJobs.entries
        .where((e) => e.value.peerDeviceId == peerDeviceId)
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      final job = _offlineJobs.remove(id);
      job?.searchTimer?.cancel();
      job?.timeoutTimer?.cancel();
    }
  }

  /// 生成本地唯一 ID（用于离线发送的临时记录）
  String _generateLocalId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _random.nextInt(99999);
    return 'local-$ts-$r';
  }

  /// 从 SharedPreferences 加载本机设备 ID（跨 session 保持稳定，消除 localDevice 未就绪时的分组错误）
  Future<void> _loadPersistedLocalDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kLocalDeviceIdKey);
      if (id != null && id.isNotEmpty) {
        _cachedLocalDeviceId = id;
        _logger.i('已加载本机设备 ID 缓存: $id');
      }
    } catch (e) {
      _logger.error('加载本机设备 ID 缓存失败', error: e);
    }
  }

  /// 从 SharedPreferences 加载设备名称缓存
  Future<void> _loadPersistedDeviceNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kDeviceNamesKey);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      _deviceNames.addAll(map.cast<String, String>());
      _logger.i('已加载 ${_deviceNames.length} 条设备名称缓存');
    } catch (e) {
      _logger.error('加载设备名称缓存失败', error: e);
    }
  }

  /// 持久化设备名称缓存
  Future<void> _persistDeviceNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeviceNamesKey, json.encode(_deviceNames));
    } catch (e) {
      _logger.error('持久化设备名称缓存失败', error: e);
    }
  }

  /// 从 SharedPreferences 加载置顶会话列表
  Future<void> _loadPersistedPinnedPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kPinnedPeersKey) ?? [];
      _pinnedPeers.addAll(list);
      _logger.i('已加载 ${_pinnedPeers.length} 个置顶会话');
    } catch (e) {
      _logger.error('加载置顶会话失败', error: e);
    }
  }

  /// 持久化置顶会话列表
  Future<void> _persistPinnedPeers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPinnedPeersKey, _pinnedPeers.toList());
    } catch (e) {
      _logger.error('持久化置顶会话失败', error: e);
    }
  }

  /// 从 SharedPreferences 同步读取持久化的信任设备列表（用于服务启动前预加载）
  Future<List<TrustedDevice>> _readTrustedDevicesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kTrustedDevicesKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = (json.decode(jsonStr) as List<dynamic>)
          .map((e) => TrustedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
      _logger.i('预读信任设备列表 ${list.length} 条');
      return list;
    } catch (e) {
      _logger.error('预读信任设备列表失败', error: e);
      return [];
    }
  }

  /// 从 SharedPreferences 加载 Dart 层持久化的信任设备，并将缺失的重新注册到 Rust
  Future<void> _loadPersistedTrustedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_kTrustedDevicesKey);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final list = (json.decode(jsonStr) as List<dynamic>)
          .map((e) => TrustedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
      final existingIds = trustedDevices.map((d) => d.deviceId).toSet();
      for (final d in list) {
        // 将 Rust 中不存在的信任设备重新注册（防止 Rust 重启后丢失）
        if (!existingIds.contains(d.deviceId)) {
          try {
            await _service.addTrustedDevice(d.deviceId, d.deviceName);
          } catch (_) {}
          trustedDevices.add(d);
        }
      }
      _logger.i('已恢复 ${list.length} 条 Dart 持久化信任设备');
    } catch (e) {
      _logger.error('加载 Dart 持久化信任设备失败', error: e);
    }
  }

  /// 将信任设备列表持久化到 Dart 层 SharedPreferences
  Future<void> _persistTrustedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = trustedDevices
          .map(
            (d) => {
              'device_id': d.deviceId,
              'device_name': d.deviceName,
              'trusted_at': d.trustedAt,
            },
          )
          .toList();
      await prefs.setString(_kTrustedDevicesKey, json.encode(list));
    } catch (e) {
      _logger.error('持久化信任设备失败', error: e);
    }
  }



  /// 启动自动刷新
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isScanning.value) refreshDevices();
      loadTransferHistory();
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
    _logger.error(message, error: error);
    _showSnack(message: message, isError: true, duration: const Duration(seconds: 3));
  }

  /// 显示错误消息
  void showError(String message) {
    _showSnack(message: message, isError: true);
  }

  /// 显示成功消息
  void showSuccess(String message) {
    _showSnack(message: message, isError: false);
  }

  void _showSnack({
    required String message,
    required bool isError,
    Duration duration = const Duration(seconds: 2),
  }) {
    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) {
      _logger.i('Skip snack because no navigator context: $message');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _logger.i('Skip snack because no ScaffoldMessenger: $message');
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: duration,
          backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        ),
      );
  }

  @override
  void onClose() {
    _stopAutoRefresh();
    // 取消所有离线发送任务
    for (final job in _offlineJobs.values) {
      job.searchTimer?.cancel();
      job.timeoutTimer?.cancel();
    }
    _offlineJobs.clear();
    stopService();
    super.onClose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 离线发送任务数据结构
// ─────────────────────────────────────────────────────────────────────────────

/// 离线发送任务：等待对端设备上线后自动发送
class _OfflineSendJob {
  final String localItemId;
  final String peerDeviceId;

  /// 文本内容（文本类型）
  final String? text;

  /// 文件路径（文件/图片/视频类型）
  final String? filePath;

  Timer? searchTimer;
  Timer? timeoutTimer;
  bool isCompleted = false;

  _OfflineSendJob({
    required this.localItemId,
    required this.peerDeviceId,
    this.text,
    this.filePath,
  });
}
