import 'package:flutter/material.dart';
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

  /// Windows 三颗自绘灯用它渲染「最大化」还是「还原」图标。
  ///
  /// 这里只是最后已知状态的缓存，**不作为判断依据**：用户用系统按钮、快捷键或
  /// 双击标题栏改状态时它都可能滞后。真正的判断一律 `await windowManager.isMaximized()`。
  static bool isMaximized = true;

  /// 双击顶栏空白处：最大化 ⇄ 还原。
  static Future<void> handleDoubleTap() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    isMaximized = !maximized;
  }

  @override
  Widget build(BuildContext context) {
    // 高度对齐 DesktopTopBar（60）：本条被压在页面树**之下**（见 desktop_scaffold
    // 的 Stack 顺序说明），只负责接住没被控件覆盖的空白区的拖拽/双击，
    // 太矮会让顶栏下半截拖不动窗口，太高又会侵入正文可点区域。
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
      child: SizedBox(
        height: scaleW(60),
        // margin: EdgeInsets.only(left: PlatformUtil.isDesktop ? scaleW(250) : 0),
        // width: MediaQuery.of(context).size.width - scaleW(400),
        width: MediaQuery.of(context).size.width,
        // 这一层现在在页面之下，任何绘制都会盖住页面；保持完全空白。
        child: const SizedBox.expand(),
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
