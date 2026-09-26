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
import 'package:slime_works/components/window/collapsible_sidebar.dart';
import 'package:slime_works/components/window/screen_top_bar.dart';
import 'package:slime_works/components/window/window_backdrop.dart';

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

    // 先探一次系统材质：窗口底色要不要留透明，取决于材质有没有真的挂上。
    // 必须在下面拼 WindowOptions 之前 await 完，否则首帧会先实心再闪成磨砂。
    // 申请压克力而非 Mica：压克力会对窗口背后的桌面做实时高斯模糊，才是磨砂质感；
    // Mica 只是壁纸的静态着色，看起来更像直接透过去。系统拒绝时原生回退为 none，
    // 界面按 WindowGlass 的判断退回实心底。
    await WindowsBackdrop.probe(requested: BackdropKind.acrylic);

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
      // macOS 下原生窗口底色必须留透明，否则 MainFlutterWindow 挂的振动层
      // 会被这层不透明底色彻底盖住。
      backgroundColor: WindowGlass.sidebar ? Colors.transparent : AppSemantic.light.surface,
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

    // 窗口底色落地之后必须把材质重新挂一遍：window_manager 的透明底色走的是
    // 老 Accent 策略（SetWindowCompositionAttribute / TRANSPARENTGRADIENT），
    // 它会盖掉先挂上的 DWM 背景材质——症状就是窗口「穿透但不模糊」。
    // 顺序是 探材质 → 拼 WindowOptions → waitUntilReadyToShow 落 Accent → 重挂材质。
    await WindowsBackdrop.reapply();
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
    // macOS 桌面端不再由根层铺满不透明底色，否则侧栏永远透不出桌面内容。
    // 内容区的不透明改由 _DesktopShell 自己补——两侧职责分开：侧栏留透明，
    // 主区必须实心，否则文字会直接压在桌面上。
    final bool bleedThroughWindow = WindowGlass.sidebar && !isMobile;
    return Material(
      color: bleedThroughWindow ? Colors.transparent : AppSemantic.of(context).canvas,
      child: isMobile
          ? widget.child
          : Stack(
              children: [
                Positioned.fill(
                  child: Obx(() {
                    final String path = getIt<DesktopScreenProvider>().globalBackgroundPath.value;
                    return AnimatedSwitcher(
                      duration: AppMotion.base,
                      reverseDuration: AppMotion.fast,
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
          child: ColoredBox(color: AppSemantic.of(context).canvas.withAlpha(120)),
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
      // 面包屑和标题占同一格、互斥：叠成上下两行会把 60 高的顶栏挤爆，
      // 而且"标题 + 上面一行小标题"读起来像两个页面粘在一起。
      // 页面给了自定义标题位（带控件的标题）就不抢，它比路由名更有信息量。
      final trail = chrome.hasBreadcrumb
          ? chrome.breadcrumb!
          : (chrome.titleWidget != null
                ? null
                : AppRoutes.breadcrumbFor(
                    Get.find<SidebarController>().selectedRoute.value,
                    navigate: (location) => goRouter.go(location),
                    leafLabel: chrome.title,
                  ));

      // 侧栏收进隐藏态后，原来住在栏顶的 macOS 三颗灯没了落脚点，
      // 借顶栏左端这一格。往右让开一截是给内容区左缘的指示条留命中区，
      // 否则红灯被那 22 宽的把手吃掉半截。
      // 跟手拖出途中侧栏顶的灯已经画出来了，顶栏这一盏要熄，否则一处两套灯；
      // 这时候栏比灯还窄，硬塞进顶栏 Row 就是那条 RenderFlex overflowed。
      final sidebar = Get.find<SidebarController>();
      final lightsHere =
          Platform.isMacOS && sidebar.isHidden.value && !sidebar.following.value;

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
            if (lightsHere)
              Padding(
                padding: EdgeInsets.only(left: scaleW(16)),
                child: const MacWindowButtons(),
              ),
            if (chrome.hasLeading) chrome.leading!,
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: trail != null
                    ? Breadcrumb(entries: trail)
                    : (chrome.titleWidget ??
                          (chrome.title != null
                              ? Text(chrome.title!, style: Theme.of(context).textTheme.titleMedium)
                              : const SizedBox.shrink())),
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
