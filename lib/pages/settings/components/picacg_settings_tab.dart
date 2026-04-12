import 'package:flutter/material.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/picacg_service.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/pages/picacg/components/picacg_login_dialog.dart';

const String _kDefaultCdnIp = '104.18.227.172';

/// PicACG 设置 Tab
///
/// 包含：
/// - 账号状态 / 登录 / 登出
/// - API 分流选择（直连 / 分流2 / 分流3 / US反代1 / US反代2 / 自定义IP）
/// - 代理设置（无代理 / HTTP / SOCKS5）
/// - 图片服务器选择
class PicAcgSettingsTab extends StatefulWidget {
  const PicAcgSettingsTab({super.key});

  @override
  State<PicAcgSettingsTab> createState() => _PicAcgSettingsTabState();
}

class _PicAcgSettingsTabState extends State<PicAcgSettingsTab> {
  late final PicAcgService _service = getIt<PicAcgService>();

  PicAcgChannelMode _channel = PicAcgChannelMode.direct;
  final TextEditingController _customIpCtrl = TextEditingController();
  final TextEditingController _relayAddrCtrl = TextEditingController();
  final TextEditingController _proxyCtrl = TextEditingController();

  String _imageServer = 'storage1.picacomic.com';
  bool _loading = true;

  /// 每个节点的测速结果：null=未测，-1=测速中，-2=不可达，>=0=延迟ms
  final Map<PicAcgChannelMode, int?> _latencyMap = {};
  bool _testingAll = false;

  static const List<String> _imageServers = [
    'storage1.picacomic.com',
    's3.picacomic.com',
    's2.picacomic.com',
    'storage-b.picacomic.com',
    'storage.diwodiwo.xyz',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final channel = await _service.getSavedChannel();
    final customIp = await _service.getSavedCustomIp();
    final proxy = await _service.getSavedProxy();
    final imageServer = await _service.getSavedImageServer();
    if (!mounted) return;
    // lanRelay 模式的中转地址存储在 customIp 字段
    final relayAddr = (channel == PicAcgChannelMode.lanRelay) ? customIp : '';
    setState(() {
      _channel = channel;
      _customIpCtrl.text = (channel == PicAcgChannelMode.cdnIp && customIp.isNotEmpty)
          ? customIp
          : _kDefaultCdnIp;
      _relayAddrCtrl.text = relayAddr;
      _proxyCtrl.text = proxy;
      _imageServer = imageServer.isEmpty ? 'storage1.picacomic.com' : imageServer;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _customIpCtrl.dispose();
    _relayAddrCtrl.dispose();
    _proxyCtrl.dispose();
    super.dispose();
  }

  Future<void> _applyChannel(PicAcgChannelMode mode) async {
    if (mode == PicAcgChannelMode.cdnIp && _customIpCtrl.text.trim().isEmpty) {
      _customIpCtrl.text = _kDefaultCdnIp;
    }
    setState(() => _channel = mode);
    final customIp = mode == PicAcgChannelMode.lanRelay
        ? _relayAddrCtrl.text.trim()
        : _customIpCtrl.text.trim();
    await _service.setChannel(mode, customIp: customIp);
  }

  /// 测速全部节点（并行）
  Future<void> _testAll() async {
    if (_testingAll) return;
    setState(() {
      _testingAll = true;
      for (final m in PicAcgChannelMode.values) {
        _latencyMap[m] = -1; // 测速中
      }
    });

    for (final mode in PicAcgChannelMode.values) {
      final customIp = mode == PicAcgChannelMode.lanRelay
          ? _relayAddrCtrl.text.trim()
          : _customIpCtrl.text.trim();
      try {
        final ms = await _service.testChannel(mode, customIp: customIp);
        if (mounted) setState(() => _latencyMap[mode] = ms);
      } catch (_) {
        if (mounted) setState(() => _latencyMap[mode] = -2); // 不可达
      }
      // 避免并发打满风控，节点间微小间隔
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
    }
    if (mounted) setState(() => _testingAll = false);
  }

  Future<void> _applyProxy() async {
    await _service.setProxy(_proxyCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('代理已保存'), duration: Duration(seconds: 1)));
  }

  Future<void> _applyImageServer(String server) async {
    setState(() => _imageServer = server);
    await _service.setImageServer(server);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace16),
      children: [
        // ─── 账号 ─────────────────────────────────────────────
        _SectionTitle('账号'),
        _AccountCard(service: _service, onChanged: () => setState(() {})),

        SizedBox(height: m.kSpace20),

        // ─── API 分流 ──────────────────────────────────────────
        _SectionTitle('API 分流'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(m.kSpace12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行：说明 + 全部测速按钮
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '分流通过 IP 直连或反向代理绕过 DNS 封锁，使用分流时通常无需设置代理。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    SizedBox(width: m.kSpace8),
                    OutlinedButton.icon(
                      icon: _testingAll
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.speed, size: 16),
                      label: const Text('全部测速'),
                      onPressed: _testingAll ? null : _testAll,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: m.kSpace8),
                // 每个节点 radio + 测速结果
                for (final mode in PicAcgChannelMode.values)
                  _ChannelRadioTile(
                    mode: mode,
                    groupValue: _channel,
                    latency: _latencyMap[mode],
                    onChanged: _applyChannel,
                  ),
                // CDN分流 自定义 IP 输入框
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _channel == PicAcgChannelMode.cdnIp
                      ? Padding(
                          padding: EdgeInsets.only(top: m.kSpace8, left: m.kSpace32),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _customIpCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'CDN IP 地址',
                                    hintText: _kDefaultCdnIp,
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              SizedBox(width: m.kSpace8),
                              FilledButton.tonal(
                                onPressed: () => _applyChannel(PicAcgChannelMode.cdnIp),
                                child: const Text('应用'),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // PC 中转 地址输入框
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _channel == PicAcgChannelMode.lanRelay
                      ? Padding(
                          padding: EdgeInsets.only(top: m.kSpace8, left: m.kSpace32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _relayAddrCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'PC 节点地址',
                                        hintText: '192.168.1.x:17888',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: m.kSpace8),
                                  FilledButton.tonal(
                                    onPressed: () => _applyChannel(PicAcgChannelMode.lanRelay),
                                    child: const Text('应用'),
                                  ),
                                ],
                              ),
                              SizedBox(height: m.kSpace8),
                              Text(
                                '需先在 PC 端《设置 → 节点服务》中启动节点，'
                                '端口默认 17888。移动端所有请求将经由 PC 分流代为获取。',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: m.kSpace20),

        // ─── 代理 ──────────────────────────────────────────────
        _SectionTitle('代理（使用分流时通常无需设置）'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(m.kSpace12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '支持 HTTP 代理（http://host:port）或 SOCKS5 代理（socks5://host:port）。'
                  '清空后保存以禁用代理。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: m.kSpace12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proxyCtrl,
                        decoration: const InputDecoration(
                          labelText: '代理地址',
                          hintText: 'http://127.0.0.1:7890',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(width: m.kSpace8),
                    FilledButton.tonal(onPressed: _applyProxy, child: const Text('保存')),
                  ],
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: m.kSpace20),

        // ─── 图片服务器 ─────────────────────────────────────────
        _SectionTitle('图片服务器'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(m.kSpace12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当某个服务器访问缓慢时可以切换。通常 storage1 或 s3 速度较快。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: m.kSpace8),
                for (final server in _imageServers)
                  RadioListTile<String>(
                    title: Text(server),
                    value: server,
                    groupValue: _imageServer,
                    dense: true,
                    onChanged: (v) => v != null ? _applyImageServer(v) : null,
                  ),
              ],
            ),
          ),
        ),

        SizedBox(height: m.kSpace20),
      ],
    );
  }
}

// ─── 账号卡片 ─────────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final PicAcgService service;
  final VoidCallback onChanged;

  const _AccountCard({required this.service, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;

    if (service.isLoggedIn) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
          ),
          title: Text(service.currentUser?.name ?? '已登录'),
          subtitle: Text(
            'Lv.${service.currentUser?.level ?? 0}  ·  ${service.currentUser?.email ?? ''}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: TextButton.icon(
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('退出'),
            onPressed: () async {
              await service.logout();
              onChanged();
            },
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace4),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(m.kSpace12),
        child: Row(
          children: [
            const Icon(Icons.account_circle_outlined, size: 40),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Text(
                '尚未登录',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.login, size: 16),
              label: const Text('登录'),
              onPressed: () async {
                final ok = await showPicAcgLoginDialog(context);
                if (ok) onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 分流单选项 ───────────────────────────────────────────────────────────────

class _ChannelRadioTile extends StatelessWidget {
  final PicAcgChannelMode mode;
  final PicAcgChannelMode groupValue;
  final int? latency; // null=未测, -1=测速中, -2=不可达, >=0=ms
  final ValueChanged<PicAcgChannelMode> onChanged;

  const _ChannelRadioTile({
    required this.mode,
    required this.groupValue,
    required this.onChanged,
    this.latency,
  });

  static const _subtitles = {
    PicAcgChannelMode.direct: '标准 DNS 解析，网络环境良好时使用',
    PicAcgChannelMode.channel2: 'IP 直连 104.21.91.145（Cloudflare 节点，推荐）',
    PicAcgChannelMode.channel3: 'IP 直连 188.114.98.153（Cloudflare 节点）',
    PicAcgChannelMode.cdnIp: '自定义 CDN IP，可填入获取的节点地址',
    PicAcgChannelMode.jpProxy: '反代节点 bika-api.jpacg.cc（JP）',
    PicAcgChannelMode.usProxy: '反代节点 bika2-api.jpacg.cc（US）',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? trailing;
    if (latency == -1) {
      trailing = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (latency == -2) {
      trailing = Text('不可达', style: TextStyle(color: theme.colorScheme.error, fontSize: 12));
    } else if (latency != null && latency! >= 0) {
      final color = latency! < 300
          ? Colors.green
          : latency! < 800
          ? Colors.orange
          : theme.colorScheme.error;
      trailing = Text(
        '${latency}ms',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      );
    }

    return RadioListTile<PicAcgChannelMode>(
      title: Text(mode.label),
      subtitle: Text(_subtitles[mode] ?? ''),
      value: mode,
      groupValue: groupValue,
      dense: true,
      secondary: trailing,
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }
}

// ─── Section 标题 ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── 测速按钮 ──────────────────────────────────────────────────────────────────

/// 右上角测速按钮 + 结果徽章（已废弃，保留为空避免编译错误）
// ignore_for_file: unused_element
