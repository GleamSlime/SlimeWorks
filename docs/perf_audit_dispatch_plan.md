# 媒体库/资源库性能审计与子智能体下派方案

> 2026-11-09 · 状态：三轮修复已合入（见「已完成」），本文剩余部分为待下派任务书。
> 每个任务块自包含（背景/证据/目标/验收/写入范围），可直接作为 `subagent` /
> `spawn_teammate` 的 prompt 使用。

---

## 背景：已确认的性能模式（所有子任务共用的上下文）

实测环境：386,641 条条目、`media.db`（redb）511MB，媒体文件全部在 SMB 网络卷
`/Volumes/192.168.3.15`。`node_server` 空闲线程 **5 分钟**就
`check_and_release_if_idle` 释放条目内存缓存 → 问题表现为「每次进页面都慢」。

三类根因模式（审计时按此模式找同类）：

1. **整表冷加载**：任何走 `items_mutex().lock()` + `ensure_items_loaded()` 的
   读路径都要把整张 `media_items` 读进内存（实测 1.3s，磁盘忙时 13.5s），
   见日志 `[media_cache] 从数据库加载媒体条目到内存，共 N 条(+Xs)`。
2. **首屏 await 重活**：把逐文件 stat / 大 FFI 传输挂在页面初始化的 await 链上
   （网络卷逐文件 stat = 每次一趟网络往返；外置卷唤醒实测 4s）。
3. **build 期间同步 FFI / 高频轮询打重接口**：卡片 build 触发同步查询，或
   定时器每 2s 轮询一个会冷加载整表的接口。

### 已完成（三轮提交，勿重复做）

| 提交 | 内容 |
|------|------|
| `e64b330` | 进页面读聚合小表 `media_collection_stats`；全量 stat 改后台限频（30min）；路径按需 `ensureCollectionItemPaths` |
| `6d82919` | 路径快照独立 `media_collection_paths` 表（不塞聚合行） |
| `1c71906` | 条目索引 `media_collection_item_index` 表：单集合读/删走 `db_get_many` 快路径；`get_all_collection_counts` 改读聚合；条目丢失预热后台化 |

关键基础设施（子任务直接复用）：
- `db_module::db_get_many(table, keys)`：单事务批量取值
- `media_collection::get_all_collection_aggregates()`：聚合小表读（旧库自动补齐一次）
- `load_collection_item_ids` / `persist_collection_item_ids`：条目索引读写
- `load_collection_paths` / `persist_collection_paths`：路径快照读写
- 新表必须同时进 `media_table_names()`（绑定到 media.db）与
  `clear_all_local_media` 的 `tables_to_clear`（清库表数断言在
  `db_clear_all_local_media_keeps_original_files`，当前 = **10**）

### 已修后剩余的整表调用点（`rust/media_collection/src/api.rs`）

| 函数 | 现状 | 定性 |
|------|------|------|
| `get_all_collection_stats` | 仍整表 + 全量路径传输 | **遗留死接口候选**：Dart 生产链路已无人调用（仅 seam/FFI 导出与历史参考 `node_http_handler.dart`），见任务 A |
| `get_all_collection_live_stats` | 整表快照 + 38 万次 stat | 已后台限频化；可再优化为从路径表取快照（任务 A 可顺带） |
| `get_all_collection_aggregates` 补齐分支 | 整表一次 | 设计如此（旧库一次性代价），不动 |
| `upsert` / `get_media_collection_items` / `delete` 的 None 分支 | 整表一次 | 旧库懒回填兜底，设计如此，不动 |

---

## 硬性约束（写进每个子任务 prompt）

1. **架构**：Flutter 只做 UI；逻辑/存储/扫描在 Rust。注释必须中文，不删已有注释。
2. **提交三道关**：`flutter analyze` 干净 + **全量** `flutter test` 对比基线失败集合
   （本机既有 389 个 golden 环境失败；head 不得新增）+ Rust `cargo build`。
3. **Rust 构建环境**（本机无 Xcode.app）：
   ```bash
   export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
   # FRB generate 若报 cargo expand 空输出，再补：
   export SDKROOT=$(xcrun --show-sdk-path)
   export CPLUS_INCLUDE_PATH="$SDKROOT/usr/include/c++/v1"
   ```
4. **基线对比法**：`git worktree add /tmp/sw_baseline_<task> <基线commit>`，然后必须
   ① `cp 主目录/.env` 进去 ② `dart run tool/stroke_icons/generate.dart`
   ③ `dart run build_runner build --delete-conflicting-outputs`，否则整片 loading error。
   失败集合规范化：`tr '\r' '\n'` → 剥 `HH:MM +N -N:` 前缀 → 只留 `/Users` 开头行 → sort -u → diff。
5. **测试环境坑**：`TestWidgetsFlutterBinding` 会把 HttpClient mock 成 400；
   extension 不能声明实例字段；`Isolate.run` 里 FRB sync 必炸。
6. **写入范围**：每个任务只改自己 scope 内的文件；跨 scope 需求回报 Lead，不要顺手改。

---

## 任务 A：遗留重接口清理 + live 快照来源优化（Rust，串行第 1 优先）

**写入范围**：`rust/media_collection/src/api.rs`、`rust/src/api/media_collection.rs`、
`lib/mock/seams/media_api_seam.dart`、`lib/src/rust/**`（FRB 生成物）、
`rust/src/frb_generated.rs`、`test/media_library_logic_test.dart`（如需）。

**内容**：
1. `get_all_collection_stats`：确认全仓（含 `rust/src/node_server/`、mobile HTTP 中转）
   无生产调用后，从 FFI 导出与 seam 删除（Rust 内部若测试用到可留 pub(crate)），
   跑 `flutter_rust_bridge_codegen generate` 重生成。若发现仍有调用方，改调用方走
   聚合表 + 路径表，再删。
2. `get_all_collection_live_stats` 的快照来源：改为遍历 `media_collection_paths` 表
   （逐集合 `load_collection_paths`），缺行的集合退回 `get_media_collection_items`
   （已有索引快路径），彻底去掉 `ensure_items_loaded`。
3. 历史参考文件 `lib/core/services/node/node_http_handler.dart` 头部已注明「仅作历史
   参考」：其中 `list_media_collections` 还在调整表 stats——确认 extension 无入口调用
   后在该 case 加注释或同步改聚合表读，避免将来被复活。

**验收**：`cargo test -p media_collection` 全过；`grep ensure_items_loaded` 只剩
「设计如此」的兜底分支；FRB 生成成功；三道关全过。

## 任务 B：其余资源库模块同类问题审计（只读审计，产出报告）

**写入范围**：仅 `docs/perf_audit_<module>.md`（报告），不改代码。

**内容**：按「三类根因模式」审计以下模块的进页面链路与轮询链路：
- `novel_reader`（进书架/阅读器：是否整表冷加载章节内容？）
- `game_library`（SQLite：进首页统计是否全表扫？GameProcessTracker 轮询频率）
- `music_player`（进页面加载列表/波形；`scutil --proxy` 每次请求都跑？）
- `manga_module` + `MangaDownloadService`（列表/搜索是否有 N+1 HTTP）
- `ledger_module`（进概览的聚合查询）
- `extract_module` / `sentry_log`（列表分页）

每个发现给出：文件:行号、触发时机（首屏 await / build / 轮询）、量级估计、
建议修法（对照本仓已验证的「聚合表 + 按需 + 后台限频」定式）、风险。
**只报告确有证据的问题**（读代码能指到具体重活），不要臆测性列出所有 IO。

**验收**：报告按「高/中/低」分级，每条可独立立项；Lead 复核后决定是否派发修复。

## 任务 C：媒体库远程链路审计（只读审计）

**写入范围**：仅 `docs/perf_audit_remote.md`。

**内容**：
- `refreshRemoteLibrary` / `fetchNodeMediaMetadata`：三路并发的失败重试与熔断复活
  探测（`recheckOfflineNodes`）在离线节点多时的耗时上界；
- `_pollRemoteThumbProgress` 每 2s/15s 轮询在 N 节点串行 for 循环——节点多时是否
  应并发 + 自适应退避；
- 深度搜索远程路径预热（`_kRemotePathConcurrency=4`）的 503 负缓存策略；
- 节点侧 `handlers.rs` 剩余动作是否有整表/逐文件 stat（对照任务 A 结果）。

**验收**：同任务 B。

---

## 下派操作手册（Lead 执行）

### 方式一：`subagent`（推荐，任务彼此独立时）

一条消息里并行发起，各自独立上下文、结果回报：

```
subagent({
  description: "清理遗留整表接口",
  cwd: "/Users/gleamslime/Desktop/SlimeWorks",
  prompt: "<本文『硬性约束』全文> + <任务 A 全文> + 当前 HEAD=<commit>"
})
subagent({ description: "资源库模块性能审计", prompt: "<硬性约束> + <任务 B>" })
subagent({ description: "远程链路性能审计",   prompt: "<硬性约束> + <任务 C>" })
```

要点：
- prompt 必须**自包含**：子智能体看不到本会话历史，背景/证据/环境命令都要带上；
- A 改代码、B/C 只写各自报告 → 写入范围无交集，可并行；
- A 完成后 Lead 复核 diff + 复跑三道关再让它提交（或 Lead 代提交）；
- B/C 报告回来后由 Lead 决定第二批修复任务的派发。

### 方式二：`workflow`（批量同构审计时）

任务 B 的 6 个模块是同构扇出，若主人明确要求 workflow，可写：

```js
const modules = ["novel_reader","game_library","music_player","manga","ledger","extract+sentry"];
const reports = await parallel(modules.map(m => () =>
  agent(`<硬性约束> + 按三类根因模式审计 ${m}，只写 docs/perf_audit_${m}.md`, {
    label: `audit:${m}`, phase: "审计",
    schema: { type:"object", properties:{ module:{type:"string"},
      findings:{type:"array", items:{type:"object", properties:{
        severity:{enum:["high","mid","low"]}, where:{type:"string"},
        evidence:{type:"string"}, fix:{type:"string"} },
        required:["severity","where","evidence","fix"], additionalProperties:false}}},
      required:["module","findings"], additionalProperties:false }
  })));
return reports.filter(Boolean);
```

结构化结果便于 Lead 汇总排序；但审计要看大量代码，单模块用 plain subagent 也够。

### 方式三：Agent Teams（长周期、多轮修复时）

```
spawn_teammate({ name:"rust-perf", description:"Rust 侧性能修复",
  prompt:"<硬性约束> + <任务 A>；完成后队 team_task 板领下一个" })
team_task_create({ subject:"任务A …", description:"…", write_scopes:["rust/","lib/src/rust/"] })
```

适合后续把 B/C 报告立项成 task 板批量消化；当前三个任务用 subagent 更轻。

### Lead 收尾清单

- [ ] 每个改代码的子任务：亲自 `git diff` 复核 + 复跑三道关（子任务自报不能替代）
- [ ] 失败集合对比用规范化流程（见硬性约束 4），别被 \r 和计数器前缀骗了
- [ ] 提交信息按本仓风格：`perf(media): …` 中文正文写根因/改法/校验
- [ ] 审计报告归档 docs/，发现项转下期任务

---

## 附：本轮已验证的日志取证命令

```bash
# 整表冷加载耗时（Rust 落文件日志）
grep 'media_cache' ~/Library/Logs/史莱姆工坊/logs/slime_works_$(date +%F).log
# Dart Loggers 只进内存环形缓冲不落盘——Dart 侧耗时看 TimingTrace 需 debug 运行
```