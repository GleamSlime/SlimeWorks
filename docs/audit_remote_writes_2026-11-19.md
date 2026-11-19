# 远程节点模式下「用户在页面上点按钮」写出路径审计（非 media / novel）

> 审计日期：2026-11-19
> 审计人：remote-auditor（只读审计，未修改任何 `lib/` / `rust/` 源码）
> 任务：task-5
> 方法：**站在用户远程节点模式下真点按钮的角度**，逐个模块从 UI 入口 → ViewModel → Service → 节点 action 追写路径。
> 判据：套用上一轮已确认的三类根因（节点缺 action / 吞 Result<bool>；客户端缺远程分支；UI 入口该隐藏没隐藏）。

---

## 0. 审计装置与可复现命令

审计期间起了一个**独立的空数据目录无头节点**（不碰 Lead 的 17901 装置、不碰开发者真实库）：

```bash
mkdir -p /tmp/audit_node/data
rust/target/debug/slime_node --port 18255 --host 127.0.0.1 \
  --name audit --data-dir /tmp/audit_node/data
```

下文所有「实测」结论都可以用下面这种形式复核：

```bash
curl -s -X POST http://127.0.0.1:18255/node/call \
  -H 'Content-Type: application/json' \
  -d '{"action":"<action>","params":{...}}'
```

★ **这个空数据目录很关键**：它暴露了一个用 Lead 的 17901 装置永远看不到的问题——17901 是长期运行、被反复操作过的实例，很多模块的全局单例早就被初始化过了；新建的节点进程**没有任何模块初始化**（见 §1）。

---

## 1. 【确定是 bug】根因补充：节点侧全局模块没有任何初始化入口

这是本报告里**影响面最大的一条**，也是上一轮「只测 media/novel 契约」绝对测不出来的——因为它不是某个 action 写错了，而是**整个模块在节点进程里根本不存在**。

### 证据：`slime_node` 启动流程里没有业务模块 init

`rust/src/bin/slime_node.rs:222` 起是节点的启动收尾，全流程只做了：解析参数 → 落数据目录环境变量 → 建日志目录 → `init_logger` → 注册 ffmpeg 路径 → `start_node_server`。

```
rust/src/bin/slime_node.rs:200   rust_lib_slime_works::api::logger::init_logger(...)
rust/src/bin/slime_node.rs:222   rust_lib_slime_works::node_server::start_node_server(...)
```

`node_server::start_node_server`（`rust/src/node_server/mod.rs:1087`）到 accept 循环为止也没有任何模块 init：

```rust
// rust/src/node_server/mod.rs:1087
pub fn start_node_server(host: String, port: u16, name: String, auth_code: String) -> Result<(), String> {
    ...
    let listener = TcpListener::bind(...)?;   // 绑端口
    // 之后只有 accept 线程
```

唯一的「兜底初始化」只给账本：

```rust
// rust/src/node_server/handlers.rs:42
fn ensure_ledger_ready() -> Result<(), String> {
    if ledger_module::api::ledger_is_ready() { return Ok(()); }
    let path = get_app_data_path("ledger/ledger.db");
    ...
}
// rust/src/node_server/handlers.rs:170-172
if action.starts_with("ledger_") {
    ensure_ledger_ready()?;
}
```

grep 全仓确认**只有账本有兜底**：

```
$ grep -rn "aliyun_ddns_init\|power_stats_init\|sentry_log_init" rust/src/node_server/
(无输出)
```

而这三个模块的 `get_manager()` 都是「没 init 就报未初始化」：

```rust
// rust/aliyun_module/src/api.rs:32-35
fn get_manager() -> Result<Arc<DdnsManager>, String> {
    DDNS_INSTANCE.read()...?.clone()
        .ok_or("DDNS模块未初始化".to_string())
}
// rust/power_stats/src/api.rs:25-31
fn get_manager() -> Result<Arc<PowerStatsManager>, String> {
    ... .ok_or("电力统计模块未初始化".to_string())
}
// rust/sentry_log/src/api.rs:9-13
fn get_instance() -> Result<&'static Arc<SentryLogStorage>, String> {
    SENTRY_LOG_INSTANCE.get().ok_or("Sentry日志存储未初始化".to_string())
}
```

### 实测（全新节点，四个模块全挂）

```
$ curl -s http://127.0.0.1:18255/aliyun/status
{"error":"DDNS模块未初始化","success":false}

$ curl -s -X POST .../node/call -d '{"action":"power_stats_get_status","params":{}}'
{"success":false,"error":"获取电力统计状态失败: 电力统计模块未初始化"}

$ curl -s http://127.0.0.1:18255/sentry/stats
{"error":"Sentry日志存储未初始化"}
```

**用户视角**：在设置里把节点加进「阿里云 / 电力统计 / Sentry」，面板探测失败（`checkNodeXxxAvailable` 全部 `catch(_) => false`），页面显示「该节点不支持此功能」。功能整个不可用，且**没有任何办法让它在远程节点上跑起来**——因为节点进程里没有代码去 init 它。

★ 这一条解释了为什么之前「很多已知的也没测出来」：之前所有验证都在 Lead 那个**跑过桌面端初始化**的节点实例（或直接用 `RustLib.init()` 起客户端）上做，模块全局单例是热的。真正独立的无头节点是冷的。

**修复方向**（供 Lead 开任务）：
1. `slime_node` 启动时按数据目录初始化 aliyun / power_stats / sentry_log（power_stats 需要 `persist=true` + db_path，因为节点是无头常驻的，理应持久化）；
2. 或者仿 `ensure_ledger_ready` 给每个模块一个惰性兜底 init（更稳，和现有约定一致）；
3. 修完要有验收：**全新 `--data-dir` 起的节点**上这些 action 必须成功。

---

## 2. 【确定是 bug（要修）】逐模块明细

### 2.1 `/aliyun` 阿里云 DDNS —— 远程模式下「立即检查」必然失败，且失败静默

**数据来源**：远程分支齐全（`fetchRemoteStatus` / `fetchRemoteLogs` / `fetchRemoteWatchDomains` / `remoteCheckAndUpdate`），走的是 `/aliyun/*` HTTP 路由（`rust/src/node_server/mod.rs:883-925`）。**但背后模块没初始化**（§1），所以三个 GET 全 500。

**写操作远程分支**：

| UI 动作 | 代码 | 远程结果 |
|---|---|---|
| 「立即检查」按钮 | `lib/pages/aliyun_ddns/aliyun_ddns_screen.dart:829` → `AliyunDdnsViewModel.checkNow()` `lib/view_models/aliyun_ddns_viewmodel.dart:134` | 走 `remoteCheckAndUpdate()` → 节点回 `{"success":false,"error":"DDNS模块未初始化"}` → 抛异常 → **未捕获，`isChecking` 只是 finally 复位** |
| 启用开关 | `aliyun_ddns_screen.dart:168` `onChanged: _viewModel.isLocal ? ... : null` | 远程模式下禁用（**这个做对了**） |
| 添加/移除监控域名 | `aliyun_ddns_screen.dart:356` / `:501` `if (_viewModel.isLocal)` | 远程模式下隐藏（**这个做对了**） |
| 清空日志 | `aliyun_ddns_screen.dart:683` `if (_viewModel.isLocal && ...)` | 远程模式下隐藏（**这个做对了**） |

**真正的 bug**：失败被吞。

```dart
// lib/view_models/aliyun_ddns_viewmodel.dart
:150-164  Future<void> refreshStatus() async { try { ... fetchRemoteStatus() ... } catch (_) {} }      // catch 在 :163
:166-175  Future<void> refreshLogs()   async { try { ... fetchRemoteLogs() ... } catch (_) {} }        // catch 在 :174
:177-183  Future<void> refreshWatchDomains() async { try { ... } catch (_) {} }                        // catch 在 :182
```

（三处 `catch (_) {}` 精确行号：163 / 174 / 182，见 `grep -n "} catch (_) {}" lib/view_models/aliyun_ddns_viewmodel.dart`）

而 `checkNow()`（`:134`）虽然在 `try/finally` 里，但**没有 catch**，异常会向上冒到 `onPressed` 里变成一次未捕获的异步异常（Flutter 侧只在控制台刷红，用户看不到）。

**用户视角**：选了远程节点 → 进阿里云页 → 页面显示「节点公网IP：未检测」、「暂无日志」、监控域名空列表 —— **看上去像「这个节点还没配置」，实际是「模块根本没起来」**。点「立即检查」按钮，转一下圈就停了，界面上什么都没有变，也没有任何错误提示。用户会以为 DDNS 没配好，去配置页再折腾一遍。

**建议**：远程分支的 `catch (_) {}` 至少要落到一个用户可见的错误状态（页面 banner 或 snackbar），`checkNow` 也要把异常转成提示。

---

### 2.2 `/power-stats` 电力统计 —— 远程只能「看空图表」，配置区被正确隐藏但读取失败同样静默

**数据来源**：远程分支齐全（`_remoteCall('power_stats_get_status' | '_get_summary' | '_get_aggregated' | '_get_logs')`，`lib/core/services/power_stats_service.dart:352,375,390,406`）。**背后模块没初始化**（§1）。

**写操作远程分支**：

| UI 动作 | 代码 | 远程结果 |
|---|---|---|
| 「手动抓取一次」 | `lib/pages/power_stats/power_stats_screen.dart:204` → `PowerStatsViewModel.fetchOnce()` `:278` → `service.fetchOnce()` `power_stats_service.dart:294` | 走 `_remoteFetchOnce()`（`:449`）→ 节点回「电力统计模块未初始化」→ 抛异常 → `fetchOnce` 的 catch（`:306-310`）把它变成 `lastResult = '抓取失败: ...'` |
| 采集配置整卡（开关/表号/间隔/启动停止轮询/清空日志） | `power_stats_screen.dart:773` `if (!_viewModel.isLocal) return const SizedBox.shrink();` | 远程模式下整卡隐藏（**这个做对了**） |

**bug：读取失败三处静默**（`lib/view_models/power_stats_viewmodel.dart`，`grep -n "} catch (_) {}"` 精确行号）：

```dart
:239  refreshStatus()     { if (!_service.isInitialized) return; try { ... } catch (_) {} }
:247  refreshSummary()    { ... } catch (_) {} }
:266  refreshAggregated() { ... } catch (_) {} }
:274  refreshLogs()       { ... } catch (_) {} }
```

**用户视角**：选了远程节点 → 进电力统计页 → **图表空、汇总卡全 0、「剩余电量 0.000」**，页面不报任何错。点「手动抓取一次」才会弹一条「抓取失败：电力统计模块未初始化」。用户第一反应是「这个节点没有电表数据」，实际上节点模块压根没启动。

★ 注意：抓取按钮那条路径其实**做对了**——`fetchOnce` 把异常转成了 `lastResult`，`_emitFetchEvent()`（`power_stats_screen.dart:1108`）再把它推成一个可见的横幅事件。**这正是其余读取路径该照抄的姿势**。

---

### 2.3 `/ledger/**` 流水账 —— 最大的一块，五类独立缺陷

账本在节点侧有完整 action（`rust/src/node_server/handlers.rs:1580-1783`，约 40 个），而且有 `ensure_ledger_ready` 兜底，**这是唯一「开箱就能在空节点上跑」的模块**（实测 `ledger_list_accounts` 直接返回内置账户）。但正因为「能跑」，它的语义缺陷才更容易骗人。

#### 2.3.1 【确定是 bug】远程模式下「改口令」整条链路断了（节点没有 `ledger_set_rule_password`）

```dart
// lib/core/services/ledger_service.dart:419-425
Future<void> setRulePassword(int ruleId, String password) async {
  await saveRulePassword(ruleId, password);     // 只写本机安全存储
  if (isLocal && password.isNotEmpty) {          // ← 远程模式这里整个跳过
    rust_api.ledgerSetRulePassword(ruleId: ruleId, password: password);
  }
}
```

节点侧没有对应 action，实测：

```
$ curl -s -X POST .../node/call -d '{"action":"ledger_set_rule_password","params":{"rule_id":1,"password":""}}'
{"success":false,"error":"不支持的动作: ledger_set_rule_password"}

$ grep -c "ledger_set_rule_password" rust/src/node_server/handlers.rs
0
```

**用户视角（这条特别阴）**：远程模式下打开「规则编辑」→ 点「清空口令」→ `lib/pages/ledger/components/ledger_rule_editor.dart:270` 调 `vm.updatePassword(rule.id, '')` → 成功写入本机安全存储 + 提示「口令已清除」→ **节点上那个规则的口令还在**（`scheduler::set_secret` 只清了客户端进程内存）。用户以为清掉了，节点照样拿旧口令每小时去收信。

反向也一样：远程模式改新口令 → 客户端存了 → 节点不知道 → 下次自动收信时 `secret_of(rule.id)`（`rust/ledger_module/src/scheduler.rs:190`）读到空串 → 写进 `last_summary` 的是 `"规则名:缺少密码"`，用户得去翻调度状态字符串才能发现。

**为什么这条容易被漏**：`upsertRule` 那条路是**通的**（`ledger_service.dart:395-406` 把 password 随 `rule_json` 一起 POST，节点侧 `rust/src/node_server/handlers.rs:1658` 会调 `ledger_set_rule_password`）。实测：

```
$ ledger_upsert_rule(..., "password":"hunter2")  → {"success":true,"data":{"id":1}}
$ ledger_has_rule_password {rule_id:1}           → {"success":true,"data":{"value":true}}
```

所以**「新建/编辑规则时顺手填口令」能用，「专门改口令/清口令」不能用**。两条路走不同的函数，只有一条补了远程分支。

#### 2.3.2 【确定是 bug】标签 / 记账模板 / 定时规则整块写本机 SharedPreferences，远程模式完全没拦住

`lib/core/services/ledger_stub_store.dart` 是纯本地实现，数据**只在内存里**（`:33-38` 的 `_groups/_tags/_templates/_schedules/_backups/_attachments`），持久化只存了一个开关（`:71` `setBool(_keyEnabled, ...)`）。它**完全不认识 NodeSettingsService**：

```
$ grep -n "NodeSettings\|isRemote\|callNodeAction" lib/core/services/ledger_stub_store.dart
(无输出)
```

调用它的地方也全部没做远程分流：

```dart
// lib/view_models/ledger/ledger_organize_viewmodel.dart:132-178
Future<bool> saveTagGroup(...) { await _tags.upsertTagGroup(group); ... }   // 标签分组
Future<bool> saveTag(...)      { await _tags.upsertTag(...); ... }          // 标签
Future<bool> deleteTag(...)    { await _tags.deleteTag(tag.id); ... }

// lib/view_models/ledger/ledger_templates_viewmodel.dart:143,157,171
await _store.upsertSchedule(schedule);            // 定时规则
await _store.setScheduleEnabled(schedule.id, ...);
await _store.deleteSchedule(schedule.id);

// lib/pages/ledger/components/ledger_tx_editor.dart:300
final att = await LedgerStubStore.instance.addAttachment();   // 附件
```

**用户视角**：远程模式下进「分类标签」页 → 新建分组、加标签 → 提示「分组「工作」已添加」→ **重启 App 就没了**（内存态），节点上更没有；且如果另一台设备连同一个节点，两边看到的标签完全不是同一套。定时规则同理：写进客户端内存，节点上的调度器根本不知道有这条规则。

**这一块的处理现状是「打了水印但没拦」**：`ledger_organize_screen.dart:194` 和 `ledger_templates_screen.dart:193` 有 `LedgerStubMark` 水印写着「演示数据 · 后端未接入」。水印能解释「为什么重启会没」，但**解释不了「为什么远程节点模式下还要往本机写」**——用户在远程模式下期望所有写入都落到节点，这里却是明确的「静默写本机」。

**建议两条路**：
- (a) 短期：远程模式下把标签/模板/定时规则的写入口禁用（与水印一致，不骗人）；
- (b) 长期：补节点 action（`ledger_*_tag` / `ledger_*_template` / `ledger_*_schedule`），并给 `LedgerStubStore` 加远程分流。

#### 2.3.3 【确定是 bug】「到点自动收账单」这条在远程模式下是死门，但 UI 照样给出开关

```rust
// rust/ledger_module/src/scheduler.rs:189-193
let password = secret_of(rule.id);
if password.is_empty() {
    summary.push(format!("{}:缺少密码", rule.name));
    continue;                      // ← 永远不会去收
}
```

结合 2.3.1：远程模式下用户**无法**把口令送进节点常驻内存（只有 `upsert_rule` 能送，且节点重启就丢）。所以：

- 用户在远程模式开着「自动收信」开关 → `ledger_scheduler_start` 在节点上真的启动了（实测 `running:true`）；
- 但每分钟跑一轮，所有规则都因 `secret_of` 为空被跳过，`last_summary` 累积成 `"规则A:缺少密码；规则B:缺少密码"`；
- **`last_summary` 有渲染点，但埋得很深**：`lib/pages/ledger/ledger_settings_screen.dart:179-181` 有「最近一轮：${status.lastSummary}」——所以这条**不是完全无声**。但它是设置页里一行 `caption` 小字，用户得主动进「流水账 → 设置」并往下滚才看得到；流水账首页 / 待确认页看不到任何异常，开关也照旧显示「开」。

实测：

```
$ ledger_scheduler_start → {"success":true,"data":{"ok":true}}
$ ledger_scheduler_status → {"active_rules":0,"enabled":true,"running":true,
                             "last_check_at":"2026-11-19 07:01:53", "last_summary":""}
```

（`active_rules:0` 因为那条测试规则未启用；一旦启用就会变成 1 且 `last_summary` 出现「缺少密码」。）

**用户视角**：远程模式 → 规则开关打开 → 调度器开着 → **一封邮件都收不到，界面上看起来一切正常**。这是「操作成功但实际数据无变化」的标准形态，且比 media 那批更难查——唯一的线索是设置页里一行 caption 小字。

**建议**：远程模式下要么隐藏调度开关（口令链路不通就先别给），要么把 `last_summary` 从设置页的 caption 提到显眼处（例如规则列表页顶部 banner，出现「缺少密码」就提示「远程节点需要重新配置口令」）。

#### 2.3.4 【确定是 bug】账本一批 mutation 对「不存在的 id」假成功（和 task-1 同一族，但这次在 ledger 模块）

节点 handler 用 `ledger_void` / `ledger_scalar` / `ledger_flag` 包一层，而这些底层 Rust 函数**执行 UPDATE/DELETE 后不检查影响行数**：

```rust
// rust/src/node_server/handlers.rs:1620
"ledger_update_transaction" => ledger_void(ledger_module::api::ledger_update_transaction(s_field(&params,"tx_json")), "修改流水"),
// rust/src/node_server/handlers.rs:1666-1668
"ledger_delete_rule" => { ledger_void(ledger_module::api::ledger_delete_rule(i_field(&params,"id")), "删除邮箱规则") }
// rust/src/node_server/handlers.rs:1669
"ledger_set_rule_enabled" => ledger_void(ledger_module::api::ledger_set_rule_enabled(...), "切换邮箱规则开关"),
// rust/src/node_server/handlers.rs:1758
"ledger_ignore_tx" => ledger_void(ledger_module::api::ledger_ignore_tx(i_field(&params,"tx_id")), "忽略流水"),
```

底层实现全是「执行完就 Ok(())」：

```rust
// rust/ledger_module/src/storage.rs:1320-1328
pub fn set_email_rule_enabled(id: i64, enabled: bool) -> Result<()> {
    with_db(|conn| { conn.execute("UPDATE email_rules SET enabled = ?1 WHERE id = ?2", ...)?; Ok(()) })
}
// rust/ledger_module/src/storage.rs:1330-1338
pub fn delete_email_rule(id: i64) -> Result<()> {
    with_db(|conn| { conn.execute("DELETE FROM email_rules WHERE id = ?1", ...)?; ... Ok(()) })
}
// rust/ledger_module/src/storage.rs:1469-1477
pub fn set_tx_status(tx_id: i64, status: &str) -> Result<()> {
    with_db(|conn| { conn.execute("UPDATE transactions SET status=... WHERE id = ?3", ...)?; Ok(()) })
}
// rust/ledger_module/src/storage.rs:893  update_transaction 同样是 UPDATE ... WHERE id=? 后直接 Ok
```

实测（对不存在的 id）：

```
ledger_set_rule_enabled   {id:999999} → {"success":true,"data":{"ok":true}}
ledger_update_transaction {id:999999} → {"success":true,"data":{"ok":true}}
ledger_delete_rule        {id:999999} → {"success":true,"data":{"ok":true}}
ledger_ignore_tx          {tx_id:999999} → {"success":true,"data":{"ok":true}}
ledger_delete_account     {id:999999} → {"success":true,"data":{"text":"账户已删除"}}
ledger_purge_email        {email_id:999999} → {"success":true,"data":{"count":0}}
ledger_ignore_email       {email_id:999999} → {"success":true,"data":{"count":0}}
ledger_confirm_all        {email_id:999999} → {"success":true,"data":{"count":0}}
ledger_forget_merchant    {merchant_key:"zzz"} → {"success":true,"data":{"ok":true}}
```

对照组（**说明正确姿势已存在**）：

```
ledger_confirm_tx   {tx_id:999999} → {"success":false,"error":"确认入账失败: 流水不存在"}   ✓
ledger_delete_category {id:999999} → {"success":false,"error":"删除类别失败: 类别不存在"}  ✓
```

★ `ledger_delete_account` 那条更值得注意：`storage.rs:473-488` 的语义是「有流水就改成停用并回一段中文，没流水就删掉并回『账户已删除』」——**对不存在的 id 也回「账户已删除」**。而客户端 `ledger_accounts_viewmodel.dart:89` 直接把这个字符串当成功提示显示给用户。

**用户视角**：远程模式下删一笔已经不存在（或另一台设备刚删掉）的流水 → 界面回「已删除」→ 刷新后那笔还在（因为压根没删到东西）。与 task-4 的「幽灵体积」是同一类错误的另一个样子：**API 说成功，数据没动**。

**建议**：这些 mutation 的底层 Rust 函数统一改成比较 `execute()` 返回的行数，0 行返回 `Err("...不存在: <id>")`；`ledger_delete_account` 还要区分「id 不存在」和「有流水改停用」。

#### 2.3.5 【疑似，需确认】CSV 导入在远程模式下逐笔 POST，量大时会长时间挂在半路

`lib/view_models/ledger/ledger_data_viewmodel.dart:275-300` `importAll()` 逐行 `await _service.addTransaction(row)`。远程模式下每一行是一次 HTTP POST（`ledger_service.dart:732` `_nodeCall`，`receiveTimeout: 60s`）。几十行没问题，几百行就是几百次串行往返。

不是「写错地方」，而是「远程模式下这条路的时间量级和桌面端完全不同」。建议至少加进度提示；若确认会超时，考虑批量 action。

---

### 2.4 `/sentry-log` 日志中心 —— 远程模式可用，但「清空项目事件」是主动骗人，且错误全静默

**数据来源**：远程 HTTP 路由齐全（`rust/src/node_server/mod.rs:761-880`：logs/stats/projects/events/delete_batch/rename/export）。**但背后存储没初始化**（§1），空节点上全部 500。

**写操作远程分流**（`lib/view_models/sentry_log/sentry_log_viewmodel.dart`）：

| UI 动作 | 远程分流 | 结果 |
|---|---|---|
| 删除单条事件 | `:203` `_sentrySettings!.deleteRemoteEvent(eventId)` → `DELETE /sentry/events/{id}` | ✓ 路由存在 |
| 批量删除 | `:224` `deleteRemoteEvents(ids)` → `POST /sentry/events/delete_batch` | ✓ 路由存在 |
| 导出 | `:248` `exportRemoteLogs(...)` → `POST /sentry/export` | ✓ 路由存在 |
| **清空项目事件** | `:276-287` **`_logger.info('远程节点不支持清空项目事件')`** | ✗ **什么都不做，静默返回** |

#### bug 1：「清空事件」按钮在远程模式下是个纯假按钮

```dart
// lib/view_models/sentry_log/sentry_log_viewmodel.dart:276-287
Future<void> clearProjectEvents(String projectId) async {
  try {
    if (isLocal) {
      await sentryLogClearProjectEvents(projectId: projectId);
    } else {
      _logger.info('远程节点不支持清空项目事件');   // ← 只写日志
    }
    await loadInitialData();                        // ← 还刷新一遍，看起来"生效了"
  } catch (e) { _logger.error('清空项目事件失败: $e'); }
}
```

而节点侧其实**有这个路由**：`rust/src/node_server/mod.rs:870` 的 `("DELETE", p) if p.starts_with("/sentry/projects/") && p.contains("/events")`。也就是说这不是「节点做不到」，而是「客户端不知道节点能做」。

UI 上这个按钮**远程模式下照常显示**：`lib/pages/sentry_log/components/sentry_log_stats_panel.dart:476` 的项目卡片上有 `tooltip: '清空事件'` 的 IconButton，点开确认弹窗（`:534` 「确定要清空项目 "xxx" 的所有事件吗？此操作不可撤销。」），确认后 `:543` 调 `clearProjectEvents`。

**用户视角**：远程模式 → 日志中心 → 项目卡片点「清空事件」→ 弹「此操作不可撤销」→ 确认 → **事件一条没少**（`loadInitialData()` 重新拉回来还是那些）。用户以为删了，实际上什么都没发生。这是本报告里**最像「骗人成功」的一条**：有确认弹窗、有不可撤销警告、行为却是空操作。

#### bug 2：`updateProjectName` 同样是「只写日志」的空分支

```dart
// lib/view_models/sentry_log/sentry_log_viewmodel.dart:263-274
if (isLocal) { await sentryLogUpdateProjectName(...); }
else { _logger.info('远程节点不支持更新项目名称'); }
```

（注：当前 grep 全仓，`updateProjectName` **没有任何 UI 调用点**，只有定义。所以这条目前是死代码，风险等级低；但如果以后加「重命名项目」的入口，它会立刻变成 bug 2 的形态。）节点侧也有对应路由（`rust/src/node_server/mod.rs:834` `POST /sentry/projects/rename`）。

#### bug 3：读取失败三处静默，用户看到的是「等待日志接入」

```dart
// lib/view_models/sentry_log/sentry_log_viewmodel.dart:104-107, 120-122, 134-136
} catch (e) {
  errorMessage.value = '加载事件失败: $e';
  _logger.error('加载Sentry事件失败: $e');
}
```

`errorMessage` 被赋值了，但 **`lib/pages/sentry_log/` 下没有任何地方渲染 `errorMessage`**：

```
$ grep -rn "errorMessage" lib/pages/sentry_log/
(无输出)
```

所以节点回「Sentry日志存储未初始化」时，用户看到的是空列表 + 空状态文案「等待日志接入」（`sentry_log_list.dart:136`）。

**用户视角**：远程模式 → 日志中心 → 一片空白，写着「等待日志接入」→ 用户以为是「还没接 SDK 上报」，实际上是「节点存储没起来」。两者修复动作完全不同（前者要改 SDK 配置，后者要修节点），文案把人引向错的那边。

---

### 2.5 `/settings` 设置页 —— 有一处「远程模式下会静默切回本机」的坑

设置页本身在远程模式下加了一条提示条（`lib/pages/settings/settings_page.dart:90-97` `_RemoteSettingsNotice`：「当前节点：xxx，设置与数据均作用于该节点」），并且正确隐藏了 Manga / 游戏 / Sentry / Mock 四组标签（`:183-196`）。**这部分做得好**。

#### bug：阿里云设置 tab 在远程模式下仍然显示，而它的「数据节点」选择器会把全局节点顶掉

`_ToolsSettingsWrapper` 的标签清单：

```dart
// lib/pages/settings/settings_page.dart:234-243
final tabLabels = <String>[
  if (!isMobile && !remoteMode) '解压设置',   // ← 解压被正确隐藏
  if (!isMobile) '阿里云',                   // ← 阿里云没有 !remoteMode 条件
];
```

阿里云 tab 里有一个 `NodeInlineSelector`（`lib/pages/settings/components/aliyun_settings_tab.dart:162`），点它会调：

```dart
// aliyun_settings_tab.dart:167-170
onNodeSelected: (nodeId) async {
  await service.setSelectedNodeId(nodeId);
  _showSnack(nodeId.isEmpty ? '已切换到本机' : '已切换到节点');
},
```

而 `AliyunDdnsService.setSelectedNodeId` **没有** `isRemoteMode` 保护：

```dart
// lib/core/services/aliyun_ddns_service.dart:191-194
Future<void> setSelectedNodeId(String nodeId) async {
  selectedNodeId.value = nodeId;
  await _prefs?.setString(_keySelectedNodeId, nodeId);   // ← 无条件写盘
}
```

对比电力统计 / 流水账 / Sentry 三家**都做了保护**：

```dart
// lib/core/services/power_stats_service.dart:195-197
if (_nodeSettingsService?.isRemoteMode != true) {
  await _prefs?.setString(_keySelectedNodeId, selectedNodeId.value);
}
// lib/core/services/ledger_service.dart:76-78   同样
// lib/core/services/sentry_settings_service.dart:73-76  同样
```

**后果**：远程模式下在这里选「本机」→ `selectedNodeId` 被清空 → `AliyunDdnsService.isLocal` 变 true → 页面立刻开始读**本机**的 DDNS 状态与日志。而全局节点仍然是远程（`NodeSettingsService.activeNodeId` 没变），设置页顶部还挂着「设置与数据均作用于该节点」的提示条。**两套状态互相打架**。

**用户视角**：远程模式 → 设置 → 工具设置 → 阿里云 → 看到「数据节点」选择器（本该在远程模式下不出现，因为全局已经定了）→ 选「本机」→ 提示「已切换到本机」→ 回到阿里云页面，**数据变成本机的了**，但侧栏节点还显示着远程节点名。

**顺带**：阿里云 tab 里的 AccessKey 输入框（`aliyun_settings_tab.dart:230-233, 280-283`）和检查间隔（`:350-353`）在远程模式下**照常可写**。它们最终都走 `service.updateConfig()`：

```dart
// lib/core/services/aliyun_ddns_service.dart:231-239
Future<void> updateConfig() async {
  try {
    rust_api.aliyunDdnsUpdateConfig(configJson: _buildConfigJson());  // ← 纯本机 FFI
    await _savePrefs();
```

`_buildConfigJson()`（`:208`）用 `accessKeyId.value` 等字段 —— 而远程模式下这些字段是从节点拉来的（`fetchRemoteStatus` 只回 status 不回 AccessKey，所以其实是本机残留值）。**改写 AccessKey 会覆盖本机配置，同时完全不影响节点**。加上 §1（节点阿里云模块没初始化），用户在远程模式下改 AccessKey，两边都不会生效。

---

### 2.6 `/device-wake` 设备唤醒 —— 设计上是「本机功能 + 节点中继」，远程模式下入口该不该留值得商榷

**数据来源**：`wakeDevices` 列表存在客户端 SharedPreferences（`lib/core/services/node/node_settings_service.dart:2593-2596` `_save()` 把 `wakeDevices` 一起 jsonEncode 存盘）。**它是纯客户端配置，不是服务端数据**——这一点决定了它不该被「远程模式必须走节点」这条规则约束。

**写操作**：

| UI 动作 | 代码 | 行为 |
|---|---|---|
| 添加/编辑/删除设备 | `lib/pages/device_wake/device_wake_screen.dart:59,69,102` → `_service.addWakeDevice/updateWakeDevice/removeWakeDevice` | 写客户端 prefs（**合理**，这是设备清单） |
| 「唤醒」按钮 | `device_wake_screen.dart:37-44` → `_service.wakeDevice(device.id)` | 按 `device.mode` 分流：`direct` → 本机 UDP 广播（`node_settings_service.dart:716`）；`relay`/`auto` → `callNodeAction(action:'wake_host')`（`:683`） |

节点侧 `wake_host` 实测可用：

```
$ wake_host {mac:"AA:BB:CC:DD:EE:FF", target:"", port:9, count:1}
{"success":true,"data":{"sent":1,"target":"255.255.255.255"}}
```

**结论：无数据错位 bug**，但有两处值得 Lead 决策：

1. **`kRemoteUnsupportedPathPrefixes` 里没有 `/device-wake`** —— 全局远程模式下这个入口仍然可见（`lib/core/routes/app_sidebars.dart:46-56` 的名单里没有它）。用户点进去看到的是**本机客户端保存的设备清单**，这在远程模式下读的不是节点数据。虽然从功能语义讲「唤醒设备清单本来就该跟着人走」，但与 AGENTS.md「远程模式不静默回退本机」的措辞有张力。
2. **`auto` 模式的判断依赖 `isNodeLanReachable(relay.id)`**（`node_settings_service.dart:700-709`：探 `lanApiBaseUrl`）。远程节点的 lan 地址在客户端可能压根不通（用户在外网），此时 `sameLan=false` → 只走中继。这是**正确降级**，不是 bug，但意味着远程模式下唤醒必然只走中继那条腿。

**建议**：不改功能，只在报告里登记为「设计如此，需 Lead 确认是否登记进 `kRemoteUnsupportedPathPrefixes`（我倾向**不登记**：设备清单是本机偏好，中继走节点，行为已经自洽）」。

---

## 3. 【确定是 bug（要修）】路由层：清单内几个路由**根本没有 UI 入口**，但会话里假定「用户能点进去」

Lead 给的范围内这几个路由，我逐个追了「用户怎么点到它」：

### 3.1 `/ncm-decrypt` —— 唯一入口在 `/tools` 卡片里，而 `/tools` 远程模式已隐藏 → **实际不可达**

```dart
// lib/pages/tools/components/ncm_decrypt_card.dart:33
onTap: () => context.go('/ncm-decrypt'),
```

而 `/tools` 在远程模式名单里：

```dart
// lib/core/routes/app_sidebars.dart:46-56
const Set<String> kRemoteUnsupportedPathPrefixes = {
  '/capture', '/tools', '/lan-transfer', '/manga', '/music', '/game',
  '/motion-lab', '/interaction-lab', '/surface-lab',
};
```

`/tools` 前缀匹配 `/tools` 本身。侧栏项因此被过滤（`app_sidebars.dart:107`），Dashboard 的功能卡片也把它过滤了（`dashboard_screen.dart:380-387` `remoteUnsupported: true`）。**没有第三个入口**（grep 全仓只有 `ncm_decrypt_card.dart:33` 一处 `context.go('/ncm-decrypt')`）。

**结论**：`/ncm-decrypt` 在远程模式下**用户点不到**。它自身确实是纯本机 FFI（`lib/core/services/ncm_decrypt_service.dart` 全文调 `rust_api.ncmScanFilesJson / ncmStartDecrypt`，无远程分支），所以「该不该隐藏」的答案是「本来就该隐藏 —— 而且已经通过父路由隐藏了」。

★ 但**仍然建议把它单独加进 `kRemoteUnsupportedPathPrefixes`**：现在它是靠「唯一入口在 /tools 下面」这个**巧合**安全的。哪天有人从设置页或 Dashboard 加一个直达链接，就立刻变成「远程模式下操作本机文件解密」的漏洞。隐式保护应当显式化。

### 3.2 `/image-tools`、`/image-toolbox` —— 都是占位页，**零入口**

```dart
// lib/core/routes/routes/tools_routes.dart:11-13
Page<void> buildPage(BuildContext context, GoRouterState state) {
  return AppRoutes.buildPage(context, state, AppRoutes.buildPlaceholder('图片工具'));
}
```

`grep -rn "image-tools\|image-toolbox" --include=*.dart lib/` 在这些文件之外**没有任何 `go(...)` / `context.go` 调用**。它们不在 `knownRoutes`（`app_routes.dart:189-230`）之外的地方被引用，也不在 `shellRoutes`（`app_sidebars.dart:71-103`）里（`ImageToolsRoute` 没有 sidebarIcon → `showInSidebar` false）。

**结论**：无数据、无写入、无入口。**无问题**（占位页本身不该在报告里占篇幅，登记为「路由存在但不可达」）。

### 3.3 `/module-management` —— 有真实写操作，**零入口**

`ModuleManagementScreen`（`lib/pages/module_management_screen.dart`）是真实的：创建 `ModuleManager`（`:68`）、`moduleInstall`（`:106`）、安装目录落在 `getApplicationSupportDirectory()/modules`（`:61-62`）。这是**纯本机动态库管理**，远程节点完全无法实现（节点进程里没有这个目录语义）。

但它**没有任何导航入口**：

```
$ grep -rn "ModuleManagementRoute\|'/module-management'" --include=*.dart lib/ | grep -v app_routes.g.dart
lib/core/routes/app_sidebars.dart:15:  '/module-management',        ← 只是「默认隐藏侧栏」名单
lib/core/routes/app_routes.dart:142:  TypedGoRoute<ModuleManagementRoute>(path: '/module-management'),
lib/core/routes/routes/business_routes.dart:5:  @TypedGoRoute...
```

`ModuleManagementRoute extends GoRouteData`（不是 `AppRouteData`），**没有 `sidebarIcon`**，也不在 `shellRoutes` 里。Dashboard 的「功能模块」卡片里也没有它。

**结论**：无问题（不可达）。但如果将来加回入口，它**必须**登记进 `kRemoteUnsupportedPathPrefixes` —— 它比 `/ncm-decrypt` 更该隐藏（模块管理直接操作本机 dylib）。

### 3.4 `/sentry-log` —— **入口在 `/tools` 下，远程模式已隐藏**，但审计范围内它其实是可达的？

这里需要 Lead 确认一个事实：`/sentry-log` 的侧栏入口是**独立**的——

```dart
// lib/core/routes/routes/tools_routes.dart:42-69
@TypedGoRoute<SentryLogRoute>(path: '/sentry-log')
class SentryLogRoute extends AppRouteData with $SentryLogRoute {
  @override String get title => '日志';
  @override StrokeIcon get sidebarIcon => StrokeIcons.assetMenuLog;   // ← 有图标 = 进侧栏
  @override String get sidebarGroupId => 'tools';
  @override bool get desktopOnly => true;
```

它在 `shellRoutes`（`app_sidebars.dart:76` `const SentryLogRoute()`）里，`kRemoteUnsupportedPathPrefixes` **没有** `/sentry-log`，所以**远程模式下侧栏可见、用户真能点进去**。`/tools` 下面那张 `SentryLogCard`（`lib/pages/tools/components/sentry_log_card.dart:33` `context.go('/sentry-log')`）是第二入口，但第一入口就在侧栏。

所以 §2.4 的结论成立：**远程模式下用户能进日志中心，能点「清空事件」（假成功）**。

---

## 4. 【疑似（需确认）】三条

### 4.1 远程模式下 Dashboard「节点请求」指标统计的是**客户端→节点**的请求数，不是节点的

```dart
// lib/pages/dashboard_screen.dart:303-313
if (_metricsService.isLocalServerRunning) {
  metrics.add(_MetricData(title: '节点请求', value: _metricsService.nodeRequestCount.toString(), ...));
}
```

`nodeRequestCount` 来自 `NodeSettingsService.nodeRequestCount`（`lib/core/services/node/node_settings_service.dart`），是**客户端本地计数器**（每次 `callNodeAction` 自增）。在远程模式下这张卡片显示的其实是「本客户端向节点发了多少次请求」，而卡片标题和上下文（顶部写着节点名、CPU/内存都是节点的）会让人以为这是**节点的**请求数。

`get_system_metrics` 这个 action 本身**没有** `node_request_count` 字段（`rust/src/node_server/handlers.rs:190-202` 只有 cpu/mem/rx/tx）。所以要么补进 action，要么在远程模式下给卡片换个标题（如「本端请求节点」）。判定：**疑似**，因为「节点请求」这个词本身有歧义，未必是 bug。

### 4.2 远程模式下 `/settings` 的「资源库」设置写的是客户端本地 prefs

`MediaSettingsTab`（`lib/pages/settings/components/media_settings_tab.dart`）全部写 `MediaPrefsService`（本机 SharedPreferences）：隐私模式、假封面、并发、封面宽度……这在远程模式下**语义上是正确的**（这些是「这台客户端怎么显示远程数据」的偏好，不该存到节点）。

但设置页顶部横幅写的是「设置与数据均作用于该节点」（`settings_page.dart:125`），**这句话对「资源库」标签是错的**。判定：**疑似**（提示文案与行为不一致，不是数据错位）。

### 4.3 `kRemoteUnsupportedPathPrefixes` 与「实际可达性」已经脱钩

现在名单里 9 个前缀（`app_sidebars.dart:46-56`），但真实情况是：

| 前缀 | 是否有 UI 入口 | 是否真有远程实现 |
|---|---|---|
| `/capture` | 侧栏 + Dashboard 卡片 | 无（纯本机动态库）✓ 该隐藏 |
| `/tools` | 侧栏 + Dashboard 卡片 | 无 ✓ 该隐藏 |
| `/lan-transfer` | 侧栏 + Dashboard 卡片 | 无 ✓ 该隐藏 |
| `/manga` | 侧栏 | 无 ✓ 该隐藏 |
| `/music` | 侧栏 | **节点有 12 个 music_* action**（`rust/src/node_server/handlers.rs:1300-1572`）但客户端没接 → 隐藏是对的，但**不是「节点做不到」** |
| `/game` | 侧栏 | 无 ✓ |
| `/motion-lab` 等三个 | 侧栏 | 无 ✓ |

★ `/music` 那条值得 Lead 注意：节点侧 `music_list_playlists` / `music_create_playlist` / `music_import_folder` 等 action **已经存在**（实测空节点上返回的是「表不存在」而不是「不支持的动作」，说明代码路径通），但客户端 `music_player` 模块没有任何 `NodeSettingsService` 调用（grep 全仓 `callNodeAction` 的 5 个调用点里没有 music）。**所以音乐播放器是「节点侧已实现、客户端没接」**，和 novel 文件夹那个任务正好相反。判定：**疑似**（不是 bug，是未完成的功能对接，但隐藏名单里它的理由（"没有节点侧实现"）已经不准确了）。

---

## 5. 【无问题】登记为已核实

| 模块 | 结论 | 依据 |
|---|---|---|
| `/dashboard` 指标区 | 远程分支正确 | `system_metrics_service.dart:105-113` 走 `get_system_metrics`；实测返回节点真实 CPU/内存。列表切换时 `_resetSeries()`（`:96-103`）清曲线，不混数据 |
| `/dashboard` 功能模块卡片 | 远程模式过滤正确 | `dashboard_screen.dart:404-407` `isRemoteMode` 时滤掉 `remoteUnsupported` 三项 |
| `/settings` 的 Manga/游戏/Sentry/Mock 标签 | 正确隐藏 | `settings_page.dart:183-196` |
| `/settings` 的「解压设置」 | 正确隐藏 | `settings_page.dart:237` `if (!isMobile && !remoteMode)` |
| `/aliyun` 的开关/域名增删/清日志 | 正确禁用或隐藏 | `aliyun_ddns_screen.dart:168, 356, 501, 683` |
| `/power-stats` 的采集配置整卡 | 正确隐藏 | `power_stats_screen.dart:773` |
| `/sentry-log` 单条删除 / 批量删除 / 导出 | 远程分支正确，节点路由存在 | `sentry_log_viewmodel.dart:203, 224, 248` + `rust/src/node_server/mod.rs:804-880` |
| `/device-wake` 唤醒 | 三分支设计自洽 | `node_settings_service.dart:640-698`；`wake_host` 实测可用 |
| `/ledger` 的规则 upsert（带口令） | 远程分支正确 | `ledger_service.dart:395-406` + 实测 `id:1` / `has_rule_password:true` |
| `/ledger` 的流水增删改查 / 统计 / 待确认 | 远程走节点，语义正确 | `ledger_service.dart:646-742` 统一 `_list/_map/_text/_id/_bool/_run` 收口，只有 `_useLocal` 才调 FFI |
| 路由权限重定向 | 无远程相关缺陷 | `app_routes.dart:315-341` 只做 `RoleManager.canAccess`，与节点无关 |

---

## 6. 【范围外但同类】顺手发现的

### 6.1 音乐播放器：节点侧 action 已实现，客户端完全没接

见 §4.3 表格。`rust/src/node_server/handlers.rs:1300-1572` 有 12 个 `music_*` action，`node_settings_service.dart` 里一个都没有。这不是「远程模式下写出错」，而是「远程模式根本用不了音乐」——被隐藏名单挡住了，所以用户看不到症状。

### 6.2 远程书的阅读进度永远存不住（节点侧没有 progress 写 action）

这个是范围外（novel 归 task-3），但**属于同一种「盯一个模块做契约测试测不出来」的形态**，Lead 应该知道：

- 书库里**远程书**点开走 `RemoteNovelReaderDialog` / `RemoteNovelReaderPage`（`library_book_card.dart:53-56` `isRemoteNovel` 分流，**这个做对了**）；
- 但这条远程阅读路径**从头到尾没有保存进度**：`grep -c "progress" lib/pages/collection/library/components/remote_novel_reader_dialog.dart` → **0**；
- 另一条走 `/novel-reader` 的路（`novel_routes.dart:17-30` → `NovelReaderPage`）在远程模式下**用户到不了**：`NovelLibraryViewModel.loadNovels()` 在 `isRemoteMode` 时直接 `novels.clear()` 并 return（`lib/view_models/novel_library_viewmodel.dart:966-971`），书库里没有本机书可点，`library_book_card.dart:57` 那条 `NovelReaderRoute` 也就没有入口。而它的 ViewModel 是全程本机 FFI 的：

```dart
// lib/view_models/novel_reader_viewmodel.dart:195
final content = await getNovelContent(filePath: novel.filePath);   // 本机 FFI
// :299
updateReadingProgress(novelId: novel.id, progress: progress);       // 本机 FFI
```

- 节点侧**没有任何 progress 写 action**：`grep -c "update_reading_progress\|set_novel_progress\|update_novel_progress" rust/src/node_server/handlers.rs` → **0**。

而且即使有人把合成 id `remote:<nodeId>:<rawId>`（`lib/view_models/novel_library_viewmodel.dart:756`）灌进本机 `updateReadingProgress`，本机库里也没有这本书 → UPDATE 命中 0 行 → **静默无效**。下次从节点拉列表，`progress` 字段仍是节点上的旧值（`handlers.rs:780` `"progress": n.progress`）。

**用户视角**：远程书读到第 20 章 → 关掉 → 再打开还是第 1 章，且没有任何提示。这条要修必须先在节点侧补一个 progress 写 action（`grep -c "..." rust/src/node_server/handlers.rs` → **0**），再让 `RemoteNovelReaderDialog` 在章节切换/关闭时调它。

### 6.3 `LedgerStubStore` 的内存态 + 有 prefs 却不存，是双重隐患

`_prefs` 只在 `_reseed()` 里读一个开关（`:61-62`），所有业务数据（标签/模板/定时/附件/备份）**从来不入盘**。注释（`:16-17`）说「方法名与签名按未来的 FFI 契约写……下一轮把方法体换成 `rust_api.ledgerXxx()` 即可」。

但当前的实现意味着：**本机模式下用户加的标签、存的模板、定的定时规则，重启 App 全部丢失**，且**没有任何提示**（水印只说「演示数据 · 后端未接入」，没说「重启就没」）。这不是远程模式的问题，但和本报告 §2.3.2 是同一处代码，Lead 修那块时应当一起决定要不要落盘。

---

## 7. 给 Lead 的开单建议（按优先级）

| # | 任务 | 写入范围 | 验收方式 |
|---|---|---|---|
| A | **节点侧补全局模块初始化**：`slime_node` 启动时（或惰性兜底）init aliyun / power_stats / sentry_log | `rust/src/bin/slime_node.rs` 或 `rust/src/node_server/handlers.rs`（仿 `ensure_ledger_ready`） | **全新 `--data-dir`** 起的节点上，`/aliyun/status`、`power_stats_get_status`、`/sentry/stats` 全部 `success:true` |
| B | **账本 mutation 收口**：`delete_email_rule` / `set_email_rule_enabled` / `update_transaction` / `set_tx_status` / `delete_account` / `forget_merchant` 比较影响行数，0 行返回带 id 的 Err | `rust/ledger_module/src/storage.rs`（+ `api.rs` 转发） | 对不存在 id 全部 `success:false`；`delete_account` 区分「不存在」与「有流水改停用」 |
| C | **补 `ledger_set_rule_password` action** + 客户端 `setRulePassword` 加远程分支 | `rust/src/node_server/handlers.rs` + `lib/core/services/ledger_service.dart` | 远程改/清口令后，`ledger_has_rule_password` 反映正确；调度器 `last_summary` 不再出现「缺少密码」 |
| D | **远程模式下禁用账本标签/模板/定时规则的写入口**（或补 action，看 Lead 选择方案） | `lib/view_models/ledger/ledger_organize_viewmodel.dart`、`ledger_templates_viewmodel.dart`、`lib/pages/ledger/components/ledger_tx_editor.dart` | 远程模式下点「添加分组/新建规则」要么报「该功能暂不支持远程节点」，要么真写到节点 |
| E | **修 `clearProjectEvents` 远程分支**：接已有的 `DELETE /sentry/projects/{id}/events` | `lib/view_models/sentry_log/sentry_log_viewmodel.dart` + `lib/core/services/sentry_settings_service.dart` | 远程清空后 `loadInitialData()` 拉回 0 条 |
| F | **把静默 catch 变成用户可见错误**：aliyun 三处、power 四处、sentry 三处；并渲染 `SentryLogViewModel.errorMessage`（现在完全没人读）、把账本 `last_summary` 提到显眼处 | `lib/view_models/aliyun_ddns_viewmodel.dart`、`power_stats_viewmodel.dart`、`sentry_log/sentry_log_viewmodel.dart`、`lib/pages/sentry_log/`、`lib/pages/ledger/` | 节点回错误时页面上看得到原因，而不是空列表/「等待日志接入」 |
| G | **`AliyunDdnsService.setSelectedNodeId` 加 `isRemoteMode` 保护**，与另三家对齐；远程模式下隐藏设置页的阿里云节点选择器 | `lib/core/services/aliyun_ddns_service.dart`、`lib/pages/settings/components/aliyun_settings_tab.dart` | 远程模式在设置页选「本机」不会真的切走 |
| H | **`kRemoteUnsupportedPathPrefixes` 补 `/ncm-decrypt`、`/module-management`**（显式化现有隐式保护） | `lib/core/routes/app_sidebars.dart` | 远程模式下即使有人加了直达链接也进不去 |
| I | （低）远程模式 Dashboard「节点请求」措辞/口径 | `lib/pages/dashboard_screen.dart` | 卡片标题与数据来源一致 |

---

## 8. 方法反思（为什么上一轮漏了这么多）

上一轮的做法是在**同一台机器、同一个热进程**里，对 media/novel 传不存在的 id，看 `success` 是否为 false。这个方法的盲区正是本次最大的发现：

1. **它只测「参数错误」，不测「环境错误」**。§1 那四个模块是「进程里没有这个模块」，不是「参数不对」——怎么传 id 都测不出来。
2. **它依赖一个已经初始化过的进程**。Lead 的 17901 装置是长期跑的，模块单例全热；换成 `--data-dir` 全新的节点，症状立刻全暴露。
3. **它只看 API 返回值，不看用户在界面上看到什么**。§2.4 的「清空事件」API 层面根本没有请求发出去（客户端只写日志），任何 API 测试都覆盖不到；§2.3.1 的「改口令」是客户端少一个 `if`，API 层连调用都没有。
4. **它只测 media/novel**。§1、§2.3、§2.4 分别落在 aliyun/power/ledger/sentry 四个模块上，媒体验收永远碰不到。

**下一次该怎么做**：至少两路并发——(a) 每模块起**全新空数据目录**的节点，跑一遍该模块的全部读写 action（环境正确性）；(b) 每模块从 UI 入口 walk 到 service，逐个写操作问「远程模式走哪条分支，走不到会怎样」（分支完整性）。这次报告本身就是 (b) 的产物。
