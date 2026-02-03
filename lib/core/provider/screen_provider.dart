import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart';

bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
bool isMobile = Platform.isAndroid || Platform.isIOS;

abstract class DesktopScreenProvider {
  /// 最小宽度
  double minWidth = 1200;

  /// 最小高度
  double minHeight = 800;

  /// 窗口尺寸
  Rx<Size> get size => Rx<Size>(Size(double.parse(dotenv.env['APP_SIZE_WIDTH'] ?? "1520"), double.parse(dotenv.env['APP_SIZE_HEIGHT'] ?? "1050")));

  /// 窗口标题
  RxString title = (dotenv.env['APP_NAME'] ?? "").obs;

  /// 窗口头部工具栏组件
  Rx<Widget> screenHeadToolsWidget = Rx<Widget>(Container());

  /// 窗口宽度
  RxDouble width = double.parse(dotenv.env['APP_SIZE_WIDTH'] ?? "1520").obs;

  /// 窗口高度
  RxDouble height = double.parse(dotenv.env['APP_SIZE_HEIGHT'] ?? "1050").obs;

  /// 是否为桌面端
  RxBool get isDesktop => RxBool(width.value > 600 || Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 是否为移动端
  RxBool get isMobile => RxBool(width.value <= 600 || Platform.isAndroid || Platform.isIOS);

  /// 设置窗口宽度
  void setWidth(double w);

  /// 设置窗口高度
  void setHeight(double h);

  /// 设置窗口标题
  void setTitle(String t);

  /// 设置窗口头部工具栏组件
  void setScreenHeadToolsWidget(Widget widget);
}
