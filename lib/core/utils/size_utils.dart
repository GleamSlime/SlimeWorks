import 'dart:io';

import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 平台检测工具类
class PlatformUtil {
  /// 是否是桌面平台 (macOS 或 Windows)
  static bool get isDesktop => Platform.isMacOS || Platform.isWindows;

  /// 是否是移动平台 (iOS 或 Android)
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
}

double _adaptiveScaleFactor() {
  final double screenWidth = ScreenUtil().screenWidth;

  if (screenWidth <= 0) {
    return 1.0;
  }

  if (PlatformUtil.isMobile || screenWidth < 600) {
    if (screenWidth >= 430) {
      return 0.94;
    }
    if (screenWidth >= 390) {
      return 0.96;
    }
    return 1.0;
  }

  if (screenWidth >= 1920) {
    return 1.0;
  }
  if (screenWidth >= 1600) {
    return 1.02;
  }
  if (screenWidth >= 1366) {
    return 1.04;
  }
  return 1.06;
}

double _adaptiveFontScaleFactor() {
  final double factor = _adaptiveScaleFactor();

  if (factor > 1.0) {
    return 1.0 + ((factor - 1.0) * 0.5);
  }
  if (factor < 1.0) {
    return 1.0 - ((1.0 - factor) * 0.6);
  }
  return 1.0;
}

double scaleW(double w, {bool large = false}) {
  return ScreenUtil().setWidth(w * _adaptiveScaleFactor());
}

double scaleH(double h, {bool large = false}) {
  return ScreenUtil().setHeight(h * _adaptiveScaleFactor());
}

double scaleS(double fontSize, {bool large = false}) {
  return ScreenUtil().setSp(fontSize * _adaptiveFontScaleFactor());
}

bool get isPhone => ScreenUtil().screenWidth < 600;
bool get isPad => !isPhone && ScreenUtil().screenHeight < 900 || ScreenUtil().screenWidth < 900;

bool get isFold => ScreenUtil().screenHeight / ScreenUtil().screenWidth < 1.2;
