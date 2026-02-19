import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:slime_works/src/rust/api/novel_reader.dart';
import 'package:slime_works/view_models/novel_library_viewmodel.dart';

class LibraryBookInfoDialog extends StatefulWidget {
  final NovelMetadata metadata;
  final NovelLibraryViewModel viewModel;

  const LibraryBookInfoDialog({super.key, required this.metadata, required this.viewModel});

  @override
  State<LibraryBookInfoDialog> createState() => _LibraryBookInfoDialogState();
}

class _LibraryBookInfoDialogState extends State<LibraryBookInfoDialog> {
  bool _editing = false;
  bool _saving = false;

  late TextEditingController _titleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _tagsCtrl; // 逗号分隔

  String? _pendingCoverPath; // 用户选择的新封面（本地路径）

  @override
  void initState() {
    super.initState();
    final m = widget.metadata;
    _titleCtrl = TextEditingController(text: m.title);
    _authorCtrl = TextEditingController(text: m.author ?? '');
    _notesCtrl = TextEditingController(text: m.notes ?? '');
    _tagsCtrl = TextEditingController(text: m.tags.join(', '));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _notesCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  // ── 选择封面 ──────────────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        setState(() => _pendingCoverPath = path);
      }
    }
  }

  // ── 保存 ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // 更新封面
      if (_pendingCoverPath != null) {
        await widget.viewModel.updateNovelCover(widget.metadata.id, _pendingCoverPath!);
      }
      // 更新文本信息
      final tagsRaw = _tagsCtrl.text.trim();
      final tags = tagsRaw.isEmpty
          ? <String>[]
          : tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      await widget.viewModel.updateNovelInfo(
        novelId: widget.metadata.id,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
        author: _authorCtrl.text.trim().isEmpty ? null : _authorCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        tags: tags,
      );
      if (mounted) setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── 工具方法 ──────────────────────────────────────────────────────────────

  String _formatSize(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  // ── 封面区域 ─────────────────────────────────────────────────────────────

  Widget _buildCover(BuildContext context) {
    final coverSource = _pendingCoverPath ?? widget.metadata.coverPath;
    final hasFile = coverSource != null && File(coverSource).existsSync();

    Widget coverWidget = hasFile
        ? Image.file(
            File(coverSource),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          )
        : Center(
            child: Icon(
              Icons.menu_book_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
          );

    return GestureDetector(
      onTap: _editing ? _pickCover : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          coverWidget,
          if (_editing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, color: Colors.white, size: 28),
                    SizedBox(height: 4),
                    Text('更换封面', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 信息行 ────────────────────────────────────────────────────────────────

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          // SelectableText 允许用户选中并复制内容
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = widget.metadata;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 头部：封面 + 主要信息 ──────────────────────────────────────
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // 封面
                  SizedBox(
                    width: 130,
                    height: double.infinity,
                    child: ClipRRect(child: _buildCover(context)),
                  ),
                  // 主要信息
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_editing) ...[
                            SelectableText(
                              m.title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 4),
                            if (m.author != null && m.author!.isNotEmpty)
                              SelectableText(
                                m.author!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                          ] else ...[
                            _editField('书名', _titleCtrl),
                            _editField('作者', _authorCtrl),
                          ],
                          const Spacer(),
                          // 格式 / 大小
                          Row(
                            children: [
                              _formatBadge(context, m.format == NovelFormat.epub ? 'EPUB' : 'TXT'),
                              const SizedBox(width: 8),
                              Text(
                                _formatSize(m.fileSize),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── 滚动信息区 ────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: _editing ? _buildEditBody() : _buildViewBody(m),
              ),
            ),

            const Divider(height: 1),

            // ── 底部按钮 ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_editing) ...[
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _editing = false;
                              _pendingCoverPath = null;
                              _titleCtrl.text = m.title;
                              _authorCtrl.text = m.author ?? '';
                              _notesCtrl.text = m.notes ?? '';
                              _tagsCtrl.text = m.tags.join(', ');
                            }),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded, size: 16),
                      label: const Text('保存'),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => setState(() => _editing = true),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('编辑'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewBody(NovelMetadata m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 进度
        _infoRow('阅读进度', '${(m.progress * 100).toStringAsFixed(1)}%'),
        // 添加时间
        _infoRow('添加时间', _formatDate(m.addedAt.toInt())),
        // 上次阅读
        if (m.lastReadAt != null) _infoRow('上次阅读', _formatDate(m.lastReadAt!.toInt())),
        // 标签
        if (m.tags.isNotEmpty) ...[const SizedBox(height: 4), _infoRow('标签', m.tags.join('  ·  '))],
        // 文件路径
        _infoRow('文件路径', m.filePath),
        // 备注
        if (m.notes != null && m.notes!.isNotEmpty) ...[
          const Divider(height: 20),
          const Text(
            '备注',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          SelectableText(m.notes!, style: const TextStyle(fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildEditBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_editField('标签（逗号分隔）', _tagsCtrl), _editField('备注', _notesCtrl, maxLines: 4)],
    );
  }

  Widget _formatBadge(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.primary),
      ),
    );
  }
}
