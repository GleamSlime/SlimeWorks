import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/routes/app_routes.dart';
import 'package:slime_works/src/rust/frb_generated.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化桌面窗口管理器
  DesktopScaffold.initManager();

  // 初始化 Rust 库
  await RustLib.init();

  // 运行应用
  runApp(const MyApp());

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

          // EasyLoading 配置
          builder: EasyLoading.init(),
        );
      },
    );
  }
}
