import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/buttons/svg_button.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/gen/assets.gen.dart';

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
        height: scaleH(60),
        margin: EdgeInsets.only(left: PlatformUtil.isDesktop ? scaleW(250) : 0),
        // width: MediaQuery.of(context).size.width - scaleW(250),
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        // color: Colors.red,
        child: Platform.isMacOS ? const _MacWindowButtons() : null,
      ),
    );
  }
}

class _MacWindowButtons extends StatelessWidget {
  const _MacWindowButtons();

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
