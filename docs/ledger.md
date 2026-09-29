# 流水账模块（Ledger）

## 模块概述

流水账是日常记账 + 银行账单自动入账的模块，两条录入路径共用一份 SQLite 账本：

- **手动记账**：流水页加一笔，或批量补录
- **邮件自动入账**：按规则每天收取账单邮件（招商银行信用卡每日账单为内置模板），解析 HTML 正文成多笔流水，进**待确认队列**，用户逐笔确认后才计入统计；规则勾了 `auto_apply` 则直接入账
- 收件协议 **IMAP / POP3** 已实现，**SMTP** 只用于连接自检（明确拒绝用它收信），**Exchange(EAS) / CardDAV** 保留配置入口但诚实报"尚未实现"
- 统计：按日/按月趋势、按类别、按商户 TopN、区间收支汇总，全部是自定义 `CustomPainter`，不引图表库

---

## 目录结构

```
lib/
  pages/ledger/
    ledger_screen.dart              - 首页（月度概览 + 日趋势 + 最近流水）
    ledger_records_screen.dart      - 流水明细（筛选 + 分页 + 编辑）
    ledger_stats_screen.dart        - 统计（类别环图 / 商户榜 / 月度趋势）
    ledger_pending_screen.dart      - 待确认账单（邮件溯源 + 逐笔确认）
    ledger_settings_screen.dart     - 账单邮箱（规则、模板预览、连接自检、抓取日志）
    ledger_accounts_screen.dart     - 账户与类别
    components/                     - 共享组件（tab/月份条/图表/各类编辑器）
    models/ledger_models.dart       - Dart 侧模型 + 月份/金额 helper
  core/services/ledger_service.dart - GetIt 单例：FFI 包装 + 口令安全存储 + 节点中转
  view_models/ledger/               - 6 个页面 VM
  core/routes/routes/ledger_routes.dart - 6 条 typed route（part of app_routes.dart）
  src/rust/api/ledger.dart          - FRB 生成（勿改）

rust/
  email_module/                     - 邮件协议层（imap/pop3/smtp + MIME 解码 + TLS 策略）
  ledger_module/                    - 账本（SQLite 存储 + 模板解析 + 调度器 + FFI 面）
```

`ledger_module` 只依赖 `email_module`（协议栈收信）+ `slime_logger`，账本用的是自带的 `rusqlite(bundled)`，与 `db_module` 的 redb 无关；`email_module` 无内部依赖。两者都是静态链接，走 `rust/src/api/ledger.rs` 转发给 FRB。

---

## 页面与路由

| 路由 | 页面 | 侧栏 |
|------|------|------|
| `/ledger` | `LedgerScreen` | 顶层唯一一格 |
| `/ledger/records` | `LedgerRecordsScreen` | `sidebarParent=/ledger` |
| `/ledger/stats` | `LedgerStatsScreen` | 同上 |
| `/ledger/pending` | `LedgerPendingScreen` | 同上 |
| `/ledger/settings` | `LedgerSettingsScreen` | 同上 |
| `/ledger/accounts` | `LedgerAccountsScreen` | 同上 |

侧栏只露"流水账"一格，五个子页挂在它下面：它们之间靠页内的胶囊 tab（`LedgerTabs`）互跳，平铺六格会把一个账本读成六个功能。

权限统一 `Permission.accessLedger`，分组 `sidebarGroupId: 'ledger'`（`sort: 44`）。

---

## 表结构（`<app_support>/ledger/ledger.db`，WAL）

| 表 | 作用 | 关键约束 |
|------|------|----------|
| `accounts` | 账户：`credit_card / debit_card / cash / deposit / other`，`last4` 用于卡片尾号匹配 | |
| `categories` | 类别，`direction` = `expense / income / transfer`，`icon` 是图标标识由 Dart 映射到 `StrokeIcons` | `name` UNIQUE；首次建库播种 22 个内置类别 + 一个"现金"账户，升级按名 `INSERT OR IGNORE` 补插 |
| `transactions` | 流水。`amount` **恒为正数**，正负只看 `direction`；`bill_date` 冗余存 `YYYY-MM-DD` 并建索引 | 见下方去重 |
| `email_rules` | 收信规则（协议/主机/用户名/发件人与标题匹配/模板/轮询间隔/每日时点/默认账户/`auto_apply`/`accept_invalid_certs`） | **口令不落这张表** |
| `email_rule_secrets` | 只存 `secret_ref`（`ledger_rule_<id>`），指向真实密钥位置 | |
| `emails` | 已收取邮件的存档 + 溯源信息（笔数、可用额度、积分、告警） | UNIQUE `(rule_id, message_uid)` |
| `fetch_logs` | 每次抓取的耗时/新邮件/新流水/跳过笔数/详情 | |
| `merchant_memory` | 商户 → 类别的记账习惯，确认一次后同类商户自动归类 | |

### 去重是三层

1. **硬幂等**：`transactions` 上 `CREATE UNIQUE INDEX ... ON (rule_id, email_uid, dedup_key) WHERE source = 'email'`。同一封邮件重复投递撞唯一键，`insert_transaction` 返回 0 而不是写脏数据。`dedup_key` = `bill_date|金额(两位小数)|商户|备注`（商户与备注先 trim）。
2. **邮件级跳过**：抓取前先读 `known_email_uids(rule_id)`，已知 UID 直接不解析、不计数。
3. **软重复提示**：手动录入时 `ledger_check_duplicate` 按"同日 + 同账户 + 同商户 + 金额差 < 0.005"找已入账的那笔，UI 弹提示但不拦死。

### 状态机

`transactions.status`：`pending`（待确认，不进任何统计）→ `posted`（已入账）或 `ignored`（已忽略）。`source`：`manual` / `email`。所有 `stats_*` 查询硬带 `status = 'posted'`，所以待确认队列里的钱绝不会提前出现在概览上。

---

## 邮件入账链路

```
调度器(每 60s 看一次到点规则)          用户在设置页点"立即检查"
        └────────────┬────────────────────────┘
              check_by_rule(rule_id, password)
        ┌────────────▼────────────┐
        │ email_module 收信        │  IMAP/POP3 over TLS，MIME 解码出 html+text
        └────────────┬────────────┘
     message_matches(发件人 + 标题，可选正则)
        └─▶ resolve_template_id ─▶ 三种模板之一
              └─▶ parse_message ─▶ ParseResult{bill_date, transactions[], available_credit, points_balance, warnings[]}
                    └─▶ 逐笔 insert_transaction（账户按卡片尾号回落规则默认账户）
                          └─▶ record_email 落待确认队列
```

### 模板

| id | 说明 |
|------|------|
| `cmb_daily_bill` | 招商银行信用卡每日账单：靠 `fixBand4` 切出明细区，`fixband5` 取日期、`fixband12` 取金额/尾号/商户/卡种三段式 |
| `generic_keyword` | 通用关键字：配日期/金额/摘要关键字，给格式已知但没有内置模板的账单 |
| `custom_regex` | 一条带命名组的正则吃整行，最灵活也最容易写错，改完必须用预览验证 |
| `auto`（规则默认值） | 命中招行指纹（标题含"每日账单/消费明细/交易明细" 且正文含 `bill_templet_resource` / `s3gw.cmbimg.com` / `cmbchina`）走内置模板，否则落 `generic_keyword` |

解析出来一笔都没有时返回明确错误（"命中了招行账单模板但一笔都没解析出来"），因为那几乎总是银行改了邮件模板，不该静默当"今天没消费"。

### 调度器

`std::thread` + 分片 1 秒睡眠（停止请求最坏 1 秒生效），每 60 秒一轮 `run_due_rules()`。规则靠 `interval_minutes`（间隔轮询）或 `daily_time`（HH:MM 每日时点，当天已跑过就不再跑）判定到点。`ledger_scheduler_status` 回 `{running, enabled, check_interval_secs, last_check_at, next_check_at, active_rules, last_summary}` 给设置页显示。

口令常驻进程内存（`scheduler::SECRETS: RwLock<HashMap<i64, String>>`），所以后台自动收信只在**本机跑过服务**时成立。Dart 侧 `ensureInitialized()` 会把安全存储里的口令推进内存（`_warmRuleSecrets`），且只有存在"启用 + 协议支持"的规则时才拉起线程。

---

## 凭证与 TLS 约束

- IMAP/POP3/SMTP 的 AUTH **强制 TLS**；只有 loopback 主机例外。`accept_invalid_certs` 必须由用户显式勾选，默认 false。
- 口令路径：Dart 只存 `flutter_secure_storage`（key = `ledger_rule_<id>`），调用 FFI 时按需带过去；Rust 只存内存 map；SQLite 里只有 `secret_ref`。
- 口令不写日志、不进错误文案；TLS 准入策略由 `rust/email_module/tests/config_policy_test.rs` 守住（明文连公网主机被拒、loopback 例外、SSL 恒满足、`serde(default)` 保证缺字段时按安全默认值补齐）。
- 走远程节点时口令只随单次请求传输，节点侧不落盘。

---

## 移动端与节点中转

Rust 的 SQLite/线程在移动端跑不动后台收信，所以：

- `LedgerService` 有 `isLocal`（`selectedNodeId` 为空）与 `currentNodeBaseUrl`，非本地时每个 FFI 调用改走 `POST /node/call`，`action` 就是同名 `ledger_*`
- `rust/src/node_server/handlers.rs` 把 `ledger_` 前缀的动作收口在一个分支里，先 `ensure_ledger_ready()`（节点自己按 `ledger/ledger.db` 建库），再按返回类型套 `ledger_json / ledger_text / ledger_scalar / ledger_flag / ledger_void` 五种包装
- **不转发**的五个：`ledger_init / is_ready / version`（节点自己初始化，不该由远端指定库路径）、`ledger_set_rule_password`（只热本机内存，远程口令一律随单次请求带过去）、`ledger_rule_detail`（UI 未用）。`ledger_list_folders` 也不单列，由 `ledger_test_connection(want_folders=true)` 覆盖
- 定时调度、口令预热这类"常驻"能力只在本机模式下有效，UI 上明确标注

---

## UI 约定

- 取色只走 `AppSemantic.of(context)`，可视化配色用 `AppVizSet`，流水账固定用 **lagoon** 色族
- 窄屏判定 `ledgerNarrow(context)` = `PlatformUtil.isMobile || 窗口宽 < 720`；胶囊 tab 窄屏收图标、筛选条换行独占、搜索框不挤扁
- 尺寸只用 `AppTheme.metrics` + `scaleW()`；图标一律 `DrawIcon(StrokeIcons.*)`
- 月份条（`LedgerMonthStrip`）钉在空态组件**外面**：这个月没账不等于哪个月都没账，收进空态等于骗用户
- 图表绘制里像素与弧度必须换算（`drawArc` 的 gap 按半径折算），不能拿 `scaleW(1.5)` 直接当弧度减

---

## 测试

| 文件 | 覆盖 |
|------|------|
| `rust/ledger_module/tests/cmb_parser_test.rs` | 招行正文解析（fixture 已脱敏） |
| `rust/ledger_module/tests/storage_test.rs` | 建库/播种/去重唯一键/统计口径 |
| `rust/ledger_module/tests/ffi_json_test.rs` | JSON 面契约 |
| `rust/email_module/tests/{config_policy,dispatch,mime}_test.rs` | TLS 策略、协议分发、MIME 解码 |
| `test/ledger_models_test.dart` | Dart 模型与月份 helper（含区间闭合性） |
| `test/ledger_service_test.dart` | `RustLib.initMock` 桩 FFI：节点/本地双路径、口令只走安全存储 |
| `test/ledger_render_test.dart` | 桌面 + 手机 golden 15 张、逐帧排版冒烟、首屏数据断言 |
| `test/ledger_icons_test.dart` | 图标标识 → `StrokeIcons` 映射全覆盖 |

---

## 已知限制

- IMAP/POP3/SMTP 客户端**尚未在真实服务器上验证过**，测试全部走桩。首次真机配置建议先用设置页的"连接自检 + 列目录"。
- Exchange(EAS) 需要 WBXML 协议栈与设备证书下发，CardDAV 同理，两者当前只占位并返回可操作的说明文案（企业 Exchange 一般同时开 IMAP，可改走 IMAP）。
- 只有招商银行每日账单是内置模板；其他银行要用 `generic_keyword` 或 `custom_regex` 自己配，且银行改版会让解析失败（会有告警与抓取日志，不会静默）。
