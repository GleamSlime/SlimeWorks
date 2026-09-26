import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 3. Notification badge — 徽标斜向滑入 + 弹性放大
///
/// 参考稿把动作拆成三条独立的时间线，各自有开/收两套时长：
/// 外框只做一次位移（260ms 顺出，收的时候不反向播），
/// 圆点同时走 scale/blur（500ms 弹）和 opacity（400ms 弹），
/// 收的时候三条一起退到 180ms 标准曲线。
/// 合成一条补间的话，圆点会先淡没再弹出来，观感整个是反的。
class Case03NotificationBadge extends StatefulWidget {
  const Case03NotificationBadge({super.key});

  @override
  State<Case03NotificationBadge> createState() => _Case03NotificationBadgeState();
}

class _Case03NotificationBadgeState extends State<Case03NotificationBadge>
    with TickerProviderStateMixin {
  static const _slideDur = Duration(milliseconds: 260);
  static const _popDur = Duration(milliseconds: 500);
  static const _fadeDur = Duration(milliseconds: 400);
  static const _closeDur = Duration(milliseconds: 180);

  /// 徽标离锚点的斜向偏移（`--badge-offset-x/y`）
  static const _offset = Offset(-8.2, 12.4);
  static const _blur = 4.0;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: _slideDur,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: _popDur,
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _fadeDur,
  );

  bool _open = false;

  @override
  void initState() {
    super.initState();
    _slide.addListener(_rebuild);
    _pop.addListener(_rebuild);
    _fade.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _slide.dispose();
    _pop.dispose();
    _fade.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      // 位移只在"出现"这一次播，所以每次都从头起
      _slide.forward(from: 0);
      _pop.animateTo(1, duration: _popDur, curve: LabEase.pop);
      _fade.animateTo(1, duration: _fadeDur, curve: LabEase.pop);
    } else {
      _pop.animateTo(0, duration: _closeDur, curve: LabEase.standard);
      _fade.animateTo(0, duration: _closeDur, curve: LabEase.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pop.value;
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const _BellTrigger(),
                Positioned(
                  top: -6,
                  right: -8,
                  child: Transform.translate(
                    offset: _offset * (1 - _slide.value),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Opacity(
                        opacity: _fade.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: scale,
                          child: LabBlur(
                            sigma: _blur * (1 - scale).clamp(0.0, 1.0),
                            child: const _BadgeDot(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }
}

/// 40 圆底铃铛：参考稿的 `.p1-bell`，三层极淡投影 + 16 描边图标
class _BellTrigger extends StatelessWidget {
  const _BellTrigger();

  static const _shadow = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 0, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 0, spreadRadius: 1),
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 2)),
  ];

  static const _bellPath =
      'M6.23612 14C6.70621 14.4149 7.3237 14.6667 8 14.6667C8.6763 14.6667 '
      '9.29379 14.4149 9.76388 14M12 5.33333C12 4.27247 11.5786 3.25505 '
      '10.8284 2.50491C10.0783 1.75476 9.06087 1.33333 8 1.33333C6.93913 '
      '1.33333 5.92172 1.75476 5.17157 2.50491C4.42143 3.25505 4 4.27247 4 '
      '5.33333C4 7.39346 3.48031 8.80397 2.89978 9.73694C2.41008 10.5239 '
      '2.16524 10.9174 2.17422 11.0272C2.18416 11.1487 2.20991 11.1951 2.30785 '
      '11.2677C2.39631 11.3333 2.79506 11.3333 3.59257 11.3333H12.4074C13.2049 '
      '11.3333 13.6037 11.3333 13.6921 11.2677C13.7901 11.1951 13.8158 11.1487 '
      '13.8258 11.0272C13.8348 10.9174 13.5899 10.5239 13.1002 '
      '9.73694C12.5197 8.80397 12 7.39346 12 5.33333Z';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: LabColor.card,
        shape: BoxShape.circle,
        boxShadow: _shadow,
      ),
      alignment: Alignment.center,
      child: LabIcon(paths: const [_bellPath], size: 16, color: LabColor.text),
    );
  }
}

/// 红点：20 圆 + 斜向红渐变 + 白色计数
class _BadgeDot extends StatelessWidget {
  const _BadgeDot();

  static const _gradient = LinearGradient(
    begin: Alignment(1, 0.7),
    end: Alignment(-1, -0.7),
    colors: [Color(0xFFEE2933), Color(0xFFEC0248)],
    stops: [0.139, 1.0],
  );

  static const _shadow = <BoxShadow>[
    BoxShadow(color: Color(0x2B000000), blurRadius: 1.4, offset: Offset(0, 0.3)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 2.7, offset: Offset(0, 0.7)),
    BoxShadow(color: Color(0x29000000), blurRadius: 0, offset: Offset(0, -0.3)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        gradient: _gradient,
        shape: BoxShape.circle,
        boxShadow: _shadow,
      ),
      alignment: Alignment.center,
      child: const Text(
        '1',
        style: TextStyle(
          fontFamily: LabFont.family,
          fontSize: 11.744,
          fontWeight: FontWeight.w500,
          height: 1,
          letterSpacing: -0.1174,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}
