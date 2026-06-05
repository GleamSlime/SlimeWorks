import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/src/rust/api/music_player.dart' as music_api;
import 'package:slime_works/view_models/music_player_viewmodel.dart';

/// 均衡器面板
class EqPanel extends StatelessWidget {
  const EqPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Get.find<MusicPlayerViewModel>();

    return Obx(() {
      final presets = viewModel.eqPresets;
      final currentId = viewModel.currentEqPresetId.value;

      // 10 段均衡器频率标签
      const freqLabels = ['32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

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
                  separatorBuilder: (_, __) => SizedBox(width: AppTheme.metrics.kSpace8),
                  itemBuilder: (context, index) {
                    final preset = presets[index];
                    final isSelected = preset.id == currentId;
                    return ChoiceChip(
                      label: Text(preset.name),
                      selected: isSelected,
                      onSelected: (_) {
                        viewModel.currentEqPresetId.value = preset.id;
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
                  // 获取当前预设的增益值
                  music_api.EqualizerPresetInfo? currentPreset;
                  if (currentId != null) {
                    for (final p in presets) {
                      if (p.id == currentId) {
                        currentPreset = p;
                        break;
                      }
                    }
                  }
                  final value = currentPreset != null && i < currentPreset.bands.length
                      ? currentPreset.bands[i]
                      : 0.0;

                  return Column(
                    children: [
                      Text(
                        '${value > 0 ? "+" : ""}${value.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Slider(
                            value: value.clamp(-12.0, 12.0),
                            min: -12,
                            max: 12,
                            divisions: 24,
                            onChanged: (v) {
                              // 实时调节（暂不保存到预设）
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
                viewModel.saveEqPreset(name, List.filled(10, 0.0));
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
