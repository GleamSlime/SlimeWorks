import 'dart:io';

import 'package:flutter/material.dart' hide MenuItem;
import 'package:get/get.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayService extends GetxService with TrayListener {
  @override
  void onInit() {
    super.onInit();
    trayManager.addListener(this);
  }

  @override
  void onClose() {
    trayManager.removeListener(this);
    trayManager.destroy();
    super.onClose();
  }

  Future<void> init() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    final String iconPath = Platform.isWindows
        ? 'assets/image/tray/tray_icon.ico'
        : 'assets/image/tray/tray_icon.png';

    await trayManager.setIcon(iconPath);

    await trayManager.setToolTip('SlimeWorks');

    final Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: '显示主窗口'),
        MenuItem.separator(),
        MenuItem(key: 'hide_window', label: '隐藏窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: '退出'),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      _showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isWindows) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseUp() {
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        _showWindow();
        break;
      case 'hide_window':
        _hideWindow();
        break;
      case 'exit_app':
        _exitApp();
        break;
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
  }

  Future<void> _exitApp() async {
    await windowManager.destroy();
    exit(0);
  }
}
