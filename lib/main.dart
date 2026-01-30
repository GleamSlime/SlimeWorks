import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';

import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/desktop_shell.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/frb_generated.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 加载环境变量
  await dotenv.load(fileName: '.env');

  // 初始化桌面窗口管理器
  await DesktopScaffold.initManager();

  // 运行应用
  runApp(const MyApp());

  // 初始化 Rust 库
  await RustLib.init();

  initializeLogger();

  // 初始化 FFmpeg
  await _initFFmpeg();

  // 配置 EasyLoading
  configLoading();
}

/// 配置 EasyLoading
void configLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.dark
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..progressColor = Colors.yellow
    ..backgroundColor = Colors.green
    ..indicatorColor = Colors.yellow
    ..textColor = Colors.yellow
    ..maskColor = Colors.blue.withAlpha(255 ~/ 2)
    ..userInteractions = false
    ..dismissOnTap = false;
}

/// 初始化 FFmpeg
Future<void> _initFFmpeg() async {
  try {
    final appDir = await getApplicationSupportDirectory();
    final windowsUrl = dotenv.env['FFMPEG_WINDOWS_URL'] ?? '';
    final macosUrl = dotenv.env['FFMPEG_MACOS_URL'] ?? '';

    if (windowsUrl.isEmpty || macosUrl.isEmpty) {
      print('⚠️ FFmpeg URLs not configured in .env');
      return;
    }

    await initializeFfmpeg(windowsUrl: windowsUrl, macosUrl: macosUrl, installDir: appDir.path);

    print('✅ FFmpeg initialized successfully');
  } catch (e) {
    print('❌ FFmpeg initialization failed: $e');
    // 不阻止应用启动，FFmpeg 初始化失败只影响视频元数据功能
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 使用 ScreenUtilInit 进行屏幕适配
    return ScreenUtilInit(
      designSize: const Size(1520, 1050), // 设计稿尺寸
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          title: '史莱姆工坊',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,

          // 主题配置
          theme: AppThemeCommon.lightTheme,
          darkTheme: AppThemeCommon.darkTheme,
          themeMode: ThemeMode.system, // 跟随系统主题
          // 路由配置
          initialRoute: AppRoutes.dashboard,
          getPages: AppRoutes.getPages(),

          // 国际化配置
          locale: const Locale('zh', 'CN'),
          fallbackLocale: const Locale('zh', 'CN'),

          // 使用 DesktopShell 包裹所有页面
          builder: (context, child) => DesktopShell(child: EasyLoading.init()(context, child)),
        );
      },
    );
  }
}
