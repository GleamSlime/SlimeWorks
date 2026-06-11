import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/components/window/floating_task_progress.dart';
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
  void onWindowClose() async {
    // 关闭窗口时隐藏到系统托盘，而非退出应用
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: isMobile
          ? widget.child
          : Stack(
              children: [
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
                // 悬浮任务进度
                const FloatingTaskProgress(),
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

class DesktopTopBar extends StatelessWidget {
  const DesktopTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chrome = getIt<DesktopScreenProvider>().screenChrome.value.data;

      return Container(
        padding: EdgeInsets.only(
          left: AppTheme.metrics.kSpace12,
          right: AppTheme.metrics.kSpace16,
          top: AppTheme.metrics.kSpace4,
        ),
        height: scaleW(60),
        child: Row(
          spacing: appMetrics.kSpace12,
          children: [
            if (chrome.hasLeading) chrome.leading!,
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    chrome.titleWidget ??
                    (chrome.title != null
                        ? Text(chrome.title!, style: Theme.of(context).textTheme.titleMedium)
                        : const SizedBox.shrink()),
              ),
            ),
            if (chrome.hasActions)
              Row(
                spacing: AppTheme.metrics.kSpace12,
                mainAxisSize: MainAxisSize.min,
                children: chrome.actions,
              ),
            if (chrome.hasToolbar)
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    height: chrome.toolbarHeight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Center(child: chrome.toolbar!),
                    ),
                  ),
                ),
              ),
            if (Platform.isWindows) const WindowsWindowButtons(),
          ],
        ),
      );
    });
  }
}
