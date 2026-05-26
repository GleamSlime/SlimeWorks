import 'dart:async';

import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';

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

  @override
  void onInit() {
    super.onInit();
    _service.ensureInitialized().then((_) {
      _bindService();
      _loadFromService();
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

  Future<void> toggleEnabled(bool value) async {
    await _service.setEnabled(value);
    if (value) {
      await _service.initRustModule();
      _service.startCheckTimer();
    } else {
      _service.stopCheckTimer();
    }
  }

  Future<void> saveAccessKeyId(String value) async {
    await _service.setAccessKeyId(value);
    await _service.updateConfig();
  }

  Future<void> saveAccessKeySecret(String value) async {
    await _service.setAccessKeySecret(value);
    await _service.updateConfig();
  }

  Future<void> addWatchDomain(WatchDomain domain) async {
    await _service.addWatchDomain(domain);
  }

  Future<void> removeWatchDomain(int index) async {
    await _service.removeWatchDomain(index);
  }

  Future<void> saveIntervalSecs(int value) async {
    await _service.setIntervalSecs(value);
    await _service.updateConfig();
  }

  Future<void> checkNow() async {
    isChecking.value = true;
    try {
      await _service.checkAndUpdate();
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> refreshStatus() async {
    await _service.refreshStatus();
  }

  Future<void> refreshLogs() async {
    await _service.refreshLogs();
  }

  Future<void> clearLogs() async {
    await _service.clearLogs();
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
    super.onClose();
  }
}
