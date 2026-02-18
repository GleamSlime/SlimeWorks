import 'package:flutter/material.dart';

/// 捕获控制面板
class CaptureControlPanel extends StatelessWidget {
  final bool isCapturing;
  final bool isCertInstalled;
  final VoidCallback onToggleCapture;
  final VoidCallback onInstallCertificate;
  final VoidCallback onRefresh;
  final VoidCallback onClearData;
  final VoidCallback onSettings;

  const CaptureControlPanel({
    super.key,
    required this.isCapturing,
    required this.isCertInstalled,
    required this.onToggleCapture,
    required this.onInstallCertificate,
    required this.onRefresh,
    required this.onClearData,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2E2E2E), const Color(0xFF1E1E1E)]
              : [const Color(0xFFF8F9FB), const Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // 响应式布局
              final isNarrow = constraints.maxWidth < 600;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isNarrow
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: [
                  // 状态指示器
                  Expanded(
                    child: Row(
                      mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isCapturing ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            boxShadow: isCapturing
                                ? [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.5),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            isCapturing ? '捕获中' : '开启捕获',
                            style: Theme.of(
                              context,
                            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (!isNarrow) const SizedBox(width: 24),
                        if (!isNarrow)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isCertInstalled
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCertInstalled
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.orange.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCertInstalled ? Icons.verified : Icons.warning_amber,
                                  size: 16,
                                  color: isCertInstalled ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isCertInstalled ? 'CA证书已安装' : 'CA证书未安装',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isCertInstalled ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (isNarrow) const SizedBox(height: 12),

                  // 控制按钮
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: isNarrow ? WrapAlignment.end : WrapAlignment.end,
                    children: [
                      IconButton.outlined(
                        icon: const Icon(Icons.settings),
                        onPressed: onSettings,
                        tooltip: '设置',
                      ),
                      IconButton.outlined(
                        icon: const Icon(Icons.refresh),
                        onPressed: onRefresh,
                        tooltip: '刷新数据',
                      ),
                      IconButton.outlined(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: onClearData,
                        tooltip: '清除所有数据',
                      ),
                      if (!isCertInstalled)
                        FilledButton.tonalIcon(
                          onPressed: onInstallCertificate,
                          icon: const Icon(Icons.security),
                          label: const Text('安装CA证书'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                        ),
                      FilledButton.tonalIcon(
                        onPressed: onToggleCapture,
                        icon: Icon(isCapturing ? Icons.stop : Icons.play_arrow),
                        label: Text(isCapturing ? '停止捕获' : '开始捕获'),
                        style: FilledButton.styleFrom(
                          backgroundColor: isCapturing ? Colors.red : Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 捕获设置对话框
class CaptureSettingsDialog extends StatefulWidget {
  final int selectedPort;
  final String selectedFormat;
  final Function(int) onPortChanged;
  final Function(String) onFormatChanged;

  const CaptureSettingsDialog({
    super.key,
    required this.selectedPort,
    required this.selectedFormat,
    required this.onPortChanged,
    required this.onFormatChanged,
  });

  @override
  State<CaptureSettingsDialog> createState() => _CaptureSettingsDialogState();
}

class _CaptureSettingsDialogState extends State<CaptureSettingsDialog> {
  late int _port;
  late String _format;

  @override
  void initState() {
    super.initState();
    _port = widget.selectedPort;
    _format = widget.selectedFormat;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '捕获设置',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings_ethernet, size: 20),
                      const SizedBox(width: 8),
                      const Text('代理端口:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _port,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: [8080, 8433, 8888, 9000].map((port) {
                            return DropdownMenuItem(value: port, child: Text(port.toString()));
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _port = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.video_settings, size: 20),
                      const SizedBox(width: 8),
                      const Text('录制格式:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _format,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: ['mp4', 'flv', 'ts', 'mkv'].map((format) {
                            return DropdownMenuItem(
                              value: format,
                              child: Text(format.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _format = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () {
                    widget.onPortChanged(_port);
                    widget.onFormatChanged(_format);
                    Navigator.pop(context);
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
