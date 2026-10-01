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
    return GestureDetector(
      onTap: onExpand,
      onPanUpdate: (d) => onPan(d.delta),
      child: ClipRRect(
        borderRadius: AppTheme.metrics.radius12,
        child: Container(
          width: 200,
          height: 112,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
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
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
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
    return Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: AppTheme.metrics.radius8,
      ),
      child: Icon(icon, color: Colors.white70, size: 14),
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
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: AppTheme.metrics.radius10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign${deltaSec.abs()}s',
            style: TextStyle(
              color: LightColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: AppTheme.metrics.fontSize17,
            ),
          ),
          SizedBox(height: AppTheme.metrics.kSpace4),
          Text(
            _fmt(t),
            style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize13),
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
    return IconButton(
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: Colors.white.withValues(alpha: 0.85),
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
  _GlassPulsePainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final scale = 0.8 + 0.4 * (0.5 + 0.5 * t);
    final opacity = 0.4 + 0.4 * t;
    final diameter = 56.0 * scale;
    final center = size.center(Offset.zero);
    final radius = diameter / 2;
    // 半透明填充
    final fill = Paint()..color = LightColors.primary.withValues(alpha: opacity * 0.15);
    canvas.drawCircle(center, radius, fill);
    // 边框
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = LightColors.primary.withValues(alpha: opacity * 0.5);
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary 限定重绘范围；播放图标保持静态，不随动画重建
    return RepaintBoundary(
      child: SizedBox(
        width: 68,
        height: 68,
        child: CustomPaint(
          painter: _GlassPulsePainter(_ctrl),
          child: const Center(
            child: Icon(Icons.play_arrow_rounded, color: Colors.white60, size: 24),
          ),
        ),
      ),
    );
  }
}

class _AudioWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
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
