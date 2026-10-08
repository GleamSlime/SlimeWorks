import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class SettingsTabPlaceholder extends StatelessWidget {
  final String title;

  const SettingsTabPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final brandColor = s.accent;

    return Center(
      child: Container(
        margin: EdgeInsets.all(m.kSpace32),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace32, vertical: m.kSpace40),
        decoration: BoxDecoration(
          color: s.surfaceRaised,
          borderRadius: m.radius16,
          border: Border.all(color: s.hairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: m.kSpace48,
              height: m.kSpace48,
              decoration: BoxDecoration(
                color: s.accentContainer,
                borderRadius: m.radius12,
              ),
              child: DrawIcon(StrokeIcons.construction,
                color: brandColor,
                size: m.iconSize24,
              ),
            ),
            SizedBox(height: m.kSpace16),
            Text(
              '$title 敬请期待',
              style: AppTextStyles.sectionTitle(context),
            ),
            SizedBox(height: m.kSpace6),
            Text(
              '该功能正在开发中，后续版本将支持',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                height: 1.5,
                color: s.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
