import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _fontScaleKey = 'font_scale';

  ThemeMode _themeMode = ThemeMode.system;
  double _fontScale = 1.0;
  Color _accentColor = LightColors.primary;

  @override
  void initState() {
    super.initState();
    // AppTheme 在 main() 中已提前加载持久化配置，直接从响应式变量读取即可
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
  }

  void _applyTheme() {
    // 更新 AppTheme 响应式变量 — MyApp.build 中的 Obx 监听这些变量并重建 MaterialApp
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

  Widget _buildModeChip(ThemeMode mode) {
    final theme = Theme.of(context);
    return ChoiceChip(
      label: Text(
        _themeModeLabel(mode),
        style: AppTextStyles.body2(color: theme.colorScheme.onSurface),
      ),
      selected: _themeMode == mode,
      side: BorderSide(color: _themeMode == mode ? theme.colorScheme.primary : theme.dividerColor),
      selectedColor: theme.colorScheme.primary.withValues(
        alpha: (theme.colorScheme.primary.a * 255.0 * 0.15).round().clamp(0, 255).toDouble(),
      ),
      onSelected: (_) => _onThemeModeChanged(mode),
    );
  }

  Widget _buildAccentSwatch(Color color) {
    final isSelected = _accentColor == color;
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
          border: Border.all(
            color: isSelected ? Colors.black87 : Colors.transparent,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.black.withValues(alpha: 64),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                size: 28,
              )
            : null,
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
            style: AppTextStyles.h5(
              color: theme.colorScheme.onSurface,
              fontWeight: AppFontWeights.semiBold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: ThemeMode.values.map(_buildModeChip).toList()),
          const SizedBox(height: 24),
          Text(
            '主题配色',
            style: AppTextStyles.h5(
              color: theme.colorScheme.onSurface,
              fontWeight: AppFontWeights.semiBold,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _accentPalette.map(_buildAccentSwatch).toList(),
          ),
          const SizedBox(height: 24),
          Text(
            '字号大小',
            style: AppTextStyles.h5(
              color: theme.colorScheme.onSurface,
              fontWeight: AppFontWeights.semiBold,
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            value: _fontScale,
            min: 0.8,
            max: 1.3,
            divisions: 10,
            label: '${(_fontScale * 100).round()}%',
            onChanged: _onFontScaleChanged,
          ),
          const SizedBox(height: 4),
          Text(
            '当前缩放：${(_fontScale * 100).round()}%',
            style: AppTextStyles.body2(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 32),
          Text(
            '预览样式',
            style: AppTextStyles.h5(
              color: theme.colorScheme.onSurface,
              fontWeight: AppFontWeights.semiBold,
            ),
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
