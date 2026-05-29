library;

/// Manga 屏蔽词管理对话框
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
enum MangaBlockWordType {
  /// 标题关键词屏蔽
  title,

  /// 分类屏蔽
  category,

  /// Tag 屏蔽
  tag,
}

const String _kBlockWordsKey = 'manga_block_words';

/// 屏蔽词配置（三类独立存储）
class MangaBlockWordsConfig {
  const MangaBlockWordsConfig({
    this.titleWords = const [],
    this.categoryWords = const [],
    this.tagWords = const [],
  });

  final List<String> titleWords;
  final List<String> categoryWords;
  final List<String> tagWords;

  factory MangaBlockWordsConfig.fromJson(Map<String, dynamic> json) => MangaBlockWordsConfig(
    titleWords: List<String>.from(json['title'] as List? ?? []),
    categoryWords: List<String>.from(json['category'] as List? ?? []),
    tagWords: List<String>.from(json['tag'] as List? ?? []),
  );

  Map<String, dynamic> toJson() => {
    'title': titleWords,
    'category': categoryWords,
    'tag': tagWords,
  };

  MangaBlockWordsConfig copyWith({
    List<String>? titleWords,
    List<String>? categoryWords,
    List<String>? tagWords,
  }) => MangaBlockWordsConfig(
    titleWords: titleWords ?? this.titleWords,
    categoryWords: categoryWords ?? this.categoryWords,
    tagWords: tagWords ?? this.tagWords,
  );

  bool get isEmpty => titleWords.isEmpty && categoryWords.isEmpty && tagWords.isEmpty;
}

// ==================== 服务工具类 ====================

/// 屏蔽词服务（静态方法，不需要实例化）
class MangaBlockWordsService {
  MangaBlockWordsService._();

  static MangaBlockWordsConfig? _cache;

  /// 加载屏蔽词配置（带内存缓存）
  static Future<MangaBlockWordsConfig> load() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kBlockWordsKey);
      if (raw == null || raw.isEmpty) {
        _cache = const MangaBlockWordsConfig();
        return _cache!;
      }
      _cache = MangaBlockWordsConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return _cache!;
    } catch (e) {
      _logger.error('加载屏蔽词失败: $e');
      return const MangaBlockWordsConfig();
    }
  }

  /// 保存屏蔽词配置
  static Future<void> save(MangaBlockWordsConfig config) async {
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
    required MangaBlockWordsConfig config,
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
Future<void> showMangaBlockWordsDialog(BuildContext context) {
  return showDialog(context: context, builder: (ctx) => const _BlockWordsDialog());
}

class _BlockWordsDialog extends StatefulWidget {
  const _BlockWordsDialog();

  @override
  State<_BlockWordsDialog> createState() => _BlockWordsDialogState();
}

class _BlockWordsDialogState extends State<_BlockWordsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MangaBlockWordsConfig _config = const MangaBlockWordsConfig();
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
    MangaBlockWordsService.invalidateCache();
    final config = await MangaBlockWordsService.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  Future<void> _addWord(MangaBlockWordType type) async {
    final controller = switch (type) {
      MangaBlockWordType.title => _titleInput,
      MangaBlockWordType.category => _categoryInput,
      MangaBlockWordType.tag => _tagInput,
    };
    final word = controller.text.trim();
    if (word.isEmpty) return;
    controller.clear();

    MangaBlockWordsConfig updated;
    switch (type) {
      case MangaBlockWordType.title:
        if (_config.titleWords.contains(word)) return;
        updated = _config.copyWith(titleWords: [..._config.titleWords, word]);
      case MangaBlockWordType.category:
        if (_config.categoryWords.contains(word)) return;
        updated = _config.copyWith(categoryWords: [..._config.categoryWords, word]);
      case MangaBlockWordType.tag:
        if (_config.tagWords.contains(word)) return;
        updated = _config.copyWith(tagWords: [..._config.tagWords, word]);
    }

    setState(() => _config = updated);
    await MangaBlockWordsService.save(updated);
  }

  Future<void> _removeWord(MangaBlockWordType type, String word) async {
    MangaBlockWordsConfig updated;
    switch (type) {
      case MangaBlockWordType.title:
        updated = _config.copyWith(titleWords: _config.titleWords.where((w) => w != word).toList());
      case MangaBlockWordType.category:
        updated = _config.copyWith(
          categoryWords: _config.categoryWords.where((w) => w != word).toList(),
        );
      case MangaBlockWordType.tag:
        updated = _config.copyWith(tagWords: _config.tagWords.where((w) => w != word).toList());
    }
    setState(() => _config = updated);
    await MangaBlockWordsService.save(updated);
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
                          onAdd: () => _addWord(MangaBlockWordType.title),
                          onRemove: (w) => _removeWord(MangaBlockWordType.title, w),
                        ),
                        _WordListTab(
                          words: _config.categoryWords,
                          inputController: _categoryInput,
                          hintText: '输入分类名称后按回车',
                          onAdd: () => _addWord(MangaBlockWordType.category),
                          onRemove: (w) => _removeWord(MangaBlockWordType.category, w),
                        ),
                        _WordListTab(
                          words: _config.tagWords,
                          inputController: _tagInput,
                          hintText: '输入 Tag 关键词后按回车',
                          onAdd: () => _addWord(MangaBlockWordType.tag),
                          onRemove: (w) => _removeWord(MangaBlockWordType.tag, w),
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
