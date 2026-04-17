import 'package:flutter/material.dart';
import 'package:slime_works/src/rust/api/module_manager.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 模块管理页面
class ModuleManagementScreen extends StatefulWidget {
  const ModuleManagementScreen({super.key});

  @override
  State<ModuleManagementScreen> createState() => _ModuleManagementScreenState();
}

class _ModuleManagementScreenState extends State<ModuleManagementScreen> {
  ModuleManager? _manager;
  ModuleLoader? _loader;
  List<InstalledModule> _modules = [];
  bool _isLoading = false;
  String? _error;
  String? _installDir;

  void _showSnack(String message, {Color? backgroundColor, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration ?? const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 获取应用支持目录
      final appDir = await getApplicationSupportDirectory();
      _installDir = '${appDir.path}/modules';

      // 确保目录存在
      await Directory(_installDir!).create(recursive: true);

      // 创建管理器和加载器
      _manager = createModuleManager(installDir: _installDir!);
      _loader = createModuleLoader(installDir: _installDir!);

      // 加载模块列表
      await _refreshModules();
    } catch (e) {
      setState(() {
        _error = '初始化失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshModules() async {
    if (_manager == null) return;

    try {
      final modules = await moduleListAll(manager: _manager!);
      debugPrint("Loaded modules: ${modules.length}");
      setState(() {
        _modules = modules;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = '加载模块列表失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _installModule(String moduleName) async {
    if (_manager == null) return;

    setState(() => _isLoading = true);

    try {
      await moduleInstall(
        manager: _manager!,
        moduleName: moduleName,
        version: null, // 安装最新版本
        lockVersion: false,
        autoLoad: true,
      );

      await _refreshModules();

      if (mounted) {
        _showSnack('模块 $moduleName 安装成功', backgroundColor: Colors.green);
      }
    } catch (e) {
      setState(() {
        _error = '安装模块失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _uninstallModule(String moduleName, String? version) async {
    if (_manager == null) return;

    setState(() => _isLoading = true);

    try {
      await moduleUninstall(manager: _manager!, moduleName: moduleName, version: version);

      await _refreshModules();

      if (mounted) {
        _showSnack('模块 $moduleName 卸载成功', backgroundColor: Colors.green);
      }
    } catch (e) {
      setState(() {
        _error = '卸载模块失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _checkUpdate(String moduleName) async {
    if (_manager == null) return;

    try {
      final newVersion = await moduleCheckUpdate(manager: _manager!, moduleName: moduleName);

      if (mounted) {
        if (newVersion != null) {
          _showSnack('模块 $moduleName 有新版本: $newVersion', duration: const Duration(seconds: 5));
        } else {
          _showSnack('模块 $moduleName 已是最新版本');
        }
      }
    } catch (e) {
      setState(() => _error = '检查更新失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部操作栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1)),
          ),
          child: Row(
            children: [
              Text('已安装模块: ${_modules.length}', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _refreshModules,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _showInstallDialog(),
                icon: const Icon(Icons.add),
                label: const Text('安装模块'),
              ),
            ],
          ),
        ),

        // 错误提示
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.red.shade100,
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _error = null),
                ),
              ],
            ),
          ),

        // 模块列表
        Expanded(
          child: _isLoading && _modules.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _modules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Theme.of(context).disabledColor),
                      const SizedBox(height: 16),
                      Text('暂无已安装的模块', style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showInstallDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('安装模块'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _modules.length,
                  itemBuilder: (context, index) {
                    final module = _modules[index];
                    return _buildModuleCard(module);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildModuleCard(InstalledModule module) {
    final isLoaded =
        _loader != null && moduleIsLoaded(loader: _loader!, moduleName: module.moduleName);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模块名称和状态
            Row(
              children: [
                Icon(
                  _getModuleIcon(module.moduleType),
                  size: 32,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            module.moduleName,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          if (module.isLocked)
                            const Chip(
                              label: Text('已锁定', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.symmetric(horizontal: 4),
                            ),
                          if (isLoaded)
                            const Chip(
                              label: Text('已加载', style: TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              backgroundColor: Colors.green,
                            ),
                        ],
                      ),
                      Text('版本: ${module.version}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'update',
                      child: Row(children: [Icon(Icons.update), SizedBox(width: 8), Text('检查更新')]),
                    ),
                    const PopupMenuItem(
                      value: 'reinstall',
                      child: Row(children: [Icon(Icons.refresh), SizedBox(width: 8), Text('重新安装')]),
                    ),
                    const PopupMenuItem(
                      value: 'uninstall',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('卸载', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'update':
                        _checkUpdate(module.moduleName);
                        break;
                      case 'reinstall':
                        _showReinstallDialog(module);
                        break;
                      case 'uninstall':
                        _showUninstallDialog(module);
                        break;
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 模块信息
            Row(
              children: [
                Expanded(child: _buildInfoItem('类型', _getModuleTypeName(module.moduleType))),
                Expanded(child: _buildInfoItem('大小', _formatFileSize(module.fileSize))),
                Expanded(child: _buildInfoItem('安装时间', module.installedAt)),
              ],
            ),
            const SizedBox(height: 8),

            // 文件路径
            Text(
              '路径: ${module.filePath}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
        ),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  IconData _getModuleIcon(ModuleType type) {
    switch (type) {
      case ModuleType.dynamicLibrary:
        return Icons.library_books;
      case ModuleType.executable:
        return Icons.terminal;
    }
  }

  String _getModuleTypeName(ModuleType type) {
    switch (type) {
      case ModuleType.dynamicLibrary:
        return '动态库';
      case ModuleType.executable:
        return '可执行';
    }
  }

  String _formatFileSize(BigInt bytes) {
    final kb = bytes ~/ BigInt.from(1024);
    final mb = kb ~/ BigInt.from(1024);

    if (mb > BigInt.zero) {
      return '${(bytes.toDouble() / 1024 / 1024).toStringAsFixed(2)} MB';
    } else if (kb > BigInt.zero) {
      return '$kb KB';
    } else {
      return '$bytes B';
    }
  }

  void _showInstallDialog() async {
    // 确保manager已初始化
    if (_manager == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('模块管理器未初始化')));
      return;
    }

    // 从Rust获取可用模块列表
    final List<AvailableModuleInfo> availableModules;
    try {
      availableModules = await moduleGetAvailable(manager: _manager!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取模块列表失败: $e')));
      }
      return;
    }

    if (availableModules.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可用的模块')));
      }
      return;
    }

    String? selectedModuleName;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装模块'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '选择模块', border: OutlineInputBorder()),
                items: availableModules.map((module) {
                  return DropdownMenuItem(
                    value: module.name,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(module.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (module.description.isNotEmpty)
                          Text(
                            module.description,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedModuleName = value),
              ),
              const SizedBox(height: 16),
              if (selectedModuleName != null) ...[
                Text(
                  '版本: ${availableModules.firstWhere((m) => m.name == selectedModuleName).version}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
              ],
              const Text('将安装最新版本的模块', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              if (selectedModuleName != null) {
                Navigator.of(context).pop();
                _installModule(selectedModuleName!);
              }
            },
            child: const Text('安装'),
          ),
        ],
      ),
    );
  }

  void _showUninstallDialog(InstalledModule module) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认卸载'),
        content: Text('确定要卸载模块 ${module.moduleName} (${module.version}) 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _uninstallModule(module.moduleName, module.version);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
  }

  void _showReinstallDialog(InstalledModule module) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新安装'),
        content: Text('确定要重新安装模块 ${module.moduleName} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (_manager != null) {
                setState(() => _isLoading = true);
                try {
                  await moduleReinstall(
                    manager: _manager!,
                    moduleName: module.moduleName,
                    version: null,
                    lockVersion: module.isLocked,
                    autoLoad: true,
                  );
                  await _refreshModules();
                  if (mounted) {
                    _showSnack('模块 ${module.moduleName} 重新安装成功', backgroundColor: Colors.green);
                  }
                } catch (e) {
                  setState(() {
                    _error = '重新安装失败: $e';
                    _isLoading = false;
                  });
                }
              }
            },
            child: const Text('重新安装'),
          ),
        ],
      ),
    );
  }
}
