import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:slime_works/components/window/desktop_layout.dart';

class SizeUtils {
  static const navigationBarHeight = 128.0;

  static const homeNavigationBarHeight = 115.0;

  static int appWidth = int.parse(dotenv.env['APP_SIZE_WIDTH'] ?? '1520');
}

double scaleW(double w, {bool large = false}) {
  if (isPhone) {
    w = w * 3.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    w = w * 0.7;
  }
  return ScreenUtil().setWidth(w);
}

double scaleH(double w, {bool large = false}) {
  if (isPhone) {
    w = w * 3.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    w = w * 0.7;
  }
  return ScreenUtil().setHeight(w);
}

double scaleS(double fontSize, {bool large = false}) {
  if (isPhone) {
    fontSize = fontSize * 3.2;
  }
  if (ScreenUtil().screenWidth >= 1920) {
    fontSize = fontSize * 0.7;
  }
  double baseSize = ScreenUtil().setSp(fontSize);

  if (PlatformUtil.isDesktop || ScreenUtil().screenWidth > 600) {
    baseSize += (ScreenUtil().screenWidth / SizeUtils.appWidth);
  }

  return baseSize;
}

bool get isPhone => ScreenUtil().screenHeight < 600 || ScreenUtil().screenWidth < 600;

bool get isFold => ScreenUtil().screenHeight / ScreenUtil().screenWidth < 1.2;
