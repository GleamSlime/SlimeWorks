import 'package:slime_works/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 构建空状态
class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final bool isCapturing;
  final bool isCertInstalled;
  final VoidCallback? onAction;

  const EmptyState({super.key, required this.message, required this.icon, this.isCapturing = false, this.isCertInstalled = false, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize64, color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
          SizedBox(height: AppTheme.metrics.kSpace16),
          Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
          SizedBox(height: AppTheme.metrics.kSpace24),
          if (!isCapturing && onAction != null)
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(isCertInstalled ? Icons.play_arrow : Icons.security),
              label: Text(isCertInstalled ? '开始捕获' : '安装证书'),
            ),
        ],
      ),
    );
  }
}

/// URL卡片
class UrlCard extends StatelessWidget {
  final String url;
  final IconData icon;
  final Color color;
  final VoidCallback? onCopy;
  final VoidCallback? onOpen;

  const UrlCard({super.key, required this.url, required this.icon, required this.color, this.onCopy, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: AppTheme.metrics.iconSize20),
        ),
        title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.copy, size: AppTheme.metrics.iconSize20),
              onPressed: () {
                if (onCopy != null) {
                  onCopy!();
                } else {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), behavior: SnackBarBehavior.floating));
                }
              },
              tooltip: '复制',
            ),
            if (onOpen != null) IconButton(icon: Icon(Icons.open_in_new, size: AppTheme.metrics.iconSize20), onPressed: onOpen, tooltip: '打开'),
          ],
        ),
      ),
    );
  }
}

/// JSON卡片
class JsonCard extends StatelessWidget {
  final String json;
  final VoidCallback? onCopy;

  const JsonCard({super.key, required this.json, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: AppTheme.metrics.kSpace12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: Icon(Icons.code, color: Colors.orange, size: AppTheme.metrics.iconSize20),
        ),
        title: Text(json.length > 50 ? '${json.substring(0, 50)}...' : json, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(AppTheme.metrics.kSpace16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.copy, size: AppTheme.metrics.iconSize18),
                      label: const Text('复制'),
                      onPressed: () {
                        if (onCopy != null) {
                          onCopy!();
                        } else {
                          Clipboard.setData(ClipboardData(text: json));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), behavior: SnackBarBehavior.floating));
                        }
                      },
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.metrics.kSpace8),
                SelectableText(json, style: TextStyle(fontFamily: 'monospace', fontSize: AppTheme.metrics.fontSize11)),
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
                Text(
                  value,
                  style: TextStyle(fontSize: AppTheme.metrics.fontSize18, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 状态徽章
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const StatusBadge({super.key, required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace8, vertical: AppTheme.metrics.kSpace4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppTheme.metrics.radius12,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.metrics.iconSize14, color: color),
          SizedBox(width: AppTheme.metrics.kSpace4),
          Text(
            text,
            style: TextStyle(fontSize: AppTheme.metrics.fontSize11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
