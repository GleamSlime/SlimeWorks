import 'dart:io';

import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 平台检测工具类
class PlatformUtil {
  /// 是否是桌面平台 (macOS 或 Windows)
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows;

  /// 是否是移动平台 (iOS 或 Android)
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
}

double scaleW(double w, {bool large = false}) {
  // if (isPhone) {
  //   w = w * 2;
  // } else if (isPad) {
  //   w *= 1.7;
  // } else if (ScreenUtil().screenWidth >= 1920) {
  //   w = w * 0.7;
  // }
  return ScreenUtil().setWidth(w);
}

double scaleH(double h, {bool large = false}) {
  // if (isPhone) {
  //   w = w * 1.9;
  // } else if (isPad) {
  //   w *= 1.7;
  // } else if (ScreenUtil().screenWidth >= 1920) {
  //   w = w * 0.7;
  // }
  return ScreenUtil().setHeight(h);
}

double scaleS(double fontSize, {bool large = false}) {
  // if (isPhone) {
  //   fontSize = fontSize * 2.2;
  // } else if (isPad) {
  //   fontSize *= 1.7;
  // } else if (ScreenUtil().screenWidth >= 1920) {
  //   fontSize = fontSize * 0.7;
  // }

  return ScreenUtil().setSp(fontSize);
}

bool get isPhone => ScreenUtil().screenWidth < 600;
bool get isPad => !isPhone && ScreenUtil().screenHeight < 900 || ScreenUtil().screenWidth < 900;

bool get isFold => ScreenUtil().screenHeight / ScreenUtil().screenWidth < 1.2;
