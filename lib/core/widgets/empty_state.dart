import 'package:flutter/material.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';

/// 空状态
///
/// 原本有 10 份各写各的空状态（图标尺寸、文案层级、是否有按钮都不一致）。
/// 这里给出唯一形态：图标 + 主文案 + 可选说明 + 可选操作。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = StrokeIcons.inbox,
    this.action,
    this.compact = false,
    this.padding,
  });

  final String title;
  final String? description;
  final StrokeIcon icon;
  final Widget? action;

  /// compact 用于卡片/分栏内的小范围占位，regular 用于整页
  final bool compact;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    final iconSize = compact ? m.iconSize28 : m.iconSize48;

    return Center(
      child: Padding(
        padding:
            padding ??
            EdgeInsets.symmetric(
              horizontal: m.kSpace32,
              vertical: compact ? m.kSpace24 : m.kSpace48,
            ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? m.kSpace48 : m.kSpace64,
              height: compact ? m.kSpace48 : m.kSpace64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: s.surfaceSunken,
                shape: BoxShape.circle,
                border: Border.all(color: s.hairline, width: scaleW(1)),
              ),
              child: DrawIcon(
                icon,
                size: iconSize,
                color: s.textTertiary,
                effect: StrokeEffect.blur,
              ),
            ),
            SizedBox(height: m.kSpace16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: compact
                  ? AppTextStyles.cardTitle(context)
                  : TextStyle(
                      fontSize: m.fontSize15,
                      fontWeight: FontWeight.w600,
                      color: s.textPrimary,
                      height: 1.5,
                    ),
            ),
            if (description != null) ...[
              SizedBox(height: m.kSpace6),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: scaleW(320)),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(context),
                ),
              ),
            ],
            if (action != null) ...[SizedBox(height: m.kSpace20), action!],
          ],
        ),
      ),
    );
  }
}

/// 页面/区块级加载指示
class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.message, this.size});

  final String? message;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size ?? m.iconSize24,
            height: size ?? m.iconSize24,
            child: CircularProgressIndicator(
              strokeWidth: scaleW(2.2),
              strokeCap: StrokeCap.round,
              color: s.accent,
            ),
          ),
          if (message != null) ...[
            SizedBox(height: m.kSpace12),
            Text(message!, style: AppTextStyles.caption(context)),
          ],
        ],
      ),
    );
  }
}

/// 模态遮罩：替代原先 `Colors.black.withValues(alpha: .3)` 的写死遮罩。
///
/// 遮罩色必须跟随主题——暗色下用半透明黑叠在深灰表面会几乎看不出层级，
/// 而亮色下同一条代码却表现正常，导致两套主题的"阻塞感"不一致。
class Scrim extends StatelessWidget {
  const Scrim({super.key, required this.child, this.visible = true});

  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return AnimatedOpacity(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: ColoredBox(color: s.scrim, child: child),
      ),
    );
  }
}

/// 骨架占位块（列表加载时比转圈更稳定：不跳动、保留布局）
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height ?? m.kSpace12,
          decoration: BoxDecoration(
            // 两端都必须是实心表面色：状态层（surfaceHover）是半透明水洗，
            // lerp 到端点会连 alpha 一起插值，骨架屏会在最亮的一帧直接消失。
            color: Color.lerp(s.surfaceSunken, s.surfaceRaised, _controller.value),
            borderRadius: widget.borderRadius ?? m.radius6,
          ),
        );
      },
    );
  }
}
