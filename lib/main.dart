import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/utils/native_reference_holder.dart';
import 'package:slime_works/view_models/music_player_viewmodel.dart';

import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/manga_service.dart';
import 'package:slime_works/core/services/manga_download_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/power_stats_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/services/system_tray_service.dart';
import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/services/initialize/ffmpeg.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/mock/mock_mode.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/api/media_collection.dart';
import 'package:slime_works/mock/seams/sentry_api_seam.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

const Loggers _logger = Loggers(name: '主程序');

Future<void> main() async {
  TimeConsumptionTest desktopTest = TimeConsumptionTest(tag: "应用初始化")..start();

  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化应用信息（版本号等）
  await AppInfoService.init();

  // 加载环境变量（.env 为可选文件，CI 环境可能不存在）
  await dotenv.load(fileName: '.env', isOptional: true);

  // 演示模式开关（编译期或 debug 运行时偏好）
  await MockMode.load();

  getItInit();

  // 初始化桌面窗口管理器
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await DesktopScaffold.initManager();
  }

  // 初始化系统托盘
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await Get.putAsync(() async {
      final service = SystemTrayService();
      await service.init();
      return service;
    });
  }

  // 初始化应用更新检查
  // 先加载自动更新开关偏好；开关开启时由 loadPrefs 内部启动闲置定时器
  // 启动时静默检查一次新版本（发现更新弹窗提示；macOS 自动模式为全自动安装）
  if (AppUpdateService.supportsUpdateCheck) {
    await getIt<AppUpdateService>().loadPrefs();
    unawaited(getIt<AppUpdateService>().checkForUpdates());
  }

  // 必须在任何 Rust FFI 调用前初始化
  await RustLib.init();

  // 注册 ffmpeg/ffprobe 路径到 media_collection 模块，确保视频封面生成可用
  _registerFfmpegPaths();

  // media_kit 延迟到首次播放再初始化：libmpv 一加载就常驻十几 MB，
  // 不碰音视频的用户没必要为此买单（见 MusicPlayerViewModel / 视频预览）

  // 恢复 Manga 下载元数据
  await getIt<MangaDownloadService>().init();
  // Manga 登录态恢复含一次网络请求（失败时要等超时），放到首帧之后，
  // 避免漫画服务器不可达时把整个应用卡在启动画面上
  unawaited(getIt<MangaService>().init());

  // 限制 Flutter imageCache 最大字节数（默认 ~100MB 可能被大量远程图片撑满）。
  // 48MB 是「压常驻后台内存」那次调整定下的，但它带来一个副作用：预览大图当时
  // 仍按**原始分辨率**解码，一张 4K 图就是 30MB+，LRU 为塞下它会把别的东西
  // 全驱逐掉——从预览返回列表时网格封面缓存已经空了，只能重新解码（表现为
  // 「cover 重新加载且很慢」）。现在预览侧已改为「解码封顶」（见
  // cover_decode_cache），单条目普遍变小，预算回到 80MB 换回返回列表的命中率：
  // 网格 480px 封面约 0.8MB/张，80MB 可驻留上百张 + 若干封顶后的预览图。
  // 后台内存的下降靠的是预览封顶本身，不是靠这条预算线硬压。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 * 1024 * 1024;

  // 网络图片的连接并发：dart:io 默认对同一 host 最多 6 条连接，远端列表一屏
  // 几十张封面会在客户端就排成一条长队，表现为「上行永远跑不满」。
  // 用 HttpOverrides 对进程内所有 HttpClient 生效——release 构建也有效，
  // 而 debugNetworkImageHttpClientProvider 只在 debug 的断言块里被读取。
  HttpOverrides.global = _MediaHttpOverrides();

  // 在 UI 启动前完成 NodeSettingsService 初始化，避免 ViewModel 与 _postAppInit 并发竞争
  await getIt<NodeSettingsService>().init();

  // 初始化 Sentry 设置服务
  await getIt<SentrySettingsService>().init();

  // 初始化语音识别设置（内网大模型列表 + 本地引擎部署状态，纯本地读取）
  await getIt<AsrSettingsService>().init();

  // 提前加载持久化主题配置（仅解析输入参数，不依赖 ScreenUtil）
  await AppTheme.loadSavedTheme();

  // 运行应用
  runApp(const MyApp());

  unawaited(_postAppInit(desktopTest));
}

Future<void> _postAppInit(TimeConsumptionTest desktopTest) async {
  // 日志目录：桌面端（macOS）显式传入系统 Logs 目录，slime_logger 会在其下
  // 再建 logs 子目录，最终日志落在 ~/Library/Logs/史莱姆工坊/logs/slime_works_<日期>.log。
  // 之前不传参时 Rust 侧回退到 $TMPDIR/slimeworks，那里会被 macOS 定期清理、
  // 且路径随登录会话变化，用户和排查问题时都很难找到日志。
  // Windows 保持原逻辑（Rust 侧用 %APPDATA%\SlimeWorks）；移动端无文件日志需求，走 TMPDIR 沙盒。
  final macHome = Platform.environment['HOME'];
  final logInstallDir = (Platform.isMacOS && macHome != null)
      ? '$macHome/Library/Logs/史莱姆工坊'
      : null;
  initializeLogger(installDir: logInstallDir);
  // Rust 日志文件已开：放行 Dart 侧日志落盘（攒批 + 定时器，见 Loggers 注释）。
  // 必须在这之后调，否则写进去时 LOG_FILE 还是 None，日志会被静默丢弃。
  // 关键作用：队列调度（[Queue] 入队/执行/完成）、封面进度（[VideoThumb]）
  // 这些只在 Dart 侧的日志，以前 release 版完全不落文件，排查性能问题时
  // 会被误判成"队列没生效"。
  Loggers.enableFileLogging();

  // 应用初始化完毕：确认远程节点连通性并预热远程媒体库元数据。
  // 放在这里而不是 NodeSettingsService.init()：那一步在 runApp 之前，
  // 提前跑一次就成了唯一一次——节点当时没起来就只能等用户进媒体库才恢复。
  // 排在最前：预热只依赖节点配置，不该被 ffmpeg/Sentry 这些无关的启动步骤排队拖慢。
  unawaited(getIt<NodeSettingsService>().warmUpAfterLaunch());

  // 异步解析 ffmpeg/ffprobe 路径：先探测系统 PATH（命中则跳过下载），
  // 未命中则触发内置模块下载。完成后将解析结果注册到 media_collection。
  if (Platform.isWindows || Platform.isMacOS) {
    Future.wait([
      RustFFmpeg.resolvePath(),
      RustFFmpeg.resolveProbe(),
    ]).then((results) {
      // results[0] = ffmpeg 路径，results[1] = ffprobe 路径
      _registerFfmpegPaths(
        ffmpegPath: results[0],
        ffprobePath: results[1],
      );
    });
  }

  // 初始化Sentry日志存储
  try {
    final appDir = Platform.isMacOS || Platform.isLinux
        ? '${Platform.environment['HOME']}/.slime_works'
        : Platform.isWindows
        ? '${Platform.environment['APPDATA']}/slime_works'
        : '.';
    sentryLogInit(dbPath: '$appDir/sentry_log.db');
  } catch (e) {
    _logger.error('[主程序] 初始化Sentry日志存储失败: $e');
  }

  // 配置 EasyLoading
  configLoading();

  // 启动系统资源监控（持续采集，不依赖 Dashboard 页面是否打开）
  getIt<SystemMetricsService>().start();

  // 流水账：打开数据库并把邮箱口令预热进 Rust 内存，
  // 否则"每日到点自动收账单"要等用户先进记账页面才开始生效。
  unawaited(
    getIt<LedgerService>().ensureInitialized().catchError((Object e) {
      // 失败已在服务层记过日志，这里只是不让它变成未捕获的异步异常；
      // 用户进记账页时会再试一次。
    }),
  );

  // 电力统计：表号存过就在后台把定时轮询拉起来，
  // 否则每天得先进一次电力页面、再点一次"启动轮询"才开始有数据。
  unawaited(
    getIt<PowerStatsService>().warmUpAfterLaunch().catchError((Object e) {
      // 服务层已记日志；进电力页面时 ensureInitialized 会再走一遍。
    }),
  );

  desktopTest.end();
}

/// 配置 EasyLoading
void configLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.dark
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..progressColor = Colors.red
    ..backgroundColor = Colors.green
    ..indicatorColor = Colors.red
    ..textColor = Colors.red
    ..maskColor = Colors.blue.withAlpha(255 ~/ 2)
    ..userInteractions = false
    ..dismissOnTap = false;
}

/// 注册 ffmpeg/ffprobe 路径到 Rust 端 media_collection 模块。
/// 接收 [RustFFmpeg.resolvePath]/[RustFFmpeg.resolveProbe] 的解析结果：
/// - 非 null：使用解析到的路径（系统 PATH 中的 "ffmpeg" 或内置模块绝对路径）
/// - null：Rust 端回退到系统 PATH 中的 "ffmpeg"/"ffprobe"
void _registerFfmpegPaths({String? ffmpegPath, String? ffprobePath}) {
  if (!Platform.isWindows && !Platform.isMacOS) return;
  registerFfmpegPaths(ffmpegPath: ffmpegPath, ffprobePath: ffprobePath);
  _logger.info(
    '[FFmpeg] 已注册到 Rust 端 | ffmpeg=$ffmpegPath | ffprobe=$ffprobePath',
  );
}

/// 放开 HTTP 连接并发上限的全局覆盖。
///
/// dart:io 默认对同一 host 只开 6 条连接（[HttpClient.maxConnectionsPerHost]），
/// 媒体库远程封面一屏几十张时，客户端自己就把请求排成了长队——节点侧再快、
/// 带宽再大也只能一条条走。图片解码与列表加载都是「小响应 × 大批量」，
/// 放宽到 32 路既能把管道填满，又不至于把节点连接池（128）打满。
class _MediaHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..maxConnectionsPerHost = 32;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver, WindowListener {
  DesktopScreenProvider get desktopScreen => getIt<DesktopScreenProvider>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 桌面端自动更新要靠「窗口是否聚焦」判断人是否在旁边（lifecycle 恒 resumed）
    if (_autoUpdateOnDesktop) {
      windowManager.addListener(this);
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
      // 启动时补探一次焦点：window_manager 只在焦点**变化**时发事件，
      // 应用一启动就没聚焦（用户切去别的窗口）的话状态会停在默认的 true，
      // 自动更新会被误判成"人就在旁边"而永远不检查。
      unawaited(_syncInitialWindowFocus());
    }
  }

  /// 把系统真实焦点同步给 AppUpdateService（失败保持默认）。
  Future<void> _syncInitialWindowFocus() async {
    try {
      final focused = await windowManager.isFocused();
      _updater?.onWindowFocusChanged(focused);
    } catch (_) {
      // 拿不到焦点状态时按"聚焦"处理（更保守：宁可不自动装也不打断用户）
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_autoUpdateOnDesktop) {
      HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// 本机是否走桌面端自动更新的闲置判定（macOS / Windows）。
  bool get _autoUpdateOnDesktop => Platform.isMacOS || Platform.isWindows;

  /// 缓存一份服务引用：指针事件是高频路径（拖动时每帧一次），
  /// 不该每次都走一遍 GetIt 查找。
  AppUpdateService? _updateService;

  AppUpdateService? get _updater {
    if (!_autoUpdateOnDesktop) return null;
    final cached = _updateService;
    if (cached != null) return cached;
    try {
      // 注册在 main() 里先于 runApp，正常不会走到异常分支；
      // 但这是高频回调路径，抛出去会污染手势/焦点事件分发，一律吞掉
      return _updateService = getIt<AppUpdateService>();
    } catch (_) {
      return null;
    }
  }

  /// 用户是否有任何交互动作。
  ///
  /// 指针事件由 build 里的根 Listener 推动；键盘另走 HardwareKeyboard 的
  /// 全局按键钩子——纯键盘操作（列表里按方向键、填空格）不产生指针事件，
  /// 漏了它就会出现「明明在敲键盘，却被判成闲置」。
  /// 只做「重置闲置时间戳」这一件事，不改变任何既有交互行为。
  void _onUserActivity() {
    _updater?.markUserActive();
  }

  /// 返回 false 表示不拦截：只是旁听，按键照常交给 Focus 树处理。
  bool _onKeyEvent(KeyEvent event) {
    _onUserActivity();
    return false;
  }

  @override
  void onWindowFocus() {
    _updater?.onWindowFocusChanged(true);
  }

  @override
  void onWindowBlur() {
    _updater?.onWindowFocusChanged(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 转发给 AppUpdateService 更新闲置时间戳（仅桌面端自动更新生效）
    if (Platform.isMacOS || Platform.isWindows) {
      getIt<AppUpdateService>().onLifecycleStateChanged(state);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // 热重载时防止 media_kit 的 NativeReferenceHolder 崩溃：
    // 热重载会重置 NativeReferenceHolder.initialized 为 false，
    // 导致 nativeEnsureInitialized 重新调用，读取 buffer 中的旧 mpv 句柄
    // 并发送 quit 命令 → mp_shutdown_clients → 回调已删除的 NativeCallable → 崩溃。
    // 解决方案：抢先调用 ensureInitialized 注册空回调，替代默认的 quit 回调。
    try {
      _preventNativeReferenceHolderCrash();
      if (Get.isRegistered<MusicPlayerViewModel>()) {
        Get.find<MusicPlayerViewModel>().disposeForHotReload();
      }
    } catch (_) {}
  }

  /// 抢先注册空回调到 NativeReferenceHolder，防止热重载后
  /// nativeEnsureInitialized 对存活的 mpv 实例发送 quit 命令
  void _preventNativeReferenceHolderCrash() {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return;
    try {
      // 抢先调用 ensureInitialized，注册空回调替代默认的 quit 回调。
      // 如果 initialized 已被热重载重置为 false，此调用会：
      //   1. 设置 initialized = true（阻止后续重复调用）
      //   2. 用空回调启动 _ensureInitialized（读到旧句柄也不发 quit）
      // 如果 initialized 仍为 true，此调用直接返回，无副作用。
      NativeReferenceHolder.ensureInitialized((_) {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 观察响应式主题参数与度量版本，任一变化时重建 MaterialApp
      final _ = AppTheme.metricsVersion.value;
      final themeMode = AppTheme.themeModeObs.value;
      final accentColor = AppTheme.accentColorObs.value;
      final fontScale = AppTheme.fontScaleObs.value;
      return ScreenUtilInit(
        designSize: isDesktop
            ? desktopScreen.isMobile.value
                  ? const Size(375, 815)
                  : const Size(1920, 1080)
            : const Size(375, 815),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return MaterialApp.router(
            title: desktopScreen.title.value,
            debugShowCheckedModeBanner: false,

            // GoRouter 配置
            routerConfig: goRouter,

            // 主题配置（在 ScreenUtil 构建完成后计算，保证 scaleW 可用）
            theme: AppTheme.buildCustomLight(accentColor, fontScale),
            darkTheme: AppTheme.buildCustomDark(accentColor, fontScale),
            themeMode: themeMode,

            // 国际化配置
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              // 全局用户活动信号：桌面端生命周期恒为 resumed，自动更新的
              // 「闲置」判定只能靠真实输入事件推动，否则用户正在操作时也会
              // 被判成闲置、静默装更新并重启（见 AppUpdateService.markUserActive）。
              // 只挂监听不拦截事件（Listener 自身不消费指针），且不参与布局。
              child = Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _onUserActivity(),
                onPointerMove: (_) => _onUserActivity(),
                onPointerSignal: (_) => _onUserActivity(),
                child: child,
              );
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                // EasyLoading 的包装层在 ExcludeSemantics 之外：它的加载弹层
                // 也会挂语义节点（开关、进度），漏在包裹外面就仍有一条会重建的
                // 语义子树。这里把最外层整体包住，语义树才是真正的空。
                Widget content = EasyLoading.init()(
                  context,
                  DesktopScaffold(child: child),
                );
                if (Platform.isWindows) {
                  // 规避 Flutter Windows 无障碍桥 AXTree 失配崩溃：
                  // UIA 客户端（输入法/PowerToys/读屏工具等）激活语义后，
                  // 页面切换或大列表重建会使引擎 accessibility_bridge 的
                  // AXTree 与框架语义树失配（"NN will not be in the tree and
                  // is not the new root"），语义更新持续报错最终导致进程
                  // 崩溃（Lost connection to device），属引擎级老 bug。
                  // 本应用无读屏适配需求，Windows 端全局排除语义后语义树
                  // 为空，引擎无更新可失配，报错与崩溃链路直接消失。
                  // 如需恢复无障碍支持，删除此包裹即可。
                  content = ExcludeSemantics(child: content);
                }
                return content;
              }
              return EasyLoading.init()(context, child);
            },
          );
        },
      );
    });
  }
}
