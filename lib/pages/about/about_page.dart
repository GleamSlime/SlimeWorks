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
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:url_launcher/url_launcher.dart';

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
                constraints: BoxConstraints(maxWidth: scaleW(560)),
                child: Column(
                  children: [
                    _buildHeader(context),
                    SizedBox(height: AppTheme.metrics.kSpace32),
                    _buildDescription(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildVersionInfo(context),
                    SizedBox(height: AppTheme.metrics.kSpace24),
                    _buildUpdateSection(context),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    // 品牌标的紫底走身份色板：明暗两档由 AppVizSet 自己解析，调用点不再写分支。
    final viz = AppVizSet.of(context);

    return Column(
      children: [
        Container(
          width: m.kSpace48 * 2,
          height: m.kSpace48 * 2,
          decoration: BoxDecoration(
            borderRadius: m.radius24,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: viz.lilac.gradient,
            ),
            boxShadow: [
              BoxShadow(
                color: s.shadowKey,
                blurRadius: scaleW(24),
                offset: Offset(0, scaleH(8)),
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
              colorFilter: ColorFilter.mode(s.onMedia, BlendMode.srcIn),
            ),
          ),
        ),
        SizedBox(height: m.kSpace20),
        Text(
          AppInfoService.appName,
          style: AppTextStyles.pageTitle(context).copyWith(letterSpacing: 1.2),
        ),
        SizedBox(height: m.kSpace4),
        Container(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
          decoration: BoxDecoration(
            color: s.accentContainer,
            borderRadius: m.radius8,
          ),
          child: Text(
            AppInfoService.versionWithBuild,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              weight: FontWeight.w600,
              color: s.accentText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      _appDescription,
      textAlign: TextAlign.center,
      style: AppTextStyles.role(
        context,
        fontSize: AppTheme.metrics.fontSize14,
        color: AppSemantic.of(context).textSecondary,
        height: 1.6,
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    final s = AppSemantic.of(context);
    return _AboutCard(
      child: Column(
        children: [
          _InfoRow(
            icon: StrokeIcons.infoOutline,
            label: '版本',
            value: '${AppInfoService.version} (${AppInfoService.buildNumber})',
          ),
          Divider(height: 1, color: s.hairline),
          _InfoRow(icon: StrokeIcons.phoneAndroid, label: '平台', value: _platformName()),
          // 构建时间只有 GitHub Actions 打包的分发版才有（见 lib/core/build_info.dart）
          if (AppInfoService.buildTime.isNotEmpty) ...[
            Divider(height: 1, color: s.hairline),
            _InfoRow(
              icon: StrokeIcons.accessTime,
              label: '构建时间',
              value: AppInfoService.buildTime,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpdateSection(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: m.kSpace12),
          child: Text('应用更新', style: AppTextStyles.sectionTitle(context)),
        ),
        if (!_supportsAutoUpdate)
          // iOS 走蒲公英分发：没有应用内更新通道，给一个直达下载页的按钮
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Platform.isIOS
                      ? 'iOS 测试版通过蒲公英分发，点击下方按钮前往下载最新版本'
                      : '当前平台不支持应用内自动更新，请前往 GitHub Releases 手动下载新版本',
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize13,
                    color: s.textTertiary,
                    height: 1.5,
                  ),
                ),
                if (Platform.isIOS) ...[
                  SizedBox(height: m.kSpace12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () async {
                        const url = 'https://www.pgyer.com/SlimeWork';
                        final ok = await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                        if (!ok) {
                          EasyLoading.showError('无法打开链接');
                        }
                      },
                      icon: DrawIcon(StrokeIcons.download, size: m.iconSize16),
                      // 文字按钮的字样式由主题的按钮档给出，这里不再手写 TextStyle
                      // （裸构造会丢 fontFamily，中文就静默回退了）。
                      label: const Text('打开分发页面'),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          _AboutCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAutoUpdateSwitch(context),
                Divider(height: 1, color: s.hairline),
                _buildCheckUpdateButton(context),
              ],
            ),
          ),
      ],
    );
  }

  /// 自动更新开关：闲置检查 + 原生下载安装
  Widget _buildAutoUpdateSwitch(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return Obx(() {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace10),
        child: Row(
          children: [
            DrawIcon(StrokeIcons.autorenew, size: m.iconSize20, color: s.textSecondary),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动更新', style: AppTextStyles.rowTitle(context)),
                  SizedBox(height: m.kSpace2),
                  Text(
                    '闲置 5 分钟后自动检查 GitHub 新版本，发现更新自动下载安装',
                    style: AppTextStyles.caption(context),
                  ),
                ],
              ),
            ),
            SizedBox(width: m.kSpace12),
            Switch(
              value: _service.autoUpdateEnabled.value,
              activeThumbColor: s.accent,
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
    final s = AppSemantic.of(context);
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
                  DrawIcon(
                    StrokeIcons.newReleases,
                    size: m.iconSize16,
                    color: s.accent,
                  ),
                  SizedBox(width: m.kSpace6),
                  Expanded(
                    child: Text(
                      '发现新版本: v${info.version} (Build ${info.buildNumber})',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize13,
                        weight: FontWeight.w600,
                        color: s.accentText,
                      ),
                    ),
                  ),
                ],
              ),
              if (info.description.isNotEmpty) ...[
                SizedBox(height: m.kSpace6),
                Text(
                  info.description,
                  style: AppTextStyles.role(
                    context,
                    fontSize: m.fontSize11,
                    color: s.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
              SizedBox(height: m.kSpace12),
            ],
            Row(
              children: [
                DrawIcon(StrokeIcons.systemUpdateAlt, size: m.iconSize20, color: s.accent),
                SizedBox(width: m.kSpace12),
                Expanded(
                  child: Text(
                    '发现新版本后会弹窗提示，也可手动检查',
                    style: AppTextStyles.body(context),
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
                            strokeWidth: AppTheme.metrics.strokeRegular,
                            color: s.accentOn,
                          ),
                        )
                      : DrawIcon(StrokeIcons.refresh, size: m.iconSize16),
                  // 同上：按钮文字走主题档，不裸写 TextStyle
                  label: Text(checking ? '检查中...' : '检查更新'),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildCopyright(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      children: [
        Text(
          _copyright,
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            color: s.textDisabled,
          ),
        ),
        SizedBox(height: m.kSpace4),
        Text(
          'Made with 💜 by GleamSlime',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize11,
            color: s.textDisabled,
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
}

class _AboutCard extends StatelessWidget {
  final Widget child;

  const _AboutCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: s.border),
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
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace10),
      child: Row(
        children: [
          DrawIcon(icon, size: m.iconSize18, color: s.textSecondary),
          SizedBox(width: m.kSpace12),
          Expanded(child: Text(label, style: AppTextStyles.rowTitle(context))),
          Text(
            value,
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize13,
              color: s.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
