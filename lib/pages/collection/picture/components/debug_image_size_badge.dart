import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

/// Debug 模式下显示在封面右下角的**解码尺寸**徽标（像素宽×高）。
///
/// 解码尺寸才是「本地/远程清晰度设置有没有生效」的证据。这里曾经改成对 http 源发
/// HEAD 取 Content-Length，而节点 `/node/media` 只路由 GET，HEAD 一律落到 404，
/// 于是每张远程卡显示的都是那枚 404 响应体的长度（恒定 37B）。
///
/// [provider] 必须和封面用的是同一个对象：resolve 命中的就是 Image 那条缓存条目，
/// 不会多一次下载或多一次解码。Release 模式下渲染为零尺寸 [SizedBox.shrink]。
class DebugImageSizeBadge extends StatefulWidget {
  const DebugImageSizeBadge({super.key, required this.provider});

  final ImageProvider<Object> provider;

  @override
  State<DebugImageSizeBadge> createState() => _DebugImageSizeBadgeState();
}

class _DebugImageSizeBadgeState extends State<DebugImageSizeBadge> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _attach();
  }

  /// 复用封面那条缓存条目，所以换 provider（缩略图生成完、hover 轮换封面）时要重挂
  void _attach() {
    _detach();
    final listener = ImageStreamListener(_onFrame);
    _listener = listener;
    _info = null;
    _stream = widget.provider.resolve(ImageConfiguration.empty)
      ..addListener(listener);
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
  }

  void _onFrame(ImageInfo info, bool _) {
    if (mounted) setState(() => _info = info);
  }

  @override
  void didUpdateWidget(DebugImageSizeBadge old) {
    super.didUpdateWidget(old);
    if (kDebugMode && old.provider != widget.provider) _attach();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _info?.image;
    if (!kDebugMode || image == null) return const SizedBox.shrink();
    final s = AppSemantic.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace5, vertical: AppTheme.metrics.kSpace2),
      decoration: BoxDecoration(
        color: s.info.color.withAlpha(210),
        borderRadius: AppTheme.metrics.radius4,
      ),
      child: Text(
        '${image.width}×${image.height}',
        // debug 徽标：实心状态色底上的白字不随明暗翻转
        style: AppTextStyles.role(context,
          fontSize: AppTheme.metrics.fontSize9,
          color: Colors.white,
          weight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
