import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 23. Tooltip open/close — 延时出现、跨触发器行进、秒退
///
/// 参考稿给气泡拆成三条独立时间线：出现走 80ms 延时 + 150ms ease-out
/// （scale 0.98→1，锚点在底边中心），离开 50ms 立即收，中间换目标时
/// 几何（x + 宽）单独用 160ms 顺出补间"滑行"过去。延时只挂在"出现"
/// 这一条规则上，所以一离开整组就秒隐，不会残留迟到的显示。
const _labels = ['Copy', 'Share', 'More'];
const _tips = ['Copy link', 'Share with team', 'More options'];

/// `--p17-in-dur / --p17-out-dur / --p17-delay / --p17-move-dur`
const _inDur = Duration(milliseconds: 150);
const _outDur = Duration(milliseconds: 50);
const _delay = Duration(milliseconds: 80);
const _moveDur = Duration(milliseconds: 160);

/// `--p17-scale-from`（scale-small）
const _scaleFrom = 0.98;

/// CSS 的 `ease-out` = cubic-bezier(0, 0, 0.58, 1)
const _easeOut = Cubic(0, 0, 0.58, 1);

/// 触发药丸：36 高、左右 12 内衬、档间 8（`.p17-trigger` / `.p17-group`）
const _pillH = 36.0;
const _pillPadX = 12.0;
const _pillGap = 8.0;

/// 气泡：上下 8、左右 10 内衬，行高 18，圆角 10，离触发器 8px
const _tipPadY = 8.0;
const _tipPadX = 10.0;
const _tipLineH = 18.0;
const _tipGap = 8.0;

/// `--p17-bg / --p17-fg`
const _tipBg = Color(0xFF222222);
const _tipFg = Color(0xFFF0F0F0);

class Case23TooltipOpenClose extends StatefulWidget {
  const Case23TooltipOpenClose({super.key});

  @override
  State<Case23TooltipOpenClose> createState() => _Case23TooltipOpenCloseState();
}

class _Case23TooltipOpenCloseState extends State<Case23TooltipOpenClose>
    with SingleTickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    value: 0,
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _appear, curve: _easeOut);

  /// 延时出现用世代号作废：离开 / 换目标都会让在途的延时失效
  int _gen = 0;

  /// 气泡当前目标几何（left / width）与文案
  double _tipX = 0;
  double _tipW = 0;
  String _tipText = _tips[0];

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  // 曲线统一挂在 CurvedAnimation 上，animateTo 只给时长，避免双重施加

  void _show(int i, double x, double w) {
    _gen++;
    final g = _gen;
    if (_appear.value > 0) {
      // 已经在显示：只补间几何，气泡从旧目标"滑"到新目标，不再延时
      setState(() {
        _tipX = x;
        _tipW = w;
        _tipText = _tips[i];
      });
      return;
    }
    setState(() {
      _tipX = x;
      _tipW = w;
      _tipText = _tips[i];
    });
    Future.delayed(_delay, () {
      if (!mounted || _gen != g) return;
      _appear.animateTo(1, duration: _inDur);
    });
  }

  void _hide() {
    // 退场不动文案也不重建：气泡停在最后一枚，50ms 内淡掉
    _gen++;
    _appear.animateTo(0, duration: _outDur);
  }

  @override
  Widget build(BuildContext context) {
    // 量的和画的同一套数：先量三颗药丸，再算每档中心对应的气泡 left
    final pillWs = [for (final l in _labels) _measure(context, l, LabText.title) + _pillPadX * 2];
    final tipWs = [for (final t in _tips) _measure(context, t, LabText.body) + _tipPadX * 2];
    final lefts = <double>[];
    var x = 0.0;
    for (final w in pillWs) {
      lefts.add(x);
      x += w + _pillGap;
    }
    final groupW = x - _pillGap;

    // 隐藏中改几何要瞬移（和参考稿的 transition:none 对齐），行进只在显示时播
    final moveDur = _appear.value > 0 ? _moveDur : Duration.zero;

    return LabStage(
      child: Center(
        child: MouseRegion(
          // 离开整组才收：档间 8px 的缝不该让气泡闪断后重走延时
          onExit: (_) => _hide(),
          child: SizedBox(
            width: groupW,
            height: _pillH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < _labels.length; i++) ...[
                      if (i > 0) const SizedBox(width: _pillGap),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => _show(
                          i,
                          lefts[i] + pillWs[i] / 2 - tipWs[i] / 2,
                          tipWs[i],
                        ),
                        child: LabAnimateButton(
                          label: _labels[i],
                          // 触屏没有 hover：点一下同样触发"出现"
                          onTap: () => _show(
                            i,
                            lefts[i] + pillWs[i] / 2 - tipWs[i] / 2,
                            tipWs[i],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                AnimatedPositioned(
                  duration: moveDur,
                  curve: LabEase.smoothOut,
                  left: _tipX,
                  width: _tipW,
                  // bottom: calc(100% + 8px)
                  bottom: _pillH + _tipGap,
                  child: _Tooltip(
                    animation: _anim,
                    text: _tipText,
                    height: _tipLineH + _tipPadY * 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }
}

/// 气泡本体：opacity + scale 共用一条出现/退场进度，锚点在底边中心
class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.animation,
    required this.text,
    required this.height,
  });

  final Animation<double> animation;
  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        // `transform-origin: 50% 100%` → 底边中心
        alignment: Alignment.bottomCenter,
        scale: Tween<double>(begin: _scaleFrom, end: 1.0).animate(animation),
        child: Container(
          height: height,
          // CSS overflow:hidden：行进中宽度补间，文字不外泄
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.symmetric(horizontal: _tipPadX),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _tipBg,
            borderRadius: BorderRadius.all(Radius.circular(10)),
            boxShadow: LabShadow.material,
          ),
          child: Text(
            text,
            maxLines: 1,
            style: LabText.body.copyWith(
              height: _tipLineH / 13,
              color: _tipFg,
            ),
          ),
        ),
      ),
    );
  }
}
