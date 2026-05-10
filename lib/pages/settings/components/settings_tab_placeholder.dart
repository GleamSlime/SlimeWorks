import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class SettingsTabPlaceholder extends StatelessWidget {
  final String title;

  const SettingsTabPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Center(
      child: Text('$title 敬请期待', style: TextStyle(fontSize: AppTheme.metrics.fontSize13, height: 1.5, color: color)),
    );
  }
}
