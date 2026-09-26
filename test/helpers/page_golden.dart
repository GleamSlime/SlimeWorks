import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/components/window/desktop_scaffold.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_provider_impl.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/services/system_metrics_service.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

// 真实页面离屏出图的公共铺垫
//
// 页面不像纯 Widget：它从 getIt 取服务、用 AppTheme 的 ThemeData、还要
// ScreenUtil 已经按窗口尺寸算好系数。这三样少一样，第一帧就直接抛，
// 所以每个页面级 golden 都从这里起步。

/// 测试里当窗口用的一套尺寸，页面里的 scaleW/scaleS 都按它折算
const Size kTestWindowSize = Size(1440, 900);

/// 载入应用真实用到的字体
///
/// 测试进程默认不带自定义字体，图标全渲染成方框、中文全fallback成系统字，
/// 排版跟真机差得没法验收。
Future<void> loadAppFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      // 部分 shell 下 FLUTTER_ROOT 为空，从 dart-sdk 可执行路径回溯一层兜底
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .absolute
          .path;

  final fonts = <(String, String)>[
    ('FZLanTingYuanS-EB-GB', 'assets/fonts/FZLanTingYuanS-EB-GB.ttf'),
    // 出图环境里没有系统中文字体，主题的回退链第一档就是 PingFang SC，
    // 不钉这一份中文会整页变豆腐块（真机由系统字提供，不需要）
    ('PingFang SC', 'assets/fonts/FZLanTingYuanS-EB-GB.ttf'),
    ('FZLanTingYuanS-R-GB', 'assets/fonts/FZLanTingYuanS-R-GB.ttf'),
    // Inter 四档静态字重都要挂全：只挂 Regular 时，w500/w600 会被引擎
    // 合成加粗，字面比真机粗一圈，出图就没法当验收依据
    ('Inter', 'assets/fonts/Inter-Regular.ttf'),
    ('Inter', 'assets/fonts/Inter-Medium.ttf'),
    ('Inter', 'assets/fonts/Inter-SemiBold.ttf'),
    ('Inter', 'assets/fonts/Inter-Bold.ttf'),
    (
      'MaterialIcons',
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ];

  for (final (family, path) in fonts) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }
}

/// 把页面要用的服务摆进 getIt：只注册这几个，且已注册就不重复注册
///
/// 走的是 lazySingleton，页面不取就什么都不跑；SystemMetricsService 不 start()，
/// 也就不会去碰 FFI，历史曲线由测试自己塞值。
void registerPageServices() {
  // 用写死的字符串而不是去读 .env：本机 .env 一改，所有出图就全变了，
  // golden 等于跟着每个人的配置漂
  dotenv.loadFromString(
    envString: 'APP_SIZE_WIDTH=${kTestWindowSize.width.toInt()}\n'
        'APP_SIZE_HEIGHT=${kTestWindowSize.height.toInt()}',
  );

  if (!getIt.isRegistered<DesktopScreenProvider>()) {
    getIt.registerLazySingleton<DesktopScreenProvider>(
      () => DesktopScreenProviderImpl(),
    );
  }
  if (!getIt.isRegistered<NodeSettingsService>()) {
    getIt.registerLazySingleton<NodeSettingsService>(
      () => NodeSettingsService(),
    );
  }
  if (!getIt.isRegistered<SystemMetricsService>()) {
    getIt.registerLazySingleton<SystemMetricsService>(
      () => SystemMetricsService(),
    );
  }
}

/// 拿到测试自己填数据的那个指标服务
SystemMetricsService pageMetrics() => getIt<SystemMetricsService>();

/// 用真实主题把页面装进窗口
///
/// [withTopBar] 复刻 _DesktopShell 的内容区：ScreenChrome 在桌面端只把配置
/// 发布给全局顶栏、自己不留痕迹，不补这一行就看不到页面标题和工具栏。
Future<void> pumpAppPage(
  WidgetTester tester,
  Widget page, {
  bool dark = false,
  Size size = kTestWindowSize,
  bool withTopBar = false,
}) async {
  registerPageServices();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: size,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        // 真实窗口里这层画布由 DesktopScaffold 的根 Material 铺；测试直接挂页面
        // 的话背景是透明的，卡片和画布的分层在图上根本看不出来。
        // 必须用 Builder 里的 context 取语义色：ScreenUtilInit 的 context 在
        // MaterialApp 之上，那儿还读不到主题，暗色版会拿成亮色画布。
        home: Builder(
          builder: (context) => ColoredBox(
            color: AppSemantic.of(context).canvas,
            child: withTopBar
                ? Column(
                    children: [
                      const DesktopTopBar(),
                      Expanded(child: page),
                    ],
                  )
                : page,
          ),
        ),
      ),
    ),
  );
}

/// 一小步一小步地推进时间
///
/// 一次 pump 到位只会渲染终态，途中那些窄宽度、半透明层根本没排过版，
/// 溢出这类问题就全藏住了。
Future<void> advance(WidgetTester tester, {int steps = 12, int ms = 30}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// 页面里挂 Timer.periodic 的话，测试结束前必须把它卸掉，
/// 否则 binding 会报"还有挂起的 Timer"。
Future<void> unmountPage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
