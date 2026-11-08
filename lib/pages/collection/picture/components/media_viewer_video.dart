part of 'media_viewer_page.dart';

// ── 视频预览 ───────────────────────────────────────────────────────────────

/// 音频占位舞台的底（恒不反转）
///
/// 没有画面可放时，这一层就是"舞台本身"——同 `mediaStage` 一样是恒定暗底，
/// 只是带了点靛蓝色相，让封面/波形那层白色墨字有对比。它不是界面表面，
/// 跟主题反相的话，亮色模式下整块舞台会变白，压在其上的 chrome 白字直接消失。
/// 三档是同一支渐变的三个停靠点，成套，单独调一档就破坏明暗节奏。
abstract final class _AudioStageBackdrop {
  static const List<Color> gradient = [Color(0xFF12101E), Color(0xFF1A1632), Color(0xFF0D0B15)];
}

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
    this.onReady,
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

  /// 播放器就绪（画面尺寸已确定）时回调一次，父级据此预热下一项。
  final VoidCallback? onReady;

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

  /// 纯音频的就绪监听（没有视频轨道，只能等 playing 事件）。
  StreamSubscription? _audioReadySub;

  /// 播放器音量变化订阅：把用户调节结果写回持久化设置。
  StreamSubscription? _volumeSub;

  /// 音量写盘防抖：拖动滑块会连续触发几十次，合并成停手后写一次。
  Timer? _volumeSaveTimer;

  /// 音量偏好（预览页专用：音量跨集、跨会话沿用，不影响音乐播放器的音量）。
  MediaPrefsService get _volumePrefs => getIt<MediaPrefsService>();

  /// 立即把当前播放器音量落盘（防抖窗口内离开页面时调用，否则这次调节会丢）。
  void _flushVolume() {
    final hadPending = _volumeSaveTimer?.isActive ?? false;
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = null;
    if (!hadPending) return;
    final v = _player?.state.volume;
    if (v != null && (v - _volumePrefs.videoVolume.value).abs() >= 0.5) {
      _volumePrefs.setVideoVolume(v);
    }
  }

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

  /// 桌面端全屏（窗口最大化 + 沉浸模式）是否处于本预览页开启的状态。
  ///
  /// 记这一位是为了「谁开谁关」：用户可能是从别处（音乐播放器沉浸模式、系统
  /// 最大化）进到这个状态的，退出预览时不该无条件还原别人的窗口。
  /// 真正的窗口态一律现查 `windowManager.isMaximized()`，本字段只做归属标记。
  bool _ownFullscreen = false;

  // ── 振幅进度条（波形）──────────────────────────────────────────────────
  // 把普通横条进度条换成按音频振幅显示的波形条：高声段顶天、安静段矮，
  // 点哪跳哪。开关持久化在 MediaPrefsService，跨会话沿用。

  /// 当前是否处于振幅模式（初始值取持久化偏好）
  bool _waveMode = false;

  /// 波形数据（0~1 峰值数组）；null = 尚未取得（提取中或失败）
  List<double>? _waveform;

  /// 波形提取是否已失败（失败后退回普通进度条，不再挂转圈骗人）
  bool _waveFailed = false;

  /// 提取任务序号：切源/切页后旧任务的结果直接丢弃，防止串页
  int _waveJob = 0;

  /// 播放位置/总时长（毫秒）。走 ValueNotifier 让波形条自己重绘，
  /// position 事件很密，不值得为它 setState 整个预览页。
  final ValueNotifier<int> _posMs = ValueNotifier<int>(0);
  final ValueNotifier<int> _durMs = ValueNotifier<int>(0);
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  /// 本机型可用的振幅进度条开关：仅桌面端 + 本地文件（远程 URL / 移动端没有解码兜底）。
  /// supports() 要摸磁盘（existsSync），按 source 记忆化，避免每帧 build 重复 stat。
  String? _waveAvailSrc;
  bool _waveAvailVal = false;
  bool get _waveAvailable {
    if (!widget.isActive) return false;
    final src = widget.source;
    if (_waveAvailSrc != src) {
      _waveAvailSrc = src;
      _waveAvailVal = getIt<VideoWaveformService>().supports(src);
    }
    return _waveAvailVal;
  }

  /// 重新挂位置/时长订阅（每个 Player 实例一次）
  void _bindPositionStreams(Player player) {
    _posSub?.cancel();
    _durSub?.cancel();
    _posMs.value = 0;
    _durMs.value = 0;
    _posSub = player.stream.position.listen((d) => _posMs.value = d.inMilliseconds);
    _durSub = player.stream.duration.listen((d) => _durMs.value = d.inMilliseconds);
  }

  /// 启动当前源的波形提取（开关关 / 平台不支持 / 已失败过则跳过）。
  void _startWaveExtraction() {
    final gen = ++_waveJob;
    _waveform = null;
    _waveFailed = false;
    final src = widget.source;
    if (!_waveMode || src == null || !getIt<VideoWaveformService>().supports(src)) return;
    getIt<VideoWaveformService>().waveformFor(src).then((data) {
      if (!mounted || gen != _waveJob) return;
      if (data == null) {
        setState(() => _waveFailed = true);
      } else {
        setState(() => _waveform = data);
      }
    });
  }

  /// 切换振幅/普通进度条，并写入偏好（下次打开预览沿用）。
  void _toggleWaveMode() {
    final next = !_waveMode;
    setState(() => _waveMode = next);
    getIt<MediaPrefsService>().setVideoWaveformSeek(next);
    if (next && _waveform == null && !_waveFailed) _startWaveExtraction();
  }

  /// 原生 Media Session / Now Playing 通道（iOS + Android）
  static const _mediaChannel = MethodChannel('slime_works/media_session');

  @override
  void initState() {
    super.initState();
    // 振幅进度条开关：跨会话沿用持久化偏好
    _waveMode = getIt<MediaPrefsService>().videoWaveformSeek.value;
    if (widget.isActive) _initPlayer();
  }

  void _initPlayer() {
    final source = widget.source;
    if (source == null || source.isEmpty) return;
    debugPrint('[MVP] _VideoPreview._initPlayer source=$source');
    // 视频预览按需初始化 media_kit，避免应用启动就加载 libmpv
    MediaKit.ensureInitialized();
    _playerReady = false;
    _readySub?.cancel();
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 128 * 1024 * 1024));
    _videoController = VideoController(_player!);
    // 套用上次记住的音量：Player 每个实例都是全新状态，不在这里恢复就会回到 100%
    _player!
      ..setVolume(_volumePrefs.videoVolume.value)
      ..setPlaylistMode(PlaylistMode.single);
    // 用户在面板里拖动后写回设置，下次打开预览沿用。
    // 与 videoVolume 同值的事件直接跳过：既避免自己 setVolume 的回声，也防重入。
    _volumeSub?.cancel();
    _volumeSub = _player!.stream.volume.listen((v) {
      if ((v - _volumePrefs.videoVolume.value).abs() < 0.5) return;
      _volumeSaveTimer?.cancel();
      _volumeSaveTimer = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _volumePrefs.setVideoVolume(v);
      });
    });
    final uri = source.startsWith('http') ? source : Uri.file(source).toString();
    _player!.open(Media(uri));
    // 振幅进度条：位置/时长订阅 + 提取当前源波形
    _bindPositionStreams(_player!);
    _startWaveExtraction();
    _readySub = _player!.stream.videoParams.listen((params) {
      if ((params.dw ?? 0) > 0 && !_playerReady) {
        _readySub?.cancel();
        _readySub = null;
        // 等播放器把尺寸真正定下来再揭界面：这是就绪等待，不是动效时长（§5.2）
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _playerReady = true;
          setState(() {});
          widget.onReady?.call();
        });
      }
    });
    // 纯音频没有视频轨道，videoParams 永远不会到：用「开始播放」当作就绪信号
    if (widget.isAudio) {
      _audioReadySub?.cancel();
      _audioReadySub = _player!.stream.playing.listen((playing) {
        if (!playing || !mounted || _playerReady) return;
        _playerReady = true;
        setState(() {});
        widget.onReady?.call();
      });
    }
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
      _audioReadySub?.cancel();
      _audioReadySub = null;
      _volumeSub?.cancel();
      _volumeSub = null;
      _flushVolume();
      // 波形状态随 Player 一起放下（再变活跃时会重新提取/读缓存）
      _waveJob++;
      _waveform = null;
      _waveFailed = false;
      _posSub?.cancel();
      _posSub = null;
      _durSub?.cancel();
      _durSub = null;
      _posMs.value = 0;
      _durMs.value = 0;
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
    // 退出预览时若全屏是本页开的，必须还回去：否则回到列表会看到侧栏和顶栏消失。
    // 只还原自己开的那一份，别动用户从别处（音乐播放器沉浸模式等）带来的状态。
    if (_ownFullscreen) {
      _ownFullscreen = false;
      final immersive = getIt<DesktopScreenProvider>().desktopImmersiveMode;
      if (immersive.value) immersive.value = false;
      unawaited(windowManager.unmaximize());
    }
    _readySub?.cancel();
    _audioReadySub?.cancel();
    _volumeSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _posMs.dispose();
    _durMs.dispose();
    _waveJob++;
    _flushVolume();
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

  // ── 桌面端全屏（窗口语义）────────────────────────────────────────────

  /// 桌面端全屏开关：窗口最大化 + 沉浸模式（隐藏侧栏与顶栏）。
  ///
  /// 不用 media_kit 的 `toggleFullscreen`：那是压一条全屏 route，与窗口真实状态
  /// 完全脱钩 —— 用户把窗口拖小之后 route 仍在栈上，`isFullscreen` 依旧为 true，
  /// 再点一次就被当成「退出全屏」直接 pop，行为与直觉相反。
  /// 改成窗口语义后，"全屏"就是窗口真的最大化，用户手动缩窗也自然退出全屏。
  Future<void> _toggleDesktopFullscreen() async {
    if (!PlatformUtil.isDesktop) return;
    final immersive = getIt<DesktopScreenProvider>().desktopImmersiveMode;
    // 窗口态现查：用户可能用系统按钮/快捷键改过，缓存值不可信
    final maximized = await windowManager.isMaximized();
    if (_ownFullscreen || (immersive.value && maximized)) {
      _ownFullscreen = false;
      immersive.value = false;
      if (maximized) await windowManager.unmaximize();
    } else {
      _ownFullscreen = true;
      immersive.value = true;
      if (!maximized) await windowManager.maximize();
    }
    if (mounted) setState(() {});
  }

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

    // 底部控制栏：进度指示器 + 弹簧 + [振幅条, 速度, 适应, 音量, 窗口, 全屏]
    // 控制栏已离开屏幕最底端，会有额外 margin
    // 振幅覆盖层：开关开 + 本机可提取 + 未失败。数据未到期间先挂转圈，
    // 让"切换"立刻可见；提取失败则整体退回普通条（不再空转骗人）。
    final waveCover = _waveMode && _waveAvailable && !_waveFailed;

    const double buttonBarH = 52.0;
    // 自定义功能按钮组（两套控件共用）：振幅开关 + 速度 + 适应 + 音量
    final customButtons = <Widget>[
      // 振幅进度条开关：仅桌面端本地文件可见（远程/移动端无解码兜底，藏起来免得点了没反应）
      if (_waveAvailable)
        _VideoWaveButton(active: _waveMode, onToggle: _toggleWaveMode),
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
    ];
    final seekBarMargin = EdgeInsets.only(
      bottom: bottomInset + AppTheme.metrics.kSpace12 + buttonBarH,
      left: AppTheme.metrics.kSpace12,
      right: AppTheme.metrics.kSpace12,
    );
    final barMargin = EdgeInsets.only(
      bottom: bottomInset + AppTheme.metrics.kSpace12,
      left: AppTheme.metrics.kSpace8,
      right: AppTheme.metrics.kSpace8,
    );
    // 移动端（MaterialVideoControls）底栏
    final bottomBar = [
      const media_controls.MaterialPositionIndicator(),
      const Spacer(),
      ...customButtons,
      // 应用内画中画（迷你悬浮窗）
      if (isMobile)
        _GlassControlIcon(
          icon: _miniMode ? Icons.close_fullscreen_rounded : Icons.picture_in_picture_alt_rounded,
          tooltip: _miniMode ? '退出画中画' : '画中画',
          onTap: _toggleMini,
        ),
      const media_controls.MaterialFullscreenButton(),
    ];
    // 桌面端（MaterialDesktopVideoControls）底栏：AdaptiveVideoControls 在
    // macOS/Windows 走 desktop 分支且只认 MaterialDesktopVideoControlsTheme，
    // 之前只包了移动端那套主题，桌面端整条自定义栏（含振幅开关）都被默认栏顶掉了。
    final desktopBottomBar = [
      const media_controls.MaterialDesktopPlayOrPauseButton(),
      const media_controls.MaterialDesktopPositionIndicator(),
      const Spacer(),
      ...customButtons,
      // 桌面端全屏 = 窗口最大化 + 沉浸模式，不能用 media_kit 的
      // MaterialDesktopFullscreenButton（它只会压一条全屏 route，与窗口状态
      // 互不知情：窗口被缩小后它仍认为"在全屏"，点一下就退出全屏）。
      _VideoFullscreenButton(onToggle: _toggleDesktopFullscreen),
    ];
    final videoWidget = media_controls.MaterialDesktopVideoControlsTheme(
      normal: media_controls.MaterialDesktopVideoControlsThemeData(
        topButtonBar: const [],
        topButtonBarMargin: EdgeInsets.zero,
        // 振幅模式下关掉原生横条，由我们叠在正上方的波形条接管点击/拖动
        displaySeekBar: !waveCover,
        seekBarMargin: seekBarMargin,
        seekBarHeight: 3.2,
        seekBarThumbSize: 14.0,
        seekBarColor: s.onMedia.withValues(alpha: 0.15),
        seekBarPositionColor: s.info.color,
        seekBarBufferColor: s.onMedia.withValues(alpha: 0.25),
        seekBarThumbColor: s.onMedia,
        bottomButtonBar: desktopBottomBar,
        bottomButtonBarMargin: barMargin,
        buttonBarHeight: buttonBarH,
        buttonBarButtonColor: s.onMedia.withValues(alpha: 0.85),
        bufferingIndicatorBuilder: (_) => _VideoLoadingSpeed(player: player),
      ),
      fullscreen: const media_controls.MaterialDesktopVideoControlsThemeData(),
      child: media_controls.MaterialVideoControlsTheme(
        normal: media_controls.MaterialVideoControlsThemeData(
          topButtonBar: const [],
          topButtonBarMargin: EdgeInsets.zero,
          // 振幅模式下关掉原生横条，由我们叠在正上方的波形条接管点击/拖动
          displaySeekBar: !waveCover,
          seekBarMargin: seekBarMargin,
          seekBarHeight: 3.2,
          seekBarThumbSize: 14.0,
          seekBarColor: s.onMedia.withValues(alpha: 0.15),
          seekBarPositionColor: s.info.color,
          seekBarBufferColor: s.onMedia.withValues(alpha: 0.25),
          seekBarThumbColor: s.onMedia,
          bottomButtonBar: bottomBar,
          bottomButtonBarMargin: barMargin,
          buttonBarHeight: buttonBarH,
          buttonBarButtonColor: s.onMedia.withValues(alpha: 0.85),
          backdropColor: s.mediaStage.withValues(alpha: 0.45),
          bufferingIndicatorBuilder: (_) => _VideoLoadingSpeed(player: player),
        ),
        fullscreen: const media_controls.MaterialVideoControlsThemeData(),
        child: Video(controller: controller, fit: _videoFit),
      ),
    );

    return Stack(
      children: [
        if (widget.isAudio)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: _AudioStageBackdrop.gradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.04,
                      child: CustomPaint(painter: _AudioWavePainter(color: s.onMedia)),
                    ),
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
          // ── 振幅进度条覆盖层 ──────────────────────────────────────────
          // 常驻叠在原生横条腾出的位置（同一 margin），不随控制栏隐藏：
          // 高声段顶天、安静段矮，一眼看出片源哪里响，点/拖即跳。
          // 波形条内部走 ValueNotifier 局部重建，高频 position 不惊动整页。
          if (waveCover)
            Positioned(
              left: AppTheme.metrics.kSpace12,
              right: AppTheme.metrics.kSpace12,
              bottom: bottomInset + AppTheme.metrics.kSpace12 + buttonBarH,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.metrics.kSpace8,
                  vertical: AppTheme.metrics.kSpace4,
                ),
                // 半透暗底让波形在亮画面/亮主题下也站得住（同 backdropColor 的路子）
                decoration: BoxDecoration(
                  color: s.mediaStage.withValues(alpha: 0.35),
                  borderRadius: AppTheme.metrics.radius12,
                ),
                child: _VideoWaveformBar(
                  waveform: _waveform,
                  loading: _waveform == null,
                  posMs: _posMs,
                  durMs: _durMs,
                  onSeek: (ms) => player.seek(Duration(milliseconds: ms)),
                ),
              ),
            ),
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
        filter: ImageFilter.blur(sigmaX: AppGlass.blurSoft, sigmaY: AppGlass.blurSoft),
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


// ── 振幅进度条覆盖层（视频预览）──────────────────────────────────────────

/// 视频预览的「振幅进度条」：复用音乐播放器的 [WaveformSeekBar]，
/// 用 ValueNotifier 只重建这一小条，不被高频 position 事件拖着整页重绘。
/// 波形还没提取好时挂转圈——切换后立刻有反馈，不用干等数据。
class _VideoWaveformBar extends StatelessWidget {
  const _VideoWaveformBar({
    required this.waveform,
    required this.loading,
    required this.posMs,
    required this.durMs,
    required this.onSeek,
  });

  /// 波形峰值（0~1）；null = 尚在提取
  final List<double>? waveform;

  /// 提取中：显示转圈占位
  final bool loading;

  /// 播放位置/总时长（毫秒）订阅源
  final ValueListenable<int> posMs;
  final ValueListenable<int> durMs;

  /// 点击/拖动跳转（毫秒）
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final wave = waveform;
    if (wave == null || loading) {
      // 提取中：转圈占位（配色跟波形自己一致，压在深底上才看得见）
      return SizedBox(
        height: scaleW(28),
        child: Center(
          child: SizedBox(
            width: AppTheme.metrics.iconSize20,
            height: AppTheme.metrics.iconSize20,
            child: CircularProgressIndicator(
              strokeWidth: AppTheme.metrics.strokeRegular,
              color: s.info.color,
            ),
          ),
        ),
      );
    }
    // 位置/时长走 ValueNotifier：高频 position 只重建这条波形，不惊动整页
    return ValueListenableBuilder<int>(
      valueListenable: posMs,
      builder: (context, pos, _) => ValueListenableBuilder<int>(
        valueListenable: durMs,
        builder: (context, dur, _) => WaveformSeekBar(
          waveform: wave,
          positionMs: pos,
          durationMs: dur,
          onSeek: onSeek,
          activeColor: s.info.color,
          inactiveColor: s.onMedia.withValues(alpha: 0.30),
          // 视频画面上的波形自带描边感，条间距收紧一点显得密而清晰
          barGap: 1.0,
          height: scaleW(28),
        ),
      ),
    );
  }
}

// ── 缓冲速度指示（播放画面中央）─────────────────────────────────────────

/// 加载/缓冲时在脉冲圈下方显示半透明下载速度小字（XX MB/s）。
///
/// 速度来自 libmpv 的 `demuxer-cache-state.raw-bytes-per-sec`（实时解复用速率，
/// 与 mpv 自带 stats 同一口径）。本地秒开场景延迟一拍再出字，避免闪跳；
/// Web/移动 WebPlayer 没有 NativePlayer，或属性读取失败时，静默退回纯脉冲圈。
class _VideoLoadingSpeed extends StatefulWidget {
  const _VideoLoadingSpeed({required this.player});

  final Player player;

  @override
  State<_VideoLoadingSpeed> createState() => _VideoLoadingSpeedState();
}

class _VideoLoadingSpeedState extends State<_VideoLoadingSpeed> {
  late StreamSubscription<bool> _bufferingSub;
  Timer? _pollTimer;
  /// 当前是否处于缓冲中（控制小字显隐节奏）
  bool _buffering = true;
  /// 当前速度文本；null 表示还没采到样本，先只显示脉冲圈
  String? _speedText;
  /// 组件销毁标志：await 回来的结果要过这道闸才允许 setState
  bool _alive = true;

  static const _firstDelay = Duration(milliseconds: 400);
  static const _pollPeriod = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _schedulePolling();
    _bufferingSub = widget.player.stream.buffering.listen((value) {
      if (!mounted) return;
      setState(() {
        _buffering = value;
        // 缓冲结束就把旧速度抹掉，下次重新进入缓冲时不闪出过期数字
        if (!value) _speedText = null;
      });
      _schedulePolling();
    });
  }

  /// 按当前缓冲状态起停轮询（幂等：非缓冲或平台不支持时不启动）
  void _schedulePolling() {
    _pollTimer?.cancel();
    if (!_buffering) return;
    final native = widget.player.platform;
    if (native is! NativePlayer) return;
    // 首拍延迟出速度，避免本地文件一闪而过的缓冲把画面点缀成抽奖
    _pollTimer = Timer(_firstDelay, () {
      unawaited(_sampleSpeed(native));
      if (!mounted) return;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollPeriod, (_) => unawaited(_sampleSpeed(native)));
    });
  }

  Future<void> _sampleSpeed(NativePlayer native) async {
    try {
      final raw = await native.getProperty('demuxer-cache-state');
      if (!mounted || !_alive || !_buffering || raw.isEmpty) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final bps = (json['raw-bytes-per-sec'] as num?)?.toDouble();
      if (bps == null) return;
      final text = _formatSpeed(bps);
      if (text != _speedText) setState(() => _speedText = text);
    } catch (e) {
      // 属性暂不可用/换源竞态：静默跳过这一拍，保持纯脉冲圈
      debugPrint('[MVP] 读取 demuxer-cache-state 失败：$e');
    }
  }

  /// 与 dashboard 网络卡片同一格式化口径：≥1024 KB/s 走 MB/s，保留两位
  static String _formatSpeed(double bytesPerSec) {
    final kbps = bytesPerSec / 1024.0;
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(2)} MB/s';
    return '${kbps.toStringAsFixed(0)} KB/s';
  }

  @override
  void dispose() {
    _alive = false;
    _pollTimer?.cancel();
    _bufferingSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _GlassPulseLoader(),
        if (_buffering && _speedText != null) ...[
          SizedBox(height: AppTheme.metrics.kSpace8),
          Text(
            _speedText!,
            style: TextStyle(
              fontSize: AppTheme.metrics.fontSize13,
              // 半透明小字：压在媒体深色底上，读得到但不抢画面
              color: s.onMedia.withValues(alpha: 0.75),
            ),
          ),
        ],
      ],
    );
  }
}

// ── 振幅进度条切换按钮（底部控制栏）─────────────────────────────────────

class _VideoWaveButton extends StatelessWidget {
  const _VideoWaveButton({required this.active, required this.onToggle});

  /// 当前是否处于振幅模式（按钮高亮反馈）
  final bool active;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return IconButton(
      tooltip: active ? '切回普通进度条' : '振幅进度条',
      icon: Icon(
        Icons.graphic_eq_rounded,
        // 开启时用 info 紫点亮，一眼看出当前处于哪种进度条
        color: active ? s.info.color : s.onMedia.withValues(alpha: 0.85),
        size: AppTheme.metrics.iconSize22,
      ),
      onPressed: onToggle,
    );
  }
}

// ── 桌面端全屏按钮（窗口语义，非 route）────────────────────────────────

/// 桌面端底栏的全屏开关。
///
/// 图标按窗口真实最大化状态切换，而不是按"有没有全屏 route"——
/// 用户拖窗口缩小后窗口态立刻变回非全屏，图标也跟着变回去，不再自说自话。
class _VideoFullscreenButton extends StatefulWidget {
  const _VideoFullscreenButton({required this.onToggle});

  final Future<void> Function() onToggle;

  @override
  State<_VideoFullscreenButton> createState() => _VideoFullscreenButtonState();
}

class _VideoFullscreenButtonState extends State<_VideoFullscreenButton> with WindowListener {
  /// 窗口是否已最大化（现查，不做跨组件共享的静态缓存）
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await windowManager.isMaximized();
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  // 用户用系统按钮/快捷键改窗口态时，图标跟着变
  @override
  void onWindowMaximize() => _refresh();

  @override
  void onWindowUnmaximize() => _refresh();

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    return IconButton(
      tooltip: _maximized ? '退出全屏' : '全屏',
      icon: Icon(
        _maximized ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        color: s.onMedia.withValues(alpha: 0.85),
        size: AppTheme.metrics.iconSize22,
      ),
      onPressed: () async {
        await widget.onToggle();
        await _refresh();
      },
    );
  }
}
