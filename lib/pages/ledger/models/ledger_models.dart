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
class LedgerCategory {
  const LedgerCategory({
    this.id = 0,
    this.name = '',
    this.icon = '',
    this.direction = kLedgerDirectionExpense,
    this.sortOrder = 0,
    this.isBuiltin = false,
  });

  final int id;
  final String name;
  final String icon;
  final String direction;
  final int sortOrder;
  final bool isBuiltin;

  bool get isIncome => direction == kLedgerDirectionIncome;

  LedgerCategory copyWith({String? name, String? icon, String? direction, int? sortOrder}) =>
      LedgerCategory(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        direction: direction ?? this.direction,
        sortOrder: sortOrder ?? this.sortOrder,
        isBuiltin: isBuiltin,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'icon': icon,
    'direction': direction,
    'sort_order': sortOrder,
  };

  factory LedgerCategory.fromJson(Map<String, dynamic> j) => LedgerCategory(
    id: _i(j, 'id'),
    name: _s(j, 'name'),
    icon: _s(j, 'icon'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    sortOrder: _i(j, 'sort_order'),
    isBuiltin: _b(j, 'is_builtin'),
  );
}

/// 一笔流水
class LedgerTx {
  const LedgerTx({
    this.id = 0,
    this.occurredAt = '',
    this.billDate = '',
    this.direction = kLedgerDirectionExpense,
    this.amount = 0,
    this.currency = 'CNY',
    this.accountId = 0,
    this.categoryId = 0,
    this.merchant = '',
    this.note = '',
    this.source = kLedgerSourceManual,
    this.ruleId = 0,
    this.emailUid = '',
    this.status = kLedgerStatusPosted,
    this.createdAt = '',
    this.updatedAt = '',
    this.accountName = '',
    this.categoryName = '',
    this.categoryIcon = '',
    this.categoryDirection = '',
  });

  final int id;
  final String occurredAt;
  final String billDate;
  final String direction;
  final double amount;
  final String currency;
  final int accountId;
  final int categoryId;
  final String merchant;
  final String note;
  final String source;
  final int ruleId;
  final String emailUid;
  final String status;
  final String createdAt;
  final String updatedAt;
  final String accountName;
  final String categoryName;
  final String categoryIcon;
  final String categoryDirection;

  bool get isIncome => direction == kLedgerDirectionIncome;
  bool get isPending => status == kLedgerStatusPending;
  bool get isIgnored => status == kLedgerStatusIgnored;
  bool get fromEmail => source == kLedgerSourceEmail;

  /// 带符号金额，用于汇总
  double get signedAmount => isIncome ? amount : -amount;

  DateTime get occurredDateTime => DateTime.tryParse(occurredAt.replaceFirst(' ', 'T')) ??
      (DateTime.tryParse(billDate) ?? DateTime.now());

  /// 展示用的"HH:MM"，邮件流水靠它区分同一天多笔
  String get timeLabel {
    if (occurredAt.length >= 16) return occurredAt.substring(11, 16);
    return '';
  }

  String get dateLabel => billDate.isEmpty ? occurredAt.substring(0, 10) : billDate;

  LedgerTx copyWith({
    int? accountId,
    int? categoryId,
    String? direction,
    double? amount,
    String? merchant,
    String? note,
    String? billDate,
    String? occurredAt,
    String? status,
    String? categoryName,
    String? categoryIcon,
    String? categoryDirection,
    String? accountName,
  }) => LedgerTx(
    id: id,
    occurredAt: occurredAt ?? this.occurredAt,
    billDate: billDate ?? this.billDate,
    direction: direction ?? this.direction,
    amount: amount ?? this.amount,
    currency: currency,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    merchant: merchant ?? this.merchant,
    note: note ?? this.note,
    source: source,
    ruleId: ruleId,
    emailUid: emailUid,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    accountName: accountName ?? this.accountName,
    categoryName: categoryName ?? this.categoryName,
    categoryIcon: categoryIcon ?? this.categoryIcon,
    categoryDirection: categoryDirection ?? this.categoryDirection,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'occurred_at': occurredAt,
    'bill_date': billDate,
    'direction': direction,
    'amount': amount,
    'currency': currency,
    'account_id': accountId,
    'category_id': categoryId,
    'merchant': merchant,
    'note': note,
    'source': source,
    'rule_id': ruleId,
    'email_uid': emailUid,
    'status': status,
  };

  factory LedgerTx.fromJson(Map<String, dynamic> j) => LedgerTx(
    id: _i(j, 'id'),
    occurredAt: _s(j, 'occurred_at'),
    billDate: _s(j, 'bill_date'),
    direction: _s(j, 'direction').isEmpty ? kLedgerDirectionExpense : _s(j, 'direction'),
    amount: _d(j, 'amount'),
    currency: _s(j, 'currency').isEmpty ? 'CNY' : _s(j, 'currency'),
    accountId: _i(j, 'account_id'),
    categoryId: _i(j, 'category_id'),
    merchant: _s(j, 'merchant'),
    note: _s(j, 'note'),
    source: _s(j, 'source').isEmpty ? kLedgerSourceManual : _s(j, 'source'),
    ruleId: _i(j, 'rule_id'),
    emailUid: _s(j, 'email_uid'),
    status: _s(j, 'status').isEmpty ? kLedgerStatusPosted : _s(j, 'status'),
    createdAt: _s(j, 'created_at'),
    updatedAt: _s(j, 'updated_at'),
    accountName: _s(j, 'account_name'),
    categoryName: _s(j, 'category_name'),
    categoryIcon: _s(j, 'category_icon'),
    categoryDirection: _s(j, 'category_direction'),
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
    this.accountId = 0,
    this.categoryId = 0,
    this.source = '',
    this.status = '',
    this.keyword = '',
    this.limit = 0,
    this.offset = 0,
  });

  final String startDate;
  final String endDate;
  final String direction;
  final int accountId;
  final int categoryId;
  final String source;
  final String status;
  final String keyword;
  final int limit;
  final int offset;

  LedgerFilter copyWith({
    String? startDate,
    String? endDate,
    String? direction,
    int? accountId,
    int? categoryId,
    String? source,
    String? status,
    String? keyword,
    int? limit,
    int? offset,
  }) => LedgerFilter(
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    direction: direction ?? this.direction,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
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
    if (accountId > 0) 'account_id': accountId,
    if (categoryId > 0) 'category_id': categoryId,
    if (source.isNotEmpty) 'source': source,
    if (status.isNotEmpty) 'status': status,
    if (keyword.isNotEmpty) 'keyword': keyword,
    if (limit > 0) 'limit': limit,
    if (offset > 0) 'offset': offset,
  };

  String get json => jsonEncode(toJson());
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
