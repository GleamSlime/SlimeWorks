import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:slime_works/components/dialogs/confirm_dialog.dart';
import 'package:slime_works/components/icons/draw_icon.dart';
import 'package:slime_works/components/icons/stroke_icons.g.dart';
import 'package:slime_works/components/window/screen_chrome.dart';
import 'package:slime_works/core/index.dart';
import 'package:slime_works/core/provider/screen_chrome.dart';
import 'package:slime_works/core/services/ledger_stub_store.dart';
import 'package:slime_works/pages/ledger/components/ledger_shared.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';
import 'package:slime_works/view_models/ledger/ledger_data_viewmodel.dart';

/// 导入与导出：账本进出都从这一页走。
///
/// 两头都是真数据——导出读 Rust 的流水表，导入写的也是它，所以整页不挂
/// [LedgerStubMark]。唯一存不住的是标签那一列：后端还没有标签表，界面就照实说
/// "导进来会丢掉"，而不是摆一个看起来会保留标签的勾选框。
class LedgerDataScreen extends BasePage<LedgerDataViewModel> {
  const LedgerDataScreen({super.key});

  @override
  State<LedgerDataScreen> createState() => _LedgerDataScreenState();
}

class _LedgerDataScreenState extends BasePageState<LedgerDataViewModel, LedgerDataScreen> {
  @override
  bool get showAppBar => false;

  @override
  LedgerDataViewModel createViewModel() => LedgerDataViewModel();

  // ── 导出 ──

  Future<void> _export() async {
    final vm = viewModel;
    if (vm.busy.value) return;
    vm.busy.value = true;
    try {
      final text = await vm.buildExport();
      if (!mounted) return;
      final bytes = Uint8List.fromList(utf8.encode(text));
      // 移动端必须把 bytes 一起交出去：那一侧的"另存为"是平台自己写文件的，
      // 只拿到路径再回头写，Android 上那条路径根本不可写。
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出流水',
        fileName: vm.exportFileName,
        bytes: bytes,
        lockParentWindow: true,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsString(text);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出 ${vm.exportCount.value} 笔到 $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导不出去：$e'), backgroundColor: AppSemantic.of(context).danger.color));
    } finally {
      vm.busy.value = false;
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final vm = viewModel;
    final current = start ? vm.customStart.value : vm.customEnd.value;
    final parsed = DateTime.tryParse(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    await vm.setCustom(start: start ? ledgerDateOf(picked) : null, end: start ? null : ledgerDateOf(picked));
  }

  // ── 导入 ──

  Future<void> _pickCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择要导入的表格',
      type: FileType.custom,
      allowedExtensions: const <String>['csv', 'txt'],
      lockParentWindow: true,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    String text;
    try {
      text = await File(path).readAsString();
    } on FormatException {
      // 银行和老版 Excel 导出的多半是 GBK/ANSI，UTF-8 读就是乱码加异常
      _setImportNote('这个文件不是 UTF-8 编码（很多银行导出的其实是 GBK/ANSI）。'
          '在表格软件里另存为"CSV UTF-8"再来一次。');
      return;
    } catch (e) {
      _setImportNote('读不到这个文件：$e');
      return;
    }
    await viewModel.loadCsv(text, path.split(Platform.pathSeparator).last);
  }

  void _setImportNote(String message) {
    viewModel.importNote.value = message;
    viewModel.preview.value = null;
  }

  Future<void> _confirmImport() async {
    final vm = viewModel;
    final rows = vm.preview.value?.rows ?? const <LedgerTx>[];
    if (rows.isEmpty) return;
    final lines = <String>[
      '这些会直接写进账本，成为已入账的流水，删起来得回明细一笔一笔挑。',
      if (vm.duplicateCount.value > 0)
        '其中有 ${vm.duplicateCount.value} 笔和已入账的很像（同日、同账户、同商户、同金额），导入不会替你合并。',
      if (vm.uncategorizedCount > 0) '${vm.uncategorizedCount} 笔对不上类别，会先留在未分类里。',
      if (vm.unmatchedAccountCount > 0)
        '${vm.unmatchedAccountCount} 笔的账户名对不上，按你刚选的兜底账户落。',
      if (vm.taggedCount > 0) '标签那一列暂时存不住，导进来会丢掉。',
    ];
    final ok = await showConfirmDialog(
      context,
      title: '导入 ${rows.length} 笔？',
      message: lines.join('\n'),
      confirmLabel: '导入',
    );
    if (!ok) return;
    final receipt = await vm.importAll();
    if (receipt == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(receipt)));
  }

  @override
  Widget buildContent(BuildContext context) {
    final m = AppTheme.metrics;
    return ScreenChrome(
      data: ScreenChromeData(
        title: '导入与导出',
        leading: appBarBackButton(context, prevRoutePath: '/ledger/settings'),
        actions: <Widget>[
          ToolIconButton(
            icon: StrokeIcons.refresh,
            tooltip: '刷新',
            onPressed: viewModel.reload,
          ),
          SizedBox(width: m.kSpace12),
        ],
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final m = AppTheme.metrics;
    return ListView(
      padding: EdgeInsets.fromLTRB(m.kSpace16, m.kSpace8, m.kSpace16, m.kSpace32),
      children: <Widget>[
        _Feedback(vm: viewModel),
        _ExportCard(vm: viewModel, onExport: _export, onPickDate: _pickDate),
        SizedBox(height: m.kSpace24),
        _ImportCard(
          vm: viewModel,
          onPick: _pickCsv,
          onImport: _confirmImport,
        ),
      ],
    );
  }
}

/// 一次写操作的回执 / 读失败
class _Feedback extends StatelessWidget {
  const _Feedback({required this.vm});

  final LedgerDataViewModel vm;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  /// 回执读的是普通字段 errorMessage（它不在 Rx 上），所以顺手读一次 lastMessage：
  /// Obx 的 builder 里一路可观察量都没碰到，Get 就直接报"improper use of Obx"
  Widget _build(BuildContext context) {
    final m = AppTheme.metrics;
    final message = vm.lastMessage.value;
    final error = vm.errorMessage;
    if (error != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: m.kSpace12),
        child: Row(
          children: <Widget>[
            DrawIcon(StrokeIcons.error, size: m.iconSize16, color: AppSemantic.of(context).danger.color),
            SizedBox(width: m.kSpace8),
            Expanded(child: Text(error, style: AppTextStyles.caption(context))),
          ],
        ),
      );
    }
    if (message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace12),
      child: Row(
        children: <Widget>[
          DrawIcon(StrokeIcons.checkCircle, size: m.iconSize16, color: AppSemantic.of(context).success.color),
          SizedBox(width: m.kSpace8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.caption(context).copyWith(
                color: AppSemantic.of(context).success.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.vm,
    required this.onExport,
    required this.onPickDate,
  });

  final LedgerDataViewModel vm;
  final VoidCallback onExport;
  final void Function({required bool start}) onPickDate;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  /// 整块 build 都在 Obx 里：这一页的候选胶囊改的就是这几个 Rx，
  /// 拆到子 widget 里读就观察不到了
  Widget _build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('导出', style: AppTextStyles.sectionTitle(context)),
              ),
              DrawIcon(StrokeIcons.download, size: m.iconSize18, color: s.textSecondary),
            ],
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '写出去的是文件，账本本身一个字都不动。',
            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
          ),
          LedgerField(
            label: '格式',
            hint: 'CSV 给人看、也能再导回来；JSON 字段与库里一一对应，给程序看',
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                TagChip(
                  label: 'CSV 表格',
                  selected: !vm.asJson.value,
                  onTap: () => vm.setFormat(json: false),
                ),
                TagChip(
                  label: 'JSON',
                  selected: vm.asJson.value,
                  onTap: () => vm.setFormat(json: true),
                ),
              ],
            ),
          ),
          LedgerField(
            label: '区间',
            child: Wrap(
              spacing: m.kSpace6,
              runSpacing: m.kSpace6,
              children: <Widget>[
                for (final preset in LedgerDataViewModel.kRangeChoices)
                  TagChip(
                    label: kLedgerRangeLabels[preset] ?? '',
                    selected: vm.range.value == preset,
                    onTap: () => vm.setRange(preset),
                  ),
              ],
            ),
          ),
          if (vm.range.value == LedgerRangePreset.custom) ...<Widget>[
            SizedBox(height: m.kSpace8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onPickDate(start: true),
                    icon: DrawIcon(StrokeIcons.calendarToday, size: m.iconSize16),
                    label: Text(vm.customStart.value.isEmpty ? '开始日期' : vm.customStart.value),
                  ),
                ),
                SizedBox(width: m.kSpace8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onPickDate(start: false),
                    icon: DrawIcon(StrokeIcons.calendarToday, size: m.iconSize16),
                    label: Text(vm.customEnd.value.isEmpty ? '结束日期' : vm.customEnd.value),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: m.kSpace12),
          Text(
            vm.exportPending.value > 0
                ? '这个区间里有 ${vm.exportCount.value} 笔已入账，另有 ${vm.exportPending.value} 笔待确认——'
                      '待确认的那几笔还没进账本，也不会出现在这份文件里。'
                : '这个区间里有 ${vm.exportCount.value} 笔已入账。',
            style: AppTextStyles.caption(context),
          ),
          SizedBox(height: m.kSpace12),
          FilledButton.icon(
            onPressed: vm.busy.value ? null : onExport,
            icon: DrawIcon(StrokeIcons.download, size: m.iconSize16),
            label: Text(vm.asJson.value ? '导出 JSON' : '导出 CSV'),
          ),
        ],
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.vm,
    required this.onPick,
    required this.onImport,
  });

  final LedgerDataViewModel vm;
  final VoidCallback onPick;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  Widget _build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final preview = vm.preview.value;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('导入', style: AppTextStyles.sectionTitle(context))),
              DrawIcon(StrokeIcons.upload, size: m.iconSize18, color: s.textSecondary),
            ],
          ),
          SizedBox(height: m.kSpace4),
          Text(
            '先预览再落库：对不上的列当场说清楚，不给你"导完才发现串行"的机会。',
            style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
          ),
          SizedBox(height: m.kSpace12),
          if (preview == null) ...<Widget>[
            OutlinedButton.icon(
              onPressed: vm.busy.value ? null : onPick,
              icon: DrawIcon(StrokeIcons.upload, size: m.iconSize16),
              label: const Text('选择 CSV 文件'),
            ),
            if (vm.importNote.value.isNotEmpty) ...<Widget>[
              SizedBox(height: m.kSpace10),
              _Note(text: vm.importNote.value, danger: true),
            ],
            SizedBox(height: m.kSpace12),
            const _FormatCheat(),
          ] else ...<Widget>[
            _PreviewRows(vm: vm, preview: preview, onPick: onPick),
            if (vm.unmatchedAccountCount > 0) ...<Widget>[
              LedgerField(
                label: '账户名对不上时落到',
                hint: '对不上的一共 ${vm.unmatchedAccountCount} 笔。不落账户也能导，之后在明细里一笔一笔改',
                child: Wrap(
                  spacing: m.kSpace6,
                  runSpacing: m.kSpace6,
                  children: <Widget>[
                    TagChip(
                      label: '不落账户',
                      selected: vm.fallbackAccountId.value == 0,
                      onTap: () => vm.fallbackAccountId.value = 0,
                    ),
                    for (final a in vm.accounts.where((a) => a.enabled))
                      TagChip(
                        label: a.name,
                        selected: vm.fallbackAccountId.value == a.id,
                        onTap: () => vm.fallbackAccountId.value = a.id,
                      ),
                  ],
                ),
              ),
            ],
            SizedBox(height: m.kSpace16),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: vm.busy.value ? null : onImport,
                    icon: DrawIcon(StrokeIcons.checkCircle, size: m.iconSize16),
                    label: Text(vm.busy.value ? '正在导入…' : '导入 ${preview.rows.length} 笔'),
                  ),
                ),
                SizedBox(width: m.kSpace10),
                TextButton(onPressed: vm.clearPreview, child: const Text('不要了')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 预览：读了几行、丢了几行、前几行长什么样
class _PreviewRows extends StatelessWidget {
  const _PreviewRows({
    required this.vm,
    required this.preview,
    required this.onPick,
  });

  final LedgerDataViewModel vm;
  final LedgerCsvPreview preview;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Obx(() => _build(context));

  /// 预览自己包一层 Obx：它读的 fileName / duplicateCount 和外层不是同一批，
  /// 换一份表格、多算出一笔重复的都得当场重画，而不是等外层碰巧因为别的改动重绘
  Widget _build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final notes = <String>[
      if (preview.skipped > 0) '${preview.skipped} 行日期或金额读不出来，已经丢掉',
      if (vm.uncategorizedCount > 0) '${vm.uncategorizedCount} 笔对不上类别，会落在未分类',
      if (vm.noAccountCount > 0) '${vm.noAccountCount} 笔没写账户',
      if (vm.duplicateCount.value > 0) '${vm.duplicateCount.value} 笔和已入账的很像',
      if (vm.taggedCount > 0) '标签那一列暂时存不住，导进来会丢掉',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                vm.fileName.value,
                style: AppTextStyles.rowTitle(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: onPick, child: const Text('换一份')),
          ],
        ),
        SizedBox(height: m.kSpace4),
        Text(
          '能读 ${preview.rows.length} 笔 · ${preview.hasHeader ? '认出了表头' : '没有表头，按标准列序读'}',
          style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
        ),
        if (notes.isNotEmpty) ...<Widget>[
          SizedBox(height: m.kSpace8),
          for (final n in notes) _Note(text: n),
        ],
        if (preview.warnings.isNotEmpty) ...<Widget>[
          SizedBox(height: m.kSpace8),
          for (final w in preview.warnings)
            Text(w, style: AppTextStyles.caption(context).copyWith(color: s.textTertiary)),
        ],
        SizedBox(height: m.kSpace12),
        for (final row in preview.rows.take(6)) _PreviewRow(tx: vm.bind(row)),
        if (preview.rows.length > 6)
          Padding(
            padding: EdgeInsets.only(top: m.kSpace6),
            child: Text(
              '后面还有 ${preview.rows.length - 6} 笔，界面只列前 6 笔',
              style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
            ),
          ),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.tx});

  final LedgerTx tx;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final tail = <String>[
      if (tx.accountName.isNotEmpty) tx.accountName else '没有账户',
      if (tx.categoryName.isNotEmpty) tx.categoryName else '未分类',
      if (tx.merchant.isNotEmpty) tx.merchant,
    ];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: m.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: m.kSpace80,
            child: Text(
              tx.dateLabel,
              style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              tail.join(' · '),
              style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: m.kSpace8),
          LedgerAmountText(
            amount: tx.amount,
            income: tx.isIncome,
            size: LedgerAmountSize.dense,
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    final color = danger ? s.danger.color : s.warning.color;
    return Padding(
      padding: EdgeInsets.only(bottom: m.kSpace4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: m.kSpace2),
            child: DrawIcon(StrokeIcons.info, size: m.iconSize14, color: color),
          ),
          SizedBox(width: m.kSpace6),
          Expanded(
            child: Text(text, style: AppTextStyles.caption(context).copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// 导入格式速查：把表头原样列出来，省得用户去翻文档
class _FormatCheat extends StatelessWidget {
  const _FormatCheat();

  @override
  Widget build(BuildContext context) {
    final m = AppTheme.metrics;
    final s = AppSemantic.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('表格要长什么样', style: AppTextStyles.overline(context)),
        SizedBox(height: m.kSpace6),
        Text(
          LedgerStubStore.csvColumns.join(' , '),
          style: AppTextStyles.caption(context).copyWith(color: s.textSecondary),
        ),
        SizedBox(height: m.kSpace6),
        Text(
          '只有"日期"和"金额"是必需的，列序打乱也行（认表头，不认第几列）；'
          '日期认 2026-03-05 / 2026/3/5 / 2026年3月5日 这几种写法；'
          '类别可以写成"父/子"两级。',
          style: AppTextStyles.caption(context),
        ),
        SizedBox(height: m.kSpace6),
        Text(
          '先导出一次，拿那份表改完再导回来，是最省事的路径。',
          style: AppTextStyles.caption(context).copyWith(color: s.textTertiary),
        ),
      ],
    );
  }
}
