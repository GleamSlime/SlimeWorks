import 'dart:async';

import 'package:flutter/material.dart';

import '../kit.dart';

/// 2. Icon bar — 底部导航条：滑块先横跨再弹回
///
/// 参考稿这条滑块是**两相位**的，不是一条补间：
/// 1. stretch（190ms `cubic-bezier(.32,.72,.24,1)`）——起点变成"旧槽与
///    新槽的并集区间"，于是滑块一次性把中间跨过的格子全盖住；
/// 2. 保持 150ms（stretch 的钟其实有 190ms，到点就中途改目标）；
/// 3. settle（420ms）——位移走 `cubic-bezier(.28,1.28,.36,1)`、宽走
///    `cubic-bezier(.24,1.34,.38,1)`，第三个控制点超过 1 就是过冲，
///    也就是 Bounce 旋钮的全部作用。
/// 图标只有透明度（.42 / hover .72 / 选中 1，260ms），没有位移没有缩放。
class Case02IconBar extends StatefulWidget {
  const Case02IconBar({super.key});

  @override
  State<Case02IconBar> createState() => _Case02IconBarState();
}

enum _Phase { idle, stretch, settle }

class _Slot {
  const _Slot(this.p, this.s);

  final double p;
  final double s;
}

class _Case02IconBarState extends State<Case02IconBar> with SingleTickerProviderStateMixin {
  /// `--bar-slot:38` `--bar-pad:6` `--bar-gap:2`；条宽 = 6*2 + 38*5 + 2*4 = 210
  static const _slot = 38.0;
  static const _pad = 6.0;
  static const _gap = 2.0;
  static const _corner = 26.0;
  static const _barW = _pad * 2 + _slot * 5 + _gap * 4;
  static const _barH = _pad * 2 + _slot;

  /// `Pf(speed)=1.6-speed/100*1.2`，speed=50 → 1.0，于是三段就是
  /// `190*1.0` / `420*1.0` / `150*1.0`
  static const _stretchDur = Duration(milliseconds: 190);
  static const _settleDur = Duration(milliseconds: 420);
  static const _holdDur = Duration(milliseconds: 150);

  /// `If(bounce,1.28,.28,.36)` / `If(bounce,1.34,.24,.38)`，bounce=50 → y2 1.28 / 1.34
  static const _moveCurve = Cubic(0.28, 1.28, 0.36, 1);
  static const _sizeCurve = Cubic(0.24, 1.34, 0.38, 1);
  static const _stretchCurve = Cubic(0.32, 0.72, 0.24, 1);
  static const _fadeCurve = Cubic(0.32, 0.72, 0.24, 1);

  static const _items = <_Item>[
    _Item('Home', _house),
    _Item('Search', _search),
    _Item('Files', _folder),
    _Item('Saved', _bookmark),
    _Item('You', _user),
  ];

  int _current = 0;
  _Phase _phase = _Phase.idle;

  /// 滑块的目标 / 起点 / 当前显示值
  _Slot _target = const _Slot(_pad, _slot);
  _Slot _from = const _Slot(_pad, _slot);

  Timer? _hold;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _stretchDur,
    value: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// 第 i 槽的几何：p = pad + i*(slot+gap)，s = slot
  static _Slot _geo(int i) => _Slot(_pad + i * (_slot + _gap), _slot);

  void _select(int i) {
    // 同一项重复点击：`if(t===c)return`，不动画
    if (i == _current) return;
    final prev = _geo(_current);
    final next = _geo(i);
    _current = i;

    // 并集区间，dilate=100 就是整段跨过去
    final o = prev.p < next.p ? prev.p : next.p;
    final end = (prev.p + prev.s) > (next.p + next.s) ? (prev.p + prev.s) : (next.p + next.s);

    _phase = _Phase.stretch;
    _from = _Slot(_shown.p, _shown.s);
    _target = _Slot(o, end - o);
    _c.duration = _stretchDur;
    _c.forward(from: 0);

    _hold?.cancel();
    _hold = Timer(_holdDur, () {
      if (!mounted) return;
      // 中途改目标：从当前显示值接着走，等价于 CSS transition 的重新取目标
      _phase = _Phase.settle;
      _from = _Slot(_shown.p, _shown.s);
      _target = next;
      _c.duration = _settleDur;
      _c.forward(from: 0).then((_) {
        if (mounted) setState(() => _phase = _Phase.idle);
      });
    });
  }

  /// 当前显示的滑块几何：曲线按相位分家，idle 直接就是目标
  _Slot get _shown {
    if (_phase == _Phase.idle) return _target;
    final t = _c.value;
    if (_phase == _Phase.stretch) {
      final e = _stretchCurve.transform(t);
      return _Slot(_from.p + (_target.p - _from.p) * e, _from.s + (_target.s - _from.s) * e);
    }
    return _Slot(
      _from.p + (_target.p - _from.p) * _moveCurve.transform(t),
      // 宽度不能为负：从 78 落回 38 时过冲曲线会往回探，探过头就成了负数，
      // Container 拿到负约束直接炸
      _from.s + (_target.s - _from.s) * _sizeCurve.transform(t),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ind = _shown;
    return IlStage(
      child: Container(
        width: _barW,
        height: _barH,
        decoration: BoxDecoration(
          color: IlColor.pane,
          borderRadius: BorderRadius.circular(_corner),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: _pad,
              child: Transform.translate(
                offset: Offset(ind.p, 0),
                child: Container(
                  width: ind.s,
                  height: _slot,
                  decoration: BoxDecoration(
                    // `--pane-thumb` = rgba(23,24,26,.07)
                    color: const Color(0x1217181A),
                    borderRadius: BorderRadius.circular(_corner),
                  ),
                ),
              ),
            ),
            Positioned(
              left: _pad,
              top: _pad,
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    _ItemButton(
                      item: _items[i],
                      active: i == _current,
                      onTap: () => _select(i),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@immutable
class _Item {
  const _Item(this.label, this.paths);

  final String label;
  final List<String> paths;
}

class _ItemButton extends StatefulWidget {
  const _ItemButton({required this.item, required this.active, required this.onTap});

  final _Item item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ItemButton> createState() => _ItemButtonState();
}

class _ItemButtonState extends State<_ItemButton> {
  bool _hover = false;

  /// .42 / hover .72 / 选中 1
  double get _opacity => widget.active ? 1 : (_hover ? 0.72 : 0.42);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: _Case02IconBarState._slot,
          height: _Case02IconBarState._slot,
          alignment: Alignment.center,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 260),
            curve: _Case02IconBarState._fadeCurve,
            opacity: _opacity,
            child: IlIcon(
              paths: widget.item.paths,
              size: 17,
              viewBox: 24,
              strokeWidth: 2,
              color: IlColor.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// 五个图标就是参考稿那五个描边图形，24 viewBox / 2px 描边，圆头圆角
const _house = [
  'M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8',
  'M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
];
const _search = [
  'M19 11A8 8 0 1 1 3 11A8 8 0 0 1 19 11Z',
  'M21 21L16.66 16.66',
];
const _folder = [
  'M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z',
];
const _bookmark = ['m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z'];
const _user = [
  'M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2',
  'M16 7A4 4 0 1 1 8 7A4 4 0 0 1 16 7Z',
];
