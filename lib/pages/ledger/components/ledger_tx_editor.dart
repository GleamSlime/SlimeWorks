import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/core/widgets/app_text_field.dart';

/// 底部导航中间那颗"记一笔"。
///
/// 概览与明细两页的 ViewModel 本来就带着账户、类别，用各自的 `_openEditor`
/// （能填默认值、存完顺手刷新）；统计/待确认/设置这几页没有这份下拉数据，
/// 为了一颗按钮给每个 VM 再加一遍不划算，这里直接向服务要。
/// 查重逻辑两边都要走，不然是同一颗按钮在有的页面会记重、有的不会。
Future<void> ledgerQuickAdd(BuildContext context) async {
  final service = GetIt.instance.get<LedgerService>();
  final accounts = await service.listAccounts();
  final categories = await service.listCategories();
  if (!context.mounted) return;
  final tx = await showLedgerTxEditor(context, accounts: accounts, categories: categories);
  if (tx == null || !context.mounted) return;
  await ledgerCommitTx(context, tx);
}

/// 把编辑器交回来的一笔落库：查重 →（像重复就）问用户 → 写入，返回是否真的记下了。
///
/// 概览、明细、模板"用一次"这几条路都走这里。写两份的后果是同一颗按钮在有的页面
/// 会拦重复、在有的页面直接记重。
Future<bool> ledgerCommitTx(BuildContext context, LedgerTx tx) async {
  final service = GetIt.instance.get<LedgerService>();
  final dup = await service.checkDuplicate(
    merchant: tx.merchant,
    amount: tx.amount,
    billDate: tx.billDate,
    accountId: tx.accountId,
  );
  if (dup.duplicated) {
    if (!context.mounted) return false;
    final keep = await showConfirmDialog(
      context,
      title: '像是同一笔',
      message: '同一天、同账户上已经有一笔 ${formatLedgerAmount(tx.amount)} 的记录了，仍要记下来吗？',
      confirmLabel: '仍然记录',
    );
    if (!keep) return false;
  }
  await service.addTransaction(tx);
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记下一笔')));
  return true;
}

/// 记一笔 / 改一笔 / 改一张模板。
///
/// 弹出即返回编辑后的 [LedgerTx]（未落库），由调用方的 ViewModel 负责查重与写，
/// 这样"发现重复→问用户是否仍然保存"这条中断-继续的链路留在数据层，
/// 表单不用知道 Rust 的查重接口。
///
/// [asTemplate] 非空就是**改这张模板**：不画日期（模板里本来就没有日期），
/// 保存时直接把这张模板按新字段覆盖回去，返回值只当作"改完了，刷新一下"的信号。
/// 同一套字段值得复用这个表单，另开一个模板编辑器只会让两边改得不一样。
///
/// 标签与附件是例外：它们直接读写 [LedgerStubStore]，因为后端还没有这两张表。
/// "存为模板"同理——勾上它就往模板仓库里多写一条，流水本身照旧走调用方。
Future<LedgerTx?> showLedgerTxEditor(
  BuildContext context, {
  LedgerTx? initial,
  LedgerTxTemplate? asTemplate,
  required List<LedgerAccount> accounts,
  required List<LedgerCategory> categories,
}) => showDialog<LedgerTx>(
  context: context,
  builder: (ctx) => _LedgerTxEditor(
    initial: initial,
    asTemplate: asTemplate,
    accounts: accounts,
    categories: categories,
  ),
);

class _LedgerTxEditor extends StatefulWidget {
  const _LedgerTxEditor({
    required this.initial,
    required this.asTemplate,
    required this.accounts,
    required this.categories,
  });

  final LedgerTx? initial;

  /// 非空 = 模板编辑模式
  final LedgerTxTemplate? asTemplate;
  final List<LedgerAccount> accounts;
  final List<LedgerCategory> categories;

  @override
  State<_LedgerTxEditor> createState() => _LedgerTxEditorState();
}

class _LedgerTxEditorState extends State<_LedgerTxEditor> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.initial == null || widget.initial!.amount <= 0
        ? ''
        : widget.initial!.amount.toStringAsFixed(2),
  );
  late final TextEditingController _destAmount = TextEditingController(
    text: (widget.initial?.destAmount ?? 0) <= 0
        ? ''
        : widget.initial!.destAmount.toStringAsFixed(2),
  );
  late final TextEditingController _merchant = TextEditingController(
    text: widget.initial?.merchant ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );

  late String _txType = widget.initial?.effectiveType ?? kLedgerTxTypeExpense;
  late int _accountId = _pickAccount(widget.initial?.accountId ?? 0, widget.initial?.accountName ?? '');
  late int _destAccountId = _pickAccount(
    widget.initial?.destAccountId ?? 0,
    widget.initial?.destAccountName ?? '',
  );
  late int _categoryId = _pickCategory(
    widget.initial?.categoryId ?? 0,
    widget.initial?.categoryName ?? '',
  );
  late int _parentId = _parentOf(_categoryId);
  late DateTime _date = _parseDate(widget.initial?.billDate);
  late TimeOfDay _time = _parseTime(widget.initial?.occurredAt);
  late bool _hidden = widget.initial?.hidden ?? false;
  late Set<int> _tagIds = <int>{...?widget.initial?.tagIds};
  late List<LedgerAttachment> _attachments = <LedgerAttachment>[
    ...?widget.initial?.attachments,
  ];
  bool _saveAsTemplate = false;
  bool _invalidAmount = false;

  /// 模板编辑模式：标题、按钮文案和保存去处都跟着换一套
  bool get _isTemplate => widget.asTemplate != null;

  /// 标签仓库里的全量标签：选中项要按 id 找回名字显示
  List<LedgerTag> _allTags = const <LedgerTag>[];

  bool get _isEdit => widget.initial != null && widget.initial!.id > 0;

  /// 转账与余额调整不属于收支，走的是"账户之间挪钱"的另一套口径
  bool get _isFlow => _txType == kLedgerTxTypeExpense || _txType == kLedgerTxTypeIncome;

  String get _direction => _txType == kLedgerTxTypeIncome
      ? kLedgerDirectionIncome
      : kLedgerDirectionExpense;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    await LedgerStubStore.instance.init();
    final tags = await LedgerStubStore.instance.listTags();
    if (!mounted) return;
    setState(() => _allTags = tags);
  }

  int _parentOf(int categoryId) {
    if (categoryId == 0) return 0;
    final self = widget.categories.where((c) => c.id == categoryId).firstOrNull;
    return self?.parentId ?? 0;
  }

  /// 模板与 CSV 带回来的常常只有名字：那条账户或类别被删过之后，
  /// 存的 id 要么指错、要么是 0。先按 id 认，认不到再按名字认一次，
  /// 两边都对不上就留空让用户自己选——比预选一个错的更诚实。
  int _pickAccount(int id, String name) {
    if (id > 0 && widget.accounts.any((a) => a.id == id)) return id;
    if (name.isEmpty) return 0;
    return widget.accounts.where((a) => a.name == name).firstOrNull?.id ?? 0;
  }

  int _pickCategory(int id, String name) {
    if (id > 0 && widget.categories.any((c) => c.id == id)) return id;
    if (name.isEmpty) return 0;
    return widget.categories
            .where((c) => c.name == name && c.direction == _direction)
            .firstOrNull
            ?.id ??
        0;
  }

  static DateTime _parseDate(String? raw) {
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed ?? DateTime.now();
  }

  static TimeOfDay _parseTime(String? raw) {
    if (raw != null && raw.length >= 16) {
      final h = int.tryParse(raw.substring(11, 13));
      final m = int.tryParse(raw.substring(14, 16));
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return TimeOfDay.fromDateTime(DateTime.now());
  }

  @override
  void dispose() {
    _amount.dispose();
    _destAmount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  /// 当前方向下可选的类别（收支类别不通用）
  List<LedgerCategory> get _typeCategories =>
      widget.categories.where((c) => c.direction == _direction).toList(growable: false);

  /// 有没有第二级：全是一级时挑选器只出一行，不给用户看一个空荡荡的子类行
  bool get _hasSubLevels => _typeCategories.any((c) => !c.isRoot);

  List<LedgerCategory> get _firstLevel => _hasSubLevels
      ? _typeCategories.where((c) => c.isRoot).toList(growable: false)
      : _typeCategories;

  /// 二级候选：没展开父类时必须是空的，否则这一行会把所有一级类再列一遍
  List<LedgerCategory> get _secondLevel => _parentId == 0
      ? const <LedgerCategory>[]
      : _typeCategories.where((c) => c.parentId == _parentId).toList(growable: false);

  List<LedgerTag> get _selectedTags =>
      _allTags.where((t) => _tagIds.contains(t.id)).toList(growable: false);

  void _setType(String type) {
    if (type == _txType) return;
    final wasIncome = _direction == kLedgerDirectionIncome;
    final nextIsFlow =
        type == kLedgerTxTypeExpense || type == kLedgerTxTypeIncome;
    setState(() {
      _txType = type;
      // 收支两类不通用：换方向还留着旧 id，就会把一笔支出挂到收入类别上
      final flipsDirection = nextIsFlow &&
          (type == kLedgerTxTypeIncome) != wasIncome;
      if (flipsDirection || !nextIsFlow) {
        _categoryId = 0;
        _parentId = 0;
      }
    });
  }

  void _pickFirstLevel(LedgerCategory category) {
    setState(() {
      if (!_hasSubLevels) {
        _categoryId = category.id;
        _parentId = 0;
        return;
      }
      if (_parentId == category.id) {
        // 再点一次收起：父类本身也可能能直接记（它没有子类时）
        if (_secondLevel.isEmpty) _categoryId = 0;
        _parentId = 0;
        return;
      }
      _parentId = category.id;
      final children = _typeCategories.where((c) => c.parentId == category.id);
      // 没有子类的父类就是叶子，直接落在这上面，不用再多点一次
      _categoryId = children.isEmpty ? category.id : 0;
    });
  }

  Future<void> _pickTags() async {
    final picked = await showLedgerTagPicker(
      context,
      selected: _tagIds,
      title: '这笔的标签',
    );
    if (picked == null) return;
    if (picked.length > kLedgerTagLimit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一笔最多挂 $kLedgerTagLimit 个标签，已经只留下前 $kLedgerTagLimit 个')),
      );
    }
    setState(() => _tagIds = picked.take(kLedgerTagLimit).toSet());
    final tags = await LedgerStubStore.instance.listTags();
    if (!mounted) return;
    setState(() => _allTags = tags);
  }

  Future<void> _addAttachment() async {
    // 桩阶段没有真文件可选，让仓库编一条元信息出来（名字也别掺时钟）
    final att = await LedgerStubStore.instance.addAttachment();
    if (!mounted) return;
    setState(() => _attachments = <LedgerAttachment>[..._attachments, att]);
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _invalidAmount = true);
      return;
    }
    if (_txType == kLedgerTxTypeTransfer && (_accountId == 0 || _destAccountId == 0)) {
      // 只选了一边的转账在账户中心会凭空少一笔进出，宁可拦住
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转账要把转出、转入两边都选好')),
      );
      return;
    }
    final initial = widget.initial;
    final occurred = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    // 转账/余额调整没有类别可言（切走类型时类别选择是留着方便切回来的），
    // 落库时必须按 0 写，否则一笔搬运会带着"餐饮"的标签进统计
    final flowCategoryId = _isFlow ? _categoryId : 0;
    final category = _typeCategories.where((c) => c.id == flowCategoryId).firstOrNull;
    final account = widget.accounts.where((a) => a.id == _accountId).firstOrNull;
    final destAccount = widget.accounts.where((a) => a.id == _destAccountId).firstOrNull;
    final tags = _selectedTags;
    final tx = LedgerTx(
      id: initial?.id ?? 0,
      occurredAt: _formatDateTime(occurred),
      billDate: _formatDate(_date),
      direction: _direction,
      txType: _txType,
      amount: amount,
      accountId: _accountId,
      destAccountId: _txType == kLedgerTxTypeTransfer ? _destAccountId : 0,
      destAmount: double.tryParse(_destAmount.text.trim()) ?? 0,
      categoryId: flowCategoryId,
      merchant: _merchant.text.trim(),
      note: _note.text.trim(),
      tagIds: tags.map((t) => t.id).toList(growable: false),
      attachments: _attachments,
      source: initial?.source ?? kLedgerSourceManual,
      ruleId: initial?.ruleId ?? 0,
      emailUid: initial?.emailUid ?? '',
      status: initial?.status ?? kLedgerStatusPosted,
      accountName: account?.name ?? initial?.accountName ?? '',
      destAccountName: destAccount?.name ?? initial?.destAccountName ?? '',
      categoryName: category?.name ?? initial?.categoryName ?? '',
      categoryIcon: category?.icon ?? initial?.categoryIcon ?? '',
      categoryDirection: category?.direction ?? initial?.categoryDirection ?? _direction,
      tagNames: tags.map((t) => t.name).toList(growable: false),
      hidden: _hidden,
    );
    if (_isTemplate) {
      // 改模板只回写模板仓库，不产生流水；id 与使用次数由 basedOn 带回去。
      // 返回值在这里只是"改完了，刷新一遍"的信号，调用方别拿它去记账。
      // 等它写完再关窗：调用方一拿到返回值就 reload，抢先返回会让列表慢一拍。
      await LedgerStubStore.instance.upsertTxTemplate(
        LedgerStubStore.templateOf(tx, basedOn: widget.asTemplate),
      );
      if (!mounted) return;
      Navigator.of(context).pop(tx);
      return;
    }
    if (_saveAsTemplate) {
      await LedgerStubStore.instance.upsertTxTemplate(
        LedgerStubStore.templateOf(tx, title: _merchant.text.trim()),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(tx);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final narrow = ledgerNarrow(context);

    return Dialog(
      backgroundColor: s.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: m.kSpace16,
        vertical: narrow ? m.kSpace24 : m.kSpace40,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: m.radiusOverlay,
        side: BorderSide(color: s.hairline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: scaleW(460)),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    _isTemplate ? '编辑模板' : (_isEdit ? '编辑这笔' : '记一笔'),
                    style: AppTextStyles.sectionTitle(context),
                  ),
                  const Spacer(),
                  ToolIconButton(
                    icon: StrokeIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
                ],
              ),
              SizedBox(height: m.kSpace12),
              _TypeRow(txType: _txType, onChanged: _setType),
              if (!_isFlow) ...<Widget>[
                SizedBox(height: m.kSpace12),
                LedgerStubMark(
                  text: _txType == kLedgerTxTypeTransfer
                      ? '转账的双边记账要等后端建表：这笔先按转出侧的单边保存，统计里暂计入支出'
                      : '余额调整要等后端建表：这笔先按普通流水保存，统计里暂计入支出',
                ),
              ],
              SizedBox(height: m.kSpace16),
              _AmountField(
                controller: _amount,
                txType: _txType,
                invalid: _invalidAmount,
                hidden: _hidden,
                onChanged: () {
                  if (_invalidAmount) setState(() => _invalidAmount = false);
                },
                onToggleHidden: () => setState(() => _hidden = !_hidden),
              ),
              if (_txType == kLedgerTxTypeTransfer) ...<Widget>[
                SizedBox(height: m.kSpace12),
                _DestAmountField(controller: _destAmount),
              ],
              if (_isFlow) ...<Widget>[
                SizedBox(height: m.kSpace16),
                const _FieldLabel(text: '类别'),
                SizedBox(height: m.kSpace8),
                _ChoiceWrap<LedgerCategory>(
                  items: _firstLevel,
                  selectedId: _hasSubLevels ? _parentId : _categoryId,
                  idOf: (c) => c.id,
                  labelOf: (c) => c.name,
                  iconOf: (c) => ledgerIconOf(c.icon),
                  onSelected: (id) {
                    final category = _typeCategories.firstWhere((c) => c.id == id);
                    _pickFirstLevel(category);
                  },
                ),
                if (_hasSubLevels && _secondLevel.isNotEmpty) ...<Widget>[
                  SizedBox(height: m.kSpace8),
                  Padding(
                    padding: EdgeInsets.only(left: m.kSpace12),
                    child: _ChoiceWrap<LedgerCategory>(
                      items: _secondLevel,
                      selectedId: _categoryId,
                      idOf: (c) => c.id,
                      labelOf: (c) => c.name,
                      iconOf: (c) => ledgerIconOf(c.icon),
                      onSelected: (id) => setState(() => _categoryId = id),
                    ),
                  ),
                ],
              ],
              SizedBox(height: m.kSpace16),
              if (_txType == kLedgerTxTypeTransfer) ...<Widget>[
                const _FieldLabel(text: '转出账户'),
                SizedBox(height: m.kSpace8),
                _ChoiceWrap<LedgerAccount>(
                  items: widget.accounts.where((a) => a.enabled).toList(growable: false),
                  selectedId: _accountId,
                  idOf: (a) => a.id,
                  labelOf: (a) => a.name,
                  iconOf: (a) => ledgerAccountIconOf(a.type),
                  onSelected: (id) => setState(() {
                    _accountId = id;
                    // 自己转给自己没有意义，落点跟着清掉
                    if (_destAccountId == id) _destAccountId = 0;
                  }),
                ),
                SizedBox(height: m.kSpace12),
                const _FieldLabel(text: '转入账户'),
                SizedBox(height: m.kSpace8),
                _ChoiceWrap<LedgerAccount>(
                  items: widget.accounts
                      .where((a) => a.enabled && a.id != _accountId)
                      .toList(growable: false),
                  selectedId: _destAccountId,
                  idOf: (a) => a.id,
                  labelOf: (a) => a.name,
                  iconOf: (a) => ledgerAccountIconOf(a.type),
                  onSelected: (id) => setState(() => _destAccountId = id),
                ),
              ] else ...<Widget>[
                const _FieldLabel(text: '账户'),
                SizedBox(height: m.kSpace8),
                _ChoiceWrap<LedgerAccount>(
                  items: widget.accounts.where((a) => a.enabled).toList(growable: false),
                  selectedId: _accountId,
                  idOf: (a) => a.id,
                  labelOf: (a) => a.name,
                  iconOf: (a) => ledgerAccountIconOf(a.type),
                  onSelected: (id) => setState(() => _accountId = id),
                ),
              ],
              SizedBox(height: m.kSpace16),
              const _FieldLabel(text: '标签'),
              SizedBox(height: m.kSpace8),
              _TagRow(
                tags: _selectedTags,
                onAdd: _pickTags,
                onRemove: (id) => setState(() => _tagIds = _tagIds.difference(<int>{id})),
              ),
              SizedBox(height: m.kSpace16),
              _AttachmentRow(
                attachments: _attachments,
                onAdd: _addAttachment,
                onRemove: (id) => setState(
                  () => _attachments = _attachments.where((a) => a.id != id).toList(),
                ),
              ),
              SizedBox(height: m.kSpace16),
              AppTextField(
                controller: _merchant,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '商户 / 说明',
                  hintText: '如：全家便利店',
                ),
              ),
              SizedBox(height: m.kSpace12),
              AppTextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              if (!_isTemplate) ...<Widget>[
                // 模板里没有日期这一项：每次记的都是当天，画个日期选择器只会让人
                // 以为"这张模板固定在 3 月 1 号"
                SizedBox(height: m.kSpace12),
                _DateRow(
                  date: _date,
                  time: _time,
                  onPickDate: _pickDate,
                  onPickTime: _pickTime,
                ),
              ],
              if (!_isEdit && !_isTemplate) ...<Widget>[
                SizedBox(height: m.kSpace8),
                _SaveAsTemplateRow(
                  checked: _saveAsTemplate,
                  onChanged: (value) => setState(() => _saveAsTemplate = value),
                ),
              ],
              SizedBox(height: m.kSpace20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  SizedBox(width: m.kSpace12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(
                        _isTemplate ? '保存模板' : (_isEdit ? '保存修改' : '记下来'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }
}

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime d) =>
    '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';

/// 支出 / 收入 / 转账 / 余额调整
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.txType, required this.onChanged});

  final String txType;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final pills = <Widget>[
      for (final type in kLedgerTxTypes)
        _ChoicePill(
          label: ledgerTxTypeLabel(type),
          icon: ledgerTxTypeIconOf(type),
          selected: txType == type,
          tone: type == kLedgerTxTypeIncome,
          compact: true,
          onTap: () => onChanged(type),
        ),
    ];
    // 宽屏拉成四等分，读起来像一段分段控件；窄屏四等分会把"余额调整"挤成
    // "余额…"，不如按内容排，宁可换行也不能少字。
    if (ledgerNarrow(context)) {
      return Wrap(spacing: m.kSpace6, runSpacing: m.kSpace6, children: pills);
    }
    return Row(
      children: <Widget>[
        for (var i = 0; i < pills.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: m.kSpace6),
          Expanded(child: pills[i]),
        ],
      ],
    );
  }
}

/// 金额输入：大号，只允许数字和一个小数点
///
/// 前缀符号跟着类型走——转账两侧都是钱在动，给它 +/- 就是把搬运读成消费。
/// 右边那颗眼睛是"这一笔的金额在列表里打码"，不是表单里的显示开关。
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.txType,
    required this.invalid,
    required this.hidden,
    required this.onChanged,
    required this.onToggleHidden,
  });

  final TextEditingController controller;
  final String txType;
  final bool invalid;
  final bool hidden;
  final VoidCallback onChanged;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final income = txType == kLedgerTxTypeIncome;
    final plain = txType == kLedgerTxTypeTransfer || txType == kLedgerTxTypeBalance;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: m.kSpace16, vertical: m.kSpace12),
      decoration: BoxDecoration(
        color: s.surfaceSunken,
        borderRadius: m.radius12,
        border: Border.all(color: invalid ? s.danger.color : s.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            plain ? '¥' : (income ? '+¥' : '-¥'),
            style: AppTextStyles.metric(context).copyWith(
              color: income ? s.success.color : s.textSecondary,
              fontSize: m.fontSize20,
            ),
          ),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: AppTextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              textAlign: TextAlign.start,
              style: AppTextStyles.metric(context),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: txType == kLedgerTxTypeBalance ? '调整后的余额' : '0.00',
                errorText: invalid ? '金额要大于 0' : null,
                errorStyle: AppTextStyles.caption(context).copyWith(color: s.danger.color),
              ),
            ),
          ),
          ToolIconButton(
            icon: hidden ? StrokeIcons.visibilityOff : StrokeIcons.visibility,
            tooltip: hidden ? '取消隐藏金额' : '在列表里隐藏这笔金额',
            onPressed: onToggleHidden,
          ),
        ],
      ),
    );
  }
}

/// 转账的到账侧金额：绝大多数情况与转出相同，所以留空就用转出数
class _DestAmountField extends StatelessWidget {
  const _DestAmountField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: AppTextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              isDense: true,
              labelText: '到账金额',
              hintText: '默认与转出相同',
            ),
          ),
        ),
        SizedBox(width: m.kSpace8),
        Padding(
          padding: EdgeInsets.only(bottom: m.kSpace10),
          child: DrawIcon(StrokeIcons.exchange, size: m.iconSize16, color: AppSemantic.of(context).textTertiary),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppTextStyles.overline(context));
}

/// 标签那一行：已选的胶囊 + 一颗"添加"
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tags, required this.onAdd, required this.onRemove});

  final List<LedgerTag> tags;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Wrap(
      spacing: m.kSpace6,
      runSpacing: m.kSpace6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final tag in tags)
          LedgerTagChip(
            label: tag.name,
            tint: ledgerColorOf(tag.color, fallback: s.textSecondary),
            onRemove: () => onRemove(tag.id),
          ),
        InkWell(
          onTap: onAdd,
          borderRadius: m.radiusPill,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace6),
            decoration: BoxDecoration(
              borderRadius: m.radiusPill,
              border: Border.all(color: s.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DrawIcon(StrokeIcons.add, size: m.iconSize12, color: s.textSecondary),
                SizedBox(width: m.kSpace4),
                Text('添加标签', style: AppTextStyles.caption(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 附件那一行。桩阶段只能"选"出一个假文件，为的是把缩略位与计数画全
class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
  });

  final List<LedgerAttachment> attachments;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('附件', style: AppTextStyles.overline(context)),
            SizedBox(width: m.kSpace8),
            InkWell(
              onTap: onAdd,
              borderRadius: m.radiusPill,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: m.kSpace6, vertical: m.kSpace2),
                child: Row(
                  children: <Widget>[
                    DrawIcon(StrokeIcons.add, size: m.iconSize12, color: s.textSecondary),
                    SizedBox(width: m.kSpace2),
                    Text('添加', style: AppTextStyles.caption(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (attachments.isNotEmpty) ...<Widget>[
          SizedBox(height: m.kSpace8),
          for (final att in attachments)
            Padding(
              padding: EdgeInsets.only(bottom: m.kSpace4),
              child: Row(
                children: <Widget>[
                  DrawIcon(
                    att.isImage ? StrokeIcons.image : StrokeIcons.description,
                    size: m.iconSize14,
                    color: s.textTertiary,
                  ),
                  SizedBox(width: m.kSpace8),
                  Expanded(
                    child: Text(
                      att.fileName,
                      style: AppTextStyles.body(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (att.sizeLabel.isNotEmpty) Text(att.sizeLabel, style: AppTextStyles.caption(context)),
                  SizedBox(width: m.kSpace8),
                  InkWell(
                    onTap: () => onRemove(att.id),
                    child: DrawIcon(StrokeIcons.close, size: m.iconSize14, color: s.textTertiary),
                  ),
                ],
              ),
            ),
          LedgerStubMark(text: '附件只存了文件名与大小，真正的文件要等后端接入'),
        ],
      ],
    );
  }
}

class _SaveAsTemplateRow extends StatelessWidget {
  const _SaveAsTemplateRow({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: m.radius8,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: m.kSpace6),
        child: Row(
          children: <Widget>[
            DrawIcon(
              checked ? StrokeIcons.checkBox : StrokeIcons.checkBoxOutlineBlank,
              size: m.iconSize16,
              color: checked ? s.accent : s.textTertiary,
            ),
            SizedBox(width: m.kSpace8),
            Expanded(
              child: Text('同时存为模板', style: AppTextStyles.body(context)),
            ),
            DrawIcon(ledgerUiIconOf('template'), size: m.iconSize16, color: s.textTertiary),
          ],
        ),
      ),
    );
  }
}


/// 可横向换行的单选条：类别、账户都用它
class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.labelOf,
    required this.iconOf,
    required this.onSelected,
  });

  final List<T> items;
  final int selectedId;
  final int Function(T) idOf;
  final String Function(T) labelOf;
  final StrokeIcon Function(T) iconOf;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('这里还没有可选项', style: AppTextStyles.caption(context));
    }
    final m = AppTheme.metrics;
    return Wrap(
      spacing: m.kSpace6,
      runSpacing: m.kSpace6,
      children: <Widget>[
        for (final item in items)
          _ChoicePill(
            label: labelOf(item),
            icon: iconOf(item),
            selected: idOf(item) == selectedId,
            onTap: () => onSelected(idOf(item)),
          ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.tone = false,
    this.compact = false,
  });

  final String label;
  final StrokeIcon icon;
  final bool selected;
  final VoidCallback onTap;

  /// true 时选中态走"成功"角色（收入）
  final bool tone;

  /// 四选一那一行要收一点：四个 pill 排在一行，太胖就把标签挤到折行
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final activeColor = tone ? s.success.color : s.accentText;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radiusPill,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? m.kSpace6 : m.kSpace10,
          vertical: compact ? m.kSpace6 : m.kSpace8,
        ),
        constraints: BoxConstraints(minHeight: compact ? m.kSpace32 : 40),
        decoration: BoxDecoration(
          color: selected ? (tone ? s.success.container : s.accentContainer) : s.surfaceSunken,
          borderRadius: m.radiusPill,
          border: Border.all(
            color: selected
                ? (tone ? s.success.containerBorder : s.accentContainerBorder)
                : s.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DrawIcon(
              icon,
              size: compact ? m.iconSize14 : m.iconSize14,
              color: selected ? activeColor : s.textSecondary,
            ),
            SizedBox(width: m.kSpace4),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.body(context).copyWith(
                  color: selected ? activeColor : s.textSecondary,
                  fontSize: compact ? m.fontSize12 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
  });

  final DateTime date;
  final TimeOfDay time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickDate,
            icon: DrawIcon(StrokeIcons.calendarToday, size: m.iconSize16),
            label: Text(_formatDate(date)),
          ),
        ),
        SizedBox(width: m.kSpace8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickTime,
            icon: DrawIcon(StrokeIcons.schedule, size: m.iconSize16),
            label: Text(time.format(context)),
          ),
        ),
      ],
    );
  }
}
