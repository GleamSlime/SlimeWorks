# 流水账模块（Ledger）

## 模块概述

流水账是日常记账 + 银行账单自动入账的模块，两条录入路径共用一份 SQLite 账本：

- **手动记账**：流水页加一笔，或批量补录
- **邮件自动入账**：按规则每天收取账单邮件（招商银行信用卡每日账单为内置模板），解析 HTML 正文成多笔流水，进**待确认队列**，用户逐笔确认后才计入统计；规则勾了 `auto_apply` 则直接入账
- 收件协议 **IMAP / POP3** 已实现，**SMTP** 只用于连接自检（明确拒绝用它收信），**Exchange(EAS) / CardDAV** 保留配置入口但诚实报"尚未实现"
- 统计：自由区间（预设 + 自定义）、按日/周/月/年聚合轴切换、按类别、按商户 TopN、区间收支汇总与资产趋势折线，全部是自定义 `CustomPainter`，不引图表库
- 记账类型四种：支出 / 收入 / 转账 / 余额调整；类别支持两级；一笔可挂多个标签。转账、标签、模板、定时这几样的**后端存储还没接**，见"记账增强的边界"

---

## 目录结构

```
lib/
  pages/ledger/
    ledger_screen.dart              - 首页（月度概览 + 日趋势 + 最近流水）
    ledger_records_screen.dart      - 流水明细（筛选 + 分页 + 编辑 + 日历视图）
    ledger_stats_screen.dart        - 统计（自由区间 / 聚合轴 / 类别环图 / 资产趋势）
    ledger_pending_screen.dart      - 待确认账单（邮件溯源 + 逐笔确认）
    ledger_settings_screen.dart     - 账单邮箱（规则、模板预览、连接自检、抓取日志）
    ledger_accounts_screen.dart     - 账户（含商户自动归类习惯）
    ledger_organize_screen.dart     - 分类与标签（类别两级树 + 标签分组）
    ledger_templates_screen.dart    - 模板与定时记账（点模板记一笔 + 规则开关）
    ledger_data_screen.dart         - 导入与导出（CSV/JSON 出，表格预览后落库）
    components/                     - 共享组件（tab/底部导航/月份条/图表/各类编辑器）
    models/ledger_models.dart       - Dart 侧模型 + 月份/金额 helper
  core/services/ledger_service.dart - GetIt 单例：FFI 包装 + 口令安全存储 + 节点中转
  core/services/ledger_stub_store.dart - 后端未接入那几样的进程级桩仓库（见下方边界）
  view_models/ledger/               - 9 个页面 VM
  core/routes/routes/ledger_routes.dart - 9 条 typed route（part of app_routes.dart）
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
| `/ledger/organize` | `LedgerOrganizeScreen` | 同上 |
| `/ledger/templates` | `LedgerTemplatesScreen` | 同上 |
| `/ledger/data` | `LedgerDataScreen` | 同上 |

侧栏只露"流水账"一格，子页挂在它下面：宽屏靠页内的胶囊 tab（`LedgerTabs`）互跳，窄屏与手机改走底部导航（`LedgerBottomNav`，四个落点 + 中间一颗"记一笔"）；把每一页都平铺到侧栏会把一个账本读成六个功能。两条导航的第一项都叫"概览"，同一个目的地不该有两种叫法。

`/ledger/accounts`、`/ledger/organize`、`/ledger/templates` 与 `/ledger/data` 不在两条导航里（它们是设置页的下级）：账户与分类两页的入口有三处——设置页的 `LedgerNavTile`、账户页里跳分类的 `LedgerNavTile`、侧栏展开后的子项；模板页与导入导出页只从设置页进，"常记的那几笔"和"搬账本"都不该和"看账"抢位置。

权限统一 `Permission.accessLedger`，分组 `sidebarGroupId: 'ledger'`（`sort: 44`）。

---

## 记账增强的边界：哪些是真数据，哪些是桩

这一轮按"先铺 UI 骨架、后端下一轮补"推进，分界线就一条：**后端已经有的继续打 Rust，后端没有的走 `LedgerStubStore`**。

| 数据 | 来源 | 说明 |
|------|------|------|
| 流水 / 账户 / 类别 | `LedgerService` → Rust | 真实数据，邮件账单链路已在跑 |
| 标签、标签分组 | `LedgerStubStore`（进程级单例 + `SharedPreferences`） | 演示数据，页面上挂 `LedgerStubMark` 水印 |
| 记账模板、定时规则 | 同上 | 演示数据，但**按模板记下来的那一笔走的是真账**（`ledgerCheckDuplicate` → `ledgerAddTransaction`），所以水印只写在模板与规则那两块，不写"这笔账是假的" |
| 附件、备份记录 | 同上 | 同上 |
| CSV/JSON 导入导出 | 编解码在 `LedgerStubStore`（纯文本），**读写的两头都是真账** | 导出打 `ledgerListTransactions`，导入逐笔 `ledgerAddTransaction`；整页不挂水印，只有"标签那一列导进来会丢"单独说清——后端还没有标签表，那是真存不住 |

模板与规则把账户与类别**按名字也存了一份**（`accountName` / `categoryName`）：桩阶段没有外键拦着，类别与账户随时会被删，只存 id 的那一半就会指错。`showLedgerTxEditor` 拿到草稿先按 id 认一次，认不到再按名字认一次，两边都对不上就留空让用户自己选——预选一个不相干的类别比空着更糟。这条回认在真库上同样成立，接后端时不用改界面。

桩仓库的方法名与签名按未来的 FFI 契约写（`Future` + 同名动词），下一轮把方法体换成 `rust_api.ledgerXxx()` 即可，界面代码一行不用改。测试里必须 `await LedgerStubStore.instance.resetForTest()`——它是进程级单例，不清零会上一个用例建的分组漏到下一个。

### 下一轮补 Rust 时的清单

- **`categories` 缺 `parent_id` 与 `color` 两列**：两级分类和"图表按用户挑的颜色取色"今天在真库里存不住。界面已经按 `hasSubLevels`（库里是否已存在非根类别）决定要不要画"上级类别"栏与"添加子类"按钮，所以后端补列之前不会摆一排点了不生效的控件；补完之后界面不用动。
- **`transactions` 缺 `type` 列**：转账与余额调整现在只能回落成支出/收入（见 `ledger_models.dart` 的 `kLedgerTxType*` 注释）。转账还需要"另一侧账户"字段，一笔记成两行还是一行两账户要在建表前定死。
- **`upsert_category` 按 `name` 命中就 UPDATE**：用户新建的子类若与内置类同名，会**改写内置类**而不是新建一条。补 `parent_id` 时唯一键要一起改成 `(name, direction, parent_id)` 之类，并在迁移里处理既有冲突。
- **`init_db` 只有 `CREATE TABLE IF NOT EXISTS`**：加列不会作用到已存在的库，必须先做一套版本化迁移（`PRAGMA user_version` 起步即可），否则老用户升级后界面读到缺列。
- **缺 `tx_templates` 与 `schedules` 两张表**：模板要存 `title / tx_type / direction / amount / dest_amount / account_id / category_id / tag_ids / merchant / note / use_count`，规则要存 `template_id / repeat / day_of_month / weekday / time_of_day / start_date / end_date / enabled / last_run_at / next_run_at`。规则的 `next_run_at` 由调度器写，界面里那个 `_guessNextRun` 只是撑住"下次"这一行的近似值，接上后端就该删。定时执行仍然只在本机调度器上跑，远程节点不跑（与收信规则同一口径）。
- **`tag_ids` 需要一张 `transaction_tags` 关联表**：流水与标签是多对多，`transactions` 里塞不下；标签与分组本身也要 `tags` / `tag_groups` 两张表。
- 桩仓库的 `enabled` / `setEnabled` 目前只有存储一侧，list 方法还没判 `_enabled`，设置页也还没有那个开关：要么补完"关掉就退回空态"，要么把这三处死代码删掉。
- **导入的类别解析要挪回 Rust**：`LedgerDataViewModel._resolveCategory` 现在把"父/子"两级名字在 Dart 里认（先父后子、只给一层就先当父类再退化成任意同名），账户同理（停用账户一律算"对不上"）。补上 `parent_id` 之后这套仍然成立，但名字撞车时该由后端按 `(name, direction, parent_id)` 唯一键来定，而不是 Dart 取 `firstOrNull`。
- **导入的标签列**：`bind()` 现在把 `tagIds` 一律写成空表——写进去就是一串指向空气的外键。`transaction_tags` 建好之后，导入要把 `标签` 那一列按名 upsert 成标签再落关联，回执里那句"标签暂时存不住，已丢掉"跟着删。
- **备份与恢复还没做**：后端存不住整库快照，所以导入导出页不摆"备份/恢复"两个点了也不生效的按钮。
- **测试 fixture 的类别名与真库内建名不是一套**：`test/ledger_render_test.dart` 用的是短名（餐饮/交通/居家…），Rust 的 `BUILTIN_CATEGORIES` 是全名（餐饮美食/交通出行/居家缴费…），默认账户真库只有"现金"。桩数据 `_seed()` 按**真库名**写，所以真机上名字回认能命中；代价是测试里那几个短名回认不中——测回认机制要用例自己造模板，别去断言 seed 的回认结果。

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

1. **硬幂等**：`transactions` 上 `CREATE UNIQUE INDEX ... ON (rule_id, email_uid, dedup_key) WHERE source = 'email'`。同一封邮件重复投递撞唯一键，`insert_transaction` 返回 0 而不是写脏数据。`dedup_key` = `交易时刻|金额(两位小数)|商户|银行类型|r行序`。尾巴那个行序是必需的：月度电子账单只给 MMDD、连时分都没有，同一天两笔同额同商户的真实重复扣款若不编进行序，第二笔就会被唯一键当重复挡掉。
2. **邮件级跳过**：抓取前先读 `known_email_uids(rule_id)`，已知 UID 直接不解析、不计数。
3. **软重复提示**：手动录入时 `ledger_check_duplicate` 按"同日 + 同账户 + 同商户 + 金额差 < 0.005"找已入账的那笔，UI 弹提示但不拦死。

### 状态机

`transactions.status`：`pending`（待确认，不进任何统计）→ `posted`（已入账）或 `ignored`（已忽略）。`source`：`manual` / `email`。所有 `stats_*` 查询硬带 `status = 'posted'`，所以待确认队列里的钱绝不会提前出现在概览上。

---

## 邮件入账链路

```
调度器(每 60s 看一次到点规则)     用户在待确认页/设置页点"立即收取"
        └────────────┬────────────────────────┘
              check_by_rule(rule_id, password)          ← 只取收件箱最新 10 封
        ┌────────────▼────────────┐
        │ email_module 收信        │  IMAP/POP3 over TLS，MIME 解码出 html+text
        └────────────┬────────────┘
     message_matches(发件人 + 标题，可选正则)
        └─▶ resolve_template_id ─▶ 三种模板之一
              └─▶ parse_message ─▶ ParseResult{bill_date, transactions[], available_credit, points_balance, warnings[]}
                    └─▶ 逐笔 insert_transaction（账户按卡片尾号回落规则默认账户）
                          └─▶ record_email 落待确认队列
```

「回补历史」（`ledger_backfill_rule`）复用上面这一整段编排，只把抓取深度从 10 封换成最近 200 封：定时收取够快，但第一次配规则、口令失效停摆几天、或那 10 封里恰好夹了广告时，过去的账单就永远进不来，得靠这个入口回灌。重复点不会记两遍——已收过的 UID 先跳过，流水表还有 UNIQUE `(rule_id, email_uid, dedup_key)` 兜底。

### 模板

| id | 说明 |
|------|------|
| `cmb_daily_bill` | 招商银行账单，两种版式都走它（id 不变，规则里显式选它也照此分流）：<br>· **每日明细**：`fixBand4` 切明细区，`fixband5` 取日期、`fixband12` 取金额/尾号/商户/卡种三段式；<br>· **月度电子账单**（2026 版）：band 容器不带引号（`<SPAN id=fixBand15>`）、明细单元格一个 id 都没有、表头全是图片，于是按 `<tr>` 取叶子 `<td>`，从行尾那个金额格倒推列位（`交易日|入账日|摘要|交易金额|卡号末四位|币种|人民币金额`），入账取人民币金额列，MMDD 的年份由账单期间 `2026-08-22-2026-09-21` 补（月日晚于期间末的算期间起始那年）。<br>两种版式共用 `fixBand4`，光看容器在不在选不对分支：先按每日版式试，谁真解析得出笔数听谁的，两边都空则报错并留档原文。|
| `generic_keyword` | 通用关键字：配日期/金额/摘要关键字，给格式已知但没有内置模板的账单 |
| `custom_regex` | 一条带命名组的正则吃整行，最灵活也最容易写错，改完必须用预览验证 |
| `auto`（规则默认值） | 命中招行指纹（标题含"每日账单/消费明细/交易明细" 且正文含 `bill_templet_resource` / `s3gw.cmbimg.com` / `cmbchina`）走内置模板，否则落 `generic_keyword` |

解析出来一笔都没有时返回明确错误（"命中了招行账单模板但一笔都没解析出来"），因为那几乎总是银行改了邮件模板，不该静默当"今天没消费"。

命中规则却解析不了的邮件，原文会写到账本旁边的 `ledger/parse_failures/rule<规则id>_<UID>_<主题>.html`，概况与日志里给出这个目录路径——银行改版时只有原文能说明新结构长什么样，把它贴回规则编辑器的「用一段 HTML 验证模板」或直接发给作者即可。没命中规则的邮件一封都不落盘。

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
- 后端存不住的能力，界面上就不摆控件。类别的两级树是个渲染器，不是一排假的下拉框：库里没有一个非根类别时，`hasSubLevels` 为假，"上级类别"栏与"添加子类"按钮都不出现
- 图表绘制里像素与弧度必须换算（`drawArc` 的 gap 按半径折算），不能拿 `scaleW(1.5)` 直接当弧度减
- 凡是要出 golden 的列表排序，比完主键必须再按名字钉死一次：`List.sort` 不是稳定排序，同样常用的两张卡片每次刷新都可能换位置

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
| `test/ledger_render_test.dart` | 桌面 + 手机 golden 25 张、逐帧排版冒烟、首屏数据断言、分类两级树与标签块的交互、模板与定时的交互（回认/入账/级联删除/规则开关）、导入导出（预览的行归认、兜底账户、确认与回执） |
| `test/ledger_icons_test.dart` | 图标标识 → `StrokeIcons` 映射全覆盖 |

桩 FFI 的返回类型必须与 FRB **生成出来的**签名一致，而不是与 Rust 源码的直觉一致：`ledgerDeleteCategory` 生成为同步 `String`，桩就要给裸字符串，给 `Future<String>` 会在返回类型检查处炸掉，症状是页面回执永远为空。`ledgerCheckRule / ledgerBackfillRule` 反过来是 `Future`，桩得给 `Future<String>.value(...)`。另外 `ledgerListCategories` 的 `direction` 传空串是"收支都要"，桩得回两个方向的并集——只回支出会让所有读类别的页面少一半。

golden 用 `--update-goldens` 重生成之后别只盯新图：拿旧基线做逐像素 diff（差异框 + 占比），确认改动落在预期的那块区域，再按 1:1 裁切目视。整页 30% 的位移通常只是底部导航把内容顶高了。

widget 测试在这一页上有五个坑，都是踩过才知道的：

- **选中态的证据要取边框，不是底色。** 测试主题走的是 `AppTheme._buildBase(AppSemantic.light)`，没经过"按用户强调色重算容器色"那一步，于是亮色档的 `accentContainer` 与 `surfaceSunken` 都是 `#F5F5F5`——比底色等于什么都没测。边框那一侧才是两个值（`#E5E5E5` / 5% 黑）。
- **懒建的 `ListView` 要先滚到位**。`tester.scrollUntilVisible` 找到之后还会再 `element()` 取一次那个 widget，项目多、滚得远时卡片已被回收，报出来的是没头没尾的 `Bad state: No element`；换成"一格一格 drag 到目标出现"的循环，失败时才说得出是哪一行没建。
- **回执与统计行各在一头**：`_Feedback` 钉在页面最顶，汇总行排在整块列表之后，断言前得先滚过去，不然测的是"没渲染"而不是"没写"。
- **`Obx` 只记它自己同步读到的那几路。** 把 `Obx(() => _buildBody(context))` 摆在外层、卡片各自在 `build` 里读 `vm.xxx.value`，等于挂了个什么都没观察到的 Obx：Get 直接报 `improper use of a GetX`，界面也不会随状态重画。要么外层同步读到全部状态，要么每块卡片自己包一层 `Obx`（导入导出页选的是后者，各块只重画自己那一块）。builder 里一路可观察量都没碰到就不行——`errorMessage` 那种普通字段不算，得顺手读一次 `lastMessage.value`。
- **桩要按 filter 真的筛，否则"换个区间"等于没测。** `ledgerCountTransactions` 一律回总笔数，导出页的区间胶囊就永远绿着；明细页翻月份同理。桩 responder 里按 `start_date / end_date / status` 过一遍 `_txs`，笔数才跟着区间走。注意 responder 比 responses 先查：`_seedEmpty()` 那种"把某路返回改成空"的写法要连 responder 一起覆盖，不然写下去是空话。

---

## 已知限制

- IMAP/POP3/SMTP 客户端**尚未在真实服务器上验证过**，测试全部走桩。首次真机配置建议先用设置页的"连接自检 + 列目录"。
- Exchange(EAS) 需要 WBXML 协议栈与设备证书下发，CardDAV 同理，两者当前只占位并返回可操作的说明文案（企业 Exchange 一般同时开 IMAP，可改走 IMAP）。
- 只有招商银行账单是内置模板（每日明细 + 月度电子账单两种版式）；其他银行要用 `generic_keyword` 或 `custom_regex` 自己配，且银行改版会让解析失败（会有告警与抓取日志，原文进 `<账本目录>/parse_failures/`，不会静默）。
