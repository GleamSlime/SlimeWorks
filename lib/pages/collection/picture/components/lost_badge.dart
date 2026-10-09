import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class LostBadge extends StatelessWidget {
  const LostBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace6,
        vertical: AppTheme.metrics.kSpace2,
      ),
      decoration: BoxDecoration(
        color: s.warning.color.withAlpha(200),
        borderRadius: AppTheme.metrics.radius4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 实心状态色底上的反相文字：状态色两档同值，白字不随明暗翻转
          DrawIcon(StrokeIcons.linkOff, size: AppTheme.metrics.iconSize12, color: s.onStatusBadge),
          SizedBox(width: AppTheme.metrics.kSpace4),
          Text('丢失', style: AppTextStyles.role(context,
            fontSize: AppTheme.metrics.fontSize10,
            color: s.onStatusBadge,
            weight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}