import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_text_styles.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class ThemeSettingsTab extends StatefulWidget {
  const ThemeSettingsTab({super.key});

  @override
  State<ThemeSettingsTab> createState() => _ThemeSettingsTabState();
}

class _ThemeSettingsTabState extends State<ThemeSettingsTab> {
  static const _accentPalette = [
    LightColors.primary,
    LightColors.purple,
    LightColors.indigo,
    LightColors.blue,
    LightColors.cyan,
    LightColors.mint,
    LightColors.green,
    LightColors.yellow,
    LightColors.orange,
    LightColors.red,
  ];

  ThemeMode _themeMode = ThemeMode.system;
  double _fontScale = 1.0;
  Color _accentColor = LightColors.primary;
  bool _appliedInitial = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_appliedInitial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyTheme();
      });
      _appliedInitial = true;
    }
  }

  void _onThemeModeChanged(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() {
      _themeMode = mode;
    });
    Get.changeThemeMode(mode);
    _applyTheme();
  }

  void _onAccentColorTap(Color color) {
    if (_accentColor.value == color.value) return;
    setState(() => _accentColor = color);
    _applyTheme();
  }

  void _onFontScaleChanged(double value) {
    setState(() => _fontScale = value);
    _applyTheme();
  }

  void _applyTheme() {
    final brightness = _resolveBrightness();
    final baseTheme = brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
    final updatedTheme = _buildCustomTheme(baseTheme, _accentColor, _fontScale);
    Get.changeTheme(updatedTheme);
  }

  Brightness _resolveBrightness() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context);
    }
  }

  ThemeData _buildCustomTheme(ThemeData base, Color accentColor, double scale) {
    final scaledTextTheme = _scaleTextTheme(base.textTheme, scale);
    final scaledPrimaryTextTheme = _scaleTextTheme(base.primaryTextTheme, scale);
    final colorScheme = base.colorScheme.copyWith(
      primary: accentColor,
      secondary: accentColor,
      primaryContainer: accentColor.withOpacity(0.2),
      onPrimary: _getContrastColor(accentColor),
    );
    return base.copyWith(
      colorScheme: colorScheme,
      primaryColor: accentColor,
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: colorScheme.surface),
      tabBarTheme: base.tabBarTheme.copyWith(
        indicator: UnderlineTabIndicator(borderSide: BorderSide(color: accentColor, width: 3)),
        labelColor: colorScheme.onSurface,
        unselectedLabelColor: colorScheme.onSurface.withAlpha(140),
      ),
      textTheme: scaledTextTheme,
      primaryTextTheme: scaledPrimaryTextTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: _getContrastColor(accentColor)),
      ),
      sliderTheme: base.sliderTheme.copyWith(thumbColor: accentColor, activeTrackColor: accentColor),
    );
  }

  TextTheme _scaleTextTheme(TextTheme textTheme, double scale) {
    return textTheme.copyWith(
      displayLarge: _scaleTextStyle(textTheme.displayLarge, scale),
      displayMedium: _scaleTextStyle(textTheme.displayMedium, scale),
      displaySmall: _scaleTextStyle(textTheme.displaySmall, scale),
      headlineLarge: _scaleTextStyle(textTheme.headlineLarge, scale),
      headlineMedium: _scaleTextStyle(textTheme.headlineMedium, scale),
      headlineSmall: _scaleTextStyle(textTheme.headlineSmall, scale),
      titleLarge: _scaleTextStyle(textTheme.titleLarge, scale),
      titleMedium: _scaleTextStyle(textTheme.titleMedium, scale),
      titleSmall: _scaleTextStyle(textTheme.titleSmall, scale),
      bodyLarge: _scaleTextStyle(textTheme.bodyLarge, scale),
      bodyMedium: _scaleTextStyle(textTheme.bodyMedium, scale),
      bodySmall: _scaleTextStyle(textTheme.bodySmall, scale),
      labelLarge: _scaleTextStyle(textTheme.labelLarge, scale),
      labelMedium: _scaleTextStyle(textTheme.labelMedium, scale),
      labelSmall: _scaleTextStyle(textTheme.labelSmall, scale),
    );
  }

  TextStyle? _scaleTextStyle(TextStyle? style, double scale) {
    if (style == null) {
      return null;
    }
    final fontSize = style.fontSize;
    if (fontSize == null) {
      return style;
    }
    return style.copyWith(fontSize: fontSize * scale);
  }

  Color _getContrastColor(Color color) {
    return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '亮色';
      case ThemeMode.dark:
        return '暗色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  Widget _buildModeChip(ThemeMode mode) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(_themeModeLabel(mode), style: AppTextStyles.body2(color: theme.colorScheme.onSurface)),
      selected: _themeMode == mode,
      side: BorderSide(color: _themeMode == mode ? theme.colorScheme.primary : theme.dividerColor),
      selectedColor: theme.colorScheme.primary.withOpacity(0.15),
      onSelected: (_) => _onThemeModeChanged(mode),
    );
  }

  Widget _buildAccentSwatch(Color color) {
    final isSelected = _accentColor.value == color.value;
    return GestureDetector(
      onTap: () => _onAccentColorTap(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: isSelected ? Colors.black87 : Colors.transparent, width: isSelected ? 3 : 1),
          boxShadow: [if (isSelected) BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3))],
        ),
        child: isSelected ? Icon(Icons.check, color: _getContrastColor(color), size: 28) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题模式',
            style: AppTextStyles.h5(color: theme.colorScheme.onSurface, fontWeight: AppFontWeights.semiBold),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: ThemeMode.values.map(_buildModeChip).toList()),
          const SizedBox(height: 24),
          Text(
            '主题配色',
            style: AppTextStyles.h5(color: theme.colorScheme.onSurface, fontWeight: AppFontWeights.semiBold),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: _accentPalette.map(_buildAccentSwatch).toList()),
          const SizedBox(height: 24),
          Text(
            '字号大小',
            style: AppTextStyles.h5(color: theme.colorScheme.onSurface, fontWeight: AppFontWeights.semiBold),
          ),
          const SizedBox(height: 12),
          Slider(value: _fontScale, min: 0.8, max: 1.3, divisions: 10, label: '${(_fontScale * 100).round()}%', onChanged: _onFontScaleChanged),
          const SizedBox(height: 4),
          Text('当前缩放：${(_fontScale * 100).round()}%', style: AppTextStyles.body2(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 32),
          Text(
            '预览样式',
            style: AppTextStyles.h5(color: theme.colorScheme.onSurface, fontWeight: AppFontWeights.semiBold),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('标题文本', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('正文示例：当前主题配色和字号大小将影响全局文本。', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: () {}, child: const Text('操作按钮')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
