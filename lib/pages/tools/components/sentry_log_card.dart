import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_colors.dart';

class SentryLogCard extends StatefulWidget {
  const SentryLogCard({super.key});

  @override
  State<SentryLogCard> createState() => _SentryLogCardState();
}

class _SentryLogCardState extends State<SentryLogCard> {
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
            onTap: () => context.go('/sentry-log'),
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
                            ? [const Color(0xFFA89FEE), const Color(0xFF7C6FE0)]
                            : [
                                const Color(0xFFA89FEE).withAlpha(40),
                                const Color(0xFF7C6FE0).withAlpha(20),
                              ],
                      ),
                      borderRadius: m.radius12,
                      boxShadow: _isHovered
                          ? [
                              BoxShadow(
                                color: const Color(0xFFA89FEE).withAlpha(60),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      Icons.radar_rounded,
                      color: _isHovered ? Colors.white : const Color(0xFFA89FEE),
                      size: m.iconSize24,
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  Text(
                    '日志中心',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: m.kSpace4),
                  Text(
                    'Sentry兼容日志收集',
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
