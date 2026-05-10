import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/view_models/novel_reader_viewmodel.dart';

/// 翻译配置面板
class TranslationConfigPanel extends StatefulWidget {
  final NovelReaderViewModel viewModel;

  const TranslationConfigPanel({super.key, required this.viewModel});

  @override
  State<TranslationConfigPanel> createState() => _TranslationConfigPanelState();
}

class _TranslationConfigPanelState extends State<TranslationConfigPanel> {
  OllamaSettingsService? _settingsService;

  final RxBool _isLoading = false.obs;
  final RxBool _isReady = false.obs;
  final RxList<OllamaModel> _models = <OllamaModel>[].obs;

  String? _selectedModel;
  TranslationLanguagePair _selectedLanguagePair = TranslationLanguagePair.presets[0];
  bool _useStreaming = false;
  int _timeoutSeconds = 60;

  @override
  void initState() {
    super.initState();
    // 从 ViewModel 读取当前配置
    _selectedModel = widget.viewModel.translationModel.value;
    _selectedLanguagePair = widget.viewModel.translationLanguagePair.value;
    _useStreaming = widget.viewModel.useStreamingTranslation.value;
    _timeoutSeconds = widget.viewModel.translationTimeout.value;
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      final settingsService = getIt.get<OllamaSettingsService>();
      await settingsService.init();

      if (!mounted) return;
      _settingsService = settingsService;

      // 加载模型列表
      await _loadModels();

      // 设置默认模型
      if (_selectedModel == null || _selectedModel!.isEmpty) {
        if (_settingsService!.defaultModel.value.isNotEmpty) {
          _selectedModel = _settingsService!.defaultModel.value;
        } else if (_models.isNotEmpty) {
          _selectedModel = _models.first.name;
        }
      }

      _isReady.value = true;
    } catch (e) {
      const Loggers(name: 'TranslationConfig').error('初始化翻译配置失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('初始化翻译配置失败: $e')));
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
      const Loggers(name: 'TranslationConfig').error('加载模型列表失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载模型列表失败: $e')));
      }
    } finally {
      _isLoading.value = false;
    }
  }

  void _confirmConfig() {
    if (_selectedModel == null || _selectedModel!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择翻译模型')));
      return;
    }

    // 保存配置到 ViewModel
    widget.viewModel.translationModel.value = _selectedModel;
    widget.viewModel.translationLanguagePair.value = _selectedLanguagePair;
    widget.viewModel.useStreamingTranslation.value = _useStreaming;
    widget.viewModel.translationTimeout.value = _timeoutSeconds;

    // 关闭面板
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!_isReady.value) {
        return Container(
          padding: EdgeInsets.all(appMetrics.paddingLarge),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.3,
            maxWidth: scaleW(400),
          ),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      return _buildContent(context);
    });
  }

  Widget _buildContent(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(appMetrics.paddingLarge),
      constraints: BoxConstraints(
        maxWidth: scaleW(500),
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('翻译配置', style: Theme.of(context).textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          SizedBox(height: appMetrics.spacingLarge),

          // 说明文字
          Text(
            '配置完成后，点击确定开启自动翻译。翻译将自动应用到当前及后续章节。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
          ),
          SizedBox(height: appMetrics.spacingLarge),

          // 模型选择
          Obx(() {
            return DropdownButtonFormField<String>(
              initialValue: _selectedModel,
              decoration: const InputDecoration(labelText: '选择翻译模型', border: OutlineInputBorder()),
              items: _models
                  .map(
                    (model) => DropdownMenuItem(
                      value: model.name,
                      child: Text(model.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedModel = value;
                });
              },
            );
          }),
          SizedBox(height: appMetrics.spacingMedium),

          // 语言对选择
          DropdownButtonFormField<TranslationLanguagePair>(
            initialValue: _selectedLanguagePair,
            decoration: const InputDecoration(labelText: '翻译语言对', border: OutlineInputBorder()),
            items: TranslationLanguagePair.presets
                .map((pair) => DropdownMenuItem(value: pair, child: Text(pair.displayName)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedLanguagePair = value;
                });
              }
            },
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 超时时间设置
          Row(
            children: [
              Expanded(
                child: Text(
                  '翻译超时时间：$_timeoutSeconds秒',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          Slider(
            value: _timeoutSeconds.toDouble(),
            min: 10,
            max: 300,
            divisions: 29,
            label: '$_timeoutSeconds秒',
            onChanged: (value) {
              setState(() {
                _timeoutSeconds = value.toInt();
              });
            },
          ),
          Text(
            '建议：30-120秒。太短可能导致翻译失败，太长会影响体验。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 流式输出开关
          SwitchListTile(
            title: const Text('启用流式输出'),
            subtitle: const Text('流式输出可能会导致小说翻译结构重复，建议关闭'),
            value: _useStreaming,
            onChanged: (value) {
              setState(() {
                _useStreaming = value;
              });
            },
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 刷新按钮
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('刷新模型列表'),
                onPressed: _loadModels,
              ),
            ],
          ),
          SizedBox(height: appMetrics.spacingLarge),

          // 确定按钮
          ElevatedButton(
            onPressed: _confirmConfig,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: appMetrics.paddingMedium),
            ),
            child: const Text('确定并开启自动翻译'),
          ),
        ],
      ),
    );
  }
}
