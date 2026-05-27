import 'dart:async';

import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';

class AliyunDdnsViewModel extends GetxController {
  final AliyunDdnsService _service = GetIt.instance.get<AliyunDdnsService>();

  final RxBool isEnabled = false.obs;
  final RxString currentIp = ''.obs;
  final RxString lastUpdate = ''.obs;
  final RxString lastResult = ''.obs;
  final RxList<Map<String, dynamic>> domainStatuses = <Map<String, dynamic>>[].obs;

  final RxString accessKeyId = ''.obs;
  final RxString accessKeySecret = ''.obs;
  final RxList<WatchDomain> watchDomains = <WatchDomain>[].obs;
  final RxInt intervalSecs = 300.obs;

  final RxList<Map<String, dynamic>> logs = <Map<String, dynamic>>[].obs;

  final RxBool isChecking = false.obs;
  final RxBool isConfigLoaded = false.obs;

  final RxString currentNodeId = ''.obs;

  bool get isLocal => currentNodeId.value.isEmpty;

  StreamSubscription? _enabledSub;
  StreamSubscription? _currentIpSub;
  StreamSubscription? _lastUpdateSub;
  StreamSubscription? _lastResultSub;
  StreamSubscription? _logsSub;
  StreamSubscription? _accessKeyIdSub;
  StreamSubscription? _accessKeySecretSub;
  StreamSubscription? _watchDomainsSub;
  StreamSubscription? _intervalSecsSub;
  StreamSubscription? _domainStatusesSub;
  StreamSubscription? _selectedNodeIdSub;

  @override
  void onInit() {
    super.onInit();
    _service.ensureInitialized().then((_) {
      _bindService();
      _loadFromService();
      currentNodeId.value = _service.selectedNodeId.value;
    });
  }

  void _bindService() {
    _enabledSub = _service.enabled.listen((v) => isEnabled.value = v);
    _currentIpSub = _service.currentIp.listen((v) => currentIp.value = v);
    _lastUpdateSub = _service.lastUpdate.listen((v) => lastUpdate.value = v);
    _lastResultSub = _service.lastResult.listen((v) => lastResult.value = v);
    _logsSub = _service.logs.listen((v) => logs.value = v);
    _accessKeyIdSub = _service.accessKeyId.listen((v) => accessKeyId.value = v);
    _accessKeySecretSub = _service.accessKeySecret.listen((v) => accessKeySecret.value = v);
    _watchDomainsSub = _service.watchDomains.listen((v) => watchDomains.value = v);
    _intervalSecsSub = _service.intervalSecs.listen((v) => intervalSecs.value = v);
    _domainStatusesSub = _service.domainStatuses.listen((v) => domainStatuses.value = v);
    _selectedNodeIdSub = _service.selectedNodeId.listen((v) => currentNodeId.value = v);
  }

  void _loadFromService() {
    isEnabled.value = _service.enabled.value;
    currentIp.value = _service.currentIp.value;
    lastUpdate.value = _service.lastUpdate.value;
    lastResult.value = _service.lastResult.value;
    accessKeyId.value = _service.accessKeyId.value;
    accessKeySecret.value = _service.accessKeySecret.value;
    watchDomains.value = _service.watchDomains.toList();
    intervalSecs.value = _service.intervalSecs.value;
    domainStatuses.value = _service.domainStatuses.toList();
    isConfigLoaded.value = true;
  }

  Future<void> switchNode(String nodeId) async {
    currentNodeId.value = nodeId;
    await _service.setSelectedNodeId(nodeId);
    currentIp.value = '';
    lastUpdate.value = '';
    lastResult.value = '';
    domainStatuses.clear();
    watchDomains.clear();
    logs.clear();
    await refreshAll();
  }

  Future<void> refreshAll() async {
    await Future.wait([refreshStatus(), refreshLogs(), refreshWatchDomains()]);
  }

  Future<void> toggleEnabled(bool value) async {
    if (!isLocal) return;
    await _service.setEnabled(value);
    if (value) {
      await _service.initRustModule();
      _service.startCheckTimer();
    } else {
      _service.stopCheckTimer();
    }
  }

  Future<void> saveAccessKeyId(String value) async {
    if (!isLocal) return;
    await _service.setAccessKeyId(value);
    await _service.updateConfig();
  }

  Future<void> saveAccessKeySecret(String value) async {
    if (!isLocal) return;
    await _service.setAccessKeySecret(value);
    await _service.updateConfig();
  }

  Future<void> addWatchDomain(WatchDomain domain) async {
    if (!isLocal) return;
    await _service.addWatchDomain(domain);
  }

  Future<void> removeWatchDomain(int index) async {
    if (!isLocal) return;
    await _service.removeWatchDomain(index);
  }

  Future<void> saveIntervalSecs(int value) async {
    if (!isLocal) return;
    await _service.setIntervalSecs(value);
    await _service.updateConfig();
  }

  Future<void> checkNow() async {
    isChecking.value = true;
    try {
      if (isLocal) {
        await _service.checkAndUpdate();
      } else {
        final result = await _service.remoteCheckAndUpdate();
        lastResult.value = result;
        await refreshStatus();
        await refreshLogs();
      }
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> refreshStatus() async {
    try {
      if (isLocal) {
        await _service.refreshStatus();
      } else {
        final status = await _service.fetchRemoteStatus();
        currentIp.value = status['current_ip'] as String? ?? '';
        lastUpdate.value = status['last_update'] as String? ?? '';
        lastResult.value = status['last_result'] as String? ?? '';
        final ds = status['domain_statuses'] as List<dynamic>? ?? [];
        domainStatuses.value = ds.map((e) => e as Map<String, dynamic>).toList();
        isEnabled.value = status['enabled'] as bool? ?? false;
      }
    } catch (_) {}
  }

  Future<void> refreshLogs() async {
    try {
      if (isLocal) {
        await _service.refreshLogs();
      } else {
        final remoteLogs = await _service.fetchRemoteLogs();
        logs.value = remoteLogs;
      }
    } catch (_) {}
  }

  Future<void> refreshWatchDomains() async {
    try {
      if (isLocal) return;
      final remoteDomains = await _service.fetchRemoteWatchDomains();
      watchDomains.value = remoteDomains;
    } catch (_) {}
  }

  Future<void> clearLogs() async {
    if (!isLocal) return;
    await _service.clearLogs();
  }

  Future<bool> checkNodeAliyunAvailable(String baseUrl) async {
    return _service.checkNodeAliyunAvailable(baseUrl);
  }

  @override
  void onClose() {
    _enabledSub?.cancel();
    _currentIpSub?.cancel();
    _lastUpdateSub?.cancel();
    _lastResultSub?.cancel();
    _logsSub?.cancel();
    _accessKeyIdSub?.cancel();
    _accessKeySecretSub?.cancel();
    _watchDomainsSub?.cancel();
    _intervalSecsSub?.cancel();
    _domainStatusesSub?.cancel();
    _selectedNodeIdSub?.cancel();
    super.onClose();
  }
}
