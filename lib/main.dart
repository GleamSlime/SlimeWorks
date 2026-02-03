import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/components/window/desktop_shell.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/services/initialize/main.dart';
import 'package:slime_works/core/services/time_consumption_test.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  TimeConsumptionTest desktopTest = TimeConsumptionTest(tag: "应用初始化")..start();

  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 加载环境变量
  await dotenv.load(fileName: '.env');

  getItInit();

  // 初始化桌面窗口管理器
  await DesktopScaffold.initManager();

  // 运行应用
  runApp(const MyApp());

  // 运行应用
  await RustLib.init();

  initializeLogger();

  // 异步加载 Rust 模块
  RustModules.initializeLazy();

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
    ..progressColor = Colors.yellow
    ..backgroundColor = Colors.green
    ..indicatorColor = Colors.yellow
    ..textColor = Colors.yellow
    ..maskColor = Colors.blue.withAlpha(255 ~/ 2)
    ..userInteractions = false
    ..dismissOnTap = false;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  DesktopScreenProvider get desktopScreen => getIt<DesktopScreenProvider>();

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: isDesktop
          ? desktopScreen.isMobile.value
                ? Size(375, 815)
                : Size(1520, 1050)
          : Size(375, 815),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return Obx(() {
          // 观察 AppTheme.metricsVersion，确保在重置度量后重建应用树
          final _ = AppTheme.metricsVersion.value;
          return GetMaterialApp(
            title: desktopScreen.title.value,
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,

            // 主题配置
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: AppTheme.themeMode,

            // 路由配置
            initialRoute: AppRoutes.dashboard,
            getPages: AppRoutes.getPages(),

            // 国际化配置
            locale: const Locale('zh', 'CN'),
            fallbackLocale: const Locale('zh', 'CN'),

            builder: (context, child) {
              final Widget result = EasyLoading.init()(context, child);
              return DesktopShell(child: result);
            },
          );
        });
      },
    );
  }
}
