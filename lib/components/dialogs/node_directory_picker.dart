import 'package:flutter/material.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

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

  /// 拼接路径：base 尾斜杠统一去掉，根目录下直接拼接。
  String _join(String base, String name) {
    final b = base.replaceAll(RegExp(r'[/\\]+$'), '');
    if (b.isEmpty) return '/$name';
    return '$b/$name';
  }

  Future<String?> _promptName(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 在当前路径下新建子目录并刷新列表。
  Future<void> _createFolder() async {
    final name = await _promptName('新建文件夹', '');
    if (name == null || name.isEmpty || !mounted) return;
    bool ok = false;
    try {
      ok = await widget.nodeSettingsService.createNodeDirectory(
        nodeId: widget.nodeId,
        path: _join(_currentPath, name),
      );
    } catch (e) {
      _showOpError('新建文件夹失败', e);
      return;
    }
    if (!mounted) return;
    if (ok) {
      await _loadDirectory(_currentPath);
    } else {
      _showOpError('新建文件夹失败', null);
    }
  }

  /// 重命名当前目录（根目录下禁用），成功后切换到新路径。
  Future<void> _renameFolder() async {
    final parts = _currentPath.replaceAll(RegExp(r'[/\\]+$'), '').split(RegExp(r'[/\\]'));
    if (parts.isEmpty) return;
    final currentName = parts.last;
    final newName = await _promptName('重命名文件夹', currentName);
    if (newName == null || newName.isEmpty || newName == currentName || !mounted) return;
    final parent = parts.sublist(0, parts.length - 1).join('/');
    final newPath = parent.isEmpty ? '/$newName' : '$parent/$newName';
    bool ok = false;
    try {
      ok = await widget.nodeSettingsService.renameNodeDirectory(
        nodeId: widget.nodeId,
        oldPath: _currentPath,
        newPath: newPath,
      );
    } catch (e) {
      _showOpError('重命名文件夹失败', e);
      return;
    }
    if (!mounted) return;
    if (ok) {
      await _loadDirectory(newPath);
    } else {
      _showOpError('重命名文件夹失败', null);
    }
  }

  /// 目录操作失败提示：带原因（节点版本过旧/网络异常等）。
  void _showOpError(String action, Object? error) {
    if (!mounted) return;
    final reason = error == null
        ? '操作未生效'
        : error.toString().split('\n').first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action：$reason（请确认节点已升级且可访问）')),
    );
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
                    icon: DrawIcon(StrokeIcons.arrowUpward),
                    tooltip: '上级目录',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _loading ? null : _navigateUp,
                  ),
                  IconButton(
                    icon: const Icon(Icons.create_new_folder, size: 18),
                    tooltip: '新建文件夹',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _loading ? null : _createFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                    tooltip: '重命名文件夹',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed:
                        _loading || _currentPath.trim() == '/' ? null : _renameFolder,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
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
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _entries.isEmpty
                  ? Center(child: Text('此目录下没有子目录', style: Theme.of(context).textTheme.bodySmall))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final name = entry.split(RegExp(r'[/\\]')).last;
                        return ListTile(
                          dense: true,
                          leading: DrawIcon(StrokeIcons.folder, size: AppTheme.metrics.iconSize20),
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          child: const Text('选择此目录'),
        ),
      ],
    );
  }
}
