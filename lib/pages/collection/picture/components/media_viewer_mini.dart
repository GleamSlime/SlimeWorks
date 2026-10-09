part of 'media_viewer_page.dart';

// ── 迷你悬浮窗（画中画）：可拖动、可播放/暂停、点击还原 ─────────────────

class _MiniPipWindow extends StatelessWidget {
  const _MiniPipWindow({
    required this.controller,
    required this.player,
    required this.onExpand,
    required this.onPan,
  });

  final VideoController controller;
  final Player player;
  final VoidCallback onExpand;
  final ValueChanged<Offset> onPan;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return GestureDetector(
      onTap: onExpand,
      onPanUpdate: (d) => onPan(d.delta),
      child: ClipRRect(
        borderRadius: AppTheme.metrics.radius12,
        child: Container(
          // 迷你画中画是固定尺寸窄容器：内部尺寸一律走宽度族
          width: scaleW(200),
          height: scaleW(112),
          decoration: BoxDecoration(
            color: s.mediaStage,
            // 浮窗描边与黑玻璃面板同一条（≈15% 白），直接取 token
            border: Border.all(color: s.immersiveBorder),
            boxShadow: [
              BoxShadow(
                color: s.mediaStage.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: controller, fit: BoxFit.cover),
              // 顶部播放状态半透明遮罩
              Positioned(
                top: 0,
                right: 0,
                child: StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? false;
                    return _MiniPipBadge(
                      icon: playing ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    );
                  },
                ),
              ),
              // 底部进度条
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: player.state.position,
                  builder: (context, snapshot) {
                    final pos = snapshot.data ?? Duration.zero;
                    final dur = player.state.duration;
                    final ratio = dur.inMilliseconds > 0
                        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      backgroundColor: s.onMedia.withValues(alpha: 0.2),
                      // 语义色取不到 const，这里丢掉 const
                      valueColor: AlwaysStoppedAnimation<Color>(s.onMedia),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPipBadge extends StatelessWidget {
  const _MiniPipBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Container(
      margin: EdgeInsets.all(AppTheme.metrics.kSpace6),
      padding: EdgeInsets.all(AppTheme.metrics.kSpace3),
      decoration: BoxDecoration(
        color: s.mediaStage.withValues(alpha: 0.5),
        borderRadius: AppTheme.metrics.radius8,
      ),
      child: Icon(icon, color: s.onMediaSecondary, size: scaleW(14)),
    );
  }
}

// ── 快进/快退反馈指示器 ─────────────────────────────────────────────

class _SeekIndicator extends StatelessWidget {
  const _SeekIndicator({required this.player, required this.target});
  final Player player;
  final Duration? target;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final t = target ?? player.state.position;
    final deltaMs = t.inMilliseconds - player.state.position.inMilliseconds;
    final deltaSec = deltaMs ~/ 1000;
    final sign = deltaSec > 0 ? '+' : (deltaSec < 0 ? '-' : '');
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.metrics.kSpace16,
        vertical: AppTheme.metrics.kSpace8,
      ),
      decoration: BoxDecoration(
        color: s.mediaStage.withValues(alpha: 0.6),
        borderRadius: AppTheme.metrics.radius10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign${deltaSec.abs()}s',
            // 深色小窗遮罩上的强调色走语义 info 紫
            style: AppTextStyles.role(
              context,
              color: AppSemantic.of(context).info.color,
              weight: FontWeight.bold,
              fontSize: AppTheme.metrics.fontSize17,
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace4),
          Text(
            _fmt(t),
            style: AppTextStyles.role(context, color: s.onMediaSecondary, fontSize: AppTheme.metrics.fontSize13),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _GlassControlIcon extends StatelessWidget {
  const _GlassControlIcon({required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: s.onMedia.withValues(alpha: 0.85),
        size: AppTheme.metrics.iconSize20,
      ),
      onPressed: onTap,
      splashRadius: 18,
      padding: EdgeInsets.all(AppTheme.metrics.kSpace8),
    );
  }
}

class _GlassPulseLoader extends StatefulWidget {
  const _GlassPulseLoader();
  @override
  State<_GlassPulseLoader> createState() => _GlassPulseLoaderState();
}

/// 脉冲加载指示器画笔：通过 repaint 直接监听动画，
/// 每帧只重绘合成层，不触发 element rebuild（避免查看器大树上每帧 markNeedsBuild）。
class _GlassPulsePainter extends CustomPainter {
  _GlassPulsePainter(this.animation, {required this.color}) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final scale = 0.8 + 0.4 * (0.5 + 0.5 * t);
    final opacity = 0.4 + 0.4 * t;
    final diameter = 56.0 * scale;
    final center = size.center(Offset.zero);
    final radius = diameter / 2;
    // 半透明填充
    final fill = Paint()..color = color.withValues(alpha: opacity * 0.15);
    canvas.drawCircle(center, radius, fill);
    // 边框
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppTheme.metrics.strokeRegular
      ..color = color.withValues(alpha: opacity * 0.5);
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(_GlassPulsePainter oldDelegate) => false;
}

class _GlassPulseLoaderState extends State<_GlassPulseLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.pulse)..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    // RepaintBoundary 限定重绘范围；播放图标保持静态，不随动画重建
    return RepaintBoundary(
      child: SizedBox(
        width: scaleW(68),
        height: scaleW(68),
        child: CustomPaint(
          painter: _GlassPulsePainter(_ctrl, color: s.info.color),
          child: Center(
            child: Icon(Icons.play_arrow_rounded, color: s.onMediaTertiary, size: scaleW(24)),
          ),
        ),
      ),
    );
  }
}

class _AudioWavePainter extends CustomPainter {
  const _AudioWavePainter({required this.color});

  /// 波形条压在舞台渐变上，颜色由调用方给（画笔里拿不到 context）
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = AppTheme.metrics.strokeRegular
      ..strokeCap = StrokeCap.round;
    const barCount = 40;
    final barW = size.width / barCount;
    for (var i = 0; i < barCount; i++) {
      final x = i * barW + barW / 2;
      final h = (20 + 40 * ((i * 7 + 3) % 13) / 13).toDouble();
      canvas.drawLine(
        Offset(x, size.height / 2 - h / 2),
        Offset(x, size.height / 2 + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
