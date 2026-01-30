import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/buttons/svg_button.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/gen/assets.gen.dart';
import 'package:slime_works/core/utils/size_utils.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  static bool isMaximized = true;

  static Future<void> handleDoubleTap() async {
    bool isMini = await windowManager.isMaximized();
    if (isMini) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }

    CustomTitleBar.isMaximized = isMini;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: handleDoubleTap,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: scaleW(70),
        // margin: EdgeInsets.only(left: PlatformUtil.isDesktop ? scaleW(250) : 0),
        width: MediaQuery.of(context).size.width - scaleW(400),
        padding: EdgeInsets.symmetric(horizontal: AppThemeCommon.kSpace4),
        // color: Colors.red,
        child: Platform.isMacOS ? const MacWindowButtons() : null,
      ),
    );
  }
}

class MacWindowButtons extends StatelessWidget {
  const MacWindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: AppThemeCommon.kSpace8,
      children: [
        SizedBox(width: AppThemeCommon.kSpace8),
        HoverSvgButton(
          svg: Assets.image.svg.macToolsCloseNoHover,
          hoverSvg: Assets.image.svg.macToolsClose,
          onTap: windowManager.close,
          size: AppThemeCommon.fontSize16,
        ),
        HoverSvgButton(
          svg: Assets.image.svg.macToolsUnfoldNoHover,
          hoverSvg: Assets.image.svg.macToolsUnfold,
          onTap: windowManager.minimize,
          size: AppThemeCommon.fontSize16,
        ),
        HoverSvgButton(
          svg: Assets.image.svg.macToolsMaxNoHover,
          hoverSvg: CustomTitleBar.isMaximized ? Assets.image.svg.macToolsMax : Assets.image.svg.macToolsMin,
          onTap: CustomTitleBar.handleDoubleTap,
          size: AppThemeCommon.fontSize16,
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
      spacing: AppThemeCommon.kSpace10,
      children: [
        InkWell(
          borderRadius: AppThemeCommon.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: windowManager.minimize,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(child: SvgPicture.asset(Assets.image.svg.windowsToolsUnfold, width: AppThemeCommon.fontSize16)),
          ),
        ),
        InkWell(
          borderRadius: AppThemeCommon.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: CustomTitleBar.handleDoubleTap,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(
              child: SvgPicture.asset(
                CustomTitleBar.isMaximized ? Assets.image.svg.windowsToolsMax : Assets.image.svg.windowsToolsMin,
                width: AppThemeCommon.fontSize16,
              ),
            ),
          ),
        ),
        InkWell(
          borderRadius: AppThemeCommon.radius32,
          hoverColor: theme.colorScheme.onSurface.withAlpha(13),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: windowManager.close,
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: scaleW(40),
            height: scaleW(40),
            child: Center(child: SvgPicture.asset(Assets.image.svg.windowsToolsClose, width: AppThemeCommon.fontSize16)),
          ),
        ),
      ],
    );
  }
}
