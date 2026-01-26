import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/window/custom_bar.dart';
import 'package:slime_works/core/services/window_position_service.dart';

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

    String windowTitle = dotenv.env['APP_NAME'] ?? "";
    double windowWidth = double.parse(dotenv.env['APP_SIZE_WIDTH'] ?? "1520");
    double windowHeight = double.parse(dotenv.env['APP_SIZE_HEIGHT'] ?? "1050");

    WindowOptions windowOptions = WindowOptions(
      size: Size(windowWidth, windowHeight),
      center: false,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      windowButtonVisibility: false,
      title: windowTitle,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 恢复上次的窗口位置
      await positionService.restorePosition();
      await windowManager.show();
      await windowManager.focus();
    });

    // 初始化并注册窗口位置服务
    await Get.putAsync(() => WindowPositionService().init());
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
    return Stack(
      children: [
        widget.child,
        Positioned(left: 0, top: 0, child: const CustomTitleBar()),
      ],
    );
  }
}
