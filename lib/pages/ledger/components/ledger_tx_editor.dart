import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_geometry.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/pages/ledger/components/ledger_icons.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 记一笔 / 改一笔。
///
/// 弹出即返回编辑后的 [LedgerTx]（未落库），由调用方的 ViewModel 负责查重与写，
/// 这样"发现重复→问用户是否仍然保存"这条中断-继续的链路留在数据层，
/// 表单不用知道 Rust 的查重接口。
Future<LedgerTx?> showLedgerTxEditor(
  BuildContext context, {
  LedgerTx? initial,
  required List<LedgerAccount> accounts,
  required List<LedgerCategory> categories,
}) => showDialog<LedgerTx>(
  context: context,
  builder: (ctx) => _LedgerTxEditor(
    initial: initial,
    accounts: accounts,
    categories: categories,
  ),
);

class _LedgerTxEditor extends StatefulWidget {
  const _LedgerTxEditor({
    required this.initial,
    required this.accounts,
    required this.categories,
  });

  final LedgerTx? initial;
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
  late final TextEditingController _merchant = TextEditingController(
    text: widget.initial?.merchant ?? '',
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.initial?.note ?? '',
  );

  late String _direction = widget.initial?.direction ?? kLedgerDirectionExpense;
  late int _accountId = widget.initial?.accountId ?? 0;
  late int _categoryId = widget.initial?.categoryId ?? 0;
  late DateTime _date = _parseDate(widget.initial?.billDate);
  late TimeOfDay _time = _parseTime(widget.initial?.occurredAt);

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

  bool get _isEdit => widget.initial != null && widget.initial!.id > 0;

  List<LedgerCategory> get _visibleCategories =>
      widget.categories.where((c) => c.direction == _direction).toList(growable: false);

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _invalidAmount = true);
      return;
    }
    final initial = widget.initial;
    final occurred = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final category = _visibleCategories.where((c) => c.id == _categoryId).firstOrNull;
    final account = widget.accounts.where((a) => a.id == _accountId).firstOrNull;
    Navigator.of(context).pop(
      LedgerTx(
        id: initial?.id ?? 0,
        occurredAt: _formatDateTime(occurred),
        billDate: _formatDate(_date),
        direction: _direction,
        amount: amount,
        accountId: _accountId,
        categoryId: _categoryId,
        merchant: _merchant.text.trim(),
        note: _note.text.trim(),
        source: initial?.source ?? kLedgerSourceManual,
        ruleId: initial?.ruleId ?? 0,
        emailUid: initial?.emailUid ?? '',
        status: initial?.status ?? kLedgerStatusPosted,
        accountName: account?.name ?? initial?.accountName ?? '',
        categoryName: category?.name ?? initial?.categoryName ?? '',
        categoryIcon: category?.icon ?? initial?.categoryIcon ?? '',
        categoryDirection: category?.direction ?? initial?.categoryDirection ?? _direction,
      ),
    );
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(m.kSpace20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    _isEdit ? '编辑这笔' : '记一笔',
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
              _DirectionRow(
                direction: _direction,
                onChanged: (value) => setState(() {
                  _direction = value;
                  // 收支类别不通用，换方向必须把旧选择清掉，否则会存进一个错类的 id
                  _categoryId = 0;
                }),
              ),
              SizedBox(height: m.kSpace16),
              _AmountField(
                controller: _amount,
                income: _direction == kLedgerDirectionIncome,
                invalid: _invalidAmount,
                onChanged: () {
                  if (_invalidAmount) setState(() => _invalidAmount = false);
                },
              ),
              SizedBox(height: m.kSpace16),
              _FieldLabel(text: '类别'),
              SizedBox(height: m.kSpace8),
              _ChoiceWrap<LedgerCategory>(
                items: _visibleCategories,
                selectedId: _categoryId,
                idOf: (c) => c.id,
                labelOf: (c) => c.name,
                iconOf: (c) => ledgerIconOf(c.icon),
                onSelected: (id) => setState(() => _categoryId = id),
              ),
              SizedBox(height: m.kSpace16),
              _FieldLabel(text: '账户'),
              SizedBox(height: m.kSpace8),
              _ChoiceWrap<LedgerAccount>(
                items: widget.accounts.where((a) => a.enabled).toList(growable: false),
                selectedId: _accountId,
                idOf: (a) => a.id,
                labelOf: (a) => a.name,
                iconOf: (a) => ledgerAccountIconOf(a.type),
                onSelected: (id) => setState(() => _accountId = id),
              ),
              SizedBox(height: m.kSpace16),
              TextField(
                controller: _merchant,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '商户 / 说明',
                  hintText: '如：全家便利店',
                ),
              ),
              SizedBox(height: m.kSpace12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              SizedBox(height: m.kSpace12),
              _DateRow(
                date: _date,
                time: _time,
                onPickDate: _pickDate,
                onPickTime: _pickTime,
              ),
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
                      child: Text(_isEdit ? '保存修改' : '记下来'),
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

  bool _invalidAmount = false;

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

class _DirectionRow extends StatelessWidget {
  const _DirectionRow({required this.direction, required this.onChanged});

  final String direction;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _ChoicePill(
            label: '支出',
            icon: StrokeIcons.trendingDown,
            selected: direction == kLedgerDirectionExpense,
            onTap: () => onChanged(kLedgerDirectionExpense),
          ),
        ),
        SizedBox(width: AppTheme.metrics.kSpace8),
        Expanded(
          child: _ChoicePill(
            label: '收入',
            icon: StrokeIcons.trendingUp,
            selected: direction == kLedgerDirectionIncome,
            tone: true,
            onTap: () => onChanged(kLedgerDirectionIncome),
          ),
        ),
      ],
    );
  }
}

/// 金额输入：大号居中，只允许数字和一个小数点
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.income,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool income;
  final bool invalid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
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
            income ? '+¥' : '-¥',
            style: AppTextStyles.metric(context).copyWith(
              color: income ? s.success.color : s.textSecondary,
              fontSize: m.fontSize20,
            ),
          ),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: TextField(
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
                hintText: '0.00',
                errorText: invalid ? '金额要大于 0' : null,
                errorStyle: AppTextStyles.caption(context).copyWith(color: s.danger.color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppTextStyles.overline(context));
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
  });

  final String label;
  final StrokeIcon icon;
  final bool selected;
  final VoidCallback onTap;

  /// true 时选中态走"成功"角色（收入）
  final bool tone;

  @override
  Widget build(BuildContext context) {
    final s = AppSemantic.of(context);
    final m = AppTheme.metrics;
    final activeColor = tone ? s.success.color : s.accentText;
    return InkWell(
      onTap: onTap,
      borderRadius: m.radiusPill,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.kSpace10, vertical: m.kSpace8),
        constraints: const BoxConstraints(minHeight: 40),
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
              size: m.iconSize14,
              color: selected ? activeColor : s.textSecondary,
            ),
            SizedBox(width: m.kSpace6),
            Text(
              label,
              style: AppTextStyles.body(context).copyWith(
                color: selected ? activeColor : s.textSecondary,
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
