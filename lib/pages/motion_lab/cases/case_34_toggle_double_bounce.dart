import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 34. Toggle — 滑块冲过头再荡回来，轨道底色瞬时换
///
/// 一条 0→1 的 linear 主时钟 + 一张关键帧表：`t` 落在 55% / 80% 两个停靠点上，
/// **每一段各自再套一次** `--p27-ease`——这条弹曲线本身带过冲，所以段内还会再顶出
/// 头，两段连起来就是"冲过头 → 荡回 → 落定"的双弹。把整条曲线一次套到底的话
/// 只剩一次弹，中途的回头点会被抹平。
/// 开和收是两张不同的表（收要从终点起跳、反向过冲到 -1px），不是同一条倒放。
/// 轨道底色 `--p27-track-dur: 0ms`：它不参与补间，翻开关那一刻就换。
const _dur = Duration(milliseconds: 350); // --p27-dur
const _bounce = Cubic(0.34, 1.35, 0.64, 1); // --p27-ease（比通用 pop 的 1.36 低一档）

const _travel = 14.66; // --p27-travel
const _ov1 = 1.0; // --toggle-ov1
const _ov2 = 0.0; // --toggle-ov2

/// 关键帧停靠点（0 / 55 / 80 / 100%）
const _stops = [0.0, 0.55, 0.80, 1.0];

/// t-toggle-on / t-toggle-off 的 translate 值
const _onX = [0.0, _travel + _ov1, _travel - _ov2, _travel];
const _offX = [_travel, -_ov1, _ov2, 0.0];

const _trackW = 44.0; // .p27-switch
const _trackH = 22.0;
const _thumbW = 22.0; // .p27-thumb
const _thumbH = 14.67;
const _thumbX = 3.67; // .p27-thumb left
const _thumbY = 3.67; // .p27-thumb top
const _pill = 122.0; // border-radius 原值：药丸靠盒子裁圆，不折成 11

/// `.p27-switch::before { inset: -16px }`：点击热区比轨道外扩 16
const _hitPad = 16.0;

/// rgba(0, 0, 0, .12) —— 关态轨道
const _trackOff = Color(0x1F000000);

/// rgba(0, 60, 255, .8) —— 开态轨道
const _trackOn = Color(0xCC003CFF);

const _thumbShadow = <BoxShadow>[
  BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 6,
    offset: Offset(0, 2),
  ), // rgba(0,0,0,.05)
  BoxShadow(
    color: Color(0x0F000000),
    blurRadius: 42,
    offset: Offset(0, 4),
  ), // rgba(0,0,0,.06)
];

class Case34ToggleDoubleBounce extends StatefulWidget {
  const Case34ToggleDoubleBounce({super.key});

  @override
  State<Case34ToggleDoubleBounce> createState() =>
      _Case34ToggleDoubleBounceState();
}

class _Case34ToggleDoubleBounceState extends State<Case34ToggleDoubleBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _dur,
    value: 0,
  );

  bool _on = false;

  /// 对应参考稿的 `.is-init`：没交互过就不能播 off 关键帧，
  /// 否则静止态会被那张表的起点顶到 _travel 上（挂载即抖一下）。
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _on = !_on;
      _played = true;
    });
    // 每次都是从头播一条新曲线，不是把上一条倒放
    _clock.forward(from: 0);
  }

  /// 分段插值：先定位落在哪一段，段内按该段两端值套一次弹曲线
  double _thumbOffset() {
    if (!_played) return _on ? _travel : 0;
    final values = _on ? _onX : _offX;
    final t = _clock.value;
    for (var i = 0; i < _stops.length - 1; i++) {
      final isLast = i == _stops.length - 2;
      if (t <= _stops[i + 1] || isLast) {
        final span = _stops[i + 1] - _stops[i];
        final p = ((t - _stops[i]) / span).clamp(0.0, 1.0);
        return values[i] + (values[i + 1] - values[i]) * _bounce.transform(p);
      }
    }
    return values.last;
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.all(_hitPad),
                  child: SizedBox(
                    width: _trackW,
                    height: _trackH,
                    child: DecoratedBox(
                      // 0ms 换色：直接吃状态，不补间
                      decoration: BoxDecoration(
                        color: _on ? _trackOn : _trackOff,
                        borderRadius: BorderRadius.circular(_pill),
                      ),
                      child: Stack(
                        // 轨道没有 overflow: hidden，滑块那层 42px 柔光是会溢出到轨道外的
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: _thumbX + _thumbOffset(),
                            top: _thumbY,
                            child: SizedBox(
                              width: _thumbW,
                              height: _thumbH,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(_pill),
                                  boxShadow: _thumbShadow,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
