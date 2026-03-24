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
import 'package:slime_works/core/services/initialize/main.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

Future<void> main() async {
  TimeConsumptionTest desktopTest = TimeConsumptionTest(tag: "应用初始化")..start();

  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 加载环境变量
  await dotenv.load(fileName: '.env');

  getItInit();

  // 初始化桌面窗口管理器
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await DesktopScaffold.initManager();
  }

  // 运行应用
  runApp(const MyApp());

  unawaited(_postAppInit(desktopTest));
}

Future<void> _postAppInit(TimeConsumptionTest desktopTest) async {
  await RustLib.init();
  await getIt<NodeSettingsService>().init();

  initializeLogger();

  // 异步加载 Rust 模块
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    RustModules.initializeLazy();
  }

  // 配置 EasyLoading
  configLoading();

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
      // 观察 AppTheme.metricsVersion，确保在重置度量后重建应用树
      final _ = AppTheme.metricsVersion.value;
      return ScreenUtilInit(
        designSize: isDesktop
            ? desktopScreen.isMobile.value
                  ? Size(375, 815)
                  : Size(1920, 1080)
            : Size(375, 815),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return MaterialApp.router(
            title: desktopScreen.title.value,
            debugShowCheckedModeBanner: false,

            // GoRouter 配置
            routerConfig: goRouter,

            // 主题配置
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: AppTheme.themeMode,

            // 国际化配置
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],

            builder: (context, child) {
              return EasyLoading.init()(context, child);
            },
          );
        },
      );
    });
  }
}
