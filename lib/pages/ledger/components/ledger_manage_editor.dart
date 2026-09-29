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

/// 类别编辑器：名称 + 收支方向 + 图标
Future<LedgerCategory?> showLedgerCategoryEditor(
  BuildContext context, {
  LedgerCategory? initial,
  String direction = kLedgerDirectionExpense,
}) => showDialog<LedgerCategory>(
  context: context,
  builder: (ctx) => _CategoryEditor(initial: initial, defaultDirection: direction),
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
  const _CategoryEditor({required this.initial, required this.defaultDirection});

  final LedgerCategory? initial;
  final String defaultDirection;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.initial?.name ?? '');

  late String _direction = widget.initial?.direction ?? widget.defaultDirection;
  late String _icon = (widget.initial?.icon.isNotEmpty ?? false)
      ? widget.initial!.icon
      : kLedgerIconKeys.first;
  String? _error;

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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final initial = widget.initial;
    return _FormDialog(
      title: initial == null ? '添加类别' : '编辑「${initial.name}」',
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
                onTap: () => setState(() => _direction = kLedgerDirectionExpense),
              ),
              TagChip(
                label: '收入',
                selected: _direction == kLedgerDirectionIncome,
                onTap: () => setState(() => _direction = kLedgerDirectionIncome),
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
