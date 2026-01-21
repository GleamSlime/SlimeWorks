import 'package:flutter/material.dart';

/// 应用字体大小定义
/// 基于设计稿中的排版规范
class AppFontSizes {
  AppFontSizes._();

  // 标题字体大小
  static const double h1 = 96.0;
  static const double h2 = 60.0;
  static const double h3 = 48.0;
  static const double h4 = 34.0;
  static const double h5 = 24.0;
  static const double h6 = 20.0;

  // 副标题字体大小
  static const double subtitle1 = 16.0;
  static const double subtitle2 = 14.0;

  // 正文字体大小
  static const double body1 = 16.0;
  static const double body2 = 14.0;
  static const double body3 = 12.0;

  // 按钮字体大小
  static const double button = 14.0;

  // 标签字体大小
  static const double caption = 12.0;

  // 小标签字体大小
  static const double overline = 10.0;
}

/// 字体权重定义
class AppFontWeights {
  AppFontWeights._();

  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

/// 应用文本样式定义
class AppTextStyles {
  AppTextStyles._();

  // H1 标题样式
  static TextStyle h1({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h1,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.2,
  );

  // H2 标题样式
  static TextStyle h2({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h2,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.2,
  );

  // H3 标题样式
  static TextStyle h3({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h3,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.3,
  );

  // H4 标题样式
  static TextStyle h4({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h4,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.3,
  );

  // H5 标题样式
  static TextStyle h5({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h5,
    fontWeight: fontWeight ?? AppFontWeights.medium,
    color: color,
    height: 1.4,
  );

  // H6 标题样式
  static TextStyle h6({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.h6,
    fontWeight: fontWeight ?? AppFontWeights.medium,
    color: color,
    height: 1.4,
  );

  // Subtitle1 样式
  static TextStyle subtitle1({Color? color, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: AppFontSizes.subtitle1,
        fontWeight: fontWeight ?? AppFontWeights.medium,
        color: color,
        height: 1.5,
      );

  // Subtitle2 样式
  static TextStyle subtitle2({Color? color, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: AppFontSizes.subtitle2,
        fontWeight: fontWeight ?? AppFontWeights.medium,
        color: color,
        height: 1.5,
      );

  // Body1 样式
  static TextStyle body1({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.body1,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.5,
  );

  // Body2 样式
  static TextStyle body2({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.body2,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.5,
  );

  // Body3 样式
  static TextStyle body3({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.body3,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.5,
  );

  // Button 样式
  static TextStyle button({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.button,
    fontWeight: fontWeight ?? AppFontWeights.medium,
    color: color,
    height: 1.2,
    letterSpacing: 0.5,
  );

  // Caption 样式
  static TextStyle caption({Color? color, FontWeight? fontWeight}) => TextStyle(
    fontSize: AppFontSizes.caption,
    fontWeight: fontWeight ?? AppFontWeights.regular,
    color: color,
    height: 1.4,
  );

  // Overline 样式
  static TextStyle overline({Color? color, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: AppFontSizes.overline,
        fontWeight: fontWeight ?? AppFontWeights.regular,
        color: color,
        height: 1.5,
        letterSpacing: 1.5,
      );
}
