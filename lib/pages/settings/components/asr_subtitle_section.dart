import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:slime_works/core/provider/main.dart';
import 'package:slime_works/core/services/asr/asr_models.dart';
import 'package:slime_works/core/services/asr/asr_settings_service.dart';
import 'package:slime_works/core/theme/app_motion.dart';
import 'package:slime_works/core/theme/app_semantics.dart';
import 'package:slime_works/core/theme/app_theme.dart';
import 'package:slime_works/core/utils/size_utils.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 资源库设置 —— 语音识别字幕分区
///
/// 三块能力：内网大模型地址列表管理（优先）、本地 SenseVoice 引擎一键部署（其次）、
/// 内网 NMT 字幕翻译（日韩原文 → 中文，供二次审核标注）
class AsrSubtitleSection extends StatelessWidget {
  const AsrSubtitleSection({super.key});

  AsrSettingsService get _settings => getIt<AsrSettingsService>();

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Header(title: '语音识别字幕'),
        SizedBox(height: m.kSpace12),
        _Card(child: _buildEnginePriority(context)),
        SizedBox(height: m.kSpace12),
        _Card(child: _buildDefaultLanguage(context)),
        SizedBox(height: m.kSpace12),
        _Card(child: _buildRemoteServerList(context)),
        if (_settings.supportsLocalEngine) ...[
          SizedBox(height: m.kSpace12),
          _Card(child: _buildLocalEngine(context)),
        ],
        SizedBox(height: m.kSpace12),
        _Card(child: _buildTranslateSection(context)),
      ],
    );
  }

  // ── 默认识别语言 ───────────────────────────────────────────────────────────

  Widget _buildDefaultLanguage(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('默认识别语言', style: AppTextStyles.cardTitle(context)),
        SizedBox(height: m.kSpace4),
        Text(
          '自动检测对日语、韩语素材经常判错，输出的字幕会混进中文或日文假名。按素材语言指定可明显改善，右键「识别字幕」的子菜单也会记住这里的选择。',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            color: s.textTertiary,
            height: 1.6,
          ),
        ),
        SizedBox(height: m.kSpace8),
        Obx(() => Wrap(
          spacing: m.kSpace8,
          runSpacing: m.kSpace6,
          children: [
            for (final option in kAsrLanguages)
              ChoiceChip(
                label: Text(option.label),
                selected: _settings.defaultLanguage.value == option.code,
                onSelected: (_) => _settings.setDefaultLanguage(option.code),
              ),
          ],
        )),
      ],
    );
  }

  // ── 引擎优先级 ────────────────────────────────────────────────────────────

  Widget _buildEnginePriority(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final prefer = _settings.preferRemote.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('优先使用内网大模型', style: AppTextStyles.cardTitle(context)),
              ),
              Switch(value: prefer, onChanged: (v) => _settings.setPreferRemote(v)),
            ],
          ),
          Text(
            prefer
                ? '识别字幕时先请求下方列表里可用的内网服务，全部不可用再回退本地引擎。'
                : '跳过内网服务，直接使用本地 SenseVoice 引擎识别。',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              color: s.textTertiary,
              height: 1.6,
            ),
          ),
          if (!prefer && !_settings.supportsLocalEngine) ...[
            SizedBox(height: m.kSpace6),
            Text(
              '当前平台没有本地引擎，关闭后无法识别字幕。',
              // 配置后果告警：走 warning 而不是 error，error 只留给真正失败的状态
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.warning.color,
                height: 1.6,
              ),
            ),
          ],
        ],
      );
    });
  }

  // ── 内网大模型列表 ─────────────────────────────────────────────────────────

  Widget _buildRemoteServerList(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('内网大模型服务', style: AppTextStyles.cardTitle(context))),
            Obx(() {
              final online = _settings.servers.where((s) => s.enabled && s.isAvailable).length;
              if (online == 0) return const SizedBox.shrink();
              // 行尾计数会跟着用户字号变长，给 Flexible + 省略号封顶，不许顶破整行
              return Flexible(
                child: Text(
                  '$online 个在线',
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            SizedBox(width: m.kSpace8),
            TextButton.icon(
              onPressed: () => _addServer(context),
              icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
              label: const Text('新建'),
            ),
          ],
        ),
        Text(
          '支持 OpenAI 兼容的 /v1/audio/transcriptions 接口（如 faster-whisper、whisper.cpp server）。列表越靠前优先级越高。',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            color: s.textTertiary,
            height: 1.6,
          ),
        ),
        SizedBox(height: m.kSpace8),
        Obx(() {
          if (_settings.servers.isEmpty) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: m.kSpace12),
              child: Text(
                '尚未配置内网服务，可点击"新建"添加，或直接使用本地引擎。',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  color: s.textTertiary,
                  height: 1.6,
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final server in _settings.servers) _buildServerTile(context, server),
              SizedBox(height: m.kSpace8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _testAll(context),
                  icon: DrawIcon(StrokeIcons.wifiFind, size: m.iconSize14),
                  label: const Text('测试全部'),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildServerTile(BuildContext context, AsrServer server) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final online = server.enabled && server.isAvailable;
    // 状态点三色：停用=中性、在线=成功、离线=危险
    final statusRole = !server.enabled ? s.neutral : (online ? s.success : s.danger);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        children: [
          Container(
            width: m.kSpace8,
            height: m.kSpace8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusRole.color,
            ),
          ),
          SizedBox(width: m.kSpace10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: AppTextStyles.rowTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${server.url}  ·  ${server.model}',
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: server.enabled,
            onChanged: (v) => _settings.setServerEnabled(server.url, v),
          ),
          IconButton(
            tooltip: '测试连通性',
            icon: DrawIcon(StrokeIcons.wifiFind, size: m.iconSize16),
            onPressed: () => _settings.testServer(server),
          ),
          IconButton(
            tooltip: '编辑',
            icon: DrawIcon(StrokeIcons.edit, size: m.iconSize16),
            onPressed: () => _editServer(context, server),
          ),
          IconButton(
            tooltip: '删除',
            icon: DrawIcon(StrokeIcons.delete, size: m.iconSize16),
            onPressed: () => _removeServer(context, server),
          ),
        ],
      ),
    );
  }

  Future<void> _addServer(BuildContext context) async {
    final server = await _showServerDialog(context);
    if (server != null) await _settings.upsertServer(server);
  }

  Future<void> _editServer(BuildContext context, AsrServer current) async {
    final server = await _showServerDialog(context, existing: current);
    if (server != null) await _settings.upsertServer(server);
  }

  Future<void> _removeServer(BuildContext context, AsrServer server) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务'),
        content: Text('确定删除「${server.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await _settings.removeServer(server.url);
  }

  Future<void> _testAll(BuildContext context) async {
    final available = await _settings.testAllServers();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('探测完成：$available 个服务可用'), duration: AppMotion.dwell),
    );
  }

  /// 新建/编辑内网服务弹窗；返回 null 表示取消
  Future<AsrServer?> _showServerDialog(BuildContext context, {AsrServer? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? 'http://');
    final modelCtrl = TextEditingController(text: existing?.model ?? 'whisper-1');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final enabled = (existing?.enabled ?? true).obs;

    return showDialog<AsrServer>(
      context: context,
      builder: (dialogContext) {
        final m = AppTheme.metrics;
        return AlertDialog(
          title: Text(existing == null ? '新建内网大模型' : '编辑内网大模型'),
          content: SizedBox(
            width: scaleW(420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：家里 5090 推理机',
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  AppTextField(
                    controller: urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '服务地址',
                      hintText: 'http://192.168.1.10:8000',
                      helperText: '只填服务根地址，请求路径由程序自动拼接',
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  AppTextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名',
                      helperText: '请求体里的 model 字段，需与服务端一致',
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  AppTextField(
                    controller: keyCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'API Key（可选）'),
                  ),
                  SizedBox(height: m.kSpace4),
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用'),
                      value: enabled.value,
                      onChanged: (v) => enabled.value = v,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final url = urlCtrl.text.trim();
                if (url.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('请填写服务地址')),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  AsrServer(
                    name: nameCtrl.text.trim().isEmpty ? url : nameCtrl.text.trim(),
                    url: url,
                    apiKey: keyCtrl.text.trim().isEmpty ? null : keyCtrl.text.trim(),
                    model: modelCtrl.text.trim().isEmpty ? 'whisper-1' : modelCtrl.text.trim(),
                    enabled: enabled.value,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ── 字幕翻译（内网 NMT）────────────────────────────────────────────────────

  Widget _buildTranslateSection(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('字幕翻译为中文', style: AppTextStyles.cardTitle(context))),
            Obx(() {
              final online = _settings.translateServers
                  .where((t) => t.enabled && t.isAvailable)
                  .length;
              if (online == 0) return const SizedBox.shrink();
              // 同上：行尾计数封顶 + 省略号
              return Flexible(
                child: Text(
                  '$online 个在线',
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            SizedBox(width: m.kSpace8),
            TextButton.icon(
              onPressed: () => _addTranslateServer(context),
              icon: DrawIcon(StrokeIcons.add, size: m.iconSize14),
              label: const Text('新建'),
            ),
          ],
        ),
        Text(
          '用于二次审核：把识别出的日韩文字幕逐段译成中文，写出同名 .zh.srt（带时间轴）。'
          '请对接 LibreTranslate 兼容的 /translate 纯 NMT 服务（NLLB、OPUS-MT 一类），'
          '它按字直译；对话式大模型会把露骨说法改成委婉语，关键词就没法命中了。',
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize12,
            color: s.textTertiary,
            height: 1.6,
          ),
        ),
        SizedBox(height: m.kSpace8),
        Obx(
          () => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('识别完成后自动翻译'),
            subtitle: Text(
              '关闭时需要在右键菜单里手动点"翻译字幕为中文"。',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.textTertiary,
                height: 1.6,
              ),
            ),
            value: _settings.autoTranslate.value,
            onChanged: (v) => _settings.setAutoTranslate(v),
          ),
        ),
        Obx(
          () => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('输出双语字幕'),
            subtitle: Text(
              '中文下面保留原文，核对露骨表述是否被漏译时更直观。',
              style: AppTextStyles.role(
                context,
                fontSize: m.fontSize12,
                color: s.textTertiary,
                height: 1.6,
              ),
            ),
            value: _settings.bilingualSubtitle.value,
            onChanged: (v) => _settings.setBilingualSubtitle(v),
          ),
        ),
        SizedBox(height: m.kSpace8),
        Obx(() {
          if (_settings.translateServers.isEmpty) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: m.kSpace12),
              child: Text(
                '尚未配置翻译服务，右键"翻译字幕"会提示无法开始。',
                style: AppTextStyles.role(
                  context,
                  fontSize: m.fontSize12,
                  color: s.textTertiary,
                  height: 1.6,
                ),
              ),
            );
          }
          return Column(
            children: [
              for (final server in _settings.translateServers)
                _buildTranslateServerTile(context, server),
              SizedBox(height: m.kSpace8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _testAllTranslate(context),
                  icon: DrawIcon(StrokeIcons.wifiFind, size: m.iconSize14),
                  label: const Text('测试全部'),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTranslateServerTile(BuildContext context, TranslateServer server) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final online = server.enabled && server.isAvailable;
    // 状态点三色：停用=中性、在线=成功、离线=危险
    final statusRole = !server.enabled ? s.neutral : (online ? s.success : s.danger);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        children: [
          Container(
            width: m.kSpace8,
            height: m.kSpace8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusRole.color,
            ),
          ),
          SizedBox(width: m.kSpace10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: AppTextStyles.rowTitle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  server.url,
                  style: AppTextStyles.caption(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: server.enabled,
            onChanged: (v) => _settings.setTranslateServerEnabled(server.url, v),
          ),
          IconButton(
            tooltip: '测试连通性',
            icon: DrawIcon(StrokeIcons.wifiFind, size: m.iconSize16),
            onPressed: () => _settings.testTranslateServer(server),
          ),
          IconButton(
            tooltip: '编辑',
            icon: DrawIcon(StrokeIcons.edit, size: m.iconSize16),
            onPressed: () => _editTranslateServer(context, server),
          ),
          IconButton(
            tooltip: '删除',
            icon: DrawIcon(StrokeIcons.delete, size: m.iconSize16),
            onPressed: () => _removeTranslateServer(context, server),
          ),
        ],
      ),
    );
  }

  Future<void> _addTranslateServer(BuildContext context) async {
    final server = await _showTranslateServerDialog(context);
    if (server != null) await _settings.upsertTranslateServer(server);
  }

  Future<void> _editTranslateServer(BuildContext context, TranslateServer current) async {
    final server = await _showTranslateServerDialog(context, existing: current);
    if (server != null) await _settings.upsertTranslateServer(server);
  }

  Future<void> _removeTranslateServer(BuildContext context, TranslateServer server) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除翻译服务'),
        content: Text('确定删除「${server.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await _settings.removeTranslateServer(server.url);
  }

  Future<void> _testAllTranslate(BuildContext context) async {
    final available = await _settings.testAllTranslateServers();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('探测完成：$available 个翻译服务可用'), duration: AppMotion.dwell),
    );
  }

  /// 新建/编辑翻译服务弹窗；返回 null 表示取消
  Future<TranslateServer?> _showTranslateServerDialog(
    BuildContext context, {
    TranslateServer? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? 'http://');
    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
    final enabled = (existing?.enabled ?? true).obs;

    return showDialog<TranslateServer>(
      context: context,
      builder: (dialogContext) {
        final m = AppTheme.metrics;
        return AlertDialog(
          title: Text(existing == null ? '新建内网翻译服务' : '编辑内网翻译服务'),
          content: SizedBox(
            width: scaleW(420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      hintText: '例如：内网 NLLB 翻译节点',
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  AppTextField(
                    controller: urlCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '服务地址',
                      hintText: 'http://192.168.1.10:5000',
                      helperText: '只填服务根地址，程序会请求该地址下的 /translate',
                    ),
                  ),
                  SizedBox(height: m.kSpace12),
                  AppTextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Key（可选）',
                      helperText: 'LibreTranslate 走请求体 api_key，网关走 Bearer，程序两者都带',
                    ),
                  ),
                  SizedBox(height: m.kSpace4),
                  Obx(
                    () => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用'),
                      value: enabled.value,
                      onChanged: (v) => enabled.value = v,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final url = urlCtrl.text.trim();
                if (url.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('请填写服务地址')),
                  );
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  TranslateServer(
                    name: nameCtrl.text.trim().isEmpty ? url : nameCtrl.text.trim(),
                    url: url,
                    apiKey: keyCtrl.text.trim().isEmpty ? null : keyCtrl.text.trim(),
                    enabled: enabled.value,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ── 本地引擎一键部署 ───────────────────────────────────────────────────────

  Widget _buildLocalEngine(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Obx(() {
      final status = _settings.localStatus.value;
      final deploying = _settings.isDeploying.value;
      final ready = _settings.localReady.value;
      final stage = _settings.deployStage.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('本地引擎 SenseVoice', style: AppTextStyles.cardTitle(context)),
              ),
              _Badge(label: ready ? '已就绪' : '未部署', role: ready ? s.success : s.danger),
            ],
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '下载 sherpa-onnx 运行时与 SenseVoice 多语模型（中/英/日/韩/粤），完全离线识别字幕。',
            style: AppTextStyles.role(
              context,
              fontSize: m.fontSize12,
              color: s.textTertiary,
              height: 1.6,
            ),
          ),
          SizedBox(height: m.kSpace8),
          Wrap(
            spacing: m.kSpace8,
            runSpacing: m.kSpace6,
            children: [
              _Badge(
                label: '运行时 ${status?.runtimeVersion ?? '-'}',
                role: _roleForFlag(context, status?.runtimeReady),
              ),
              _Badge(label: '识别模型', role: _roleForFlag(context, status?.modelReady)),
              _Badge(label: 'VAD 模型', role: _roleForFlag(context, status?.vadReady)),
              if ((status?.diskUsageBytes ?? BigInt.zero) > BigInt.zero)
                _Badge(label: _fmtBytes(status!.diskUsageBytes), role: s.neutral),
            ],
          ),
          if (deploying) ...[
            SizedBox(height: m.kSpace12),
            ClipRRect(
              borderRadius: m.radius2,
              child: LinearProgressIndicator(
                value: _settings.deployProgress.value,
                minHeight: m.kSpace4,
                backgroundColor: s.surfaceRaised,
              ),
            ),
            SizedBox(height: m.kSpace4),
            Text(
              _stageText(stage, _settings.deployProgress.value),
              style: AppTextStyles.caption(context),
            ),
          ],
          SizedBox(height: m.kSpace12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (ready)
                TextButton(
                  onPressed: deploying ? null : () => _removeDeployment(context),
                  child: const Text('删除部署'),
                ),
              SizedBox(width: m.kSpace8),
              FilledButton.tonal(
                onPressed: deploying ? null : () => _deploy(context),
                child: Text(deploying ? '部署中…' : (ready ? '重新部署' : '一键部署')),
              ),
            ],
          ),
        ],
      );
    });
  }

  /// 就绪标记 → 语义状态角色：true 记成功，未就绪/未知按失败给危险色
  AppStatusRole _roleForFlag(BuildContext context, bool? flag) {
    final s = AppSemantic.of(context);
    return flag == true ? s.success : s.danger;
  }

  String _stageText(int stage, double progress) {
    final pct = (progress * 100).toStringAsFixed(0);
    return switch (stage) {
      1 => '正在下载组件… $pct%',
      2 => '正在解压安装…',
      3 => '部署完成',
      4 => '部署失败，可重试',
      _ => '准备中…',
    };
  }

  Future<void> _deploy(BuildContext context) async {
    final error = await _settings.deployLocal();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null ? '本地语音识别引擎已部署完成' : '部署失败：$error'),
        duration: AppMotion.dwellLong,
      ),
    );
  }

  Future<void> _removeDeployment(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地部署'),
        content: const Text('将删除已下载的运行时与模型文件以释放磁盘空间，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final error = await _settings.removeLocalDeployment();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error == null ? '本地部署已删除' : '删除失败：$error')),
    );
  }

  String _fmtBytes(BigInt bytes) {
    final mb = bytes ~/ BigInt.from(1024 * 1024);
    if (mb >= BigInt.from(1024)) {
      final gb = (bytes / BigInt.from(1024 * 1024 * 1024)).toDouble();
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${mb.toInt()} MB';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.role});

  final String label;
  final AppStatusRole role;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return ConstrainedBox(
      // 标签会随用户字号变长，宽度族封顶：宁可截断，不许顶破所在行
      constraints: BoxConstraints(maxWidth: scaleW(160)),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace8, vertical: m.kSpace2),
        decoration: BoxDecoration(
          color: role.container,
          borderRadius: m.radius999,
          border: Border.all(color: role.containerBorder),
        ),
        child: Text(
          label,
          style: AppTextStyles.role(
            context,
            fontSize: m.fontSize11,
            color: role.onContainer,
            weight: FontWeight.w600,
            height: 1.5,
            letterSpacing: 0.6,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Text(
      title,
      style: AppTextStyles.role(
        context,
        fontSize: m.fontSize13,
        color: s.accent,
        weight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(m.kSpace16),
      decoration: BoxDecoration(
        color: s.surface,
        borderRadius: m.radius12,
        border: Border.all(color: s.border),
      ),
      child: child,
    );
  }
}
