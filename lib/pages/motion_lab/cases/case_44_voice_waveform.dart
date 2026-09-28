import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 44. Voice waveform — 发送语音时随振幅起伏的多层声波
///
/// 参考稿那一束不是"一条线"，而是**同一条声波的多重回声**：贴着中轴一根不粗的
/// 亮芯，外面再套四层越远越淡、越矮的包络。五层吃的是**同一张谐波表**，厚度全靠
/// 逐层横向错开叠出来 —— 一旦给内层加高频细纹就变梳齿。上下两路再取两个错相，
/// 于是波腹左右不完全对齐。
///
/// 形状账（1534×618 的 2x 截图逐列量出来的逻辑值）：
/// -  波形盒 628 宽；上包络最高 53.5、下包络最高 69 → **上下不对称**（下面多出约
///    29%）。画布 256 宽 → 折算 [_halfUp] 22 / [_halfDn] 28
/// -  最外层包络沿中轴**约 10 个腹**（实测 6 个峰落在 2x px 306/432/561/687/810/933，
///    间距 125 = 62 逻辑 px = 整幅的 1/10.05），腹高 68/75/99/91/107/86 长短不齐，
///    两腹之间只凹到三成多。所以频谱每层只留 f≈10 附近一档极窄的载波（见 [_Band._wts]），
///    五层共用同一张谐波表、各自偏一点中心再横向错开 [_Layer.shift]，才有那种互相穿插的
///    回声厚度
/// -  上下两路取同一张表的两个错相，于是波腹左右不对齐（[_Layer.skew] 以整幅为
///    单位，别再按周期读）
/// -  束不从盒左沿就起：实测上沿到 u≈0.13 才离开中轴，见 [_swell0]
/// -  两个窗分开用：振幅吃 [_taper]，芯的底厚吃 [_body]。合成一个窗的话亮芯会在两端
///    被一起削没 —— 参考稿实测右端芯还有 5 的跨度，而振幅早就归零了
/// -  束边是带雾的，不是硬描边：五层作为一个整体过一次 [_feather] 高斯，亮芯留在
///    这层之外保持锐利
/// -  横向渐变：青色一直占前 42%，之后蓝→紫→品红，尾端回粉（停点见 [_ramp]）
/// -  中轴那根白线是**加色**的：同一档紫色芯上叠出浅粉、同一档青色芯上叠出亮青，
///    只有 `BlendMode.screen` 同时给得出这两种结果
/// -  说明文字 `#989898`、六字宽 158 逻辑 px
///
/// 振幅来源是**合成包络**：谐波表由 `math.Random(固定 seed)` 定相，主时钟只推进下面那两档。
///
/// 动线只有一条：**波从中轴生出来，往两侧走，走到端点消失，一路重复**。
///
/// 载波的坐标是 `|u − 0.5|`（见 [_arg]）—— 中轴是原点、两翼对称地往外长，再减去
/// `speed·t` 就是"整幅图案往外推"。方向感靠的是**单调**：`speed` 是每圈走的**整数个
/// 周期**，所以接缝上两帧严丝合缝（既不用倒着退回去，也不会跳一帧）；而腹从中间出来后
/// 一路被 [_taper] 那扇窗压着往下走，到端点正好归零 —— "扩散直至消失"是窗给的，不是
/// 另加一档淡出。
///
/// 之前两版错在都带一档**会回头**的东西：胀缩是 `sin²`（推出去还要收回来），音量波是
/// 高斯包（长起来还要落下去）—— 眼睛锁定的那一排腹于是会中途换成前一排，读出来就是
/// 倒播。改成单调外推之后没有可锁定的第二选了。
///
/// 起幅（按下、以及循环里"开始说"那一段）另有一档横向闸门 [_spread]：束的横向范围按
/// `g` 从中间往两边开，方向与外推一致。`g = 1` 时它恒等于 1，量到的形状一个字都没改。
///
/// 两档都只吃主时钟，不读麦克风、不读 `DateTime.now()`，任何一帧都可复现。
///
/// 五层**不许是等差的一叠副本**：每层的载波中心、带宽、横向错相各抖一档
/// （[_Layer.dc] / [sig] / [shift]），两翼还故意不做镜像（[_waveLean]）—— 于是腹与腹
/// 互相穿插的位置一路在变。抖的幅度仍锁在"极窄带"里 —— 每层只在 f≈10 附近留三档，
/// 一旦给内层加高频细纹就变梳齿。
///
/// 触屏：整块舞台就是"按住说话"的面，按下即 [LabTouchLock.acquire]。这一路是裸
/// `Listener`（要 CSS `setPointerCapture` 那种"按住就是我的"语义，且上滑取消要连续
/// 跟手），不进竞技场 —— 不锁的话手指一位移就被页面外层那颗滚动赢走，"上滑取消"
/// 变成"滚整页"。见 `DESIGN.md` §12.9。

/// 舞台版式：波形盒左 20、宽 256，中轴 y=112；说明文字在中轴下方 61
const _waveX = 20.0;
const _waveW = 256.0;
const _axisY = 112.0;

/// 上/下包络的最大半高（= 参考稿的 53.5 / 69 × 256/628）
const _halfUp = 22.0;
const _halfDn = 28.0;

/// 说明文字与中轴的间距（参考稿 150 逻辑 px × 0.408）
const _captionGap = 61.0;

/// 上滑多少算进"取消"档
const _armTravel = 28.0;

/// 载波每圈往外走几个**完整周期**
///
/// 必须是整数：一圈的位移正好是周期的整倍数，接缝上两帧重合，既不用倒退也不会跳。
/// 1 = 一腹从中轴走到端点 2100ms（波形盒 256px、一腹 26px → 折算过去约 61px/s，
/// 任一固定点上约 420ms 过一个腹，跟"说话"的节奏对得上）
const _waveSpeed = 1;

/// 镜像的破缺量：给有符号的那一段加这点偏置，两翼的腹距与波速各差约 6%
///
/// 纯镜像太"规律"（左右严丝合缝地一起动，一眼就是复制粘贴），偏开之后两翼互相错着走
const _waveLean = 0.06;

/// 参考稿的横向渐变停点（t 相对波形盒左沿）
const _ramp = <Color>[
  Color(0xFF00FBFF),
  Color(0xFF00FBFF),
  Color(0xFF23BEFF),
  Color(0xFF6E93FF),
  Color(0xFFB15DFF),
  Color(0xFFE21CFF),
  Color(0xFFFB27F8),
  Color(0xFFFA6CF9),
];
const _rampStops = <double>[0.0, 0.42, 0.50, 0.60, 0.70, 0.80, 0.88, 1.0];

/// 取消档：整条渐变往灰里退，只留一点品红认得出是谁
const _cancelMix = Color(0xFF9A9AA4);

/// 束边的羽化量（画布 px）。参考稿的束边不是硬描边，逐层之间有一层看得见的雾；
/// 折算到 256 宽的画布上约一个多 px 的高斯
const _feather = 1.3;

/// 分层：外层→内层。[k] 半高系数，[floor] 常数底厚（芯不随振幅消失、层与层之间也不
/// 互相捏到零），[skew] 下沿相对上沿的错相，[shift] 该层整体在横向上的错相
/// （两个错相都以整幅为单位，别再按周期读）
///
/// 后两个是**去规律**档：[dc] 该层载波中心相对 f=10 的偏移、[sig] 该层的带宽。五层若只
/// 错开 [shift]，那一叠就是等差副本，腹与腹的穿插位置永远不变；载波中心各偏一点，
/// 腹距就不一样，穿插才一路在动。
class _Layer {
  const _Layer({
    required this.lo,
    required this.hi,
    required this.k,
    required this.alpha,
    required this.floor,
    required this.skew,
    required this.shift,
    required this.dc,
    required this.sig,
  });

  final int lo;
  final int hi;
  final double k;
  final double alpha;
  final double floor;
  final double skew;
  final double shift;
  final double dc;
  final double sig;
}

const _layers = <_Layer>[
  _Layer(lo: 8, hi: 13, k: 1.00, alpha: 0.28, floor: 0.16, skew: 0.022, shift: 0.000, dc: 0.00, sig: 0.40),
  _Layer(lo: 8, hi: 13, k: 0.74, alpha: 0.41, floor: 0.15, skew: 0.026, shift: 0.023, dc: 0.34, sig: 0.36),
  _Layer(lo: 8, hi: 13, k: 0.57, alpha: 0.51, floor: 0.14, skew: 0.019, shift: 0.041, dc: -0.38, sig: 0.45),
  _Layer(lo: 8, hi: 13, k: 0.37, alpha: 0.67, floor: 0.13, skew: 0.024, shift: 0.057, dc: 0.17, sig: 0.38),
  _Layer(lo: 8, hi: 13, k: 0.24, alpha: 0.92, floor: 0.12, skew: 0.021, shift: 0.083, dc: -0.21, sig: 0.42),
];

/// 谐波表：固定 seed 定幅度与相位，`f` 取整数保证周期闭合、滚动无缝。
/// 每档频段单独归一到 [0,1]，层与层之间才比得出高低。
abstract final class _Band {
  static const _seed = 20260928;
  static const _top = 13;

  /// 每档的随机底幅：五层共用同一张表（"同一条声波的多重回声"就靠这个），
  /// 层与层的差别只落在 [_wts] 那一圈带通上
  static final List<double> _gain = () {
    final r = math.Random(_seed);
    return [0.0, for (var f = 1; f <= _top; f++) 0.55 + r.nextDouble()];
  }();

  static final List<double> _phase = () {
    final r = math.Random(_seed + 7);
    return [for (var f = 0; f <= _top; f++) r.nextDouble()];
  }();

  /// 第 i 层实际吃到的各频幅度 = 底幅 × 该层自己的带通（中心 `10 + dc`、宽 `sig`）。
  ///
  /// 带通原本五层共用同一档：只留 f=9/10/11 三档（参考稿最外层包络实测 6 个峰、间距
  /// 125 的 2x px = 62 逻辑 px = 整幅的 1/10.05），两档边带相差 1 正好让腹高在整幅里
  /// 起伏一个来回（腹高实测 68/75/99/91/107/86，最高与最低差一半）。现在逐层把中心偏
  /// ±0.4、宽偏 ±0.05 —— 那是把这一层的腹距整体挪个百分点，穿插位置才一路在变；
  /// 档再宽就糊成一片（沟填平、腹凸不出来），而**一旦给内层加高频细纹就变梳齿**
  static final List<List<double>> _wts = [
    for (final l in _layers)
      [
        0.0,
        for (var f = 1; f <= _top; f++)
          _gain[f] * math.exp(-((f - 10.0 - l.dc) * (f - 10.0 - l.dc)) / l.sig),
      ],
  ];

  /// 各频段的实际极值（密采一遍），用来归一；与 [_layers] 同序
  static final List<List<double>> _norm = [
    for (var i = 0; i < _layers.length; i++) _extent(i),
  ];

  static List<double> _extent(int i) {
    var mn = double.infinity, mx = -double.infinity;
    for (var j = 0; j < 2880; j++) {
      final v = _raw(i, j / 2880);
      if (v < mn) mn = v;
      if (v > mx) mx = v;
    }
    return [mn, mx];
  }

  static double _raw(int i, double u) {
    final l = _layers[i];
    final w = _wts[i];
    var s = 0.0;
    for (var f = l.lo; f <= l.hi; f++) {
      s += w[f] * math.sin(2 * math.pi * (f * u + _phase[f]));
    }
    return s;
  }

  /// 0..1 的包络读数：一条 S 形软饱和曲线，两端都**不硬截**。
  /// 硬截（clamp 到 1）会把腹顶削成平台、腹与腹之间变成方头齿轮；指数取 2.2 是让
  /// 腹顶圆、沟也圆，同时把最矮的腹抬到标称半高的四成 —— 参考稿实测谷/峰 0.38~0.44。
  /// 最后垫 0.24 的底，两腹之间不捏到零
  static double read(int i, double u) {
    final e = _norm[i];
    final span = e[1] - e[0];
    if (span <= 0) return 0.5;
    final m = (_raw(i, u) - e[0]) / span;
    final a = math.pow(m.clamp(0.0, 1.0), _peak).toDouble();
    final b = math.pow((1 - m).clamp(0.0, 1.0), _peak).toDouble();
    return _base + (1 - _base) * a / (a + b);
  }

  static const _base = 0.24;

  /// S 形的陡峭度
  static const _peak = 2.2;
}

/// 纺锤窗：参考稿的束不是从波形盒左沿就起，实测上沿到 u≈0.14 才离开中轴、右端
/// u≈0.99 收回去，所以窗整体右移
const _swell0 = 0.06;

double _swell(double u) =>
    math.sin(math.pi * ((u - _swell0) / (1.0 - _swell0)).clamp(0.0, 1.0));

/// 振幅窗：两端收到零。指数 1.1 是量出来的 —— 参考稿两端的腹并不塌成尖，u=0.25 处
/// 就还有最大半高的六成，所以窗比正弦还平
double _taper(double u) => math.pow(_swell(u), 1.1).toDouble();

/// 底厚窗：同样收到零，但胖得多，让亮芯在远离中段的位置也还有肉
double _body(double u) => math.pow(_swell(u), 0.35).toDouble();

/// 起幅的横向闸门：**从中轴往两侧开**，不是整条一起变高
///
/// [g] 是闸门开度（`open`，只涨不落）。闸门按"到中轴的距离"比宽，`g·1.35` 就是当前开到
/// 的半幅（单位：半幅 = 1），外面 0.35 是软边。`g = 1` 时 `(1.35 − q)/0.35 ≥ 1` 对整幅
/// 恒成立 —— 也就是说开满那一档闸门完全不存在，量到的纺锤形状一个字没改，改的只有进来的路。
double _spread(double u, double g) {
  final q = (u - 0.5).abs() * 2;
  final t = ((g * 1.35 - q) / 0.35).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 第 [i] 层在 [u] 处该读谐波表的哪一个横坐标：**从中轴生出来、往两侧走**
///
/// `|u − 0.5|` 把中轴钉成原点、两翼对称地往外长（整幅正好铺满一个周期 → 一翼 5 个腹），
/// 减 `speed·t` 让整幅图案一路往外推：某个腹从中轴出来，走到端点要 2100ms，而每圈走的
/// 位移是整数个周期，所以接缝上两帧重合 —— 没有"退回去"这一段，倒播无从发生。
///
/// `_waveLean` 给有符号的那一段加偏置：纯镜像会让左右严丝合缝地一起动，一眼是复制粘贴；
/// 偏开 6% 之后两翼的腹距与波速都不一样。[shift] 是该层的静态错相（下沿再叠 [skew]），
/// 两者都以整幅为单位
double _arg(int i, double u, double t, {required bool upper}) {
  final l = _layers[i];
  final s = u - 0.5;
  return s.abs() +
      s * _waveLean +
      l.shift +
      (upper ? 0 : l.skew) -
      t * _waveSpeed;
}

class Case44VoiceWaveform extends StatefulWidget {
  const Case44VoiceWaveform({super.key});

  @override
  State<Case44VoiceWaveform> createState() => _Case44VoiceWaveformState();
}

class _Case44VoiceWaveformState extends State<Case44VoiceWaveform>
    with TickerProviderStateMixin {
  /// 主时钟：一圈 = 一次"按住说完一句"，载波的外推相位与那两档包络都从它派生，
  /// 所以离屏按 16ms 推进就能逐帧复现，不需要真的有人按着
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..addListener(() => setState(() {}));

  /// 按住时把高度与横向闸门顶到满：松手收回，循环那两档自己走
  late final AnimationController _held = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(() => setState(() {}));

  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _armed = false;
  bool _locked = false;

  /// 循环里的**高度**包络：两头各留一段平的空档，中间是"正在说"
  static double _level(double t) {
    if (t < 0.06) return 0;
    if (t < 0.18) return LabEase.smoothOut.transform((t - 0.06) / 0.12);
    if (t < 0.80) return 1;
    if (t < 0.94) return 1 - Curves.easeIn.transform((t - 0.80) / 0.14);
    return 0;
  }

  /// 循环里的**横向**闸门：只涨不落
  ///
  /// 一句话收尾时束要消失，但"往中间收"是个反向动作，眼睛会把它读成倒播 —— 所以收那
  /// 一程只降高度，闸门一路停在 1。它落回 0 的那一瞬间高度也正好是 0（上面那档的
  /// t < 0.06 空档），画布上什么都没有，接缝看不出来。
  static double _attack(double t) =>
      t < 0.06 ? 0 : LabEase.smoothOut.transform(((t - 0.06) / 0.12).clamp(0.0, 1.0));

  void _lock() {
    if (_locked) return;
    _locked = true;
    LabTouchLock.acquire();
  }

  void _unlock() {
    if (!_locked) return;
    _locked = false;
    LabTouchLock.release();
  }

  void _down(PointerDownEvent e) {
    _pointer = e.pointer;
    _downAt = e.localPosition;
    // 锁必须在 down 这一下就给出：上滑取消要连续跟手，而页面那颗滚动的 slop 更短
    _lock();
    _held.forward();
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    if (_pointer != e.pointer) return;
    final armed = _downAt.dy - e.localPosition.dy >= _armTravel;
    if (armed != _armed) setState(() => _armed = armed);
  }

  void _release(PointerEvent e) {
    if (_pointer != e.pointer) return;
    _pointer = null;
    _armed = false;
    _unlock();
    _held.reverse();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    // 抬起事件没送到也要把锁交回去，否则整页滚不动
    _unlock();
    _c.dispose();
    _held.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = math.max(_level(_c.value), _held.value);
    // 闸门只涨不落（见 [_attack]）：束收回去那一段只降高度，不往中间挤
    final open = math.max(_attack(_c.value), _held.value);
    final armed = _armed ? 1.0 : 0.0;
    final caption = _armed
        ? '松开取消'
        : level <= 0.01
              ? '按住说话'
              : '上滑取消发送';
    return LabStage(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _release,
        onPointerCancel: _release,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _WavePainter(
                    phase: _c.value,
                    level: level,
                    open: open,
                    armed: armed,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: _axisY + _captionGap - 8,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  transitionBuilder: (child, t) => FadeTransition(
                    opacity: t,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.28),
                        end: Offset.zero,
                      ).animate(t),
                      child: child,
                    ),
                  ),
                  child: Text(
                    caption,
                    key: ValueKey(caption),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: LabFont.family,
                      fontFamilyFallback: LabFont.fallback,
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      height: 16 / 11,
                      color: Color(0xFF989898),
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.phase,
    required this.level,
    required this.open,
    required this.armed,
  });

  /// 主时钟（0..1 一圈 = 一次说话），载波的外推只吃它
  final double phase;

  /// 高度（起幅 + 按住顶满）
  final double level;

  /// 横向闸门：只涨不落（见 [_attack]）
  final double open;
  final double armed;

  /// 采样点数：256 px 画布上每 px 1.25 个点，一腹约 26 px → 每腹 32 个点，不留折角
  static const _steps = 320;

  List<Color> _rampAt(double alpha) => [
    for (final c in _ramp)
      Color.lerp(c, _cancelMix, armed * 0.82)!.withValues(alpha: alpha),
  ];

  LinearGradient _grad(double alpha) => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: _rampAt(alpha),
    stops: _rampStops,
  );

  /// 第 [i] 层在 [u] 处的上/下沿。横坐标过 [_arg]（从中轴往两侧外推的载波 + 该层的
  /// 静态错相，下沿再叠 [skew]）；振幅吃 [_taper]、底厚吃 [_body]，两个窗分开；
  /// 高度再乘 [g]（起幅）与 [_spread]（按下那一段往两边开的横向范围）
  double _edge(int i, double u, double g, {required bool upper}) {
    final v = _Band.read(i, _arg(i, u, phase, upper: upper));
    final l = _layers[i];
    final half = l.floor * _body(u) + (1 - l.floor) * v * _taper(u);
    return _axisY +
        (upper ? -_halfUp : _halfDn) *
            l.k *
            g *
            half *
            _spread(u, open);
  }

  /// 一层上下沿围成的透镜形
  Path _lens(int i, double g) {
    final p = Path();
    for (var j = 0; j <= _steps; j++) {
      final u = j / _steps;
      final x = u * _waveW + _waveX;
      final y = _edge(i, u, g, upper: true);
      j == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    for (var j = _steps; j >= 0; j--) {
      final u = j / _steps;
      p.lineTo(u * _waveW + _waveX, _edge(i, u, g, upper: false));
    }
    p.close();
    return p;
  }

  /// 亮芯不是描在轴上的等宽细线，而是**芯带中间那一条**：跟着芯带一起粗一起细，
  /// 高光只占芯带宽度的四成多
  Path _spine(double g) {
    final i = _layers.length - 1;
    final p = Path();
    for (var j = 0; j <= _steps; j++) {
      final u = j / _steps;
      final x = u * _waveW + _waveX;
      final up = _edge(i, u, g, upper: true);
      final dn = _edge(i, u, g, upper: false);
      final y = (up + dn) / 2 - (dn - up) * 0.22;
      j == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    for (var j = _steps; j >= 0; j--) {
      final u = j / _steps;
      final up = _edge(i, u, g, upper: true);
      final dn = _edge(i, u, g, upper: false);
      p.lineTo(u * _waveW + _waveX, (up + dn) / 2 + (dn - up) * 0.22);
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(_waveX, 0, _waveW, size.height);
    // 起幅：纺锤从一条线胀起来
    final g = Curves.easeOut.transform(level);
    // 五层包络作为一个整体过一次高斯：参考稿的束边是带雾的，裸 vector 描边太硬。
    // 亮芯留在这层之外，保持锐利
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ImageFilter.blur(
          sigmaX: _feather,
          sigmaY: _feather,
          tileMode: TileMode.decal,
        ),
    );
    for (var i = 0; i < _layers.length; i++) {
      canvas.drawPath(
        _lens(i, g),
        Paint()..shader = _grad(_layers[i].alpha).createShader(rect),
      );
    }
    canvas.restore();
    if (g <= 0.001) return;

    // 亮芯：加色的缎带。同一档紫芯上叠成浅粉、青芯上叠成亮青，只有 screen 同时给得出
    canvas.drawPath(
      _spine(g),
      Paint()
        ..blendMode = BlendMode.screen
        ..color = Colors.white.withValues(alpha: 0.22 * g),
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase ||
      old.level != level ||
      old.open != open ||
      old.armed != armed;
}
