import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/core/theme/app_colors.dart';
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

  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _fontScaleKey = 'font_scale';

  ThemeMode _themeMode = ThemeMode.system;
  double _fontScale = 1.0;
  Color _accentColor = LightColors.primary;

  @override
  void initState() {
    super.initState();
    _themeMode = AppTheme.themeModeObs.value;
    _accentColor = AppTheme.accentColorObs.value;
    _fontScale = AppTheme.fontScaleObs.value;
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<void> _saveAccentColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.toARGB32());
  }

  Future<void> _saveFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, scale);
  }

  void _onThemeModeChanged(ThemeMode mode) {
    if (_themeMode == mode) return;
    setState(() {
      _themeMode = mode;
    });
    _saveThemeMode(mode);
    _applyTheme();
  }

  void _onAccentColorTap(Color color) {
    if (_accentColor.toARGB32() == color.toARGB32()) return;
    setState(() => _accentColor = color);
    _saveAccentColor(color);
    _applyTheme();
  }

  void _onFontScaleChanged(double value) {
    setState(() => _fontScale = value);
    _saveFontScale(value);
    _applyTheme();
    AppTheme.resetMetrics();
  }

  void _applyTheme() {
    AppTheme.themeModeObs.value = _themeMode;
    AppTheme.accentColorObs.value = _accentColor;
    AppTheme.fontScaleObs.value = _fontScale;
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

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
    }
  }

  Widget _buildModeChip(ThemeMode mode) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isSelected = _themeMode == mode;
    return GestureDetector(
      onTap: () => _onThemeModeChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withAlpha(25)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: m.radius12,
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withAlpha(80),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _themeModeIcon(mode),
              size: m.iconSize20,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withAlpha(120),
            ),
            SizedBox(width: m.kSpace8),
            Text(
              _themeModeLabel(mode),
              style: TextStyle(
                fontSize: m.fontSize13,
                height: 1.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentSwatch(Color color) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    final isSelected = _accentColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => _onAccentColorTap(color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: m.iconSize44,
        height: m.iconSize44,
        margin: EdgeInsets.only(bottom: m.kSpace4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isSelected ? theme.colorScheme.onSurface : Colors.transparent,
            width: isSelected ? 3 : 0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withAlpha(100),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                size: m.iconSize20,
              )
            : null,
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withAlpha(20),
            borderRadius: m.radius6,
          ),
          child: Icon(
            icon,
            size: m.iconSize12,
            color: theme.colorScheme.primary,
          ),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: TextStyle(
            fontSize: m.fontSize15,
            height: 1.4,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return SingleChildScrollView(
      padding: EdgeInsets.all(m.kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('主题模式', Icons.palette_outlined),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: m.radius12,
              border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Wrap(
              spacing: m.kSpace12,
              runSpacing: m.kSpace8,
              children: ThemeMode.values.map(_buildModeChip).toList(),
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('主题配色', Icons.color_lens_outlined),
          SizedBox(height: m.kSpace4),
          Text(
            '选择全局强调色，将影响按钮、标签、滑块等组件',
            style: TextStyle(
              fontSize: m.fontSize12,
              height: 1.5,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: m.radius12,
              border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Wrap(
              spacing: m.kSpace12,
              runSpacing: m.kSpace12,
              children: _accentPalette.map(_buildAccentSwatch).toList(),
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('字号大小', Icons.text_fields_rounded),
          SizedBox(height: m.kSpace4),
          Text(
            '调整全局文本缩放比例，影响所有页面的文字大小',
            style: TextStyle(
              fontSize: m.fontSize12,
              height: 1.5,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: m.radius12,
              border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _fontScale,
                        min: 0.8,
                        max: 1.3,
                        divisions: 10,
                        label: '${(_fontScale * 100).round()}%',
                        onChanged: _onFontScaleChanged,
                      ),
                    ),
                    SizedBox(width: m.kSpace8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        '${(_fontScale * 100).round()}%',
                        style: TextStyle(
                          fontSize: m.fontSize12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace32),
          _buildSectionTitle('预览样式', Icons.preview_outlined),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: m.radius12,
              border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('标题文本', style: theme.textTheme.headlineSmall),
                SizedBox(height: m.kSpace8),
                Text('正文示例：当前主题配色和字号大小将影响全局文本。', style: theme.textTheme.bodyMedium),
                SizedBox(height: m.kSpace16),
                Row(
                  children: [
                    ElevatedButton(onPressed: () {}, child: const Text('操作按钮')),
                    SizedBox(width: m.kSpace12),
                    OutlinedButton(onPressed: () {}, child: const Text('次要按钮')),
                    SizedBox(width: m.kSpace12),
                    TextButton(onPressed: () {}, child: const Text('文字按钮')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
