import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/icons/stroke_zone.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class ScreenTopBar extends StatelessWidget {
  const ScreenTopBar({super.key});

  static bool isMaximized = true;

  static Future<void> handleDoubleTap() async {
    bool isMini = await windowManager.isMaximized();
    if (isMini) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }

    ScreenTopBar.isMaximized = isMini;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: handleDoubleTap,
      onPanStart: (_) {
        // 只交给系统拖拽。磨砂那边不需要在这里挂「拖拽中」标志：startDragging
        // 一旦把指针交给系统，Flutter 就再也收不到 onPanEnd，那个标志会永久卡在
        // true，把重抓彻底锁死（实测拖一次窗口之后磨砂就再也不更新）。
        // 不锁也不闪：LiveFrost 心跳发现矩形在变就不抓，等它停下才补一帧。
        windowManager.startDragging();
      },
      child: Container(
        height: scaleH(40),
        // margin: EdgeInsets.only(left: PlatformUtil.isDesktop ? scaleW(250) : 0),
        // width: MediaQuery.of(context).size.width - scaleW(400),
        width: MediaQuery.of(context).size.width,
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace4),
        child: Platform.isMacOS
            ? Obx(
                () => getIt<DesktopScreenProvider>().isMobile.value
                    ? const MacWindowButtonsReserve()
                    : const SizedBox.shrink(),
              )
            : null,
      ),
    );
  }
}

/// macOS 原生红黄绿的等大占位。
///
/// 窗口现在直接用系统按钮（`windowButtonVisibility: true`），Flutter 侧不再自绘；
/// 但原生按钮常驻在整窗左上角，会压住侧栏顶部与顶栏左端的内容，所以那两处留出
/// 与三颗灯等大的空白。尺寸对齐原生灯的实际占位，保证撤下自绘按钮后布局不位移。
class MacWindowButtonsReserve extends StatelessWidget {
  /// 是否额外让出一段左内边距（顶栏左端用，与原来的 lightsHere 缩进一致）
  final bool withLeadingGap;

  const MacWindowButtonsReserve({super.key, this.withLeadingGap = false});

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final lightsWidth = scaleW(13) * 3 + m.kSpace8 * 2;
    return SizedBox(
      width: withLeadingGap ? scaleW(16) + lightsWidth : lightsWidth,
      height: scaleW(13),
    );
  }
}

class WindowsWindowButtons extends StatelessWidget {
  const WindowsWindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    // 这三颗灯住在定宽定高的按钮盒里（下面那个 SizedBox 走的是宽度族），字形尺寸
    // 必须同族：用了随字号缩放的那一族，用户把字号拉到 2.0 就会把这排顶穿。
    final size = scaleW(15);

    Widget button(StrokeIcon icon, String label, VoidCallback onTap) {
      // StrokeZone 包在 InkWell 外：悬停水洗由 InkWell 的 hoverColor 负责，
      // 这一层只把"按下/进入"广播给里面的图标，两者互不打架。
      return StrokeZone(
        child: InkWell(
          borderRadius: AppTheme.metrics.radius32,
          hoverColor: s.surfaceHover,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(
              child: DrawIcon(
                icon,
                size: size,
                color: s.textPrimary,
                trigger: StrokeTrigger.press,
                semanticLabel: label,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      spacing: AppTheme.metrics.kSpace10,
      children: [
        button(StrokeIcons.assetWindowsToolsUnfold, '最小化', windowManager.minimize),
        button(
          ScreenTopBar.isMaximized
              ? StrokeIcons.assetWindowsToolsMax
              : StrokeIcons.assetWindowsToolsMin,
          '最大化/还原',
          ScreenTopBar.handleDoubleTap,
        ),
        button(StrokeIcons.assetWindowsToolsClose, '关闭', windowManager.close),
      ],
    );
  }
}
