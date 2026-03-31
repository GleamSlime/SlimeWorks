import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Debug 模式下显示在封面右下角的图片大小 badge。
/// Release 模式下渲染为零尺寸 [SizedBox.shrink]。
class DebugImageSizeBadge extends StatefulWidget {
  const DebugImageSizeBadge({super.key, required this.src});

  final String? src;

  @override
  State<DebugImageSizeBadge> createState() => _DebugImageSizeBadgeState();
}

class _DebugImageSizeBadgeState extends State<DebugImageSizeBadge> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _fetchSize();
  }

  @override
  void didUpdateWidget(DebugImageSizeBadge old) {
    super.didUpdateWidget(old);
    if (old.src != widget.src) {
      _bytes = null;
      if (kDebugMode) _fetchSize();
    }
  }

  Future<void> _fetchSize() async {
    final src = widget.src;
    if (src == null || src.isEmpty) return;
    try {
      int size;
      if (src.startsWith('http')) {
        // HTTP HEAD 请求获取 Content-Length，不下载 body
        final resp = await http.head(Uri.parse(src)).timeout(const Duration(seconds: 4));
        final lenStr = resp.headers['content-length'];
        size = (lenStr != null && lenStr.isNotEmpty) ? (int.tryParse(lenStr) ?? 0) : 0;
      } else {
        final f = File(src);
        size = f.existsSync() ? f.lengthSync() : 0;
      }
      if (mounted) setState(() => _bytes = size);
    } catch (_) {}
  }

  String _fmt(int bytes) {
    if (bytes <= 0) return '?';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final b = _bytes;
    // 用 src+bytes 作 key，避免多个相同大小的图片在同一 AnimatedSwitcher Stack 产生 key 冲突
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: b == null
          ? SizedBox.shrink(key: ValueKey('${widget.src}_empty'))
          : Container(
              key: ValueKey('${widget.src}_$b'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withAlpha(210),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _fmt(b),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
    );
  }
}
