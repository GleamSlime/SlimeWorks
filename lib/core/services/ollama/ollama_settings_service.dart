import 'dart:convert';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/utils/logger.dart';

/// Ollama 设置存储服务
/// 负责管理 Ollama 配置的持久化存储
class OllamaSettingsService extends GetxService {
  static const String _keyServers = 'ollama_servers';
  static const String _keyDefaultModel = 'ollama_default_model';

  late final SharedPreferences _prefs;
  final OllamaService _ollamaService;

  final RxList<OllamaServer> servers = <OllamaServer>[].obs;
  final RxString defaultModel = ''.obs;
  final RxBool isInitialized = false.obs;

  OllamaSettingsService(this._ollamaService);

  /// 初始化服务
  Future<void> init() async {
    if (isInitialized.value) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadSettings();
      isInitialized.value = true;

      // 启动时查找可用服务器
      if (servers.isNotEmpty) {
        _findAvailableServer();
      }
    } catch (e) {
      const Loggers(name: 'Ollama').error('初始化 Ollama 设置失败', error: e);
    }
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    try {
      // 加载服务器列表
      final serversJson = _prefs.getString(_keyServers);
      if (serversJson != null) {
        final List<dynamic> decoded = jsonDecode(serversJson);
        final loadedServers = decoded
            .map((json) => OllamaServer.fromJson(json as Map<String, dynamic>))
            .toList();
        servers.assignAll(loadedServers);
        _ollamaService.setServers(loadedServers);
      } else {
        // 默认添加本地服务器
        final defaultServers = [
          OllamaServer(url: 'http://localhost:11434'),
          OllamaServer(url: 'http://127.0.0.1:11434'),
        ];
        servers.assignAll(defaultServers);
        _ollamaService.setServers(defaultServers);
        // 保存默认配置
        final json = jsonEncode(defaultServers.map((s) => s.toJson()).toList());
        await _prefs.setString(_keyServers, json);
      }

      // 加载默认模型
      defaultModel.value = _prefs.getString(_keyDefaultModel) ?? '';
    } catch (e) {
      const Loggers(name: 'Ollama').error('加载 Ollama 设置失败', error: e);
    }
  }

  /// 保存服务器列表
  Future<void> saveServers(List<OllamaServer> newServers) async {
    try {
      final serverList = List<OllamaServer>.from(newServers);
      servers.assignAll(serverList);
      final json = jsonEncode(serverList.map((s) => s.toJson()).toList());
      await _prefs.setString(_keyServers, json);
      _ollamaService.setServers(serverList);
      const Loggers(name: 'Ollama').info('保存 Ollama 服务器列表成功');
    } catch (e) {
      const Loggers(name: 'Ollama').error('保存 Ollama 服务器列表失败', error: e);
      rethrow;
    }
  }

  /// 保存默认模型
  Future<void> saveDefaultModel(String model) async {
    try {
      defaultModel.value = model;
      await _prefs.setString(_keyDefaultModel, model);
      const Loggers(name: 'Ollama').info('保存默认模型成功: $model');
    } catch (e) {
      const Loggers(name: 'Ollama').error('保存默认模型失败', error: e);
      rethrow;
    }
  }

  /// 添加服务器
  Future<void> addServer(OllamaServer server) async {
    final newServers = List<OllamaServer>.from(servers);
    newServers.add(server);
    await saveServers(newServers);
  }

  /// 移除服务器
  Future<void> removeServer(String url) async {
    final newServers = servers.where((s) => s.url != url).toList();
    await saveServers(newServers);
  }

  /// 更新服务器
  Future<void> updateServer(String oldUrl, OllamaServer newServer) async {
    final index = servers.indexWhere((s) => s.url == oldUrl);
    if (index != -1) {
      final newServers = List<OllamaServer>.from(servers);
      newServers[index] = newServer;
      await saveServers(newServers);
    }
  }

  /// 测试服务器连接
  Future<bool> testServer(OllamaServer server) async {
    return await _ollamaService.testServer(server);
  }

  /// 查找可用服务器
  Future<void> _findAvailableServer() async {
    try {
      await _ollamaService.findAvailableServer();
    } catch (e) {
      const Loggers(name: 'Ollama').error('查找可用 Ollama 服务器失败', error: e);
    }
  }

  /// 手动刷新服务器状态
  Future<void> refreshServerStatus() async {
    await _findAvailableServer();
    // 刷新服务器列表以更新状态
    servers.refresh();
  }

  /// 获取可用模型列表
  Future<List<OllamaModel>> getModels() async {
    return await _ollamaService.getModels();
  }

  @override
  void onClose() {
    _ollamaService.dispose();
    super.onClose();
  }
}
