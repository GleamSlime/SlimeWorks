import 'dart:io';

import 'package:flutter/material.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/media_prefs_service.dart';

/// 隐私「伪封面」：把真实封面整张换成设置里指定的那张无害图片
///
/// 和隐私模式的高斯模糊不一样，伪封面看上去就是一张普通封面——不糊、不给锁角标，
/// 旁人看不出这里藏着内容。所有卡片共用同一个 ImageProvider，同一张图只解码一次进
/// ImageCache；宿主各自 new FileImage 的话，一屏几十张卡就是几十份位图。
class FakeCover extends StatelessWidget {
  const FakeCover({super.key, this.fit = BoxFit.cover});

  final BoxFit fit;

  /// 统一解码宽度：够铺满最大的封面格，又不会把几 MB 的原图整幅拉进内存
  static const int _decodeWidth = 720;

  static final Map<String, ImageProvider<Object>> _providers =
      <String, ImageProvider<Object>>{};

  static ImageProvider<Object>? providerFor(String path) {
    if (path.isEmpty) return null;
    return _providers.putIfAbsent(
      path,
      () => ResizeImage.resizeIfNeeded(
        _decodeWidth,
        null,
        FileImage(File(path)),
      ),
    );
  }

  /// 当前是否处于伪封面状态（媒体偏好未注册时按关闭处理）
  static bool get enabled => getIt.isRegistered<MediaPrefsService>()
      ? getIt.get<MediaPrefsService>().fakeCover.value
      : false;

  @override
  Widget build(BuildContext context) {
    final prefs = getIt.isRegistered<MediaPrefsService>()
        ? getIt.get<MediaPrefsService>()
        : null;
    final provider = providerFor(prefs?.fakeCoverPath.value ?? '');
    if (provider == null) return const _BlankCover();
    return Image(
      image: provider,
      fit: fit,
      // 图片文件被挪走 / 换机器后路径失效：退成实色底，绝不回落到真实封面
      errorBuilder: (_, _, _) => const _BlankCover(),
    );
  }
}

/// 伪封面图片读不出来时的纯色兜底，同样不泄露任何内容
class _BlankCover extends StatelessWidget {
  const _BlankCover();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppSemantic.of(context).surfaceSunken);
}
