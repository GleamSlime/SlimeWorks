library;

/// PicACG 屏蔽词管理对话框
///
/// 支持按「分类」「标题」「Tag」三类屏蔽词管理
/// 数据存储于 SharedPreferences，应用于搜索结果的客户端过滤

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/core/utils/size_utils.dart';
const Loggers _logger = Loggers(name: '屏蔽词');

// ==================== 数据模型 ====================

/// 屏蔽词类型
enum PicAcgBlockWordType {
  /// 标题关键词屏蔽
  title,

  /// 分类屏蔽
  category,

  /// Tag 屏蔽
  tag,
}

const String _kBlockWordsKey = 'picacg_block_words';

/// 屏蔽词配置（三类独立存储）
class PicAcgBlockWordsConfig {
  const PicAcgBlockWordsConfig({
    this.titleWords = const [],
    this.categoryWords = const [],
    this.tagWords = const [],
  });

  final List<String> titleWords;
  final List<String> categoryWords;
  final List<String> tagWords;

  factory PicAcgBlockWordsConfig.fromJson(Map<String, dynamic> json) => PicAcgBlockWordsConfig(
    titleWords: List<String>.from(json['title'] as List? ?? []),
    categoryWords: List<String>.from(json['category'] as List? ?? []),
    tagWords: List<String>.from(json['tag'] as List? ?? []),
  );

  Map<String, dynamic> toJson() => {
    'title': titleWords,
    'category': categoryWords,
    'tag': tagWords,
  };

  PicAcgBlockWordsConfig copyWith({
    List<String>? titleWords,
    List<String>? categoryWords,
    List<String>? tagWords,
  }) => PicAcgBlockWordsConfig(
    titleWords: titleWords ?? this.titleWords,
    categoryWords: categoryWords ?? this.categoryWords,
    tagWords: tagWords ?? this.tagWords,
  );

  bool get isEmpty => titleWords.isEmpty && categoryWords.isEmpty && tagWords.isEmpty;
}

// ==================== 服务工具类 ====================

/// 屏蔽词服务（静态方法，不需要实例化）
class PicAcgBlockWordsService {
  PicAcgBlockWordsService._();

  static PicAcgBlockWordsConfig? _cache;

  /// 加载屏蔽词配置（带内存缓存）
  static Future<PicAcgBlockWordsConfig> load() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBlockWordsKey);
      if (raw == null || raw.isEmpty) {
        _cache = const PicAcgBlockWordsConfig();
        return _cache!;
      }
      _cache = PicAcgBlockWordsConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _cache!;
    } catch (e) {
      _logger.error('加载屏蔽词失败: $e');
      return const PicAcgBlockWordsConfig();
    }
  }

  /// 保存屏蔽词配置
  static Future<void> save(PicAcgBlockWordsConfig config) async {
    try {
      _cache = config;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBlockWordsKey, jsonEncode(config.toJson()));
    } catch (e) {
      _logger.error('保存屏蔽词失败: $e');
    }
  }

  /// 清除内存缓存（修改后需调用）
  static void invalidateCache() {
    _cache = null;
  }

  /// 检查漫画是否应被屏蔽
  /// [title] 漫画标题  [categories] 漫画分类列表  [tags] Tag 列表
  static bool shouldBlock({
    required String title,
    required List<String> categories,
    required List<String> tags,
    required PicAcgBlockWordsConfig config,
  }) {
    final titleLower = title.toLowerCase();
    for (final w in config.titleWords) {
      if (titleLower.contains(w.toLowerCase())) return true;
    }
    for (final w in config.categoryWords) {
      if (categories.any((c) => c.toLowerCase().contains(w.toLowerCase()))) return true;
    }
    for (final w in config.tagWords) {
      if (tags.any((t) => t.toLowerCase().contains(w.toLowerCase()))) return true;
    }
    return false;
  }
}

// ==================== UI 对话框 ====================

/// 展示屏蔽词管理对话框
Future<void> showPicAcgBlockWordsDialog(BuildContext context) {
  return showDialog(context: context, builder: (ctx) => const _BlockWordsDialog());
}

class _BlockWordsDialog extends StatefulWidget {
  const _BlockWordsDialog();

  @override
  State<_BlockWordsDialog> createState() => _BlockWordsDialogState();
}

class _BlockWordsDialogState extends State<_BlockWordsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PicAcgBlockWordsConfig _config = const PicAcgBlockWordsConfig();
  bool _loading = true;

  /// 各 Tab 输入控制器
  final _titleInput = TextEditingController();
  final _categoryInput = TextEditingController();
  final _tagInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleInput.dispose();
    _categoryInput.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    PicAcgBlockWordsService.invalidateCache();
    final config = await PicAcgBlockWordsService.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _addWord(PicAcgBlockWordType type) async {
    final controller = switch (type) {
      PicAcgBlockWordType.title => _titleInput,
      PicAcgBlockWordType.category => _categoryInput,
      PicAcgBlockWordType.tag => _tagInput,
    };
    final word = controller.text.trim();
    if (word.isEmpty) return;
    controller.clear();

    PicAcgBlockWordsConfig updated;
    switch (type) {
      case PicAcgBlockWordType.title:
        if (_config.titleWords.contains(word)) return;
        updated = _config.copyWith(titleWords: [..._config.titleWords, word]);
      case PicAcgBlockWordType.category:
        if (_config.categoryWords.contains(word)) return;
        updated = _config.copyWith(categoryWords: [..._config.categoryWords, word]);
      case PicAcgBlockWordType.tag:
        if (_config.tagWords.contains(word)) return;
        updated = _config.copyWith(tagWords: [..._config.tagWords, word]);
    }

    setState(() => _config = updated);
    await PicAcgBlockWordsService.save(updated);
  }

  Future<void> _removeWord(PicAcgBlockWordType type, String word) async {
    PicAcgBlockWordsConfig updated;
    switch (type) {
      case PicAcgBlockWordType.title:
        updated = _config.copyWith(titleWords: _config.titleWords.where((w) => w != word).toList());
      case PicAcgBlockWordType.category:
        updated = _config.copyWith(
          categoryWords: _config.categoryWords.where((w) => w != word).toList(),
        );
      case PicAcgBlockWordType.tag:
        updated = _config.copyWith(tagWords: _config.tagWords.where((w) => w != word).toList());
    }
    setState(() => _config = updated);
    await PicAcgBlockWordsService.save(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scaleW(480), maxHeight: scaleW(500)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(metrics.kSpace20, metrics.kSpace20, metrics.kSpace8, 0),
              child: Row(
                children: [
                  const Icon(Icons.block_outlined),
                  SizedBox(width: metrics.kSpace8),
                  Text('屏蔽词管理', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: '标题屏蔽'),
                Tab(text: '分类屏蔽'),
                Tab(text: 'Tag 屏蔽'),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _WordListTab(
                          words: _config.titleWords,
                          inputController: _titleInput,
                          hintText: '输入标题关键词后按回车',
                          onAdd: () => _addWord(PicAcgBlockWordType.title),
                          onRemove: (w) => _removeWord(PicAcgBlockWordType.title, w),
                        ),
                        _WordListTab(
                          words: _config.categoryWords,
                          inputController: _categoryInput,
                          hintText: '输入分类名称后按回车',
                          onAdd: () => _addWord(PicAcgBlockWordType.category),
                          onRemove: (w) => _removeWord(PicAcgBlockWordType.category, w),
                        ),
                        _WordListTab(
                          words: _config.tagWords,
                          inputController: _tagInput,
                          hintText: '输入 Tag 关键词后按回车',
                          onAdd: () => _addWord(PicAcgBlockWordType.tag),
                          onRemove: (w) => _removeWord(PicAcgBlockWordType.tag, w),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(metrics.kSpace12),
              child: Text(
                '屏蔽词在搜索结果中进行客户端过滤',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个分类 Tab 的词列表 + 输入框
class _WordListTab extends StatelessWidget {
  const _WordListTab({
    required this.words,
    required this.inputController,
    required this.hintText,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> words;
  final TextEditingController inputController;
  final String hintText;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = appMetrics;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(metrics.kSpace12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: inputController,
                  decoration: InputDecoration(
                    hintText: hintText,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: metrics.kSpace12,
                      vertical: metrics.kSpace8,
                    ),
                  ),
                  onSubmitted: (_) => onAdd(),
                  textInputAction: TextInputAction.done,
                ),
              ),
              SizedBox(width: metrics.kSpace8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: onAdd,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: words.isEmpty
              ? Center(
                  child: Text(
                    '暂无屏蔽词',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: metrics.kSpace12),
                  itemCount: words.length,
                  itemBuilder: (ctx, i) {
                    final word = words[i];
                    return ListTile(
                      dense: true,
                      title: Text(word, style: theme.textTheme.bodyMedium),
                      trailing: IconButton(
                        icon: Icon(Icons.close, size: scaleW(16), color: theme.colorScheme.error),
                        onPressed: () => onRemove(word),
                      ),
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
