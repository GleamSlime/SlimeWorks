// 打上 golden 标签：CI 用 `flutter test --exclude-tags golden` 跳过像素比对
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/widgets/app_chips.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/widgets/empty_state.dart';
import 'package:slime_works/core/widgets/glass_surface.dart';
import 'package:slime_works/core/widgets/section_header.dart';

/// 设计系统离屏渲染
///
/// 目的不是断言像素，而是**让人看得见**主题改动的结果：
/// `flutter test --update-goldens test/design_system_render_test.dart`
/// 会在 test/goldens/ 下产出 light/dark 两张整页 PNG，不需要启动 macOS
/// 应用、也不需要屏幕录制权限。改完 token 跑一次即可肉眼验收。
void main() {
  setUpAll(() async {
    // 测试环境默认用占位字体（所有字形都是方块），必须把项目字体喂进去
    // 才能看清中文排版效果。
    for (final entry in const {
      'FZLanTingYuanS-EB-GB': 'assets/fonts/FZLanTingYuanS-EB-GB.ttf',
    }.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(entry.key)
        ..addFont(
          Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
        );
      await loader.load();
    }
  });

  testWidgets('浅色设计系统总览', (tester) async {
    await _render(tester, dark: false, file: 'goldens/design_light.png');
  });

  testWidgets('深色设计系统总览', (tester) async {
    await _render(tester, dark: true, file: 'goldens/design_dark.png');
  });
}

Future<void> _render(
  WidgetTester tester, {
  required bool dark,
  required String file,
}) async {
  tester.view.physicalSize = const Size(1280, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1280, 2400),
      minTextAdapt: true,
      splitScreenMode: false,
      builder: (context, _) {
        AppTheme.resetMetrics();
        final theme = dark
            ? AppTheme.buildCustomDark(DarkColors.primary, 1.0)
            : AppTheme.buildCustomLight(LightColors.primary, 1.0);
        // 这里不能对 context 调 AppSemantic.of()：它挂在 ScreenUtilInit 的
        // builder 上，位于 MaterialApp 之上，还没有 Theme。
        final semantic = dark ? AppSemantic.dark : AppSemantic.light;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Scaffold(
            backgroundColor: semantic.canvas,
            body: _Gallery(dark: dark),
          ),
        );
      },
    ),
  );

  // 不能用 pumpAndSettle：状态点呼吸、骨架屏微光是无限动画，永远静不下来。
  // 这里显式推进固定时长，让截图帧的动画相位可复现。
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(file),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.all(m.kSpace24),
      children: [
        // 标题：渐变文字（dashboard 用的就是这条渐变）
        ShaderMask(
          shaderCallback: (b) => s.accentGradient.createShader(b),
          child: Text(
            '工坊系统',
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: m.kSpace4),
        Text('实时监控 · 模块管理 · 一站式工具', style: AppTextStyles.body(context)),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '表面层次', subtitle: '画布与卡片必须拉开，否则整页发平'),
        Row(
          children: [
            _chip(context, 'canvas', s.canvas),
            SizedBox(width: m.kSpace12),
            _chip(context, 'surface', s.surface),
            SizedBox(width: m.kSpace12),
            _chip(context, 'sunken', s.surfaceSunken),
            SizedBox(width: m.kSpace12),
            _chip(context, 'hover', s.surfaceHover),
            SizedBox(width: m.kSpace12),
            _chip(context, 'active', s.surfaceActive),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '卡片'),
        Row(
          children: [
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('标准卡片', style: AppTextStyles.cardTitle(context)),
                    SizedBox(height: m.kSpace6),
                    Text('表面色 + 发丝描边，无投影。', style: AppTextStyles.body(context)),
                  ],
                ),
              ),
            ),
            SizedBox(width: m.kSpace16),
            Expanded(
              child: AppCard(
                elevated: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('抬升卡片', style: AppTextStyles.cardTitle(context)),
                    SizedBox(height: m.kSpace6),
                    Text('语义投影跟随明暗。', style: AppTextStyles.body(context)),
                  ],
                ),
              ),
            ),
            SizedBox(width: m.kSpace16),
            Expanded(
              child: AppCard(
                selected: true,
                child: Text('选中卡片', style: AppTextStyles.cardTitle(context)),
              ),
            ),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '统计卡'),
        Row(
          children: [
            Expanded(child: StatCard(label: 'CPU', value: '4.6%')),
            SizedBox(width: m.kSpace16),
            Expanded(
              child: StatCard(
                label: '内存',
                value: '184 MB',
                icon: Icons.storage_rounded,
              ),
            ),
            SizedBox(width: m.kSpace16),
            Expanded(
              child: StatCard(
                label: '异常',
                value: '3',
                icon: Icons.error_outline_rounded,
                tone: s.danger,
              ),
            ),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '按钮四档', subtitle: '圆角/内距统一，TextButton 不再带描边'),
        Wrap(
          spacing: m.kSpace12,
          runSpacing: m.kSpace12,
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
            FilledButton(onPressed: () {}, child: const Text('Filled')),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            TextButton(onPressed: () {}, child: const Text('Text')),
            const FilledButton(onPressed: null, child: Text('Disabled')),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '状态胶囊'),
        Wrap(
          spacing: m.kSpace10,
          runSpacing: m.kSpace10,
          children: [
            for (final t in Tone.values)
              StatusChip(label: t.name, tone: t, showDot: true),
          ],
        ),
        SizedBox(height: m.kSpace16),
        Wrap(
          spacing: m.kSpace10,
          runSpacing: m.kSpace10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: const [
            TagChip(label: '标签'),
            TagChip(label: '已选', selected: true),
            CountBadge(count: 12),
            CountBadge(count: 240),
            StatusDot(tone: Tone.success),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '输入与选择'),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: '搜索',
                  hintText: '输入关键词…',
                  prefixIcon: Icon(Icons.search, size: 16),
                ),
              ),
            ),
            SizedBox(width: m.kSpace16),
            Switch(value: true, onChanged: (_) {}),
            SizedBox(width: m.kSpace8),
            Switch(value: false, onChanged: (_) {}),
            SizedBox(width: m.kSpace8),
            Checkbox(value: true, onChanged: (_) {}),
          ],
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '排版层级'),
        _typeRow(context, 'pageTitle', AppTextStyles.pageTitle(context)),
        _typeRow(context, 'sectionTitle', AppTextStyles.sectionTitle(context)),
        _typeRow(context, 'cardTitle', AppTextStyles.cardTitle(context)),
        _typeRow(context, 'body', AppTextStyles.body(context)),
        _typeRow(context, 'caption', AppTextStyles.caption(context)),
        _typeRow(context, 'overline', AppTextStyles.overline(context)),
        _typeRow(context, 'metric', AppTextStyles.metric(context)),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '磨砂玻璃', subtitle: '叠在列表之上，背后内容应被柔化'),
        SizedBox(
          height: m.kSpace80 * 2.6,
          child: Stack(
            children: [
              Positioned.fill(
                child: ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  itemBuilder: (context, i) => Padding(
                    padding: EdgeInsets.symmetric(vertical: m.kSpace4),
                    child: Container(
                      height: m.kSpace20,
                      // 背景必须高对比，否则"糊没糊"根本看不出来；
                      // 用强调色做斑马条，玻璃边缘的柔化才可见。
                      decoration: BoxDecoration(
                        color: s.accent.withValues(alpha: i.isOdd ? 0.55 : 0.18),
                        borderRadius: m.radius4,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: m.kSpace24,
                right: m.kSpace24,
                top: m.kSpace24,
                child: GlassSurface(
                  child: Padding(
                    padding: EdgeInsets.all(m.kSpace20),
                    child: Row(
                      children: [
                        Icon(Icons.bubble_chart, color: s.accent, size: m.iconSize20),
                        SizedBox(width: m.kSpace12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('GlassSurface', style: AppTextStyles.cardTitle(context)),
                              SizedBox(height: m.kSpace4),
                              Text(
                                'tint + blur ${s.glassBlur.round()} + 发丝描边',
                                style: AppTextStyles.caption(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '侧边栏观感预览'),
        _SidebarMock(dark: dark),
        SizedBox(height: m.kSpace24),

        SectionHeader(title: '空状态与骨架'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: EmptyState(
                  title: '还没有内容',
                  description: '导入本地文件或连接节点后即可开始浏览。',
                  icon: Icons.folder_open_outlined,
                  action: const FilledButton(onPressed: null, child: Text('去导入')),
                ),
              ),
            ),
            SizedBox(width: m.kSpace16),
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(height: 18, width: 140),
                    SizedBox(height: m.kSpace10),
                    const SkeletonBox(height: 12),
                    SizedBox(height: m.kSpace6),
                    const SkeletonBox(height: 12, width: 180),
                    SizedBox(height: m.kSpace14),
                    const SkeletonBox(height: 56),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: m.kSpace24),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: m.kSpace40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: m.radius8,
              border: Border.all(color: s.border, width: 1),
            ),
          ),
          SizedBox(height: m.kSpace4),
          Text(label, style: AppTextStyles.caption(context)),
        ],
      ),
    );
  }

  Widget _typeRow(BuildContext context, String role, TextStyle style) {
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: m.kSpace80,
            child: Text(role, style: AppTextStyles.caption(context)),
          ),
          Expanded(
            child: Text('SlimeWorks 设计系统 0123456789', style: style),
          ),
        ],
      ),
    );
  }
}

/// 用真实语义色拼一个侧边栏小样，判断它能否从内容区中"读出来"
class _SidebarMock extends StatelessWidget {
  const _SidebarMock({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    Widget item(IconData icon, String label, {bool selected = false}) {
      return Container(
        height: m.kSpace32 * 1.3,
        margin: EdgeInsets.symmetric(vertical: m.kSpace2),
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
        decoration: BoxDecoration(
          color: selected ? s.accentContainer : Colors.transparent,
          borderRadius: m.radiusControl,
        ),
        child: Row(
          children: [
            Icon(icon, size: m.iconSize16, color: selected ? s.accent : s.textTertiary),
            SizedBox(width: m.kSpace10),
            Text(
              label,
              style: TextStyle(
                fontSize: m.fontSize13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? s.accentText : s.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // stretch 对齐要求高度有界，而这里在 ListView 里、父级给的是无限高，
    // 所以必须显式定高，否则子节点拿到 Infinity 约束直接崩。
    return SizedBox(
      height: m.kSpace80 * 3.6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: m.kSpace80 * 2.6,
            padding: EdgeInsets.all(m.kSpace8),
            decoration: BoxDecoration(
              gradient: AppTheme.sideBarTheme(context),
              borderRadius: m.radiusPanel,
              border: Border.all(color: s.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                item(Icons.dashboard_outlined, '概览', selected: true),
                item(Icons.crop_free_rounded, '屏幕捕获'),
                item(Icons.swap_horiz_rounded, '互传'),
                SizedBox(height: m.kSpace12),
                Text('收藏夹', style: AppTextStyles.overline(context)),
                item(Icons.photo_library_outlined, '媒体库'),
                item(Icons.menu_book_outlined, '书库'),
              ],
            ),
          ),
          SizedBox(width: m.kSpace16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: s.surface,
                borderRadius: m.radiusPanel,
                border: Border.all(color: s.hairline, width: 1),
              ),
              child: Center(
                child: Text('内容区', style: AppTextStyles.caption(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
