import 'package:flutter/material.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// 节点目录浏览器弹窗。
///
/// 以列表方式展示节点上某路径的一级子目录，支持逐层进入/返回上级，
/// 确认后返回所选目录的完整路径。
class NodeDirectoryPicker extends StatefulWidget {
  const NodeDirectoryPicker({
    super.key,
    required this.nodeId,
    required this.nodeSettingsService,
    this.initialPath = '/',
  });

  final String nodeId;
  final NodeSettingsService nodeSettingsService;
  final String initialPath;

  @override
  State<NodeDirectoryPicker> createState() => _NodeDirectoryPickerState();
}

class _NodeDirectoryPickerState extends State<NodeDirectoryPicker> {
  late String _currentPath;
  List<String> _entries = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath.trim().isEmpty ? '/' : widget.initialPath.trim();
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirs = await widget.nodeSettingsService.listNodeDirectories(
        nodeId: widget.nodeId,
        path: path,
      );
      if (mounted) {
        setState(() {
          _currentPath = path;
          _entries = dirs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
          _error = '无法访问目录: $e';
        });
      }
    }
  }

  void _navigateTo(String path) => _loadDirectory(path);

  void _navigateUp() {
    final parts = _currentPath.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]'));
    if (parts.length <= 1) {
      _loadDirectory('/');
      return;
    }
    parts.removeLast();
    final parent = parts.join('/');
    _loadDirectory(parent.isEmpty ? '/' : parent);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择目录'),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 当前路径展示
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.metrics.kSpace16,
                vertical: AppTheme.metrics.kSpace8,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: '上级目录',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _loading ? null : _navigateUp,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 目录列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _entries.isEmpty
                          ? Center(
                              child: Text(
                                '此目录下没有子目录',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : ListView.builder(
                              itemCount: _entries.length,
                              itemBuilder: (context, index) {
                                final entry = _entries[index];
                                final name = entry.split(RegExp(r'[/\\]')).last;
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder_rounded,
                                    size: 20,
                                  ),
                                  title: Text(name),
                                  subtitle: Text(
                                    entry,
                                    style: Theme.of(context).textTheme.labelSmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _navigateTo(entry),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          child: const Text('选择此目录'),
        ),
      ],
    );
  }
}
