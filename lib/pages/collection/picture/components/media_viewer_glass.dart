part of 'media_viewer_page.dart';

// ── 玻璃磨砂 icon 按钮 ─────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppTheme.metrics.radius22,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 42,
            height: 42,
            color: Colors.black.withValues(alpha: 0.42),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: AppTheme.metrics.iconSize22),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

// ── 玻璃计数标签（带滚动动画） ──────────────────────────────────────────────

class _GlassChip extends StatefulWidget {
  const _GlassChip({required this.current, required this.total});

  final int current;
  final int total;

  @override
  State<_GlassChip> createState() => _GlassChipState();
}

class _GlassChipState extends State<_GlassChip> {
  bool _goingForward = true;

  @override
  void didUpdateWidget(_GlassChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current) {
      _goingForward = widget.current > oldWidget.current;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius14,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace10,
            vertical: AppTheme.metrics.kSpace4,
          ),
          color: Colors.black.withValues(alpha: 0.42),
          // 固定宽度避免数字变化时容器宽度跳动
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 只有当前数字有滚动动画
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  final isIncoming = child.key == ValueKey(widget.current);
                  final begin = isIncoming
                      ? Offset(0, _goingForward ? 1.0 : -1.0)
                      : Offset(0, _goingForward ? -1.0 : 1.0);
                  final pos = Tween<Offset>(
                    begin: begin,
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                  return ClipRect(
                    child: SlideTransition(position: pos, child: child),
                  );
                },
                child: Text(
                  '${widget.current + 1}',
                  key: ValueKey(widget.current),
                  style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize13),
                ),
              ),
              // 总数静止，无动画
              Text(
                ' / ${widget.total}',
                style: TextStyle(color: Colors.white70, fontSize: AppTheme.metrics.fontSize13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 浮动操作菜单（右下角，点击展开向上弹出独立圆形按钮，3s 自动收起）───────────

class _FloatingActionMenu extends StatefulWidget {
  const _FloatingActionMenu({
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    this.onSave,
  });

  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  /// null = 不显示保存按钮
  final VoidCallback? onSave;

  @override
  State<_FloatingActionMenu> createState() => _FloatingActionMenuState();
}

class _FloatingActionMenuState extends State<_FloatingActionMenu>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  Timer? _autoCollapseTimer;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _collapse();
    } else {
      _expand();
    }
  }

  void _expand() {
    setState(() => _expanded = true);
    _animController.forward();
    _resetAutoCollapse();
  }

  void _collapse() {
    setState(() => _expanded = false);
    _animController.reverse();
    _autoCollapseTimer?.cancel();
  }

  void _resetAutoCollapse() {
    _autoCollapseTimer?.cancel();
    _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _expanded) _collapse();
    });
  }

  void _handleAction(VoidCallback action) {
    _collapse();
    action();
  }

  /// 构建一个独立的圆形玻璃按钮，带 fade+scale 动画。
  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required int delayMs,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _animController,
        curve: Interval(delayMs / 300.0, 1.0, curve: Curves.easeOut),
      ),
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: _animController,
          curve: Interval(delayMs / 300.0, 1.0, curve: Curves.easeOutBack),
        ),
        child: _GlassIconButton(icon: icon, tooltip: tooltip, onTap: () => _handleAction(onTap)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 按顺序收集需要展示的操作按钮（从上到下：保存、上一项、下一项）
    final actionBtns = <Widget>[];
    var delay = 0;
    if (widget.onSave != null) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.save_alt_rounded,
          tooltip: '保存到相册',
          onTap: widget.onSave!,
          delayMs: delay,
        ),
      );
      delay += 60;
    }
    if (widget.canGoPrev) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.expand_less_rounded,
          tooltip: '上一项',
          onTap: widget.onPrev,
          delayMs: delay,
        ),
      );
      delay += 60;
    }
    if (widget.canGoNext) {
      actionBtns.add(
        _actionBtn(
          icon: Icons.expand_more_rounded,
          tooltip: '下一项',
          onTap: widget.onNext,
          delayMs: delay,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 展开的独立圆形按钮，每个之间有 10px 间距
        if (_expanded) ...[
          for (final btn in actionBtns) ...[btn, SizedBox(height: AppTheme.metrics.kSpace10)],
        ],
        // 常驻折叠/展开总按钮
        _GlassIconButton(
          icon: Icons.more_vert_rounded,
          tooltip: _expanded ? '收起' : '更多操作',
          onTap: _toggle,
        ),
      ],
    );
  }
}

