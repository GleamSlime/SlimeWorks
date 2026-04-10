import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/pages/picacg/models/picacg_models.dart';

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
  });

  final PicAcgImage image;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Alignment alignment;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object? error)? errorBuilder;

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
              const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return widget.errorBuilder?.call(context, snapshot.error) ??
              const Center(child: Icon(Icons.broken_image_outlined, size: 32));
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
          ),
        );
      },
    );
  }
}
