import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 10. Page side-by-side — 前后两页错位 8px 交棒
///
/// 两页都是铺满容器的绝对层，非选中那页停在 `translateX(±8px)` + blur 3 + 透明 0。
/// 换页时两层的位移/模糊/淡入**共用 250ms 同一根曲线**（`--p8-slide-dur` 与
/// `--p8-fade-dur` 都是 `var(--duration-fast)`，`--p8-stagger: 0ms`），
/// 所以进来那页往左走 8、出去那页往右退 8，读起来像一张纸被推过去。
/// 返回键是另一层：它只跟 opacity，不参与位移和模糊，单独一条 250ms。
/// 这一格在参考稿里没有 `btn-animate`，触发点是列表行和返回键本身。
const _dur = Duration(milliseconds: 250); // `--p8-slide-dur` / `--p8-fade-dur`

/// `--p8-distance: var(--distance-base)`，页 1 从左边来、页 2 从右边来
const _distance = 8.0;

/// `--p8-blur: var(--blur-medium)`
const _blur = 3.0;

/// `.p8-modal` 离舞台左上角各 18
const _modalX = 18.0;
const _modalY = 18.0;
const _modalW = 260.0;
const _modalH = 267.0;

/// 悬停换底色：`transition: background-color 120ms ease`
const _hoverDur = Duration(milliseconds: 120);
const _cssEase = Cubic(0.25, 0.1, 0.25, 1);

const _rowHover = Color(0x05020202); // rgba(2, 2, 2, .02)
const _nameColor = Color(0xFF17171C);
const _symColor = Color(0xFF5E6773);
const _iconBg = Color(0xFFF8F8F8);
const _chipBg = Color(0x80F4F4F4); // rgba(244, 244, 244, .5)
const _chipHoverBg = Color(0xE6F4F4F4); // rgba(244, 244, 244, .9)
const _pillBg = Color(0xFFF7F7F8);

const _rowStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 22 / 14,
);

const _amountStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 48,
  fontWeight: FontWeight.w500,
  height: 1,
  color: LabColor.text,
);

const _pillStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 14,
  fontWeight: FontWeight.w500,
  height: 16 / 14,
  color: _symColor,
);

/// `.amount-available`：14/18
const _availStyle = TextStyle(
  fontFamily: LabFont.family,
  fontFamilyFallback: LabFont.fallback,
  fontSize: 14,
  fontWeight: FontWeight.w400,
  height: 18 / 14,
  color: LabColor.text,
);

/// `.back-btn` 的那枚 chevron
const _chevronPath = 'M10 4L6 8L10 12';

/// 一行币种：名字 / 代号 / 占位图形的描边路径
class _Token {
  const _Token(this.name, this.sym, this.marks);

  final String name;
  final String sym;
  final List<String> marks;
}

/// 原稿的币种图标是位图资产，这里用同尺寸的几何占位图形顶上
const _tokens = <_Token>[
  _Token('Ethereum', 'ETH', [
    'M8 1.4L12.6 8.9L8 11.8L3.4 8.9L8 1.4Z',
    'M3.4 10.1L8 14.8L12.6 10.1L8 12.7L3.4 10.1Z',
  ]),
  _Token('Avalanche', 'AVAX', [
    'M8 2.2L14.2 13H1.8L8 2.2Z',
  ]),
  _Token('BNB', 'BNB', [
    'M8 1.8L14.2 8L8 14.2L1.8 8Z',
  ]),
];

class Case10PageSideBySide extends StatefulWidget {
  const Case10PageSideBySide({super.key});

  @override
  State<Case10PageSideBySide> createState() => _Case10PageSideBySideState();
}

class _Case10PageSideBySideState extends State<Case10PageSideBySide> {
  /// `data-page`，初始是 1
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Positioned(
            left: _modalX,
            top: _modalY,
            child: Container(
              width: _modalW,
              height: _modalH,
              decoration: const BoxDecoration(
                color: LabColor.card,
                borderRadius: BorderRadius.all(Radius.circular(12)),
                boxShadow: LabShadow.material,
              ),
              // overflow: hidden：面板本身 267 高，舞台只露出上面 242，底边被切掉
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: SizedBox(
                  width: _modalW,
                  height: _modalH,
                  child: Stack(
                    children: [
                      // `.page-title` 不在 .page 里，换页时它不动
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 25,
                        child: Center(child: _Sk(95, 14, 4)),
                      ),
                      _slide(
                        fromLeft: true,
                        active: _page == 1,
                        child: _TokenList(onPick: () => setState(() => _page = 2)),
                      ),
                      _slide(
                        fromLeft: false,
                        active: _page == 2,
                        child: const _AmountScreen(),
                      ),
                      _backButton(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一层 .page：位移/模糊/淡入共用一条补间
  Widget _slide({
    required bool fromLeft,
    required bool active,
    required Widget child,
  }) {
    final fromX = fromLeft ? -_distance : _distance;
    return Positioned.fill(
      // pointer-events 跟着 data-page 立刻翻转，不等补间跑完
      child: IgnorePointer(
        ignoring: !active,
        child: LabTween(
          target: active ? 1 : 0,
          duration: _dur,
          curve: LabEase.smoothOut,
          builder: (context, t) => Transform.translate(
            offset: Offset(fromX * (1 - t), 0),
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: LabBlur(sigma: _blur * (1 - t), child: child),
            ),
          ),
        ),
      ),
    );
  }

  /// 返回键：只跟着淡入淡出，画在最上层（z-index: 2）
  Widget _backButton() {
    return Positioned(
      left: 16,
      top: 16,
      child: IgnorePointer(
        ignoring: _page != 2,
        child: LabTween(
          target: _page == 2 ? 1 : 0,
          duration: _dur,
          curve: LabEase.smoothOut,
          builder: (context, t) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: _ChipButton(
              // svg 自带 translateX(-1px)
              iconOffset: const Offset(-1, 0),
              onTap: () => setState(() => _page = 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// 页 1：币种列表（`.tokens`，left 8 / top 60.5 / 宽 244）
class _TokenList extends StatelessWidget {
  const _TokenList({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    // 整页是一层铺满容器的绝对层，所以内容用 padding 落位而不是再套一层定位
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 60.5),
      child: SizedBox(
        width: 244,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final token in _tokens) _TokenRow(token: token, onTap: onPick),
          ],
        ),
      ),
    );
  }
}

/// 一行币种：32 圆图标 + 名字/代号，悬停有极淡底色
class _TokenRow extends StatefulWidget {
  const _TokenRow({required this.token, required this.onTap});

  final _Token token;
  final VoidCallback onTap;

  @override
  State<_TokenRow> createState() => _TokenRowState();
}

class _TokenRowState extends State<_TokenRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _hoverDur,
          curve: _cssEase,
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          decoration: BoxDecoration(
            color: _hovered ? _rowHover : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Row(
            children: [
              _TokenIcon(marks: widget.token.marks),
              const SizedBox(width: 12),
              // name 压住 sym 4px：原稿是 margin-bottom: -4
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.token.name, style: _rowStyle.copyWith(color: _nameColor)),
                  Transform.translate(
                    offset: const Offset(0, -4),
                    child: Text(widget.token.sym, style: _rowStyle.copyWith(color: _symColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.token-icon`：32 圆 + 1px 内描边 + 一层极淡投影
class _TokenIcon extends StatelessWidget {
  const _TokenIcon({required this.marks});

  final List<String> marks;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: _iconBg,
        shape: BoxShape.circle,
        border: Border.all(color: LabColor.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      // 原稿这里是一张 50% 透明度的位图，换成同尺寸的实心占位图形
      child: LabIcon(paths: marks, size: 16, strokeWidth: 1, filled: true, color: LabColor.textFaint),
    );
  }
}

/// 页 2：金额输入屏（`.amount-screen`，left/right 8 / top 78 / 列间距 16）
class _AmountScreen extends StatelessWidget {
  const _AmountScreen();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 78),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Text('\$10', textAlign: TextAlign.center, style: _amountStyle),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Pill('25%'),
              SizedBox(width: 12),
              _Pill('50%'),
              SizedBox(width: 12),
              _Pill('Max'),
            ],
          ),
          SizedBox(height: 16),
          Text(
            '\$66.11 available',
            textAlign: TextAlign.center,
            style: _availStyle,
          ),
        ],
      ),
    );
  }
}

/// `.pill`：36 高药丸，只展示不可点
class _Pill extends StatelessWidget {
  const _Pill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _pillBg,
        borderRadius: BorderRadius.all(Radius.circular(27)),
      ),
      alignment: Alignment.center,
      child: Text(label, style: _pillStyle),
    );
  }
}

/// `.chip-btn`：32 圆返回键
class _ChipButton extends StatefulWidget {
  const _ChipButton({required this.onTap, required this.iconOffset});

  final VoidCallback onTap;
  final Offset iconOffset;

  @override
  State<_ChipButton> createState() => _ChipButtonState();
}

class _ChipButtonState extends State<_ChipButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _hoverDur,
          curve: _cssEase,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered ? _chipHoverBg : _chipBg,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Transform.translate(
            offset: widget.iconOffset,
            child: const LabIcon(paths: [_chevronPath], size: 16, strokeWidth: 1.5),
          ),
        ),
      ),
    );
  }
}

/// 通用骨架块
class _Sk extends StatelessWidget {
  const _Sk(this.width, this.height, this.radius);

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: LabColor.skeleton,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
