import 'dart:convert';

/// 流水账演示后端：账户、类别、流水、统计、规则与待确认邮件。
class MockLedgerData {
  MockLedgerData._() {
    _seed();
  }

  static final MockLedgerData instance = MockLedgerData._();

  final List<Map<String, dynamic>> accounts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> categories = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> transactions = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> rules = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> merchantMemory = <Map<String, dynamic>>[];
  int _txId = 0;
  int _logId = 0;

  static const _accountNames = ['微信零钱', '招行信用卡', '支付宝'];

  void _seed() {
    final now = DateTime.now();
    accounts.addAll([
      {
        'id': 1,
        'name': '微信零钱',
        'type': 'ewallet',
        'last4': '6688',
        'currency': 'CNY',
        'balance': 3280.5,
        'sort_order': 0,
        'enabled': true,
      },
      {
        'id': 2,
        'name': '招行信用卡',
        'type': 'credit_card',
        'last4': '1024',
        'currency': 'CNY',
        'credit_limit': 30000,
        'balance': -1260.8,
        'sort_order': 1,
        'enabled': true,
      },
      {
        'id': 3,
        'name': '支付宝',
        'type': 'ewallet',
        'last4': '9527',
        'currency': 'CNY',
        'balance': 860.2,
        'sort_order': 2,
        'enabled': true,
      },
    ]);

    const expense = [
      ['餐饮', '🍜', '1'],
      ['交通', '🚇', '2'],
      ['购物', '🛍️', '3'],
      ['居住', '🏠', '4'],
      ['娱乐', '🎬', '5'],
      ['医疗', '💊', '6'],
      ['学习', '📚', '7'],
      ['其他', '🧾', '8'],
    ];
    var id = 1;
    for (final e in expense) {
      categories.add({
        'id': id++,
        'name': e[0],
        'icon': e[1],
        'direction': 'expense',
        'sort_order': int.parse(e[2]),
        'is_builtin': true,
        'parent_id': 0,
        'color': '',
      });
    }
    categories.addAll([
      {
        'id': 20,
        'name': '工资',
        'icon': '💰',
        'direction': 'income',
        'sort_order': 1,
        'is_builtin': true,
        'parent_id': 0,
        'color': '',
      },
      {
        'id': 21,
        'name': '理财',
        'icon': '📈',
        'direction': 'income',
        'sort_order': 2,
        'is_builtin': true,
        'parent_id': 0,
        'color': '',
      },
    ]);

    for (var m = 2; m >= 0; m--) {
      final base = DateTime(now.year, now.month - m, 1);
      for (var d = 1; d <= 24; d++) {
        final day = DateTime(base.year, base.month, d);
        if (day.isAfter(now)) break;
        final date =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final isIncome = d == 5 || d == 20;
        final catId = isIncome ? (d == 5 ? 20 : 21) : (1 + d % 8);
        final cat = categories.firstWhere((c) => c['id'] == catId);
        final merchant = isIncome ? '公司财务' : _merchants[d % _merchants.length];
        transactions.add({
          'id': ++_txId,
          'occurred_at': '${date}T12:30:00',
          'bill_date': date,
          'direction': isIncome ? 'income' : 'expense',
          'tx_type': isIncome ? 'income' : 'expense',
          'amount': isIncome
              ? (d == 5 ? 12800.0 : 320.0)
              : double.parse((12 + (d * 7.3) % 180).toStringAsFixed(2)),
          'currency': 'CNY',
          'account_id': 1 + d % 3,
          'account_name': _accountNames[d % 3],
          'category_id': catId,
          'category_name': cat['name'],
          'category_icon': cat['icon'],
          'category_direction': cat['direction'],
          'merchant': merchant,
          'note': isIncome ? '月度入账' : '演示消费 $d',
          'tag_ids': <int>[],
          'tag_names': <String>[],
          'source': 'manual',
          'status': 'posted',
          'created_at': '${date}T12:35:00',
          'updated_at': '${date}T12:35:00',
          'hidden': false,
        });
      }
    }
    transactions.sort(
      (a, b) => (b['bill_date'] as String).compareTo(a['bill_date'] as String),
    );

    rules.addAll([
      {
        'id': 1,
        'name': '招行账单',
        'enabled': true,
        'protocol': 'imap',
        'host': 'imap.example.com',
        'port': 993,
        'use_ssl': true,
        'username': 'demo@slime.local',
        'mailbox': 'INBOX',
        'sender_match': 'creditcard@example.com',
        'subject_match': '账单',
        'match_is_regex': false,
        'template_id': 'cmb',
        'template_config': '{}',
        'interval_minutes': 60,
        'daily_time': '',
        'default_account_id': 2,
        'auto_apply': true,
        'accept_invalid_certs': false,
        'last_run_at': '',
        'last_result': '演示规则',
      },
      {
        'id': 2,
        'name': '支付宝账单',
        'enabled': false,
        'protocol': 'imap',
        'host': 'imap.example.com',
        'port': 993,
        'use_ssl': true,
        'username': 'demo@slime.local',
        'mailbox': 'INBOX',
        'sender_match': 'alipay@example.com',
        'subject_match': '对账单',
        'match_is_regex': false,
        'template_id': 'alipay',
        'template_config': '{}',
        'interval_minutes': 180,
        'daily_time': '08:00',
        'default_account_id': 3,
        'auto_apply': false,
        'accept_invalid_certs': false,
        'last_run_at': '',
        'last_result': '',
      },
    ]);

    merchantMemory.addAll([
      {'merchant': '星巴克', 'category_id': 1, 'category_name': '餐饮', 'hit_count': 18},
      {'merchant': '地铁出行', 'category_id': 2, 'category_name': '交通', 'hit_count': 42},
      {'merchant': '山姆会员店', 'category_id': 3, 'category_name': '购物', 'hit_count': 11},
      {'merchant': '哔哩哔哩', 'category_id': 5, 'category_name': '娱乐', 'hit_count': 9},
      {'merchant': '连锁药房', 'category_id': 6, 'category_name': '医疗', 'hit_count': 4},
    ]);
  }

  static const List<String> _merchants = [
    '星巴克',
    '地铁出行',
    '山姆会员店',
    '哔哩哔哩',
    '连锁药房',
    '街角面馆',
    '城市书店',
  ];

  List<Map<String, dynamic>> filterTx(Map<String, dynamic> params) {
    final filter = _filterOf(params);
    var list = List<Map<String, dynamic>>.of(transactions);
    final start = filter['start_date'] as String? ?? '';
    final end = filter['end_date'] as String? ?? '';
    final direction = filter['direction'] as String? ?? '';
    final accountId = (filter['account_id'] as num?)?.toInt() ?? 0;
    final categoryId = (filter['category_id'] as num?)?.toInt() ?? 0;
    final keyword = (filter['keyword'] as String? ?? '').trim();
    if (start.isNotEmpty) {
      list = list.where((t) => (t['bill_date'] as String).compareTo(start) >= 0).toList();
    }
    if (end.isNotEmpty) {
      list = list.where((t) => (t['bill_date'] as String).compareTo(end) <= 0).toList();
    }
    if (direction.isNotEmpty) {
      list = list.where((t) => t['direction'] == direction).toList();
    }
    if (accountId > 0) {
      list = list.where((t) => t['account_id'] == accountId).toList();
    }
    if (categoryId > 0) {
      list = list.where((t) => t['category_id'] == categoryId).toList();
    }
    if (keyword.isNotEmpty) {
      list = list
          .where(
            (t) =>
                (t['merchant'] as String).contains(keyword) ||
                (t['note'] as String).contains(keyword),
          )
          .toList();
    }
    final offset = (filter['offset'] as num?)?.toInt() ?? 0;
    final limit = (filter['limit'] as num?)?.toInt() ?? 0;
    if (offset > 0) list = list.skip(offset).toList();
    if (limit > 0) list = list.take(limit).toList();
    return list;
  }

  Map<String, dynamic> _filterOf(Map<String, dynamic> params) {
    final raw = params['filter_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (raw is Map<String, dynamic>) return raw;
    return <String, dynamic>{};
  }

  String raw(String action, Map<String, dynamic> params) =>
      jsonEncode(_handle(action, params));

  String text(String action, Map<String, dynamic> params) {
    final result = _handle(action, params);
    return result is String ? result : '操作成功';
  }

  int id(String action, Map<String, dynamic> params) {
    final result = _handle(action, params);
    return result is int ? result : 0;
  }

  bool boolean(String action, Map<String, dynamic> params) {
    final result = _handle(action, params);
    return result is bool ? result : false;
  }

  void run(String action, Map<String, dynamic> params) => _handle(action, params);

  Object? _handle(String action, Map<String, dynamic> params) {
    switch (action) {
      case 'ledger_list_accounts':
        return accounts;
      case 'ledger_upsert_account':
        return _upsertAccount(params);
      case 'ledger_delete_account':
        accounts.removeWhere((a) => a['id'] == params['id']);
        return 'ok';
      case 'ledger_list_categories':
        final direction = params['direction'] as String? ?? '';
        return direction.isEmpty
            ? categories
            : categories.where((c) => c['direction'] == direction).toList();
      case 'ledger_upsert_category':
        return _upsertCategory(params);
      case 'ledger_delete_category':
        categories.removeWhere((c) => c['id'] == params['id']);
        return 'ok';
      case 'ledger_list_merchant_memory':
        return merchantMemory;
      case 'ledger_forget_merchant':
        merchantMemory.removeWhere((m) => m['merchant'] == params['merchant_key']);
        return null;
      case 'ledger_list_transactions':
        return filterTx(params);
      case 'ledger_count_transactions':
        final f = _filterOf(params);
        final savedOffset = f['offset'];
        final savedLimit = f['limit'];
        f['offset'] = 0;
        f['limit'] = 0;
        final count = filterTx(<String, dynamic>{'filter_json': jsonEncode(f)}).length;
        f['offset'] = savedOffset;
        f['limit'] = savedLimit;
        return count;
      case 'ledger_add_transaction':
        return _addTx(params);
      case 'ledger_update_transaction':
        _updateTx(params);
        return null;
      case 'ledger_delete_transaction':
        final before = transactions.length;
        transactions.removeWhere((t) => t['id'] == params['id']);
        return transactions.length != before;
      case 'ledger_check_duplicate':
        return {'duplicated': false, 'existing_id': 0, 'existing_desc': ''};
      case 'ledger_stats_by_day':
        return _byDay(params);
      case 'ledger_stats_by_category':
        return _byCategory(params);
      case 'ledger_stats_by_merchant':
        return _byMerchant(params);
      case 'ledger_stats_by_month':
        return _byMonth(params);
      case 'ledger_stats_summary':
        return _summary(params);
      case 'ledger_list_rules':
        return rules;
      case 'ledger_upsert_rule':
        return _upsertRule(params);
      case 'ledger_delete_rule':
        rules.removeWhere((r) => r['id'] == params['id']);
        return null;
      case 'ledger_set_rule_enabled':
        for (final r in rules) {
          if (r['id'] == params['id']) r['enabled'] = params['enabled'];
        }
        return null;
      case 'ledger_templates':
        return [
          {'id': 'auto', 'name': '自动识别', 'description': '根据邮件正文自动判断账单结构'},
          {'id': 'cmb', 'name': '招行信用卡', 'description': '招商银行信用卡账单模板'},
          {'id': 'alipay', 'name': '支付宝账单', 'description': '支付宝月度对账单模板'},
          {'id': 'wechat', 'name': '微信支付', 'description': '微信支付账单模板'},
        ];
      case 'ledger_parse_preview':
        return '识别到 3 笔交易：\n2025-03-02  星巴克  -32.00\n2025-03-05  地铁出行  -6.00\n2025-03-08  山姆会员店  -286.40';
      case 'ledger_check_rule':
        return '连接成功，匹配到 3 封账单邮件（演示数据）。';
      case 'ledger_backfill_rule':
        return '补录完成：新增 12 笔交易（演示数据）。';
      case 'ledger_fetch_emails':
        return _fetchedEmails();
      case 'ledger_test_connection':
        return {
          'ok': true,
          'protocol': 'imap',
          'detail': '演示连接可用',
          'capabilities': ['idle', 'search'],
          'folders': ['INBOX', '账单', 'Archive'],
        };
      case 'ledger_list_pending':
      case 'ledger_list_received_emails':
        return _pendingEmails();
      case 'ledger_email_transactions':
        return transactions.take(3).toList();
      case 'ledger_pending_count':
        return _pendingEmails().length;
      case 'ledger_confirm_tx':
      case 'ledger_confirm_all':
      case 'ledger_ignore_tx':
      case 'ledger_ignore_email':
      case 'ledger_purge_email':
        return action == 'ledger_confirm_all' ? 4 : null;
      case 'ledger_scheduler_start':
      case 'ledger_scheduler_stop':
        return null;
      case 'ledger_scheduler_status':
        return {
          'running': true,
          'enabled': true,
          'check_interval_secs': 300,
          'last_check_at': '2025-03-21 08:00:00',
          'next_check_at': '2025-03-21 08:05:00',
          'active_rules': 1,
          'last_summary': '本次新增 3 笔',
        };
      case 'ledger_get_logs':
        return _logs();
      case 'ledger_clear_logs':
        return null;
      case 'ledger_has_rule_password':
        return true;
      case 'ledger_set_rule_password':
        return null;
      default:
        return null;
    }
  }

  int _upsertAccount(Map<String, dynamic> params) {
    final map = jsonDecode(params['account_json'] as String? ?? '{}') as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) {
      final newId = accounts.length + 1;
      map['id'] = newId;
      map['sort_order'] ??= accounts.length;
      map['enabled'] ??= true;
      accounts.add(map);
      return newId;
    }
    final i = accounts.indexWhere((a) => a['id'] == id);
    if (i >= 0) accounts[i] = {...accounts[i], ...map};
    return id;
  }

  int _upsertCategory(Map<String, dynamic> params) {
    final map = jsonDecode(params['category_json'] as String? ?? '{}') as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) {
      final newId = categories.length + 1;
      map['id'] = newId;
      map['is_builtin'] = false;
      map['parent_id'] ??= 0;
      categories.add(map);
      return newId;
    }
    final i = categories.indexWhere((c) => c['id'] == id);
    if (i >= 0) categories[i] = {...categories[i], ...map};
    return id;
  }

  int _addTx(Map<String, dynamic> params) {
    final map = jsonDecode(params['tx_json'] as String? ?? '{}') as Map<String, dynamic>;
    final id = ++_txId;
    map['id'] = id;
    map['status'] ??= 'posted';
    map['source'] ??= 'manual';
    map['currency'] ??= 'CNY';
    map['created_at'] ??= DateTime.now().toString();
    map['updated_at'] = DateTime.now().toString();
    _decorate(map);
    transactions.insert(0, map);
    return id;
  }

  void _updateTx(Map<String, dynamic> params) {
    final map = jsonDecode(params['tx_json'] as String? ?? '{}') as Map<String, dynamic>;
    final i = transactions.indexWhere((t) => t['id'] == map['id']);
    if (i < 0) return;
    _decorate(map);
    transactions[i] = {...transactions[i], ...map};
  }

  void _decorate(Map<String, dynamic> tx) {
    final accountId = (tx['account_id'] as num?)?.toInt() ?? 0;
    final account = accounts.where((a) => a['id'] == accountId);
    if (account.isNotEmpty) tx['account_name'] = account.first['name'];
    final categoryId = (tx['category_id'] as num?)?.toInt() ?? 0;
    final category = categories.where((c) => c['id'] == categoryId);
    if (category.isNotEmpty) {
      tx['category_name'] = category.first['name'];
      tx['category_icon'] = category.first['icon'];
      tx['category_direction'] = category.first['direction'];
    }
  }

  List<Map<String, dynamic>> _byDay(Map<String, dynamic> params) {
    final list = filterTx(params);
    final map = <String, Map<String, dynamic>>{};
    for (final t in list) {
      final date = t['bill_date'] as String;
      final row = map.putIfAbsent(
        date,
        () => {'bill_date': date, 'income': 0.0, 'expense': 0.0, 'count': 0},
      );
      if (t['direction'] == 'income') {
        row['income'] = (row['income'] as double) + (t['amount'] as num).toDouble();
      } else {
        row['expense'] = (row['expense'] as double) + (t['amount'] as num).toDouble();
      }
      row['count'] = (row['count'] as int) + 1;
    }
    return map.values.toList()
      ..sort((a, b) => (a['bill_date'] as String).compareTo(b['bill_date'] as String));
  }

  List<Map<String, dynamic>> _byCategory(Map<String, dynamic> params) {
    final list = filterTx(params);
    final map = <int, Map<String, dynamic>>{};
    for (final t in list) {
      final id = t['category_id'] as int;
      final row = map.putIfAbsent(
        id,
        () => {
          'category_id': id,
          'category_name': t['category_name'],
          'category_icon': t['category_icon'],
          'direction': t['direction'],
          'total': 0.0,
          'count': 0,
        },
      );
      row['total'] = (row['total'] as double) + (t['amount'] as num).toDouble();
      row['count'] = (row['count'] as int) + 1;
    }
    final rows = map.values.toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return rows;
  }

  List<Map<String, dynamic>> _byMerchant(Map<String, dynamic> params) {
    final list = filterTx(params);
    final top = (params['top'] as num?)?.toInt() ?? 10;
    final map = <String, Map<String, dynamic>>{};
    for (final t in list) {
      final merchant = t['merchant'] as String? ?? '未知';
      final row = map.putIfAbsent(
        merchant,
        () => {
          'merchant': merchant,
          'total': 0.0,
          'count': 0,
          'last_date': t['bill_date'],
        },
      );
      row['total'] = (row['total'] as double) + (t['amount'] as num).toDouble();
      row['count'] = (row['count'] as int) + 1;
      if ((t['bill_date'] as String).compareTo(row['last_date'] as String) > 0) {
        row['last_date'] = t['bill_date'];
      }
    }
    final rows = map.values.toList()
      ..sort((a, b) => (b['total'] as double).compareTo(a['total'] as double));
    return rows.take(top).toList();
  }

  List<Map<String, dynamic>> _byMonth(Map<String, dynamic> params) {
    final count = (params['months'] as num?)?.toInt() ?? 12;
    final map = <String, Map<String, dynamic>>{};
    for (final t in transactions) {
      final month = (t['bill_date'] as String).substring(0, 7);
      final row = map.putIfAbsent(
        month,
        () => {'month': month, 'income': 0.0, 'expense': 0.0, 'net': 0.0, 'count': 0},
      );
      final amount = (t['amount'] as num).toDouble();
      if (t['direction'] == 'income') {
        row['income'] = (row['income'] as double) + amount;
      } else {
        row['expense'] = (row['expense'] as double) + amount;
      }
      row['count'] = (row['count'] as int) + 1;
    }
    final rows = map.values.toList()
      ..sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
    for (final r in rows) {
      r['net'] = (r['income'] as double) - (r['expense'] as double);
    }
    return rows.length > count ? rows.sublist(rows.length - count) : rows;
  }

  Map<String, dynamic> _summary(Map<String, dynamic> params) {
    final list = filterTx(params);
    var income = 0.0;
    var expense = 0.0;
    for (final t in list) {
      final amount = (t['amount'] as num).toDouble();
      if (t['direction'] == 'income') {
        income += amount;
      } else {
        expense += amount;
      }
    }
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    var monthIncome = 0.0;
    var monthExpense = 0.0;
    for (final t in transactions) {
      if (!(t['bill_date'] as String).startsWith(month)) continue;
      final amount = (t['amount'] as num).toDouble();
      if (t['direction'] == 'income') {
        monthIncome += amount;
      } else {
        monthExpense += amount;
      }
    }
    return {
      'income': income,
      'expense': expense,
      'net': income - expense,
      'count': list.length,
      'min_date': list.isEmpty ? '' : (list.last['bill_date'] as String),
      'max_date': list.isEmpty ? '' : (list.first['bill_date'] as String),
      'month': month,
      'month_income': monthIncome,
      'month_expense': monthExpense,
      'month_net': monthIncome - monthExpense,
    };
  }

  int _upsertRule(Map<String, dynamic> params) {
    final map = jsonDecode(params['rule_json'] as String? ?? '{}') as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) {
      final newId = rules.length + 1;
      map['id'] = newId;
      rules.add(map);
      return newId;
    }
    final i = rules.indexWhere((r) => r['id'] == id);
    if (i >= 0) rules[i] = {...rules[i], ...map};
    return id;
  }

  List<Map<String, dynamic>> _pendingEmails() => [
    for (var i = 0; i < 4; i++)
      {
        'id': 100 + i,
        'rule_id': 1,
        'rule_name': i.isEven ? '招行账单' : '支付宝账单',
        'message_uid': 'mock-mail-$i',
        'from_addr': 'bill@example.com',
        'subject': '${DateTime.now().month} 月账单（演示 ${i + 1}）',
        'received_at': '2025-03-2${i + 1} 08:00:00',
        'bill_date': '2025-03-2${i + 1}',
        'tx_count': 3 + i,
        'applied': i == 3,
        'available_credit': 28600.0 - i * 300,
        'points_balance': 1200 + i * 50,
        'warnings': i == 1 ? <String>['有一笔金额无法识别'] : <String>[],
        'html_len': 2048 + i * 128,
      },
  ];

  List<Map<String, dynamic>> _fetchedEmails() => [
    for (var i = 0; i < 3; i++)
      {
        'uid': 'mock-uid-$i',
        'from': 'bill@example.com',
        'subject': '账单邮件 ${i + 1}（演示）',
        'date': '2025-03-2${i + 1} 08:00:00',
        'size_bytes': 4096 + i * 512,
        'html_len': 1800,
        'matched': i != 2,
        'template_id': 'cmb',
        'bill_date': '2025-03-2${i + 1}',
        'tx_count': i == 2 ? 0 : 3,
        'warnings': <String>[],
        'transactions': <Map<String, dynamic>>[],
        'body_text_head': '尊敬的用户，您本期账单如下……',
      },
  ];

  List<Map<String, dynamic>> _logs() => [
    for (var i = 0; i < 5; i++)
      {
        'id': ++_logId,
        'rule_id': 1 + i % 2,
        'started_at': '2025-03-2${i + 1} 08:00:00',
        'finished_at': '2025-03-2${i + 1} 08:00:06',
        'ok': i != 1,
        'new_emails': i.isEven ? 1 : 0,
        'new_tx': i.isEven ? 3 : 0,
        'skipped_tx': i == 2 ? 1 : 0,
        'detail': i == 1 ? '登录失败（演示）' : '收取完成',
      },
  ];
}
