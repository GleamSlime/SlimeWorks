import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/buttons/svg_button.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/gen/assets.gen.dart';
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
        // color: Colors.red,
        child: Platform.isMacOS
            ? Obx(
                () => getIt<DesktopScreenProvider>().isMobile.value
                    ? const MacWindowButtons()
                    : SizedBox.shrink(),
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
    return Row(
      spacing: AppTheme.metrics.kSpace8,
      mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.start,
      children: [
        HoverSvgButton(
          svg: Assets.image.svg.macToolsCloseNoHover,
          hoverSvg: Assets.image.svg.macToolsClose,
          onTap: windowManager.close,
          size: 13,
        ),
        HoverSvgButton(
          svg: Assets.image.svg.macToolsUnfoldNoHover,
          hoverSvg: Assets.image.svg.macToolsUnfold,
          onTap: windowManager.minimize,
          size: 13,
        ),
        HoverSvgButton(
          svg: Assets.image.svg.macToolsMaxNoHover,
          hoverSvg: ScreenTopBar.isMaximized
              ? Assets.image.svg.macToolsMax
              : Assets.image.svg.macToolsMin,
          onTap: ScreenTopBar.handleDoubleTap,
          size: 13,
        ),
      ],
    );
  }
}

class WindowsWindowButtons extends StatelessWidget {
  const WindowsWindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      spacing: AppTheme.metrics.kSpace10,
      children: [
        InkWell(
          borderRadius: AppTheme.metrics.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: windowManager.minimize,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(
              child: SvgPicture.asset(
                Assets.image.svg.windowsToolsUnfold,
                width: AppTheme.metrics.fontSize16,
              ),
            ),
          ),
        ),
        InkWell(
          borderRadius: AppTheme.metrics.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: ScreenTopBar.handleDoubleTap,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(
              child: SvgPicture.asset(
                ScreenTopBar.isMaximized
                    ? Assets.image.svg.windowsToolsMax
                    : Assets.image.svg.windowsToolsMin,
                width: AppTheme.metrics.fontSize16,
              ),
            ),
          ),
        ),
        InkWell(
          borderRadius: AppTheme.metrics.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: windowManager.close,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(
              child: SvgPicture.asset(
                Assets.image.svg.windowsToolsClose,
                width: AppTheme.metrics.fontSize16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
