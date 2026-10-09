import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:slime_works/components/node/node_switcher_button.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/aliyun_ddns_service.dart';
import 'package:slime_works/core/services/node/node_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/theme/app_viz.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/view_models/aliyun_ddns_viewmodel.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

class AliyunDdnsScreen extends StatefulWidget {
  const AliyunDdnsScreen({super.key});

  @override
  State<AliyunDdnsScreen> createState() => _AliyunDdnsScreenState();
}

class _AliyunDdnsScreenState extends State<AliyunDdnsScreen> with TickerProviderStateMixin {
  late AliyunDdnsViewModel _viewModel;
  late AnimationController _entranceController;
  late Animation<double> _entranceAnimation;
  NodeSettingsService? _nodeService;

  StreamSubscription? _nodeListSub;
  StreamSubscription? _nodeConnectivitySub;
  StreamSubscription? _currentNodeSub;

  @override
  void initState() {
    super.initState();
    _viewModel = Get.put(AliyunDdnsViewModel());
    _nodeService = GetIt.instance.get<NodeSettingsService>();

    _entranceController = AnimationController(
      vsync: this,
      duration: AppMotion.entrance,
    );
    _entranceAnimation = CurvedAnimation(parent: _entranceController, curve: AppMotion.decelerate);

    _nodeListSub = _nodeService!.remoteNodes.listen((_) {
      if (mounted) setState(() {});
    });
    _nodeConnectivitySub = _nodeService!.nodeConnectivity.listen((_) {
      if (mounted) setState(() {});
    });
    _currentNodeSub = _viewModel.currentNodeId.listen((_) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.refreshAll();
      _entranceController.forward();
    });
  }

  @override
  void dispose() {
    _nodeListSub?.cancel();
    _nodeConnectivitySub?.cancel();
    _currentNodeSub?.cancel();
    _entranceController.dispose();
    try {
      Get.delete<AliyunDdnsViewModel>(force: true);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);

    return ScreenChrome(
      data: ScreenChromeData(
        title: '阿里云',
        actions: [
          _buildNodeSwitcher(),
          SizedBox(width: m.kSpace8),
          _buildCheckButton(context, s, m),
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
              _buildEnableBanner(context, s, m),
              SizedBox(height: m.kSpace16),
              _buildIpStatusCard(context, s, m),
              SizedBox(height: m.kSpace16),
              _buildDomainListCard(context, s, m),
              SizedBox(height: m.kSpace16),
              _buildLogCard(context, s, m),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnableBanner(BuildContext context, AppSemantic s, ThemeMetrics m) {
    return Obx(
      () => Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
        decoration: BoxDecoration(
          color: _viewModel.isEnabled.value ? s.success.container : s.surfaceSunken,
          borderRadius: m.radius12,
          border: Border.all(
            color: _viewModel.isEnabled.value ? s.success.containerBorder : s.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace32,
              height: m.kSpace32,
              decoration: BoxDecoration(
                // 未启用时这一格只是"在的"，用悬停水洗而不是把状态色调暗
                color: _viewModel.isEnabled.value ? s.success.container : s.surfaceHover,
                borderRadius: m.radius8,
              ),
              child: DrawIcon(StrokeIcons.cloudSync,
                size: m.iconSize18,
                color: _viewModel.isEnabled.value ? s.success.color : s.textDisabled,
              ),
            ),
            SizedBox(width: m.kSpace12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '域名解析自动更新',
                    style: AppTextStyles.cardTitle(context),
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    _viewModel.isLocal
                        ? (_viewModel.isEnabled.value
                              ? '已启用 - 定时检测IP变化并自动更新'
                              : '已关闭 - 前往设置配置AccessKey后开启')
                        : '远程节点 - 查看远程节点的阿里云DDNS状态',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      height: 1.6,
                      color: s.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _viewModel.isEnabled.value,
              onChanged: _viewModel.isLocal ? (v) => _viewModel.toggleEnabled(v) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIpStatusCard(BuildContext context, AppSemantic s, ThemeMetrics m) {
    final viz = AppVizSet.of(context).sky;

    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: m.radius12,
          border: Border.all(color: s.hairline),
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
                    color: viz.base.withValues(alpha: s.isDark ? 0.18 : 0.12),
                    borderRadius: m.radius6,
                  ),
                  child: DrawIcon(StrokeIcons.public, size: m.iconSize12, color: viz.base),
                ),
                SizedBox(width: m.kSpace8),
                Text(
                  '网络状态',
                  style: AppTextStyles.sectionTitle(context),
                ),
              ],
            ),
            SizedBox(height: m.kSpace12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(m.kSpace12),
              decoration: BoxDecoration(
                color: s.surfaceSunken,
                borderRadius: m.radius8,
              ),
              child: Row(
                children: [
                  DrawIcon(StrokeIcons.language, size: m.iconSize16, color: s.accent),
                  SizedBox(width: m.kSpace10),
                  Text(
                    _viewModel.isLocal ? '本机公网IP' : '节点公网IP',
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      height: 1.6,
                      color: s.textTertiary,
                    ),
                  ),
                  SizedBox(width: m.kSpace8),
                  // IP 是变长内容，放弹性槽里才会在挤的时候截断，不会顶破这一行
                  Expanded(
                    child: Text(
                      _viewModel.currentIp.value.isEmpty ? '未检测' : _viewModel.currentIp.value,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.mono(context, size: m.fontSize13).copyWith(
                        fontWeight: FontWeight.w600,
                        color: _viewModel.currentIp.value.isEmpty ? s.textDisabled : viz.base,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  color: s.surfaceSunken,
                  borderRadius: m.radius8,
                ),
                child: Row(
                  children: [
                    DrawIcon(StrokeIcons.schedule, size: m.iconSize16, color: s.textDisabled),
                    SizedBox(width: m.kSpace10),
                    Text(
                      '上次检查',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize12,
                        height: 1.6,
                        color: s.textTertiary,
                      ),
                    ),
                    SizedBox(width: m.kSpace8),
                    Expanded(
                      child: Text(
                        _viewModel.lastUpdate.value,
                        textAlign: TextAlign.end,
                        style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                          color: s.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                      ? s.danger.container
                      : s.success.container,
                  borderRadius: m.radius8,
                ),
                child: Row(
                  children: [
                    DrawIcon(
                      _viewModel.lastResult.value.contains('失败')
                          ? StrokeIcons.errorOutline
                          : StrokeIcons.checkCircleOutline,
                      size: m.iconSize16,
                      color: _viewModel.lastResult.value.contains('失败')
                          ? s.danger.color
                          : s.success.color,
                    ),
                    SizedBox(width: m.kSpace10),
                    Expanded(
                      child: Text(
                        _viewModel.lastResult.value,
                        style: AppTextStyles.role(
                          context,
                          fontSize: m.fontSize12,
                          height: 1.6,
                          color: s.textSecondary,
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

  Widget _buildDomainListCard(BuildContext context, AppSemantic s, ThemeMetrics m) {
    final viz = AppVizSet.of(context).amber;

    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: m.radius12,
          border: Border.all(color: s.hairline),
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
                    color: viz.base.withValues(alpha: s.isDark ? 0.18 : 0.12),
                    borderRadius: m.radius6,
                  ),
                  child: DrawIcon(StrokeIcons.dns, size: m.iconSize12, color: viz.base),
                ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: Text(
                    '监控域名',
                    style: AppTextStyles.sectionTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_viewModel.isLocal) _buildAddDomainButton(context, s, m),
              ],
            ),
            SizedBox(height: m.kSpace12),
            if (_viewModel.watchDomains.isEmpty)
              _buildEmptyDomainHint(context, s, m)
            else
              ..._viewModel.watchDomains.asMap().entries.map(
                (entry) => _buildDomainItem(context, s, m, entry.key, entry.value),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddDomainButton(BuildContext context, AppSemantic s, ThemeMetrics m) {
    return SizedBox(
      height: m.kSpace24,
      child: TextButton.icon(
        onPressed: () => _showAddDomainDialog(context, m),
        icon: DrawIcon(StrokeIcons.add, size: m.iconSize16),
        label: Text(
          '添加',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            height: 1.2,
            color: s.accentText,
          ),
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: m.kSpace10),
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  Widget _buildEmptyDomainHint(BuildContext context, AppSemantic s, ThemeMetrics m) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: m.kSpace24),
      child: Column(
        children: [
          DrawIcon(
            StrokeIcons.addCircleOutline,
            size: m.iconSize32,
            color: s.textDisabled,
          ),
          SizedBox(height: m.kSpace8),
          Text(
            '点击右上角添加需要监控的域名',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              height: 1.6,
              color: s.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainItem(
    BuildContext context,
    AppSemantic s,
    ThemeMetrics m,
    int index,
    WatchDomain domain,
  ) {
    final viz = AppVizSet.of(context);
    final statusMap = _viewModel.domainStatuses.firstWhereOrNull(
      (row) => row['domain_name'] == domain.domainName && row['rr'] == domain.rr,
    );
    final resolvedIp = statusMap?['resolved_ip'] as String? ?? '';
    final updated = statusMap?['updated'] as bool? ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace8),
      child: Container(
        padding: EdgeInsets.all(m.kSpace12),
        decoration: BoxDecoration(
          color: s.surfaceSunken,
          borderRadius: m.radius8,
        ),
        child: Row(
          children: [
            Container(
              width: m.kSpace24,
              height: m.kSpace24,
              decoration: BoxDecoration(
                color: updated ? s.success.container : s.warning.container,
                borderRadius: m.radius6,
              ),
              child: DrawIcon(
                updated ? StrokeIcons.check : StrokeIcons.language,
                size: m.iconSize14,
                color: updated ? s.success.color : s.warning.color,
              ),
            ),
            SizedBox(width: m.kSpace10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    domain.fullDomain,
                    style: AppTextStyles.rowTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: m.kSpace2),
                  Text(
                    resolvedIp.isEmpty ? '未解析' : '解析IP: $resolvedIp',
                    style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                      color: resolvedIp.isEmpty ? s.textDisabled : viz.sky.base,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
              decoration: BoxDecoration(
                color: s.info.container,
                borderRadius: m.radius4,
              ),
              child: Text(
                domain.recordType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize10,
                  height: 1.5,
                  weight: FontWeight.w600,
                  color: s.info.onContainer,
                ),
              ),
            ),
            SizedBox(width: m.kSpace8),
            if (_viewModel.isLocal)
              IconButton(
                onPressed: () => _showRemoveDomainDialog(context, index, domain),
                icon: DrawIcon(StrokeIcons.close, size: m.iconSize16, color: s.textDisabled),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: m.kSpace24, minHeight: m.kSpace24),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddDomainDialog(BuildContext context, ThemeMetrics m) {
    final domainNameCtrl = TextEditingController();
    final rrCtrl = TextEditingController(text: '@');
    String recordType = 'A';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        // 语义色从弹窗自己的 ctx 解析：主题在弹窗开着的时候切换也能跟着换
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              DrawIcon(
                StrokeIcons.addCircle,
                size: m.iconSize20,
                color: AppSemantic.of(ctx).accent,
              ),
              SizedBox(width: m.kSpace8),
              const Text('添加监控域名'),
            ],
          ),
          content: SizedBox(
            width: scaleW(360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  controller: domainNameCtrl,
                  onTap: () {
                    domainNameCtrl.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: domainNameCtrl.text.length,
                    );
                  },
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
                      child: AppTextField(
                        controller: rrCtrl,
                        onTap: () {
                          rrCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: rrCtrl.text.length,
                          );
                        },
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
                                    child: Text(v, style: AppTextStyles.body(ctx)),
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

  void _showRemoveDomainDialog(BuildContext context, int index, WatchDomain domain) {
    showDialog(
      context: context,
      builder: (ctx) {
        // 移除会动到线上解析记录，确认按钮走 danger 实底 + 反相字
        final s = AppSemantic.of(ctx);
        return AlertDialog(
          title: const Text('移除域名'),
          content: Text('确定移除 ${domain.fullDomain} 的监控？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                _viewModel.removeWatchDomain(index);
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: s.danger.color,
                foregroundColor: s.accentOn,
              ),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogCard(BuildContext context, AppSemantic s, ThemeMetrics m) {
    final viz = AppVizSet.of(context).mint;

    return Obx(
      () => Container(
        padding: EdgeInsets.all(m.kSpace16),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: m.radius12,
          border: Border.all(color: s.hairline),
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
                    color: viz.base.withValues(alpha: s.isDark ? 0.18 : 0.12),
                    borderRadius: m.radius6,
                  ),
                  child: DrawIcon(StrokeIcons.history, size: m.iconSize12, color: viz.base),
                ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: Text(
                    '更新日志',
                    style: AppTextStyles.sectionTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_viewModel.isLocal && _viewModel.logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _viewModel.clearLogs(),
                    icon: DrawIcon(StrokeIcons.deleteOutline, size: m.iconSize14),
                    label: Text(
                      '清空',
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize11,
                        height: 1.2,
                        color: s.accentText,
                      ),
                    ),
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
                    style: AppTextStyles.role(
                      context,
                      fontSize: m.fontSize12,
                      height: 1.6,
                      color: s.textTertiary,
                    ),
                  ),
                ),
              )
            else
              ..._viewModel.logs.reversed
                  .take(15)
                  .map((log) => _buildLogItem(context, s, m, log)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(
    BuildContext context,
    AppSemantic s,
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
          color: success ? s.success.container : s.danger.container,
          borderRadius: m.radius6,
        ),
        child: Row(
          children: [
            DrawIcon(
              success ? StrokeIcons.checkCircle : StrokeIcons.error,
              size: m.iconSize14,
              color: success ? s.success.color : s.danger.color,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$rr.$domain'.replaceAll('@.', ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.role(
                            context,
                            fontSize: m.fontSize12,
                            height: 1.6,
                            weight: FontWeight.w600,
                            color: s.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(width: m.kSpace8),
                      // 时间戳也放进弹性槽而不是裸 Text：裸 Text 拿到的是无限宽约束，
                      // 用户字号拉到 2.0 时它不会截断而是把这一行顶破。
                      Flexible(
                        child: Text(
                          timestamp,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.mono(context, size: m.fontSize10).copyWith(
                            color: s.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: m.kSpace2),
                  if (oldIp.isNotEmpty && oldIp != newIp)
                    Text(
                      '$oldIp → $newIp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.mono(context, size: m.fontSize12).copyWith(
                        color: s.accent,
                      ),
                    )
                  else
                    Text(
                      message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.role(
                        context,
                        fontSize: m.fontSize12,
                        height: 1.6,
                        color: s.textSecondary,
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

  Widget _buildCheckButton(BuildContext context, AppSemantic s, ThemeMetrics m) {
    return Obx(
      () => IconButton(
        onPressed: _viewModel.isChecking.value ? null : () => _viewModel.checkNow(),
        icon: _viewModel.isChecking.value
            ? SizedBox(
                width: m.iconSize18,
                height: m.iconSize18,
                child: CircularProgressIndicator(strokeWidth: AppTheme.metrics.strokeRegular, color: s.accent),
              )
            : DrawIcon(StrokeIcons.sync, size: m.iconSize20),
        tooltip: '立即检查',
      ),
    );
  }

  Widget _buildNodeSwitcher() {
    if (_nodeService == null) return const SizedBox.shrink();

    return Obx(
      () => NodeSwitcherButton(
        nodeService: _nodeService!,
        currentNodeId: _viewModel.currentNodeId.value,
        availabilityChecker: (baseUrl) => _viewModel.checkNodeAliyunAvailable(baseUrl),
        onNodeSelected: (nodeId) => _viewModel.switchNode(nodeId),
      ),
    );
  }
}
