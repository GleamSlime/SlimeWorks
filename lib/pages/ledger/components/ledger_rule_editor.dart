import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_settings_viewmodel.dart';

/// 邮箱规则编辑器：连接参数 + 匹配条件 + 模板 + 收取时机。
///
/// 口令只活在这个表单的 controller 里，保存时交给 [LedgerService] 写进安全存储——
/// 不进规则 JSON、不进日志，界面回显的永远是"已保存"而不是内容本身。
Future<void> showLedgerRuleEditor(
  BuildContext context, {
  required LedgerSettingsViewModel vm,
  LedgerRule? initial,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RuleEditorDialog(vm: vm, initial: initial),
  );
}

class _RuleEditorDialog extends StatefulWidget {
  const _RuleEditorDialog({required this.vm, this.initial});

  final LedgerSettingsViewModel vm;
  final LedgerRule? initial;

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  static const Map<String, String> _protocolLabels = <String, String>{
    'imap': 'IMAP',
    'pop3': 'POP3',
    'smtp': 'SMTP',
    'exchange_eas': 'Exchange',
    'carddav': 'CardDAV',
  };

  static const Map<String, ({int ssl, int plain})> _portPresets = <String, ({int ssl, int plain})>{
    'imap': (ssl: 993, plain: 143),
    'pop3': (ssl: 995, plain: 110),
    'smtp': (ssl: 465, plain: 587),
  };

  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _mailbox;
  late final TextEditingController _sender;
  late final TextEditingController _subject;
  late final TextEditingController _password;
  final TextEditingController _sampleHtml = TextEditingController();

  late String _protocol;
  late bool _useSsl;
  late bool _matchIsRegex;
  late bool _autoApply;
  late bool _acceptInvalidCerts;
  late String _templateId;
  late String _dailyTime;
  late int _intervalMinutes;
  late int _accountId;

  bool _passwordVisible = false;
  bool _clearPassword = false;
  bool _showSample = false;

  /// 联网操作的忙态：VM 的 probing 在这个弹层里观察不到（它不是 Rx 监听点），
  /// 自己记一份才不会让"自检"被连点两次。
  bool _busy = false;
  String? _errorText;
  LedgerProbeReport? _report;
  List<LedgerFetchedEmail> _fetched = const <LedgerFetchedEmail>[];
  LedgerParseResult? _parsed;

  bool get _isNew => widget.initial == null || widget.initial!.id == 0;
  bool get _protocolSupported => _portPresets.containsKey(_protocol);

  @override
  void initState() {
    super.initState();
    final rule = widget.initial;
    _name = TextEditingController(text: rule?.name ?? '');
    _host = TextEditingController(text: rule?.host ?? '');
    _port = TextEditingController(text: rule == null || rule.port == 0 ? '' : '${rule.port}');
    _username = TextEditingController(text: rule?.username ?? '');
    _mailbox = TextEditingController(text: rule?.mailbox ?? 'INBOX');
    _sender = TextEditingController(text: rule?.senderMatch ?? '');
    _subject = TextEditingController(text: rule?.subjectMatch ?? '');
    // 编辑已有规则时口令框永远留空：空表示"沿用已存的那一份"
    _password = TextEditingController();

    _protocol = rule?.protocol ?? 'imap';
    _useSsl = rule?.useSsl ?? true;
    _matchIsRegex = rule?.matchIsRegex ?? false;
    _autoApply = rule?.autoApply ?? false;
    _acceptInvalidCerts = rule?.acceptInvalidCerts ?? false;
    _templateId = rule?.templateId ?? 'auto';
    _dailyTime = rule?.dailyTime ?? '';
    _intervalMinutes = rule?.intervalMinutes ?? 0;
    _accountId = rule?.defaultAccountId ?? widget.vm.accounts.firstOrNull?.id ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _mailbox.dispose();
    _sender.dispose();
    _subject.dispose();
    _password.dispose();
    _sampleHtml.dispose();
    super.dispose();
  }

  void _setProtocol(String value) {
    final preset = _portPresets[value];
    if (preset != null && _port.text.isEmpty) {
      _port.text = _useSsl ? '${preset.ssl}' : '${preset.plain}';
    }
    setState(() => _protocol = value);
  }

  void _setSsl(bool value) {
    final preset = _portPresets[_protocol];
    if (preset != null) _port.text = value ? '${preset.ssl}' : '${preset.plain}';
    setState(() => _useSsl = value);
  }

  Future<void> _pickDailyTime() async {
    final parts = _dailyTime.split(':');
    final initialTime = parts.length == 2
        ? TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]))
        : const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initialTime);
    if (picked == null) return;
    setState(() {
      _dailyTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _intervalMinutes = 0;
    });
  }

  LedgerRule _buildRule() => LedgerRule(
    id: widget.initial?.id ?? 0,
    name: _name.text.trim(),
    enabled: widget.initial?.enabled ?? true,
    protocol: _protocol,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    useSsl: _useSsl,
    username: _username.text.trim(),
    mailbox: _mailbox.text.trim().isEmpty ? 'INBOX' : _mailbox.text.trim(),
    senderMatch: _sender.text.trim(),
    subjectMatch: _subject.text.trim(),
    matchIsRegex: _matchIsRegex,
    templateId: _templateId,
    templateConfig: widget.initial?.templateConfig ?? '{}',
    intervalMinutes: _intervalMinutes,
    dailyTime: _dailyTime,
    defaultAccountId: _accountId,
    autoApply: _autoApply,
    acceptInvalidCerts: _acceptInvalidCerts,
  );

  /// 只拦"跑起来一定失败"的项；占位协议放行，让用户先把配置存下来
  String? _validate() {
    if (_name.text.trim().isEmpty) return '给这条规则起个名字';
    if (_host.text.trim().isEmpty) return '填写收信服务器地址';
    if (_username.text.trim().isEmpty) return '填写邮箱账号';
    if (int.tryParse(_port.text.trim()) == null) return '端口要填数字';
    if (_isNew && _password.text.isEmpty) return '新规则要填邮箱口令或应用专用密码';
    if (_sender.text.trim().isEmpty && _subject.text.trim().isEmpty) {
      return '发件人和标题至少填一个，否则每封邮件都会被当成账单';
    }
    if (_intervalMinutes == 0 && _dailyTime.isEmpty) return '选一种收取时机：固定间隔或每天定点';
    return null;
  }

  void _resetResults() => setState(() {
    _errorText = null;
    _report = null;
    _fetched = const <LedgerFetchedEmail>[];
    _parsed = null;
  });

  /// ViewModel 的错误是个普通字段，弹层收不到 BasePage 那条 SnackBar，
  /// 所以每次联网调用后手动把它取走，折成表单里的红字。
  String? _drainError() {
    final message = widget.vm.errorMessage;
    if (message == null) return null;
    widget.vm.clearError();
    return message;
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    Object? failure;
    try {
      await action();
    } catch (e) {
      // ViewModel 自己会 catch，这里兜住的是它没接住的那一类
      failure = e;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorText = _drainError() ?? (failure == null ? null : '操作没跑通: $failure');
    });
  }

  Future<void> _probe() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    _resetResults();
    await _guard(() async {
      final report = await widget.vm.probe(_buildRule(), _password.text);
      if (mounted) setState(() => _report = report);
    });
  }

  Future<void> _preview() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    _resetResults();
    await _guard(() async {
      final list = await widget.vm.previewFetch(_buildRule(), _password.text);
      if (mounted) setState(() => _fetched = list);
    });
  }

  Future<void> _parseSample() async {
    await _guard(() async {
      final result = await widget.vm.parseSample(_sampleHtml.text, _buildRule());
      if (mounted) setState(() => _parsed = result);
    });
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    final password = _password.text;
    final rule = _buildRule();
    LedgerSaveResult? result;
    await _guard(() async {
      result = await widget.vm.saveRule(rule, password);
    });
    if (!mounted || result != LedgerSaveResult.saved) return;
    if (_clearPassword && !_isNew) {
      // 保存已经跑完，这里只处理"用户明确要清掉已存口令"这一种情况
      await widget.vm.updatePassword(rule.id, '');
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final busy = _busy;

    return Dialog(
      backgroundColor: s.surfaceRaised,
      insetPadding: EdgeInsets.all(m.kSpace16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: scaleW(720),
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(m.kSpace20, m.kSpace16, m.kSpace12, m.kSpace4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _isNew ? '添加邮箱账单规则' : '编辑「${widget.initial!.name}」',
                      style: AppTextStyles.pageTitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ToolIconButton(
                    icon: StrokeIcons.close,
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(m.kSpace20, m.kSpace8, m.kSpace20, m.kSpace8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    LedgerField(
                      label: '规则名称',
                      child: LedgerInput(_name, hint: '招行每日账单'),
                    ),
                    LedgerField(
                      label: '协议',
                      child: Wrap(
                        spacing: m.kSpace6,
                        runSpacing: m.kSpace6,
                        children: <Widget>[
                          for (final entry in _protocolLabels.entries)
                            TagChip(
                              label: entry.value,
                              selected: _protocol == entry.key,
                              onTap: () => _setProtocol(entry.key),
                            ),
                        ],
                      ),
                    ),
                    if (!_protocolSupported)
                      _Notice(
                        text: '${_protocolLabels[_protocol]} 这一版还没实现，配置能存下来，'
                            '但收取会直接返回"尚未支持"。当前可用的是 IMAP / POP3 / SMTP。',
                      ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          flex: 3,
                          child: LedgerField(
                            label: '服务器',
                            child: LedgerInput(_host, hint: 'imap.example.com'),
                          ),
                        ),
                        SizedBox(width: m.kSpace12),
                        Expanded(
                          child: LedgerField(
                            label: '端口',
                            child: LedgerInput(
                              _port,
                              hint: '993',
                              keyboardType: TextInputType.number,
                              formatter: FilteringTextInputFormatter.digitsOnly,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _CheckboxRow(
                      label: 'TLS 加密连接（关掉后只有本机地址还肯收，口令不该裸奔出去）',
                      checked: _useSsl,
                      onChanged: _setSsl,
                    ),
                    LedgerField(
                      label: '邮箱账号',
                      child: LedgerInput(_username, hint: 'me@example.com'),
                    ),
                    LedgerField(
                      label: '邮箱口令 / 应用专用密码',
                      hint: _isNew ? null : '留空表示沿用已保存的那一份',
                      child: TextField(
                        controller: _password,
                        obscureText: !_passwordVisible,
                        // 口令不参与任何自动填充与回显
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '不进数据库，只存系统钥匙串',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              IconButton(
                                tooltip: _passwordVisible ? '隐藏' : '显示',
                                onPressed: () =>
                                    setState(() => _passwordVisible = !_passwordVisible),
                                icon: DrawIcon(
                                  _passwordVisible ? StrokeIcons.visibilityOff : StrokeIcons.visibility,
                                  size: m.iconSize16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!_isNew && widget.vm.hasPassword[widget.initial!.id] == true)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace6),
                        child: _CheckboxRow(
                          label: '保存后清除已存口令',
                          checked: _clearPassword,
                          onChanged: (v) => setState(() => _clearPassword = v),
                        ),
                      ),
                    LedgerField(
                      label: '邮件目录',
                      hint: 'POP3 忽略这一项；IMAP 自检成功后可以直接点下面的目录',
                      child: LedgerInput(_mailbox, hint: 'INBOX'),
                    ),
                    if (_report != null && _report!.folders.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace6),
                        child: Wrap(
                          spacing: m.kSpace6,
                          runSpacing: m.kSpace6,
                          children: <Widget>[
                            for (final folder in _report!.folders.take(12))
                              TagChip(
                                label: folder,
                                selected: _mailbox.text == folder,
                                onTap: () => setState(() => _mailbox.text = folder),
                              ),
                          ],
                        ),
                      ),
                    SizedBox(height: m.kSpace16),
                    const AppDivider(),
                    SizedBox(height: m.kSpace8),
                    Text('哪些邮件算账单', style: AppTextStyles.sectionTitle(context)),
                    SizedBox(height: m.kSpace8),
                    LedgerField(
                      label: '发件人包含',
                      child: LedgerInput(_sender, hint: 'cc@cmbc.cn'),
                    ),
                    LedgerField(
                      label: '标题包含',
                      child: LedgerInput(_subject, hint: '每日交易明细'),
                    ),
                    _CheckboxRow(
                      label: '按正则匹配（关闭时按"包含"匹配）',
                      checked: _matchIsRegex,
                      onChanged: (v) => setState(() => _matchIsRegex = v),
                    ),
                    SizedBox(height: m.kSpace16),
                    const AppDivider(),
                    SizedBox(height: m.kSpace8),
                    Text('怎么解析、什么时候收', style: AppTextStyles.sectionTitle(context)),
                    SizedBox(height: m.kSpace8),
                    LedgerField(
                      label: '解析模板',
                      child: Wrap(
                        spacing: m.kSpace6,
                        runSpacing: m.kSpace6,
                        children: <Widget>[
                          TagChip(
                            label: '自动判断',
                            selected: _templateId == 'auto',
                            onTap: () => setState(() => _templateId = 'auto'),
                          ),
                          for (final t in widget.vm.templates)
                            TagChip(
                              label: t.name.isEmpty ? t.id : t.name,
                              selected: _templateId == t.id,
                              onTap: () => setState(() => _templateId = t.id),
                            ),
                        ],
                      ),
                    ),
                    LedgerField(
                      label: '收取时机',
                      hint: '间隔模式每次应用启动后按分钟轮询；定点模式每天到点跑一次',
                      child: Wrap(
                        spacing: m.kSpace6,
                        runSpacing: m.kSpace6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          for (final option in const <({String label, int minutes})>[
                            (label: '每 15 分钟', minutes: 15),
                            (label: '每小时', minutes: 60),
                            (label: '每 6 小时', minutes: 360),
                          ])
                            TagChip(
                              label: option.label,
                              selected: _intervalMinutes == option.minutes,
                              onTap: () => setState(() {
                                _intervalMinutes = option.minutes;
                                _dailyTime = '';
                              }),
                            ),
                          TagChip(
                            label: _dailyTime.isEmpty ? '每天定点…' : '每天 $_dailyTime',
                            selected: _intervalMinutes == 0 && _dailyTime.isNotEmpty,
                            onTap: _pickDailyTime,
                          ),
                        ],
                      ),
                    ),
                    LedgerField(
                      label: '默认入账账户',
                      child: widget.vm.accounts.isEmpty
                          ? Text(
                              '还没有账户，先去"账户与类别"里建一个',
                              style: AppTextStyles.caption(context),
                            )
                          : Wrap(
                              spacing: m.kSpace6,
                              runSpacing: m.kSpace6,
                              children: <Widget>[
                                for (final a in widget.vm.accounts)
                                  TagChip(
                                    label: a.name,
                                    selected: _accountId == a.id,
                                    onTap: () => setState(() => _accountId = a.id),
                                  ),
                              ],
                            ),
                    ),
                    _CheckboxRow(
                      label: '解析结果直接入账，不进待确认队列',
                      checked: _autoApply,
                      onChanged: (v) => setState(() => _autoApply = v),
                    ),
                    _CheckboxRow(
                      label: '接受无效证书（仅在信任的网络里用）',
                      checked: _acceptInvalidCerts,
                      danger: true,
                      onChanged: (v) => setState(() => _acceptInvalidCerts = v),
                    ),
                    SizedBox(height: m.kSpace16),
                    _ActionBar(
                      busy: busy,
                      onProbe: _probe,
                      onPreview: _preview,
                      onSample: () => setState(() => _showSample = !_showSample),
                    ),
                    if (_errorText != null)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace12),
                        child: _Notice(danger: true, text: _errorText!),
                      ),
                    if (_report != null) _ReportBlock(report: _report!),
                    if (_fetched.isNotEmpty) _FetchedBlock(emails: _fetched),
                    if (_showSample)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace16),
                        child: LedgerField(
                          label: '贴一段账单 HTML 验证模板',
                          hint: '不发邮件、不落库，只跑解析引擎',
                          child: TextField(
                            controller: _sampleHtml,
                            minLines: 4,
                            maxLines: 8,
                            style: AppTextStyles.mono(context),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '把邮件正文的 HTML 粘在这里',
                            ),
                          ),
                        ),
                      ),
                    if (_showSample)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(
                            onPressed: busy ? null : _parseSample,
                            child: const Text('解析这段 HTML'),
                          ),
                        ),
                      ),
                    if (_parsed != null) _ParsedBlock(result: _parsed!),
                    SizedBox(height: m.kSpace8),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(m.kSpace20, m.kSpace8, m.kSpace20, m.kSpace16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.vm.lastMessage.value,
                        style: AppTextStyles.caption(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                    SizedBox(width: m.kSpace8),
                    FilledButton(
                      onPressed: busy ? null : _save,
                      child: const Text('保存规则'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckboxRow extends StatelessWidget {
  const _CheckboxRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    this.danger = false,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace6),
      child: InkWell(
        onTap: () => onChanged(!checked),
        borderRadius: m.radius8,
        child: Row(
          children: <Widget>[
            Checkbox(
              value: checked,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body(context).copyWith(
                  color: danger && checked ? s.danger.color : s.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.busy,
    required this.onProbe,
    required this.onPreview,
    required this.onSample,
  });

  final bool busy;
  final VoidCallback onProbe;
  final VoidCallback onPreview;
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Wrap(
      spacing: m.kSpace8,
      runSpacing: m.kSpace8,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: busy ? null : onProbe,
          icon: DrawIcon(StrokeIcons.link, size: m.iconSize14),
          label: const Text('连接自检'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onPreview,
          icon: DrawIcon(StrokeIcons.download, size: m.iconSize14),
          label: const Text('试收取'),
        ),
        TextButton.icon(
          onPressed: onSample,
          icon: DrawIcon(StrokeIcons.description, size: m.iconSize14),
          label: const Text('用一段 HTML 验证模板'),
        ),
      ],
    );
  }
}

/// 提示条：警告/危险两种落点，颜色全从语义角色来
class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final role = danger ? s.danger : s.warning;
    return Container(
      margin: EdgeInsets.only(top: m.kSpace10),
      padding: EdgeInsets.symmetric(horizontal: m.kSpace12, vertical: m.kSpace8),
      decoration: BoxDecoration(
        color: role.container,
        borderRadius: m.radius8,
        border: Border.all(color: role.containerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DrawIcon(StrokeIcons.warning, size: m.iconSize16, color: role.color),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Text(text, style: AppTextStyles.caption(context).copyWith(
              color: role.onContainer,
            )),
          ),
        ],
      ),
    );
  }
}

class _ReportBlock extends StatelessWidget {
  const _ReportBlock({required this.report});

  final LedgerProbeReport report;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StatusChip(
            label: report.ok ? '连接成功' : '连接失败',
            tone: report.ok ? Tone.success : Tone.danger,
          ),
          SizedBox(height: m.kSpace6),
          Text(report.detail, style: AppTextStyles.body(context)),
          if (report.capabilities.isNotEmpty) ...[
            SizedBox(height: m.kSpace6),
            Text(
              '服务器能力：${report.capabilities.join('、')}',
              style: AppTextStyles.caption(context),
            ),
          ],
          if (report.folders.isNotEmpty) ...[
            SizedBox(height: m.kSpace6),
            Text(
              '可见目录 ${report.folders.length} 个：${report.folders.take(8).join('、')}',
              style: AppTextStyles.caption(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// 试收取结果：只读，不落库，用来在保存前确认模板抓得住
class _FetchedBlock extends StatelessWidget {
  const _FetchedBlock({required this.emails});

  final List<LedgerFetchedEmail> emails;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final matched = emails.where((e) => e.matched).length;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '抓到 ${emails.length} 封，命中规则 $matched 封',
            style: AppTextStyles.cardTitle(context),
          ),
          SizedBox(height: m.kSpace8),
          for (final email in emails)
            Padding(
              padding: EdgeInsets.only(bottom: m.kSpace8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DrawIcon(
                    email.matched ? StrokeIcons.check : StrokeIcons.removeCircleOutline,
                    size: m.iconSize16,
                    color: email.matched ? s.success.color : s.textTertiary,
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          email.subject.isEmpty ? '(无主题)' : email.subject,
                          style: AppTextStyles.rowTitle(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email.matched
                              ? '${email.templateId} · ${email.billDate} · ${email.txCount} 笔'
                              : '没匹配上：发件人 ${email.from}',
                          style: AppTextStyles.caption(context),
                        ),
                        for (final warning in email.warnings)
                          Text(
                            warning,
                            style: AppTextStyles.caption(context).copyWith(color: s.warning.color),
                          ),
                        for (final tx in email.transactions.take(6))
                          Text(
                            '${tx.datetime}  ${tx.description}  ${tx.rawAmount}',
                            style: AppTextStyles.mono(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ParsedBlock extends StatelessWidget {
  const _ParsedBlock({required this.result});

  final LedgerParseResult result;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Padding(
      padding: EdgeInsets.only(top: m.kSpace12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '模板「${result.templateId}」解出 ${result.transactions.length} 笔',
            style: AppTextStyles.cardTitle(context),
          ),
          for (final warning in result.warnings)
            Text(
              warning,
              style: AppTextStyles.caption(context).copyWith(color: s.warning.color),
            ),
          SizedBox(height: m.kSpace6),
          for (final tx in result.transactions.take(20))
            Padding(
              padding: EdgeInsets.only(bottom: m.kSpace4),
              child: Text(
                '${tx.datetime.padRight(17)} ${tx.description.padRight(28)} ${tx.rawAmount}',
                style: AppTextStyles.mono(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
