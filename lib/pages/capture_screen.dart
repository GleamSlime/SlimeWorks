import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/src/rust/api/capture.dart';
import 'package:slime_works/src/rust/api/ffmpeg.dart';
import 'package:slime_works/pages/capture_screen/models/recording_task.dart';
import 'package:slime_works/pages/capture_screen/widgets/dialogs.dart';
import 'package:slime_works/pages/capture_screen/widgets/list_builders.dart';

/// 数据捕获页面
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isCapturing = false;
  bool _isCertInstalled = false;
  int _selectedPort = 8433;
  String _selectedFormat = 'mp4';
  Timer? _refreshTimer;

  List<String> _videos = [];
  List<String> _images = [];
  List<String> _jsonData = [];
  List<String> _javascript = [];
  List<RecordingTask> _recordingTasks = [];
  List<RecordingTask> _availableVideos = [];

  CaptureStats? _stats;

  int get _completedCount => _recordingTasks.where((t) => t.status == RecordingStatus.completed).length;
  int get _errorCount => _recordingTasks.where((t) => t.status == RecordingStatus.error).length;
  int get _recordingCount => _recordingTasks.where((t) => t.status == RecordingStatus.recording).length;
  int get _totalRecordingSize =>
      _recordingTasks.where((t) => t.status == RecordingStatus.recording && t.fileSize != null).fold(0, (sum, task) => sum + task.fileSize!);
  bool get _hasSelectedTasks => _recordingTasks.any((t) => t.isSelected);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadCapturedData().catchError((e) => print('Load data error: $e'));
    _checkProxyStatus();
    _checkCertificateStatus();
    _loadAvailableVideos();
  }

  /// 从捕获的数据加载视频列表（使用 Rust FFmpeg）
  Future<void> _loadAvailableVideos() async {
    // 获取应用目录
    final appDir = await getApplicationSupportDirectory();
    final capturedVideos = getCapturedVideos(installDir: appDir.path);
    if (capturedVideos.isEmpty) {
      setState(() {
        _availableVideos = [];
      });
      return;
    }

    // 获取缓存目录
    final cacheDir = await getTemporaryDirectory();

    List<RecordingTask> tasks = [];

    // 并发处理所有视频
    await Future.wait(
      capturedVideos.map((url) async {
        try {
          // 获取视频元数据
          final metadata = await getVideoMetadata(videoPath: url);

          // 生成缩略图
          String thumbnailPath = '';
          try {
            thumbnailPath = await generateVideoThumbnail(videoUrl: url, cacheDir: cacheDir.path);
          } catch (e) {
            print('生成缩略图失败 $url: $e');
          }

          tasks.add(
            RecordingTask(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: _extractVideoName(url),
              url: url,
              thumbnail: thumbnailPath,
              resolution: '${metadata.width}x${metadata.height}',
              frameRate: '${metadata.frameRate.toStringAsFixed(0)} fps',
              bitrate: '${(metadata.bitRate.toInt() / 1000).toStringAsFixed(0)} kbps',
            ),
          );
        } catch (e) {
          print('处理视频失败 $url: $e');
          // 如果获取元数据失败，使用默认值
          tasks.add(
            RecordingTask(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: _extractVideoName(url),
              url: url,
              thumbnail: '',
              resolution: '未知',
              frameRate: '未知',
              bitrate: '未知',
            ),
          );
        }
      }),
    );

    if (mounted) {
      setState(() {
        _availableVideos = tasks;
      });
    }
  }

  String _extractVideoName(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      return uri.pathSegments.last.split('.').first;
    }
    return '未知视频';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 检查证书安装状态
  void _checkCertificateStatus() {
    try {
      setState(() {
        _isCertInstalled = isCaCertificateInstalled();
      });
    } catch (e) {
      setState(() {
        _isCertInstalled = false;
      });
    }
  }

  /// 检查代理运行状态
  void _checkProxyStatus() {
    setState(() {
      _isCapturing = isProxyRunning();
    });
  }

  /// 加载捕获的数据
  Future<void> _loadCapturedData() async {
    // 获取应用目录
    final appDir = await getApplicationSupportDirectory();
    setState(() {
      _videos = getCapturedVideos(installDir: appDir.path);
      _images = getCapturedImages(installDir: appDir.path);
      _jsonData = getCapturedJson(installDir: appDir.path);
      _javascript = getCapturedJavascript(installDir: appDir.path);
      _stats = getCaptureStats(installDir: appDir.path);
    });
  }

  /// 安装CA证书
  Future<void> _installCertificate() async {
    if (Platform.isMacOS) {
      final password = await showPasswordDialog(context);
      if (password == null || password.isEmpty) {
        _showMessage('已取消', isError: true);
        return;
      }

      try {
        final result = installCaCertificate(password: password);
        _showMessage(result);
        _checkCertificateStatus();

        // 显示信任证书引导
        if (mounted) {
          showTrustCertificateGuide(context);
        }
      } catch (e) {
        _showMessage('证书安装失败: $e', isError: true);
      }
    } else if (Platform.isWindows) {
      // final isAdmin = isRunningAsAdministrator();
      // if (!isAdmin) {
      //   _showMessage('请以管理员身份重新启动应用以安装证书', isError: true);
      //   return;
      // }

      try {
        installCaCertificate(password: '');
        _showMessage('证书安装成功');
        setState(() {
          _isCertInstalled = true;
        });
        _checkCertificateStatus();
      } catch (e) {
        _showMessage('证书安装失败: $e', isError: true);
      }
    }
  }

  /// 切换捕获状态
  Future<void> _toggleCapture() async {
    try {
      if (_isCapturing) {
        // 停止捕获
        final result = stopCaptureProxy();
        _showMessage(result);
        _refreshTimer?.cancel();
        _refreshTimer = null;
      } else {
        // 启动代理
        final result = startCaptureProxy(port: _selectedPort);
        _showMessage(result);

        // 启动定时刷新（每2秒刷新一次数据）
        _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
          if (mounted) {
            _loadCapturedData().catchError((e) => print('Refresh error: $e'));
          }
        });
      }
      _checkProxyStatus();
    } catch (e) {
      _showMessage('操作失败: $e', isError: true);
    }
  }

  /// 显示消息
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green, behavior: SnackBarBehavior.floating));
  }

  /// 清除所有数据
  Future<void> _clearData() async {
    final confirmed = await showClearDataDialog(context);
    if (confirmed == true) {
      clearCapturedData();
      await _loadCapturedData();
      _showMessage('数据已清除');
    }
  }

  /// 复制到剪贴板
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showMessage('已复制到剪贴板');
  }

  /// 开始录制选中的视频
  void _startRecording() {
    final selectedVideos = _availableVideos.where((v) => v.isSelected).toList();
    if (selectedVideos.isEmpty) {
      _showMessage('请先选择要录制的视频', isError: true);
      return;
    }

    for (var video in selectedVideos) {
      // 创建录制任务
      final task = RecordingTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: video.name,
        url: video.url,
        thumbnail: video.thumbnail,
        resolution: video.resolution,
        frameRate: video.frameRate,
        bitrate: video.bitrate,
        status: RecordingStatus.recording,
        startTime: DateTime.now(),
      );

      setState(() {
        _recordingTasks.insert(0, task);
      });
    }

    // 清除选中状态
    setState(() {
      for (var video in _availableVideos) {
        video.isSelected = false;
      }
    });

    _showMessage('已开始录制 ${selectedVideos.length} 个视频');
  }

  /// 修改录制任务名称
  Future<void> _editTaskName(RecordingTask task) async {
    final result = await showEditTaskNameDialog(context, task.name);

    if (result != null && result.isNotEmpty) {
      setState(() {
        task.name = result;
      });
      _showMessage('名称已更新');
    }
  }

  /// 删除录制任务
  Future<void> _deleteTask(RecordingTask task) async {
    final deleteFile = await showDeleteTaskDialog(context, task.name, task.status == RecordingStatus.completed, task.fileSizeStr);

    if (deleteFile != null) {
      setState(() {
        _recordingTasks.remove(task);
      });
      _showMessage(deleteFile ? '任务和文件已删除' : '任务已删除');
    }
  }

  /// 批量删除选中的任务
  Future<void> _batchDelete() async {
    final selectedTasks = _recordingTasks.where((t) => t.isSelected).toList();
    if (selectedTasks.isEmpty) return;

    final confirmed = await showBatchDeleteDialog(context, selectedTasks.length);

    if (confirmed == true) {
      setState(() {
        _recordingTasks.removeWhere((t) => t.isSelected);
      });
      _showMessage('已删除 ${selectedTasks.length} 个任务');
    }
  }

  /// 重新录制
  Future<void> _reRecord(RecordingTask task) async {
    final confirmed = await showReRecordDialog(context, task.name, task.status == RecordingStatus.completed);

    if (confirmed == true) {
      setState(() {
        task.isSelected = false;
      });

      final newTask = RecordingTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: task.name,
        url: task.url,
        thumbnail: task.thumbnail,
        resolution: task.resolution,
        frameRate: task.frameRate,
        bitrate: task.bitrate,
        status: RecordingStatus.recording,
        startTime: DateTime.now(),
      );

      setState(() {
        _recordingTasks.remove(task);
        _recordingTasks.insert(0, newTask);
      });

      _showMessage('已开始重新录制');
    }
  }

  /// 打开文件所在文件夹
  void _openFileLocation(RecordingTask task) {
    // TODO: 实现打开文件夹功能
    _showMessage('打开文件夹功能待实现');
  }

  /// 预览视频
  void _previewVideo(RecordingTask task) {
    showVideoPreview(context, task.name);
  }

  @override
  Widget build(BuildContext context) {
    return DesktopLayout(
      title: '数据捕获',
      child: Column(
        children: [
          // 控制面板
          _buildControlPanel(),

          const Divider(height: 1),

          // Tabs
          _buildTabBar(),

          // Tab内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildCaptureTab(), _buildRecordingTab(), _buildVideoList(), _buildImageList(), _buildScriptList()],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建控制面板
  Widget _buildControlPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? [const Color(0xFF2E2E2E), const Color(0xFF1E1E1E)] : [const Color(0xFFF8F9FB), const Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 状态指示器和捕获按钮
              Expanded(
                child: Row(
                  children: [
                    // 动画状态指示器
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: _isCapturing ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        boxShadow: _isCapturing ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 12, spreadRadius: 2)] : null,
                      ),
                    ),
                    const SizedBox(width: 12),

                    Text(_isCapturing ? '捕获中' : '开启捕获', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),

                    const SizedBox(width: 24),

                    // 证书状态
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isCertInstalled ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _isCertInstalled ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCertInstalled ? Icons.verified : Icons.warning_amber,
                            size: 16,
                            color: _isCertInstalled ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isCertInstalled ? 'CA证书已安装' : 'CA证书未安装',
                            style: TextStyle(fontSize: 12, color: _isCertInstalled ? Colors.green : Colors.orange, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 右侧控制按钮
              Row(
                children: [
                  // 刷新按钮
                  IconButton.outlined(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await _loadCapturedData();
                      _checkCertificateStatus();
                    },
                    tooltip: '刷新数据',
                  ),

                  const SizedBox(width: 8),

                  // 清除按钮
                  IconButton.outlined(icon: const Icon(Icons.delete_outline), onPressed: _clearData, tooltip: '清除所有数据'),

                  const SizedBox(width: 16),

                  // 证书安装按钮
                  if (!_isCertInstalled)
                    FilledButton.tonalIcon(
                      onPressed: _installCertificate,
                      icon: const Icon(Icons.security),
                      label: const Text('安装CA证书'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                    ),

                  if (!_isCertInstalled) const SizedBox(width: 12),

                  // 开始/停止按钮
                  FilledButton.tonalIcon(
                    onPressed: _toggleCapture,
                    icon: Icon(_isCapturing ? Icons.stop : Icons.play_arrow),
                    label: Text(_isCapturing ? '停止捕获' : '开始捕获'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isCapturing ? Colors.red : Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 端口和格式设置
          if (!_isCapturing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  // 端口选择
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.settings_ethernet, size: 20),
                        const SizedBox(width: 8),
                        const Text('代理端口:'),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<int>(
                            value: _selectedPort,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: [8080, 8433, 8888, 9000].map((port) {
                              return DropdownMenuItem(value: port, child: Text(port.toString()));
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedPort = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  // 录制格式选择
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.video_settings, size: 20),
                        const SizedBox(width: 8),
                        const Text('录制格式:'),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            value: _selectedFormat,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: ['mp4', 'flv', 'ts', 'mkv'].map((format) {
                              return DropdownMenuItem(value: format, child: Text(format.toUpperCase()));
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedFormat = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建Tab栏
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        tabs: const [
          Tab(icon: Icon(Icons.file_download), text: '捕获列表'),
          Tab(icon: Icon(Icons.video_library), text: '录制管理'),
          Tab(icon: Icon(Icons.video_collection), text: '视频'),
          Tab(icon: Icon(Icons.image), text: '图片'),
          Tab(icon: Icon(Icons.code), text: '脚本'),
        ],
      ),
    );
  }

  /// 构建捕获Tab（捕获到的可录制视频列表）
  Widget _buildCaptureTab() {
    return Column(
      children: [
        // 统计和操作栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Row(
            children: [
              StatChip(label: '可录制', count: _availableVideos.length, color: Colors.blue),
              const SizedBox(width: 12),
              StatChip(label: '已选择', count: _availableVideos.where((v) => v.isSelected).length, color: Colors.purple),

              const Spacer(),

              // 全选/取消全选
              TextButton.icon(
                onPressed: () {
                  final allSelected = _availableVideos.every((v) => v.isSelected);
                  setState(() {
                    for (var video in _availableVideos) {
                      video.isSelected = !allSelected;
                    }
                  });
                },
                icon: Icon(_availableVideos.every((v) => v.isSelected) ? Icons.check_box : Icons.check_box_outline_blank),
                label: Text(_availableVideos.every((v) => v.isSelected) ? '取消全选' : '全选'),
              ),

              const SizedBox(width: 12),

              // 开始录制按钮
              FilledButton.icon(
                onPressed: _availableVideos.any((v) => v.isSelected) ? _startRecording : null,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('开始录制'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              ),
            ],
          ),
        ),

        // 视频列表
        Expanded(
          child: _availableVideos.isEmpty
              ? _buildEmptyState('暂无捕获到的视频流', Icons.videocam_off)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _availableVideos.length,
                  itemBuilder: (context, index) {
                    final video = _availableVideos[index];
                    return _buildAvailableVideoCard(video);
                  },
                ),
        ),
      ],
    );
  }

  /// 构建可录制视频卡片
  Widget _buildAvailableVideoCard(RecordingTask video) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          setState(() {
            video.isSelected = !video.isSelected;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 选择框
              Checkbox(
                value: video.isSelected,
                onChanged: (value) {
                  setState(() {
                    video.isSelected = value ?? false;
                  });
                },
              ),

              const SizedBox(width: 12),

              // 缩略图
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 120,
                  height: 68,
                  color: Colors.grey[300],
                  child: video.thumbnail.isNotEmpty
                      ? Image.file(
                          File(video.thumbnail),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.videocam, size: 32);
                          },
                        )
                      : const Icon(Icons.videocam, size: 32),
                ),
              ),

              const SizedBox(width: 16),

              // 视频信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        InfoChip(icon: Icons.aspect_ratio, label: video.resolution, color: Colors.blue),
                        InfoChip(icon: Icons.speed, label: video.frameRate, color: Colors.green),
                        InfoChip(icon: Icons.signal_cellular_alt, label: video.bitrate, color: Colors.orange),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      video.url,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // 操作按钮
              IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => _copyToClipboard(video.url), tooltip: '复制链接'),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建录制Tab（录制任务管理）
  Widget _buildRecordingTab() {
    return Column(
      children: [
        // 录制统计栏
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [const Color(0xFF2E2E2E), const Color(0xFF252525)]
                  : [const Color(0xFFF8F9FB), const Color(0xFFF5F5F5)],
            ),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatCard(label: '录制完毕', value: _completedCount.toString(), color: Colors.green, icon: Icons.check_circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(label: '录制异常', value: _errorCount.toString(), color: Colors.red, icon: Icons.error),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(label: '录制中', value: _recordingCount.toString(), color: Colors.orange, icon: Icons.fiber_manual_record),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: '录制大小',
                      value: '${(_totalRecordingSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                      color: Colors.blue,
                      icon: Icons.storage,
                    ),
                  ),
                ],
              ),

              if (_hasSelectedTasks) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('已选择 ${_recordingTasks.where((t) => t.isSelected).length} 个任务', style: const TextStyle(color: Colors.orange)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _batchDelete,
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('批量删除'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // 录制任务列表
        Expanded(
          child: _recordingTasks.isEmpty
              ? _buildEmptyState('暂无录制任务', Icons.videocam_off)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _recordingTasks.length,
                  itemBuilder: (context, index) {
                    final task = _recordingTasks[index];
                    return _buildRecordingTaskCard(task);
                  },
                ),
        ),
      ],
    );
  }

  /// 构建录制任务卡片
  Widget _buildRecordingTaskCard(RecordingTask task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          if (task.status == RecordingStatus.completed) {
            _previewVideo(task);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 选择框
              Checkbox(
                value: task.isSelected,
                onChanged: (value) {
                  setState(() {
                    task.isSelected = value ?? false;
                  });
                },
              ),

              const SizedBox(width: 12),

              // 缩略图
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 140,
                      height: 79,
                      color: Colors.grey[300],
                      child: task.thumbnail.isNotEmpty
                          ? Image.network(
                              task.thumbnail,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(Icons.videocam, size: 32);
                              },
                            )
                          : const Icon(Icons.videocam, size: 32),
                    ),
                  ),

                  // 状态覆盖层
                  if (task.status == RecordingStatus.recording)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                        child: const Center(child: Icon(Icons.fiber_manual_record, color: Colors.red, size: 32)),
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 16),

              // 任务信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称和状态
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.name,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadgeWidget(task.status),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 参数信息
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        InfoChip(icon: Icons.aspect_ratio, label: task.resolution, color: Colors.blue),
                        InfoChip(icon: Icons.speed, label: task.frameRate, color: Colors.green),
                        InfoChip(icon: Icons.signal_cellular_alt, label: task.bitrate, color: Colors.orange),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 录制进度（录制中）
                    if (task.status == RecordingStatus.recording) ...[
                      LinearProgressIndicator(
                        value: task.progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('${(task.progress * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 12),
                          Text(task.fileSizeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],

                    // 录制统计（已完成）
                    if (task.status == RecordingStatus.completed) ...[
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('时长: ${task.duration}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 12),
                          const Icon(Icons.storage, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('大小: ${task.fileSizeStr}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const SizedBox(width: 12),
                          const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            task.endTime != null
                                ? '${task.endTime!.month}/${task.endTime!.day} ${task.endTime!.hour}:${task.endTime!.minute.toString().padLeft(2, '0')}'
                                : '--',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],

                    // 错误信息
                    if (task.status == RecordingStatus.error && task.errorMessage != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.errorMessage!,
                                style: const TextStyle(fontSize: 11, color: Colors.red),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // 操作按钮
              Column(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: '更多操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _editTaskName(task);
                          break;
                        case 'copy':
                          _copyToClipboard(task.url);
                          break;
                        case 'rerecord':
                          _reRecord(task);
                          break;
                        case 'open':
                          _openFileLocation(task);
                          break;
                        case 'delete':
                          _deleteTask(task);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('修改名称')]),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: Row(children: [Icon(Icons.copy, size: 18), SizedBox(width: 8), Text('复制链接')]),
                      ),
                      if (task.status == RecordingStatus.completed)
                        const PopupMenuItem(
                          value: 'open',
                          child: Row(children: [Icon(Icons.folder_open, size: 18), SizedBox(width: 8), Text('打开文件夹')]),
                        ),
                      if (task.status == RecordingStatus.completed || task.status == RecordingStatus.error)
                        const PopupMenuItem(
                          value: 'rerecord',
                          child: Row(children: [Icon(Icons.refresh, size: 18), SizedBox(width: 8), Text('重新录制')]),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建状态徽章组件
  Widget _buildStatusBadgeWidget(RecordingStatus status) {
    Color color;
    IconData icon;
    String text;

    switch (status) {
      case RecordingStatus.idle:
        color = Colors.grey;
        icon = Icons.pending;
        text = '待录制';
        break;
      case RecordingStatus.recording:
        color = Colors.orange;
        icon = Icons.fiber_manual_record;
        text = '录制中';
        break;
      case RecordingStatus.completed:
        color = Colors.green;
        icon = Icons.check_circle;
        text = '已完成';
        break;
      case RecordingStatus.error:
        color = Colors.red;
        icon = Icons.error;
        text = '录制异常';
        break;
    }

    return StatusBadge(text: text, color: color, icon: icon);
  }

  /// 构建视频列表
  Widget _buildVideoList() {
    return _buildItemList(
      items: _videos,
      emptyMessage: '暂无捕获的视频链接',
      emptyIcon: Icons.videocam_off,
      itemBuilder: (url) => _buildUrlCard(url: url, icon: Icons.video_library, color: Colors.purple),
    );
  }

  /// 构建图片列表
  Widget _buildImageList() {
    return _buildItemList(
      items: _images,
      emptyMessage: '暂无捕获的图片链接',
      emptyIcon: Icons.image_not_supported,
      itemBuilder: (url) => _buildUrlCard(url: url, icon: Icons.image, color: Colors.pink),
    );
  }

  /// 构建脚本列表
  Widget _buildScriptList() {
    final allScripts = [
      ..._jsonData.map((e) => {'type': 'json', 'data': e}),
      ..._javascript.map((e) => {'type': 'js', 'data': e}),
    ];

    return allScripts.isEmpty
        ? _buildEmptyState('暂无捕获的脚本文件', Icons.code_off)
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allScripts.length,
            itemBuilder: (context, index) {
              final script = allScripts[index];
              if (script['type'] == 'json') {
                return _buildJsonCard(script['data'] as String);
              } else {
                return _buildUrlCard(url: script['data'] as String, icon: Icons.javascript, color: Colors.green);
              }
            },
          );
  }

  /// 构建通用列表
  Widget _buildItemList({
    required List<String> items,
    required String emptyMessage,
    required IconData emptyIcon,
    required Widget Function(String) itemBuilder,
  }) {
    if (items.isEmpty) {
      return _buildEmptyState(emptyMessage, emptyIcon);
    }

    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (context, index) => itemBuilder(items[index]));
  }

  /// 构建空状态组件
  Widget _buildEmptyState(String message, IconData icon) {
    return EmptyState(
      message: message,
      icon: icon,
      isCapturing: _isCapturing,
      isCertInstalled: _isCertInstalled,
      onAction: _isCertInstalled ? _toggleCapture : _installCertificate,
    );
  }

  /// 构建URL卡片
  Widget _buildUrlCard({required String url, required IconData icon, required Color color}) {
    return UrlCard(url: url, icon: icon, color: color, onCopy: () => _copyToClipboard(url));
  }

  /// 构建JSON卡片
  Widget _buildJsonCard(String json) {
    return JsonCard(json: json, onCopy: () => _copyToClipboard(json));
  }
}
