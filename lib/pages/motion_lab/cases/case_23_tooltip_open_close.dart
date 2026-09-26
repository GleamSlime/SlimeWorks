import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 23. Tooltip open/close — 延时出现、跨触发器行进、秒退
///
/// 参考稿给气泡拆成三条独立时间线：出现走 80ms 延时 + 150ms ease-out
/// （scale 0.98→1，锚点在底边中心），离开 50ms 立即收，换目标时落点单独
/// 用 160ms 顺出补间"滑行"过去。延时只挂在"出现"这一条规则上，所以一离开
/// 整组就秒隐，不会残留迟到的显示。
/// 宽度**不预量、不补间**：槽宽给 0、气泡用 OverflowBox 居中，多宽由文案自己
/// 撑。预量一份宽度再补间过去，量的口径和渲的口径一旦对不上（字体兜底、系统
/// 文字缩放），多出来的那截就成了文案右边的空白。
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

  /// 气泡当前落点（left，气泡自身的中心对齐到触发器中心）与文案
  double _tipX = 0;
  String _tipText = _tips[0];

  /// 鼠标指针是否在这组药丸上：桌面上点击等同 hover，
  /// 只有触屏（指针从不"进来"）才让点击承担"按住/抬开"两种语义
  bool _pointerInGroup = false;

  /// 指尖当前按住的是哪一颗，-1 = 没有
  int _pinned = -1;

  @override
  void dispose() {
    _appear.dispose();
    super.dispose();
  }

  // 曲线统一挂在 CurvedAnimation 上，animateTo 只给时长，避免双重施加

  void _show(int i, double x) {
    _gen++;
    final g = _gen;
    if (_appear.value > 0) {
      // 已经在显示：只补间落点，气泡从旧目标"滑"到新目标，不再延时
      setState(() {
        _tipX = x;
        _tipText = _tips[i];
      });
      return;
    }
    setState(() {
      _tipX = x;
      _tipText = _tips[i];
    });
    Future.delayed(_delay, () {
      if (!mounted || _gen != g) return;
      _appear.animateTo(1, duration: _inDur);
    });
  }

  void _hide() {
    // 退场不动文案也不重建：气泡停在最后一枚，50ms 内淡掉
    _pinned = -1;
    _gen++;
    _appear.animateTo(0, duration: _outDur);
  }

  @override
  Widget build(BuildContext context) {
    // 量的和画的同一套数：三颗药丸的宽 + 8 的档距，决定每档中心落在哪
    final pillWs = [for (final l in _labels) _measure(context, l, LabText.title) + _pillPadX * 2];
    final centers = <double>[];
    var x = 0.0;
    for (final w in pillWs) {
      centers.add(x + w / 2);
      x += w + _pillGap;
    }

    // 隐藏中改落点要瞬移（和参考稿的 transition:none 对齐），滑行只在显示时播
    final moveDur = _appear.value > 0 ? _moveDur : Duration.zero;

    return LabStage(
      child: Center(
        child: MouseRegion(
          onEnter: (_) => _pointerInGroup = true,
          // 离开整组才收：档间 8px 的缝不该让气泡闪断后重走延时
          onExit: (_) {
            _pointerInGroup = false;
            _hide();
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _labels.length; i++) ...[
                    if (i > 0) const SizedBox(width: _pillGap),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => _show(i, centers[i]),
                      child: LabAnimateButton(
                        label: _labels[i],
                        // 触屏没有 hover：点一下触发"出现"，再点同一颗抬开
                        onTap: () {
                          if (_pointerInGroup) return _show(i, centers[i]);
                          if (_pinned == i) return _hide();
                          _pinned = i;
                          _show(i, centers[i]);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              AnimatedPositioned(
                duration: moveDur,
                curve: LabEase.smoothOut,
                left: _tipX,
                // 槽宽 0 + OverflowBox 居中：气泡多宽都由文案自己撑，
                // 落点始终是那枚药丸的中心
                width: 0,
                // 高必须给死：Stack 的 loose 约束下 OverflowBox 会去要
                // "允许范围内最大"，宽度有上限、高度没有，就成了无限高
                height: _tipLineH + _tipPadY * 2,
                // bottom: calc(100% + 8px)
                bottom: _pillH + _tipGap,
                child: OverflowBox(
                  alignment: Alignment.center,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: _Tooltip(
                    animation: _anim,
                    text: _tipText,
                    height: _tipLineH + _tipPadY * 2,
                  ),
                ),
              ),
            ],
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
