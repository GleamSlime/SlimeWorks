import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_text_styles.dart';

class SettingsTabPlaceholder extends StatelessWidget {
  final String title;

  const SettingsTabPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Center(
      child: Text('$title 敬请期待', style: AppTextStyles.body2(color: color)),
    );
  }
}
