import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/components/window/window_backdrop.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/provider/screen_provider.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/core/widgets/app_chips.dart';
import 'package:slime_works/core/widgets/app_card.dart';
import 'package:slime_works/core/widgets/empty_state.dart';
import 'package:slime_works/core/widgets/glass_menu.dart';
import 'package:slime_works/core/widgets/glass_surface.dart';
import 'package:slime_works/core/widgets/page_container.dart';
import 'package:slime_works/core/widgets/section_header.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';

/// 设计系统总览（原"主题预览"）
///
/// 这是本次 UI 统一的验收工具：所有 token、组件、明暗差异、磨砂与投影
/// 都在这一个页面里可比对。改一处主题定义，这里立刻能看出全站效果，
/// 不必逐个页面翻。
class ThemePreviewScreen extends StatefulWidget {
  const ThemePreviewScreen({super.key});

  @override
  State<ThemePreviewScreen> createState() => _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends State<ThemePreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return ScreenChrome(
      data: ScreenChromeData(
        title: '设计系统总览',
        actions: [
          // 明暗切换：语义层是否真的自动解析，切一下就知道了
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('浅色')),
              ButtonSegment(value: true, label: Text('深色')),
            ],
            selected: {s.isDark},
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              // 只写响应式状态：MyApp 的 build 里 Obx 会据此重建 theme/darkTheme。
              // 不能用 Get.changeThemeMode——本项目用的是 MaterialApp.router，
              // Get 并未持有 ThemeData 控制权，调用会抛异常。
              AppTheme.themeModeObs.value = v.first ? ThemeMode.dark : ThemeMode.light;
            },
          ),
          SizedBox(width: m.kSpace12),
        ],
      ),
      child: Scaffold(
        body: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace24),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: s.hairline, width: scaleW(1))),
                ),
                child: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerHeight: 0,
                  tabs: [
                    Tab(text: '色彩与表面'),
                    Tab(text: '排版'),
                    Tab(text: '组件'),
                    Tab(text: '玻璃与投影'),
                    Tab(text: '动效'),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _ColorTab(),
                    _TypographyTab(),
                    _ComponentsTab(),
                    _GlassTab(),
                    _MotionTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 各 Tab 的公共外壳：统一内距与最大宽度
class _Pane extends StatelessWidget {
  const _Pane({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ContentContainer(
        width: ContentWidth.wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in children) ...[c, SizedBox(height: AppTheme.metrics.kSpace32)],
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.note});
  final String title;
  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, subtitle: note),
        child,
        SizedBox(height: m.kSpace8),
      ],
    );
  }
}

// ───────────────────────────── 色彩 ─────────────────────────────

/// 语义色经主题插值后可能带小数通道，这里统一成 #RRGGBB 展示
String _colorHex(Color c) {
  String part(double v) => v.clamp(0, 1).round()
      .toRadixString(16)
      .padLeft(2, '0')
      .toUpperCase();
  return '#${part(c.r)}${part(c.g)}${part(c.b)}';
}


class _ColorTab extends StatelessWidget {
  const _ColorTab();

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    Widget swatch(String name, Color color, {String? hex}) {
      return SizedBox(
        width: scaleW(150),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: scaleW(52),
              decoration: BoxDecoration(
                color: color,
                borderRadius: m.radius8,
                border: Border.all(color: s.border, width: scaleW(1)),
              ),
            ),
            SizedBox(height: m.kSpace6),
            Text(name, style: AppTextStyles.caption(context)),
            Text(
              hex ?? _colorHex(color),
              style: AppTextStyles.mono(context, size: m.fontSize10),
            ),
          ],
        ),
      );
    }

    Widget row(List<Widget> children) => Wrap(
      spacing: m.kSpace16,
      runSpacing: m.kSpace16,
      children: children,
    );

    return _Pane(
      children: [
        _Block(
          title: '表面层次',
          note: '同一色相下的小幅明度阶梯。页面深度靠它，而不是靠彩色块。',
          child: row([
            swatch('canvas 画布', s.canvas),
            swatch('surface 表面', s.surface),
            swatch('raised 浮起', s.surfaceRaised),
            swatch('sunken 下沉', s.surfaceSunken),
            swatch('hover 悬停', s.surfaceHover),
            swatch('active 选中', s.surfaceActive),
          ]),
        ),
        _Block(
          title: '描边三档',
          note:
              '历史上 black1/white1 与 black10/white10 取值相同（都是 0x1A），'
              '发丝线实际以 10% 绘制，因此全站分割线偏重。现已分离。',
          child: row([
            _BorderedBox('hairline 发丝线', s.hairline),
            _BorderedBox('border 常规', s.border),
            _BorderedBox('borderStrong 强调', s.borderStrong),
          ]),
        ),
        _Block(
          title: '文字层级',
          child: row([
            swatch('textPrimary', s.textPrimary),
            swatch('textSecondary', s.textSecondary),
            swatch('textTertiary', s.textTertiary),
            swatch('textDisabled', s.textDisabled),
          ]),
        ),
        _Block(
          title: '强调色',
          note:
              '亮色下主色从品牌软紫自动加深到可承载白字的深度'
              '（#A89FEE 对白底对比度仅 1.9，直接用会发灰）。',
          child: row([
            swatch('accent 强调', s.accent),
            swatch('accentText 文字', s.accentText),
            swatch('accentContainer 容器', s.accentContainer),
            swatch('brand.soft 品牌软紫', AppBrand.soft),
          ]),
        ),
        _Block(
          title: '语义状态色',
          note: '取代 259 处 Colors.green / orange / red 裸用；容器底与文字同源于一个角色。',
          child: row([
            for (final tone in Tone.values)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(label: tone.name, tone: tone, showDot: true),
                  SizedBox(height: m.kSpace8),
                  StatusChip(label: tone.name, tone: tone, dense: true),
                ],
              ),
          ]),
        ),
        _Block(
          title: '自定义主题色跟随',
          note: '改主色时语义层必须同步，否则新组件不动、只有老代码变——这是原实现的断层。',
          child: _AccentPickerRow(color: AppTheme.accentColorObs.value),
        ),
        _Block(
          title: '字号缩放跟随',
          child: Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前 ${AppTheme.fontScaleObs.value.toStringAsFixed(2)}x'),
                SizedBox(height: m.kSpace8),
                Slider(
                  value: AppTheme.fontScaleObs.value,
                  min: 0.8,
                  max: 1.4,
                  divisions: 12,
                  onChanged: (v) => AppTheme.fontScaleObs.value = v,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _BorderedBox extends StatelessWidget {
  const _BorderedBox(this.label, this.borderColor);
  final String label;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return SizedBox(
      width: scaleW(180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: scaleW(52),
            decoration: BoxDecoration(
              color: s.surface,
              borderRadius: m.radius8,
              border: Border.all(color: borderColor, width: scaleW(1)),
            ),
          ),
          SizedBox(height: m.kSpace6),
          Text(label, style: AppTextStyles.caption(context)),
        ],
      ),
    );
  }
}

class _AccentPickerRow extends StatelessWidget {
  const _AccentPickerRow({required this.color});
  final Color color;

  static const List<Color> _presets = [
    Color(0xFFA89FEE),
    Color(0xFF6F5FD9),
    Color(0xFF6FB8E8),
    Color(0xFF82D7BB),
    Color(0xFFF5A569),
    Color(0xFFFF6C74),
  ];

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Wrap(
      spacing: m.kSpace10,
      runSpacing: m.kSpace10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in _presets)
          GestureDetector(
            onTap: () => AppTheme.accentColorObs.value = c,
            child: Container(
              width: scaleW(28),
              height: scaleW(28),
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == color ? Colors.black : Colors.transparent,
                  width: scaleW(2),
                ),
              ),
            ),
          ),
        Text('当前：${_colorHex(color)}', style: AppTextStyles.caption(context)),
      ],
    );
  }

}

// ───────────────────────────── 排版 ─────────────────────────────

class _TypographyTab extends StatelessWidget {
  const _TypographyTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    Widget item(String role, TextStyle? style, String source) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: scaleW(120),
              child: Text(role, style: AppTextStyles.caption(context)),
            ),
            SizedBox(
              width: scaleW(110),
              child: Text(source, style: AppTextStyles.mono(context, size: m.fontSize10)),
            ),
            Expanded(
              child: Text('SlimeWorks 设计系统 Aa 0123456789', style: style),
            ),
          ],
        ),
      );
    }

    return _Pane(
      children: [
        _Block(
          title: '语义文本角色',
          note: '规范文档一直引用 AppTextStyles 但它此前并不存在，各页因此手搭字号——这是 12 种小节标题的成因。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item('pageTitle', AppTextStyles.pageTitle(context), 'AppTextStyles'),
              item('sectionTitle', AppTextStyles.sectionTitle(context), 'AppTextStyles'),
              item('cardTitle', AppTextStyles.cardTitle(context), 'AppTextStyles'),
              item('body', AppTextStyles.body(context), 'AppTextStyles'),
              item('caption', AppTextStyles.caption(context), 'AppTextStyles'),
              item('overline', AppTextStyles.overline(context), 'AppTextStyles'),
              item('metric', AppTextStyles.metric(context), 'AppTextStyles'),
            ],
          ),
        ),
        _Block(
          title: 'Material 文本槽位',
          note: '明暗两套主题现在共用同一份定义，字重不再一边 w500 一边缺省。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item('displayLarge', theme.textTheme.displayLarge, 'textTheme'),
              item('displaySmall', theme.textTheme.displaySmall, 'textTheme'),
              item('headlineMedium', theme.textTheme.headlineMedium, 'textTheme'),
              item('titleLarge', theme.textTheme.titleLarge, 'textTheme'),
              item('titleMedium', theme.textTheme.titleMedium, 'textTheme'),
              item('bodyLarge', theme.textTheme.bodyLarge, 'textTheme'),
              item('bodyMedium', theme.textTheme.bodyMedium, 'textTheme'),
              item('bodySmall', theme.textTheme.bodySmall, 'textTheme'),
              item('labelSmall', theme.textTheme.labelSmall, 'textTheme'),
            ],
          ),
        ),
        _Block(
          title: '字号令牌',
          child: Wrap(
            spacing: m.kSpace16,
            runSpacing: m.kSpace10,
            children: [
              for (final e in <String, double>{
                'fontSize9': m.fontSize9,
                'fontSize10': m.fontSize10,
                'fontSize11': m.fontSize11,
                'fontSize12': m.fontSize12,
                'fontSize13': m.fontSize13,
                'fontSize14': m.fontSize14,
                'fontSize15': m.fontSize15,
                'fontSize16': m.fontSize16,
                'fontSize18': m.fontSize18,
                'fontSize20': m.fontSize20,
                'fontSize24': m.fontSize24,
                'fontSize28': m.fontSize28,
              }.entries)
                Text('${e.key} · ${e.value.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: e.value, color: AppSemantic.of(context).textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── 组件 ─────────────────────────────

class _ComponentsTab extends StatelessWidget {
  const _ComponentsTab();

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return _Pane(
      children: [
        _Block(
          title: '按钮四档',
          note:
              'FilledButton 原本用了 54 次却没有对应主题，落到 M3 默认胶囊圆角，'
              '与 Elevated/Outlined 的 radius8 不一致；TextButton 主题被加了描边，'
              '导致 134 个文字按钮看起来像线框按钮。',
          child: Wrap(
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
        ),
        _Block(
          title: '图标按钮 / 选择控件',
          child: Wrap(
            spacing: m.kSpace12,
            runSpacing: m.kSpace12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ToolIconButton(icon: StrokeIcons.search),
              const ToolIconButton(icon: StrokeIcons.tune, selected: true),
              const ToolIconButton(icon: StrokeIcons.moreHoriz),
              Switch(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              Checkbox(value: true, onChanged: (_) {}),
              Checkbox(value: null, onChanged: (_) {}),
              RadioGroup<int>(
                groupValue: 0,
                onChanged: (_) {},
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Radio(value: 0), Radio(value: 1)],
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '输入框',
          child: SizedBox(
            width: scaleW(320),
            child: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(labelText: '标签', hintText: '占位文本'),
                ),
                SizedBox(height: m.kSpace12),
                const TextField(
                  decoration: InputDecoration(
                    labelText: '错误态',
                    errorText: '这里需要填写',
                  ),
                ),
              ],
            ),
          ),
        ),
        _Block(
          title: '卡片',
          child: Row(
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
                      Text('叠加语义投影，跟随明暗主题。', style: AppTextStyles.body(context)),
                    ],
                  ),
                ),
              ),
              SizedBox(width: m.kSpace16),
              Expanded(
                child: AppCard(
                  selected: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选中卡片', style: AppTextStyles.cardTitle(context)),
                      SizedBox(height: m.kSpace6),
                      Text('强调色容器底 + 强调描边。', style: AppTextStyles.body(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '统计卡',
          note: '原先 _StatCardHover / StatCard / _StatChip / _InfoChip / _StatusPill 等 6 种实现。',
          child: Row(
            children: [
              Expanded(
                child: StatCard(
                  label: '媒体总数',
                  value: '12,480',
                  icon: StrokeIcons.photoLibrary,
                ),
              ),
              SizedBox(width: m.kSpace16),
              Expanded(
                child: StatCard(
                  label: '下载中',
                  value: '8',
                  hint: '8 项进行中 · 2 排队',
                  icon: StrokeIcons.downloading,
                  tone: s.info,
                ),
              ),
              SizedBox(width: m.kSpace16),
              Expanded(
                child: StatCard(
                  label: '异常',
                  value: '3',
                  icon: StrokeIcons.errorOutline,
                  tone: s.danger,
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '标签与徽标',
          child: Wrap(
            spacing: m.kSpace10,
            runSpacing: m.kSpace10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const TagChip(label: '科幻'),
              const TagChip(label: '已选', selected: true),
              const TagChip(label: '可移除', onRemoved: null),
              const CountBadge(count: 12),
              const CountBadge(count: 240),
              const CountBadge(count: 3, tone: Tone.danger),
              const StatusDot(tone: Tone.success, pulsing: true),
            ],
          ),
        ),
        _Block(
          title: '空状态 / 加载 / 骨架',
          note: '10 份各写各的空状态收敛到此；加载改骨架屏，避免列表高度跳动。',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    height: scaleW(180),
                    child: EmptyState(
                      title: '还没有内容',
                      description: '导入本地文件或连接节点后即可开始浏览。',
                      icon: StrokeIcons.folderOpen,
                      action: const FilledButton(
                        onPressed: null,
                        child: Text('去导入'),
                      ),
                    ),
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
                      const SkeletonBox(height: 12, width: 200),
                      SizedBox(height: m.kSpace14),
                      const SkeletonBox(height: 60, borderRadius: null),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '分栏与内容宽度',
          note: '18 种 maxWidth 收敛为 4 档语义档位。',
          child: Wrap(
            spacing: m.kSpace10,
            runSpacing: m.kSpace10,
            children: [for (final w in ContentWidth.values) TagChip(label: '${w.name} · ${w.rawMaxWidth}')],
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── 玻璃 ─────────────────────────────

class _GlassTab extends StatefulWidget {
  const _GlassTab();

  @override
  State<_GlassTab> createState() => _GlassTabState();
}

class _GlassTabState extends State<_GlassTab> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return _Pane(
      children: [
        _Block(
          title: '圆角令牌',
          note: '语义命名，调用点不必再记数字；music_player 等模块曾手写 6 种未走令牌的圆角。',
          child: Wrap(
            spacing: m.kSpace16,
            runSpacing: m.kSpace16,
            children: [
              _radiusBox('radiusControl', m.radiusControl),
              _radiusBox('radiusField', m.radiusField),
              _radiusBox('radiusCard', m.radiusCard),
              _radiusBox('radiusPanel', m.radiusPanel),
              _radiusBox('radiusOverlay', m.radiusOverlay),
              _radiusBox('radiusPill', m.radiusPill),
            ],
          ),
        ),
        _Block(
          title: '间距节奏',
          child: Wrap(
            spacing: m.kSpace12,
            runSpacing: m.kSpace8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final e in <String, double>{
                'kSpace2': m.kSpace2,
                'kSpace4': m.kSpace4,
                'kSpace6': m.kSpace6,
                'kSpace8': m.kSpace8,
                'kSpace12': m.kSpace12,
                'kSpace16': m.kSpace16,
                'kSpace20': m.kSpace20,
                'kSpace24': m.kSpace24,
                'kSpace32': m.kSpace32,
              }.entries)
                Column(
                  children: [
                    Container(
                      width: e.value * 2,
                      height: scaleW(20),
                      color: s.accent.withValues(alpha: 0.5),
                    ),
                    SizedBox(height: m.kSpace4),
                    Text('${e.key}\n${e.value.toStringAsFixed(1)}',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.mono(context, size: m.fontSize10)),
                  ],
                ),
            ],
          ),
        ),
        _Block(
          title: '抬升层级',
          child: Row(
            children: [
              for (final e in Elevation.values) ...[
                Expanded(
                  child: Container(
                    height: scaleW(72),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.surface,
                      borderRadius: m.radius8,
                      boxShadow: s.elevation(e),
                    ),
                    child: Text(e.name, style: AppTextStyles.caption(context)),
                  ),
                ),
                SizedBox(width: m.kSpace16),
              ],
            ],
          ),
        ),
        _Block(
          title: '磨砂玻璃：面板透出背后内容',
          note:
              '下方列表会滚动，玻璃面板浮在其上。看到列表在面板下变得柔和即为生效。'
              '侧边栏透出"桌面"需再叠一层原生 NSVisualEffectView（窗口级）。',
          child: SizedBox(
            height: scaleW(300),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    controller: _controller,
                    itemCount: 40,
                    itemBuilder: (context, i) => Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: m.kSpace8,
                        vertical: m.kSpace4,
                      ),
                      child: Container(
                        height: scaleW(28),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
                        decoration: BoxDecoration(
                          color: i.isEven ? s.surfaceSunken : s.surfaceHover,
                          borderRadius: m.radius6,
                        ),
                        child: Text('列表行 $i', style: AppTextStyles.caption(context)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: scaleW(40),
                  right: scaleW(40),
                  top: scaleW(70),
                  child: GlassSurface(
                    child: Padding(
                      padding: EdgeInsets.all(m.kSpace20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GlassSurface', style: AppTextStyles.cardTitle(context)),
                          SizedBox(height: m.kSpace6),
                          Text(
                            'tint + blur ${s.glassBlur.round()} + 发丝描边',
                            style: AppTextStyles.caption(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: scaleW(24),
                  bottom: scaleW(24),
                  child: GlassFloat(
                    child: Row(
                      children: [
                        const ToolIconButton(icon: StrokeIcons.playArrow),
                        const ToolIconButton(icon: StrokeIcons.skipNext),
                        SizedBox(width: m.kSpace6),
                        Text('悬浮工具条', style: AppTextStyles.caption(context)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _Block(
          title: '与不透明表面对比',
          child: Row(
            children: [
              Expanded(
                child: AppCard(
                  child: Text('不透明表面', style: AppTextStyles.caption(context)),
                ),
              ),
              SizedBox(width: m.kSpace16),
              Expanded(
                child: GlassSurface(
                  padding: EdgeInsets.all(m.kSpace16),
                  child: Text('玻璃表面', style: AppTextStyles.caption(context)),
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '菜单',
          note:
              '弹的是真菜单，样式即 popupMenuTheme：行高从 Material 默认的 48 收到 30，'
              '图标槽定宽所以文字齐整，选中项打勾、危险项整行染色，普通项与删除之间断行。'
              '下面这个用的是 position: under（贴着按钮下方展开，不盖住按钮本身）。',
          child: Row(
            children: [
              PopupMenuButton<String>(
                position: PopupMenuPosition.under,
                itemBuilder: (_) => [
                  GlassMenuItem<String>(
                    value: 'sort',
                    label: '按修改时间',
                    icon: StrokeIcons.schedule,
                    selected: true,
                  ),
                  GlassMenuItem<String>(
                    value: 'name',
                    label: '按文件名',
                    icon: StrokeIcons.sortByAlpha,
                  ),
                  GlassMenuItem<String>(
                    value: 'pin',
                    label: '固定到侧边栏',
                    icon: StrokeIcons.pushPin,
                  ),
                  const PopupMenuDivider(),
                  GlassMenuItem<String>(
                    value: 'delete',
                    label: '从库中移除',
                    icon: StrokeIcons.deleteOutline,
                    destructive: true,
                  ),
                ],
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: m.kSpace12,
                    vertical: m.kSpace8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DrawIcon(StrokeIcons.sort, size: m.iconSize16),
                      SizedBox(width: m.kSpace6),
                      Text('打开示例菜单', style: AppTextStyles.caption(context)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (Platform.isWindows) _BackdropDiagnosticsBlock(),
      ],
    );
  }

  Widget _radiusBox(String label, BorderRadius radius) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      children: [
        Container(
          width: scaleW(72),
          height: scaleW(48),
          decoration: BoxDecoration(
            color: s.accentContainer,
            borderRadius: radius,
            border: Border.all(color: s.accentContainerBorder, width: scaleW(1)),
          ),
        ),
        SizedBox(height: m.kSpace6),
        Text(label, style: AppTextStyles.caption(context)),
      ],
    );
  }
}

/// Windows 系统材质（Mica / 压克力）诊断。
///
/// 原生查得到的部分只是“DWM 认了这个材质”；材质画在顶层窗口上，而 Flutter 的内容
/// 画在它的一块子窗口里，子窗口的透明像素让不让材质透出来，属性里读不到，只能在这里
/// 当场换一种看效果。改的只是当前窗口的材质，不会留下副作用。
class _BackdropDiagnosticsBlock extends StatelessWidget {
  const _BackdropDiagnosticsBlock();

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return _Block(
      title: '系统材质（Windows）',
      note: '下面这几个值是原生回读回来的真实结果，不是请求值。'
          '换材质后侧栏应当跟着透出桌面的色调；如果发黑或毫无变化，'
          '说明材质被 Flutter 的子窗口挡住了，Windows 只能退回实心底。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: m.kSpace16,
            runSpacing: m.kSpace6,
            children: [
              _fact(context, '系统 build', '${WindowsBackdrop.buildNumber}'),
              _fact(context, '透明效果',
                  WindowsBackdrop.transparentEffectsEnabled ? '开' : '关'),
              _fact(context, '公开材质属性',
                  WindowsBackdrop.publicBackdropSupported ? '支持' : '不支持'),
              _fact(context, '内部 Mica 属性',
                  WindowsBackdrop.legacyMicaSupported ? '支持' : '不支持'),
              // 磨砂开关读的是 provider 里的 Rx，包一层 Obx 才能在换材质后跟着翻。
              Obx(() => _fact(
                    context,
                    '界面磨砂',
                    getIt<DesktopScreenProvider>().windowsBackdropActive.value
                        ? '开'
                        : '关（实心底）',
                  )),
            ],
          ),
          SizedBox(height: m.kSpace12),
          Obx(() => Wrap(
                spacing: m.kSpace8,
                children: [
                  for (final kind in BackdropKind.values)
                    OutlinedButton(
                      onPressed: () => WindowsBackdrop.apply(kind),
                      child: Text(WindowsBackdrop.applied == kind
                          ? '${kind.name}（当前）'
                          : kind.name),
                    ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：', style: AppTextStyles.caption(context)),
        Text(value,
            style: AppTextStyles.mono(context, size: m.fontSize11)
                .copyWith(color: s.textPrimary)),
      ],
    );
  }
}

// ───────────────────────────── 动效 ─────────────────────────────

class _MotionTab extends StatefulWidget {
  const _MotionTab();

  @override
  State<_MotionTab> createState() => _MotionTabState();
}

class _MotionTabState extends State<_MotionTab> {
  bool _expanded = false;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;

    return _Pane(
      children: [
        _Block(
          title: '时长与曲线',
          note: '原先满屏 250/280/300/400/600ms 各写各的，观感忽快忽慢。',
          child: Wrap(
            spacing: m.kSpace12,
            runSpacing: m.kSpace12,
            children: [
              for (final e in <String, Duration>{
                'instant': AppMotion.instant,
                'fast': AppMotion.fast,
                'base': AppMotion.base,
                'slow': AppMotion.slow,
                'emphasis': AppMotion.emphasis,
              }.entries)
                StatusChip(label: '${e.key} · ${e.value.inMilliseconds}ms', tone: Tone.accent),
            ],
          ),
        ),
        _Block(
          title: '悬停：改底色而非缩放',
          note: '卡片 hover 用 1.04 缩放会让整排内容抖动重叠，是廉价感主要来源。',
          child: Row(
            children: [
              Expanded(
                child: Hoverable(
                  onTap: () {},
                  borderRadius: m.radiusCard,
                  child: Container(
                    height: scaleW(72),
                    alignment: Alignment.center,
                    child: Text('Hoverable（底色）', style: AppTextStyles.caption(context)),
                  ),
                ),
              ),
              SizedBox(width: m.kSpace16),
              Expanded(
                child: AppCard(
                  onTap: () {},
                  child: Text('AppCard（自带悬停态）', style: AppTextStyles.caption(context)),
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '展开 / 收起',
          child: AppCard(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: '点击切换',
                  subtitle: 'duration=${AppMotion.base.inMilliseconds}ms · emphasizedDecelerate',
                  trailing: AnimatedRotation(
                    duration: AppMotion.base,
                    curve: AppMotion.standard,
                    turns: _expanded ? 0.25 : 0,
                    child: DrawIcon(StrokeIcons.chevronRight, size: m.iconSize18, color: s.textTertiary),
                  ),
                ),
                AnimatedSize(
                  duration: AppMotion.base,
                  curve: AppMotion.decelerate,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: EdgeInsets.only(bottom: m.kSpace8),
                          child: Text(
                            '展开后的内容。AnimatedSize 配 topCenter 可避免收起时向上跳。',
                            style: AppTextStyles.body(context),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
        _Block(
          title: '交错入场',
          note: '取代各页手写的 Future.delayed(300 + index * 80)——那种写法会造成可点击但无内容的空窗。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                onPressed: () => setState(() => _replay++),
                child: const Text('重播动画'),
              ),
              SizedBox(height: m.kSpace12),
              KeyedSubtree(
                key: ValueKey('stagger-$_replay'),
                child: Row(
                  children: [
                    for (var i = 0; i < 6; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 5 ? 0 : m.kSpace10),
                          child: StaggerEntrance(
                            index: i,
                            child: Container(
                              height: scaleW(56),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: s.accentContainer,
                                borderRadius: m.radius8,
                                border: Border.all(
                                  color: s.accentContainerBorder,
                                  width: scaleW(1),
                                ),
                              ),
                              child: Text('$i', style: AppTextStyles.caption(context)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Block(
          title: '脉冲状态点',
          child: Wrap(
            spacing: m.kSpace20,
            runSpacing: m.kSpace12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusDot(tone: Tone.success, pulsing: true),
              const StatusDot(tone: Tone.warning, pulsing: true),
              const StatusDot(tone: Tone.danger, pulsing: true),
              Text('用于节点在线、下载中等持续状态', style: AppTextStyles.caption(context)),
            ],
          ),
        ),
      ],
    );
  }
}
