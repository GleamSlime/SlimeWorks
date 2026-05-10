import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/ollama/ollama_models.dart';
import 'package:slime_works/core/services/ollama/ollama_service.dart';
import 'package:slime_works/core/services/ollama/ollama_settings_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/utils/logger.dart';

/// 翻译面板组件
class TranslationPanel extends StatefulWidget {
  final String selectedText;

  const TranslationPanel({super.key, required this.selectedText});

  @override
  State<TranslationPanel> createState() => _TranslationPanelState();
}

class _TranslationPanelState extends State<TranslationPanel> {
  OllamaService? _ollamaService;
  OllamaSettingsService? _settingsService;

  final RxBool _isLoading = false.obs;
  final RxBool _isReady = false.obs;
  final RxBool _isTranslating = false.obs;
  final RxString _translatedText = ''.obs;
  final RxList<OllamaModel> _models = <OllamaModel>[].obs;

  String? _selectedModel;
  TranslationLanguagePair _selectedLanguagePair = TranslationLanguagePair.presets[0];

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      final ollamaService = getIt.get<OllamaService>();
      final settingsService = getIt.get<OllamaSettingsService>();
      await settingsService.init();

      if (!mounted) return;
      _ollamaService = ollamaService;
      _settingsService = settingsService;

      // 加载模型列表
      await _loadModels();

      // 设置默认模型
      if (_settingsService!.defaultModel.value.isNotEmpty) {
        _selectedModel = _settingsService!.defaultModel.value;
      } else if (_models.isNotEmpty) {
        _selectedModel = _models.first.name;
      }

      _isReady.value = true;
    } catch (e) {
      const Loggers(name: 'Translation').error('初始化翻译服务失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('初始化翻译服务失败: $e')));
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
      const Loggers(name: 'Translation').error('加载模型列表失败', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载模型列表失败: $e')));
      }
    } finally {
      _isLoading.value = false;
    }
  }

  Future<void> _translate() async {
    if (_selectedModel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择翻译模型')));
      return;
    }

    if (widget.selectedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有要翻译的文本')));
      return;
    }

    _isTranslating.value = true;
    _translatedText.value = '';

    const Loggers(
      name: 'Translation',
    ).info('开始翻译, model=$_selectedModel, lang=${_selectedLanguagePair.displayName}');

    try {
      // 添加超时保护以防长时间无响应
      final future = _ollamaService!.translate(
        model: _selectedModel!,
        text: widget.selectedText,
        languagePair: _selectedLanguagePair,
        onChunk: (chunk) {
          _translatedText.value += chunk;
          const Loggers(name: 'Translation').info('收到 chunk: ${chunk.replaceAll('\n', '')}');
        },
      );

      final result = await future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('翻译请求超时');
        },
      );

      const Loggers(name: 'Translation').info('翻译完成, result length=${result.length}');

      if (_translatedText.value.isEmpty) {
        _translatedText.value = result;
      }
    } catch (e, st) {
      const Loggers(name: 'Translation').error('翻译失败', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('翻译失败: $e')));
      }
    } finally {
      _isTranslating.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!_isReady.value) {
        return Container(
          padding: EdgeInsets.all(appMetrics.paddingLarge),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
            maxWidth: MediaQuery.of(context).size.width * 0.5,
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
        maxHeight: MediaQuery.of(context).size.height * 0.8,
        maxWidth: MediaQuery.of(context).size.width * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('文本翻译', style: Theme.of(context).textTheme.titleLarge),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 模型选择和语言对选择
          Row(
            children: [
              Expanded(
                child: Obx(() {
                  return DropdownButtonFormField<String>(
                    initialValue: _selectedModel,
                    decoration: const InputDecoration(
                      labelText: '选择模型',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _models
                        .map(
                          (model) => DropdownMenuItem(
                            value: model.name,
                            child: Text(model.name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _isTranslating.value
                        ? null
                        : (value) {
                            setState(() {
                              _selectedModel = value;
                            });
                          },
                  );
                }),
              ),
              SizedBox(width: appMetrics.spacingMedium),
              Expanded(
                child: DropdownButtonFormField<TranslationLanguagePair>(
                  initialValue: _selectedLanguagePair,
                  decoration: const InputDecoration(
                    labelText: '语言对',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: TranslationLanguagePair.presets
                      .map((pair) => DropdownMenuItem(value: pair, child: Text(pair.displayName)))
                      .toList(),
                  onChanged: _isTranslating.value
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedLanguagePair = value;
                            });
                          }
                        },
                ),
              ),
              SizedBox(width: appMetrics.spacingMedium),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isTranslating.value ? null : _loadModels,
                tooltip: '刷新模型列表',
              ),
            ],
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 原文
          Expanded(
            child: Container(
              padding: EdgeInsets.all(appMetrics.paddingMedium),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: AppTheme.metrics.radius8,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.selectedText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          SizedBox(height: appMetrics.spacingMedium),

          // 翻译按钮
          Obx(() {
            return ElevatedButton.icon(
              onPressed: _isTranslating.value ? null : _translate,
              icon: _isTranslating.value
                  ? SizedBox(
                      width: scaleW(16),
                      height: scaleW(16),
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate),
              label: Text(_isTranslating.value ? '翻译中...' : '开始翻译'),
            );
          }),
          SizedBox(height: appMetrics.spacingMedium),

          // 译文
          Obx(() {
            if (_translatedText.value.isEmpty) {
              return Container(
                padding: EdgeInsets.all(appMetrics.paddingLarge),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: AppTheme.metrics.radius8,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                child: Center(
                  child: Text('翻译结果将显示在这里', style: TextStyle(color: Theme.of(context).hintColor)),
                ),
              );
            }

            return Expanded(
              child: Container(
                padding: EdgeInsets.all(appMetrics.paddingMedium),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: AppTheme.metrics.radius8,
                  color: Theme.of(context).cardColor,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _translatedText.value,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
