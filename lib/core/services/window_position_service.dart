import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

/// 窗口位置存储服务
class WindowPositionService extends GetxService {
  static const String _keyX = 'window_position_x';
  static const String _keyY = 'window_position_y';
  static const String _keyWidth = 'window_width';
  static const String _keyHeight = 'window_height';
  static const String _keyScreenLeft = 'window_screen_left';
  static const String _keyScreenTop = 'window_screen_top';

  late SharedPreferences? _pref;

  double get windowWidth {
    return _pref?.getDouble(_keyWidth) ?? getIt.get<DesktopScreenProvider>().width.value;
  }

  double get windowHeight {
    return _pref?.getDouble(_keyHeight) ?? getIt.get<DesktopScreenProvider>().height.value;
  }

  double get windowX {
    return _pref?.getDouble(_keyX) ?? 0;
  }

  double get windowY {
    return _pref?.getDouble(_keyY) ?? 0;
  }

  /// 初始化服务
  Future<WindowPositionService> init() async {
    try {
      _pref = await SharedPreferences.getInstance();
    } catch (e) {
      _pref = null;
    }
    return this;
  }

  /// 保存窗口位置和大小
  Future<void> savePosition() async {
    if (_pref == null) return;

    final position = await windowManager.getPosition();
    final size = await windowManager.getSize();

    await _pref!.setDouble(_keyX, position.dx);
    await _pref!.setDouble(_keyY, position.dy);
    await _pref!.setDouble(_keyWidth, size.width);
    await _pref!.setDouble(_keyHeight, size.height);

    DesktopScreenProvider desktopScreen = getIt.get<DesktopScreenProvider>();
    desktopScreen.setWidth(size.width);
    desktopScreen.setHeight(size.height);

    final bounds = await _getScreenBounds();

    if (bounds != null) {
      await _pref!.setDouble(_keyScreenLeft, bounds.left);
      await _pref!.setDouble(_keyScreenTop, bounds.top);
    }

    if (kDebugMode) {
      print('保存窗口位置: x=${position.dx}, y=${position.dy}, width=${size.width}, height=${size.height}');
    }
  }

  /// 恢复窗口位置和大小
  Future<void> restorePosition() async {
    if (_pref == null) {
      // 如果 SharedPreferences 不可用，使用默认居中位置
      await windowManager.center();
      return;
    }

    final x = _pref!.getDouble(_keyX);
    final y = _pref!.getDouble(_keyY);
    final width = _pref!.getDouble(_keyWidth);
    final height = _pref!.getDouble(_keyHeight);
    if (x != null && y != null && width != null && height != null) {
      // 检查保存的位置是否仍然有效（屏幕可能已改变）
      if (await _isPositionValid(x, y, width, height)) {
        await windowManager.setPosition(Offset(x, y));
        await windowManager.setSize(Size(width, height));
      } else {
        // 如果位置无效，使用默认居中位置
        await windowManager.center();
      }
    }

    if (kDebugMode) {
      print('恢复窗口位置: x=$x, y=$y, width=$width, height=$height');
    }
  }

  /// 获取当前屏幕边界
  Future<Rect?> _getScreenBounds() async {
    try {
      // 注意: Flutter 目前没有直接的 API 获取屏幕边界
      // 这里使用一个简单的方法：假设主屏幕从 (0,0) 开始
      // 在多屏幕环境中，可能需要使用平台特定的代码
      final view = PlatformDispatcher.instance.views.first;
      final physicalSize = view.physicalSize;
      final devicePixelRatio = view.devicePixelRatio;

      return Rect.fromLTWH(0, 0, physicalSize.width / devicePixelRatio, physicalSize.height / devicePixelRatio);
    } catch (e) {
      if (kDebugMode) {
        print('获取屏幕边界失败: $e');
      }
      return null;
    }
  }

  /// 检查位置是否有效（是否在任何屏幕范围内）
  Future<bool> _isPositionValid(double x, double y, double width, double height) async {
    try {
      final screenBounds = await _getScreenBounds();
      if (screenBounds == null) return false;

      // 检查窗口至少有一部分在屏幕内
      final windowRect = Rect.fromLTWH(x, y, width, height);

      // 确保窗口中心点在屏幕范围内（允许一些容差）
      final center = windowRect.center;

      // 扩展屏幕边界检查，允许窗口部分在屏幕外（多屏幕场景）
      // 只要窗口的右下角或左上角在合理范围内即可
      return center.dx >= -width / 2 &&
          center.dx <= screenBounds.right + width / 2 &&
          center.dy >= -height / 2 &&
          center.dy <= screenBounds.bottom + height / 2;
    } catch (e) {
      if (kDebugMode) {
        print('检查位置有效性失败: $e');
      }
      return false;
    }
  }

  /// 清除保存的位置信息
  Future<void> clearPosition() async {
    if (_pref == null) return;

    await _pref!.remove(_keyX);
    await _pref!.remove(_keyY);
    await _pref!.remove(_keyWidth);
    await _pref!.remove(_keyHeight);
    await _pref!.remove(_keyScreenLeft);
    await _pref!.remove(_keyScreenTop);
  }
}
