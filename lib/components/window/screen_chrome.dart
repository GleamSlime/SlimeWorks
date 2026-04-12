import 'package:flutter/material.dart';

import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_provider.dart';

class ScreenChrome extends StatefulWidget {
  final ScreenChromeData data;
  final Widget child;

  const ScreenChrome({super.key, required this.data, required this.child});

  @override
  State<ScreenChrome> createState() => _ScreenChromeState();
}

class _ScreenChromeState extends State<ScreenChrome> {
  final Object _owner = Object();
  late final DesktopScreenProvider _desktopScreen = getIt<DesktopScreenProvider>();

  @override
  void initState() {
    super.initState();
    _publishChrome();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publishChrome();
  }

  @override
  void didUpdateWidget(covariant ScreenChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _publishChrome();
  }

  @override
  void dispose() {
    // 立即同步清除，防止下一个页面加载前头部仍显示当前页数据
    _desktopScreen.clearScreenChrome(owner: _owner);
    super.dispose();
  }

  void _publishChrome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _desktopScreen.setScreenChrome(widget.data, owner: _owner);
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
