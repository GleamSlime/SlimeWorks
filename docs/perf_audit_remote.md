# 媒体库远程链路性能审计（任务 C，只读）

> 2026-11-09 · 基线 HEAD=`3a42a40` · 审计人：任务 C 子智能体
> 范围：`media_library_vm_remote.dart` / `media_library_vm_search.dart` /
> `node_settings_service.dart` / `rust/src/node_server/handlers.rs`（及其依赖的
> `media_collection/src/api.rs` 读路径）。只写本报告，未改任何代码。
> `get_all_collection_stats` / `get_all_collection_live_stats` 标注为**任务 A 处理中**，本文不深究。

## 0. 关键常量与调用链速查（量级估计的依据）

| 常量 | 值 | 位置 |
|------|-----|------|
| 业务 Dio 超时 | connect 3s / receive 12s / send 12s | `lib/core/services/node/node_settings_service.dart:54-56` |
| 探测快速档 | 200ms | 同文件 :80 |
| 探测确认档 | 1.5s | 同文件 :87 |
| 503/429 忙重试 | 2 次，延迟 150ms/300ms | 同文件 :90、:1584-1589 |
| 元数据预热快照有效期 | 60s | 同文件 :244 |
| 远程刷新节流窗口 | 60s（仅进页面入口） | `lib/view_models/media_library_viewmodel.dart:447` |
| 缩略图进度轮询 | 忙 2s / 闲 15s，**节点间串行** | `lib/view_models/media_library_vm_remote.dart:23-55` |
| 深度搜索预热并发 | 4 | `media_library_viewmodel.dart:203` |
| 搜索输入防抖 | 280ms | `media_library_viewmodel.dart:162` |
| 节点侧最大并发连接 | 128，超出回 503 | `rust/src/node_server/mod.rs:158、:179-199` |

调用链：进页面 `refreshAllOnEnter` → 本地 FFI（Phase 1，先出 UI）→
`_refreshRemoteBackground`（`media_library_vm_refresh.dart:147-173`）→
**先 `await recheckOfflineNodes()`，再 `refreshRemoteLibrary()`**（:162-164）→
节点间 `Future.wait`、节点内三路 `Future.wait`（`vm_remote.dart:69`、
`node_settings_service.dart:359-363`）。

`get_thumb_progress` 节点侧只读两个 AtomicU64（`media_handler.rs:12-21`），
`ping` 在连接线程就地回答不进共享 runtime 队列（`mod.rs:417-422`）——这两个
接口本身极轻，问题全在客户端的调度方式上。

---

## 高优先级

### H1. 熔断节点的缩略图轮询每 15s 付一整轮确认档探测，且「忙」档会持续放大

- **位置**：`lib/view_models/media_library_vm_remote.dart:23-37`（串行 for + 不筛熔断节点）；
  `lib/core/services/node/node_settings_service.dart:1518`（`_callNode` 先 `_ensureNodeReachable`）；
  :637-662（复探单飞 + 1.5s 确认档）；:619-632（`_reprobeNode` 每 base 并发）；
  :573-613（`_probeNodeUrl` 内**候选 URL 串行**，无端口 base 会生成 2 个候选，:1691-1707）。
- **触发时机**：媒体库首次 `onInitAsync` 启动轮询（`media_library_viewmodel.dart:674`），
  永久 VM 生命周期内一直跑。轮询列表取 `enabledRemoteNodes`（:10），**不剔除已熔断/已知离线节点**。
  熔断节点走到 `_callNode` 必进 `_ensureNodeReachable`：复探失败 → 抛 → 轮询 catch 吞掉 →
  15s 后再来一遍。每轮探测墙钟上界 ≈ 最多 3 个 base 并发 × 2 候选串行 × 1.5s ≈ **3s/节点**
  （全不可达时；有 401/HTTP 应答会提前返回）。节点间 for 串行，K 个死节点一轮 ≈ **K × 3s**。
  埋点注释（:577-579）自证快速档 200ms 实测付过 1.2s——主 isolate 忙时超时回调排后，
  实际上界还会超。
- **放大路径**：任一节点有缩略图任务在跑 → 全列表进入 2s 档（`vm_remote.dart:40`），
  死节点探测频率同步升到每 2s 一轮，K × 3s 的探测串几乎首尾相接；且探测本身占用主
  isolate 事件循环回调，正是 :18 注释说的「这条链一慢就会连带拖住首屏取数」。
- **量级**：K=3 死节点 + 1 活跃节点 ≈ 每轮 9s 串行探测，2s 档下探测流量常驻；
  每次探测 = LAN/WAN 并发 + 候选端口串行，最多 6 个 HTTP 往返/节点/轮。
- **建议修法**：① 轮询列表先过滤 `isNodeCircuitBreaked` / `nodeConnectivity != true` 的节点
  （复活交给已有的 `recheckOfflineNodes`，进页面/手动刷新时才付）；② 节点间 `Future.wait`
  并发；③ 对连续失败节点做指数退避（15s → 60s → 300s），成功一次即复位。
- **风险**：过滤后死节点复活期间的进度不显示——可接受，节点恢复时
  `libraryMutationTick` 会触发全量刷新重新纳入。改动只涉及 VM 轮询函数，风险低。

### H2. 单个「活着但慢/挂起」的节点把远程刷新整体拖到 ~2 分钟量级，且期间远程刷新被互斥跳过

- **位置**：`lib/view_models/media_library_vm_remote.dart:69-71`（`Future.wait` 等**全部**节点）；
  `node_settings_service.dart:1553-1597`（候选 URL 串行 + 忙重试 `index--`）；
  :1611-1628（失败后 `_quickProbeNode`）；:1644-1685（quick probe **双层串行 for**，
  每个候选 1.5s，最多 2 base × 2 URL = 4 × 1.5s = 6s）；
  `media_library_vm_refresh.dart:148`（`isLoadingRemote` 互斥）、:168-171（完成才更新节流时间戳）。
- **触发时机**：节点进程活着但业务动作不应答（磁盘忙、SMB 卷挂起、worker 被占满排队）——
  与「彻底离线」不同：ping 有回应不熔断，业务请求 receiveTimeout 12s 才失败。
  `get_thumb_progress`/`list_*` 均无专属超时档（`_nodeCallOptionsForAction` :2001-2023
  只给 novels/manga/import 放宽，媒体动作全用默认 12s）。
- **量级估计**（单节点单动作上界，LAN+WAN 各带隐式端口候选 = 最多 4 URL）：
  - 纯挂起：4 × 12s = 48s + quick probe 6s ≈ **54s**；
  - 持续 503（节点忙）：每 URL 3 次尝试 × 12s + 0.45s 退避，4 URL ≈ **146s ≈ 2.4min**；
  - 三路元数据并发取 max，不叠加；但 `recheckOfflineNodes` 在 `refreshRemoteLibrary`
    **之前** await（`vm_refresh.dart:162-164`），其自身上界另加 ≈ 0.4s + 3s（见 M1）。
  - 期间 `isLoadingRemote=true`，后续进页面刷新全部被 :148 直接 return；手动刷新
    `refreshAll` 又合流到同一个 `_refreshAllFuture`（`vm_refresh.dart:115-119`）——
    远程栏最长 ~2.5 分钟不更新。轮询侧同理：串行 for 中一个挂起节点每轮吞 54s+。
- **建议修法**：① 给 `get_thumb_progress` 这类轻轮询动作配短超时档（connect 2s / receive 3s），
  失败即跳过本轮；② 忙重试遵守节点已发的 `Retry-After: 1`（`mod.rs:193`）而不是立刻
  150ms 重试同一地址；③ 候选 URL 兜底只对**连接层**失败启用（现在 receiveTimeout 也换地址
  重试，:1709-1717——节点活着只是慢时，换一个地址照样慢，纯浪费 12s × 候选数）；
  ④ `refreshRemoteLibrary` 改为逐节点到货逐节点落地（每节点完成即 assignAll 增量），
  别让 `Future.wait` 的全屏障把快节点的数据也扣住。
- **风险**：③ 收窄重试面可能漏掉「LAN 通但反向代理只挂某一路线」的罕见拓扑；
  ④ 增量落地要处理节点删除时的清理。均限于服务层/VM，不动协议。

---

## 中优先级

### M1. 离线复探是远程刷新的前置 await：离线节点多时首屏远程栏白等 ~3.4s+

- **位置**：`media_library_vm_refresh.dart:160-164`（顺序刻意为之，注释说明熔断位挂着时
  `fetchNodeMediaMetadata` 直接抛）；`node_settings_service.dart:271-295`
  （`recheckOfflineNodes`：stale 节点 `Future.wait` **并发**，:283）；
  :503-571（`checkNodeConnectivity`：LAN/WAN 快速档并发 200ms → 不通过再确认档并发 1.5s）。
- **判定**：**并发已做对**——K 个离线节点墙钟不随 K 线性增长。上界 =
  快速档 0.2s × 2 候选串行 + 确认档 1.5s × 2 候选串行 ≈ **3.4s**（全不可达；
  主 isolate 忙时实测会超，见 :577-579 埋点）。全在线时零流量（:279-281）。
- **问题**：这 3.4s 是**所有**节点远程数据的前置串行段——哪怕 5 个节点里 4 个健康、
  1 个死，健康节点的取数也要等死节点探测完才开始。
- **建议修法**：把复探改成按节点并行推进：每个 stale 节点「复探 → 成功则取数」独立成链，
  健康节点直接取数，最后汇合。或者简单版：`recheckOfflineNodes` 不 await，
  让 `refreshRemoteLibrary` 先跑（健康节点不受影响），复活节点靠 `libraryMutationTick`
  补一轮（该机制已存在，:293）。
- **风险**：简单版会让复活节点多付一轮全量刷新（tick → `refreshAll`），量大时可先做按节点并行版。

### M2. 缩略图轮询节点间串行 + 无失败退避（与 H1/H2 叠加的调度缺陷）

- **位置**：`lib/view_models/media_library_vm_remote.dart:23-37`。
- **触发时机**：每 2s（忙）/15s（闲）一轮。健康 LAN 下单节点 `get_thumb_progress`
  往返几 ms，N 节点串行一轮几十 ms，**纯健康场景不构成问题**；但任何一个节点慢/死，
  整轮墙钟 = Σ每节点耗时（上界见 H1/H2），`_remoteThumbPolling` 防重叠只是把后续轮次顺延。
- **建议修法**：节点间 `Future.wait`（进度只是求和，天然可并发）；连续失败节点退避。
  与 H1 的过滤修法合并成一个改动即可。
- **风险**：并发后瞬时连接数 +N，远小于节点 128 上限，无风险。

### M3. 深度搜索远程预热：为拿 file_path 拉整份条目 JSON，且节点已有现成路径快照表没暴露成 action

- **位置**：`lib/view_models/media_library_vm_search.dart:270-290`
  （`_fetchRemoteItemPaths` → `fetchNodeMediaCollectionItems`，取回后只用 `file_path` 一个字段）；
  `rust/src/node_server/handlers.rs:219-242`（`get_media_collection_items` 序列化
  id/title/kind/宽高/时长等全字段）；
  `rust/media_collection/src/api.rs:2971-2987`（`get_collection_file_paths`：路径快照表
  快路径 + 懒回填，**已存在但仅 FFI 导出**，`handlers.rs` 无对应 action）。
- **触发时机**：深度搜索扫到远程集合且标题未命中时逐个入队（`vm_search.dart:202`）。
- **量级**：600 个远程集合 × 每集合几千条 × 每条 ~300B 全字段 JSON ≈ 数百 MB 级传输 +
  客户端 `Map.from` 双份解析；实际只需要路径字符串（约 1/4 体积）。批次并发 4、
  每批到货 600ms 节流重算（`media_library_viewmodel.dart:209-238`）——调度已对，
  浪费在载荷。另外正缓存 `_remoteCollectionItemPaths` 无条目数上限（:185），
  38 万条路径全字符串常驻 VM 内存（每条约百字节，几十 MB 级）。
- **建议修法**：节点新增 `get_collection_file_paths` action（一行转发到已有 Rust 函数），
  客户端预热改调它；老节点没有该 action 时回退现有全量接口（`_fetchNodeMediaMetadata`
  已有「老节点缺 action 宽容」先例）。正缓存可加 LRU 上限（如 50k 条路径）。
- **风险**：新老节点混布期需要回退分支；改动跨 Dart/Rust 两侧但都是加法，低风险。

### M4. 503 负缓存跨防抖窗口反复清空：持续过载时同一批集合反复重试

- **位置**：`media_library_viewmodel.dart:487-491`（每次 `appliedSearchQuery` 变化都
  `_resetRemotePathSession`，注释明说「上一轮失败的集合值得再试」）；
  `vm_search.dart:294-297`（清负缓存 + 清队列）；:283-289（失败入负缓存）；
  `node_settings_service.dart:1584-1589`（传输层已先做 2 次忙重试）。
- **判定**：**同一查询词内**负缓存工作正常，无重复请求、无饿死（`_requestRemoteItemPaths`
  :303-314 四重去重齐全；`_pumpRemoteItemPaths` :246-267 单流水线 + 退出搜索清队列）。
  问题只在**换词**时：280ms 防抖后每个新词都清负缓存，若节点持续 503（例如正被导入/
  缩略图打满），用户每敲一个词就重新对同一批失败集合发起「2 次传输层忙重试 + 失败」，
  每次失败集合还各自经历完整候选 URL 流程。不是死循环，但过载期是无用流量放大器。
- **量级**：每词 × 失败集合数 F × 3 次尝试；F=100、连续输入 5 个词 ≈ 1500 个请求打向
  已经说「我忙」的节点。
- **建议修法**：负缓存带 TTL（如 30s 内换词不清），或按节点记「忙」状态：某节点上一轮
  成片 503 时，新词轮次直接跳过该节点预热并延迟重试。
- **风险**：TTL 内节点恢复了也不重试，深度搜索少命中几个集合——可接受，下一轮 TTL 过期自愈。

### M5.（跨模块移交，任务 B 范围）`list_novels` / `search_all_novels` 在 async worker 里逐本读封面 + base64

- **位置**：`rust/src/node_server/handlers.rs:470-511、:513-559`；
  `encode_cover_base64` :1635-1653（每本 `exists()` + `metadata()` + `fs::read` ≤256KB + base64），
  外加 `load_chapter_count_map` :1601-1608 每次整读 JSON 文件。
- **触发时机**：远程小说列表/搜索。这些同步 IO 直接跑在 `dispatch_action` 的
  tokio worker 上（未 `spawn_blocking`，对比 `media_handler.rs:227、:250` 已正确移入）。
  N 本书 = 3N 次文件系统调用；封面在 SMB 卷时每次都是网络往返，且占住共享 runtime
  worker（`mod.rs:34-52`，worker 数 clamp 4..128），拖累同节点其它请求。
  客户端为此给了 45s receiveTimeout（`node_settings_service.dart:2002-2006`），侧面印证慢。
- **归属**：novel 链路属任务 B 审计范围，此处仅记录证据供 Lead 合并，不展开修法。

---

## 低优先级

### L1. `list_directories` 逐 entry `is_dir()`，SMB 上是逐文件 stat

- **位置**：`rust/src/node_server/handlers.rs:437-444`（`e.path().is_dir()` 丢弃了
  `DirEntry::file_type()` 的现成信息，每次都可能触发一趟 stat）。
- **触发时机**：远程上传选目录浏览器，用户交互频率，非首屏/轮询。
- **量级**：一个几百子目录的 SMB 目录 = 几百趟网络往返。
- **建议修法**：改用 `e.file_type().map(|t| t.is_dir())`（read_dir 已带回类型，Windows/
  SMB 多数场景免额外 stat）；顺手可移入 `spawn_blocking`。
- **风险**：极低。

### L2. `rescan_media_covers` 全量时在请求线程同步收集全部条目

- **位置**：`handlers.rs:130-159` + `spawn_import_thumbnail_generation` :1564-1587
  （逐集合 `get_media_collection_items` 收集文件路径——索引快路径，但 600 集合全量
  仍是几百个读事务 + 几十万条 clone，发生在返回 `count` 之前）。
- **触发时机**：用户手动「重扫封面」，低频；客户端 `import_media_folder` 有 10min
  超时档兜着，但 `rescan_media_covers` 用默认 12s——大库全量重扫可能客户端先超时。
- **建议修法**：先回 `count`，文件收集移入后台线程（与缩略图生成同线程即可）。
- **风险**：进度总数上报时机变化，需确认 `THUMB_TOTAL` 语义。

### L3. 聚合表旧库补齐分支的一次性整表（设计如此，仅备案）

- **位置**：`handlers.rs:162-172`（`list_media_collections` 调 `get_all_collection_aggregates`）；
  `rust/media_collection/src/api.rs:2824-2874`（缺行时 `ensure_items_loaded` 整表补算一次）。
- **判定**：派发计划已定性「设计如此，不动」。节点侧旧库升级后**首次**
  `list_media_collections` 仍会付一次 1.3~13.5s 整表代价，且可能顶到客户端 12s
  receiveTimeout → 换地址重试再付一遍。属一次性迁移成本，不立项；若用户反馈
  「升级后第一次进远程库超时」，根因在此。

---

## 查过且未发现问题的链路

| 链路 | 结论 |
|------|------|
| `refreshRemoteLibrary` 并发结构 | 节点间 + 节点内三路均已 `Future.wait` 并发（`vm_remote.dart:69`、`node_settings_service.dart:359`），单节点失败只落自己（:155-169），**结构无问题**；问题在 H2 的超时/重试上界 |
| `recheckOfflineNodes` 并发度 | stale 节点并发探测（:283），不随节点数线性放大；全在线零流量。剩余问题只是 M1 的前置串行段 |
| 预热快照机制 | `fetchNodeMediaMetadata` 60s 新鲜度 + 取用即失效 + 残缺快照不入缓存（:297-343），无重复拉取 |
| `get_thumb_progress` 节点侧 | 两个 AtomicU64 读（`media_handler.rs:16-21`），零 IO；`ping` 不排队（`mod.rs:420`）。重的是客户端调度（H1/M2），接口本身干净 |
| `list_media_collections` 节点侧 | 已改聚合表（`handlers.rs:165-172`），无整表冷加载（L3 一次性补齐除外） |
| `get_media_collection_items` 节点侧 | 索引快路径 `db_get_many`（`api.rs:2583-2603`），None 分支整表仅旧库首访回填，设计如此 |
| `list_media_folders` / `list_smart_folders` | 进程级 OnceLock 内存缓存（`api.rs:2065、:2182、:3963`），非 5 分钟释放的条目缓存，冷加载仅进程首访且表小 |
| 深度搜索限速流水线调度 | 并发 4 + 单流水线 + 四重去重 + 600ms 合并重建 + 退出搜索清队列（`vm_search.dart:238-314`、`viewmodel.dart:225-238`），无饿死、无同词重复请求；剩余问题见 M3/M4 |
| `_callNode` 在途去重 | 按 nodeId+action+params 单飞（:1521-1534），封面/元数据并发不会重复打 |
| 503 与熔断的语义区分 | 节点忙回 503 不算死节点（`mod.rs:175-199`、`node_settings_service.dart:599-606`），不会误熔断 |
| `get_all_collection_stats` / `get_all_collection_live_stats` | **任务 A 处理中**，本文不深究 |

## 建议派发顺序

1. **H1+M2 合并**一个改动（轮询过滤熔断节点 + 节点间并发 + 失败退避）：只动
   `vm_remote.dart` 一个函数，收益/风险比最高。
2. **H2**（轻动作短超时档 + 忙重试遵守 Retry-After + receiveTimeout 不换地址）：
   只动 `node_settings_service.dart`。
3. **M3**（节点暴露 `get_collection_file_paths` action + 客户端预热改载荷）：跨两侧，加法改动。
4. M1/M4/L1/L2 视复核结果立项；M5 移交任务 B 报告合并。