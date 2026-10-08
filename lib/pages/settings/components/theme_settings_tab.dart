import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/live_frost.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';

class ThemeSettingsTab extends StatefulWidget {
  const ThemeSettingsTab({super.key});

  @override
  State<ThemeSettingsTab> createState() => _ThemeSettingsTabState();
}

class _ThemeSettingsTabState extends State<ThemeSettingsTab> {
  static const _accentPalette = [
    // 第一档是「跟随主题」：近黑，明暗各由语义层给一份
    AppTheme.kFollowThemeAccent,
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
  Color _accentColor = AppTheme.kFollowThemeAccent;
  bool _liveTranslucent = false;

  @override
  void initState() {
    super.initState();
    _themeMode = AppTheme.themeModeObs.value;
    _accentColor = AppTheme.accentColorObs.value;
    _fontScale = AppTheme.fontScaleObs.value;
    _loadLiveTranslucent();
  }

  Future<void> _loadLiveTranslucent() async {
    if (!LiveFrost.supported) return;
    final bool enabled = await LiveFrost.loadPreference();
    if (mounted) setState(() => _liveTranslucent = enabled);
  }

  Future<void> _onLiveTranslucentChanged(bool value) async {
    setState(() => _liveTranslucent = value);
    // 开关即起停整条抓帧链路：开=窗口透明+实时磨砂底，关=不透明 Dart 底色。
    await LiveFrost.setEnabled(value);
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

  StrokeIcon _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return StrokeIcons.lightMode;
      case ThemeMode.dark:
        return StrokeIcons.darkMode;
      case ThemeMode.system:
        return StrokeIcons.brightnessAuto;
    }
  }

  Widget _buildModeChip(ThemeMode mode) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final isSelected = _themeMode == mode;
    return GestureDetector(
      onTap: () => _onThemeModeChanged(mode),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standardCurve,
        padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
        decoration: BoxDecoration(
          color: isSelected ? s.accent.withAlpha(25) : s.surface,
          borderRadius: m.radius12,
          border: Border.all(
            color: isSelected ? s.accent : s.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DrawIcon(
              _themeModeIcon(mode),
              size: m.iconSize20,
              color: isSelected ? s.accent : s.textTertiary,
            ),
            SizedBox(width: m.kSpace8),
            // 标签吃字号族，界面字号拉到 2.0 时必须能被压，否则这颗 chip 会顶破 Wrap
            Flexible(
              child: Text(
                _themeModeLabel(mode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize13,
                  height: 1.5,
                  weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? s.accent : s.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccentSwatch(Color color) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final isSelected = _accentColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => _onAccentColorTap(color),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.standardCurve,
        width: m.iconSize44,
        height: m.iconSize44,
        margin: EdgeInsets.only(bottom: m.kSpace4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 色板预览：这里必须铺原始候选色本身，不能换成当前主题的语义色
          color: color,
          border: Border.all(
            color: isSelected ? s.textPrimary : Colors.transparent,
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
            ? DrawIcon(
                StrokeIcons.check,
                // 勾的墨色跟着色板深浅走，与语义层无关
                color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                size: m.iconSize20,
              )
            : null,
      ),
    );
  }

  Widget _buildSectionTitle(String title, StrokeIcon icon) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Row(
      children: [
        Container(
          width: m.kSpace24,
          height: m.kSpace24,
          decoration: BoxDecoration(
            color: s.accentContainer,
            borderRadius: m.radius6,
          ),
          child: DrawIcon(
            icon,
            size: m.iconSize12,
            color: s.accent,
          ),
        ),
        SizedBox(width: m.kSpace8),
        Text(
          title,
          style: AppTextStyles.sectionTitle(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return SingleChildScrollView(
      padding: EdgeInsets.all(m.kSpace24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('主题模式', StrokeIcons.palette),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: m.radius12,
              border: Border.all(color: s.border),
            ),
            child: Wrap(
              spacing: m.kSpace12,
              runSpacing: m.kSpace8,
              children: ThemeMode.values.map(_buildModeChip).toList(),
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('主题配色', StrokeIcons.colorLens),
          SizedBox(height: m.kSpace4),
          Text(
            '选择全局强调色，将影响按钮、标签、滑块等组件',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.5,
              color: s.textTertiary,
            ),
          ),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: m.radius12,
              border: Border.all(color: s.border),
            ),
            child: Wrap(
              spacing: m.kSpace12,
              runSpacing: m.kSpace12,
              children: _accentPalette.map(_buildAccentSwatch).toList(),
            ),
          ),
          SizedBox(height: m.kSpace24),
          _buildSectionTitle('字号大小', StrokeIcons.textFields),
          SizedBox(height: m.kSpace4),
          Text(
            '调整全局文本缩放比例，影响所有页面的文字大小',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.5,
              color: s.textTertiary,
            ),
          ),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace16),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: m.radius12,
              border: Border.all(color: s.border),
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
                        color: s.accentContainer,
                        borderRadius: m.radius999,
                      ),
                      child: Text(
                        '${(_fontScale * 100).round()}%',
                        maxLines: 1,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          weight: FontWeight.w600,
                          color: s.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.kSpace32),
          if (LiveFrost.supported) ...[
            _buildSectionTitle('窗口效果', StrokeIcons.waterDrop),
            SizedBox(height: m.kSpace4),
            Text(
              '开启后窗口底色实时透出并模糊桌面内容（磨砂质感）；关闭则使用不透明底色',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                height: 1.5,
                color: s.textTertiary,
              ),
            ),
            SizedBox(height: m.kSpace12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace8),
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: m.radius12,
                border: Border.all(color: s.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '实时半透明',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize14,
                        color: s.textPrimary,
                      ),
                    ),
                  ),
                  Switch(
                    value: _liveTranslucent,
                    onChanged: _onLiveTranslucentChanged,
                  ),
                ],
              ),
            ),
            SizedBox(height: m.kSpace32),
          ],
          _buildSectionTitle('预览样式', StrokeIcons.preview),
          SizedBox(height: m.kSpace12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(m.kSpace20),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: m.radius12,
              border: Border.all(color: s.border),
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
