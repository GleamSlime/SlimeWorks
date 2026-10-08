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
import 'package:slime_works/components/window/live_frost.dart';
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

    // 「实时半透明」是系统材质失效时的自绘兜底：偏好开着就把抓帧链路拉起来，
    // 它会把窗口底色切成透明；必须在拼 WindowOptions 前完成，首帧就是磨砂。
    await LiveFrost.restore();
    final bool liveFrostOn = LiveFrost.running.value;

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
      // 会被这层不透明底色彻底盖住。Windows 开「实时半透明」时同理，磨砂帧
      // 要透过窗口底显示。
      backgroundColor: (WindowGlass.sidebar || liveFrostOn)
          ? Colors.transparent
          : AppSemantic.light.surface,
      // macOS 直接用系统原生红黄绿：伪装按钮在新系统的玻璃材质上怎么调都不像。
      // Windows 仍是自绘的 WindowsWindowButtons，这里保持隐藏。
      windowButtonVisibility: Platform.isMacOS,
      title: desktopScreen.title.value,
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setMinimumSize(const Size(_minWidth, _minHeight));
      await windowManager.setAspectRatio(_aspectRatio);
      // 恢复上次的窗口位置
      await positionService.restorePosition();
      // 归位后强制补抓一帧：启动瞬间抓的那帧是在窗口还没挪到保存位置时抓的，
      // 位置是错的；而程序化移动不会产生 WM_EXITSIZEMOVE、onWindowMoved 不触发，
      // 不主动补抓磨砂就会一直停在错误区域（看起来像「拍了左上角、还放大了」）。
      // refresh 作废旧矩形逼心跳立即重抓，跟帧循环会一直跟到宽高比/最小尺寸
      // 约束的收敛结束。
      await LiveFrost.refresh();
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
    // 窗口移动时保存位置。磨砂的重抓不再依赖这里——LiveFrost 心跳会自查矩形
    // 变化，本机 window_manager 的移动/缩放事件实测不可靠。
    _positionService?.savePosition();
  }

  @override
  void onWindowFocus() {
    // 失焦期间背后的桌面可能已经变了（别的窗口开关、移动、换内容），心跳只盯
    // 自身矩形发现不了这些；重新聚焦时强制补抓一帧，让磨砂和桌面保持同步。
    LiveFrost.refresh();
  }

  @override
  void onWindowMinimize() {
    // 看不见的时候别闪帧，也省掉无谓的抓帧开销
    LiveFrost.setPaused(true);
  }

  @override
  void onWindowRestore() {
    LiveFrost.setPaused(false);
  }

  @override
  void onWindowResize() {
    AppTheme.resetMetrics();
  }

  @override
  void onWindowResized() {
    // 窗口大小改变时保存；磨砂重抓由 LiveFrost 心跳自查矩形变化驱动。
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
    // Windows「实时半透明」运行中同理：磨砂帧就是窗口底，根层必须透明。
    final bool liveFrost =
        LiveFrost.supported && getIt<DesktopScreenProvider>().liveFrostActive.value;
    final bool bleedThroughWindow =
        (WindowGlass.sidebar || liveFrost) && !isMobile;
    return Material(
      color: bleedThroughWindow ? Colors.transparent : AppSemantic.of(context).canvas,
      child: isMobile
          ? widget.child
          : Stack(
              children: [
                Positioned.fill(
                  child: liveFrost
                      // 系统材质在这台 26200 上不渲染，磨砂由实时抓帧自绘。
                      ? const LiveFrostBackdrop()
                      : Obx(() {
                          final String path =
                              getIt<DesktopScreenProvider>().globalBackgroundPath.value;
                          return AnimatedSwitcher(
                            duration: AppMotion.base,
                            reverseDuration: AppMotion.fast,
                            child: path.isEmpty
                                ? const SizedBox.shrink()
                                : _GlobalBlurBackground(
                                    key: ValueKey<String>(path), coverPath: path),
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

      // 侧栏隐藏后栏顶那三颗灯没落脚点了，借顶栏左端这一格占位。
      // 原生灯常驻整窗左上角，这里只让出等大空白避免内容被压；跟手拖出途中
      // 栏比灯还窄，硬塞进顶栏 Row 就是那条 RenderFlex overflowed，故沿用同一判据。
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
            if (lightsHere) const MacWindowButtonsReserve(withLeadingGap: true),
            if (chrome.hasLeading) chrome.leading!,
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: trail != null
                    ? Breadcrumb(entries: trail)
                    : (chrome.titleWidget ??
                          (chrome.title != null
                              ? Text(
                                  chrome.title!,
                                  // 标题字号跟着用户字体比例走，长标题只截断不换行：
                                  // 这一栏高度是定值，换行就是把整条顶破
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.role(
                                    context,
                                    fontSize: AppTheme.metrics.fontSize14,
                                    weight: FontWeight.w500,
                                    color: AppSemantic.of(context).textPrimary,
                                  ),
                                )
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
