import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/asr_service.dart';
import 'package:slime_works/core/services/asr/subtitle_translate_service.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/src/rust/api/asr.dart' as asr_api;

const Loggers _logger = Loggers(name: '语音识别设置');

/// 语音识别设置服务（GetIt 单例 + GetxService）
///
/// 负责两件事：
/// 1. 内网大模型列表的持久化与增删改查（优先内网）
/// 2. 本地 SenseVoice 引擎的一键部署状态与进度（其次本地）
class AsrSettingsService extends GetxService {
  static const String _keyServers = 'asr_servers';
  static const String _keyPreferRemote = 'asr_prefer_remote';
  static const String _keyDefaultLanguage = 'asr_default_language';
  static const String _keyTranslateServers = 'asr_translate_servers';
  static const String _keyAutoTranslate = 'asr_auto_translate';
  static const String _keyBilingual = 'asr_bilingual_subtitle';

  late final SharedPreferences _prefs;
  final AsrService _asrService;
  final SubtitleTranslateService _translateService;

  /// 内网服务列表（顺序即优先级）
  final RxList<AsrServer> servers = <AsrServer>[].obs;

  /// 是否优先使用内网服务；关闭后直接走本地引擎
  final RxBool preferRemote = true.obs;

  /// 识别字幕的默认语言（右键菜单会记住上一次的选择）
  final RxString defaultLanguage = 'auto'.obs;

  /// 内网字幕翻译服务列表（顺序即优先级）
  final RxList<TranslateServer> translateServers = <TranslateServer>[].obs;

  /// 识别出字幕后是否自动翻译为中文
  final RxBool autoTranslate = false.obs;

  /// 中文字幕是否保留原文（双语两行，审核时可对照）
  final RxBool bilingualSubtitle = true.obs;

  /// 本地引擎部署状态
  final Rx<asr_api.AsrStatusInfo?> localStatus = Rx<asr_api.AsrStatusInfo?>(null);
  final RxBool localReady = false.obs;

  /// 一键部署：是否进行中 / 进度 0~1 / 阶段（0 空闲 1 下载 2 解压 3 完成 4 失败）
  final RxBool isDeploying = false.obs;
  final RxDouble deployProgress = 0.0.obs;
  final RxInt deployStage = 0.obs;

  /// 移动端没有本地 sidecar，只支持内网服务
  bool get supportsLocalEngine => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Timer? _deployTimer;
  Future<String?>? _deployFuture;

  AsrSettingsService(this._asrService, this._translateService);

  /// 初始化：读取持久化配置 + 刷新本地部署状态（纯本地操作，不触发网络）
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadSettings();
      refreshLocalStatus();
    } catch (e, st) {
      _logger.error('初始化语音识别设置失败', error: e, stackTrace: st);
    }
  }

  void _loadSettings() {
    final raw = _prefs.getString(_keyServers);
    List<AsrServer> loaded = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        loaded = decoded
            .map((json) => AsrServer.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _logger.error('内网服务列表解析失败，已重置为空', error: e);
      }
    }
    servers.assignAll(loaded);
    preferRemote.value = _prefs.getBool(_keyPreferRemote) ?? true;
    defaultLanguage.value = _prefs.getString(_keyDefaultLanguage) ?? 'auto';
    _asrService.setServers(loaded);

    translateServers.assignAll(_decodeTranslateServers());
    _translateService.setServers(translateServers.toList());
    autoTranslate.value = _prefs.getBool(_keyAutoTranslate) ?? false;
    bilingualSubtitle.value = _prefs.getBool(_keyBilingual) ?? true;
  }

  List<TranslateServer> _decodeTranslateServers() {
    final raw = _prefs.getString(_keyTranslateServers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((json) => TranslateServer.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.error('字幕翻译服务列表解析失败，已重置为空', error: e);
      return const [];
    }
  }

  /// 设置默认识别语言（右键菜单选择后也会写回这里，作为下次的默认值）
  Future<void> setDefaultLanguage(String code) async {
    defaultLanguage.value = code;
    await _prefs.setString(_keyDefaultLanguage, code);
  }

  // ── 内网服务管理 ──────────────────────────────────────────────────────────

  /// 新增或按地址覆盖一条服务
  Future<void> upsertServer(AsrServer server) async {
    final index = servers.indexWhere((s) => s.url == server.url);
    if (index >= 0) {
      servers[index] = server;
    } else {
      servers.add(server);
    }
    await _persistServers();
  }

  Future<void> removeServer(String url) async {
    servers.removeWhere((s) => s.url == url);
    await _persistServers();
  }

  Future<void> setServerEnabled(String url, bool enabled) async {
    final index = servers.indexWhere((s) => s.url == url);
    if (index < 0) return;
    servers[index] = servers[index].copyWith(enabled: enabled);
    await _persistServers();
  }

  Future<void> setPreferRemote(bool value) async {
    preferRemote.value = value;
    await _prefs.setBool(_keyPreferRemote, value);
  }

  Future<void> _persistServers() async {
    _asrService.setServers(servers.toList());
    await _prefs.setString(
      _keyServers,
      jsonEncode(servers.map((s) => s.toJson()).toList()),
    );
  }

  /// 测试单个服务连通性，并把最新状态写回列表
  Future<bool> testServer(AsrServer server) async {
    final ok = await _asrService.testServer(server);
    _syncAvailabilityFromService();
    return ok;
  }

  /// 依次测试所有启用服务（设置页"测试全部"按钮）
  Future<int> testAllServers() async {
    int available = 0;
    for (final server in servers.where((s) => s.enabled)) {
      if (await _asrService.testServer(server)) available++;
    }
    _syncAvailabilityFromService();
    _logger.info('[语音识别] 内网服务探测完成：$available/${servers.where((s) => s.enabled).length} 可用');
    return available;
  }

  void _syncAvailabilityFromService() {
    final latest = _asrService.servers;
    bool changed = false;
    for (final server in latest) {
      final index = servers.indexWhere((s) => s.url == server.url);
      if (index >= 0 && servers[index] != server) {
        servers[index] = server;
        changed = true;
      }
    }
    if (changed) {
      // 探测结果也持久化，下次启动即可看到上次是否在线
      unawaited(_persistServers());
    }
  }

  /// 返回当前可用的内网服务；先信任缓存状态，失效时再探测一轮
  Future<AsrServer?> pickAvailableServer() async {
    final cached = _asrService.firstAvailable;
    if (cached != null) return cached;
    final probed = await _asrService.probeAvailableServer();
    _syncAvailabilityFromService();
    return probed;
  }

  // ── 字幕翻译服务管理 ──────────────────────────────────────────────────────

  /// 新增或按地址覆盖一条翻译服务
  Future<void> upsertTranslateServer(TranslateServer server) async {
    final index = translateServers.indexWhere((s) => s.url == server.url);
    if (index >= 0) {
      translateServers[index] = server;
    } else {
      translateServers.add(server);
    }
    await _persistTranslateServers();
  }

  Future<void> removeTranslateServer(String url) async {
    translateServers.removeWhere((s) => s.url == url);
    await _persistTranslateServers();
  }

  Future<void> setTranslateServerEnabled(String url, bool enabled) async {
    final index = translateServers.indexWhere((s) => s.url == url);
    if (index < 0) return;
    translateServers[index] = translateServers[index].copyWith(enabled: enabled);
    await _persistTranslateServers();
  }

  Future<void> setAutoTranslate(bool value) async {
    autoTranslate.value = value;
    await _prefs.setBool(_keyAutoTranslate, value);
  }

  Future<void> setBilingualSubtitle(bool value) async {
    bilingualSubtitle.value = value;
    await _prefs.setBool(_keyBilingual, value);
  }

  Future<void> _persistTranslateServers() async {
    _translateService.setServers(translateServers.toList());
    await _prefs.setString(
      _keyTranslateServers,
      jsonEncode(translateServers.map((s) => s.toJson()).toList()),
    );
  }

  /// 测试单个翻译服务
  Future<bool> testTranslateServer(TranslateServer server) async {
    final ok = await _translateService.testServer(server);
    _syncTranslateAvailabilityFromService();
    return ok;
  }

  /// 依次测试所有启用的翻译服务，返回可用数量
  Future<int> testAllTranslateServers() async {
    final enabled = translateServers.where((s) => s.enabled).toList();
    var available = 0;
    for (final server in enabled) {
      if (await _translateService.testServer(server)) available++;
    }
    _syncTranslateAvailabilityFromService();
    _logger.info('[语音识别] 字幕翻译服务探测完成：$available/${enabled.length} 可用');
    return available;
  }

  void _syncTranslateAvailabilityFromService() {
    bool changed = false;
    for (final server in _translateService.servers) {
      final index = translateServers.indexWhere((s) => s.url == server.url);
      if (index >= 0 && translateServers[index] != server) {
        translateServers[index] = server;
        changed = true;
      }
    }
    if (changed) {
      unawaited(_persistTranslateServers());
    }
  }

  /// 取当前可用的翻译服务：每次都真探测一轮
  ///
  /// 这里不能像语音识别那样先用缓存标记短路——识别失败会回落本地引擎，
  /// 而翻译没有退路：服务进程几小时前就退了、缓存还显示可用，
  /// 整批字幕会全部走失败兜底原样写回，任务却报成功。
  Future<TranslateServer?> pickAvailableTranslateServer() async {
    final probed = await _translateService.probeAvailableServer();
    _syncTranslateAvailabilityFromService();
    return probed;
  }

  SubtitleTranslateService get translateService => _translateService;

  // ── 本地引擎一键部署 ──────────────────────────────────────────────────────

  /// 刷新本地部署状态（同步 FFI，几乎零开销）
  void refreshLocalStatus() {
    if (!supportsLocalEngine) {
      localStatus.value = null;
      localReady.value = false;
      return;
    }
    try {
      localStatus.value = asr_api.asrGetStatus();
      localReady.value = asr_api.asrIsReady();
    } catch (e) {
      _logger.error('读取本地语音识别状态失败', error: e);
      localStatus.value = null;
      localReady.value = false;
    }
  }

  /// 一键部署：下载 sherpa-onnx 运行时 + SenseVoice/VAD 模型
  ///
  /// 返回 null 表示成功，否则为错误信息；调用方可直接 await
  Future<String?> deployLocal() async {
    if (!supportsLocalEngine) return '当前平台不支持本地语音识别引擎';
    if (isDeploying.value) {
      // 重复点击时等待同一次部署结果，而不是再起一个下载
      return await _deployFuture ?? '部署已在进行中';
    }

    final future = _runDeploy();
    _deployFuture = future;
    isDeploying.value = true;
    deployStage.value = 1;
    deployProgress.value = 0;
    _startDeployPolling();

    try {
      final error = await future;
      refreshLocalStatus();
      return error;
    } finally {
      _deployTimer?.cancel();
      _deployTimer = null;
      isDeploying.value = false;
      _deployFuture = null;
    }
  }

  Future<String?> _runDeploy() async {
    try {
      await asr_api.asrDeploy();
      deployStage.value = 3;
      deployProgress.value = 1;
      return null;
    } catch (e) {
      deployStage.value = 4;
      _logger.error('本地语音识别部署失败', error: e);
      return e.toString();
    }
  }

  /// 轮询 Rust 侧的部署进度（下载/解压都在后台线程写原子变量）
  void _startDeployPolling() {
    _deployTimer?.cancel();
    _deployTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final raw = asr_api.asrGetDeployProgress();
      if (raw >= 0) {
        deployProgress.value = (raw / 100.0).clamp(0.0, 0.99);
      }
      deployStage.value = asr_api.asrGetDeployStage();
    });
  }

  /// 删除本地部署（释放磁盘）
  Future<String?> removeLocalDeployment() async {
    if (!supportsLocalEngine) return '当前平台不支持本地语音识别引擎';
    try {
      asr_api.asrRemoveDeployment();
      refreshLocalStatus();
      return null;
    } catch (e) {
      _logger.error('删除本地语音识别部署失败', error: e);
      return e.toString();
    }
  }

  /// 部署目录占用（GB 展示用）
  double get localDiskUsageGb {
    final bytes = localStatus.value?.diskUsageBytes ?? BigInt.zero;
    return bytes / BigInt.from(1024 * 1024 * 1024);
  }
}
