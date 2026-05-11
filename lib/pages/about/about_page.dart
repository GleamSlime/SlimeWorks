import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/gen/assets.gen.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _appDescription = '一站式数字内容管理与创作平台';
  static const String _copyright = '© 2026 gleamslime.com';

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
              // colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
            icon: Icons.info_outline,
            label: '版本',
            value: '${AppInfoService.version} (${AppInfoService.buildNumber})',
          ),
          Divider(height: 1, color: theme.dividerColor),
          _InfoRow(icon: Icons.phone_android_outlined, label: '平台', value: _platformName()),
          Divider(height: 1, color: theme.dividerColor),
          _InfoRow(icon: Icons.code_outlined, label: '框架', value: 'Flutter ${_flutterVersion()}'),
        ],
      ),
    );
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
            icon: Icons.language_outlined,
            label: '官方网站',
            value: 'gleamslime.com',
            onTap: () {},
          ),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(icon: Icons.code_outlined, label: 'GitHub', value: '查看源代码', onTap: () {}),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(icon: Icons.bug_report_outlined, label: '问题反馈', value: '提交 Issue', onTap: () {}),
          Divider(height: 1, color: theme.dividerColor),
          _LinkRow(
            icon: Icons.description_outlined,
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
  final IconData icon;
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
          Icon(icon, size: AppTheme.metrics.fontSize18, color: theme.colorScheme.primary),
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
  final IconData icon;
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
            Icon(icon, size: AppTheme.metrics.fontSize18, color: theme.colorScheme.primary),
            SizedBox(width: AppTheme.metrics.kSpace12),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
            ),
            SizedBox(width: AppTheme.metrics.kSpace4),
            Icon(
              Icons.chevron_right,
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
