import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class NovelTextCoverStyle {
  const NovelTextCoverStyle({required this.text, required this.color});

  final String text;
  final Color color;

  static final RegExp _letterOrNumber = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
  static const List<Color> _palette = <Color>[
    Color(0xFF355C7D),
    Color(0xFF6A4C93),
    Color(0xFF8E5572),
    Color(0xFF2A6F6B),
    Color(0xFF9A5B34),
    Color(0xFF4F6D7A),
    Color(0xFF7A4EAB),
    Color(0xFFA14D5A),
    Color(0xFF3E6B48),
    Color(0xFF8A6A2F),
    Color(0xFF4361A8),
    Color(0xFF7D4C59),
  ];

  static NovelTextCoverStyle fromTitle(String title) {
    String first = '书';
    for (final rune in title.runes) {
      final character = String.fromCharCode(rune);
      if (_letterOrNumber.hasMatch(character)) {
        first = character;
        break;
      }
    }
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(first)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return NovelTextCoverStyle(text: first, color: _palette[hash % _palette.length]);
  }
}

class NovelTextCover extends StatelessWidget {
  const NovelTextCover({
    super.key,
    required this.title,
    this.fontSize = 48,
    this.borderRadius,
  });

  final String title;
  final double fontSize;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final style = NovelTextCoverStyle.fromTitle(title);
    return Semantics(
      label: title,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.lerp(style.color, Colors.white, 0.14)!,
              Color.lerp(style.color, Colors.black, 0.16)!,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
            child: Text(
              style.text,
              style: AppTextStyles.role(
                context,
                fontSize: fontSize,
                weight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
