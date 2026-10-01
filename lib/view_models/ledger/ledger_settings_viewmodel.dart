import 'package:get/get.dart';
import 'package:get_it/get_it.dart';

import 'package:slime_works/core/services/ledger_service.dart';
import 'package:slime_works/core/viewmodels/base_viewmodel.dart';
import 'package:slime_works/pages/ledger/models/ledger_models.dart';

/// 邮箱账单设置页：规则 CRUD、连接自检、试收取、调度与日志。
///
/// 口令只走 `LedgerService` 的安全存储，VM 里不留任何明文副本，
/// 也不把口令写进任何状态字段或日志。
class LedgerSettingsViewModel extends BaseViewModel {
  final LedgerService _service = GetIt.instance.get<LedgerService>();

  final RxList<LedgerRule> rules = <LedgerRule>[].obs;
  final RxList<LedgerTemplate> templates = <LedgerTemplate>[].obs;
  final RxList<LedgerAccount> accounts = <LedgerAccount>[].obs;
  final RxList<LedgerFetchLog> logs = <LedgerFetchLog>[].obs;
  final Rx<LedgerSchedulerStatus> scheduler = const LedgerSchedulerStatus().obs;
  final RxMap<int, bool> hasPassword = <int, bool>{}.obs;
  final RxString lastMessage = ''.obs;
  final RxBool probing = false.obs;

  /// "启动应用时自动打开"是独立于本次运行状态的本地偏好，
  /// 关掉它只是下次启动不拉起定时器，不影响现在正在跑的那一个。
  final RxBool autoOpenScheduler = true.obs;

  @override
  Future<void> onInitAsync() async {
    await _service.ensureInitialized();
    await reload();
    super.onInitAsync();
  }

  Future<void> reload() async {
    setLoading(true);
    try {
      rules.assignAll(await _service.listRules());
      templates.assignAll(await _service.listTemplates());
      accounts.assignAll(await _service.listAccounts());
      logs.assignAll(await _service.listLogs(limit: 30));
      scheduler.value = await _service.schedulerStatus();
      autoOpenScheduler.value = _service.autoOpenScheduler;
      for (final rule in rules) {
        hasPassword[rule.id] = await _service.hasRulePassword(rule.id);
      }
      clearError();
    } catch (e) {
      setError('读取邮箱设置失败: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<LedgerSaveResult> saveRule(LedgerRule rule, String password) async {
    try {
      await _service.upsertRule(rule, password: password);
      lastMessage.value = '规则「${rule.name}」已保存';
      await reload();
      return LedgerSaveResult.saved;
    } catch (e) {
      setError('保存规则失败: $e');
      return LedgerSaveResult.failed;
    }
  }

  Future<void> deleteRule(int id) async {
    try {
      await _service.deleteRule(id);
      lastMessage.value = '规则已删除';
      await reload();
    } catch (e) {
      setError('删除规则失败: $e');
    }
  }

  Future<void> setEnabled(int id, bool enabled) async {
    try {
      await _service.setRuleEnabled(id, enabled);
      await reload();
    } catch (e) {
      setError('切换开关失败: $e');
    }
  }

  /// 只换口令（编辑已有规则时口令框留空表示不改）
  Future<void> updatePassword(int ruleId, String password) async {
    try {
      await _service.setRulePassword(ruleId, password);
      hasPassword[ruleId] = password.isNotEmpty ||
          await _service.hasRulePassword(ruleId);
      lastMessage.value = password.isEmpty ? '口令已清除' : '口令已更新';
    } catch (e) {
      setError('保存口令失败: $e');
    }
  }

  /// 连接自检：表单里的临时配置也能测，不要求先保存
  Future<LedgerProbeReport?> probe(LedgerRule rule, String password) async {
    probing.value = true;
    try {
      final report = await _service.testConnection(
        config: _configOf(rule, password),
        password: password,
        wantFolders: rule.protocol == 'imap',
      );
      lastMessage.value = report.ok
          ? '连接成功${report.folders.isEmpty ? '' : '，可见 ${report.folders.length} 个文件夹'}'
          : '连接失败：${report.detail}';
      return report;
    } catch (e) {
      setError('连接自检失败: $e');
      return null;
    } finally {
      probing.value = false;
    }
  }

  /// 试收取：解析但不落库，用来在保存前确认模板抓得住
  Future<List<LedgerFetchedEmail>> previewFetch(LedgerRule rule, String password, {int limit = 5}) async {
    probing.value = true;
    try {
      return await _service.fetchEmails(
        config: _configOf(rule, password),
        password: password,
        limit: limit,
      );
    } catch (e) {
      setError('试收取失败: $e');
      return const <LedgerFetchedEmail>[];
    } finally {
      probing.value = false;
    }
  }

  /// 贴一段账单 HTML 直接验证模板
  Future<LedgerParseResult?> parseSample(String html, LedgerRule rule) async {
    probing.value = true;
    try {
      return await _service.parsePreview(
        html: html,
        templateId: rule.templateId,
        templateConfig: rule.templateConfig,
      );
    } catch (e) {
      setError('解析失败: $e');
      return null;
    } finally {
      probing.value = false;
    }
  }

  Future<void> runRuleNow(int ruleId) async {
    probing.value = true;
    try {
      lastMessage.value = await _service.checkRule(ruleId);
      await reload();
    } catch (e) {
      setError('立即收取失败: $e');
    } finally {
      probing.value = false;
    }
  }

  /// 回补历史邮件：日常收取只看最新 10 封，这里把最近的历史邮件逐封匹配补录。
  ///
  /// 已入过账的邮件由 Rust 侧按 UID 跳过、流水表又有唯一索引兜底，所以重复点
  /// 不会记两遍；代价是几十秒到几分钟的批量下载，界面上用 [probing] 挡住重入。
  Future<void> backfillRule(int ruleId) async {
    probing.value = true;
    lastMessage.value = '正在回补历史邮件…';
    try {
      lastMessage.value = await _service.backfillHistory(ruleId);
      await reload();
    } catch (e) {
      setError('历史回补失败: $e');
    } finally {
      probing.value = false;
    }
  }

  Future<void> setSchedulerEnabled(bool enabled) async {
    try {
      if (enabled) {
        await _service.startScheduler();
      } else {
        await _service.stopScheduler();
      }
      scheduler.value = await _service.schedulerStatus();
      // 关开关时把"启动时自动打开"一起落盘：用户明确关掉的偏好不该在下次启动复活，
      // 而这次刷新也让另一个开关立刻反映后端真实值。
      await _service.setAutoOpenScheduler(enabled);
      autoOpenScheduler.value = _service.autoOpenScheduler;
    } catch (e) {
      setError('调度开关设置失败: $e');
    }
  }

  Future<void> setAutoOpenScheduler(bool value) async {
    autoOpenScheduler.value = value;
    try {
      await _service.setAutoOpenScheduler(value);
    } catch (e) {
      setError('启动偏好设置失败: $e');
    }
  }

  Future<void> clearLogs() async {
    try {
      await _service.clearLogs();
      await reload();
    } catch (e) {
      setError('清空日志失败: $e');
    }
  }

  /// 与 Rust 的 EmailAccountWire 字段一致；rule_id 为 0 表示用内联配置
  Map<String, dynamic> _configOf(LedgerRule rule, String password) => <String, dynamic>{
    'rule_id': rule.id,
    'protocol': rule.protocol,
    'host': rule.host,
    'port': rule.port,
    'use_ssl': rule.useSsl,
    'username': rule.username,
    'mailbox': rule.mailbox,
    'sender_match': rule.senderMatch,
    'subject_match': rule.subjectMatch,
    'match_is_regex': rule.matchIsRegex,
    'template_id': rule.templateId,
    'template_config': rule.templateConfig,
    'default_account_id': rule.defaultAccountId,
    'auto_apply': rule.autoApply,
    'accept_invalid_certs': rule.acceptInvalidCerts,
    'password': password,
  };
}
