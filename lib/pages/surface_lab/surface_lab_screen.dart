import 'package:flutter/material.dart';

import 'cases/surface_lab_cases.dart';
import 'kit.dart';

/// 表面实验室：9 个"表面怎么动"的组件，一格一个
///
/// 第三块参考页，定位和前两块一样——**看的东西，不是用的东西**：这一页复刻一组
/// 浮层与形变表面（按钮长成面板、悬浮窗被拽着走、金属钮被压进洞里、灵动岛鼓起来、
/// 一块表面翻成另一块……），尺寸/圆角/颜色/时长/弹簧参数全部本地自带，
/// 不读也不写任何全局主题（`AppTheme` / `AppSemantic` / `AppMotion` 都不碰）。
///
/// 和交互实验室的分工：那边看的是"手怎么把东西拖动"，判定和阈值同等重要；
/// 这边看的是**一块表面怎么变成另一块**，所以共享元素、裁切、投影这三族是主角。
class SurfaceLabScreen extends StatefulWidget {
  const SurfaceLabScreen({super.key});

  @override
  State<SurfaceLabScreen> createState() => _SurfaceLabScreenState();
}

class _SurfaceLabScreenState extends State<SurfaceLabScreen> {
  SvCat? _cat;
  SvCase? _focused;

  List<SvCase> get _shown =>
      kSvCases.where((c) => _cat == null || c.cat == _cat).toList();

  @override
  Widget build(BuildContext context) {
    // 整页自带默认字样式：这页的排版全部本地定义，不靠宿主那层 Material。
    // 少了这一行，页头/卡片标题在没有 Material 祖先时就接住 MaterialApp 的
    // 兜底样式——黄色双下划线
    return DefaultTextStyle(
      style: SvText.body,
      child: Stack(
        children: [
          ColoredBox(
            color: SvColor.pane,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                      child: Center(
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 24,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final c in _shown)
                              SvCard(
                                seq: c.seq,
                                title: c.title,
                                subtitle: c.subtitle,
                                stageW: c.stageW,
                                stageH: c.stageH,
                                dark: c.dark,
                                onEnlarge: () => setState(() => _focused = c),
                                stage: c.build(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_focused != null) _buildFocus(_focused!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '表面实验室',
            style: TextStyle(
              fontFamily: SvFont.family,
              // 页头是中文，少了这行回退，离屏出图就是一排豆腐块
              fontFamilyFallback: SvFont.fallback,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: SvColor.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_shown.length} / ${kSvCases.length} 格，每格一个独立组件；'
            '这一页看的是表面怎么变成另一块表面，右下角圆钮把这一格放大一倍单看。',
            style: SvText.subtitle,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                label: '全部',
                selected: _cat == null,
                onTap: () => setState(() => _cat = null),
              ),
              for (final cat in SvCat.values)
                _chip(
                  label: cat.label,
                  selected: _cat == cat,
                  onTap: () => setState(() => _cat = _cat == cat ? null : cat),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: SvEase.standard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? SvColor.primary : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          label,
          style: SvText.title.copyWith(
            color: selected ? SvColor.onPrimary : SvColor.primary,
            height: 20 / 14,
          ),
        ),
      ),
    );
  }

  /// 放大层：还是同一个案例组件，只是整块放大一倍看细节，不复制实现
  Widget _buildFocus(SvCase c) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _focused = null),
        child: ColoredBox(
          color: c.dark ? const Color(0xE60A0A0A) : const Color(0xE6FFFFFF),
          child: Center(
            child: GestureDetector(
              // 点案例本身不该关掉放大层
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${c.seq}. ${c.title}',
                    style: SvText.title.copyWith(
                      fontSize: 15,
                      color: c.dark ? SvDarkColor.text : SvColor.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.subtitle,
                    style: SvText.subtitle.copyWith(
                      color: c.dark ? SvDarkColor.textMuted : SvColor.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: c.stageW * 2,
                    height: c.stageH * 2,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Material(color: Colors.transparent, child: c.build()),
                    ),
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
