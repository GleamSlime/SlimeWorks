import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slime_works/components/window/desktop_layout.dart';
import 'package:slime_works/src/rust/api/capture.dart';

/// 数据捕获页面
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isCapturing = false;
  int _selectedPort = 8433;
  Timer? _refreshTimer;

  List<String> _videos = [];
  List<String> _images = [];
  List<String> _jsonData = [];
  List<String> _javascript = [];

  CaptureStats? _stats;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCapturedData();
    _checkProxyStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 检查代理运行状态
  void _checkProxyStatus() {
    setState(() {
      _isCapturing = isProxyRunning();
    });
  }

  /// 加载捕获的数据
  void _loadCapturedData() {
    setState(() {
      _videos = getCapturedVideos();
      _images = getCapturedImages();
      _jsonData = getCapturedJson();
      _javascript = getCapturedJavascript();
      _stats = getCaptureStats();
    });
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
        // 开始捕获 - macOS 需要先安装证书
        if (Platform.isMacOS) {
          // 先检查证书是否已安装
          bool certInstalled = false;
          try {
            certInstalled = isCaCertificateInstalled();
          } catch (e) {
            // 检查失败，假设未安装
            certInstalled = false;
          }

          // 如果证书未安装，提示输入密码进行安装
          if (!certInstalled) {
            final password = await _showPasswordDialog();
            if (password == null || password.isEmpty) {
              _showMessage('已取消', isError: true);
              return;
            }

            try {
              final certResult = installCaCertificate(password: password);
              _showMessage(certResult);
            } catch (e) {
              _showMessage('证书安装失败: $e', isError: true);
              return;
            }
          } else {
            // 证书已安装，无需输入密码
            print('[证书] CA证书已安装，跳过密码输入');
          }
        }

        // 启动代理
        final result = startCaptureProxy(port: _selectedPort);
        _showMessage(result);

        // 启动定时刷新（每2秒刷新一次数据）
        _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
          if (mounted) {
            _loadCapturedData();
          }
        });
      }
      _checkProxyStatus();
    } catch (e) {
      _showMessage('操作失败: $e', isError: true);
    }
  }

  /// 显示密码输入对话框
  Future<String?> _showPasswordDialog() async {
    final passwordController = TextEditingController(text: '');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(children: [Icon(Icons.security, size: 24), SizedBox(width: 8), Text('安装CA证书')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('需要管理员密码来安装CA证书到系统钥匙串。'),
            const SizedBox(height: 8),
            const Text('这是HTTPS流量捕获所必需的步骤。', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '管理员密码', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, passwordController.text), child: const Text('确定')),
        ],
      ),
    );
  }

  /// 显示消息
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green, behavior: SnackBarBehavior.floating));
  }

  /// 清除所有数据
  void _clearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要清除所有捕获的数据吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              clearCapturedData();
              _loadCapturedData();
              Navigator.pop(context);
              _showMessage('数据已清除');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 复制到剪贴板
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showMessage('已复制到剪贴板');
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

          // 统计信息
          _buildStatsBar(),

          const Divider(height: 1),

          // Tabs
          _buildTabBar(),

          // Tab内容
          Expanded(
            child: TabBarView(controller: _tabController, children: [_buildVideoList(), _buildImageList(), _buildJsonList(), _buildJavascriptList()]),
          ),
        ],
      ),
    );
  }

  /// 构建控制面板
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          // 状态指示器
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _isCapturing ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: _isCapturing ? [BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)] : null,
            ),
          ),
          const SizedBox(width: 12),

          Text(_isCapturing ? '捕获中...' : '未启动', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),

          const SizedBox(width: 24),

          // 端口选择
          if (!_isCapturing) ...[
            const Text('端口:'),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
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
            const SizedBox(width: 16),
          ],

          const Spacer(),

          // 刷新按钮
          IconButton.outlined(icon: const Icon(Icons.refresh), onPressed: _loadCapturedData, tooltip: '刷新数据'),

          const SizedBox(width: 8),

          // 清除按钮
          IconButton.outlined(icon: const Icon(Icons.delete_outline), onPressed: _clearData, tooltip: '清除所有数据'),

          const SizedBox(width: 16),

          // 开始/停止按钮
          FilledButton.icon(
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
    );
  }

  /// 构建统计栏
  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildStatChip('总计', _stats?.total ?? 0, Colors.blue),
          const SizedBox(width: 12),
          _buildStatChip('视频', _stats?.videos ?? 0, Colors.purple),
          const SizedBox(width: 12),
          _buildStatChip('图片', _stats?.images ?? 0, Colors.pink),
          const SizedBox(width: 12),
          _buildStatChip('JSON', _stats?.json ?? 0, Colors.orange),
          const SizedBox(width: 12),
          _buildStatChip('JS', _stats?.javascript ?? 0, Colors.green),
        ],
      ),
    );
  }

  /// 构建统计芯片
  Widget _buildStatChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
      label: Text(label),
      side: BorderSide(color: color.withOpacity(0.3)),
      backgroundColor: color.withOpacity(0.1),
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
        tabs: const [
          Tab(icon: Icon(Icons.video_library), text: '视频'),
          Tab(icon: Icon(Icons.image), text: '图片'),
          Tab(icon: Icon(Icons.code), text: 'JSON'),
          Tab(icon: Icon(Icons.javascript), text: 'JavaScript'),
        ],
      ),
    );
  }

  /// 构建视频列表
  Widget _buildVideoList() {
    return _buildItemList(
      items: _videos,
      emptyMessage: '暂无捕获的视频链接',
      itemBuilder: (url) => _buildUrlCard(url: url, icon: Icons.video_library, color: Colors.purple),
    );
  }

  /// 构建图片列表
  Widget _buildImageList() {
    return _buildItemList(
      items: _images,
      emptyMessage: '暂无捕获的图片链接',
      itemBuilder: (url) => _buildUrlCard(url: url, icon: Icons.image, color: Colors.pink),
    );
  }

  /// 构建JSON列表
  Widget _buildJsonList() {
    return _buildItemList(items: _jsonData, emptyMessage: '暂无捕获的JSON数据', itemBuilder: (json) => _buildJsonCard(json));
  }

  /// 构建JavaScript列表
  Widget _buildJavascriptList() {
    return _buildItemList(
      items: _javascript,
      emptyMessage: '暂无捕获的JavaScript链接',
      itemBuilder: (url) => _buildUrlCard(url: url, icon: Icons.javascript, color: Colors.green),
    );
  }

  /// 构建通用列表
  Widget _buildItemList({required List<String> items, required String emptyMessage, required Widget Function(String) itemBuilder}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Theme.of(context).hintColor),
            const SizedBox(height: 16),
            Text(emptyMessage, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
          ],
        ),
      );
    }

    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (context, index) => itemBuilder(items[index]));
  }

  /// 构建URL卡片
  Widget _buildUrlCard({required String url, required IconData icon, required Color color}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () => _copyToClipboard(url), tooltip: '复制'),
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: () {
                // TODO: 打开URL
              },
              tooltip: '打开',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建JSON卡片
  Widget _buildJsonCard(String json) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.1),
          child: const Icon(Icons.code, color: Colors.orange, size: 20),
        ),
        title: Text(json.length > 50 ? '${json.substring(0, 50)}...' : json, maxLines: 1, overflow: TextOverflow.ellipsis),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(icon: const Icon(Icons.copy, size: 18), label: const Text('复制'), onPressed: () => _copyToClipboard(json)),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
