import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class LostBadge extends StatelessWidget {
  const LostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace6,
        vertical: AppTheme.metrics.kSpace2,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(200),
        borderRadius: AppTheme.metrics.radius4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: AppTheme.metrics.iconSize12, color: Colors.white),
          SizedBox(width: AppTheme.metrics.kSpace4),
          Text('丢失', style: TextStyle(
            color: Colors.white,
            fontSize: AppTheme.metrics.fontSize10,
            fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}