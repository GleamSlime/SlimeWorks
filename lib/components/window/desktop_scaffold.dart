import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/core/services/window_position_service.dart';

// abstract class DesktopScreen {
//   static const double minWidth = 1200;
//   static const double minHeight = 800;

//   static Size get size => Size(width.value, height.value);

//   static String title = dotenv.env['APP_NAME'] ?? "";

//   static RxDouble width = double.parse(dotenv.env['APP_SIZE_WIDTH'] ?? "1520").obs;
//   static RxDouble height = double.parse(dotenv.env['APP_SIZE_HEIGHT'] ?? "1050").obs;

//   static RxBool get isDesktop => RxBool(width.value > 600 || Platform.isWindows || Platform.isLinux || Platform.isMacOS);
//   static RxBool get isMobile => RxBool(width.value <= 600 || Platform.isAndroid || Platform.isIOS);

//   static void setWidth(double width) {
//     if (width < minWidth) {
//       DesktopScreen.width.value = minWidth;
//     } else {
//       DesktopScreen.width.value = width;
//     }
//   }

//   static void setHeight(double height) {
//     if (height < minHeight) {
//       DesktopScreen.height.value = minHeight;
//     } else {
//       DesktopScreen.height.value = height;
//     }
//   }
// }

class DesktopScaffold extends StatefulWidget {
  final Widget child;

  const DesktopScaffold({super.key, required this.child});

  static Future<void> initManager() async {
    if (Platform.isIOS || Platform.isAndroid) {
      return;
    }

    await windowManager.ensureInitialized();

    // 初始化窗口位置服务
    final positionService = await Get.putAsync(() async {
      final service = WindowPositionService();
      await service.init();
      return service;
    });

    DesktopScreenProvider desktopScreen = getIt.get<DesktopScreenProvider>();

    desktopScreen.setWidth(positionService.windowWidth);
    desktopScreen.setHeight(positionService.windowHeight);

    WindowOptions windowOptions = WindowOptions(
      size: desktopScreen.size.value,
      center: false,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.white,
      windowButtonVisibility: false,
      title: desktopScreen.title.value,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 恢复上次的窗口位置
      await positionService.restorePosition();
      // await windowManager.show();
      // await windowManager.focus();
    });
  }

  @override
  State<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends State<DesktopScaffold> with WindowListener {
  WindowPositionService? _positionService;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _positionService = Get.find<WindowPositionService>();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMoved() {
    // 窗口移动时保存位置
    _positionService?.savePosition();
  }

  @override
  void onWindowResized() {
    // 窗口大小改变时保存
    _positionService?.savePosition();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        children: [
          widget.child,
          Positioned(left: 0, top: 0, child: const ScreenTopBar()),
        ],
      ),
    );
  }
}
