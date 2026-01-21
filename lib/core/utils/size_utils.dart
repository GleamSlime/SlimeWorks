import 'package:flutter_screenutil/flutter_screenutil.dart';

class SizeUtils {
  static const navigationBarHeight = 128.0;

  static const homeNavigationBarHeight = 115.0;
}

double scaleW(double w, {bool large = false}) {
  if (isPhone && large) {
    w = w * 1.2;
  }
  return ScreenUtil().setWidth(w);
}

double scaleH(double w, {bool large = false}) {
  if (isPhone && large) {
    w = w * 1.2;
  }
  return ScreenUtil().setHeight(w);
}

double scaleS(double fontSize, {bool large = false}) {
  if (isPhone && large) {
    fontSize = fontSize * 1.2;
  }
  return ScreenUtil().setSp(fontSize);
}

bool get isPhone => ScreenUtil().screenHeight < 600;

bool get isFold => ScreenUtil().screenHeight / ScreenUtil().screenWidth < 1.2;
