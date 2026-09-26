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
import 'package:slime_works/core/theme/app_motion.dart';
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
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: scaleH(40),
        // margin: EdgeInsets.only(left: PlatformUtil.isDesktop ? scaleW(250) : 0),
        // width: MediaQuery.of(context).size.width - scaleW(400),
        width: MediaQuery.of(context).size.width,
        padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace4),
        child: Platform.isMacOS
            ? Obx(
                () => getIt<DesktopScreenProvider>().isMobile.value
                    ? const MacWindowButtons()
                    : const SizedBox.shrink(),
              )
            : null,
      ),
    );
  }
}

class MacWindowButtons extends StatelessWidget {
  final MainAxisAlignment? mainAxisAlignment;

  const MacWindowButtons({super.key, this.mainAxisAlignment});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    // 三颗灯只跟窗口缩放（scaleW），不吃用户的字号比例：系统的红黄绿从不随字体
    // 变大，而收起态那条栏只有 75 设计像素宽，字号一过 1.5 这一排就把侧栏顶穿。
    return Row(
      spacing: AppTheme.metrics.kSpace8,
      mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.start,
      children: [
        _MacLight(
          icon: StrokeIcons.assetMacToolsClose,
          role: s.danger,
          label: '关闭',
          onTap: windowManager.close,
        ),
        _MacLight(
          icon: StrokeIcons.assetMacToolsUnfold,
          role: s.warning,
          label: '最小化',
          onTap: windowManager.minimize,
        ),
        _MacLight(
          // 最大化/还原两态共用一枚绿灯：符号跟着状态换，切换时旧的擦回去、新的描出来
          icon: ScreenTopBar.isMaximized
              ? StrokeIcons.assetMacToolsMax
              : StrokeIcons.assetMacToolsMin,
          role: s.success,
          label: '最大化/还原',
          onTap: ScreenTopBar.handleDoubleTap,
        ),
      ],
    );
  }
}

/// macOS 窗口灯：闲置是一枚实心圆，符号只在指针进来时描出来、出去时擦回去
///
/// 闲置无符号是系统约定（原来那两张 `*_no_hover` 资产画的就是纯圆），所以这一处
/// 不吃 [DrawIcon] 的"出现即描一次"，改用 manual 把进度直接交给悬停动画。
class _MacLight extends StatefulWidget {
  const _MacLight({
    required this.icon,
    required this.role,
    required this.label,
    required this.onTap,
  });

  final StrokeIcon icon;
  final AppStatusRole role;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MacLight> createState() => _MacLightState();
}

class _MacLightState extends State<_MacLight> with SingleTickerProviderStateMixin {
  /// 灯珠直径（设计稿像素）。不走 `metrics.iconSize13`：那是字号族、还要乘用户字号
  /// 比例，而系统的红黄绿从不随字体变大，收起态那条 75 宽的栏一排就被顶穿。
  static const double _kDiscSize = 13;

  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
    // 移开要利落：留在原地慢慢淡出会让人觉得这一排卡住了
    reverseDuration: AppMotion.instant,
  );
  final StrokeController _stroke = StrokeController();

  @override
  void initState() {
    super.initState();
    _reveal.addListener(() => _stroke.progress = _reveal.value);
  }

  @override
  void dispose() {
    _reveal.dispose();
    _stroke.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _reveal.forward(),
      onExit: (_) => _reveal.reverse(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.role.color,
          ),
          child: SizedBox(
            width: scaleW(_kDiscSize),
            height: scaleW(_kDiscSize),
            child: Center(
              child: DrawIcon(
                widget.icon,
                size: scaleW(_kDiscSize * 0.62),
                color: widget.role.onContainer,
                // 8 像素见方里，Tabler 原图的 2 号笔会细成一条缝
                weight: 3,
                trigger: StrokeTrigger.manual,
                controller: _stroke,
                semanticLabel: widget.label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WindowsWindowButtons extends StatelessWidget {
  const WindowsWindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final size = AppTheme.metrics.fontSize15;

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
