import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
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
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        transform: _isHovered
            ? Matrix4.translationValues(0, -AppMotion.travelMicro, 0)
            : Matrix4.identity(),
        child: Card(
          // 层次靠描边而不是投影：悬停只把描边提到 strong 档
          shape: RoundedRectangleBorder(
            borderRadius: m.radius12,
            side: BorderSide(
              color: _isHovered ? s.borderStrong : s.hairline,
              width: scaleW(1),
            ),
          ),
          child: InkWell(
            borderRadius: m.radius12,
            onTap: () => context.go('/ncm-decrypt'),
            child: Container(
              width: scaleW(200),
              padding: EdgeInsets.all(m.kSpace16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.standard,
                    width: m.kSpace48,
                    height: m.kSpace48,
                    decoration: BoxDecoration(
                      // 身份色只出水洗底，铺渐变和彩色发光都是旧语言的招牌
                      color: viz.base.withValues(
                        alpha: s.isDark
                            ? (_isHovered ? 0.30 : 0.18)
                            : (_isHovered ? 0.22 : 0.12),
                      ),
                      borderRadius: m.radius12,
                    ),
                    child: DrawIcon(StrokeIcons.lockOpen, color: viz.base, size: m.iconSize24),
                  ),
                  SizedBox(height: m.kSpace12),
                  Text('NCM解密', style: AppTextStyles.cardTitle(context)),
                  SizedBox(height: m.kSpace4),
                  Text('网易云NCM格式解密', style: AppTextStyles.caption(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
