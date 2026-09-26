import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appDescription = '一站式数字内容管理与创作平台';
  static const String _copyright = '© 2026 gleamslime.com';

  AppUpdateService get _service => getIt<AppUpdateService>();

  // 仅 macOS/Windows 支持原生自动更新
  bool get _supportsAutoUpdate => Platform.isMacOS || Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    return ScreenChrome(
      data: const ScreenChromeData(title: '关于'),
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace40,
              vertical: AppTheme.metrics.kSpace32,
            ),
            // 内层 Center 让滚动容器撑满窗口宽度，滚动条才贴着窗口右边缘；
            // 内容宽度仍由 ConstrainedBox 限制并居中。
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    _buildHeader(context),
                    SizedBox(height: AppTheme.metrics.kSpace32),
                    _buildDescription(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildVersionInfo(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildUpdateSection(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildTechStack(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildLinks(context),
                    SizedBox(height: AppTheme.metrics.kSpace32),
                    _buildCopyright(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Container(
          width: AppTheme.metrics.kSpace48 * 2,
          height: AppTheme.metrics.kSpace48 * 2,
          decoration: BoxDecoration(
            borderRadius: AppTheme.metrics.radius24,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [const Color(0xFF6B5CE7), const Color(0xFF9B8CE8)]
                  : [const Color(0xFFA89FEE), const Color(0xFFC8BFF8)],
            ),
            boxShadow: [
              BoxShadow(
                color: LightColors.primary.withAlpha(60),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: SvgPicture.asset(
              Assets.image.svg.topBarLogo,
              width: scaleW(100),
              height: scaleW(100),
              // 底板是紫色渐变，原图的深蓝描边压在上面几乎读不出来；
              // 资产已经去掉底色与投影，单色压平后就是干净的线稿
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
          ),
        ),
        SizedBox(height: AppTheme.metrics.kSpace20),
        Text(
          AppInfoService.appName,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: AppTheme.metrics.kSpace4),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace12,
            vertical: AppTheme.metrics.kSpace4,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(25),
            borderRadius: AppTheme.metrics.radius8,
          ),
          child: Text(
            AppInfoService.versionWithBuild,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _appDescription,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(180),
        height: 1.6,
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    final theme = Theme.of(context);
    return _AboutCard(
      child: Column(
        children: [
          _InfoRow(
            icon: StrokeIcons.infoOutline,
            label: '版本',
            value: '${AppInfoService.version} (${AppInfoService.buildNumber})',
          ),
          Divider(height: 1, color: theme.dividerColor),
          _InfoRow(icon: StrokeIcons.phoneAndroid, label: '平台', value: _platformName()),
          Divider(height: 1, color: theme.dividerColor),
          _InfoRow(icon: StrokeIcons.code, label: '框架', value: 'Flutter ${_flutterVersion()}'),
        ],
      ),
    );
  }

  Widget _buildUpdateSection(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: m.kSpace12),
          child: Text(
            '应用更新',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (!_supportsAutoUpdate)
          _AboutCard(
            child: Text(
              '当前平台不支持应用内自动更新，请前往 GitHub Releases 手动下载新版本',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(140),
                height: 1.5,
              ),
            ),
          )
        else
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAutoUpdateSwitch(context),
                Divider(height: 1, color: theme.dividerColor),
                _buildCheckUpdateButton(context),
              ],
            ),
          ),
      ],
    );
  }

  /// 自动更新开关：闲置检查 + 原生下载安装
  Widget _buildAutoUpdateSwitch(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;
    final brandColor = isDark ? DarkColors.primary : LightColors.primary;

    return Obx(() {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace10),
        child: Row(
          children: [
            DrawIcon(StrokeIcons.autorenew, size: m.iconSize20, color: brandColor),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动更新', style: theme.textTheme.bodyMedium),
                  SizedBox(height: m.kSpace2),
                  Text(
                    '闲置 5 分钟后自动检查 GitHub 新版本，发现更新自动下载安装',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace12),
            Switch(
              value: _service.autoUpdateEnabled.value,
              activeThumbColor: brandColor,
              onChanged: (v) async {
                await _service.setAutoUpdateEnabled(v);
                EasyLoading.showInfo(v ? '已开启自动更新' : '已关闭自动更新');
              },
            ),
          ],
        ),
      );
    });
  }

  /// 检查更新：展示上次检查结果并提供手动触发入口
  Widget _buildCheckUpdateButton(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final checking = _service.isChecking.value;
      final info = _service.updateInfo.value;
      return Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info != null) ...[
              Row(
                children: [
                  DrawIcon(StrokeIcons.newReleases,
                    size: m.iconSize16,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: m.kSpace6),
                  Expanded(
                    child: Text(
                      '发现新版本: v${info.version} (Build ${info.buildNumber})',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (info.description.isNotEmpty) ...[
                SizedBox(height: m.kSpace6),
                Text(
                  info.description,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(140),
                    height: 1.4,
                  ),
                ),
              ],
              SizedBox(height: m.kSpace12),
            ],
            Row(
              children: [
                DrawIcon(StrokeIcons.systemUpdateAlt,
                  size: m.iconSize20,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Text(
                    '发现新版本后会弹窗提示，也可手动检查',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(140),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: checking
                      ? null
                      : () async {
                          await _service.checkForUpdates(silent: false);
                          if (!_service.lastCheckHadUpdate) {
                            EasyLoading.showInfo('当前已是最新版本');
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
                      : DrawIcon(StrokeIcons.refresh, size: m.iconSize16),
                  label: Text(
                    checking ? '检查中...' : '检查更新',
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

  Widget _buildTechStack(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      const _TechItem(icon: '🦀', name: 'Rust', desc: '高性能核心引擎'),
      const _TechItem(icon: '🎯', name: 'Dart', desc: '跨平台 UI 框架'),
      const _TechItem(icon: '⚡', name: 'GetX', desc: '状态管理与依赖注入'),
      const _TechItem(icon: '🔗', name: 'GoRouter', desc: '声明式路由导航'),
    ];

    return _AboutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
            child: Text(
              '技术栈',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: AppTheme.metrics.kSpace8,
            runSpacing: AppTheme.metrics.kSpace8,
            children: items.map((item) => _buildTechChip(context, item)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTechChip(BuildContext context, _TechItem item) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace12,
        vertical: AppTheme.metrics.kSpace8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        borderRadius: AppTheme.metrics.radius8,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.icon, style: TextStyle(fontSize: AppTheme.metrics.fontSize13)),
          SizedBox(width: AppTheme.metrics.kSpace8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                item.desc,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(120),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLinks(BuildContext context) {
    final theme = Theme.of(context);
    return _AboutCard(
      child: Column(
        children: [
          _LinkRow(
            icon: StrokeIcons.language,
            label: '官方网站',
            value: 'gleamslime.com',
            onTap: () {},
          ),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(icon: StrokeIcons.code, label: 'GitHub', value: '查看源代码', onTap: () {}),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(icon: StrokeIcons.bugReport, label: '问题反馈', value: '提交 Issue', onTap: () {}),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(
            icon: StrokeIcons.description,
            label: '开源许可',
            value: '查看第三方许可',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: AppInfoService.appName,
                applicationVersion: '${AppInfoService.version}+${AppInfoService.buildNumber}',
                applicationIcon: Padding(
                  padding: EdgeInsets.all(AppTheme.metrics.kSpace12),
                  child: SvgPicture.asset(
                    Assets.image.svg.topBarLogo,
                    width: AppTheme.metrics.kSpace48,
                    colorFilter: ColorFilter.mode(theme.colorScheme.primary, BlendMode.srcIn),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCopyright(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          _copyright,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(100),
          ),
        ),
        SizedBox(height: AppTheme.metrics.kSpace4),
        Text(
          'Made with 💜 by GleamSlime',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(80),
          ),
        ),
      ],
    );
  }

  String _platformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Unknown';
  }

  String _flutterVersion() {
    return '3.x';
  }
}

class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final StrokeIcon icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace10),
      child: Row(
        children: [
          DrawIcon(icon, size: AppTheme.metrics.fontSize18, color: theme.colorScheme.primary),
          SizedBox(width: AppTheme.metrics.kSpace12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final StrokeIcon icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.metrics.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.metrics.kSpace10),
        child: Row(
          children: [
            DrawIcon(icon, size: AppTheme.metrics.fontSize18, color: theme.colorScheme.primary),
            SizedBox(width: AppTheme.metrics.kSpace12),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            DrawIcon(StrokeIcons.chevronRight,
              size: AppTheme.metrics.fontSize15,
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechItem {
  final String icon;
  final String name;
  final String desc;

  const _TechItem({required this.icon, required this.name, required this.desc});
}
