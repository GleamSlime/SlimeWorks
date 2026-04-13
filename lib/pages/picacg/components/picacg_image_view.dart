import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

/// 圆形加载进度环（模拟进度 0-99%，图片完成后消失）
///
/// 因 Rust 侧字节下载不提供流式进度，通过指数衰减时间模拟，
/// 给用户提供「正在加载」的可感知反馈。
class PicAcgProgressRing extends StatefulWidget {
  const PicAcgProgressRing({super.key, this.size = 44, this.color});

  /// 环的整体尺寸（宽高相等）
  final double size;

  /// 颜色（默认使用 Theme.colorScheme.primary）
  final Color? color;

  @override
  State<PicAcgProgressRing> createState() => _PicAcgProgressRingState();
}

class _PicAcgProgressRingState extends State<PicAcgProgressRing> {
  double _progress = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 每 80ms 以指数衰减方式递增，约 4s 抵近 99%
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() {
        _progress = _progress + (99 - _progress) * 0.025;
        if (_progress > 99) _progress = 99;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = _progress.toInt().clamp(0, 99);
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: pct / 100,
            strokeWidth: 2.5,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
          Text(
            '$pct%',
            style: TextStyle(
              fontSize: widget.size * 0.27,
              color: color,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class PicAcgImageView extends StatefulWidget {
  const PicAcgImageView({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
  });

  final PicAcgImage image;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final WidgetBuilder? loadingBuilder;

  /// 加载失败时的占位构建器
  ///
  /// 第三个参数 [onRetry] 为重试回调，调用后会重新发起图片加载
  final Widget Function(BuildContext context, Object? error, VoidCallback onRetry)? errorBuilder;

  /// 图片成功加载后的回调（第一次渲染完成后触发）
  final VoidCallback? onLoad;

  @override
  State<PicAcgImageView> createState() => _PicAcgImageViewState();
}

class _PicAcgImageViewState extends State<PicAcgImageView> {
  late final PicAcgService _service = getIt<PicAcgService>();
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchImageBytes(widget.image);
  }

  /// 重试加载图片（清除旧 Future，重新发起请求）
  void _retry() {
    setState(() {
      _future = _service.fetchImageBytes(widget.image);
    });
  }

  @override
  void didUpdateWidget(covariant PicAcgImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path ||
        oldWidget.image.fileServer != widget.image.fileServer) {
      _future = _service.fetchImageBytes(widget.image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loadingBuilder?.call(context) ??
              Center(child: PicAcgProgressRing(size: 44));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return widget.errorBuilder?.call(context, snapshot.error, _retry) ??
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, size: 32),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _retry, child: const Text('重试')),
                  ],
                ),
              );
        }

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (_, value, child) => Opacity(opacity: value, child: child),
          child: Image.memory(
            snapshot.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            alignment: widget.alignment,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: (ctx, child, frame, _) {
              // 第一帧渲染完成后触发 onLoad 回调
              if (frame != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLoad?.call());
              }
              return child;
            },
          ),
        );
      },
    );
  }
}
