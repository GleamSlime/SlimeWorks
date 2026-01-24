import 'dart:ffi';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SizeUtils {
  static const navigationBarHeight = 128.0;

  static const homeNavigationBarHeight = 115.0;

  static int appWidth = int.parse(dotenv.env['APP_SIZE_WIDTH'] ?? '1520');
}

double scaleW(double w, {bool large = false}) {
  if (isPhone && large) {
    w = w * 1.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    w = w * 0.7;
  }
  return ScreenUtil().setWidth(w);
}

double scaleH(double w, {bool large = false}) {
  if (isPhone && large) {
    w = w * 1.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    w = w * 0.7;
  }
  return ScreenUtil().setHeight(w);
}

double scaleS(double fontSize, {bool large = false}) {
  if (isPhone && large) {
    fontSize = fontSize * 1.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    fontSize = fontSize * 0.7;
  }
  return ScreenUtil().setSp(fontSize) + (ScreenUtil().screenWidth / SizeUtils.appWidth);
}

bool get isPhone => ScreenUtil().screenHeight < 600;

bool get isFold => ScreenUtil().screenHeight / ScreenUtil().screenWidth < 1.2;
