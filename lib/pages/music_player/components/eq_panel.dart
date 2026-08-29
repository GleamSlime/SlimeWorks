import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';

/// 均衡器面板
class EqPanel extends StatefulWidget {
  const EqPanel({super.key});

  @override
  State<EqPanel> createState() => _EqPanelState();
}

class _EqPanelState extends State<EqPanel> {
  /// 本地管理的频段增益值，不受 Obx 重建影响
  late List<double> _bands;

  /// 当前选中的预设 ID（本地缓存，用于检测切换）
  String? _lastPresetId;

  @override
  void initState() {
    super.initState();
    _bands = List.filled(10, 0.0);
    // 打开面板时加载均衡器预设
    final viewModel = Get.find<MusicPlayerViewModel>();
    viewModel.loadEqPresets();
  }

  /// 从预设同步 bands 到本地状态
  void _syncBandsFromPreset(music_api.EqualizerPresetInfo? preset) {
    for (int i = 0; i < 10; i++) {
      _bands[i] = preset != null && i < preset.bands.length
          ? preset.bands[i]
          : 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Get.find<MusicPlayerViewModel>();
    const freqLabels = ['32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

    return Obx(() {
      final presets = viewModel.eqPresets;
      final currentId = viewModel.currentEqPresetId.value;

      // 检测预设切换，从预设同步 bands
      if (currentId != _lastPresetId) {
        _lastPresetId = currentId;
        music_api.EqualizerPresetInfo? currentPreset;
        if (currentId != null) {
          for (final p in presets) {
            if (p.id == currentId) {
              currentPreset = p;
              break;
            }
          }
        }
        _syncBandsFromPreset(currentPreset);
      }

      return Padding(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('均衡器', style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: AppTheme.metrics.kSpace12),
            // 预设选择
            if (presets.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => SizedBox(width: AppTheme.metrics.kSpace8),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    final isSelected = preset.id == currentId;
                    return ChoiceChip(
                      label: Text(preset.name),
                      selected: isSelected,
                      onSelected: (_) {
                        viewModel.currentEqPresetId.value = preset.id;
                        // 应用预设到播放器
                        viewModel.applyEqBands(preset.bands.map((e) => e.toDouble()).toList());
                      },
                    );
                  },
                ),
              ),
            SizedBox(height: AppTheme.metrics.kSpace16),
            // 均衡器滑块
            SizedBox(
              height: 200,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(10, (i) {
                  return Column(
                    children: [
                      Text(
                        '${_bands[i] > 0 ? "+" : ""}${_bands[i].toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: _bands[i].clamp(-12.0, 12.0),
                            min: -12,
                            max: 12,
                            divisions: 24,
                            onChanged: (v) {
                              setState(() {
                                _bands[i] = v;
                              });
                              // 实时应用均衡器
                              viewModel.applyEqBands(List.from(_bands));
                            },
                          ),
                        ),
                      ),
                      Text(freqLabels[i], style: Theme.of(context).textTheme.bodySmall),
                    ],
                  );
                }),
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            // 保存预设按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _showSavePresetDialog(context, viewModel);
                  },
                  child: const Text('保存为预设'),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  void _showSavePresetDialog(BuildContext context, MusicPlayerViewModel viewModel) {
    final nameController = TextEditingController(text: '自定义预设');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存均衡器预设'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: '预设名称', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                viewModel.saveEqPreset(name, List.from(_bands));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
