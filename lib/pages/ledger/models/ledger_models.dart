/// 流水账的数据模型。
///
/// 字段名与 Rust `ledger_module` 的 serde 输出逐字对齐（snake_case），
/// 所以这里只做一次 Map 读取，不引入代码生成依赖。
/// 金额一律正数存储，正负由 direction 决定，避免"收入记成负数"这类口径混乱。
library;

import 'dart:convert';

const String kLedgerDirectionExpense = 'expense';
const String kLedgerDirectionIncome = 'income';
const String kLedgerSourceManual = 'manual';
const String kLedgerSourceEmail = 'email';
const String kLedgerStatusPending = 'pending';
const String kLedgerStatusPosted = 'posted';
const String kLedgerStatusIgnored = 'ignored';

/// 记账类型。
///
/// 与 [kLedgerDirectionExpense] 那组"方向"不是一回事：方向只有收/支两值，
/// 是汇总口径（邮件流水解析出来天然只有方向）；类型多了转账和余额调整，
/// 它们既不算收入也不算支出，混进方向就会把"这个月花了多少"顶歪。
/// 库里没这一列时按方向回落成支出/收入，老数据一行都不用迁。
const String kLedgerTxTypeExpense = 'expense';
const String kLedgerTxTypeIncome = 'income';
const String kLedgerTxTypeTransfer = 'transfer';
const String kLedgerTxTypeBalance = 'balance';

/// 一次最多挂几个标签：超过这个数说明在拿标签当分类用，提醒一句而不是硬拦
const int kLedgerTagLimit = 10;

/// 定时记账的重复频率
const String kLedgerRepeatDaily = 'daily';
const String kLedgerRepeatWeekly = 'weekly';
const String kLedgerRepeatBiweekly = 'biweekly';
const String kLedgerRepeatMonthly = 'monthly';
const String kLedgerRepeatQuarterly = 'quarterly';
const String kLedgerRepeatYearly = 'yearly';

const Map<String, String> kLedgerRepeatLabels = <String, String>{
  kLedgerRepeatDaily: '每天',
  kLedgerRepeatWeekly: '每周',
  kLedgerRepeatBiweekly: '每两周',
  kLedgerRepeatMonthly: '每月',
  kLedgerRepeatQuarterly: '每季',
  kLedgerRepeatYearly: '每年',
};

/// 下标就是 Dart 的 weekday（1=周一…7=周日），0 留给周日取模后的落点
const List<String> kLedgerWeekdayLabels = <String>['日', '一', '二', '三', '四', '五', '六'];

/// 记账表单的落库结果：`duplicate` 不是错误，是要用户拍板的中间态
enum LedgerSaveResult { saved, duplicate, failed }

Map<String, dynamic> _map(Object? raw) => switch (raw) {
  Map<String, dynamic> m => m,
  Map m => m.map((k, v) => MapEntry(k.toString(), v)),
  _ => <String, dynamic>{},
};

List<Map<String, dynamic>> _mapList(Object? raw) => switch (raw) {
  List list => list.map(_map).toList(),
  _ => const <Map<String, dynamic>>[],
};

String _s(Map<String, dynamic> m, String k) => (m[k] ?? '').toString();

int _i(Map<String, dynamic> m, String k) => switch (m[k]) {
  num n => n.toInt(),
  String str => int.tryParse(str) ?? 0,
  _ => 0,
};

double _d(Map<String, dynamic> m, String k) => switch (m[k]) {
  num n => n.toDouble(),
  String str => double.tryParse(str) ?? 0.0,
  _ => 0.0,
};

bool _b(Map<String, dynamic> m, String k) => switch (m[k]) {
  bool v => v,
  num n => n != 0,
  _ => false,
};

double? _dOpt(Map<String, dynamic> m, String k) => m[k] == null ? null : _d(m, k);

int? _iOpt(Map<String, dynamic> m, String k) => m[k] == null ? null : _i(m, k);

List<int> _iList(Map<String, dynamic> m, String k) => switch (m[k]) {
  List list => list.map(_num).toList(growable: false),
  _ => const <int>[],
};

List<String> _sList(Map<String, dynamic> m, String k) => switch (m[k]) {
  List list => list.map((e) => e.toString()).toList(growable: false),
  _ => const <String>[],
};

int _num(Object? raw) => switch (raw) {
  num n => n.toInt(),
  String str => int.tryParse(str) ?? 0,
  _ => 0,
};

/// 账户：信用卡/借记卡/现金/存款
class LedgerAccount {
  const LedgerAccount({
    this.id = 0,
    this.name = '',
    this.type = 'credit_card',
    this.last4 = '',
    this.currency = 'CNY',
    this.creditLimit = 0,
    this.balance = 0,
    this.sortOrder = 0,
    this.enabled = true,
    this.createdAt = '',
  });

  final int id;
  final String name;
  final String type;
  final String last4;
  final String currency;
  final double creditLimit;
  final double balance;
  final int sortOrder;
  final bool enabled;
  final String createdAt;

  /// 尾号展示：信用卡显示"尾号 9842"，现金类不显示
  String get displaySuffix => last4.isEmpty ? '' : '尾号$last4';

  LedgerAccount copyWith({
    int? id,
    String? name,
    String? type,
    String? last4,
    String? currency,
    double? creditLimit,
    double? balance,
    int? sortOrder,
    bool? enabled,
  }) => LedgerAccount(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    last4: last4 ?? this.last4,
    currency: currency ?? this.currency,
    creditLimit: creditLimit ?? this.creditLimit,
    balance: balance ?? this.balance,
    sortOrder: sortOrder ?? this.sortOrder,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'type': type,
    'last4': last4,
    'currency': currency,
    'credit_limit': creditLimit,
    'balance': balance,
    'sort_order': sortOrder,
    'enabled': enabled,
  };

  factory LedgerAccount.fromJson(Map<String, dynamic> j) => LedgerAccount(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    type: _s(j, 'type').isEmpty ? 'credit_card' : _s(j, 'type'),
    last4: _s(j, 'last4'),
    currency: _s(j, 'currency').isEmpty ? 'CNY' : _s(j, 'currency'),
    creditLimit: _d(j, 'credit_limit'),
    balance: _d(j, 'balance'),
    sortOrder: _i(j, 'sort_order'),
    enabled: j.containsKey('enabled') ? _b(j, 'enabled') : true,
    createdAt: _s(j, 'created_at'),
  );
}

/// 收支类别
///
/// 两级：`parent_id == 0` 是父类，其余挂在某个父类下面。记账时只能选叶子，
/// 统计时按父类汇总——"餐饮"下再分"早餐/午餐/咖啡"这种需求，一级列表放不下。
class LedgerCategory {
  const LedgerCategory({
    this.id = 0,
    this.name = '',
    this.icon = '',
    this.direction = kLedgerDirectionExpense,
    this.sortOrder = 0,
    this.isBuiltin = false,
    this.parentId = 0,
    this.color = '',
  });

  final int id;
  final String name;
  final String icon;
  final String direction;
  final int sortOrder;
  final bool isBuiltin;
  final int parentId;

  /// `#RRGGBB`，空串=跟类别名走语义色（图表要稳定的颜色，不能按 index 轮询）
  final String color;

  bool get isIncome => direction == kLedgerDirectionIncome;
  bool get isRoot => parentId == 0;

  LedgerCategory copyWith({
    String? name,
    String? icon,
    String? direction,
    int? sortOrder,
    int? parentId,
    String? color,
  }) => LedgerCategory(
    id: id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    direction: direction ?? this.direction,
    sortOrder: sortOrder ?? this.sortOrder,
    isBuiltin: isBuiltin,
    parentId: parentId ?? this.parentId,
    color: color ?? this.color,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'icon': icon,
    'direction': direction,
    'sort_order': sortOrder,
    'parent_id': parentId,
    'color': color,
  };

  factory LedgerCategory.fromJson(Map<String, dynamic> j) => LedgerCategory(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    icon: _s(j, 'icon'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    sortOrder: _i(j, 'sort_order'),
    isBuiltin: _b(j, 'is_builtin'),
    parentId: _i(j, 'parent_id'),
    color: _s(j, 'color'),
  );
}

/// 一笔流水
class LedgerTx {
  const LedgerTx({
    this.id = 0,
    this.occurredAt = '',
    this.billDate = '',
    this.direction = kLedgerDirectionExpense,
    this.txType = '',
    this.amount = 0,
    this.currency = 'CNY',
    this.accountId = 0,
    this.destAccountId = 0,
    this.destAmount = 0,
    this.categoryId = 0,
    this.merchant = '',
    this.note = '',
    this.tagIds = const <int>[],
    this.attachments = const <LedgerAttachment>[],
    this.source = kLedgerSourceManual,
    this.ruleId = 0,
    this.emailUid = '',
    this.status = kLedgerStatusPosted,
    this.createdAt = '',
    this.updatedAt = '',
    this.accountName = '',
    this.destAccountName = '',
    this.categoryName = '',
    this.categoryIcon = '',
    this.categoryDirection = '',
    this.tagNames = const <String>[],
    this.hidden = false,
  });

  final int id;
  final String occurredAt;
  final String billDate;
  final String direction;

  /// 空串=旧数据，此时 [effectiveType] 按 direction 回落
  final String txType;
  final double amount;
  final String currency;
  final int accountId;

  /// 转账的落点账户；非转账恒为 0
  final int destAccountId;

  /// 转账到落点的实际到账数（跨账户换算时有出入），0 表示与 [amount] 相同
  final double destAmount;
  final int categoryId;
  final String merchant;
  final String note;
  final List<int> tagIds;
  final List<LedgerAttachment> attachments;
  final String source;
  final int ruleId;
  final String emailUid;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String accountName;
  final String destAccountName;
  final String categoryName;
  final String categoryIcon;
  final String categoryDirection;
  final List<String> tagNames;

  /// 这一笔的金额在列表里打码（公共场合记账，不想让金额跟着截图一起出去）
  final bool hidden;

  String get effectiveType => txType.isEmpty ? direction : txType;
  bool get isIncome => direction == kLedgerDirectionIncome;
  bool get isPending => status == kLedgerStatusPending;
  bool get isIgnored => status == kLedgerStatusIgnored;
  bool get fromEmail => source == kLedgerSourceEmail;
  bool get isTransfer => effectiveType == kLedgerTxTypeTransfer;
  bool get isBalanceAdjust => effectiveType == kLedgerTxTypeBalance;

  /// 转账/余额调整不进收支汇总：把"从储蓄卡挪 5000 到理财"算成支出，
  /// 一个月的支出曲线就会被自己造的搬运刷成灾难。
  bool get countsInFlow => !isTransfer && !isBalanceAdjust;

  /// 这一笔让账户余额变化多少（转账看的是出账那一侧）
  double get signedAmount => isIncome ? amount : -amount;

  /// 落点侧的变化：转账只有这里用得到
  double get destSignedAmount => destAmount <= 0 ? amount : destAmount;

  DateTime get occurredDateTime => DateTime.tryParse(occurredAt.replaceFirst(' ', 'T')) ??
      (DateTime.tryParse(billDate) ?? DateTime.now());

  /// 展示用的"HH:MM"，邮件流水靠它区分同一天多笔
  String get timeLabel {
    if (occurredAt.length >= 16) return occurredAt.substring(11, 16);
    return '';
  }

  String get dateLabel => billDate.isEmpty ? occurredAt.substring(0, 10) : billDate;

  /// 照着这一笔再记一笔：id 归零、日期换成今天、来源退回手动。
  ///
  /// 邮件抓来的那笔带着 rule_id/email_uid，直接复用会被当成重复账单丢掉，
  /// 所以复制出来的必须是"人手记的"那一类。时刻保留原样，只换日期。
  LedgerTx get asDraft {
    final now = ledgerDateOf(DateTime.now());
    final clock = occurredAt.length >= 19 ? occurredAt.substring(11, 19) : '00:00:00';
    return LedgerTx(
      occurredAt: '$now $clock',
      billDate: now,
      direction: direction,
      txType: txType,
      amount: amount,
      currency: currency,
      accountId: accountId,
      destAccountId: destAccountId,
      destAmount: destAmount,
      categoryId: categoryId,
      merchant: merchant,
      note: note,
      tagIds: tagIds,
      attachments: const <LedgerAttachment>[],
      status: kLedgerStatusPosted,
      accountName: accountName,
      destAccountName: destAccountName,
      categoryName: categoryName,
      categoryIcon: categoryIcon,
      categoryDirection: categoryDirection,
      tagNames: tagNames,
      hidden: hidden,
    );
  }

  LedgerTx copyWith({
    int? accountId,
    int? categoryId,
    String? direction,
    String? txType,
    double? amount,
    int? destAccountId,
    double? destAmount,
    String? merchant,
    String? note,
    String? billDate,
    String? occurredAt,
    String? status,
    List<int>? tagIds,
    List<LedgerAttachment>? attachments,
    String? categoryName,
    String? categoryIcon,
    String? categoryDirection,
    String? accountName,
    String? destAccountName,
    List<String>? tagNames,
    bool? hidden,
  }) => LedgerTx(
    id: id,
    occurredAt: occurredAt ?? this.occurredAt,
    billDate: billDate ?? this.billDate,
    direction: direction ?? this.direction,
    txType: txType ?? this.txType,
    amount: amount ?? this.amount,
    currency: currency,
    accountId: accountId ?? this.accountId,
    destAccountId: destAccountId ?? this.destAccountId,
    destAmount: destAmount ?? this.destAmount,
    categoryId: categoryId ?? this.categoryId,
    merchant: merchant ?? this.merchant,
    note: note ?? this.note,
    tagIds: tagIds ?? this.tagIds,
    attachments: attachments ?? this.attachments,
    source: source,
    ruleId: ruleId,
    emailUid: emailUid,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    accountName: accountName ?? this.accountName,
    destAccountName: destAccountName ?? this.destAccountName,
    categoryName: categoryName ?? this.categoryName,
    categoryIcon: categoryIcon ?? this.categoryIcon,
    categoryDirection: categoryDirection ?? this.categoryDirection,
    tagNames: tagNames ?? this.tagNames,
    hidden: hidden ?? this.hidden,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'occurred_at': occurredAt,
    'bill_date': billDate,
    'direction': direction,
    'tx_type': effectiveType,
    'amount': amount,
    'currency': currency,
    'account_id': accountId,
    'dest_account_id': destAccountId,
    'dest_amount': destAmount,
    'category_id': categoryId,
    'merchant': merchant,
    'note': note,
    'tag_ids': tagIds,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'source': source,
    'rule_id': ruleId,
    'email_uid': emailUid,
    'status': status,
    'hidden': hidden,
  };

  factory LedgerTx.fromJson(Map<String, dynamic> j) => LedgerTx(
    id: _i(j, 'id'),
    occurredAt: _s(j, 'occurred_at'),
    billDate: _s(j, 'bill_date'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    txType: _s(j, 'tx_type'),
    amount: _d(j, 'amount'),
    currency: _s(j, 'currency').isEmpty ? 'CNY' : _s(j, 'currency'),
    accountId: _i(j, 'account_id'),
    destAccountId: _i(j, 'dest_account_id'),
    destAmount: _d(j, 'dest_amount'),
    categoryId: _i(j, 'category_id'),
    merchant: _s(j, 'merchant'),
    note: _s(j, 'note'),
    tagIds: _iList(j, 'tag_ids'),
    attachments: _mapList(j['attachments']).map(LedgerAttachment.fromJson).toList(growable: false),
    source: _s(j, 'source').isEmpty ? kLedgerSourceManual : _s(j, 'source'),
    ruleId: _i(j, 'rule_id'),
    emailUid: _s(j, 'email_uid'),
    status: _s(j, 'status').isEmpty ? kLedgerStatusPosted : _s(j, 'status'),
    createdAt: _s(j, 'created_at'),
    updatedAt: _s(j, 'updated_at'),
    accountName: _s(j, 'account_name'),
    destAccountName: _s(j, 'dest_account_name'),
    categoryName: _s(j, 'category_name'),
    categoryIcon: _s(j, 'category_icon'),
    categoryDirection: _s(j, 'category_direction'),
    tagNames: _sList(j, 'tag_names'),
    hidden: _b(j, 'hidden'),
  );
}

/// 标签：跨分类的第二条检索轴
///
/// 分类必须单选、且是一棵固定的树；标签回答的是"这笔是谁花的、走哪个项目"，
/// 一笔可以挂好几个。分组只是标签的抽屉，不参与记账口径。
class LedgerTag {
  const LedgerTag({
    this.id = 0,
    this.name = '',
    this.groupId = 0,
    this.color = '',
    this.useCount = 0,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final int groupId;
  final String color;

  /// 挂在几笔流水上；删之前要给用户看这个数
  final int useCount;
  final int sortOrder;

  LedgerTag copyWith({String? name, int? groupId, String? color, int? sortOrder}) => LedgerTag(
    id: id,
    name: name ?? this.name,
    groupId: groupId ?? this.groupId,
    color: color ?? this.color,
    useCount: useCount,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'group_id': groupId,
    'color': color,
    'sort_order': sortOrder,
  };

  factory LedgerTag.fromJson(Map<String, dynamic> j) => LedgerTag(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    groupId: _i(j, 'group_id'),
    color: _s(j, 'color'),
    useCount: _i(j, 'use_count'),
    sortOrder: _i(j, 'sort_order'),
  );
}

/// 标签分组（"出差报销""家庭"这类抽屉）
class LedgerTagGroup {
  const LedgerTagGroup({
    this.id = 0,
    this.name = '',
    this.color = '',
    this.sortOrder = 0,
    this.tags = const <LedgerTag>[],
  });

  final int id;
  final String name;
  final String color;
  final int sortOrder;

  /// 组内标签。后端一次带回，省得界面为每个组再发一轮请求
  final List<LedgerTag> tags;

  LedgerTagGroup copyWith({String? name, String? color, int? sortOrder, List<LedgerTag>? tags}) =>
      LedgerTagGroup(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'color': color,
    'sort_order': sortOrder,
  };

  factory LedgerTagGroup.fromJson(Map<String, dynamic> j) => LedgerTagGroup(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    color: _s(j, 'color'),
    sortOrder: _i(j, 'sort_order'),
    tags: _mapList(j['tags']).map(LedgerTag.fromJson).toList(growable: false),
  );
}

/// 流水附件。
///
/// 这一轮只有占位：文件名与大小能编排出完整的 UI（选择、缩略、删除、计数），
/// 真正的落盘与 FFI 下一轮接。字段按未来契约写，届时只换数据来源。
class LedgerAttachment {
  const LedgerAttachment({
    this.id = 0,
    this.fileName = '',
    this.mimeType = '',
    this.sizeBytes = 0,
    this.path = '',
  });

  final int id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String path;

  bool get isImage => mimeType.startsWith('image/');

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'file_name': fileName,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'path': path,
  };

  factory LedgerAttachment.fromJson(Map<String, dynamic> j) => LedgerAttachment(
    id: _i(j, 'id'),
    fileName: _s(j, 'file_name'),
    mimeType: _s(j, 'mime_type'),
    sizeBytes: _i(j, 'size_bytes'),
    path: _s(j, 'path'),
  );
}

/// 记账模板：把"经常要重复填的那一笔"存下来，点一下就记
///
/// 注意与 [LedgerTemplate] 不是一回事——那个是邮件账单的解析模板。
/// 这里存的是流水草稿，字段是 [LedgerTx] 的子集，日期不入模板（每次记当天）。
class LedgerTxTemplate {
  const LedgerTxTemplate({
    this.id = 0,
    this.title = '',
    this.txType = kLedgerTxTypeExpense,
    this.direction = kLedgerDirectionExpense,
    this.amount = 0,
    this.destAmount = 0,
    this.accountId = 0,
    this.destAccountId = 0,
    this.categoryId = 0,
    this.tagIds = const <int>[],
    this.merchant = '',
    this.note = '',
    this.useCount = 0,
    this.createdAt = '',
    this.accountName = '',
    this.destAccountName = '',
    this.categoryName = '',
    this.categoryIcon = '',
    this.tagNames = const <String>[],
  });

  final int id;
  final String title;
  final String txType;
  final String direction;
  final double amount;
  final double destAmount;
  final int accountId;
  final int destAccountId;
  final int categoryId;
  final List<int> tagIds;
  final String merchant;
  final String note;
  final int useCount;
  final String createdAt;
  final String accountName;
  final String destAccountName;
  final String categoryName;
  final String categoryIcon;
  final List<String> tagNames;

  bool get isIncome => direction == kLedgerDirectionIncome;
  bool get isTransfer => txType == kLedgerTxTypeTransfer;

  /// 展开成一张待确认的流水草稿；日期与 id 交给调用方填
  LedgerTx toDraft({String? billDate, String? occurredAt}) => LedgerTx(
    billDate: billDate ?? '',
    occurredAt: occurredAt ?? '',
    txType: txType,
    direction: direction,
    amount: amount,
    destAmount: destAmount,
    accountId: accountId,
    destAccountId: destAccountId,
    categoryId: categoryId,
    tagIds: tagIds,
    merchant: merchant,
    note: note,
    accountName: accountName,
    destAccountName: destAccountName,
    categoryName: categoryName,
    categoryIcon: categoryIcon,
    tagNames: tagNames,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'tx_type': txType,
    'direction': direction,
    'amount': amount,
    'dest_amount': destAmount,
    'account_id': accountId,
    'dest_account_id': destAccountId,
    'category_id': categoryId,
    'tag_ids': tagIds,
    'merchant': merchant,
    'note': note,
  };

  factory LedgerTxTemplate.fromJson(Map<String, dynamic> j) => LedgerTxTemplate(
    id: _i(j, 'id'),
    title: _s(j, 'title'),
    txType: _s(j, 'tx_type').isEmpty ? kLedgerTxTypeExpense : _s(j, 'tx_type'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    amount: _d(j, 'amount'),
    destAmount: _d(j, 'dest_amount'),
    accountId: _i(j, 'account_id'),
    destAccountId: _i(j, 'dest_account_id'),
    categoryId: _i(j, 'category_id'),
    tagIds: _iList(j, 'tag_ids'),
    merchant: _s(j, 'merchant'),
    note: _s(j, 'note'),
    useCount: _i(j, 'use_count'),
    createdAt: _s(j, 'created_at'),
    accountName: _s(j, 'account_name'),
    destAccountName: _s(j, 'dest_account_name'),
    categoryName: _s(j, 'category_name'),
    categoryIcon: _s(j, 'category_icon'),
    tagNames: _sList(j, 'tag_names'),
  );
}

/// 定时记账：模板 + 一套重复规则
class LedgerSchedule {
  const LedgerSchedule({
    this.id = 0,
    this.name = '',
    this.templateId = 0,
    this.repeat = kLedgerRepeatMonthly,
    this.dayOfMonth = 1,
    this.weekday = 1,
    this.timeOfDay = '09:00',
    this.startDate = '',
    this.endDate = '',
    this.enabled = true,
    this.lastRunAt = '',
    this.nextRunAt = '',
    this.templateTitle = '',
  });

  final int id;
  final String name;
  final int templateId;
  final String repeat;

  /// monthly/biweekly 用；monthly 超过当月天数时落在月末
  final int dayOfMonth;

  /// weekly 用，1=周一
  final int weekday;
  final String timeOfDay;
  final String startDate;

  /// 空串=无限期
  final String endDate;
  final bool enabled;
  final String lastRunAt;
  final String nextRunAt;
  final String templateTitle;

  bool get hasEnd => endDate.isNotEmpty;

  String get repeatLabel => kLedgerRepeatLabels[repeat] ?? repeat;

  /// "每月 5 日 09:00" 这种一行话
  String get whenLabel {
    final hm = timeOfDay.length >= 5 ? timeOfDay.substring(0, 5) : timeOfDay;
    return switch (repeat) {
      kLedgerRepeatDaily => '每天 $hm',
      kLedgerRepeatWeekly => '每${kLedgerWeekdayLabels[weekday % 7]} $hm',
      kLedgerRepeatBiweekly => '每两周 周${kLedgerWeekdayLabels[weekday % 7]} $hm',
      kLedgerRepeatMonthly => '每月 $dayOfMonth 日 $hm',
      kLedgerRepeatQuarterly => '每季 $dayOfMonth 日 $hm',
      kLedgerRepeatYearly => '每年 $dayOfMonth 日 $hm',
      _ => repeat,
    };
  }

  LedgerSchedule copyWith({
    String? name,
    int? templateId,
    String? repeat,
    int? dayOfMonth,
    int? weekday,
    String? timeOfDay,
    String? startDate,
    String? endDate,
    bool? enabled,
  }) => LedgerSchedule(
    id: id,
    name: name ?? this.name,
    templateId: templateId ?? this.templateId,
    repeat: repeat ?? this.repeat,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    weekday: weekday ?? this.weekday,
    timeOfDay: timeOfDay ?? this.timeOfDay,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    enabled: enabled ?? this.enabled,
    lastRunAt: lastRunAt,
    nextRunAt: nextRunAt,
    templateTitle: templateTitle,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'template_id': templateId,
    'repeat': repeat,
    'day_of_month': dayOfMonth,
    'weekday': weekday,
    'time_of_day': timeOfDay,
    'start_date': startDate,
    'end_date': endDate,
    'enabled': enabled,
  };

  factory LedgerSchedule.fromJson(Map<String, dynamic> j) => LedgerSchedule(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    templateId: _i(j, 'template_id'),
    repeat: _s(j, 'repeat').isEmpty ? kLedgerRepeatMonthly : _s(j, 'repeat'),
    dayOfMonth: j.containsKey('day_of_month') ? _i(j, 'day_of_month') : 1,
    weekday: j.containsKey('weekday') ? _i(j, 'weekday') : 1,
    timeOfDay: _s(j, 'time_of_day').isEmpty ? '09:00' : _s(j, 'time_of_day'),
    startDate: _s(j, 'start_date'),
    endDate: _s(j, 'end_date'),
    enabled: j.containsKey('enabled') ? _b(j, 'enabled') : true,
    lastRunAt: _s(j, 'last_run_at'),
    nextRunAt: _s(j, 'next_run_at'),
    templateTitle: _s(j, 'template_title'),
  );
}

/// 邮件自动记账规则
class LedgerRule {
  const LedgerRule({
    this.id = 0,
    this.name = '',
    this.enabled = true,
    this.protocol = 'imap',
    this.host = '',
    this.port = 0,
    this.useSsl = true,
    this.username = '',
    this.mailbox = 'INBOX',
    this.senderMatch = '',
    this.subjectMatch = '',
    this.matchIsRegex = false,
    this.templateId = 'auto',
    this.templateConfig = '{}',
    this.intervalMinutes = 0,
    this.dailyTime = '',
    this.defaultAccountId = 0,
    this.autoApply = false,
    this.acceptInvalidCerts = false,
    this.lastRunAt = '',
    this.lastResult = '',
  });

  final int id;
  final String name;
  final bool enabled;
  final String protocol;
  final String host;
  final int port;
  final bool useSsl;
  final String username;
  final String mailbox;
  final String senderMatch;
  final String subjectMatch;
  final bool matchIsRegex;
  final String templateId;
  final String templateConfig;
  final int intervalMinutes;
  final String dailyTime;
  final int defaultAccountId;
  final bool autoApply;
  final bool acceptInvalidCerts;
  final String lastRunAt;
  final String lastResult;

  /// 当前版本真正能跑的协议；EAS/CardDAV 只占位，选中即给出明确提示
  bool get protocolSupported =>
      protocol == 'imap' || protocol == 'pop3' || protocol == 'smtp';

  LedgerRule copyWith({
    int? id,
    String? name,
    bool? enabled,
    String? protocol,
    String? host,
    int? port,
    bool? useSsl,
    String? username,
    String? mailbox,
    String? senderMatch,
    String? subjectMatch,
    bool? matchIsRegex,
    String? templateId,
    String? templateConfig,
    int? intervalMinutes,
    String? dailyTime,
    int? defaultAccountId,
    bool? autoApply,
    bool? acceptInvalidCerts,
  }) => LedgerRule(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    protocol: protocol ?? this.protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    useSsl: useSsl ?? this.useSsl,
    username: username ?? this.username,
    mailbox: mailbox ?? this.mailbox,
    senderMatch: senderMatch ?? this.senderMatch,
    subjectMatch: subjectMatch ?? this.subjectMatch,
    matchIsRegex: matchIsRegex ?? this.matchIsRegex,
    templateId: templateId ?? this.templateId,
    templateConfig: templateConfig ?? this.templateConfig,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
    dailyTime: dailyTime ?? this.dailyTime,
    defaultAccountId: defaultAccountId ?? this.defaultAccountId,
    autoApply: autoApply ?? this.autoApply,
    acceptInvalidCerts: acceptInvalidCerts ?? this.acceptInvalidCerts,
    lastRunAt: lastRunAt,
    lastResult: lastResult,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'enabled': enabled,
    'protocol': protocol,
    'host': host,
    'port': port,
    'use_ssl': useSsl,
    'username': username,
    'mailbox': mailbox,
    'sender_match': senderMatch,
    'subject_match': subjectMatch,
    'match_is_regex': matchIsRegex,
    'template_id': templateId,
    'template_config': templateConfig,
    'interval_minutes': intervalMinutes,
    'daily_time': dailyTime,
    'default_account_id': defaultAccountId,
    'auto_apply': autoApply,
    'accept_invalid_certs': acceptInvalidCerts,
  };

  factory LedgerRule.fromJson(Map<String, dynamic> j) => LedgerRule(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    enabled: j.containsKey('enabled') ? _b(j, 'enabled') : true,
    protocol: _s(j, 'protocol').isEmpty ? 'imap' : _s(j, 'protocol'),
    host: _s(j, 'host'),
    port: _i(j, 'port'),
    useSsl: j.containsKey('use_ssl') ? _b(j, 'use_ssl') : true,
    username: _s(j, 'username'),
    mailbox: _s(j, 'mailbox').isEmpty ? 'INBOX' : _s(j, 'mailbox'),
    senderMatch: _s(j, 'sender_match'),
    subjectMatch: _s(j, 'subject_match'),
    matchIsRegex: _b(j, 'match_is_regex'),
    templateId: _s(j, 'template_id').isEmpty ? 'auto' : _s(j, 'template_id'),
    templateConfig: _s(j, 'template_config').isEmpty ? '{}' : _s(j, 'template_config'),
    intervalMinutes: _i(j, 'interval_minutes'),
    dailyTime: _s(j, 'daily_time'),
    defaultAccountId: _i(j, 'default_account_id'),
    autoApply: _b(j, 'auto_apply'),
    acceptInvalidCerts: _b(j, 'accept_invalid_certs'),
    lastRunAt: _s(j, 'last_run_at'),
    lastResult: _s(j, 'last_result'),
  );
}

/// 待确认（或已入账）的一封账单邮件
class LedgerPendingEmail {
  const LedgerPendingEmail({
    this.id = 0,
    this.ruleId = 0,
    this.ruleName = '',
    this.messageUid = '',
    this.fromAddr = '',
    this.subject = '',
    this.receivedAt = '',
    this.billDate = '',
    this.txCount = 0,
    this.applied = false,
    this.availableCredit,
    this.pointsBalance,
    this.warnings = const <String>[],
    this.htmlLen = 0,
  });

  final int id;
  final int ruleId;
  final String ruleName;
  final String messageUid;
  final String fromAddr;
  final String subject;
  final String receivedAt;
  final String billDate;
  final int txCount;
  final bool applied;
  final double? availableCredit;
  final int? pointsBalance;
  final List<String> warnings;
  final int htmlLen;

  factory LedgerPendingEmail.fromJson(Map<String, dynamic> j) => LedgerPendingEmail(
    id: _i(j, 'id'),
    ruleId: _i(j, 'rule_id'),
    ruleName: _s(j, 'rule_name'),
    messageUid: _s(j, 'message_uid'),
    fromAddr: _s(j, 'from_addr'),
    subject: _s(j, 'subject'),
    receivedAt: _s(j, 'received_at'),
    billDate: _s(j, 'bill_date'),
    txCount: _i(j, 'tx_count'),
    applied: _b(j, 'applied'),
    availableCredit: _dOpt(j, 'available_credit'),
    pointsBalance: _iOpt(j, 'points_balance'),
    warnings: switch (j['warnings']) {
      List list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    },
    htmlLen: _i(j, 'html_len'),
  );
}

/// 解析出的一笔账单行（模板引擎产物）
class LedgerParsedTx {
  const LedgerParsedTx({
    this.time = '',
    this.datetime = '',
    this.currency = 'CNY',
    this.amount = 0,
    this.rawAmount = '',
    this.description = '',
    this.cardTail = '',
    this.entryType = '',
    this.merchant = '',
    this.direction = kLedgerDirectionExpense,
    this.txId = 0,
    this.status = kLedgerStatusPending,
  });

  final String time;
  final String datetime;
  final String currency;
  final double amount;
  final String rawAmount;
  final String description;
  final String cardTail;
  final String entryType;
  final String merchant;
  final String direction;

  /// 已落库时对应的流水 id（待确认队列展开用）；0 表示还没入库
  final int txId;
  final String status;

  bool get isIncome => direction == kLedgerDirectionIncome;

  factory LedgerParsedTx.fromJson(Map<String, dynamic> j) => LedgerParsedTx(
    time: _s(j, 'time'),
    datetime: _s(j, 'datetime'),
    currency: _s(j, 'currency').isEmpty ? 'CNY' : _s(j, 'currency'),
    amount: _d(j, 'amount'),
    rawAmount: _s(j, 'raw_amount'),
    description: _s(j, 'description'),
    cardTail: _s(j, 'card_tail'),
    entryType: _s(j, 'entry_type'),
    merchant: _s(j, 'merchant'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    txId: _i(j, 'tx_id'),
    status: _s(j, 'status'),
  );
}

/// 模板引擎对一封邮件的解析产物（预览与真实收信共用）
class LedgerParseResult {
  const LedgerParseResult({
    this.templateId = '',
    this.billDate = '',
    this.transactions = const <LedgerParsedTx>[],
    this.availableCredit,
    this.pointsBalance,
    this.warnings = const <String>[],
  });

  final String templateId;
  final String billDate;
  final List<LedgerParsedTx> transactions;
  final double? availableCredit;
  final int? pointsBalance;
  final List<String> warnings;

  bool get isEmpty => transactions.isEmpty;

  factory LedgerParseResult.fromJson(Map<String, dynamic> j) => LedgerParseResult(
    templateId: _s(j, 'template_id'),
    billDate: _s(j, 'bill_date'),
    transactions: _mapList(j['transactions']).map(LedgerParsedTx.fromJson).toList(),
    availableCredit: _dOpt(j, 'available_credit'),
    pointsBalance: _iOpt(j, 'points_balance'),
    warnings: switch (j['warnings']) {
      List list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    },
  );
}

/// 预览收取到的一封邮件
class LedgerFetchedEmail {
  const LedgerFetchedEmail({
    this.uid = '',
    this.from = '',
    this.subject = '',
    this.date = '',
    this.sizeBytes = 0,
    this.htmlLen = 0,
    this.matched = false,
    this.templateId = '',
    this.billDate = '',
    this.txCount = 0,
    this.warnings = const <String>[],
    this.transactions = const <LedgerParsedTx>[],
    this.availableCredit,
    this.pointsBalance,
    this.bodyTextHead = '',
  });

  final String uid;
  final String from;
  final String subject;
  final String date;
  final int sizeBytes;
  final int htmlLen;
  final bool matched;
  final String templateId;
  final String billDate;
  final int txCount;
  final List<String> warnings;
  final List<LedgerParsedTx> transactions;
  final double? availableCredit;
  final int? pointsBalance;
  final String bodyTextHead;

  factory LedgerFetchedEmail.fromJson(Map<String, dynamic> j) => LedgerFetchedEmail(
    uid: _s(j, 'uid'),
    from: _s(j, 'from'),
    subject: _s(j, 'subject'),
    date: _s(j, 'date'),
    sizeBytes: _i(j, 'size_bytes'),
    htmlLen: _i(j, 'html_len'),
    matched: _b(j, 'matched'),
    templateId: _s(j, 'template_id'),
    billDate: _s(j, 'bill_date'),
    txCount: _i(j, 'tx_count'),
    warnings: switch (j['warnings']) {
      List list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    },
    transactions: _mapList(j['transactions']).map(LedgerParsedTx.fromJson).toList(),
    availableCredit: _dOpt(j, 'available_credit'),
    pointsBalance: _iOpt(j, 'points_balance'),
    bodyTextHead: _s(j, 'body_text_head'),
  );
}

/// 邮件规则模板说明
class LedgerTemplate {
  const LedgerTemplate({this.id = '', this.name = '', this.description = ''});

  final String id;
  final String name;
  final String description;

  factory LedgerTemplate.fromJson(Map<String, dynamic> j) => LedgerTemplate(
    id: _s(j, 'id'),
    name: _s(j, 'name'),
    description: _s(j, 'description'),
  );
}

/// 一次收信的日志
class LedgerFetchLog {
  const LedgerFetchLog({
    this.id = 0,
    this.ruleId = 0,
    this.startedAt = '',
    this.finishedAt = '',
    this.ok = false,
    this.newEmails = 0,
    this.newTx = 0,
    this.skippedTx = 0,
    this.detail = '',
  });

  final int id;
  final int ruleId;
  final String startedAt;
  final String finishedAt;
  final bool ok;
  final int newEmails;
  final int newTx;
  final int skippedTx;
  final String detail;

  factory LedgerFetchLog.fromJson(Map<String, dynamic> j) => LedgerFetchLog(
    id: _i(j, 'id'),
    ruleId: _i(j, 'rule_id'),
    startedAt: _s(j, 'started_at'),
    finishedAt: _s(j, 'finished_at'),
    ok: _b(j, 'ok'),
    newEmails: _i(j, 'new_emails'),
    newTx: _i(j, 'new_tx'),
    skippedTx: _i(j, 'skipped_tx'),
    detail: _s(j, 'detail'),
  );
}

/// 调度器状态
class LedgerSchedulerStatus {
  const LedgerSchedulerStatus({
    this.running = false,
    this.enabled = false,
    this.checkIntervalSecs = 60,
    this.lastCheckAt = '',
    this.nextCheckAt = '',
    this.activeRules = 0,
    this.lastSummary = '',
  });

  final bool running;
  final bool enabled;
  final int checkIntervalSecs;
  final String lastCheckAt;
  final String nextCheckAt;
  final int activeRules;
  final String lastSummary;

  factory LedgerSchedulerStatus.fromJson(Map<String, dynamic> j) => LedgerSchedulerStatus(
    running: _b(j, 'running'),
    enabled: _b(j, 'enabled'),
    checkIntervalSecs: _i(j, 'check_interval_secs'),
    lastCheckAt: _s(j, 'last_check_at'),
    nextCheckAt: _s(j, 'next_check_at'),
    activeRules: _i(j, 'active_rules'),
    lastSummary: _s(j, 'last_summary'),
  );
}

/// 查询条件：所有统计接口共用这一个形态
class LedgerFilter {
  const LedgerFilter({
    this.startDate = '',
    this.endDate = '',
    this.direction = '',
    this.txType = '',
    this.accountId = 0,
    this.categoryId = 0,
    this.tagIds = const <int>[],
    this.minAmount = 0,
    this.maxAmount = 0,
    this.source = '',
    this.status = '',
    this.keyword = '',
    this.limit = 0,
    this.offset = 0,
  });

  final String startDate;
  final String endDate;
  final String direction;

  /// 记账类型过滤（含转账/余额调整）；与 [direction] 二选一时优先看它
  final String txType;
  final int accountId;
  final int categoryId;

  /// 命中其中任意一个标签即算匹配（OR）——标签是"这笔属于哪些项目"，
  /// 要求同时命中会筛到只剩个位数
  final List<int> tagIds;
  final double minAmount;
  final double maxAmount;
  final String source;
  final String status;
  final String keyword;
  final int limit;
  final int offset;

  /// 一条筛选都没挂：明细页用它决定要不要显示"清除筛选"
  bool get isEmpty =>
      direction.isEmpty &&
      txType.isEmpty &&
      accountId == 0 &&
      categoryId == 0 &&
      tagIds.isEmpty &&
      minAmount <= 0 &&
      maxAmount <= 0 &&
      source.isEmpty &&
      keyword.isEmpty;

  LedgerFilter copyWith({
    String? startDate,
    String? endDate,
    String? direction,
    String? txType,
    int? accountId,
    int? categoryId,
    List<int>? tagIds,
    double? minAmount,
    double? maxAmount,
    String? source,
    String? status,
    String? keyword,
    int? limit,
    int? offset,
  }) => LedgerFilter(
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    direction: direction ?? this.direction,
    txType: txType ?? this.txType,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    tagIds: tagIds ?? this.tagIds,
    minAmount: minAmount ?? this.minAmount,
    maxAmount: maxAmount ?? this.maxAmount,
    source: source ?? this.source,
    status: status ?? this.status,
    keyword: keyword ?? this.keyword,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (startDate.isNotEmpty) 'start_date': startDate,
    if (endDate.isNotEmpty) 'end_date': endDate,
    if (direction.isNotEmpty) 'direction': direction,
    if (txType.isNotEmpty) 'tx_type': txType,
    if (accountId > 0) 'account_id': accountId,
    if (categoryId > 0) 'category_id': categoryId,
    if (tagIds.isNotEmpty) 'tag_ids': tagIds,
    if (minAmount > 0) 'min_amount': minAmount,
    if (maxAmount > 0) 'max_amount': maxAmount,
    if (source.isNotEmpty) 'source': source,
    if (status.isNotEmpty) 'status': status,
    if (keyword.isNotEmpty) 'keyword': keyword,
    if (limit > 0) 'limit': limit,
    if (offset > 0) 'offset': offset,
  };

  String get json => jsonEncode(toJson());
}

/// 时间区间：起止都是 'YYYY-MM-DD'，闭区间
///
/// 明细页和统计页都要"选一段时间"，各自算一遍日期就把大小月、跨年、
/// 季度首月这些坑复制两份。这里算一次，两页共用。
class LedgerPeriod {
  const LedgerPeriod({
    required this.startDate,
    required this.endDate,
    required this.title,
    this.preset = LedgerRangePreset.custom,
  });

  final String startDate;
  final String endDate;

  /// 胶囊上显示的那句话（"近 30 天""2026年9月"）
  final String title;
  final LedgerRangePreset preset;

  bool get isAll => startDate.isEmpty && endDate.isEmpty;

  LedgerFilter toFilter({String status = kLedgerStatusPosted}) => LedgerFilter(
    startDate: startDate,
    endDate: endDate,
    status: status,
  );

  /// 标题里的日期区间；'2026-09-01' → '9.1'，省掉年份噪音
  String get shortLabel {
    if (isAll) return '全部';
    if (startDate == endDate) return _shortDay(startDate);
    return '${_shortDay(startDate)} - ${_shortDay(endDate)}';
  }

  int get dayCount {
    final s = DateTime.tryParse(startDate);
    final e = DateTime.tryParse(endDate);
    if (s == null || e == null) return 0;
    return e.difference(s).inDays + 1;
  }
}

String _shortDay(String date) {
  if (date.length < 10) return date;
  final m = int.tryParse(date.substring(5, 7)) ?? 0;
  final d = int.tryParse(date.substring(8, 10)) ?? 0;
  return '$m.$d';
}

/// 时间预设。`custom` 由日期选择器填，其余都从"今天"倒推。
enum LedgerRangePreset {
  today,
  yesterday,
  last7,
  last30,
  thisWeek,
  thisMonth,
  lastMonth,
  thisQuarter,
  thisYear,
  lastBillCycle,
  all,
  custom,
}

const Map<LedgerRangePreset, String> kLedgerRangeLabels = <LedgerRangePreset, String>{
  LedgerRangePreset.today: '今天',
  LedgerRangePreset.yesterday: '昨天',
  LedgerRangePreset.last7: '近 7 天',
  LedgerRangePreset.last30: '近 30 天',
  LedgerRangePreset.thisWeek: '本周',
  LedgerRangePreset.thisMonth: '本月',
  LedgerRangePreset.lastMonth: '上月',
  LedgerRangePreset.thisQuarter: '本季',
  LedgerRangePreset.thisYear: '今年',
  LedgerRangePreset.lastBillCycle: '上一账单周期',
  LedgerRangePreset.all: '全部',
  LedgerRangePreset.custom: '自定义',
};

/// 聚合轴：同一区间可以按日/周/月/季/年切，趋势图的分辨率就是这一件事
enum LedgerAxis { day, week, month, quarter, year }

const Map<LedgerAxis, String> kLedgerAxisLabels = <LedgerAxis, String>{
  LedgerAxis.day: '按日',
  LedgerAxis.week: '按周',
  LedgerAxis.month: '按月',
  LedgerAxis.quarter: '按季',
  LedgerAxis.year: '按年',
};

/// 一个聚合格子：`key` 与后端聚合键逐字一致，`label` 给横轴用
class LedgerBucket {
  const LedgerBucket(this.key, this.label);

  final String key;
  final String label;
}

/// 聚合后的一格收支
class LedgerAxisRow {
  const LedgerAxisRow({
    this.bucket = '',
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.count = 0,
  });

  final String bucket;
  final double income;
  final double expense;
  final double net;
  final int count;

  factory LedgerAxisRow.fromJson(Map<String, dynamic> j) => LedgerAxisRow(
    bucket: _s(j, 'bucket'),
    income: _d(j, 'income'),
    expense: _d(j, 'expense'),
    net: _d(j, 'net'),
    count: _i(j, 'count'),
  );
}

/// 资产趋势的一格：某天时点上的资产/负债/净资产
class LedgerAssetPoint {
  const LedgerAssetPoint({
    this.date = '',
    this.asset = 0,
    this.liability = 0,
    this.netWorth = 0,
  });

  final String date;

  /// 正数账户加起来
  final double asset;

  /// 负债按正数存（"欠 1.2 万"就是 12000），净资产 = asset - liability
  final double liability;
  final double netWorth;

  factory LedgerAssetPoint.fromJson(Map<String, dynamic> j) => LedgerAssetPoint(
    date: _s(j, 'date'),
    asset: _d(j, 'asset'),
    liability: _d(j, 'liability'),
    netWorth: _d(j, 'net_worth'),
  );
}

/// 'YYYY-MM-DD'
String ledgerDateOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// 按预设算出区间。[billDay] 是账单日（1~28），只有"上一账单周期"用到。
LedgerPeriod ledgerPeriodOf(LedgerRangePreset preset, {DateTime? now, int billDay = 1}) {
  final t = now ?? DateTime.now();
  final today = ledgerDateOf(t);
  String back(int days) => ledgerDateOf(t.subtract(Duration(days: days)));
  String label(LedgerRangePreset p) => kLedgerRangeLabels[p] ?? '';

  return switch (preset) {
    LedgerRangePreset.today => LedgerPeriod(
      startDate: today,
      endDate: today,
      title: label(LedgerRangePreset.today),
      preset: preset,
    ),
    LedgerRangePreset.yesterday => LedgerPeriod(
      startDate: back(1),
      endDate: back(1),
      title: label(LedgerRangePreset.yesterday),
      preset: preset,
    ),
    LedgerRangePreset.last7 => LedgerPeriod(
      startDate: back(6),
      endDate: today,
      title: label(LedgerRangePreset.last7),
      preset: preset,
    ),
    LedgerRangePreset.last30 => LedgerPeriod(
      startDate: back(29),
      endDate: today,
      title: label(LedgerRangePreset.last30),
      preset: preset,
    ),
    LedgerRangePreset.thisWeek => () {
      // 周一为一周之始：周日起算会让"本周"在周日这天只有 1 天
      final start = t.subtract(Duration(days: t.weekday - 1));
      return LedgerPeriod(
        startDate: ledgerDateOf(start),
        endDate: ledgerDateOf(start.add(const Duration(days: 6))),
        title: label(LedgerRangePreset.thisWeek),
        preset: preset,
      );
    }(),
    LedgerRangePreset.thisMonth => LedgerPeriod(
      startDate: ledgerMonthStart(ledgerMonthOf(t)),
      endDate: ledgerMonthEnd(ledgerMonthOf(t)),
      title: label(LedgerRangePreset.thisMonth),
      preset: preset,
    ),
    LedgerRangePreset.lastMonth => () {
      final prev = ledgerMonthShift(ledgerMonthOf(t), -1);
      return LedgerPeriod(
        startDate: ledgerMonthStart(prev),
        endDate: ledgerMonthEnd(prev),
        title: label(LedgerRangePreset.lastMonth),
        preset: preset,
      );
    }(),
    LedgerRangePreset.thisQuarter => () {
      final q = (t.month - 1) ~/ 3;
      final start = DateTime(t.year, q * 3 + 1);
      final end = DateTime(t.year, q * 3 + 4).subtract(const Duration(days: 1));
      return LedgerPeriod(
        startDate: ledgerDateOf(start),
        endDate: ledgerDateOf(end),
        title: label(LedgerRangePreset.thisQuarter),
        preset: preset,
      );
    }(),
    LedgerRangePreset.thisYear => LedgerPeriod(
      startDate: '${t.year}-01-01',
      endDate: '${t.year}-12-31',
      title: label(LedgerRangePreset.thisYear),
      preset: preset,
    ),
    LedgerRangePreset.lastBillCycle => () {
      // 账单日当天出的是上一周期的账，所以"上一账单周期"结束于上一个账单日
      final d = billDay.clamp(1, 28);
      var end = DateTime(t.year, t.month, d);
      if (!end.isBefore(t)) end = DateTime(end.year, end.month - 1, d);
      final start = DateTime(end.year, end.month - 1, d).add(const Duration(days: 1));
      return LedgerPeriod(
        startDate: ledgerDateOf(start),
        endDate: ledgerDateOf(end),
        title: label(LedgerRangePreset.lastBillCycle),
        preset: preset,
      );
    }(),
    LedgerRangePreset.all => LedgerPeriod(
      startDate: '',
      endDate: '',
      title: label(LedgerRangePreset.all),
      preset: preset,
    ),
    LedgerRangePreset.custom => LedgerPeriod(
      startDate: today,
      endDate: today,
      title: label(LedgerRangePreset.custom),
      preset: preset,
    ),
  };
}

/// 区间内的每一天，'YYYY-MM-DD'
List<String> ledgerDateSpan(String from, String to) {
  final start = DateTime.tryParse(from);
  final end = DateTime.tryParse(to);
  if (start == null || end == null || end.isBefore(start)) return const <String>[];
  final out = <String>[];
  var cursor = start;
  // 3660 格 ≈ 10 年，再长就是脏数据，别让它把 UI 拖死
  while (out.length < 3660) {
    out.add(ledgerDateOf(cursor));
    if (!cursor.isBefore(end)) break;
    cursor = cursor.add(const Duration(days: 1));
  }
  return out;
}

/// 按月刻度的短标签：'2026-03' → '3月'
///
/// 聚合轴的月份格和净资产曲线的月份格都从这里取字，两处一旦分叉，同一个"3月"
/// 在两张图上会长得不一样。
String ledgerMonthTick(String monthKey) {
  final m = int.tryParse(monthKey.length >= 7 ? monthKey.substring(5) : '');
  return m == null ? monthKey : '$m月';
}

/// 聚合轴的全部格子（含空白格）
///
/// 后端只返回有账的那些格子，空掉的月份不会出现在结果里。横轴要连续，
/// 所以格子在这里按区间生成，再把行数据往里填——否则"这个月没花钱"
/// 和"这个月没数据"在图上长得一模一样。
List<LedgerBucket> ledgerBuckets(LedgerPeriod period, LedgerAxis axis) {
  if (period.isAll) return const <LedgerBucket>[];
  return switch (axis) {
    LedgerAxis.day => [
      for (final d in ledgerDateSpan(period.startDate, period.endDate))
        LedgerBucket(d, d.substring(8)),
    ],
    LedgerAxis.week => _weekBuckets(period),
    LedgerAxis.month => [
      for (final m in ledgerMonthSpan(period.startDate.substring(0, 7), period.endDate.substring(0, 7)))
        LedgerBucket(m, ledgerMonthTick(m)),
    ],
    LedgerAxis.quarter => _quarterBuckets(period),
    LedgerAxis.year => [
      for (var y = int.parse(period.startDate.substring(0, 4)); y <= int.parse(period.endDate.substring(0, 4)); y++)
        if (y > 0) LedgerBucket('$y', '$y'),
    ],
  };
}

List<LedgerBucket> _weekBuckets(LedgerPeriod period) {
  final start = DateTime.tryParse(period.startDate);
  final end = DateTime.tryParse(period.endDate);
  if (start == null || end == null) return const <LedgerBucket>[];
  var cursor = start.subtract(Duration(days: start.weekday - 1));
  final out = <LedgerBucket>[];
  while (out.length < 560) {
    final key = ledgerDateOf(cursor);
    out.add(LedgerBucket(key, '${cursor.month}.${cursor.day}'));
    if (!cursor.isBefore(end)) break;
    cursor = cursor.add(const Duration(days: 7));
  }
  return out;
}

List<LedgerBucket> _quarterBuckets(LedgerPeriod period) {
  final out = <LedgerBucket>[];
  final from = int.parse(period.startDate.substring(0, 4));
  final to = int.parse(period.endDate.substring(0, 4));
  for (var y = from; y <= to && out.length < 80; y++) {
    for (var q = 1; q <= 4; q++) {
      final first = DateTime(y, (q - 1) * 3 + 1);
      final last = DateTime(y, q * 3 + 1).subtract(const Duration(days: 1));
      // 只保留与区间真有交叠的季度，跨年时首尾各裁一截
      if (ledgerDateOf(last).compareTo(period.startDate) < 0) continue;
      if (ledgerDateOf(first).compareTo(period.endDate) > 0) continue;
      out.add(LedgerBucket('$y-Q$q', '$y年$q季'));
    }
  }
  return out;
}

/// 日期落在哪个聚合格子上——与 [ledgerBuckets] 的 key 规则必须逐字一致
String ledgerBucketKeyOf(String date, LedgerAxis axis) {
  if (date.length < 10) return date;
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  return switch (axis) {
    LedgerAxis.day => date,
    // 与 _weekBuckets 同样以周一为原点回退
    LedgerAxis.week => ledgerDateOf(d.subtract(Duration(days: d.weekday - 1))),
    LedgerAxis.month => date.substring(0, 7),
    LedgerAxis.quarter => '${d.year}-Q${(d.month - 1) ~/ 3 + 1}',
    LedgerAxis.year => '${d.year}',
  };
}

/// 把稀疏的行数据铺满全部格子
List<LedgerAxisRow> ledgerFillBuckets(List<LedgerBucket> buckets, List<LedgerAxisRow> rows) {
  final byKey = <String, LedgerAxisRow>{
    for (final row in rows) row.bucket: row,
  };
  return [
    for (final b in buckets)
      byKey[b.key] ?? LedgerAxisRow(bucket: b.key),
  ];
}

/// 按天分组的一行
class LedgerDayRow {
  const LedgerDayRow({
    this.billDate = '',
    this.income = 0,
    this.expense = 0,
    this.count = 0,
  });

  final String billDate;
  final double income;
  final double expense;
  final int count;

  double get net => income - expense;

  factory LedgerDayRow.fromJson(Map<String, dynamic> j) => LedgerDayRow(
    billDate: _s(j, 'bill_date'),
    income: _d(j, 'income'),
    expense: _d(j, 'expense'),
    count: _i(j, 'count'),
  );
}

/// 按类别分组的一行
class LedgerCategoryRow {
  const LedgerCategoryRow({
    this.categoryId = 0,
    this.categoryName = '',
    this.categoryIcon = '',
    this.direction = kLedgerDirectionExpense,
    this.total = 0,
    this.count = 0,
  });

  final int categoryId;
  final String categoryName;
  final String categoryIcon;
  final String direction;
  final double total;
  final int count;

  factory LedgerCategoryRow.fromJson(Map<String, dynamic> j) => LedgerCategoryRow(
    categoryId: _i(j, 'category_id'),
    categoryName: _s(j, 'category_name'),
    categoryIcon: _s(j, 'category_icon'),
    direction: _s(j, 'direction'),
    total: _d(j, 'total'),
    count: _i(j, 'count'),
  );
}

/// 按商户分组的一行
class LedgerMerchantRow {
  const LedgerMerchantRow({
    this.merchant = '',
    this.total = 0,
    this.count = 0,
    this.lastDate = '',
  });

  final String merchant;
  final double total;
  final int count;
  final String lastDate;

  factory LedgerMerchantRow.fromJson(Map<String, dynamic> j) => LedgerMerchantRow(
    merchant: _s(j, 'merchant'),
    total: _d(j, 'total'),
    count: _i(j, 'count'),
    lastDate: _s(j, 'last_date'),
  );
}

/// 按月的收支
class LedgerMonthRow {
  const LedgerMonthRow({
    this.month = '',
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.count = 0,
  });

  final String month;
  final double income;
  final double expense;
  final double net;
  final int count;

  /// "2026-09" → "9月"，图表轴标签用
  String get shortLabel {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    final m = int.tryParse(parts[1]) ?? 0;
    return '$m月';
  }

  factory LedgerMonthRow.fromJson(Map<String, dynamic> j) => LedgerMonthRow(
    month: _s(j, 'month'),
    income: _d(j, 'income'),
    expense: _d(j, 'expense'),
    net: _d(j, 'net'),
    count: _i(j, 'count'),
  );
}

/// 区间汇总
class LedgerSummary {
  const LedgerSummary({
    this.income = 0,
    this.expense = 0,
    this.net = 0,
    this.count = 0,
    this.minDate = '',
    this.maxDate = '',
    this.month = '',
    this.monthIncome = 0,
    this.monthExpense = 0,
    this.monthNet = 0,
  });

  final double income;
  final double expense;
  final double net;
  final int count;
  final String minDate;
  final String maxDate;
  final String month;
  final double monthIncome;
  final double monthExpense;
  final double monthNet;

  bool get isEmpty => count == 0;

  factory LedgerSummary.fromJson(Map<String, dynamic> j) => LedgerSummary(
    income: _d(j, 'income'),
    expense: _d(j, 'expense'),
    net: _d(j, 'net'),
    count: _i(j, 'count'),
    minDate: _s(j, 'min_date'),
    maxDate: _s(j, 'max_date'),
    month: _s(j, 'month'),
    monthIncome: _d(j, 'month_income'),
    monthExpense: _d(j, 'month_expense'),
    monthNet: _d(j, 'month_net'),
  );
}

/// 连接自检结果
class LedgerProbeReport {
  const LedgerProbeReport({
    this.ok = false,
    this.protocol = '',
    this.detail = '',
    this.capabilities = const <String>[],
    this.folders = const <String>[],
  });

  final bool ok;
  final String protocol;
  final String detail;
  final List<String> capabilities;
  final List<String> folders;

  factory LedgerProbeReport.fromJson(Map<String, dynamic> j) => LedgerProbeReport(
    ok: _b(j, 'ok'),
    protocol: _s(j, 'protocol'),
    detail: _s(j, 'detail'),
    capabilities: switch (j['capabilities']) {
      List list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    },
    folders: switch (j['folders']) {
      List list => list.map((e) => e.toString()).toList(),
      _ => const <String>[],
    },
  );
}

/// 查重结果
class LedgerDupCheck {
  const LedgerDupCheck({this.duplicated = false, this.existingId = 0, this.existingDesc = ''});

  final bool duplicated;
  final int existingId;
  final String existingDesc;

  factory LedgerDupCheck.fromJson(Map<String, dynamic> j) => LedgerDupCheck(
    duplicated: _b(j, 'duplicated'),
    existingId: _i(j, 'existing_id'),
    existingDesc: _s(j, 'existing_desc'),
  );
}

/// 金额展示：千分位 + 两位小数，符号交给调用方按方向加
String formatLedgerAmount(double value, {bool withSign = false, bool income = false}) {
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final buf = StringBuffer();
  final intPart = parts[0];
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  buf.write('.${parts[1]}');
  if (!withSign) return buf.toString();
  return income ? '+$buf' : '-$buf';
}

/// 月份工具：流水页的"上一月/下一月"游标
String ledgerMonthOf(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

String ledgerMonthShift(String month, int delta) {
  final parts = month.split('-');
  final y = int.tryParse(parts.first) ?? DateTime.now().year;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? DateTime.now().month;
  final base = DateTime(y, m);
  final shifted = DateTime(base.year, base.month + delta);
  return ledgerMonthOf(shifted);
}

String ledgerMonthStart(String month) => '$month-01';

/// '2026-03' → '2026年3月'
String ledgerMonthLabel(String month) {
  final parts = month.split('-');
  if (parts.length != 2) return month;
  return '${parts[0]}年${int.tryParse(parts[1]) ?? 0}月';
}

/// 月末日期：用"下个月第 0 天"这种写法规避大小月与闰年分支
String ledgerMonthEnd(String month) {
  final parts = month.split('-');
  final y = int.tryParse(parts.first) ?? 1970;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return '$month-$lastDay';
}

/// 这个月的每一天（'YYYY-MM-DD'）
///
/// 日趋势图按整月排格子：只画有账的那几天，横轴就成了"有账的日子"而不是"这个月"，
/// 三天没花钱和二十天没花钱看起来一模一样。
List<String> ledgerMonthDays(String month) {
  if (month.length < 7) return const <String>[];
  final parts = month.split('-');
  final y = int.tryParse(parts.first) ?? 1970;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return <String>[
    for (var d = 1; d <= lastDay; d++) '$month-${d.toString().padLeft(2, '0')}',
  ];
}

/// 从 [from] 到 [to] 的连续月份（含两端），'YYYY-MM'
///
/// 统计接口只返回有账的月份，中间空掉的月份得自己补上格子：不然柱子互相错位，
/// "这个月没花钱"看着跟"这个月没数据"一模一样。
List<String> ledgerMonthSpan(String from, String to) {
  final start = DateTime.tryParse('$from-01');
  final end = DateTime.tryParse('$to-01');
  if (from.length < 7 || to.length < 7 || start == null || end == null) {
    return const <String>[];
  }
  if (end.isBefore(start)) return const <String>[];
  final out = <String>[];
  var cursor = start;
  // 600 格是脏数据的兜底，不让这里跟着离谱的月份一直转
  while (out.length < 600) {
    out.add(ledgerMonthOf(cursor));
    if (!cursor.isBefore(end)) break;
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return out;
}

/// 折进聚合格的一格收支（[date] 用 'YYYY-MM-DD' 或 'YYYY-MM'，与 [axis] 的粒度对齐）
typedef LedgerFlowSlot = ({String date, double income, double expense, int count});

/// 把日/月的收支折进聚合轴。
///
/// 后端只有按日与按月两种粒度，按周/季/年就在这儿按键归并，不用动 Rust。
/// 格子由 [ledgerBuckets] 生成，键的规则两边共用 [ledgerBucketKeyOf]。
List<LedgerAxisRow> ledgerFoldAxis(
  List<LedgerBucket> buckets,
  List<LedgerFlowSlot> rows,
  LedgerAxis axis,
) {
  final income = <String, double>{};
  final expense = <String, double>{};
  final count = <String, int>{};
  for (final row in rows) {
    // 按月给的 'YYYY-MM' 补成'当月 1 号'再落格，季/年轴才认得出它是哪一年
    final key = ledgerBucketKeyOf(
      row.date.length == 7 ? '${row.date}-01' : row.date,
      axis,
    );
    income[key] = (income[key] ?? 0) + row.income;
    expense[key] = (expense[key] ?? 0) + row.expense;
    count[key] = (count[key] ?? 0) + row.count;
  }
  return <LedgerAxisRow>[
    for (final bucket in buckets)
      LedgerAxisRow(
        bucket: bucket.key,
        income: income[bucket.key] ?? 0,
        expense: expense[bucket.key] ?? 0,
        net: (income[bucket.key] ?? 0) - (expense[bucket.key] ?? 0),
        count: count[bucket.key] ?? 0,
      ),
  ];
}

/// "今天/昨天"友好标签，其余给月日
String ledgerDateLabel(String date) {
  if (date.length < 10) return date;
  final today = DateTime.now();
  final asDate = DateTime(today.year, today.month, today.day);
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  final diff = asDate.difference(DateTime(parsed.year, parsed.month, parsed.day)).inDays;
  return switch (diff) {
    0 => '今天',
    1 => '昨天',
    2 => '前天',
    _ => '${parsed.month}月${parsed.day}日',
  };
}
