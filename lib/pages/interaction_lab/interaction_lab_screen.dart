import 'package:flutter/material.dart';

import 'cases/interaction_lab_cases.dart';
import 'kit.dart';

/// 交互实验室：12 个交互组件，一格一个
///
/// 和动效实验室同一套定位——**看的东西，不是用的东西**：这一页复刻一组带真实
/// 手势的组件（按住拖拽、下拉刷新、滑动确认、验证码融合……），尺寸/圆角/颜色/
/// 时长/弹簧参数全部本地自带，不读也不写任何全局主题（`AppTheme` / `AppSemantic`
/// / `AppMotion` 都不碰），所以它既不会被全站换肤带跑，也不会把东西带回全站。
///
/// 和动效实验室的分工：那边演的是"一个属性怎么从 A 补间到 B"，点一下就够；
/// 这边每一格都要真的按住、拖、敲键盘才成立，所以交互判定（阈值、吸附、
/// 松手回收）和动画参数同等重要。
class InteractionLabScreen extends StatefulWidget {
  const InteractionLabScreen({super.key});

  @override
  State<InteractionLabScreen> createState() => _InteractionLabScreenState();
}

class _InteractionLabScreenState extends State<InteractionLabScreen> {
  IlCat? _cat;
  IlCase? _focused;

  List<IlCase> get _shown =>
      kIlCases.where((c) => _cat == null || c.cat == _cat).toList();

  @override
  Widget build(BuildContext context) {
    // 整页自带默认字样式：这页的排版全部本地定义，不靠宿主那层 Material。
    // 少了这一行，页头/卡片标题在没有 Material 祖先时就接住 MaterialApp 的
    // 兜底样式——黄色双下划线
    return DefaultTextStyle(
      style: IlText.body,
      child: Stack(
        children: [
          ColoredBox(
            color: IlColor.page,
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
                              IlCard(
                                seq: c.seq,
                                title: c.title,
                                subtitle: c.subtitle,
                                stageW: c.stageW,
                                stageH: c.stageH,
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
            '交互实验室',
            style: TextStyle(
              fontFamily: IlFont.family,
              // 页头是中文，少了这行回退，离屏出图就是一排豆腐块
              fontFamilyFallback: IlFont.fallback,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: IlColor.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_shown.length} / ${kIlCases.length} 格，每格一个独立组件；'
            '这些都要真的按住、拖、敲键盘才成立，右下角圆钮把这一格放大一倍单看。',
            style: IlText.subtitle,
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
              for (final cat in IlCat.values)
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
        curve: Curves.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? IlColor.ink : const Color(0xFFF4F4F4),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          label,
          style: IlText.title.copyWith(
            color: selected ? IlColor.pane : IlColor.ink,
            height: 16 / 13,
          ),
        ),
      ),
    );
  }

  /// 放大层：还是同一个案例组件，只是整块放大一倍看细节，不复制实现
  ///
  /// 走 `FittedBox` 而不是让组件自己改尺寸：舞台固定 372×232，2 倍是整数缩放，
  /// 组件本身不用知道自己在被放大。
  Widget _buildFocus(IlCase c) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _focused = null),
        child: ColoredBox(
          color: const Color(0xE6FFFFFF),
          child: Center(
            child: GestureDetector(
              // 点案例本身不该关掉放大层
              onTap: () {},
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${c.seq}. ${c.title}', style: IlText.title.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(c.subtitle, style: IlText.subtitle),
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
