import 'package:material_ui/material_ui.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class NovelImportDialogResult {
  final bool scanFolder;
  final OllamaModelOption? model;
  final bool preserveDirectoryStructure;

  const NovelImportDialogResult({
    required this.scanFolder,
    this.model,
    this.preserveDirectoryStructure = true,
  });
}

Future<NovelImportDialogResult?> showNovelImportDialog({
  required BuildContext context,
  required bool scanFolder,
  bool supportsDirectoryStructure = true,
}) {
  return showDialog<NovelImportDialogResult>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _NovelImportDialog(
      scanFolder: scanFolder,
      supportsDirectoryStructure: supportsDirectoryStructure,
    ),
  );
}

class _NovelImportDialog extends StatefulWidget {
  final bool scanFolder;
  final bool supportsDirectoryStructure;

  const _NovelImportDialog({
    required this.scanFolder,
    required this.supportsDirectoryStructure,
  });

  @override
  State<_NovelImportDialog> createState() => _NovelImportDialogState();
}

class _NovelImportDialogState extends State<_NovelImportDialog> {
  final List<OllamaModelOption> _models = <OllamaModelOption>[];
  String? _selectedModelId;
  bool _preserveDirectoryStructure = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = getIt<OllamaSettingsService>();
      await settings.init();
      final models = await settings.getModelOptions();
      if (!mounted) return;
      setState(() {
        _models
          ..clear()
          ..addAll(models);
        if (!_models.any((model) => model.id == _selectedModelId)) {
          _selectedModelId = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final selected = _models
        .where((model) => model.id == _selectedModelId)
        .firstOrNull;
    return AlertDialog(
      title: Text(widget.scanFolder ? '扫描小说文件夹' : '导入小说'),
      content: SizedBox(
        width: scaleW(460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '可选择已配置的 Ollama 模型，在导入后校准小说类型，并将含露骨性描写的书籍标记为 H。选择模型后将跳过关键词自动打标签。',
                style: AppTextStyles.body(context),
              ),
              SizedBox(height: m.kSpace12),
              DropdownButtonFormField<String>(
                initialValue: _selectedModelId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '使用大模型检测书籍（可选）',
                  hintText: '请选择大模型',
                  border: OutlineInputBorder(),
                ),
                items: _models
                    .map(
                      (model) => DropdownMenuItem<String>(
                        value: model.id,
                        child: Text(
                          model.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) => setState(() => _selectedModelId = value),
              ),
              if (widget.scanFolder && widget.supportsDirectoryStructure)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('按原目录创建文件夹', style: AppTextStyles.body(context)),
                  subtitle: Text(
                    '以所选文件夹为第一级，逐级保留其中的子目录结构。',
                    style: AppTextStyles.caption(context),
                  ),
                  value: _preserveDirectoryStructure,
                  onChanged: (value) =>
                      setState(() => _preserveDirectoryStructure = value),
                ),
              if (_loading)
                Padding(
                  padding: EdgeInsets.only(top: m.kSpace8),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: m.kSpace8),
                      Text(
                        '正在读取 Ollama 模型…',
                        style: AppTextStyles.caption(context),
                      ),
                    ],
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: m.kSpace8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '模型读取失败：$_error',
                          style: AppTextStyles.caption(context),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadModels,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              else if (_models.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: m.kSpace8),
                  child: Text(
                    '未发现可用模型，仍可直接导入。请先在 Ollama 设置中配置服务器。',
                    style: AppTextStyles.caption(context),
                  ),
                ),
              SizedBox(height: m.kSpace8),
              Text(
                selected == null
                    ? '未选择模型：导入后按现有关键词规则自动打标签。'
                    : '将使用 ${selected.model.name} 抽样检测开头、中部和结尾，并跳过关键词自动打标签；长书不会整本送入上下文。',
                style: AppTextStyles.caption(context),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).pop(
                  NovelImportDialogResult(
                    scanFolder: widget.scanFolder,
                    model: selected,
                    preserveDirectoryStructure: _preserveDirectoryStructure,
                  ),
                ),
          child: Text(widget.scanFolder ? '选择文件夹' : '选择文件'),
        ),
      ],
    );
  }
}
