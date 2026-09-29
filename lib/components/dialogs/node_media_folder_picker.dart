import 'package:flutter/material.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 节点媒体库文件夹层级选择器。
///
/// 以列表方式展示媒体库逻辑文件夹（id/name/parent_id），
/// 支持逐层进入子文件夹/返回上级，确认后返回所选文件夹的 (folderId, 路径标题)。
/// folderId 为空字符串表示媒体库根目录。
class NodeMediaFolderPicker extends StatefulWidget {
  const NodeMediaFolderPicker({
    super.key,
    required this.nodeId,
    required this.nodeSettingsService,
  });

  final String nodeId;
  final NodeSettingsService nodeSettingsService;

  @override
  State<NodeMediaFolderPicker> createState() => _NodeMediaFolderPickerState();
}

class _NodeMediaFolderPickerState extends State<NodeMediaFolderPicker> {
  List<Map<String, dynamic>> _folders = [];
  final List<Map<String, dynamic>> _pathStack = []; // 进入过的文件夹栈（不含当前层）
  bool _loading = false;
  String? _error;

  String get _currentId =>
      _pathStack.isEmpty ? '' : (_pathStack.last['id'] ?? '').toString();

  String get _pathLabel {
    if (_pathStack.isEmpty) return '媒体库根目录';
    return _pathStack.map((f) => (f['name'] ?? '').toString()).join(' / ');
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final folders = await widget.nodeSettingsService.fetchNodeMediaFolders(
        widget.nodeSettingsService.getNodeById(widget.nodeId)!,
      );
      if (mounted) {
        setState(() {
          _folders = folders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法加载媒体库文件夹: $e';
        });
      }
    }
  }

  /// 当前层的子文件夹：parent_id 等于当前文件夹 id（根层为 null/空）。
  List<Map<String, dynamic>> get _children => _folders.where((f) {
        final pid = (f['parent_id'] as String?) ?? '';
        return pid == _currentId && (f['id'] ?? '').toString().isNotEmpty;
      }).toList();

  void _enterFolder(Map<String, dynamic> folder) {
    setState(() => _pathStack.add(folder));
  }

  void _navigateUp() {
    setState(() {
      if (_pathStack.isNotEmpty) _pathStack.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    return AlertDialog(
      title: const Text('选择媒体库文件夹'),
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
                    tooltip: '上级文件夹',
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _pathStack.isEmpty ? null : _navigateUp,
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  Expanded(
                    child: Text(
                      _pathLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 文件夹列表
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
                  : children.isEmpty
                  ? Center(
                      child: Text(
                        '此文件夹下没有子文件夹',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      itemCount: children.length,
                      itemBuilder: (context, index) {
                        final f = children[index];
                        return ListTile(
                          dense: true,
                          leading: DrawIcon(StrokeIcons.folder, size: AppTheme.metrics.iconSize20),
                          title: Text((f['name'] ?? '').toString()),
                          onTap: () => _enterFolder(f),
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
          onPressed: () => Navigator.of(context).pop((_currentId, _pathLabel)),
          child: const Text('选择此文件夹'),
        ),
      ],
    );
  }
}
