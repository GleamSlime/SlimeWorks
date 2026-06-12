import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class OllamaSettingsTab extends StatefulWidget {
  const OllamaSettingsTab({super.key});

  @override
  State<OllamaSettingsTab> createState() => _OllamaSettingsTabState();
}

class _OllamaSettingsTabState extends State<OllamaSettingsTab> {
  OllamaSettingsService? _settingsService;
  final RxBool _isLoading = false.obs;
  final RxBool _isReady = false.obs;
  final RxList<OllamaModel> _models = <OllamaModel>[].obs;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      final service = getIt.get<OllamaSettingsService>();
      await service.init();
      if (mounted) {
        setState(() {
          _settingsService = service;
        });
        _isReady.value = true;
        _loadModels();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('初始化 Ollama 服务失败: $e')));
      }
    }
  }

  Future<void> _loadModels() async {
    if (_settingsService == null) return;
    _isLoading.value = true;
    try {
      final models = await _settingsService!.getModels();
      _models.value = models;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取模型列表失败: $e')));
      }
    } finally {
      _isLoading.value = false;
    }
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(icon, size: m.iconSize12, color: theme.colorScheme.primary),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: TextStyle(
            fontSize: m.fontSize15,
            height: 1.4,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: m.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!_isReady.value || _settingsService == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(appMetrics.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildServerSection(),
              SizedBox(height: appMetrics.spacingXLarge),
              _buildDefaultModelSection(),
              SizedBox(height: appMetrics.spacingXLarge),
              _buildTestConnectionSection(),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildServerSection() {
    final m = AppTheme.metrics;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brandColor = isDark ? DarkColors.primary : LightColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSectionTitle('Ollama 服务器', Icons.smart_toy_outlined),
            Spacer(),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddServerDialog,
              tooltip: '添加服务器',
              iconSize: m.iconSize18,
            ),
          ],
        ),
        SizedBox(height: appMetrics.spacingMedium),
        Obx(() {
          if (_settingsService!.servers.isEmpty) {
            return Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace24, vertical: m.kSpace32),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(60),
                borderRadius: m.radius12,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: m.kSpace40,
                    height: m.kSpace40,
                    decoration: BoxDecoration(
                      color: brandColor.withAlpha(20),
                      borderRadius: m.radius10,
                    ),
                    child: Icon(Icons.dns_outlined, size: m.iconSize20, color: brandColor),
                  ),
                  SizedBox(height: m.kSpace12),
                  Text(
                    '暂无配置的服务器',
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    '点击右上角 + 添加 Ollama 服务器',
                    style: TextStyle(
                      fontSize: m.fontSize12,
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _settingsService!.servers.length,
            itemBuilder: (context, index) {
              final server = _settingsService!.servers[index];
              return _buildServerCard(server);
            },
          );
        }),
      ],
    );
  }

  Widget _buildServerCard(OllamaServer server) {
    final m = AppTheme.metrics;
    final statusColor = server.isAvailable ? Colors.green : Colors.grey;

    return Container(
      margin: EdgeInsets.only(bottom: m.kSpace8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: m.radius12,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: ClipRRect(
        borderRadius: m.radius12,
        child: Row(
          children: [
            Container(width: 4, height: 56, color: statusColor),
            Expanded(
              child: ListTile(
                leading: Container(
                  width: m.kSpace32,
                  height: m.kSpace32,
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: m.radius8,
                  ),
                  child: Icon(
                    server.isAvailable ? Icons.check_circle_outline : Icons.error_outline,
                    size: m.iconSize16,
                    color: statusColor,
                  ),
                ),
                title: Text(server.url, style: TextStyle(fontSize: m.fontSize13, fontWeight: FontWeight.w600)),
                subtitle: server.lastChecked != null
                    ? Text(
                        '最后检查: ${_formatDateTime(server.lastChecked!)}',
                        style: TextStyle(fontSize: m.fontSize12),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditServerDialog(server),
                      tooltip: '编辑',
                      iconSize: m.iconSize18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteServer(server.url),
                      tooltip: '删除',
                      iconSize: m.iconSize18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultModelSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('默认 AI 模型', Icons.psychology_outlined),
        SizedBox(height: appMetrics.spacingMedium),
        Obx(() {
          return _buildSettingsCard(
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _settingsService!.defaultModel.value.isEmpty
                        ? null
                        : _settingsService!.defaultModel.value,
                    decoration: const InputDecoration(
                      labelText: '选择默认模型',
                      border: OutlineInputBorder(),
                    ),
                    items: _models
                        .map(
                          (model) => DropdownMenuItem(value: model.name, child: Text(model.name)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _settingsService!.saveDefaultModel(value);
                      }
                    },
                  ),
                ),
                SizedBox(width: appMetrics.spacingMedium),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadModels,
                  tooltip: '刷新模型列表',
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTestConnectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('连接测试', Icons.wifi_find_outlined),
        SizedBox(height: appMetrics.spacingMedium),
        _buildSettingsCard(
          child: Column(
            children: [
              Text('测试所有服务器的连接状态'),
              SizedBox(height: appMetrics.spacingMedium),
              Obx(() {
                return ElevatedButton.icon(
                  onPressed: _isLoading.value ? null : _testAllServers,
                  icon: _isLoading.value
                      ? SizedBox(
                          width: scaleW(16),
                          height: scaleW(16),
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_isLoading.value ? '测试中...' : '测试所有服务器'),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddServerDialog() {
    final urlController = TextEditingController(text: 'http://localhost:11434');
    final apiKeyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 Ollama 服务器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: '服务器 URL',
                hintText: 'http://localhost:11434',
              ),
            ),
            SizedBox(height: appMetrics.spacingMedium),
            TextField(
              controller: apiKeyController,
              decoration: const InputDecoration(labelText: 'API Key（可选）'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入服务器 URL')));
                return;
              }

              final server = OllamaServer(
                url: url,
                apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
              );

              await _settingsService!.addServer(server);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('服务器添加成功')));
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showEditServerDialog(OllamaServer server) {
    final urlController = TextEditingController(text: server.url);
    final apiKeyController = TextEditingController(text: server.apiKey ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑 Ollama 服务器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: '服务器 URL'),
            ),
            SizedBox(height: appMetrics.spacingMedium),
            TextField(
              controller: apiKeyController,
              decoration: const InputDecoration(labelText: 'API Key（可选）'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text.trim();
              if (url.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入服务器 URL')));
                return;
              }

              final newServer = OllamaServer(
                url: url,
                apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
              );

              await _settingsService!.updateServer(server.url, newServer);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('服务器更新成功')));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteServer(String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除服务器 $url 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _settingsService!.removeServer(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('服务器已删除')));
      }
    }
  }

  Future<void> _testAllServers() async {
    _isLoading.value = true;
    try {
      await _settingsService!.refreshServerStatus();
      _loadModels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('服务器测试完成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('测试失败: $e')));
      }
    } finally {
      _isLoading.value = false;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
