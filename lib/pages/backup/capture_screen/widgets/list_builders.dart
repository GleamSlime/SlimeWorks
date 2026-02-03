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
          Icon(icon, size: 64, color: Theme.of(context).hintColor.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
          const SizedBox(height: 24),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
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
            if (onOpen != null) IconButton(icon: const Icon(Icons.open_in_new, size: 20), onPressed: onOpen, tooltip: '打开'),
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
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.1),
          child: const Icon(Icons.code, color: Colors.orange, size: 20),
        ),
        title: Text(json.length > 50 ? '${json.substring(0, 50)}...' : json, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
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
                const SizedBox(height: 8),
                SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(
              count.toString(),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
