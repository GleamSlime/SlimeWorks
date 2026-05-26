import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/theme/app_colors.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/aliyun_ddns_viewmodel.dart';

class AliyunDdnsScreen extends StatefulWidget {
  const AliyunDdnsScreen({super.key});

  @override
  State<AliyunDdnsScreen> createState() => _AliyunDdnsScreenState();
}

class _AliyunDdnsScreenState extends State<AliyunDdnsScreen> with TickerProviderStateMixin {
  late AliyunDdnsViewModel _viewModel;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;

  @override
  void initState() {
    super.initState();
    _viewModel = Get.put(AliyunDdnsViewModel());

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.refreshStatus();
      _viewModel.refreshLogs();
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    try {
      Get.delete<AliyunDdnsViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final theme = Theme.of(context);

    return ScreenChrome(
      data: ScreenChromeData(
        title: '阿里云',
        actions: [
          _buildCheckButton(context, theme, m),
          SizedBox(width: m.kSpace8),
        ],
      ),
      child: FadeTransition(
        opacity: _entranceAnimation,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEnableBanner(context, theme, m),
              SizedBox(height: m.kSpace16),
              _buildIpStatusCard(context, theme, m),
              SizedBox(height: m.kSpace16),
              _buildDomainListCard(context, theme, m),
              SizedBox(height: m.kSpace16),
              _buildLogCard(context, theme, m),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnableBanner(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Obx(
      () => Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
        decoration: BoxDecoration(
          color: _viewModel.isEnabled.value
              ? LightColors.success.withAlpha(15)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
          borderRadius: m.radius12,
          border: Border.all(
            color: _viewModel.isEnabled.value
                ? LightColors.success.withAlpha(40)
                : theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                color: _viewModel.isEnabled.value
                    ? LightColors.success.withAlpha(25)
                    : theme.colorScheme.onSurface.withAlpha(10),
                borderRadius: m.radius8,
              ),
              child: Icon(
                Icons.cloud_sync_rounded,
                size: m.iconSize18,
                color: _viewModel.isEnabled.value
                    ? LightColors.success
                    : theme.colorScheme.onSurface.withAlpha(60),
              ),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '域名解析自动更新',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    _viewModel.isEnabled.value ? '已启用 - 定时检测IP变化并自动更新' : '已关闭 - 前往设置配置AccessKey后开启',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _viewModel.isEnabled.value,
              onChanged: (v) => _viewModel.toggleEnabled(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIpStatusCard(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace24,
                  height: m.kSpace24,
                  decoration: BoxDecoration(
                    color: LightColors.blue.withAlpha(20),
                    borderRadius: m.radius6,
                  ),
                  child: Icon(Icons.public_rounded, size: m.iconSize12, color: LightColors.blue),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '网络状态',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.kSpace12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                borderRadius: m.radius8,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: m.iconSize16,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: m.kSpace10),
                  Text(
                    '本机公网IP',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _viewModel.currentIp.value.isEmpty ? '未检测' : _viewModel.currentIp.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: _viewModel.currentIp.value.isEmpty
                          ? theme.colorScheme.onSurface.withAlpha(60)
                          : LightColors.blue,
                    ),
                  ),
                ],
              ),
            ),
            if (_viewModel.lastUpdate.value.isNotEmpty) ...[
              SizedBox(height: m.kSpace8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(m.kSpace12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: m.radius8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: m.iconSize16,
                      color: theme.colorScheme.onSurface.withAlpha(80),
                    ),
                    SizedBox(width: m.kSpace10),
                    Text(
                      '上次检查',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _viewModel.lastUpdate.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_viewModel.lastResult.value.isNotEmpty) ...[
              SizedBox(height: m.kSpace8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(m.kSpace12),
                decoration: BoxDecoration(
                  color: _viewModel.lastResult.value.contains('失败')
                      ? LightColors.red.withAlpha(8)
                      : LightColors.success.withAlpha(8),
                  borderRadius: m.radius8,
                ),
                child: Row(
                  children: [
                    Icon(
                      _viewModel.lastResult.value.contains('失败')
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: m.iconSize16,
                      color: _viewModel.lastResult.value.contains('失败')
                          ? LightColors.red
                          : LightColors.success,
                    ),
                    SizedBox(width: m.kSpace10),
                    Expanded(
                      child: Text(
                        _viewModel.lastResult.value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        ),
                        maxLines: 2,
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
    );
  }

  Widget _buildDomainListCard(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace24,
                  height: m.kSpace24,
                  decoration: BoxDecoration(
                    color: LightColors.orange.withAlpha(20),
                    borderRadius: m.radius6,
                  ),
                  child: Icon(Icons.dns_rounded, size: m.iconSize12, color: LightColors.orange),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '监控域名',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _buildAddDomainButton(context, theme, m),
              ],
            ),
            SizedBox(height: m.kSpace12),
            if (_viewModel.watchDomains.isEmpty)
              _buildEmptyDomainHint(context, theme, m)
            else
              ..._viewModel.watchDomains.asMap().entries.map(
                (entry) => _buildDomainItem(context, theme, m, entry.key, entry.value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddDomainButton(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return SizedBox(
      height: m.kSpace24,
      child: TextButton.icon(
        onPressed: () => _showAddDomainDialog(context, theme, m),
        icon: Icon(Icons.add_rounded, size: m.iconSize16),
        label: Text('添加', style: TextStyle(fontSize: m.fontSize12)),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  Widget _buildEmptyDomainHint(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: m.kSpace24),
      child: Column(
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            size: m.iconSize32,
            color: theme.colorScheme.onSurface.withAlpha(30),
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '点击右上角添加需要监控的域名',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainItem(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    int index,
    WatchDomain domain,
  ) {
    final statusMap = _viewModel.domainStatuses.firstWhereOrNull(
      (s) => s['domain_name'] == domain.domainName && s['rr'] == domain.rr,
    );
    final resolvedIp = statusMap?['resolved_ip'] as String? ?? '';
    final updated = statusMap?['updated'] as bool? ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace8),
      child: Container(
        padding: EdgeInsets.all(m.kSpace12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: m.radius8,
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace24,
              height: m.kSpace24,
              decoration: BoxDecoration(
                color: updated
                    ? LightColors.success.withAlpha(20)
                    : LightColors.orange.withAlpha(15),
                borderRadius: m.radius6,
              ),
              child: Icon(
                updated ? Icons.check_rounded : Icons.language_rounded,
                size: m.iconSize14,
                color: updated ? LightColors.success : LightColors.orange,
              ),
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    domain.fullDomain,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    resolvedIp.isEmpty ? '未解析' : '解析IP: $resolvedIp',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: resolvedIp.isEmpty
                          ? theme.colorScheme.onSurface.withAlpha(60)
                          : LightColors.blue,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
              decoration: BoxDecoration(
                color: LightColors.purple.withAlpha(15),
                borderRadius: m.radius4,
              ),
              child: Text(
                domain.recordType,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: m.fontSize10,
                  color: LightColors.purple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: m.kSpace8),
            IconButton(
              onPressed: () => _showRemoveDomainDialog(context, theme, m, index, domain),
              icon: Icon(
                Icons.close_rounded,
                size: m.iconSize16,
                color: theme.colorScheme.onSurface.withAlpha(40),
              ),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(minWidth: m.kSpace24, minHeight: m.kSpace24),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDomainDialog(BuildContext context, ThemeData theme, ThemeMetrics m) {
    final domainNameCtrl = TextEditingController();
    final rrCtrl = TextEditingController(text: '@');
    String recordType = 'A';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle_rounded, size: m.iconSize20, color: theme.colorScheme.primary),
              SizedBox(width: m.kSpace8),
              const Text('添加监控域名'),
            ],
          ),
          content: SizedBox(
            width: scaleW(360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: domainNameCtrl,
                  decoration: const InputDecoration(
                    labelText: '主域名',
                    hintText: 'example.com',
                    isDense: true,
                  ),
                ),
                SizedBox(height: m.kSpace12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rrCtrl,
                        decoration: const InputDecoration(
                          labelText: '子域名(RR)',
                          hintText: '@ 或 www',
                          isDense: true,
                        ),
                      ),
                    ),
                    SizedBox(width: m.kSpace12),
                    SizedBox(
                      width: scaleW(80),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: '类型', isDense: true),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: recordType,
                            isDense: true,
                            isExpanded: true,
                            items: ['A', 'AAAA', 'CNAME']
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text(v, style: theme.textTheme.bodyMedium),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setDialogState(() => recordType = v);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                if (domainNameCtrl.text.trim().isEmpty) return;
                _viewModel.addWatchDomain(
                  WatchDomain(
                    domainName: domainNameCtrl.text.trim(),
                    rr: rrCtrl.text.trim().isEmpty ? '@' : rrCtrl.text.trim(),
                    recordType: recordType,
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveDomainDialog(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    int index,
    WatchDomain domain,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除域名'),
        content: Text('确定移除 ${domain.fullDomain} 的监控？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              _viewModel.removeWatchDomain(index);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: LightColors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: m.radius12,
          border: Border.all(color: theme.dividerColor.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: m.kSpace24,
                  height: m.kSpace24,
                  decoration: BoxDecoration(
                    color: LightColors.mint.withAlpha(20),
                    borderRadius: m.radius6,
                  ),
                  child: Icon(Icons.history_rounded, size: m.iconSize12, color: LightColors.mint),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '更新日志',
                  style: TextStyle(
                    fontSize: m.fontSize15,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_viewModel.logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _viewModel.clearLogs(),
                    icon: Icon(Icons.delete_outline_rounded, size: m.iconSize14),
                    label: Text('清空', style: TextStyle(fontSize: m.fontSize11)),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: m.kSpace8),
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            if (_viewModel.logs.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: m.kSpace16),
                child: Center(
                  child: Text(
                    '暂无日志',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(60),
                    ),
                  ),
                ),
              )
            else
              ..._viewModel.logs.reversed
                  .take(15)
                  .map((log) => _buildLogItem(context, theme, m, log)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(
    BuildContext context,
    ThemeData theme,
    ThemeMetrics m,
    Map<String, dynamic> log,
  ) {
    final success = log['success'] as bool? ?? false;
    final timestamp = log['timestamp'] as String? ?? '';
    final domain = log['domain'] as String? ?? '';
    final rr = log['rr'] as String? ?? '';
    final oldIp = log['old_ip'] as String? ?? '';
    final newIp = log['new_ip'] as String? ?? '';
    final message = log['message'] as String? ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace6),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace8),
        decoration: BoxDecoration(
          color: success ? LightColors.success.withAlpha(6) : LightColors.red.withAlpha(6),
          borderRadius: m.radius6,
        ),
        child: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_rounded,
              size: m.iconSize14,
              color: success ? LightColors.success : LightColors.red,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '$rr.$domain'.replaceAll('@.', ''),
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        timestamp,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: m.fontSize10,
                          color: theme.colorScheme.onSurface.withAlpha(80),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  if (oldIp.isNotEmpty && oldIp != newIp)
                    Text(
                      '$oldIp → $newIp',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckButton(BuildContext context, ThemeData theme, ThemeMetrics m) {
    return Obx(
      () => IconButton(
        onPressed: _viewModel.isChecking.value ? null : () => _viewModel.checkNow(),
        icon: _viewModel.isChecking.value
            ? SizedBox(
                width: m.iconSize18,
                height: m.iconSize18,
                child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
              )
            : Icon(Icons.sync_rounded, size: m.iconSize20),
        tooltip: '立即检查',
      ),
    );
  }
}
