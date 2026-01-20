import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:slime_works/components/window/custom_bar.dart';

class DesktopScaffold extends StatelessWidget {
  final Widget child;

  const DesktopScaffold({super.key, required this.child});

  static Future<void> initManager() async {
    WidgetsFlutterBinding.ensureInitialized();

    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: '史莱姆工坊',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const CustomTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
