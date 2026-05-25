import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/utils/logger.dart';
const Loggers _logger = Loggers(name: '窗口位置');


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
      _logger.info(
        '保存窗口位置: x=${position.dx}, y=${position.dy}, width=${size.width}, height=${size.height}',
      );
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
      _logger.info('恢复窗口位置: x=$x, y=$y, width=$width, height=$height');
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

      return Rect.fromLTWH(
        0,
        0,
        physicalSize.width / devicePixelRatio,
        physicalSize.height / devicePixelRatio,
      );
    } catch (e) {
      if (kDebugMode) {
        _logger.error('获取屏幕边界失败: $e');
      }
      return null;
    }
  }

  /// 检查位置是否有效（兼容多屏幕，允许窗口在任意屏幕上）
  Future<bool> _isPositionValid(double x, double y, double width, double height) async {
    // 只做基础合理性检查：坐标值在可接受范围内（-8000 ~ 20000 覆盖绝大多数多屏桌面布局）
    const double kMinCoord = -8000;
    const double kMaxCoord = 20000;
    if (x < kMinCoord || x > kMaxCoord || y < kMinCoord || y > kMaxCoord) {
      return false;
    }
    // 窗口尺寸合理性
    if (width < 100 || height < 100 || width > 10000 || height > 10000) {
      return false;
    }
    return true;
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
