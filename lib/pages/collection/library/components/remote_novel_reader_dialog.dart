import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/novel_reader.dart';

class RemoteNovelReaderDialog extends StatefulWidget {
  final NovelMetadata metadata;
  final String nodeId;
  final String nodeName;

  const RemoteNovelReaderDialog({
    super.key,
    required this.metadata,
    required this.nodeId,
    required this.nodeName,
  });

  @override
  State<RemoteNovelReaderDialog> createState() => _RemoteNovelReaderDialogState();
}

class _RemoteNovelReaderDialogState extends State<RemoteNovelReaderDialog> {
  final NodeSettingsService _service = getIt<NodeSettingsService>();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _chapters = <Map<String, dynamic>>[];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final chapters = await _service.fetchNodeNovelContent(
        nodeId: widget.nodeId,
        filePath: widget.metadata.filePath,
      );
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _loading = false;
        _selected = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters.isEmpty ? null : _chapters[_selected];

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 960,
        height: 680,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: appMetrics.kSpace12,
                vertical: appMetrics.kSpace10,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.metadata.title}  ·  ${widget.nodeName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('加载失败: $_error'))
                  : Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: ListView.separated(
                            itemCount: _chapters.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final title = (_chapters[index]['title'] ?? '章节 ${index + 1}')
                                  .toString();
                              return ListTile(
                                selected: index == _selected,
                                title: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => setState(() => _selected = index),
                              );
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(appMetrics.kSpace12),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                (chapter?['content'] ?? '').toString(),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
