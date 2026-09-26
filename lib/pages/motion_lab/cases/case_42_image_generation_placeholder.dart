import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 42. Image generation placeholder — 一片噪点先醒，再把整张图接出来
///
/// 噪点是一个个 1.5px 的圆点（`--pv6s`），静止时按各自的 `--v` 停在半隐的档位上
/// （`opacity: calc(--pv6p * var(--v))`、`scale: calc(--pv6a + (1 - --pv6a) * var(--v))`，
/// 而 `--pv6a` 是 0，所以静止点既是"淡"的也是"小"的）。
/// 按 Play 之后每点跑 `pv6e`：0%/100% 完全透明+缩到 0，50% 满亮满大，
/// 一轮 1400ms（`--pv6h`）乘以每点自己的倍率 `--k`、再错开 `--delay`，
/// 于是这片噪声不是齐刷地闪，而是逐点醒来。
/// 醒满一轮就换内容：两层同一条 650ms / 顺出（`--pv68/--pv67`）交叉——
/// 点层淡出并糊到 3px（`--pv66`），图从糊 3px 收到 0 并淡入。
/// 点阵的落位/倍率/延迟由固定种子生成，出图每次同一副样子。
const _box = 142.0; // `.pv6n`
const _boxRadius = 12.0;
const _boxBg = Color(0x0A000000); // rgba(0,0,0,.04)

const _dotSize = 1.5; // `--pv6s`
const _dotColor = Color(0x47000000); // `--pv69` 浅色盘取值 rgba(0,0,0,.28)
const _periodMs = 1400.0; // `--pv6h`
const _peak = 1.0; // `--pv6p`
const _minScale = 0.0; // `--pv6a`

const _wakeMs = 1400.0; // 醒满一轮再揭示（顺序由脚本定，这里取一个整周期）
const _revealMs = 650.0; // `--pv68`
const _blurPx = 3.0; // `--pv66`
const _totalMs = _wakeMs + _revealMs;

const _cells = 20; // 点阵按 20×20 铺在 142 见方里，格距 7.1
const _jitter = 1.6;
const _maxDelayMs = 900.0;

class Case42ImageGenerationPlaceholder extends StatefulWidget {
  const Case42ImageGenerationPlaceholder({super.key});

  @override
  State<Case42ImageGenerationPlaceholder> createState() =>
      _Case42ImageGenerationPlaceholderState();
}

class _Case42ImageGenerationPlaceholderState extends State<Case42ImageGenerationPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(microseconds: (_totalMs * 1000).round()),
  );

  /// 没按过 Play 之前只有静止噪点，一点都不会闪
  bool _started = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _play() {
    _started = true;
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LabStage(
      child: Stack(
        children: [
          Center(
            child: SizedBox(
              width: _box,
              height: _box,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_boxRadius),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: _boxBg),
                  child: ListenableBuilder(
                    listenable: _c,
                    builder: (context, _) => CustomPaint(
                      size: const Size(_box, _box),
                      painter: _GenPainter(elapsed: _c.value * _totalMs, pulsing: _started),
                    ),
                  ),
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Play', onTap: _play)],
          ),
        ],
      ),
    );
  }
}

/// 一个噪点：位置 + 周期倍率 + 起步延迟 + 静止档位
class _Dot {
  const _Dot(this.at, this.k, this.delay, this.v);

  final Offset at;
  final double k;
  final double delay;
  final double v;
}

final List<_Dot> _dots = () {
  final r = math.Random(20260942);
  final step = _box / _cells;
  final out = <_Dot>[];
  for (var y = 0; y < _cells; y++) {
    for (var x = 0; x < _cells; x++) {
      out.add(
        _Dot(
          Offset(
            (x + 0.5) * step + (r.nextDouble() - 0.5) * _jitter * 2,
            (y + 0.5) * step + (r.nextDouble() - 0.5) * _jitter * 2,
          ),
          0.7 + r.nextDouble() * 1.0,
          r.nextDouble() * _maxDelayMs,
          0.35 + r.nextDouble() * 0.65,
        ),
      );
    }
  }
  return out;
}();

/// 两层：底下那层是噪点，上面那层是图，交叉只走时长和糊度
class _GenPainter extends CustomPainter {
  const _GenPainter({required this.elapsed, required this.pulsing});

  final double elapsed;
  final bool pulsing;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = LabEase.smoothOut.transform(((elapsed - _wakeMs) / _revealMs).clamp(0.0, 1.0));

    // 噪点层：整层的 alpha/filter 一次给，逐点只管自己那一档
    if (r < 1) {
      canvas.saveLayer(
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, 1 - r)
          ..imageFilter = _blur(r * _blurPx),
      );
      _noise(canvas, size);
      canvas.restore();
    }
    if (r > 0) {
      canvas.saveLayer(
        rect,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, r)
          ..imageFilter = _blur((1 - r) * _blurPx),
      );
      paintPhoto(canvas, rect);
      canvas.restore();
    }
  }

  ui.ImageFilter? _blur(double sigma) => sigma <= 0.05
      ? null
      : ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal);

  void _noise(Canvas canvas, Size size) {
    final paint = Paint();
    for (final d in _dots) {
      final a = _alphaOf(d);
      if (a <= 0) continue;
      // --pv6a 是 0，所以 scale 和 opacity 同一条包络，缩到 0 就什么都看不见了
      final s = _minScale + (1 - _minScale) * a;
      // 透明度是"元素 opacity × 底色 rgba(0,0,0,.28)"，别把 .28 顶掉
      paint.color = Color.fromRGBO(0, 0, 0, _dotColor.a * a * _peak);
      canvas.drawCircle(d.at, _dotSize / 2 * s.clamp(0.0, 1.0), paint);
    }
  }

  /// 静止 = 该点的 `--v`；跑起来才换成 `pv6e` 那条 0→1→0（交叉段也照跑）
  double _alphaOf(_Dot d) {
    if (!pulsing || elapsed <= d.delay) return d.v;
    final t = (elapsed - d.delay) / (_periodMs * d.k);
    final p = t - t.floor();
    // 两个半程各自 ease-in-out（animation-timing-function 是逐段生效的）
    return p < 0.5 ? LabEase.inOut.transform(p * 2) : 1 - LabEase.inOut.transform((p - 0.5) * 2);
  }

  @override
  bool shouldRepaint(_GenPainter old) => old.elapsed != elapsed || old.pulsing != pulsing;
}

/// 生成的那张"图"：不允许用外部位图，所以照旧本地画——
/// 天空渐变 + 一轮低阳 + 两道山形 + 前景水面，比例全部归一化
const _sky = [Color(0xFF9FB8D8), Color(0xFFE9D9C4)];
const _sunColor = Color(0xFFFFF1DA);
const _ridgeFar = Color(0xFF7D8A99);
const _ridgeNear = Color(0xFF5C6773);
const _waterColor = Color(0xFF46505B);

void paintPhoto(Canvas canvas, Rect r) {
  final paint = Paint()..shader = labLinearGradient(180, _sky).createShader(r);
  canvas.drawRect(r, paint);
  paint.shader = null;

  paint.color = _sunColor;
  canvas.drawCircle(Offset(r.left + r.width * 0.72, r.top + r.height * 0.3), r.width * 0.07, paint);

  paint.color = _ridgeFar;
  canvas.drawPath(_ridge(r, 0.28, 0.44), paint);
  paint.color = _ridgeNear;
  canvas.drawPath(_ridge(r, 0.7, 0.56), paint);

  paint.color = _waterColor;
  canvas.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.8, r.width, r.height * 0.2), paint);
}

/// 一个山头：顶点在 (cx, peak)，两侧斜到画面底
Path _ridge(Rect r, double cx, double peak) {
  final w = r.width;
  final h = r.height;
  return Path()
    ..moveTo(r.left + w * (cx - 0.44), r.top + h)
    ..lineTo(r.left + w * cx, r.top + h * peak)
    ..lineTo(r.left + w * (cx + 0.44), r.top + h)
    ..close();
}
