import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';

class DesktopScaffold extends StatefulWidget {
  final Widget child;

  const DesktopScaffold({super.key, required this.child});

  static const double _aspectRatio = 16.0 / 9.0;
  static const double _minWidth = 1280.0;
  static const double _minHeight = 720.0;

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

    double initWidth = positionService.windowWidth.clamp(_minWidth, double.infinity);
    double initHeight = positionService.windowHeight.clamp(_minHeight, double.infinity);
    initHeight = initWidth / _aspectRatio;

    desktopScreen.setWidth(initWidth);
    desktopScreen.setHeight(initHeight);

    WindowOptions windowOptions = WindowOptions(
      size: Size(initWidth, initHeight),
      minimumSize: const Size(_minWidth, _minHeight),
      center: false,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: LightColors.background1,
      windowButtonVisibility: false,
      title: desktopScreen.title.value,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setMinimumSize(const Size(_minWidth, _minHeight));
      await windowManager.setAspectRatio(_aspectRatio);
      // 恢复上次的窗口位置
      await positionService.restorePosition();
      // 延迟到下一帧再计算度量，避免在 ScreenUtil 未初始化前访问它
      WidgetsBinding.instance.addPostFrameCallback((_) => AppTheme.resetMetrics());
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
  void onWindowResize() {
    AppTheme.resetMetrics();
  }

  @override
  void onWindowResized() {
    // 窗口大小改变时保存
    _positionService?.savePosition();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: isMobile
          ? widget.child
          : Stack(
              children: [
                // 全局背景图（游戏详情页设置，AnimatedSwitcher 保证进出场均有淡入淡出过渡）
                Positioned.fill(
                  child: Obx(() {
                    final String path = getIt<DesktopScreenProvider>().globalBackgroundPath.value;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      reverseDuration: const Duration(milliseconds: 150),
                      child: path.isEmpty
                          ? const SizedBox.shrink()
                          : _GlobalBlurBackground(key: ValueKey<String>(path), coverPath: path),
                    );
                  }),
                ),
                widget.child,
                const Positioned(left: 0, top: 0, child: ScreenTopBar()),
              ],
            ),
    );
  }
}

/// 全局模糊封面背景（铺满整个窗口）
class _GlobalBlurBackground extends StatelessWidget {
  const _GlobalBlurBackground({super.key, required this.coverPath});

  final String coverPath;

  @override
  Widget build(BuildContext context) {
    final String value = coverPath.trim();
    Widget image;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      image = CachedNetworkImage(
        imageUrl: value,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      final File file = File(value);
      if (value.isNotEmpty && file.existsSync()) {
        image = Image.file(file, fit: BoxFit.cover, alignment: Alignment.center);
      } else {
        return const SizedBox.shrink();
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        image,
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor.withAlpha(120)),
        ),
      ],
    );
  }
}
