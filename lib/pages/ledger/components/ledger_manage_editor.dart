import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 账户编辑器：弹出即返回编辑结果，写库交给调用方的 ViewModel。
///
/// 与 [showLedgerTxEditor] 同一个取舍——表单只管收集字段，不碰服务，
/// 于是"内置类别不能删""有流水的账户改成停用"这类回执留在数据层说。
Future<LedgerAccount?> showLedgerAccountEditor(
  BuildContext context, {
  LedgerAccount? initial,
}) => showDialog<LedgerAccount>(
  context: context,
  builder: (ctx) => _AccountEditor(initial: initial),
);

/// 类别编辑器：名称 + 收支方向 + 上级类别 + 图标
///
/// [parents] 是候选父类（调用方给同方向的根类别）。空表就**不画这一栏**：
/// 后端的类别表还没有 `parent_id` 列，摆一个选了也不生效的控件，用户只会以为
/// 两级分类已经存住了。
Future<LedgerCategory?> showLedgerCategoryEditor(
  BuildContext context, {
  LedgerCategory? initial,
  String direction = kLedgerDirectionExpense,
  List<LedgerCategory> parents = const <LedgerCategory>[],
  int defaultParentId = 0,
}) => showDialog<LedgerCategory>(
  context: context,
  builder: (ctx) => _CategoryEditor(
    initial: initial,
    defaultDirection: direction,
    parents: parents,
    defaultParentId: defaultParentId,
  ),
);

/// 标签分组编辑器：名称 + 颜色
Future<LedgerTagGroup?> showLedgerTagGroupEditor(
  BuildContext context, {
  LedgerTagGroup? initial,
}) => showDialog<LedgerTagGroup>(
  context: context,
  builder: (ctx) => _TagGroupEditor(initial: initial),
);

/// 标签编辑器：名称 + 归入哪个分组 + 颜色
Future<LedgerTag?> showLedgerTagEditor(
  BuildContext context, {
  LedgerTag? initial,
  required List<LedgerTagGroup> groups,
  int defaultGroupId = 0,
}) => showDialog<LedgerTag>(
  context: context,
  builder: (ctx) => _TagEditor(
    initial: initial,
    groups: groups,
    defaultGroupId: defaultGroupId,
  ),
);

// ───────────────────────────────────────────────────────────────────────────
// 定时规则
// ───────────────────────────────────────────────────────────────────────────

/// 定时记账规则编辑器：名字 + 用哪张模板 + 重复频率 + 时点 + 起止 + 开关
///
/// 规则本身只是一行配置，到点真的去记一笔的是调度器（本机 Rust 侧），
/// 所以这一页写进去的"下次"只是按频率推出来的预览，不是承诺。
Future<LedgerSchedule?> showLedgerScheduleEditor(
  BuildContext context, {
  LedgerSchedule? initial,
  required List<LedgerTxTemplate> templates,
}) => showDialog<LedgerSchedule>(
  context: context,
  builder: (ctx) => _ScheduleEditor(initial: initial, templates: templates),
);

// ───────────────────────────────────────────────────────────────────────────
// 账户
// ───────────────────────────────────────────────────────────────────────────

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({required this.initial});

  final LedgerAccount? initial;

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _last4 = TextEditingController(text: widget.initial?.last4 ?? '');
  late final TextEditingController _limit = TextEditingController(
    text: _amountText(widget.initial?.creditLimit ?? 0),
  );
  late final TextEditingController _balance = TextEditingController(
    text: _amountText(widget.initial?.balance ?? 0),
  );

  late String _type = widget.initial?.type ?? 'credit_card';
  String? _error;

  bool get _isCard => _type == 'credit_card' || _type == 'debit_card';

  static String _amountText(double value) => value <= 0 ? '' : value.toStringAsFixed(2);

  @override
  void dispose() {
    _name.dispose();
    _last4.dispose();
    _limit.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '给账户起个名字');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      LedgerAccount(
        id: initial?.id ?? 0,
        name: _name.text.trim(),
        type: _type,
        last4: _isCard ? _last4.text.trim() : '',
        currency: initial?.currency ?? 'CNY',
        creditLimit: _type == 'credit_card' ? (double.tryParse(_limit.text.trim()) ?? 0) : 0,
        balance: double.tryParse(_balance.text.trim()) ?? 0,
        sortOrder: initial?.sortOrder ?? 0,
        enabled: initial?.enabled ?? true,
        createdAt: initial?.createdAt ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final initial = widget.initial;
    return _FormDialog(
      title: initial == null ? '添加账户' : '编辑「${initial.name}」',
      error: _error,
      onSubmit: _submit,
      children: <Widget>[
        LedgerField(
          label: '名称',
          child: LedgerInput(_name, hint: '招行信用卡 / 现金钱包'),
        ),
        LedgerField(
          label: '类型',
          child: Wrap(
            spacing: m.kSpace6,
            runSpacing: m.kSpace6,
            children: <Widget>[
              for (final entry in kLedgerAccountTypes.entries)
                TagChip(
                  label: entry.value,
                  selected: _type == entry.key,
                  onTap: () => setState(() => _type = entry.key),
                ),
            ],
          ),
        ),
        if (_isCard)
          LedgerField(
            label: '尾号',
            hint: '只填后四位，方便一眼认出是哪张卡',
            child: LedgerInput(
              _last4,
              hint: '9842',
              keyboardType: TextInputType.number,
              formatter: FilteringTextInputFormatter.digitsOnly,
            ),
          ),
        if (_type == 'credit_card')
          LedgerField(
            label: '额度',
            hint: '用来在首页看"已用多少"，不影响记账本身',
            child: LedgerInput(
              _limit,
              hint: '50000',
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              formatter: _decimalFormatter,
            ),
          ),
        LedgerField(
          label: '当前余额',
          hint: '手动填的快照数，流水不会自动改动它',
          child: LedgerInput(
            _balance,
            hint: '0',
            keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
            formatter: _decimalFormatter,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 类别
// ───────────────────────────────────────────────────────────────────────────

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({
    required this.initial,
    required this.defaultDirection,
    required this.parents,
    required this.defaultParentId,
  });

  final LedgerCategory? initial;
  final String defaultDirection;
  final List<LedgerCategory> parents;

  /// 「在此父类下新建」从外面带进来的父类；编辑已有类别时以 [initial] 为准
  final int defaultParentId;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');

  late String _direction = widget.initial?.direction ?? widget.defaultDirection;
  late String _icon = (widget.initial?.icon.isNotEmpty ?? false)
      ? widget.initial!.icon
      : kLedgerIconKeys.first;
  late int _parentId = widget.initial?.parentId ?? widget.defaultParentId;
  String? _error;

  /// 只列同方向、且不是自己（自己不能当自己的父类）的根类别
  List<LedgerCategory> get _parentChoices => widget.parents
      .where((c) => c.direction == _direction && c.id != widget.initial?.id)
      .toList(growable: false);

  bool get _showParentField => _parentChoices.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '给类别起个名字');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      LedgerCategory(
        id: initial?.id ?? 0,
        name: _name.text.trim(),
        icon: _icon,
        direction: _direction,
        sortOrder: initial?.sortOrder ?? 0,
        isBuiltin: initial?.isBuiltin ?? false,
        parentId: _showParentField ? _parentId : (initial?.parentId ?? 0),
        color: initial?.color ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final initial = widget.initial;
    final parentNames = <int, String>{
      for (final p in _parentChoices) p.id: p.name,
    };
    return _FormDialog(
      title: initial == null
          ? (widget.defaultParentId == 0 ? '添加类别' : '在「${parentNames[widget.defaultParentId] ?? ''}」下添加子类')
          : '编辑「${initial.name}」',
      error: _error,
      onSubmit: _submit,
      children: <Widget>[
        LedgerField(
          label: '名称',
          child: LedgerInput(_name, hint: '宠物 / 通勤'),
        ),
        LedgerField(
          label: '方向',
          hint: '决定它出现在支出统计还是收入统计里',
          child: Wrap(
            spacing: m.kSpace6,
            runSpacing: m.kSpace6,
            children: <Widget>[
              TagChip(
                label: '支出',
                selected: _direction == kLedgerDirectionExpense,
                // 收支类别不通用：方向一改，挂在旧方向上的父类就失效了
                onTap: () => setState(() {
                  _direction = kLedgerDirectionExpense;
                  _parentId = 0;
                }),
              ),
              TagChip(
                label: '收入',
                selected: _direction == kLedgerDirectionIncome,
                onTap: () => setState(() {
                  _direction = kLedgerDirectionIncome;
                  _parentId = 0;
                }),
              ),
            ],
          ),
        ),
        if (_showParentField)
          LedgerField(
            label: '上级类别',
            hint: '只做两级：子类统计时并到父类里，记一笔时先选父类再选它',
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                TagChip(
                  label: '无（一级类别）',
                  selected: _parentId == 0,
                  onTap: () => setState(() => _parentId = 0),
                ),
                for (final p in _parentChoices)
                  TagChip(
                    label: p.name,
                    selected: _parentId == p.id,
                    onTap: () => setState(() => _parentId = p.id),
                  ),
              ],
            ),
          ),
        LedgerField(
          label: '图标',
          child: Wrap(
            spacing: m.kSpace6,
            runSpacing: m.kSpace6,
            children: <Widget>[
              for (final key in kLedgerIconKeys)
                _IconChoice(
                  iconKey: key,
                  income: _direction == kLedgerDirectionIncome,
                  selected: _icon == key,
                  onTap: () => setState(() => _icon = key),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 图标候选：选中态靠描边，图标本身不变颜色，避免和方向色混在一起
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.iconKey,
    required this.income,
    required this.selected,
    required this.onTap,
  });

  final String iconKey;
  final bool income;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Tooltip(
      message: kLedgerIconLabels[iconKey] ?? iconKey,
      child: InkWell(
        onTap: onTap,
        borderRadius: m.radius8,
        child: Container(
          padding: EdgeInsets.all(m.kSpace6),
          decoration: BoxDecoration(
            color: selected ? s.accentContainer : s.surfaceSunken,
            borderRadius: m.radius8,
            border: Border.all(
              color: selected ? s.accentContainerBorder : s.hairline,
              width: selected ? scaleW(1.4) : scaleW(1),
            ),
          ),
          child: DrawIcon(
            ledgerIconOf(iconKey),
            size: m.iconSize20,
            color: selected ? s.accentText : s.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 标签分组 / 标签
// ───────────────────────────────────────────────────────────────────────────

class _TagGroupEditor extends StatefulWidget {
  const _TagGroupEditor({required this.initial});

  final LedgerTagGroup? initial;

  @override
  State<_TagGroupEditor> createState() => _TagGroupEditorState();
}

class _TagGroupEditorState extends State<_TagGroupEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late String _color = (widget.initial?.color.isNotEmpty ?? false)
      ? widget.initial!.color
      : kLedgerTagPalette.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '给分组起个名字');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      LedgerTagGroup(
        id: initial?.id ?? 0,
        name: _name.text.trim(),
        color: _color,
        sortOrder: initial?.sortOrder ?? 0,
        // 组内标签跟着对象一起回传：桩仓库的更新分支是整条替换，漏了就把标签洗没了
        tags: initial?.tags ?? const <LedgerTag>[],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return _FormDialog(
      title: initial == null ? '添加标签分组' : '编辑「${initial.name}」',
      error: _error,
      onSubmit: _submit,
      children: <Widget>[
        LedgerField(
          label: '名称',
          child: LedgerInput(_name, hint: '工作 / 家庭'),
        ),
        LedgerField(
          label: '颜色',
          hint: '挑标签和统计图上都会用这同一个色',
          child: _ColorRow(
            selected: _color,
            onPick: (hex) => setState(() => _color = hex),
          ),
        ),
      ],
    );
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.initial,
    required this.groups,
    required this.defaultGroupId,
  });

  final LedgerTag? initial;
  final List<LedgerTagGroup> groups;
  final int defaultGroupId;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late int _groupId = widget.initial?.groupId ?? widget.defaultGroupId;
  late String _color = (widget.initial?.color.isNotEmpty ?? false)
      ? widget.initial!.color
      : _colorOf(_groupId);
  String? _error;

  /// 没归组就给默认色：新建标签时一个分组都还没有是正常路径
  String _colorOf(int groupId) {
    for (final g in widget.groups) {
      if (g.id == groupId && g.color.isNotEmpty) return g.color;
    }
    return kLedgerTagPalette.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '给标签起个名字');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      LedgerTag(
        id: initial?.id ?? 0,
        name: _name.text.trim(),
        groupId: _groupId,
        color: _color,
        useCount: initial?.useCount ?? 0,
        sortOrder: initial?.sortOrder ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final initial = widget.initial;
    return _FormDialog(
      title: initial == null ? '添加标签' : '编辑「${initial.name}」',
      error: _error,
      onSubmit: _submit,
      children: <Widget>[
        LedgerField(
          label: '名称',
          child: LedgerInput(_name, hint: '出差 / 客户名：张三'),
        ),
        if (widget.groups.isNotEmpty)
          LedgerField(
            label: '归入分组',
            // 换组顺手把色跟过去：一个组里的标签同色才读得出"这几个是一抽屉的"
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                for (final g in widget.groups)
                  TagChip(
                    label: g.name,
                    selected: _groupId == g.id,
                    onTap: () => setState(() {
                      _groupId = g.id;
                      _color = _colorOf(g.id);
                    }),
                  ),
              ],
            ),
          ),
        LedgerField(
          label: '颜色',
          child: _ColorRow(
            selected: _color,
            onPick: (hex) => setState(() => _color = hex),
          ),
        ),
      ],
    );
  }
}

/// 一排色块：选中靠描边加粗，色块本身永远是那个颜色
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onPick});

  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final picked = ledgerColorOf(selected, fallback: s.textTertiary);
    return Wrap(
      spacing: m.kSpace8,
      runSpacing: m.kSpace8,
      children: <Widget>[
        for (final hex in kLedgerTagPalette)
          GestureDetector(
            // 色块是手画的 Container，测试只能按 key 找
            key: ValueKey<String>('color:$hex'),
            onTap: () => onPick(hex),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: m.kSpace24,
              height: m.kSpace24,
              decoration: BoxDecoration(
                color: ledgerColorOf(hex, fallback: s.textTertiary),
                borderRadius: m.radius6,
                border: Border.all(
                  color: hex == selected ? s.textPrimary : s.hairline,
                  width: hex == selected ? scaleW(2) : scaleW(1),
                ),
              ),
              child: hex == selected
                  ? DrawIcon(StrokeIcons.check, size: m.iconSize12, color: Colors.white)
                  : null,
            ),
          ),
        // 自定义色没在候选里时给一颗"当前色"，否则编辑已有标签会看不见自己的选择
        if (!kLedgerTagPalette.contains(selected))
          Container(
            width: m.kSpace24,
            height: m.kSpace24,
            decoration: BoxDecoration(
              color: picked,
              borderRadius: m.radius6,
              border: Border.all(color: s.textPrimary, width: scaleW(2)),
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 两个编辑器共用的弹层外壳
// ───────────────────────────────────────────────────────────────────────────

class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.children,
    required this.onSubmit,
    required this.error,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSubmit;

  /// 校验没过的提示；null 就不占位
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    return Dialog(
      backgroundColor: s.surfaceRaised,
      insetPadding: EdgeInsets.all(m.kSpace16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: scaleW(520),
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
                      title,
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
                padding: EdgeInsets.fromLTRB(m.kSpace20, m.kSpace8, m.kSpace20, m.kSpace12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ...children,
                    if (error != null)
                      Padding(
                        padding: EdgeInsets.only(top: m.kSpace12),
                        child: Text(
                          error!,
                          style: AppTextStyles.caption(context).copyWith(color: s.danger.color),
                        ),
                      ),
                    SizedBox(height: m.kSpace16),
                    Row(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        FilledButton(onPressed: onSubmit, child: const Text('保存')),
                      ],
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

/// 金额输入：只放数字、一个小数点和负号，其余字符当场丢掉
final TextInputFormatter _decimalFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^-?\d*\.?\d{0,2}'),
);

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor({required this.initial, required this.templates});

  final LedgerSchedule? initial;
  final List<LedgerTxTemplate> templates;

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _day = TextEditingController(
    text: '${widget.initial?.dayOfMonth ?? 1}',
  );

  /// 新建规则默认不落任何模板：到点照哪张模板记账是这条规则的全部内容，
  /// 顺手预选第一张只会让人在没注意时建出一条"每月自动记一笔咖啡"的规则。
  late int _templateId = widget.initial?.templateId ?? 0;
  late String _repeat = widget.initial?.repeat ?? kLedgerRepeatMonthly;
  late int _weekday = widget.initial?.weekday ?? 1;
  late String _time = widget.initial?.timeOfDay ?? '09:00';
  late String _start = widget.initial?.startDate ?? ledgerDateOf(DateTime.now());
  late String _end = widget.initial?.endDate ?? '';
  late bool _enabled = widget.initial?.enabled ?? true;
  String? _error;

  /// 频率决定要填哪一格：按月/季/年看几号，按周/两周看星期几，每天两样都不看
  bool get _byDayOfMonth =>
      _repeat == kLedgerRepeatMonthly ||
      _repeat == kLedgerRepeatQuarterly ||
      _repeat == kLedgerRepeatYearly;

  bool get _byWeekday =>
      _repeat == kLedgerRepeatWeekly || _repeat == kLedgerRepeatBiweekly;

  @override
  void dispose() {
    _name.dispose();
    _day.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '给这条规则起个名字');
      return;
    }
    if (widget.templates.isNotEmpty && _templateId == 0) {
      setState(() => _error = '要选一张模板：到点记的就是它');
      return;
    }
    final day = int.tryParse(_day.text.trim()) ?? 0;
    if (_byDayOfMonth && (day < 1 || day > 31)) {
      setState(() => _error = '一个月最多 31 天');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      LedgerSchedule(
        id: initial?.id ?? 0,
        name: name,
        templateId: _templateId,
        repeat: _repeat,
        // 用不上的那一格原样留着：切过频率再切回来，之前填的号数不该丢掉
        dayOfMonth: _byDayOfMonth ? day : (initial?.dayOfMonth ?? 1),
        weekday: _byWeekday ? _weekday : (initial?.weekday ?? 1),
        timeOfDay: _time,
        startDate: _start,
        endDate: _end,
        enabled: _enabled,
        lastRunAt: initial?.lastRunAt ?? '',
        nextRunAt: initial?.nextRunAt ?? '',
        templateTitle:
            widget.templates
                .where((t) => t.id == _templateId)
                .firstOrNull
                ?.title ??
            initial?.templateTitle ??
            '',
      ),
    );
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      ),
    );
    if (picked == null) return;
    setState(
      () => _time =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year + 5, 12, 31);
    final raw = DateTime.tryParse(start ? _start : _end);
    // 手填过的日期可能早就出了可选范围，钳一下而不是让日期选择器抛异常
    var initialDate = raw ?? now;
    if (initialDate.isBefore(first)) initialDate = first;
    if (initialDate.isAfter(last)) initialDate = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = ledgerDateOf(picked);
      } else {
        _end = ledgerDateOf(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final initial = widget.initial;
    return _FormDialog(
      title: initial == null ? '新建定时规则' : '编辑「${initial.name}」',
      error: _error,
      onSubmit: _submit,
      children: <Widget>[
        LedgerField(
          label: '名字',
          child: LedgerInput(_name, hint: '每月房租 / 会员续费'),
        ),
        if (widget.templates.isEmpty)
          const LedgerField(
            label: '模板',
            hint: '还没有模板：先在"记一笔"里勾一次"存为模板"，回来这里就能选了',
            child: SizedBox.shrink(),
          )
        else
          LedgerField(
            label: '模板',
            hint: '到点就照这张模板记一笔，日期取当天',
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                for (final t in widget.templates)
                  TagChip(
                    label: t.title.isEmpty ? '（没有名字）' : t.title,
                    selected: _templateId == t.id,
                    onTap: () => setState(() => _templateId = t.id),
                  ),
              ],
            ),
          ),
        LedgerField(
          label: '重复',
          child: Wrap(
            spacing: m.kSpace6,
            runSpacing: m.kSpace6,
            children: <Widget>[
              for (final e in kLedgerRepeatLabels.entries)
                TagChip(
                  label: e.value,
                  selected: _repeat == e.key,
                  onTap: () => setState(() => _repeat = e.key),
                ),
            ],
          ),
        ),
        if (_byDayOfMonth)
          LedgerField(
            label: '每月几号',
            hint: '碰到 2 月没有 30 号，调度器会落在月末',
            child: SizedBox(
              width: m.kSpace80,
              child: LedgerInput(
                _day,
                hint: '1',
                keyboardType: TextInputType.number,
                formatter: FilteringTextInputFormatter.digitsOnly,
              ),
            ),
          ),
        if (_byWeekday)
          LedgerField(
            label: '星期几',
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                for (var d = 1; d <= 7; d++)
                  TagChip(
                    label: '周${kLedgerWeekdayLabels[d % 7]}',
                    selected: _weekday == d,
                    onTap: () => setState(() => _weekday = d),
                  ),
              ],
            ),
          ),
        LedgerField(
          label: '几点',
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PickButton(text: _time, onTap: _pickTime),
          ),
        ),
        LedgerField(
          label: '开始日期',
          child: Align(
            alignment: Alignment.centerLeft,
            child: _PickButton(text: _start, onTap: () => _pickDate(start: true)),
          ),
        ),
        LedgerField(
          label: '结束日期',
          hint: '不填就是长期有效',
          child: Row(
            children: <Widget>[
              _PickButton(
                text: _end.isEmpty ? '未设' : _end,
                onTap: () => _pickDate(start: false),
              ),
              if (_end.isNotEmpty) ...<Widget>[
                SizedBox(width: m.kSpace8),
                TextButton(
                  onPressed: () => setState(() => _end = ''),
                  child: const Text('清除'),
                ),
              ],
            ],
          ),
        ),
        LedgerField(
          label: '状态',
          hint: '关掉之后规则还在，只是到点不跑',
          child: Row(
            children: <Widget>[
              Switch(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              SizedBox(width: m.kSpace8),
              Text('启用', style: AppTextStyles.caption(context)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 表单里"点开就是系统选择器"的那颗按钮（时间、日期都用它）
class _PickButton extends StatelessWidget {
  const _PickButton({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(text, style: AppTextStyles.body(context)),
    );
  }
}
