import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_text_styles.dart';

/// 主题演示页面
/// 展示所有字体大小和颜色的效果
class ThemePreviewScreen extends StatelessWidget {
  const ThemePreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    return DesktopLayout(
      title: '主题预览',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Text(
              '主题与排版系统',
              style: AppTextStyles.h3(
                color: isDark ? DarkColors.white100 : LightColors.black100,
              ),
            ),
            const SizedBox(height: 32),

            // 字体大小展示
            _buildTypographySection(isDark),

            const SizedBox(height: 48),

            // 颜色展示
            _buildColorsSection(isDark),

            const SizedBox(height: 48),

            // 组件展示
            _buildComponentsSection(isDark),
          ],
        ),
      ),
    );
  }

  /// 构建排版系统展示
  Widget _buildTypographySection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '排版系统',
          style: AppTextStyles.h5(
            color: isDark ? DarkColors.white100 : LightColors.black100,
            fontWeight: AppFontWeights.semiBold,
          ),
        ),
        const SizedBox(height: 16),

        // H1 - H6
        _buildTextStyleItem('H1', AppTextStyles.h1(), '96px', isDark),
        _buildTextStyleItem('H2', AppTextStyles.h2(), '60px', isDark),
        _buildTextStyleItem('H3', AppTextStyles.h3(), '48px', isDark),
        _buildTextStyleItem('H4', AppTextStyles.h4(), '34px', isDark),
        _buildTextStyleItem('H5', AppTextStyles.h5(), '24px', isDark),
        _buildTextStyleItem('H6', AppTextStyles.h6(), '20px', isDark),

        const Divider(height: 32),

        // Subtitle & Body
        _buildTextStyleItem(
          'Subtitle1',
          AppTextStyles.subtitle1(),
          '16px',
          isDark,
        ),
        _buildTextStyleItem(
          'Subtitle2',
          AppTextStyles.subtitle2(),
          '14px',
          isDark,
        ),
        _buildTextStyleItem('Body1', AppTextStyles.body1(), '16px', isDark),
        _buildTextStyleItem('Body2', AppTextStyles.body2(), '14px', isDark),
        _buildTextStyleItem('Body3', AppTextStyles.body3(), '12px', isDark),
      ],
    );
  }

  /// 构建单个文本样式展示项
  Widget _buildTextStyleItem(
    String name,
    TextStyle style,
    String size,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              name,
              style: AppTextStyles.body2(
                color: isDark ? DarkColors.white80 : LightColors.black80,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              size,
              style: AppTextStyles.body2(
                color: isDark ? DarkColors.white40 : LightColors.black40,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Typography 排版示例',
              style: style.copyWith(
                color: isDark ? DarkColors.white100 : LightColors.black100,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建颜色系统展示
  Widget _buildColorsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '颜色系统',
          style: AppTextStyles.h5(
            color: isDark ? DarkColors.white100 : LightColors.black100,
            fontWeight: AppFontWeights.semiBold,
          ),
        ),
        const SizedBox(height: 16),

        // 黑白色系
        Text(
          '黑白色系',
          style: AppTextStyles.subtitle1(
            color: isDark ? DarkColors.white100 : LightColors.black100,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (isDark) ...[
              _buildColorBox('White 100%', DarkColors.white100),
              _buildColorBox('White 80%', DarkColors.white80),
              _buildColorBox('White 40%', DarkColors.white40),
              _buildColorBox('White 20%', DarkColors.white20),
              _buildColorBox('White 15%', DarkColors.white15),
              _buildColorBox('White 10%', DarkColors.white10),
            ] else ...[
              _buildColorBox('Black 100%', LightColors.black100),
              _buildColorBox('Black 80%', LightColors.black80),
              _buildColorBox('Black 40%', LightColors.black40),
              _buildColorBox('Black 20%', LightColors.black20),
              _buildColorBox('Black 10%', LightColors.black10),
            ],
          ],
        ),

        const SizedBox(height: 24),

        // 主色和次要颜色
        Text(
          '主色与次要颜色',
          style: AppTextStyles.subtitle1(
            color: isDark ? DarkColors.white100 : LightColors.black100,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildColorBox(
              'Primary',
              isDark ? DarkColors.primary : LightColors.primary,
            ),
            _buildColorBox(
              'Purple',
              isDark ? DarkColors.purple : LightColors.purple,
            ),
            _buildColorBox(
              'Indigo',
              isDark ? DarkColors.indigo : LightColors.indigo,
            ),
            _buildColorBox('Blue', isDark ? DarkColors.blue : LightColors.blue),
            _buildColorBox('Cyan', isDark ? DarkColors.cyan : LightColors.cyan),
            _buildColorBox('Mint', isDark ? DarkColors.mint : LightColors.mint),
            _buildColorBox(
              'Green',
              isDark ? DarkColors.green : LightColors.green,
            ),
            _buildColorBox(
              'Yellow',
              isDark ? DarkColors.yellow : LightColors.yellow,
            ),
            _buildColorBox(
              'Orange',
              isDark ? DarkColors.orange : LightColors.orange,
            ),
            _buildColorBox('Red', isDark ? DarkColors.red : LightColors.red),
          ],
        ),

        const SizedBox(height: 24),

        // 背景色
        Text(
          '背景色',
          style: AppTextStyles.subtitle1(
            color: isDark ? DarkColors.white100 : LightColors.black100,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildColorBox(
              'Background 1',
              isDark ? DarkColors.background1 : LightColors.background1,
            ),
            _buildColorBox(
              'Background 2',
              isDark ? DarkColors.background2 : LightColors.background2,
            ),
            _buildColorBox(
              'Background 3',
              isDark ? DarkColors.background3 : LightColors.background3,
            ),
            _buildColorBox(
              'Background 4',
              isDark ? DarkColors.background4 : LightColors.background4,
            ),
            _buildColorBox(
              'Background 5',
              isDark ? DarkColors.background5 : LightColors.background5,
            ),
            _buildColorBox(
              'Background 6',
              isDark ? DarkColors.background6 : LightColors.background6,
            ),
          ],
        ),
      ],
    );
  }

  /// 构建颜色块
  Widget _buildColorBox(String name, Color color) {
    return Container(
      width: 150,
      height: 80,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        style: AppTextStyles.caption(
          color: _getContrastColor(color),
          fontWeight: AppFontWeights.medium,
        ),
      ),
    );
  }

  /// 获取对比色（用于文本显示）
  Color _getContrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// 构建组件展示
  Widget _buildComponentsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '组件示例',
          style: AppTextStyles.h5(
            color: isDark ? DarkColors.white100 : LightColors.black100,
            fontWeight: AppFontWeights.semiBold,
          ),
        ),
        const SizedBox(height: 16),

        // 按钮
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('主要按钮')),
            TextButton(onPressed: () {}, child: const Text('文本按钮')),
            OutlinedButton(onPressed: () {}, child: const Text('轮廓按钮')),
          ],
        ),

        const SizedBox(height: 24),

        // 输入框
        SizedBox(
          width: 300,
          child: TextField(
            decoration: InputDecoration(
              labelText: '标签',
              hintText: '请输入内容...',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '卡片标题',
                  style: AppTextStyles.h6(
                    color: isDark ? DarkColors.white100 : LightColors.black100,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '这是一个示例卡片，展示了卡片的样式效果。',
                  style: AppTextStyles.body2(
                    color: isDark ? DarkColors.white80 : LightColors.black80,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
