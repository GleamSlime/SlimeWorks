import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';

class NcmDecryptCard extends StatefulWidget {
  const NcmDecryptCard({super.key});

  @override
  State<NcmDecryptCard> createState() => _NcmDecryptCardState();
}

class _NcmDecryptCardState extends State<NcmDecryptCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: _isHovered ? (Matrix4.translationValues(0, -2, 0)) : Matrix4.identity(),
        child: Card(
          elevation: _isHovered ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: m.radius12,
            side: BorderSide(
              color: _isHovered
                  ? theme.colorScheme.primary.withAlpha(60)
                  : isDark
                      ? DarkColors.white10
                      : LightColors.black10,
              width: _isHovered ? 1.5 : 0.5,
            ),
          ),
          child: InkWell(
            borderRadius: m.radius12,
            onTap: () => context.go('/ncm-decrypt'),
            child: Container(
              width: 200,
              padding: EdgeInsets.all(m.kSpace16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: m.kSpace48,
                    height: m.kSpace48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isHovered
                            ? [const Color(0xFF4ECDC4), const Color(0xFF2EAF9B)]
                            : [
                                const Color(0xFF4ECDC4).withAlpha(40),
                                const Color(0xFF2EAF9B).withAlpha(20),
                              ],
                      ),
                      borderRadius: m.radius12,
                      boxShadow: _isHovered
                          ? [
                              BoxShadow(
                                color: const Color(0xFF4ECDC4).withAlpha(60),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.lock_open_rounded,
                      color: _isHovered ? Colors.white : const Color(0xFF4ECDC4),
                      size: m.iconSize24,
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  Text(
                    'NCM解密',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    '网易云NCM格式解密',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
