import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SettingsTabPlaceholder extends StatelessWidget {
  final String title;

  const SettingsTabPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = theme.brightness == Brightness.dark;
    final brandColor = isDark ? DarkColors.primary : LightColors.primary;

    return Center(
      child: Container(
        margin: EdgeInsets.all(m.kSpace32),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace32, vertical: m.kSpace40),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: m.radius16,
          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(60)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: m.kSpace48,
              height: m.kSpace48,
              decoration: BoxDecoration(
                color: brandColor.withAlpha(25),
                borderRadius: m.radius12,
              ),
              child: Icon(
                Icons.construction_rounded,
                color: brandColor,
                size: m.iconSize24,
              ),
            ),
            SizedBox(height: m.kSpace16),
            Text(
              '$title 敬请期待',
              style: TextStyle(
                fontSize: m.fontSize15,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: m.kSpace6),
            Text(
              '该功能正在开发中，后续版本将支持',
              style: TextStyle(
                fontSize: m.fontSize12,
                height: 1.5,
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
