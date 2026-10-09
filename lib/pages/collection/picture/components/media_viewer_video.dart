part of 'media_viewer_page.dart';

// ── 视频预览 ───────────────────────────────────────────────────────────────

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({
    required this.source,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.isActive = true,
    this.isAudio = false,
    this.title,
    this.coverSource,
  });

  final String? source;
  final VoidCallback onDragStart;
  final void Function(double dy) onDragUpdate;
  final void Function(double velocity, double screenExtent) onDragEnd;

  /// 是否为当前活跃页（仅活跃页初始化 Player 并播放；邻页仅占位）
  final bool isActive;

  /// 是否为纯音频（无视频轨道），显示音乐占位背景
  final bool isAudio;

  /// 媒体标题（用于系统播放控件显示）
  final String? title;

  /// 封面图路径或 URL（用于系统播放控件显示）
  final String? coverSource;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  Player? _player;
  VideoController? _videoController;
  BoxFit _videoFit = BoxFit.contain;
  bool _swiping = false;
  bool _playerReady = false;
  StreamSubscription? _readySub;

  // 应用内迷你悬浮窗（画中画）：复用同一 Player 的第二个视频输出
  VideoController? _miniController;
  bool _miniMode = false;
  Offset _miniOffset = const Offset(16, 88);

  // 水平拖动快进/快退
  bool _seeking = false;
  double _seekAccumDx = 0.0;
  Duration _seekStart = Duration.zero;

  // 音量面板是否展开
  bool _showVolumePanel = false;

  /// 原生 Media Session / Now Playing 通道（iOS + Android）
  static const _mediaChannel = MethodChannel('slime_works/media_session');

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _initPlayer();
  }

  void _initPlayer() {
    final source = widget.source;
    if (source == null || source.isEmpty) return;
    debugPrint('[MVP] _VideoPreview._initPlayer source=$source');
    _playerReady = false;
    _readySub?.cancel();
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 128 * 1024 * 1024));
    _videoController = VideoController(_player!);
    final uri = source.startsWith('http') ? source : Uri.file(source).toString();
    _player!.open(Media(uri));
    _player!.setPlaylistMode(PlaylistMode.single);
    _readySub = _player!.stream.videoParams.listen((params) {
      if ((params.dw ?? 0) > 0 && !_playerReady) {
        _readySub?.cancel();
        _readySub = null;
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _playerReady = true;
          setState(() {});
        });
      }
    });
    _updateNowPlaying();
  }

  @override
  void didUpdateWidget(_VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // isActive 变化：从非活跃→活跃时初始化 Player，从活跃→非活跃时释放 Player
    if (widget.isActive && !oldWidget.isActive) {
      _initPlayer();
      return;
    }
    if (!widget.isActive && oldWidget.isActive) {
      _readySub?.cancel();
      _miniController = null;
      _player?.dispose();
      _player = null;
      _videoController = null;
      _playerReady = false;
      _miniMode = false;
      return;
    }
    // 活跃状态下 source 变化
    if (widget.isActive) {
      final oldEmpty = oldWidget.source == null || oldWidget.source!.isEmpty;
      final newEmpty = widget.source == null || widget.source!.isEmpty;
      final sourceChanged = !oldEmpty && !newEmpty && oldWidget.source != widget.source;
      debugPrint(
        '[MVP] _VideoPreview.didUpdateWidget oldSource=${oldWidget.source}, newSource=${widget.source}, oldEmpty=$oldEmpty, newEmpty=$newEmpty, sourceChanged=$sourceChanged',
      );
      if ((oldEmpty && !newEmpty) || sourceChanged) {
        _miniController = null;
        _miniMode = false;
        _player?.dispose();
        _player = null;
        _videoController = null;
        _initPlayer();
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _readySub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  /// 把封面图读成字节并通过 MethodChannel 发给原生层，由原生层更新
  /// MPNowPlayingInfoCenter (iOS) 或 MediaSession (Android)。
  Future<void> _updateNowPlaying() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      Uint8List? artBytes;
      final cover = widget.coverSource;
      if (cover != null && cover.isNotEmpty) {
        if (cover.startsWith('http')) {
          final resp = await http.get(Uri.parse(cover)).timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) artBytes = resp.bodyBytes;
        } else {
          final f = File(cover);
          if (f.existsSync()) artBytes = await f.readAsBytes();
        }
      }
      await _mediaChannel.invokeMethod<void>('setNowPlaying', {
        'title': widget.title ?? '',
        'artist': '',
        'artwork': artBytes,
      });
    } catch (_) {
      // 非致命：系统控件显示默认信息即可
    }
  }

  /// 切换应用内迷你悬浮窗（画中画）。
  /// media_kit 基于 Flutter 纹理渲染，无法做系统级 PiP，故用第二个 VideoController
  /// 复用同一 Player 渲染成可拖动的小窗。
  void _toggleMini() {
    final player = _player;
    if (player == null) return;
    if (_miniMode) {
      _miniController = null;
      setState(() => _miniMode = false);
    } else {
      _miniController = VideoController(player);
      setState(() => _miniMode = true);
    }
  }

  // ── 水平拖动快进/快退 ────────────────────────────────────────────────

  void _beginSeek() {
    final p = _player;
    if (p == null) return;
    _seekStart = p.state.position;
    _seekAccumDx = 0.0;
    setState(() => _seeking = true);
  }

  void _updateSeek(double dx) {
    _seekAccumDx += dx;
    if (_seeking) setState(() {});
  }

  void _commitSeek() {
    final p = _player;
    if (p == null || !_seeking) return;
    final width = MediaQuery.sizeOf(context).width;
    final span = 60.0; // 一个屏幕宽度对应的快进时长（秒）
    final durMs = p.state.duration.inMilliseconds;
    final base = _seekStart.inMilliseconds;
    final targetMs = (base + _seekAccumDx / width * span * 1000).round().clamp(0, durMs);
    p.seek(Duration(milliseconds: targetMs));
    setState(() => _seeking = false);
  }

  void _cancelSeek() {
    if (_seeking) setState(() => _seeking = false);
  }

  /// 快进/快退反馈的屏幕方位（向右拖 = 右侧，向左拖 = 左侧）。
  Alignment get _seekAlign =>
      _seekAccumDx >= 0 ? Alignment.centerRight : Alignment.centerLeft;

  /// 拖动中的目标时间点（null = 未在拖动）。
  Duration? get _seekTarget {
    final p = _player;
    if (p == null || !_seeking) return null;
    final width = MediaQuery.sizeOf(context).width;
    final span = 60.0; // 一个屏幕宽度对应的快进时长（秒）
    final durMs = p.state.duration.inMilliseconds;
    final base = _seekStart.inMilliseconds;
    final ms = (base + _seekAccumDx / width * span * 1000).round().clamp(0, durMs);
    return Duration(milliseconds: ms);
  }

  @override
  Widget build(BuildContext context) {
    // 视频层的所有 chrome 都压在画面/黑台上，取不随明暗翻转的媒体 chrome 语义色
    final s = AppSemantic.of(context);
    final player = _player;
    final controller = _videoController;
    if (player == null || controller == null) {
      // 非活跃页（邻页预缓存）：显示黑色占位或封面缩略图
      if (!widget.isActive) {
        return SizedBox.expand(child: ColoredBox(color: s.mediaStage));
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppTheme.metrics.kSpace56,
              height: AppTheme.metrics.kSpace56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.onMedia.withValues(alpha: 0.08),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.error_outline_rounded,
                // 查看器深色画面上的强调色走语义 info 紫（原始色板不进业务代码）
                color: AppSemantic.of(context).info.color.withValues(alpha: 0.7),
                size: scaleW(28),
              ),
            ),
            SizedBox(height: AppTheme.metrics.kSpace12),
            Text(
              '无法加载视频',
              style: AppTextStyles.role(context, color: s.onMediaTertiary, fontSize: AppTheme.metrics.fontSize13),
            ),
          ],
        ),
      );
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final viewPad = MediaQuery.viewPaddingOf(context);
    final bottomInset = isMobile ? viewPad.bottom : 0.0;

    // 底部控制栏：进度指示器 + 弹簧 + [速度, 适应, 音量, 窗口, 全屏]
    // 控制栏已离开屏幕最底端，会有额外 margin
    final bottomBar = [
      const media_controls.MaterialPositionIndicator(),
      const Spacer(),
      _VideoSpeedButton(player: player),
      _VideoFitButton(
        currentFit: _videoFit,
        onToggle: () =>
            setState(() => _videoFit = _videoFit == BoxFit.contain ? BoxFit.cover : BoxFit.contain),
      ),
      _VideoVolumeButton(
        player: player,
        panelOpen: _showVolumePanel,
        onTogglePanel: () => setState(() => _showVolumePanel = !_showVolumePanel),
      ),
      // 应用内画中画（迷你悬浮窗）
      if (isMobile)
        _GlassControlIcon(
          icon: _miniMode ? Icons.close_fullscreen_rounded : Icons.picture_in_picture_alt_rounded,
          tooltip: _miniMode ? '退出画中画' : '画中画',
          onTap: _toggleMini,
        ),
      const media_controls.MaterialFullscreenButton(),
    ];

    const double buttonBarH = 52.0;
    final videoWidget = media_controls.MaterialVideoControlsTheme(
      normal: media_controls.MaterialVideoControlsThemeData(
        topButtonBar: const [],
        topButtonBarMargin: EdgeInsets.zero,
        seekBarMargin: EdgeInsets.only(
          bottom: bottomInset + AppTheme.metrics.kSpace12 + buttonBarH,
          left: AppTheme.metrics.kSpace12,
          right: AppTheme.metrics.kSpace12,
        ),
        seekBarHeight: 3.2,
        seekBarThumbSize: 14.0,
        seekBarColor: s.onMedia.withValues(alpha: 0.15),
        seekBarPositionColor: s.info.color,
        seekBarBufferColor: s.onMedia.withValues(alpha: 0.25),
        seekBarThumbColor: s.onMedia,
        bottomButtonBar: bottomBar,
        bottomButtonBarMargin: EdgeInsets.only(
          bottom: bottomInset + AppTheme.metrics.kSpace12,
          left: AppTheme.metrics.kSpace8,
          right: AppTheme.metrics.kSpace8,
        ),
        buttonBarHeight: buttonBarH,
        buttonBarButtonColor: s.onMedia.withValues(alpha: 0.85),
        backdropColor: s.mediaStage.withValues(alpha: 0.45),
        bufferingIndicatorBuilder: (_) => const _GlassPulseLoader(),
      ),
      fullscreen: const media_controls.MaterialVideoControlsThemeData(),
      child: Video(controller: controller, fit: _videoFit),
    );

    return Stack(
      children: [
        if (widget.isAudio)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF12101E), Color(0xFF1A1632), Color(0xFF0D0B15)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(opacity: 0.04, child: CustomPaint(painter: _AudioWavePainter())),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.coverSource != null && widget.coverSource!.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: AppTheme.metrics.radius16,
                            boxShadow: [
                              BoxShadow(
                                color: AppSemantic.of(context).info.color.withValues(alpha: 0.2),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: AppTheme.metrics.radius16,
                            child: widget.coverSource!.startsWith('http')
                                ? Image.network(
                                    widget.coverSource!,
                                    width: scaleW(200),
                                    height: scaleW(200),
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(widget.coverSource!),
                                    width: scaleW(200),
                                    height: scaleW(200),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        )
                      else
                        Container(
                          width: scaleW(200),
                          height: scaleW(200),
                          decoration: BoxDecoration(
                            borderRadius: AppTheme.metrics.radius16,
                            color: s.onMedia.withValues(alpha: 0.05),
                            border: Border.all(color: s.onMedia.withValues(alpha: 0.08)),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: AppSemantic.of(context).info.color.withValues(alpha: 0.4),
                            size: AppTheme.metrics.iconSize64,
                          ),
                        ),
                      SizedBox(height: AppTheme.metrics.kSpace24),
                      if (widget.title != null && widget.title!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppTheme.metrics.kSpace40),
                          child: Text(
                            widget.title!,
                            style: AppTextStyles.role(
                              context,
                              color: s.onMedia.withValues(alpha: 0.8),
                              fontSize: AppTheme.metrics.fontSize15,
                              weight: FontWeight.w500,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Text(
                          '音频播放中',
                          style: AppTextStyles.role(
                            context,
                            color: s.onMediaFaint,
                            fontSize: AppTheme.metrics.fontSize13,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!widget.isAudio)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _playerReady ? 0.0 : 1.0,
                duration: AppMotion.base,
                // 播放器就绪后静音封面层的动画 ticker：
                // 避免不可见的脉冲加载动画仍每帧驱动重绘（隐形动画泄漏）
                child: TickerMode(
                  enabled: !_playerReady,
                  child: widget.coverSource != null && widget.coverSource!.isNotEmpty
                      ? (widget.coverSource!.startsWith('http')
                            ? Image.network(widget.coverSource!, fit: _videoFit)
                            : Image.file(File(widget.coverSource!), fit: _videoFit))
                      : Container(
                          color: s.mediaStage,
                          child: const Center(child: _GlassPulseLoader()),
                        ),
                ),
              ),
            ),
          ),
        // ── 迷你悬浮窗（画中画）──────────────────────────────────────
        if (_miniMode && _miniController != null) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMini,
              child: Container(
                color: s.mediaStage,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fullscreen_rounded, color: s.onMediaTertiary, size: scaleW(56)),
                    SizedBox(height: AppTheme.metrics.kSpace12),
                    Text(
                      '已进入画中画，点击画面或小窗恢复全屏',
                      style: AppTextStyles.role(
                        context,
                        color: s.onMediaTertiary,
                        fontSize: AppTheme.metrics.fontSize13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: _miniOffset.dx.clamp(0.0, (MediaQuery.sizeOf(context).width - 200.0).clamp(0.0, 1e9)),
            top: _miniOffset.dy
                .clamp(0.0, (MediaQuery.sizeOf(context).height - 116.0 - viewPad.top - 60).clamp(0.0, 1e9)),
            child: _MiniPipWindow(
              controller: _miniController!,
              player: player,
              onExpand: _toggleMini,
              onPan: (delta) => setState(() => _miniOffset += delta),
            ),
          ),
        ] else ...[
          IgnorePointer(ignoring: _swiping, child: videoWidget),
          // 音量面板（点击音量按钮展开）
          if (_showVolumePanel)
            Positioned(
              right: AppTheme.metrics.kSpace8,
              bottom: bottomInset + 12 + buttonBarH + 6,
              child: _VolumePanel(
                player: player,
                onClose: () => setState(() => _showVolumePanel = false),
              ),
            ),
          if (isMobile)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // 排除底部控制栏区域，避免拖动进度条时误触发上下翻页
              bottom: bottomInset + 12 + buttonBarH + 24,
              child: _VideoSwipeListener(
                onDragStart: () {
                  setState(() => _swiping = true);
                  widget.onDragStart();
                },
                onDragUpdate: widget.onDragUpdate,
                onDragEnd: (velocity, screenExtent) {
                  widget.onDragEnd(velocity, screenExtent);
                  setState(() => _swiping = false);
                },
                onDragCancel: () => setState(() => _swiping = false),
                screenExtent: () {
                  final box = context.findRenderObject() as RenderBox;
                  return box.size.height;
                },
                onSeekStart: _beginSeek,
                onSeekUpdate: _updateSeek,
                onSeekEnd: _commitSeek,
                onSeekCancel: _cancelSeek,
                screenWidth: () {
                  final box = context.findRenderObject() as RenderBox;
                  return box.size.width;
                },
              ),
            ),
          // 水平拖动快进/快退反馈层
          if (_seeking)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: _seekAlign,
                  child: _SeekIndicator(
                    player: player,
                    target: _seekTarget,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _VideoSwipeListener extends StatefulWidget {
  const _VideoSwipeListener({
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.screenExtent,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.onSeekCancel,
    required this.screenWidth,
  });

  // 垂直滑动 = 翻页
  final VoidCallback onDragStart;
  final void Function(double dy) onDragUpdate;
  final void Function(double velocity, double screenExtent) onDragEnd;
  final VoidCallback onDragCancel;
  final double Function() screenExtent;
  // 水平滑动 = 快进/快退
  final VoidCallback onSeekStart;
  final void Function(double dx) onSeekUpdate;
  final VoidCallback onSeekEnd;
  final VoidCallback onSeekCancel;
  final double Function() screenWidth;

  @override
  State<_VideoSwipeListener> createState() => _VideoSwipeListenerState();
}

class _VideoSwipeListenerState extends State<_VideoSwipeListener> {
  int? _activePointerId;
  double _lastX = 0.0;
  double _lastY = 0.0;
  double _accH = 0.0;
  double _accV = 0.0;
  DateTime? _lastMoveTime;
  double _lastVelocity = 0.0;
  static const double _kThreshold = 12.0;

  /// null = 尚未判定轴；true = 水平，false = 垂直。
  bool? _axis;
  bool get _horizontal => _axis == true;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointerId != null) return;
    _activePointerId = event.pointer;
    _lastX = event.position.dx;
    _lastY = event.position.dy;
    _accH = 0.0;
    _accV = 0.0;
    _lastMoveTime = null;
    _lastVelocity = 0.0;
    _axis = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId) return;
    final dx = event.position.dx - _lastX;
    final dy = event.position.dy - _lastY;
    _lastX = event.position.dx;
    _lastY = event.position.dy;

    final now = DateTime.now();
    if (_lastMoveTime != null) {
      final dt = now.difference(_lastMoveTime!).inMicroseconds;
      if (dt > 0) {
        final delta = _horizontal ? dx : dy;
        _lastVelocity = delta / (dt / 1e6);
      }
    }
    _lastMoveTime = now;

    if (_axis == null) {
      _accH += dx;
      _accV += dy;
      if (_accH.abs() > _kThreshold || _accV.abs() > _kThreshold) {
        // 首次超过阈值的方向定为拖动轴
        _axis = _accH.abs() >= _accV.abs();
        if (_horizontal) {
          widget.onSeekStart();
          widget.onSeekUpdate(_accH);
        } else {
          widget.onDragStart();
          widget.onDragUpdate(_accV);
        }
        _accH = 0.0;
        _accV = 0.0;
      }
    } else if (_horizontal) {
      widget.onSeekUpdate(dx);
    } else {
      widget.onDragUpdate(dy);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) return;
    if (_axis == true) {
      widget.onSeekEnd();
    } else if (_axis == false) {
      widget.onDragEnd(_lastVelocity * 1000.0, widget.screenExtent());
    }
    _reset();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    if (_axis == true) {
      widget.onSeekCancel();
    } else if (_axis == false) {
      widget.onDragCancel();
    }
    _reset();
  }

  void _reset() {
    _activePointerId = null;
    _accH = 0.0;
    _accV = 0.0;
    _lastVelocity = 0.0;
    _axis = null;
    _lastMoveTime = null;
  }
}

class _VideoSpeedButton extends StatelessWidget {
  const _VideoSpeedButton({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.rate,
      initialData: player.state.rate,
      builder: (context, snapshot) {
        final s = AppSemantic.of(context);
        final rate = snapshot.data ?? 1.0;
        final label = (rate == rate.truncateToDouble()) ? '${rate.toInt()}x' : '${rate}x';
        return PopupMenuButton<double>(
          tooltip: '播放速度',
          // 速度菜单浮在播放画面上，底色必须是恒定的深遮罩而非主题表面
          color: s.mediaScrimStrong,
          itemBuilder: (_) => [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
              .map(
                (r) => PopupMenuItem<double>(
                  value: r,
                  child: Text(
                    (r == r.truncateToDouble()) ? '${r.toInt()}x' : '${r}x',
                    // 仅覆盖选中字色、其余继承弹出菜单默认字阶，保留裸构造
                    style: TextStyle(
                      color: r == rate ? AppSemantic.of(context).accent : null,
                    ),
                  ),
                ),
              )
              .toList(),
          onSelected: player.setRate,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.metrics.kSpace8,
              vertical: AppTheme.metrics.kSpace12,
            ),
            child: Text(
              label,
              style: AppTextStyles.role(context, color: s.onMedia, fontSize: AppTheme.metrics.fontSize13),
            ),
          ),
        );
      },
    );
  }
}

// ── 视频适应方式按钮（contain ↔ cover）─────────────────────────────────────

class _VideoFitButton extends StatelessWidget {
  const _VideoFitButton({required this.currentFit, required this.onToggle});
  final BoxFit currentFit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final isCover = currentFit == BoxFit.cover;
    return IconButton(
      tooltip: isCover ? '适应屏幕' : '填充屏幕',
      icon: Icon(
        isCover ? Icons.fit_screen_rounded : Icons.crop_rounded,
        color: s.onMedia,
        size: AppTheme.metrics.iconSize22,
      ),
      onPressed: onToggle,
    );
  }
}

// ── 视频音量按钮（点击展开音量面板）────────────────────────────────────

class _VideoVolumeButton extends StatelessWidget {
  const _VideoVolumeButton({
    required this.player,
    required this.panelOpen,
    required this.onTogglePanel,
  });
  final Player player;
  final bool panelOpen;
  final VoidCallback onTogglePanel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.stream.volume,
      initialData: player.state.volume,
      builder: (context, snapshot) {
        final s = AppSemantic.of(context);
        final vol = snapshot.data ?? 100.0;
        final icon = vol == 0
            ? Icons.volume_off_rounded
            : (vol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);
        return IconButton(
          tooltip: '音量',
          icon: Icon(icon, color: s.onMedia, size: AppTheme.metrics.iconSize22),
          onPressed: onTogglePanel,
          color: panelOpen ? AppSemantic.of(context).info.color : null,
        );
      },
    );
  }
}

// ── 音量滑块面板（面板形式，可拖动调节 + 静音）───────────────────────

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({required this.player, required this.onClose});
  final Player player;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return ClipRRect(
      borderRadius: AppTheme.metrics.radius12,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: scaleW(220),
          padding: EdgeInsets.symmetric(
            horizontal: AppTheme.metrics.kSpace12,
            vertical: AppTheme.metrics.kSpace8,
          ),
          color: s.mediaStage.withValues(alpha: 0.62),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.volume_up_rounded,
                      color: s.onMediaSecondary,
                      size: AppTheme.metrics.iconSize20,
                    ),
                    onPressed: () => player.setVolume(100.0),
                  ),
                  Expanded(
                    child: StreamBuilder<double>(
                      stream: player.stream.volume,
                      initialData: player.state.volume,
                      builder: (context, snapshot) {
                        final vol = (snapshot.data ?? 100.0).clamp(0.0, 100.0);
                        return Slider(
                          value: vol,
                          min: 0,
                          max: 100,
                          activeColor: AppSemantic.of(context).info.color,
                          onChanged: player.setVolume,
                        );
                      },
                    ),
                  ),
                  SizedBox(width: AppTheme.metrics.kSpace8),
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(
                      Icons.close_rounded,
                      color: s.onMediaTertiary,
                      size: AppTheme.metrics.iconSize20,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.center,
                child: StreamBuilder<double>(
                  stream: player.stream.volume,
                  initialData: player.state.volume,
                  builder: (context, snapshot) {
                    final vol = (snapshot.data ?? 100.0).round();
                    return Text(
                      '$vol%',
                      style: AppTextStyles.role(
                        context,
                        color: s.onMediaSecondary,
                        fontSize: AppTheme.metrics.fontSize13,
                      ),
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

