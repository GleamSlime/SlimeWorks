import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:slime_works/core/utils/logger.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

const Loggers _logger = Loggers(name: '流水账增强');

/// 记账增强部分的桩数据仓库。
///
/// **只管后端还没有的那几样**：标签与标签组、记账模板、定时规则、附件、备份记录。
/// 流水/账户/类别仍然走 [LedgerService] 打到 Rust——那边已经有真实数据在跑，
/// 把整本账换成演示库会让刚修好的邮件账单看起来又丢了。
///
/// 方法名与签名按未来的 FFI 契约写（`Future` + 同名动词），下一轮把方法体换成
/// `rust_api.ledgerXxx()` 即可，界面代码一行不用改。
class LedgerStubStore {
  LedgerStubStore._();

  static final LedgerStubStore instance = LedgerStubStore._();

  static const String _keyEnabled = 'ledger_stub_enabled';

  SharedPreferences? _prefs;

  /// 界面文案里也要出现这个词，用户才不会把自己的演示数据当成真账
  static const String watermark = '演示数据';

  bool _enabled = false;
  bool get enabled => _enabled;

  final List<LedgerTagGroup> _groups = <LedgerTagGroup>[];
  final List<LedgerTag> _tags = <LedgerTag>[];
  final List<LedgerTxTemplate> _templates = <LedgerTxTemplate>[];
  final List<LedgerSchedule> _schedules = <LedgerSchedule>[];
  final List<LedgerBackup> _backups = <LedgerBackup>[];
  final List<LedgerAttachment> _attachments = <LedgerAttachment>[];
  int _nextId = 1000;

  int _id() => ++_nextId;

  Future<void> init() async {
    if (_groups.isNotEmpty) return;
    await _reseed();
  }

  /// 把仓库倒回刚播种的状态，给测试用（单例是进程级的，用例之间必须能清零）
  Future<void> resetForTest() async => _reseed();

  Future<void> _reseed() async {
    _groups.clear();
    _tags.clear();
    _templates.clear();
    _schedules.clear();
    _backups.clear();
    _attachments.clear();
    _nextId = 1000;
    _seed();
    try {
      _prefs = await SharedPreferences.getInstance();
      _enabled = _prefs?.getBool(_keyEnabled) ?? true;
    } catch (e) {
      await _logger.e('桩数据开关读取失败，按默认开启处理', e);
    }
  }

  /// 关掉之后这些接口一律返回空表，页面退回"后端未接入"的空态
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_keyEnabled, value);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 标签
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LedgerTagGroup>> listTagGroups() async => List<LedgerTagGroup>.of(_groups);

  /// 平铺的标签表；groupId 传 0 表示全要
  Future<List<LedgerTag>> listTags({int groupId = 0}) async => [
    for (final t in _tags)
      if (groupId == 0 || t.groupId == groupId) t,
  ];

  Future<int> upsertTagGroup(LedgerTagGroup group) async {
    if (group.id == 0) {
      final created = LedgerTagGroup(
        id: _id(),
        name: group.name,
        color: group.color,
        sortOrder: group.sortOrder,
        tags: group.tags,
      );
      _groups.add(created);
      for (final t in created.tags) {
        _tags.add(LedgerTag(
          id: _id(),
          name: t.name,
          groupId: created.id,
          color: t.color,
          sortOrder: t.sortOrder,
        ));
      }
      return created.id;
    }
    final index = _groups.indexWhere((g) => g.id == group.id);
    if (index >= 0) _groups[index] = group;
    return group.id;
  }

  Future<void> deleteTagGroup(int id) async {
    _groups.removeWhere((g) => g.id == id);
    _tags.removeWhere((t) => t.groupId == id);
  }

  /// 就地新建标签用：名字重复就直接复用已有那条，不造两个一样的标签
  Future<LedgerTag> upsertTagByName(String name, {int groupId = 0}) async {
    final trimmed = name.trim();
    for (final t in _tags) {
      if (t.name == trimmed && t.groupId == groupId) return t;
    }
    final tag = LedgerTag(id: _id(), name: trimmed, groupId: groupId);
    _tags.add(tag);
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _groups[index] = _groups[index].copyWith(tags: <LedgerTag>[..._groups[index].tags, tag]);
    }
    return tag;
  }

  Future<int> upsertTag(LedgerTag tag) async {
    if (tag.id == 0) {
      final created = LedgerTag(
        id: _id(),
        name: tag.name,
        groupId: tag.groupId,
        color: tag.color,
        sortOrder: tag.sortOrder,
      );
      _tags.add(created);
      final index = _groups.indexWhere((g) => g.id == created.groupId);
      if (index >= 0) {
        _groups[index] = _groups[index].copyWith(tags: <LedgerTag>[..._groups[index].tags, created]);
      }
      return created.id;
    }
    final index = _tags.indexWhere((t) => t.id == tag.id);
    if (index >= 0) _tags[index] = tag;
    _rebuildGroupTags();
    return tag.id;
  }

  Future<void> deleteTag(int id) async {
    _tags.removeWhere((t) => t.id == id);
    _rebuildGroupTags();
  }

  void _rebuildGroupTags() {
    for (var i = 0; i < _groups.length; i++) {
      final g = _groups[i];
      _groups[i] = g.copyWith(
        tags: _tags.where((t) => t.groupId == g.id).toList(growable: false),
      );
    }
  }

  /// 标签的引用次数：删之前要告诉用户有几笔流水挂着它
  int tagUseCount(int tagId) => _tags.firstWhere((t) => t.id == tagId, orElse: () => const LedgerTag()).useCount;

  // ─────────────────────────────────────────────────────────────────────────
  // 模板
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LedgerTxTemplate>> listTxTemplates() async => List<LedgerTxTemplate>.of(_templates);

  Future<int> upsertTxTemplate(LedgerTxTemplate template) async {
    if (template.id == 0) {
      final created = LedgerTxTemplate(
        id: _id(),
        title: template.title,
        txType: template.txType,
        direction: template.direction,
        amount: template.amount,
        destAmount: template.destAmount,
        accountId: template.accountId,
        destAccountId: template.destAccountId,
        categoryId: template.categoryId,
        tagIds: template.tagIds,
        merchant: template.merchant,
        note: template.note,
        useCount: 0,
        accountName: template.accountName,
        destAccountName: template.destAccountName,
        categoryName: template.categoryName,
        categoryIcon: template.categoryIcon,
        tagNames: template.tagNames,
      );
      _templates.add(created);
      return created.id;
    }
    final index = _templates.indexWhere((t) => t.id == template.id);
    if (index >= 0) _templates[index] = template;
    return template.id;
  }

  Future<void> deleteTxTemplate(int id) async {
    _templates.removeWhere((t) => t.id == id);
    _schedules.removeWhere((s) => s.templateId == id);
  }

  /// 用一次：计数 +1，界面上"常用模板"就靠这个排序
  Future<void> markTemplateUsed(int id) async {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final t = _templates[index];
    _templates[index] = LedgerTxTemplate.fromJson(<String, dynamic>{
      ...t.toJson(),
      'use_count': t.useCount + 1,
    });
  }

  /// 流水存成模板：只带走重复要填的那几样，日期与 id 一律丢掉。
  ///
  /// [basedOn] 非空就是**改一张已有模板**——id、使用次数、创建时间原样留着，
  /// 不然每改一次就变成一张新模板，"常用"排序也就废了。
  static LedgerTxTemplate templateOf(
    LedgerTx tx, {
    String title = '',
    LedgerTxTemplate? basedOn,
  }) {
    // 标题沿用"商户优先、没有商户看备注"这条老规则；两个都被清空了就用原名，
    // 免得改一次模板就变成一张没有名字的卡片。
    final auto = tx.merchant.isNotEmpty ? tx.merchant : tx.note;
    final name = title.isNotEmpty
        ? title
        : (auto.isNotEmpty ? auto : (basedOn?.title ?? ''));
    return LedgerTxTemplate(
      id: basedOn?.id ?? 0,
      title: name,
      createdAt: basedOn?.createdAt ?? '',
      useCount: basedOn?.useCount ?? 0,
      txType: tx.effectiveType,
      direction: tx.direction,
      amount: tx.amount,
      destAmount: tx.destAmount,
      accountId: tx.accountId,
      destAccountId: tx.destAccountId,
      categoryId: tx.categoryId,
      tagIds: tx.tagIds,
      merchant: tx.merchant,
      note: tx.note,
      accountName: tx.accountName,
      destAccountName: tx.destAccountName,
      categoryName: tx.categoryName,
      categoryIcon: tx.categoryIcon,
      tagNames: tx.tagNames,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 定时记账
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LedgerSchedule>> listSchedules() async => List<LedgerSchedule>.of(_schedules);

  Future<int> upsertSchedule(LedgerSchedule schedule) async {
    if (schedule.id == 0) {
      final created = LedgerSchedule(
        id: _id(),
        name: schedule.name,
        templateId: schedule.templateId,
        repeat: schedule.repeat,
        dayOfMonth: schedule.dayOfMonth,
        weekday: schedule.weekday,
        timeOfDay: schedule.timeOfDay,
        startDate: schedule.startDate,
        endDate: schedule.endDate,
        enabled: schedule.enabled,
        nextRunAt: _guessNextRun(schedule),
        templateTitle: schedule.templateTitle,
      );
      _schedules.add(created);
      return created.id;
    }
    final index = _schedules.indexWhere((s) => s.id == schedule.id);
    if (index >= 0) _schedules[index] = schedule;
    return schedule.id;
  }

  Future<void> setScheduleEnabled(int id, bool enabled) async {
    final index = _schedules.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _schedules[index] = _schedules[index].copyWith(enabled: enabled);
  }

  Future<void> deleteSchedule(int id) async {
    _schedules.removeWhere((s) => s.id == id);
  }

  /// 只给个"下一次"的近似值撑住界面：真正的调度归 Rust 侧的调度器
  static String _guessNextRun(LedgerSchedule s) {
    final now = DateTime.now();
    final base = DateTime.tryParse(s.startDate) ?? now;
    final day = base.day > 28 ? 28 : base.day;
    final next = DateTime(now.year, now.month + (s.repeat == kLedgerRepeatYearly ? 12 : 1), day);
    return '${ledgerDateOf(next)} ${s.timeOfDay}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 附件（只有元信息，真正的文件下一轮才落盘）
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LedgerAttachment>> listAttachmentsOf(List<int> ids) async => [
    for (final a in _attachments)
      if (ids.contains(a.id)) a,
  ];

  /// "选文件"在桩阶段就是编一条元信息出来，让缩略位/计数/删除都有东西可画。
  /// 名字和大小都按第几条推，不掺时钟：出图基线受不起每跑一次换个文件名。
  Future<LedgerAttachment> addAttachment({String? fileName, int sizeBytes = 0}) async {
    final seq = _attachments.length + 1;
    final name = fileName ?? '凭证-$seq.jpg';
    final mime = name.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';
    final att = LedgerAttachment(
      id: _id(),
      fileName: name,
      mimeType: mime,
      sizeBytes: sizeBytes > 0 ? sizeBytes : 40960 + seq * 900,
    );
    _attachments.add(att);
    return att;
  }

  Future<void> deleteAttachment(int id) async {
    _attachments.removeWhere((a) => a.id == id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 备份
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<LedgerBackup>> listBackups() async => List<LedgerBackup>.of(_backups);

  Future<void> addBackup(LedgerBackup backup) async {
    _backups.insert(0, backup);
    if (_backups.length > 20) _backups.removeLast();
  }

  Future<void> deleteBackup(int id) async {
    _backups.removeWhere((b) => b.id == id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CSV：导出与导入都在这一轮真正跑通（纯文本，不碰库）
  // ─────────────────────────────────────────────────────────────────────────

  /// 导出的列顺序，也是导入时"标准格式"的表头
  static const List<String> csvColumns = <String>[
    '日期',
    '类型',
    '方向',
    '金额',
    '账户',
    '对方账户',
    '类别',
    '标签',
    '商户',
    '备注',
    '来源',
  ];

  static String encodeCsv(List<LedgerTx> rows) {
    final buf = StringBuffer(csvColumns.join(','));
    for (final tx in rows) {
      buf
        ..write('\n')
        ..write(<String>[
          tx.dateLabel,
          ledgerTxTypeName(tx.effectiveType),
          tx.isIncome ? '收入' : '支出',
          tx.amount.toStringAsFixed(2),
          tx.accountName,
          tx.destAccountName,
          tx.categoryName,
          tx.tagNames.join('|'),
          tx.merchant,
          tx.note,
          tx.source == kLedgerSourceEmail ? '邮件' : '手动',
        ].map(_csvCell).join(','));
    }
    return buf.toString();
  }

  static String _csvCell(String raw) {
    final v = raw.replaceAll('"', '""');
    return (v.contains(',') || v.contains('"') || v.contains('\n')) ? '"$v"' : v;
  }

  /// 按表头映射解析。列名对不上时给中文错误而不是抛格式异常——这是用户手改的表格。
  static LedgerCsvPreview decodeCsv(String text, {Map<String, String> columnMap = const <String, String>{}}) {
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return const LedgerCsvPreview(error: '文件是空的');
    }
    final header = _splitCsvLine(lines.first);
    final hasHeader = header.any((h) => csvColumns.contains(h.trim()));
    final body = hasHeader ? lines.sublist(1) : lines;
    final columns = hasHeader ? header : List<String>.filled(csvColumns.length, '');

    final index = <String, int>{};
    for (var i = 0; i < columns.length; i++) {
      final mapped = columnMap[columns[i].trim()];
      final key = (mapped != null && mapped.isNotEmpty) ? mapped : columns[i].trim();
      if (csvColumns.contains(key) || kCsvCanonical.containsKey(key)) {
        index[kCsvCanonical[key] ?? key] = i;
      }
    }
    if (!index.containsKey('日期') || !index.containsKey('金额')) {
      return const LedgerCsvPreview(error: '至少要能对上"日期"和"金额"两列');
    }

    final rows = <LedgerTx>[];
    final skipped = <String>[];
    for (var n = 0; n < body.length; n++) {
      final cells = _splitCsvLine(body[n]);
      String at(String col) {
        final i = index[col];
        return (i == null || i >= cells.length) ? '' : cells[i].trim();
      }

      final date = _normalizeDate(at('日期'));
      final amount = double.tryParse(at('金额').replaceAll(',', ''));
      if (date == null || amount == null) {
        skipped.add('第 ${n + 2} 行：日期或金额读不出来');
        continue;
      }
      final type = at('类型');
      rows.add(LedgerTx(
        billDate: date,
        occurredAt: '$date 00:00',
        txType: kCsvTypeNameReverse[type] ?? kLedgerTxTypeExpense,
        direction: at('方向') == '收入' ? kLedgerDirectionIncome : kLedgerDirectionExpense,
        amount: amount.abs(),
        merchant: at('商户'),
        note: at('备注'),
        categoryName: at('类别'),
        accountName: at('账户'),
        tagNames: at('标签').isEmpty ? const <String>[] : at('标签').split('|'),
      ));
    }
    return LedgerCsvPreview(
      rows: rows,
      warnings: skipped.take(5).toList(growable: false),
      skipped: skipped.length,
      hasHeader: hasHeader,
    );
  }

  /// 用户导出的表格列名五花八门，这里只认几种常见写法
  static const Map<String, String> kCsvCanonical = <String, String>{
    'date': '日期',
    'time': '日期',
    'amount': '金额',
    'account': '账户',
    'category': '类别',
    'merchant': '商户',
    'note': '备注',
    'comment': '备注',
    'tags': '标签',
    'type': '类型',
  };

  static List<String> _splitCsvLine(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  static String? _normalizeDate(String raw) {
    if (raw.isEmpty) return null;
    final slashed = raw.replaceAll(RegExp(r'[./年月]'), '-').replaceAll('日', '');
    final parts = slashed.split('-').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2].replaceAll(RegExp(r'[^0-9]'), ''));
    if (y == null || m == null || d == null || y < 1970) return null;
    // 月份/日期超出范围也按"读不出来"处理：2026-13-40 写得进预览就会写得进库，
    // 而库里那一笔的日期是空的，比丢掉更糟——用户看不见它，也没法改它。
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 桩数据
  // ─────────────────────────────────────────────────────────────────────────

  void _seed() {
    final groupDefs = <(String, String, List<String>)>[
      ('工作', '#5B8FF9', <String>['出差', '客户名：张三', '可报销', '项目 A']),
      ('家庭', '#61DDAA', <String>['家庭日常', '父母', '孩子']),
      ('习惯', '#F6BD16', <String>['咖啡', '健身', '订阅服务']),
      ('待办核销', '#E8684A', <String>['待报销', '已平账']),
    ];
    for (final (name, color, tagNames) in groupDefs) {
      final gid = _id();
      final tags = <LedgerTag>[
        for (var i = 0; i < tagNames.length; i++)
          LedgerTag(
            id: _id(),
            name: tagNames[i],
            groupId: gid,
            color: color,
            useCount: (i * 7 + 3) % 19,
            sortOrder: i,
          ),
      ];
      _tags.addAll(tags);
      _groups.add(LedgerTagGroup(id: gid, name: name, color: color, tags: tags));
    }

    // 模板存的是"名字"而不是类别/账户 id：id 归 Rust 的库管，桩里写死的数字在真机上
    // 多半指向别的东西。名字在编辑器里会按当前列表再认一次，认不到就留空让用户选，
    // 比默认选到一个错的类别上要好。类别名与图标照 BUILTIN_CATEGORIES 写，
    // 账户只敢用建库必有的那个"现金"——其余账户名是用户自己起的。
    final tplDefs = <(String, String, String, double, String, String)>[
      ('午餐', '餐饮美食', 'restaurant', 32, '现金', '外卖/堂食'),
      ('咖啡', '餐饮美食', 'restaurant', 18, '现金', '咖啡'),
      ('地铁通勤', '交通出行', 'bus', 6, '现金', '地铁'),
      ('房租', '居家缴费', 'home', 3200, '', '每月房租'),
      ('视频会员', '休闲娱乐', 'game', 25, '', '自动续费'),
      ('话费充值', '通讯网络', 'deviceSimChat', 50, '', '中国移动'),
    ];
    for (final (title, categoryName, categoryIcon, amount, accountName, merchant)
        in tplDefs) {
      _templates.add(LedgerTxTemplate(
        id: _id(),
        title: title,
        direction: kLedgerDirectionExpense,
        amount: amount,
        merchant: merchant,
        categoryName: categoryName,
        categoryIcon: categoryIcon,
        accountName: accountName,
        useCount: title.length * 3,
      ));
    }
    int templateIdOf(String title) => _templates.firstWhere((t) => t.title == title).id;

    // 播种日期写死，不用 DateTime.now()：这一页要出 golden 基线，
    // 跟着时钟走的"下次"会让基线图每个月自己变红一次。
    // _guessNextRun 仍然按当前时间推，那是用户刚建的规则该看的值，
    // 但它不参与任何基线。
    _schedules.addAll(<LedgerSchedule>[
      LedgerSchedule(
        id: _id(),
        name: '每月房租',
        templateId: templateIdOf('房租'),
        repeat: kLedgerRepeatMonthly,
        dayOfMonth: 1,
        timeOfDay: '09:00',
        startDate: '2026-03-01',
        nextRunAt: '2026-04-01 09:00',
        templateTitle: '房租',
      ),
      LedgerSchedule(
        id: _id(),
        name: '视频会员续费',
        templateId: templateIdOf('视频会员'),
        repeat: kLedgerRepeatMonthly,
        dayOfMonth: 15,
        timeOfDay: '10:30',
        startDate: '2026-03-15',
        endDate: '2027-03-14',
        enabled: false,
        nextRunAt: '2026-04-15 10:30',
        templateTitle: '视频会员',
      ),
    ]);

    _backups.addAll(<LedgerBackup>[
      LedgerBackup(id: _id(), fileName: 'ledger-20260928.json', sizeBytes: 184320, createdAt: '2026-09-28 23:10'),
      LedgerBackup(id: _id(), fileName: 'ledger-20260901.csv', sizeBytes: 46210, createdAt: '2026-09-01 08:42'),
    ]);

    _attachments.addAll(<LedgerAttachment>[
      LedgerAttachment(id: _id(), fileName: '小票-0928.jpg', mimeType: 'image/jpeg', sizeBytes: 236544),
      LedgerAttachment(id: _id(), fileName: '合同扫描件.pdf', mimeType: 'application/pdf', sizeBytes: 1204224),
    ]);
  }
}

/// CSV 导入的解析产物：先预览再落库，不给"导入完才发现列错了"留机会
class LedgerCsvPreview {
  const LedgerCsvPreview({
    this.rows = const <LedgerTx>[],
    this.warnings = const <String>[],
    this.skipped = 0,
    this.hasHeader = true,
    this.error,
  });

  final List<LedgerTx> rows;
  final List<String> warnings;
  final int skipped;
  final bool hasHeader;
  final String? error;

  bool get ok => error == null && rows.isNotEmpty;
}

/// 一次备份的元信息
class LedgerBackup {
  const LedgerBackup({
    this.id = 0,
    this.fileName = '',
    this.sizeBytes = 0,
    this.createdAt = '',
  });

  final int id;
  final String fileName;
  final int sizeBytes;
  final String createdAt;

  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

String ledgerTxTypeName(String txType) => switch (txType) {
  kLedgerTxTypeIncome => '收入',
  kLedgerTxTypeTransfer => '转账',
  kLedgerTxTypeBalance => '余额调整',
  _ => '支出',
};

const Map<String, String> kCsvTypeNameReverse = <String, String>{
  '支出': kLedgerTxTypeExpense,
  '收入': kLedgerTxTypeIncome,
  '转账': kLedgerTxTypeTransfer,
  '余额调整': kLedgerTxTypeBalance,
};
