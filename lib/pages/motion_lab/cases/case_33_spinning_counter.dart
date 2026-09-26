import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../lab_kit.dart';

/// 33. Spinning counter — 每位数字一条卷轴，转三圈后各自落定
///
/// 参考稿 `--p26-*`：单元格高 30、单圈 1400ms、曲线 cubic-bezier(0.16, 1, 0.3, 1)、
/// 逐列错峰 90ms、目标值 100。每位剪出 30px 窗口、里面塞一条 0-9×(spins+1) 的数字带，
/// 整带向上平移 (spins×10+落点)×30px——所以是"转过去"而不是"跳过去"。
/// 拖影是**纵向**高斯模糊（参考稿特意注明横向 CSS blur() 会糊错方向），
/// 随各列进度线性衰到 0；窗口上下 22% 起用渐变遮罩软收边，滚出的数字淡出而非硬裁。
class Case33SpinningCounter extends StatefulWidget {
  const Case33SpinningCounter({super.key});

  @override
  State<Case33SpinningCounter> createState() => _Case33SpinningCounterState();
}

class _Case33SpinningCounterState extends State<Case33SpinningCounter> with SingleTickerProviderStateMixin {
  static const _cell = 30.0; // `--p26-cell`
  static const _durMs = 1400.0; // `--p26-dur`
  static const _staggerMs = 90.0; // `--p26-stagger`
  static const _spins = 3; // `--p26-spins`
  static const _blur = 3.0; // `--p26-spin-blur`
  static const _ease = Cubic(0.16, 1, 0.3, 1); // `--p26-ease`
  static const _target = '100'; // `--p26-target`（toLocaleString 后无千分位）

  /// 三列错峰的最长收尾 = 1400 + 90×2；未起转时静止只显示一列 0
  static const _totalMs = _durMs + _staggerMs * 2;

  static final _valueStyle = LabText.number.copyWith(
    fontSize: 23,
    fontWeight: FontWeight.w600, // `.p26-value`
    height: 1,
  );

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1580),
  );

  bool _started = false;

  /// 等宽数字让每列同宽，卷轴落地时整串不会抖宽度
  late final double _colW = () {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: _valueStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _started = true);
    // 参考稿每次点击都重建卷轴并从头起转：落点不动，再点就再转一遍
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final str = _started ? _target : '0';
    // `.stage-inner` 通用值 padding-bottom:56，这一格没有覆盖，内容中心偏上
    return LabStage(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Center(
                child: ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < str.length; i++) _reel(str[i], i),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          LabStageFooter(
            children: [LabAnimateButton(label: 'Animate', onTap: _toggle)],
          ),
        ],
      ),
    );
  }

  /// 一列：数字带纵向滚过 30px 窗口，带自身吃纵向模糊，窗口吃渐变遮罩
  Widget _reel(String ch, int i) {
    final digit = int.tryParse(ch);
    if (digit == null) {
      // 千分位逗号这类不进卷轴，直接站着（.t-reel-sep）
      return Text(ch, style: _valueStyle);
    }
    // 未起转时静止在 "0"：落点就是本位数字、不转圈、不带糊
    final land = (_started ? _spins * 10 + digit : digit) * _cell;
    final local = _started
        ? ((_c.value * _totalMs - i * _staggerMs) / _durMs).clamp(0.0, 1.0)
        : 1.0;
    final y = -land * _ease.transform(local);
    // 模糊按**线性**进度衰（参考稿逐帧如此，不跟着缓动曲线走）
    final sigmaY = _started ? _blur * (1 - local) : 0.0;

    Widget strip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 0-9 循环 spins+1 轮，第 spins*10+digit 格正是落点
        for (var k = 0; k < (_spins + 1) * 10; k++)
          SizedBox(height: _cell, child: Center(child: Text('${k % 10}', style: _valueStyle))),
      ],
    );
    if (sigmaY > 0.05) {
      // 只做纵向糊：横向 CSS 式模糊会把字糊花，方向本身就是要还原的点
      strip = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 0.0, sigmaY: sigmaY),
        child: strip,
      );
    }

    return SizedBox(
      width: _colW,
      height: _cell,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (size) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0.0, 0.22, 0.78, 1.0], // mask-image 原值
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
        child: ClipRect(
          // 窗口只有 30 高，带子按整条自然高度排版再平移
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: _cell * (_spins + 1) * 10,
            child: Transform.translate(offset: Offset(0, y), child: SizedBox(width: _colW, child: strip)),
          ),
        ),
      ),
    );
  }
}
