import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class AboutSettingsTab extends StatefulWidget {
  const AboutSettingsTab({super.key});

  @override
  State<AboutSettingsTab> createState() => _AboutSettingsTabState();
}

class _AboutSettingsTabState extends State<AboutSettingsTab> {
  AppUpdateService get _service => getIt<AppUpdateService>();
  // 仅 macOS/Windows 支持原生自动更新
  bool get _supportsAutoUpdate => Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    // 桌面端宽屏 ScreenChrome 不嵌套 Scaffold，用 EasyLoading 替代 SnackBar
    EasyLoading.showInfo(text);
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
          child: Icon(icon, size: m.iconSize12, color: theme.colorScheme.primary),
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

  Widget _buildCard({required Widget child}) {
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

  Widget _buildVersionRow(String label, String value) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: m.fontSize13,
              color: theme.colorScheme.onSurface.withAlpha(140),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: m.fontSize13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoUpdateSwitch() {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final enabled = _service.autoUpdateEnabled.value;
      final isDark = theme.brightness == Brightness.dark;
      final brandColor = isDark ? DarkColors.primary : LightColors.primary;
      return _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.autorenew_rounded,
                  size: m.iconSize20,
                  color: brandColor,
                ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自动更新',
                        style: TextStyle(
                          fontSize: m.fontSize13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: m.kSpace2),
                      Text(
                        '闲置 5 分钟后自动检查 GitHub 新版本，发现更新自动下载安装',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          height: 1.4,
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: brandColor,
                  onChanged: (v) async {
                    await _service.setAutoUpdateEnabled(v);
                    _showSnack(v ? '已开启自动更新' : '已关闭自动更新');
                  },
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCheckButton() {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final checking = _service.isChecking.value;
      final info = _service.updateInfo.value;
      return _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info != null) ...[
              Row(
                children: [
                  Icon(
                    Icons.new_releases_rounded,
                    size: m.iconSize16,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: m.kSpace6),
                  Text(
                    '发现新版本: v${info.version} (Build ${info.buildNumber})',
                    style: TextStyle(
                      fontSize: m.fontSize13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              if (info.description.isNotEmpty) ...[
                SizedBox(height: m.kSpace6),
                Text(
                  info.description,
                  style: TextStyle(
                    fontSize: m.fontSize12,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withAlpha(140),
                  ),
                ),
              ],
              SizedBox(height: m.kSpace12),
            ],
            Row(
              children: [
                FilledButton.icon(
                  onPressed: checking
                      ? null
                      : () async {
                          await _service.checkForUpdates(silent: false);
                          if (!_service.lastCheckHadUpdate) {
                            _showSnack('当前已是最新版本');
                          }
                        },
                  icon: checking
                      ? SizedBox(
                          width: m.iconSize16,
                          height: m.iconSize16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Icon(Icons.refresh_rounded, size: m.iconSize16),
                  label: Text(
                    checking ? '检查中...' : '立即检查更新',
                    style: TextStyle(fontSize: m.fontSize13),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return SingleChildScrollView(
      padding: EdgeInsets.all(m.kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('应用信息', Icons.info_outline_rounded),
          SizedBox(height: m.kSpace12),
          _buildCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVersionRow('应用名称', AppInfoService.appName),
                _buildVersionRow('版本号', AppInfoService.version),
                _buildVersionRow('构建号', AppInfoService.buildNumber),
                _buildVersionRow(
                  '完整版本',
                  AppInfoService.versionWithBuild,
                ),
                _buildVersionRow('运行平台', _platformLabel()),
              ],
            ),
          ),
          if (_supportsAutoUpdate) ...[
            SizedBox(height: m.kSpace24),
            _buildSectionTitle('自动更新', Icons.system_update_alt_rounded),
            SizedBox(height: m.kSpace12),
            _buildAutoUpdateSwitch(),
            SizedBox(height: m.kSpace12),
            _buildCheckButton(),
          ] else ...[
            SizedBox(height: m.kSpace24),
            _buildSectionTitle('应用更新', Icons.system_update_alt_rounded),
            SizedBox(height: m.kSpace12),
            _buildCard(
              child: Text(
                '当前平台不支持应用内自动更新，请前往 GitHub Releases 手动下载新版本',
                style: TextStyle(
                  fontSize: m.fontSize12,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _platformLabel() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }
}
