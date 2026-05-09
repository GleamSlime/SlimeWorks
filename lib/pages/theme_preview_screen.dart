import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/provider/main.dart';

import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/theme/app_colors.dart';

/// 主题演示页面
/// 展示所有字体大小和颜色的效果
class ThemePreviewScreen extends StatelessWidget {
  const ThemePreviewScreen({super.key});

  DesktopScreenProvider get desktopScreen => getIt.get<DesktopScreenProvider>();

  @override
  Widget build(BuildContext context) {
    final isDark = Get.isDarkMode;

    /// 构建排版系统展示
    Widget buildTypographySection(bool isDark) {
      ThemeData theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '排版系统',
            style: TextStyle(fontSize: 22.0, height: 1.4,
              color: isDark ? DarkColors.white100 : LightColors.black100,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),
          Obx(
            () => Text(
              "桌面尺寸: ${desktopScreen.width.value.toStringAsFixed(0)} x ${desktopScreen.height.value.toStringAsFixed(0)} (是否为移动端: ${desktopScreen.isMobile.value})",
              style: TextStyle(fontSize: 13.0, height: 1.5, color: isDark ? DarkColors.white80 : LightColors.black80),
            ),
          ),

          const SizedBox(height: 16),

          // H1 - H6
          _buildTextStyleItem('H1', TextStyle(fontSize: 72.0, height: 1.2,), '96px', isDark),
          _buildTextStyleItem('H2', TextStyle(fontSize: 48.0, height: 1.2,), '60px', isDark),
          _buildTextStyleItem('H3', TextStyle(fontSize: 36.0, height: 1.3,), '48px', isDark),
          _buildTextStyleItem('H4', TextStyle(fontSize: 28.0, height: 1.3,), '34px', isDark),
          _buildTextStyleItem('H5', TextStyle(fontSize: 22.0, height: 1.4), '24px', isDark),
          _buildTextStyleItem('H6', TextStyle(fontSize: 18.0, height: 1.4,), '20px', isDark),

          const Divider(height: 32),

          // Subtitle & Body
          _buildTextStyleItem('Subtitle1', TextStyle(fontSize: 15.0, height: 1.5,), '16px', isDark),
          _buildTextStyleItem('Subtitle2', TextStyle(fontSize: 13.0, height: 1.5,), '14px', isDark),
          _buildTextStyleItem('Body1', TextStyle(fontSize: 15.0, height: 1.5), '16px', isDark),
          _buildTextStyleItem('Body2', TextStyle(fontSize: 13.0, height: 1.5), '14px', isDark),
          _buildTextStyleItem('Body3', TextStyle(fontSize: 11.0, height: 1.5,), '12px', isDark),

          const Divider(height: 32),

          _buildTextStyleItem(
            'HeadlineLarge',
            theme.textTheme.headlineLarge,
            '${theme.textTheme.headlineLarge?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'headlineMedium',
            theme.textTheme.headlineMedium,
            '${theme.textTheme.headlineMedium?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'headlineSmall',
            theme.textTheme.headlineSmall,
            '${theme.textTheme.headlineSmall?.fontSize ?? 0}px',
            isDark,
          ),

          const Divider(height: 32),

          _buildTextStyleItem(
            'labelLarge',
            theme.textTheme.labelLarge,
            '${theme.textTheme.labelLarge?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'labelMedium',
            theme.textTheme.labelMedium,
            '${theme.textTheme.labelMedium?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'labelSmall',
            theme.textTheme.labelSmall,
            '${theme.textTheme.labelSmall?.fontSize ?? 0}px',
            isDark,
          ),

          const Divider(height: 32),

          _buildTextStyleItem(
            'bodyLarge',
            theme.textTheme.bodyLarge,
            '${theme.textTheme.bodyLarge?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'bodyMedium',
            theme.textTheme.bodyMedium,
            '${theme.textTheme.bodyMedium?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'bodySmall',
            theme.textTheme.bodySmall,
            '${theme.textTheme.bodySmall?.fontSize ?? 0}px',
            isDark,
          ),

          const Divider(height: 32),

          _buildTextStyleItem(
            'titleLarge',
            theme.textTheme.titleLarge,
            '${theme.textTheme.titleLarge?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'titleMedium',
            theme.textTheme.titleMedium,
            '${theme.textTheme.titleMedium?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'titleSmall',
            theme.textTheme.titleSmall,
            '${theme.textTheme.titleSmall?.fontSize ?? 0}px',
            isDark,
          ),

          const Divider(height: 32),

          _buildTextStyleItem(
            'displayLarge',
            theme.textTheme.displayLarge,
            '${theme.textTheme.displayLarge?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'displayMedium',
            theme.textTheme.displayMedium,
            '${theme.textTheme.displayMedium?.fontSize ?? 0}px',
            isDark,
          ),
          _buildTextStyleItem(
            'displaySmall',
            theme.textTheme.displaySmall,
            '${theme.textTheme.displaySmall?.fontSize ?? 0}px',
            isDark,
          ),
        ],
      );
    }

    return ScreenChrome(
      data: const ScreenChromeData(title: '主题预览'),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 切换系统主题
              SwitchListTile(
                title: Text(
                  '切换系统主题',
                  style: TextStyle(fontSize: 15.0, height: 1.5,
                    color: isDark ? DarkColors.white100 : LightColors.black100,
                  ),
                ),
                value: Get.isDarkMode,
                onChanged: (value) {
                  if (value) {
                    Get.changeThemeMode(ThemeMode.dark);
                  } else {
                    Get.changeThemeMode(ThemeMode.light);
                  }
                },
              ),
              const SizedBox(height: 32),

              // 字体大小展示
              buildTypographySection(isDark),

              const SizedBox(height: 48),

              // 颜色展示
              _buildColorsSection(isDark),

              const SizedBox(height: 48),

              // 组件展示
              _buildComponentsSection(isDark),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单个文本样式展示项
  Widget _buildTextStyleItem(String name, TextStyle? style, String size, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              name,
              style: TextStyle(fontSize: 13.0, height: 1.5, color: isDark ? DarkColors.white80 : LightColors.black80),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              size,
              style: TextStyle(fontSize: 13.0, height: 1.5, color: isDark ? DarkColors.white40 : LightColors.black40),
            ),
          ),
          Expanded(
            child: Text(
              'Typography 排版示例',
              style: style?.copyWith(color: isDark ? DarkColors.white100 : LightColors.black100),
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
          style: TextStyle(fontSize: 22.0, height: 1.4,
            color: isDark ? DarkColors.white100 : LightColors.black100,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),

        // 黑白色系
        Text(
          '黑白色系',
          style: TextStyle(fontSize: 15.0, height: 1.5,
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
          style: TextStyle(fontSize: 15.0, height: 1.5,
            color: isDark ? DarkColors.white100 : LightColors.black100,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildColorBox('Primary', isDark ? DarkColors.primary : LightColors.primary),
            _buildColorBox('Purple', isDark ? DarkColors.purple : LightColors.purple),
            _buildColorBox('Indigo', isDark ? DarkColors.indigo : LightColors.indigo),
            _buildColorBox('Blue', isDark ? DarkColors.blue : LightColors.blue),
            _buildColorBox('Cyan', isDark ? DarkColors.cyan : LightColors.cyan),
            _buildColorBox('Mint', isDark ? DarkColors.mint : LightColors.mint),
            _buildColorBox('Green', isDark ? DarkColors.green : LightColors.green),
            _buildColorBox('Yellow', isDark ? DarkColors.yellow : LightColors.yellow),
            _buildColorBox('Orange', isDark ? DarkColors.orange : LightColors.orange),
            _buildColorBox('Red', isDark ? DarkColors.red : LightColors.red),
          ],
        ),

        const SizedBox(height: 24),

        // 背景色
        Text(
          '背景色',
          style: TextStyle(fontSize: 15.0, height: 1.5,
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
        border: Border.all(color: Colors.grey.withAlpha(77), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        style: TextStyle(fontSize: 11.0, height: 1.4,
          color: _getContrastColor(color),
          fontWeight: FontWeight.w500,
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
          style: TextStyle(fontSize: 22.0, height: 1.4,
            color: isDark ? DarkColors.white100 : LightColors.black100,
            fontWeight: FontWeight.w600,
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
                  style: TextStyle(fontSize: 18.0, height: 1.4,
                    color: isDark ? DarkColors.white100 : LightColors.black100,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '这是一个示例卡片，展示了卡片的样式效果。',
                  style: TextStyle(fontSize: 13.0, height: 1.5,
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
