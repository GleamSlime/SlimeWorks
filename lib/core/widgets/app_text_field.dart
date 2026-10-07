import 'package:flutter/material.dart';

import 'package:slime_works/core/theme/app_theme.dart';

/// 全项目输入框的统一入口。
///
/// 为什么需要它：Material 3 把输入正文写死成 `textTheme.bodyLarge`（本项目
/// 14 / 行高 1.7），而 `InputDecorationTheme` 里**没有** `style` 这一档——主题
/// 够不着它，只有 `TextField.style` 能改。放任各页面上手写 style，就会出现
/// 「占位符 13、打进去的字 14」「行高 1.7 把框撑得比同排按钮高一截」这类
/// 各处不一致的老问题。所以正文统一由这里发出，与主题的 hint/label 同源
/// （[AppTheme.fieldTextStyle]），调用点不需要也不应该再写字号。
///
/// [TextFormField] 全项目只有 5 处，不值得复制一份转发构造器，直接传
/// `style: AppTheme.fieldTextStyle` 即可。
class AppTextField extends TextField {
  const AppTextField({
    super.key,
    super.groupId,
    super.controller,
    super.focusNode,
    super.undoController,
    super.decoration,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textAlignVertical,
    super.textDirection,
    super.readOnly,
    super.showCursor,
    super.autofocus,
    super.statesController,
    super.obscuringCharacter,
    super.obscureText,
    super.autocorrect,
    super.smartDashesType,
    super.smartQuotesType,
    super.enableSuggestions,
    super.maxLines,
    super.minLines,
    super.expands,
    super.maxLength,
    super.maxLengthEnforcement,
    super.onChanged,
    super.onEditingComplete,
    super.onSubmitted,
    super.onAppPrivateCommand,
    super.inputFormatters,
    super.enabled,
    super.ignorePointers,
    super.cursorWidth,
    super.cursorHeight,
    super.cursorRadius,
    super.cursorOpacityAnimates,
    super.cursorColor,
    super.cursorErrorColor,
    super.selectionHeightStyle,
    super.selectionWidthStyle,
    super.keyboardAppearance,
    super.scrollPadding,
    super.dragStartBehavior,
    super.enableInteractiveSelection,
    super.selectAllOnFocus,
    super.selectionControls,
    super.onTap,
    super.onTapAlwaysCalled,
    super.onTapOutside,
    super.onTapUpOutside,
    super.mouseCursor,
    super.buildCounter,
    super.scrollController,
    super.scrollPhysics,
    super.autofillHints,
    super.contentInsertionConfiguration,
    super.clipBehavior,
    super.restorationId,
    super.stylusHandwritingEnabled,
    super.enableIMEPersonalizedLearning,
    super.contextMenuBuilder,
    super.canRequestFocus,
    super.spellCheckConfiguration,
    super.magnifierConfiguration,
    super.hintLocales,
  });

  /// 控件档正文 + 调用点自己的样式。
  ///
  /// 覆写的是 TextField 里那个 final 字段的读取器：TextField.build 走的是一次
  /// 虚调用，所以这里给的值就是它最终用的值。调用点显式传了 fontSize/height
  /// （等宽输入框、多行正文）时仍以调用点为准，只补齐它没写的那些档。
  @override
  TextStyle? get style => AppTheme.fieldTextStyle.merge(super.style);
}
