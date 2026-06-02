import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/services/picacg_download_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/sentry_settings_service.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/services/system_tray_service.dart';
import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/services/app_info_service.dart';
import 'package:slime_works/core/services/app_update_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/utils/logger.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/api/sentry_log.dart';
import 'package:slime_works/src/rust/frb_generated.dart';
import 'package:media_kit/media_kit.dart';

const Loggers _logger = Loggers(name: '主程序');

Future<void> main() async {
  TimeConsumptionTest desktopTest = TimeConsumptionTest(tag: "应用初始化")..start();

  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化应用信息（版本号等）
  await AppInfoService.init();

  // 加载环境变量（.env 为可选文件，CI 环境可能不存在）
  await dotenv.load(fileName: '.env', isOptional: true);

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

  // 初始化桌面端自动更新
  // 先检测更新服务器连通性，不通则跳过（避免 Sparkle 弹出原生错误弹窗）
  if (Platform.isMacOS || Platform.isWindows) {
    await getIt<AppUpdateService>().checkForUpdates();
  }

  // 必须在任何 Rust FFI 调用前初始化
  await RustLib.init();

  // 初始化 media_kit（视频播放）
  MediaKit.ensureInitialized();

  // 恢复 PicACG 登录态与网络配置
  await getIt<PicAcgService>().init();
  // 恢复 PicACG 下载元数据
  await getIt<PicAcgDownloadService>().init();

  // 限制 Flutter imageCache 最大字节数（默认 ~100MB 可能被大量远程图片撑满），
  // 设为 80MB 缓解远程媒体库浏览时内存持续增长问题。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 * 1024 * 1024;

  // 在 UI 启动前完成 NodeSettingsService 初始化，避免 ViewModel 与 _postAppInit 并发竞争
  await getIt<NodeSettingsService>().init();

  // 初始化 Sentry 设置服务
  await getIt<SentrySettingsService>().init();

  // 提前加载持久化主题配置（仅解析输入参数，不依赖 ScreenUtil）
  await AppTheme.loadSavedTheme();

  // 运行应用
  runApp(const MyApp());

  unawaited(_postAppInit(desktopTest));
}

Future<void> _postAppInit(TimeConsumptionTest desktopTest) async {
  initializeLogger();

  // 初始化Sentry日志存储
  try {
    final appDir = Platform.isMacOS || Platform.isLinux
        ? '${Platform.environment['HOME']}/.slime_works'
        : Platform.isWindows
        ? '${Platform.environment['APPDATA']}/slime_works'
        : '.';
    await sentryLogInit(dbPath: '$appDir/sentry_log.db');
  } catch (e) {
    _logger.error('[主程序] 初始化Sentry日志存储失败: $e');
  }

  // 配置 EasyLoading
  configLoading();

  // 启动系统资源监控（持续采集，不依赖 Dashboard 页面是否打开）
  getIt<SystemMetricsService>().start();

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  DesktopScreenProvider get desktopScreen => getIt<DesktopScreenProvider>();

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
              if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                return EasyLoading.init()(
                  context,
                  DesktopScaffold(child: child),
                );
              }
              return EasyLoading.init()(context, child);
            },
          );
        },
      );
    });
  }
}
