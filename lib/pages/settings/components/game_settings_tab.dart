import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/game_library/models/game_library_models.dart';
import 'package:slime_works/view_models/game_library/game_library_settings_viewmodel.dart';

class GameSettingsTab extends StatefulWidget {
  const GameSettingsTab({super.key});

  @override
  State<GameSettingsTab> createState() => _GameSettingsTabState();
}

class _GameSettingsTabState extends State<GameSettingsTab> {
  GameLibrarySettingsViewModel? _viewModel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final vm = GameLibrarySettingsViewModel();
    await vm.onInitAsync();
    if (!mounted) return;
    setState(() {
      _viewModel = vm;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _viewModel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Obx(() {
      final GameLibrarySettings? settings = _viewModel!.settings.value;
      if (settings == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return ListView(
        padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
        children: <Widget>[
          Card(
            child: SwitchListTile(
              value: settings.autoTrackPlayTime,
              title: const Text('自动记录游玩时长'),
              subtitle: const Text('启动游戏时自动添加会话记录（演示版为估算时长）'),
              onChanged: (bool value) {
                _viewModel!.saveSettings(settings.copyWith(autoTrackPlayTime: value));
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              value: settings.autoSave,
              title: const Text('自动保存编辑'),
              subtitle: const Text('修改游戏详情后自动落盘'),
              onChanged: (bool value) {
                _viewModel!.saveSettings(settings.copyWith(autoSave: value));
              },
            ),
          ),
          Card(
            child: SwitchListTile(
              value: settings.enableDesktopLaunch,
              title: const Text('允许桌面端直接启动游戏'),
              subtitle: const Text('仅在 Windows/macOS/Linux 生效'),
              onChanged: (bool value) {
                _viewModel!.saveSettings(settings.copyWith(enableDesktopLaunch: value));
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('默认排序'),
              subtitle: Text(settings.defaultSort),
              trailing: DropdownButton<String>(
                value: settings.defaultSort,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'updatedAt_desc', child: Text('最近更新')),
                  DropdownMenuItem<String>(value: 'name_asc', child: Text('名称 A-Z')),
                  DropdownMenuItem<String>(value: 'rating_desc', child: Text('评分高到低')),
                  DropdownMenuItem<String>(value: 'last_played_desc', child: Text('最近游玩')),
                ],
                onChanged: (String? value) {
                  if (value != null) {
                    _viewModel!.saveSettings(settings.copyWith(defaultSort: value));
                  }
                },
              ),
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('说明：AI 分析相关能力按迁移要求已排除，保留游戏管理、分类、详情、统计和设置功能。'),
                  SizedBox(height: AppTheme.metrics.kSpace12),
                  Wrap(
                    spacing: AppTheme.metrics.kSpace8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: _exportBackup,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('导出备份'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _importBackup,
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('导入备份'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _exportBackup() async {
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: '导出游戏库备份',
      fileName: 'game_library_backup.json',
      lockParentWindow: true,
    );
    if (path == null) {
      return;
    }

    final String jsonText = _viewModel!.exportBackupJson();
    await File(path).writeAsString(jsonText);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到 $path')));
  }

  Future<void> _importBackup() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      dialogTitle: '导入游戏库备份',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      lockParentWindow: true,
    );
    final String? path = picked?.files.single.path;
    if (path == null) {
      return;
    }

    final String jsonText = await File(path).readAsString();
    await _viewModel!.importBackupJson(jsonText);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备份导入成功')));
  }
}
