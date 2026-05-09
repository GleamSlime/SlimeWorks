import 'package:flutter/material.dart';

class SettingsTabPlaceholder extends StatelessWidget {
  final String title;

  const SettingsTabPlaceholder({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium?.color;
    return Center(
      child: Text('$title 敬请期待', style: TextStyle(fontSize: 13.0, height: 1.5, color: color)),
    );
  }
}
