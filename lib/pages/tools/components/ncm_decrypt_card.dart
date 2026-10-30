import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

class NcmDecryptCard extends StatefulWidget {
  const NcmDecryptCard({super.key});

  @override
  State<NcmDecryptCard> createState() => _NcmDecryptCardState();
}

class _NcmDecryptCardState extends State<NcmDecryptCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final viz = AppVizSet.of(context).mint;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () => context.go('/ncm-decrypt'),
        child: AnimatedContainer(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          transform: Matrix4.translationValues(0, _isHovered ? -2.0 : 0, 0),
          width: scaleW(220),
          padding: EdgeInsets.all(m.kSpace20),
          decoration: AppCard.glassDecoration(
            context,
            borderRadius: m.radiusCard,
            borderColor: _isHovered ? s.borderStrong : null,
            lifted: _isHovered,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: AppMotion.base,
                curve: AppMotion.standard,
                width: scaleW(48),
                height: scaleW(48),
                decoration: BoxDecoration(
                  color: viz.base.withValues(
                    alpha: s.isDark
                        ? (_isHovered ? 0.30 : 0.18)
                        : (_isHovered ? 0.22 : 0.12),
                  ),
                  borderRadius: m.radiusControl,
                ),
                child: Center(
                  child: DrawIcon(StrokeIcons.lockOpen, color: viz.base, size: scaleW(24)),
                ),
              ),
              SizedBox(height: m.kSpace14),
              Text('NCM解密', style: AppTextStyles.cardTitle(context)),
              SizedBox(height: m.kSpace4),
              Text('网易云NCM格式解密', style: AppTextStyles.caption(context)),
            ],
          ),
        ),
      ),
    );
  }
}
