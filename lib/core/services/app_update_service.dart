import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/build_info.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/services/macos_update_installer.dart';
import 'windows_update_installer.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/utils/system_proxy.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用更新服务：以 GitHub Actions 发布的 Release 为唯一信息源。
///
/// - 更新内容（版本、提交清单、资产与 sha256 摘要）全部来自 GitHub REST API；
/// - macOS：全自动更新——后台下载 DMG → 校验 → 挂载替换 → 自动重启；
/// - Windows / Android：弹窗后跳转 GitHub Release 页面手动下载；
/// - iOS：弹窗后跳转蒲公英下载页；
/// - 不再调用 auto_updater（Sparkle/WinSparkle）：WinSparkle 0.8.1 因缺少 DSA
///   签名恒报"更新失败"，Sparkle 交互流程也无法做到无人值守全自动。
class AppUpdateService {
  static const String _repo = 'GleamSlime/SlimeWorks';
  static const String _apiBase = 'https://api.github.com';
  static const String _iosDownloadUrl = 'https://www.pgyer.com/SlimeWork';

  // 自动更新偏好键
  static const String _prefKeyAutoUpdate = 'auto_update_enabled';
  // 闲置判定阈值：5 分钟无交互视为闲置
  static const Duration _idleThreshold = Duration(minutes: 5);
  // 闲置轮询周期：每分钟检查一次闲置状态
  static const Duration _idlePollInterval = Duration(minutes: 1);

  final Loggers _logger = Loggers(name: '应用更新');
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'User-Agent': 'SlimeWorks-Updater'},
    ),
  );

  final RxBool isChecking = false.obs;
  final Rx<AppUpdateInfo?> updateInfo = Rx<AppUpdateInfo?>(null);
  // 自动更新开关（持久化到 SharedPreferences）
  final RxBool autoUpdateEnabled = false.obs;
  // 最近一次检查是否发现新版本（供 UI 判断提示语）
  bool lastCheckHadUpdate = false;
  // macOS 下载进度（0~1；null 表示未在下载）
  final RxnDouble downloadProgress = RxnDouble();
  // macOS 安装阶段文案（弹窗内实时展示）
  final RxString installPhase = ''.obs;

  /// 自动安装是否正在进行（下载+安装全程）。
  ///
  /// 为什么必须是 Rx 且**点击瞬间就置位**：原实现只看 [downloadProgress]
  /// 是否为 null 来判断"正在下载"，但该值要等收到第一个字节才有——从点击到
  /// 连接建立（DNS/TLS/首包）这段时间里按钮仍然是可点的，连点两下就会并发
  /// 跑两份下载，两边的 onProgress 交替写 [downloadProgress]，界面上的进度
  /// 就在两个值之间来回跳。这里在进入下载前同步置位，彻底堵住这个窗口。
  final RxBool autoInstallBusy = false.obs;

  /// 最近一次「人还在用」的时刻（惰性初始化：必须走 [nowProvider]，
  /// 否则字段初值会用真实时钟，注入时钟的单测在 Linux 上算出负的闲置时长）。
  DateTime? _lastActiveTimeValue;
  Timer? _idleCheckTimer;

  DateTime get _lastActiveTime => _lastActiveTimeValue ??= nowProvider();
  set _lastActiveTime(DateTime value) => _lastActiveTimeValue = value;

  /// 时钟注入口（默认 DateTime.now），单测用来快进闲置判定与退避。
  @visibleForTesting
  DateTime Function() nowProvider = DateTime.now;

  /// 窗口是否处于聚焦状态。
  ///
  /// 桌面端 lifecycle 恒为 resumed（窗口一直在前台），光看 [AppLifecycleState]
  /// 永远判不出"人是不是在操作"，必须叠加系统的实际焦点状态：窗口失焦
  /// （切到别的 App、锁屏、最小化到托盘）才算真的闲下来。
  /// 非桌面端没有这个信号，保持 true（交给 lifecycle 判断）。
  bool windowFocused = true;

  /// 上一次失败后的等待时长（指数退避：1min → 2 → 4 …，上限 1h）。
  Duration _checkBackoff = Duration.zero;

  /// 退避到什么时候之前不允许再自动检查。
  DateTime? _backoffUntil;

  /// 静态退避参数（单测断言用）。
  static const Duration initialBackoff = Duration(minutes: 1);
  static const Duration maxBackoff = Duration(hours: 1);

  /// 当前平台是否参与应用内更新检查（全平台弹窗；macOS/Windows 额外支持全自动安装）
  static bool get supportsUpdateCheck =>
      Platform.isMacOS || Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  /// 当前平台能否在应用内完成"下载→校验→替换/安装→重启"的全自动更新。
  /// macOS 走 DMG ditto 替换，Windows 走 Inno 静默安装；
  /// Android 的 APK 必须由系统安装器接管（无法静默覆盖自身），iOS 受沙盒限制只能跳蒲公英。
  static bool get supportsAutoInstall => Platform.isMacOS || Platform.isWindows;

  /// 从 SharedPreferences 加载偏好，启动时调用
  Future<void> loadPrefs() async {
    // Debug 模式下禁用更新检查（避免开发期间弹出更新提示）
    if (kDebugMode) return;
    if (!supportsUpdateCheck) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoUpdateEnabled.value = prefs.getBool(_prefKeyAutoUpdate) ?? false;
      _logger.info('[应用更新] 加载偏好: autoUpdate=${autoUpdateEnabled.value}');
      if (autoUpdateEnabled.value) {
        startAutoCheck();
      }
    } catch (e) {
      _logger.error('[应用更新] 加载偏好失败: $e');
    }
  }

  /// 切换自动更新开关
  Future<void> setAutoUpdateEnabled(bool enabled) async {
    if (autoUpdateEnabled.value == enabled) return;
    autoUpdateEnabled.value = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyAutoUpdate, enabled);
    } catch (e) {
      _logger.error('[应用更新] 保存开关失败: $e');
    }
    if (enabled) {
      startAutoCheck();
    } else {
      stopAutoCheck();
    }
  }

  /// 启动自动检查：闲置达到阈值后触发一次检查
  void startAutoCheck() {
    // 状态重置放在平台门之前：这些字段描述的是「重新开始算」的语义，与当前
    // 平台支不支持自动检查无关。放门后的话，不支持平台的 startAutoCheck 会
    // 变成什么都不做的空操作，调用方以为已经重置、实际留着上一次的退避。
    _idleCheckTimer?.cancel();
    _lastActiveTime = nowProvider();
    _backoffUntil = null;
    _checkBackoff = Duration.zero;
    if (!supportsUpdateCheck) return;
    _idleCheckTimer = Timer.periodic(_idlePollInterval, (_) => _maybeIdleCheck());
    _logger.info(
      '[应用更新] 已启动自动检查（闲置阈值 ${_idleThreshold.inMinutes} 分钟）',
    );
  }

  /// 停止自动检查
  void stopAutoCheck() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = null;
    _logger.info('[应用更新] 已停止自动检查');
  }

  /// 由 main.dart 在 AppLifecycleState 变化时调用
  void onLifecycleStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastActiveTime = nowProvider();
    }
  }

  /// 用户最近交互时间更新（鼠标/键盘/滚轮都会调，见 main.dart 的根 Listener）。
  ///
  /// 这个方法是「人还在用」的唯一信号：桌面端 lifecycle 恒为 resumed，
  /// 没有它的话 _maybeIdleCheck 的五分钟闲置判定必然成立，用户正在操作时
  /// 也会被静默装更新并重启。
  void markUserActive() {
    _lastActiveTime = nowProvider();
  }

  /// 窗口焦点变化（桌面端 window_manager 的 onWindowFocus/onWindowBlur 转发）。
  ///
  /// 失焦 = 人去看别的东西了，才算「可以静默安装」；重新聚焦按活跃处理，
  /// 把闲置计时重置掉。
  void onWindowFocusChanged(bool focused) {
    windowFocused = focused;
    if (focused) {
      _lastActiveTime = nowProvider();
    }
  }

  /// 当前是否满足「可以静默自动安装」：开关打开 + 闲置够久 + 窗口失焦。
  @visibleForTesting
  bool canAutoInstallQuietly() {
    if (!autoUpdateEnabled.value) return false;
    if (windowFocused) return false;
    return nowProvider().difference(_lastActiveTime) >= _idleThreshold;
  }

  /// 下一次允许自动检查的时间点（无退避时为 null），单测断言用。
  @visibleForTesting
  DateTime? get backoffUntil => _backoffUntil;

  /// 当前退避时长，单测断言用。
  @visibleForTesting
  Duration get currentBackoff => _checkBackoff;

  /// 记录一次检查失败并推进指数退避：1min → 2 → 4 → … → 上限 1h。
  @visibleForTesting
  void registerCheckFailure() {
    final next = _checkBackoff == Duration.zero
        ? initialBackoff
        : Duration(
            milliseconds: (_checkBackoff.inMilliseconds * 2).clamp(
              initialBackoff.inMilliseconds,
              maxBackoff.inMilliseconds,
            ),
          );
    _checkBackoff = next > maxBackoff ? maxBackoff : next;
    _backoffUntil = nowProvider().add(_checkBackoff);
    _logger.info('[应用更新] 检查失败，${_checkBackoff.inMinutes} 分钟后重试');
  }

  /// 闲置检查：达到阈值、开关开启、窗口失焦且不在退避期内时触发一次自动检查
  Future<void> _maybeIdleCheck() async {
    if (!autoUpdateEnabled.value || isChecking.value) return;
    final now = nowProvider();
    final idleDuration = now.difference(_lastActiveTime);
    if (idleDuration < _idleThreshold) return;
    // 失败退避：连续失败时按 1min→2→4…→1h 递增，别每分钟打一次 GitHub
    final backoffUntil = _backoffUntil;
    if (backoffUntil != null && now.isBefore(backoffUntil)) return;
    // 窗口还聚焦着说明人就在旁边看着，静默重启会直接打断他——等失焦再说
    if (windowFocused) {
      _logger.info('[应用更新] 已闲置但窗口仍聚焦，暂不自动检查');
      return;
    }

    _logger.info(
      '[应用更新] 检测到闲置 ${idleDuration.inMinutes} 分钟且窗口未聚焦，开始自动检查',
    );
    await _performCheck(showDialog: true, autoInstall: true);
  }

  /// 检查更新入口。[autoInstall] 为 true 时（闲置自动检查）macOS/Windows 直接全自动安装；
  /// 用户主动点按钮时保持弹窗确认，不静默重启。
  Future<void> checkForUpdates({bool silent = true, bool autoInstall = false}) async {
    // Debug 模式下不弹更新提示
    if (kDebugMode) {
      _logger.info('[应用更新] Debug 模式，跳过更新检查');
      return;
    }
    await _performCheck(showDialog: true, autoInstall: autoInstall);
  }

  /// 拉取 Release、比较版本、按需弹窗；macOS 在自动模式下直接静默安装重启。
  Future<void> _performCheck({
    required bool showDialog,
    required bool autoInstall,
  }) async {
    if (isChecking.value) return;
    isChecking.value = true;
    lastCheckHadUpdate = false;
    try {
      final info = await _fetchLatestRelease();
      if (info == null) {
        _logger.info('[应用更新] 检查：无法获取 Release 信息（网络不可达或解析失败）');
        // 自动检查失败要退避：否则每分钟一次的闲置轮询会把失败请求反复打到 GitHub
        if (autoInstall) registerCheckFailure();
        return;
      }
      // 拿到应答就清掉退避：失败计数只用于连续失败
      _checkBackoff = Duration.zero;
      _backoffUntil = null;

      if (!_isNewer(info)) {
        _logger.info('[应用更新] 检查：已是最新版本（远端 build=${info.remoteBuildCode ?? info.buildNumber}）');
        return;
      }

      updateInfo.value = info;
      lastCheckHadUpdate = true;

      // 自动模式（macOS/Windows）：不打扰用户，下载校验后自动安装并重启
      if (autoInstall && supportsAutoInstall) {
        _logger.info('[应用更新] 自动模式：开始静默下载安装 v${info.version}');
        await _startAutoInstall(info, autoTriggered: true);
        return;
      }

      if (!showDialog) return;
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        _showUpdateDialog(context, info);
      }
    } catch (e) {
      _logger.error('[应用更新] 检查更新失败: $e');
      if (autoInstall) registerCheckFailure();
    } finally {
      isChecking.value = false;
    }
  }

  // ───────────────────────── GitHub Release 获取与解析 ─────────────────────────

  /// 通过 GitHub REST API 获取最新 Release，组装各平台所需信息。
  Future<AppUpdateInfo?> _fetchLatestRelease() async {
    try {
      // GitHub 在部分网络环境需走代理：每次检查前自适应探测系统代理
      // （env 变量 → macOS scutil → Windows 注册表），带 TTL 缓存，
      // 用户中途开关代理也能在下一次缓存过期后跟上。
      final proxy = SystemProxy.applyToDio(_dio);
      _logger.info('[应用更新] 检查更新，代理: ${proxy ?? '直连'}');
      final resp = await _dio.get<dynamic>(
        '$_apiBase/repos/$_repo/releases/latest',
        options: Options(responseType: ResponseType.plain),
      );
      if (resp.statusCode != 200 || resp.data == null) return null;
      return parseRelease(jsonDecode(resp.data as String) as Map<String, dynamic>);
    } catch (e) {
      _logger.error('[应用更新] 获取 Release 失败: $e');
      return null;
    }
  }

  /// 解析 Release JSON：tag 形如 `v1.0.0+20261107.ae4a4a2`；
  /// macOS 取 `*-macos.dmg` 资产（带 sha256 digest），其余平台只需页面链接。
  /// 公开为 static 供单元测试直接校验解析规则。
  static AppUpdateInfo? parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    if (tag.isEmpty) return null;
    final versionMatch = RegExp(r'^v(\d[\w.\-]*)\+(.+)$').firstMatch(tag);
    final version = versionMatch?.group(1) ?? tag;
    final ciBuildNumber = versionMatch?.group(2) ?? '';

    // 提交清单正文（Release body 由 CI 用同一份"本次推送提交记录"写入）
    final body = (json['body'] as String? ?? '').trim();

    String? dmgUrl;
    String? dmgSha256;
    int? assetBuildCode;
    String? exeUrl;
    String? exeSha256;
    for (final asset in (json['assets'] as List? ?? const [])) {
      final name = (asset['name'] as String? ?? '');
      final lower = name.toLowerCase();
      final digest = asset['digest'] as String?;
      final sha = digest != null && digest.startsWith('sha256:')
          ? digest.substring(7)
          : null;
      // 资产名形如 slime_works-1.0.0+155-macos.dmg：+ 后的纯数字即 CI run_number
      final codeMatch = RegExp(r'\+(\d+)[^/]*-macos\.dmg$').firstMatch(name);
      if (lower.endsWith('.dmg') && (dmgUrl == null || codeMatch != null)) {
        dmgUrl = asset['browser_download_url'] as String?;
        dmgSha256 = sha;
        if (codeMatch != null) {
          assetBuildCode = int.tryParse(codeMatch.group(1)!);
        }
      }
      // Windows 安装包名形如 _1.0.0+155_windows_x64.exe（fastforge 产物）
      if (lower.endsWith('.exe') && lower.contains('windows')) {
        exeUrl = asset['browser_download_url'] as String?;
        exeSha256 = sha;
      }
    }

    final releaseUrl = json['html_url'] as String? ??
        'https://github.com/$_repo/releases/latest';

    return AppUpdateInfo(
      version: version,
      buildNumber: ciBuildNumber,
      title: json['name'] as String? ?? 'SlimeWorks v$version',
      description: body,
      downloadUrl: dmgUrl ?? releaseUrl,
      releaseUrl: releaseUrl,
      windowsDownloadUrl: exeUrl,
      windowsSha256: exeSha256,
      remoteBuildCode: assetBuildCode,
      sha256: dmgSha256,
    );
  }

  /// 版本比较：优先用 CI 数字构建号（GitHub run_number，注入在 CiBuildInfo/资产名里），
  /// 拿不到时退回 tag 的 YYYYMMDD 前缀比较，再退回版本号比较。
  bool _isNewer(AppUpdateInfo info) {
    final currentBuild = AppInfoService.buildCode;
    if (info.remoteBuildCode != null) {
      return info.remoteBuildCode! > currentBuild;
    }
    // tag 构建号形如 20261107.ae4a4a2：同日构建哈希不可序，但足以挡住跨日误判
    final remoteDate = int.tryParse(
        RegExp(r'^(\d{8})').stringMatch(info.buildNumber) ?? '');
    final localDate = int.tryParse(
        RegExp(r'^(\d{8})').stringMatch(CiBuildInfo.buildNumber) ?? '');
    if (remoteDate != null && localDate != null) {
      return remoteDate > localDate;
    }
    return _versionGreaterThan(info.version, AppInfoService.version);
  }

  /// 语义化版本号比较（点分数字，缺位补 0）
  bool _versionGreaterThan(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb;
    }
    return false;
  }

  // ───────────────────────── 平台化"立即更新"动作 ─────────────────────────

  /// 弹窗主按钮：macOS/Windows 走应用内全自动安装；Android 跳 GitHub Release 页；
  /// iOS 跳蒲公英下载页。
  Future<void> performUpdateAction(BuildContext context, AppUpdateInfo info) async {
    if (supportsAutoInstall) {
      // 不关弹窗：全自动安装的下载进度与阶段文案就地展示，
      // 安装完成时应用会自动退出重启，无需用户再操作。
      await _startAutoInstall(info);
      return;
    }
    // 其余平台是"跳转下载页"，先关弹窗再离开应用
    Navigator.of(context).pop();
    final url = Platform.isIOS ? _iosDownloadUrl : info.releaseUrl;
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        _logger.error('[应用更新] 无法打开下载页面: $url');
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('无法打开下载页面，请稍后重试')),
          );
        }
      }
    } catch (e) {
      _logger.error('[应用更新] 打开下载页面异常: $e');
    }
  }

  // ───────────────────────── macOS / Windows 全自动安装 ─────────────────────────

  /// 下载安装包 → sha256 校验 → 替换/静默安装 → 自动重启，全程无人值守。
  /// [autoTriggered] 为 true 表示由闲置自动检查发起（可能是用户不在电脑前）。
  /// 这种情况在真正安装重启前还要再确认一次「人确实不在」：下载可能要几分钟，
  /// 期间用户完全可能回来继续用，此时静默重启会直接打断他。
  Future<void> _startAutoInstall(AppUpdateInfo info, {bool autoTriggered = false}) async {
    // 重入闸：连点按钮/自动检查与手动点击撞在一起时，只允许一份下载在跑。
    // 不拦的话两份下载会同时写 downloadProgress，进度表在两个值之间跳。
    if (autoInstallBusy.value) {
      _logger.info('[应用更新] 已在自动安装中，忽略重复触发');
      return;
    }
    // Windows 必须拿到安装包直链才能自动装；缺失（资产改名/未上传）时
    // 退回下载页面，避免拿着 Release 页面 URL 去下载 HTML。
    if (Platform.isWindows && (info.windowsDownloadUrl ?? '') == '') {
      installPhase.value = '未找到 Windows 安装包，跳转下载页面…';
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.of(context).pop();
        await launchUrl(Uri.parse(info.releaseUrl),
            mode: LaunchMode.externalApplication);
      }
      return;
    }
    autoInstallBusy.value = true;
    final url = Platform.isWindows
        ? info.windowsDownloadUrl!
        : info.downloadUrl;
    final sha = Platform.isWindows ? info.windowsSha256 : info.sha256;
    try {
      installPhase.value = '正在下载更新…';
      final pkgPath = await _downloadPackage(
        url: url,
        expectedSha256: sha,
        onProgress: (received, total) {
          downloadProgress.value = total > 0 ? received / total : null;
        },
      );
      // 下载期间用户可能回来了：自动触发的那一路必须再确认一次，
      // 人在就转成确认弹窗（用户主动点按钮的路径本来就已是确认后的，无需再问）
      if (autoTriggered && !canAutoInstallQuietly()) {
        _logger.info('[应用更新] 下载完成但用户已回来，改为弹窗确认');
        installPhase.value = '更新已就绪，等待确认…';
        downloadProgress.value = null;
        autoInstallBusy.value = false;
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showUpdateDialog(ctx, info);
        }
        return;
      }
      installPhase.value = '正在安装并重启…';
      await _installAndRelaunch(pkgPath);
      // 接力脚本已接管：等主进程退出即可，正常情况下不会走到这里
      _logger.info('[应用更新] 安装脚本已接管，应用即将自动重启');
    } catch (e) {
      installPhase.value = '';
      downloadProgress.value = null;
      _logger.error('[应用更新] 自动安装失败: $e');
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自动更新失败：$e，可前往 GitHub Releases 手动下载')),
        );
      }
    } finally {
      // 失败要放开重试；成功路径进程会被接力脚本替换，放开也无害
      autoInstallBusy.value = false;
    }
  }

  /// 按平台委派下载（macOS 装 DMG / Windows 装 Inno exe）
  Future<String> _downloadPackage({
    required String url,
    String? expectedSha256,
    required void Function(int received, int total) onProgress,
  }) {
    if (Platform.isWindows) {
      return WindowsUpdateInstaller(logger: _logger).download(
        url: url,
        expectedSha256: expectedSha256,
        onProgress: onProgress,
      );
    }
    return MacosUpdateInstaller(logger: _logger).download(
      url: url,
      expectedSha256: expectedSha256,
      onProgress: onProgress,
    );
  }

  /// 按平台委派"接管安装并重启"的脱离会话脚本
  Future<void> _installAndRelaunch(String pkgPath) {
    if (Platform.isWindows) {
      return WindowsUpdateInstaller(logger: _logger).installAndRelaunch(
        pkgPath,
        currentExe: Platform.resolvedExecutable,
        mainPid: pid,
      );
    }
    return MacosUpdateInstaller(logger: _logger).installAndRelaunch(pkgPath);
  }

  // ───────────────────────── 更新弹窗 ─────────────────────────

  /// 使用 showDialog 弹出更新说明（内容即 GitHub Release 提交清单）。
  void _showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final s = AppSemantic.of(ctx);
        final m = AppTheme.metrics;
        // 主按钮文案按平台区分：macOS 是"自动下载安装并重启"
        final actionLabel = supportsAutoInstall
            ? '立即更新（自动安装）'
            : Platform.isIOS
                ? '前往蒲公英下载'
                : '前往下载页面';
        return Obx(() {
          // busy 覆盖"点击后到首包之间"的空窗期，downloading 只管进度条显隐
          final busy = autoInstallBusy.value;
          final downloading = downloadProgress.value != null;
          return AlertDialog(
            backgroundColor: s.surfaceRaised,
            shape: RoundedRectangleBorder(borderRadius: m.radius16),
            title: Row(
              children: [
                DrawIcon(StrokeIcons.newReleases, size: m.iconSize20, color: s.accent),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: Text(
                    '发现新版本 v${info.version}',
                    style: AppTextStyles.rowTitle(ctx),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: scaleW(420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 更新内容：GitHub Actions 发布时写入的提交清单
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: scaleW(240)),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        info.description.isEmpty
                            ? '构建号：${info.buildNumber}'
                            : info.description,
                        style: AppTextStyles.role(
                          ctx,
                          fontSize: m.fontSize12,
                          color: s.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  // macOS 全自动安装的实时进度区
                  if (supportsAutoInstall && (downloading || installPhase.value.isNotEmpty)) ...[
                    SizedBox(height: m.kSpace12),
                    Text(
                      installPhase.value,
                      style: AppTextStyles.role(
                        ctx,
                        fontSize: m.fontSize12,
                        color: s.accentText,
                      ),
                    ),
                    if (downloading) ...[
                      SizedBox(height: m.kSpace6),
                      LinearProgressIndicator(
                        value: downloadProgress.value,
                        minHeight: scaleW(4),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              if (!supportsAutoInstall || !busy)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  // 按钮文字样式由主题的字阶+字族统一发出，这里再写裸 TextStyle
                  // 会把 fontFamily 整条顶掉，中文会变兜底字
                  child: const Text('稍后提醒'),
                ),
              FilledButton(
                // 下载/安装进行中禁止重复触发（busy 从点击瞬间即为 true）
                onPressed: busy ? null : () => performUpdateAction(ctx, info),
                child: Text(actionLabel),
              ),
            ],
          );
        });
      },
    );
  }
}


class AppUpdateInfo {
  final String version;
  final String buildNumber;
  final String title;
  final String description;
  /// macOS 为 DMG 下载地址；其余平台回退为 Release 页面
  final String downloadUrl;
  /// GitHub Release 页面（Windows/Android"立即更新"跳转目标）
  final String releaseUrl;
  /// Windows Inno 安装包直链（*_windows_x64.exe），拿不到为 null；
  /// 仅 Windows 自动安装使用（其余平台仍走 downloadUrl/页面跳转）
  final String? windowsDownloadUrl;
  /// Windows 安装包的 sha256（GitHub API digest），拿不到为 null
  final String? windowsSha256;
  /// CI 数字构建号（从 DMG 资产名的 +N 解出），拿不到为 null
  final int? remoteBuildCode;
  /// DMG 的 sha256（GitHub API digest），拿不到为 null
  final String? sha256;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.title,
    required this.description,
    required this.downloadUrl,
    required this.releaseUrl,
    this.windowsDownloadUrl,
    this.windowsSha256,
    this.remoteBuildCode,
    this.sha256,
  });
}
