import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  Future<void> handleDoubleTap() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: handleDoubleTap,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 48.h,
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Row(
          children: [
            const _MacWindowButtons(),
            SizedBox(width: 12.w),
            // const Text('My App', style: TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _MacWindowButtons extends StatelessWidget {
  const _MacWindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MacButton(
          color: const Color(0xFFFF5F57),
          onTap: () => windowManager.close(),
        ),
        _MacButton(
          color: const Color(0xFFFFBD2E),
          onTap: () => windowManager.minimize(),
        ),
        _MacButton(
          color: const Color(0xFF28C840),
          onTap: () => windowManager.maximize(),
        ),
      ],
    );
  }
}

class _MacButton extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _MacButton({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
