import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 统计芯片
class StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const StatChip({super.key, required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace12, vertical: AppTheme.metrics.kSpace6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppTheme.metrics.radius16,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: AppTheme.metrics.fontSize11, fontWeight: FontWeight.w500)),
          SizedBox(width: AppTheme.metrics.kSpace6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace2),
            decoration: BoxDecoration(color: color, borderRadius: AppTheme.metrics.radius10),
            child: Text(
              count.toString(),
              style: TextStyle(color: Colors.white, fontSize: AppTheme.metrics.fontSize11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// 统计卡片
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const StatCard({super.key, required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: AppTheme.metrics.iconSize24),
          SizedBox(width: AppTheme.metrics.kSpace12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: Theme.of(context).hintColor)),
                SizedBox(height: AppTheme.metrics.kSpace4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: AppTheme.metrics.fontSize18, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 信息芯片
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const InfoChip({super.key, required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppTheme.metrics.radius4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize14, color: color),
          SizedBox(width: AppTheme.metrics.kSpace4),
          Text(
            label,
            style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
