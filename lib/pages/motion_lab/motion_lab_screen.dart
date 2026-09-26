import 'package:flutter/material.dart';

import 'cases/motion_lab_cases.dart';
import 'lab_kit.dart';

/// 动效实验室：43 个动效案例，一格一个组件
///
/// 这张页面的定位和样式总览页一样，是**看的东西**而不是**用的东西**：
/// 它复刻外部参考稿的每一个案例，尺寸/圆角/颜色/时长/曲线全部本地自带，
/// 不读也不写任何全局主题（`AppTheme` / `AppSemantic` / `AppMotion` 都不碰），
/// 所以它既不会被全站换肤带跑，也不会把任何东西带回全站。
///
/// 页面本身也不做继承 `BasePage` 那一套：它没有 ViewModel、不取服务、不进路由守卫
/// 的权限链路之外。案例文件之间互不引用，只被 `cases/motion_lab_cases.dart` 点名。
class MotionLabScreen extends StatefulWidget {
  const MotionLabScreen({super.key});

  @override
  State<MotionLabScreen> createState() => _MotionLabScreenState();
}

class _MotionLabScreenState extends State<MotionLabScreen> {
  LabCat? _cat;
  bool _proOnly = false;
  LabCase? _focused;

  List<LabCase> get _shown => kLabCases
      .where((c) => _cat == null || c.cat == _cat)
      .where((c) => !_proOnly || c.pro)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ColoredBox(
          color: LabColor.page,
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
                            LabCard(
                              seq: c.seq,
                              title: c.title,
                              subtitle: c.subtitle,
                              pro: c.pro,
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
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '动效实验室',
            style: TextStyle(
              fontFamily: LabFont.family,
              // 页头是中文，少了这行回退，离屏出图就是一排豆腐块
              fontFamilyFallback: LabFont.fallback,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: LabColor.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_shown.length} / ${kLabCases.length} 格，每格一个独立组件；'
            '右下角圆钮把这一格放大一倍单看。',
            style: LabText.subtitle,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(label: '全部', selected: _cat == null && !_proOnly, onTap: () {
                setState(() {
                  _cat = null;
                  _proOnly = false;
                });
              }),
              for (final cat in LabCat.values)
                _chip(
                  label: cat.label,
                  selected: _cat == cat,
                  onTap: () => setState(() => _cat = _cat == cat ? null : cat),
                ),
              _chip(label: '仅 Pro', selected: _proOnly, onTap: () {
                setState(() => _proOnly = !_proOnly);
              }),
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
          color: selected ? LabColor.text : LabColor.chip,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(
          label,
          style: LabText.title.copyWith(
            color: selected ? LabColor.card : LabColor.animateText,
            height: 16 / 13,
          ),
        ),
      ),
    );
  }

  /// 放大层：还是同一个案例组件，只是整块放大一倍看细节，不复制实现
  ///
  /// 放大走 `FittedBox` 而不是让组件自己改尺寸：舞台固定 296×260，
  /// 2 倍是整数缩放，细节看得清，组件本身也不用知道自己在被放大。
  Widget _buildFocus(LabCase c) {
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
                  Text('${c.seq}. ${c.title}', style: LabText.title.copyWith(fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(c.subtitle, style: LabText.subtitle),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: LabSize.stageW * 2,
                    height: LabSize.stageH * 2,
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
