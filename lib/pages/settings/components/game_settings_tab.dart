import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/index.dart';
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

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(
            icon,
            size: m.iconSize12,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: TextStyle(
            fontSize: m.fontSize15,
            height: 1.4,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: m.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: child,
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace8),
      child: Row(
        children: [
          Container(
            width: m.kSpace32,
            height: m.kSpace32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(15),
              borderRadius: m.radius8,
            ),
            child: Icon(icon, size: m.iconSize16, color: theme.colorScheme.primary),
          ),
          SizedBox(width: m.kSpace12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                SizedBox(height: m.kSpace2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _viewModel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final m = AppTheme.metrics;

    return Obx(() {
      final GameLibrarySettings? settings = _viewModel!.settings.value;
      if (settings == null) {
        return const Center(child: CircularProgressIndicator());
      }

      return ListView(
        padding: EdgeInsets.all(m.kSpace16),
        children: <Widget>[
          _buildSectionTitle('功能开关', Icons.toggle_on_outlined),
          SizedBox(height: m.kSpace12),
          _buildSettingsCard(
            child: Column(
              children: [
                _buildSwitchRow(
                  title: '自动记录游玩时长',
                  subtitle: '启动游戏时自动添加会话记录（演示版为估算时长）',
                  value: settings.autoTrackPlayTime,
                  onChanged: (v) => _viewModel!.saveSettings(settings.copyWith(autoTrackPlayTime: v)),
                  icon: Icons.timer_outlined,
                ),
                Divider(height: m.kSpace8),
                _buildSwitchRow(
                  title: '自动保存编辑',
                  subtitle: '修改游戏详情后自动落盘',
                  value: settings.autoSave,
                  onChanged: (v) => _viewModel!.saveSettings(settings.copyWith(autoSave: v)),
                  icon: Icons.save_outlined,
                ),
                Divider(height: m.kSpace8),
                _buildSwitchRow(
                  title: '允许桌面端直接启动游戏',
                  subtitle: '仅在 Windows/macOS/Linux 生效',
                  value: settings.enableDesktopLaunch,
                  onChanged: (v) => _viewModel!.saveSettings(settings.copyWith(enableDesktopLaunch: v)),
                  icon: Icons.play_circle_outline,
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('排序与数据', Icons.sort_rounded),
          SizedBox(height: m.kSpace12),
          _buildSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: m.kSpace32,
                      height: m.kSpace32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withAlpha(15),
                        borderRadius: m.radius8,
                      ),
                      child: Icon(Icons.sort_rounded, size: m.iconSize16, color: Theme.of(context).colorScheme.primary),
                    ),
                    SizedBox(width: m.kSpace12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('默认排序', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                          SizedBox(height: m.kSpace2),
                          Text(settings.defaultSort, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withAlpha(120))),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
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
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('数据备份', Icons.backup_outlined),
          SizedBox(height: m.kSpace12),
          _buildSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '导出或导入游戏库数据，备份文件为 JSON 格式',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
                  ),
                ),
                SizedBox(height: m.kSpace12),
                Wrap(
                  spacing: m.kSpace8,
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
