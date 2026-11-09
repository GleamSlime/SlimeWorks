# 资源库模块性能审计报告（任务 B）

> 2026-11-09 · 基线 HEAD=3a42a40 · 只读审计，未改任何代码。
> 审计对象：novel_reader / game_library / music_player / manga_module+MangaDownloadService /
> ledger_module / extract_module / sentry_log。
> 按三类根因模式找同类：① 整表冷加载 ② 首屏 await 重活 ③ build 同步 FFI / 高频轮询打重接口。
> 每条给出：文件:行号、触发时机、量级估计、建议修法（对照 e64b330/6d82919/1c71906 定式）、风险。
> 分级口径：**高**=实测可预期秒级卡顿或持续性 CPU 浪费；**中**=规模增长后线性恶化 / 条件触发的重活；**低**=量级有限但模式相同。

---

## 发现总览

| # | 级别 | 模块 | 一句话 |
|---|------|------|--------|
| 1 | 高 | game_library | Windows 启动器模式追踪：整个游戏会话期间每 3s 起一个 PowerShell 枚举全部进程 |
| 2 | 高 | sentry_log | 「分页」是假的：每次查询把全部事件 JSON 反序列化 + 内存过滤 + 排序，且无保留期清理 |
| 3 | 高 | novel_reader | 远程书架首屏 await 串行拉每个节点的全部封面 base64（N 节点 × M 本 × ~40KB） |
| 4 | 高 | music_player | `get_playlist_items` 每次读整张 music_items 表再过滤，且完全绕过已有条目缓存；sync FFI 主 isolate 执行 |
| 5 | 中 | novel_reader | 书架/封面卡 build 期间 O(全部书籍) 过滤 + 逐封面 `existsSync`（外置/网络卷放大） |
| 6 | 中 | music_player | 进页面 `_loadPathMappings` 同步 FFI 递归扫描每个映射目录的全部文件（逐文件 stat，不限深度） |
| 7 | 中 | game_library | 进库页收藏状态 N+1：每个游戏一次串行 FFI + SQLite 查询；分类页每次过滤全量重查 |
| 8 | 中 | manga_module | 首页封面预取无并发上限一次性发出全部 HTTP，且 60 条 LRU 缓存互相驱逐 |
| 9 | 中 | extract_module | 选完目录即同步 FFI 递归扫描（限深 32）全部压缩包，挂 UI isolate |
| 10 | 低 | music_player | 元数据修复完成后再拉一次整表；波形/CUE 每次切歌重付（有磁盘缓存，量级有限） |
| 11 | 低 | novel_reader | TXT 章节「按需加载」实为整书缓存克隆再取一章；内容缓存无上限不驱逐 |
| — | 无问题 | ledger_module | 聚合查询有索引、列表有 LIMIT/OFFSET（详见下文核查记录） |
| — | 无问题 | game_library 统计 | 首页/统计 SQL 走索引或小表聚合 |
| — | 无问题 | manga 列表/搜索 | API 层一页一请求，无 N+1 |
| — | 无问题 | extract 轮询 | 200ms 轮询打的是纯内存小对象，符合定式 |
| — | 无问题 | music `_getSystemProxy` | 已缓存（`_proxyChecked`），每 VM 生命周期只跑一次 scutil |

---

## 1.【高】game_library：启动器模式追踪轮询每 3s 起 PowerShell 全进程枚举

- **文件**：`lib/core/services/game_process_tracker.dart:19`（`_pollInterval = 3s`）、
  `:158-183`（`_findProcessesInDir`：`powershell -NoProfile ... Get-Process | Where Path.StartsWith(dir)`）、
  `:186-196`（`_pollUntilDone`：while 循环直到无进程或 **24 小时**超时）。
- **触发时机**：轮询（后台常驻，游戏运行全程）。主进程 45s 内退出即判启动器模式
  （`:97`），之后整个游戏会话都走 `_pollUntilDone`。
- **量级**：Windows 上每次 `Get-Process`（无 `-Name` 过滤）要枚举全部进程并读 `Path`
  （对受保护进程逐个抛异常），单次实测常见 0.5~2s CPU；每 3s 一次、最长 24h ⇒
  玩 4 小时 ≈ 4800 次 PowerShell 冷启动。这是持续性后台 CPU 浪费，还会与游戏抢核。
  非启动器路径（`_waitForPidExit` 每 2s `tasklist /FI` / `kill -0`）开销小得多，属正常。
- **建议修法**：进入 `_pollUntilDone` 后先拿到子进程 PID 列表，改用与主路径相同的
  「按 PID 探活」（tasklist /FI 或 OpenProcess），只在全部 PID 消失时才重新做一次目录扫描
  （游戏可能换 exe）；目录扫描间隔放宽到 15~30s 自适应退避。按本仓架构约定进程枚举应下沉
  Rust（现有 `game_library_launch_game` 已在 Rust 层），可用 sysinfo/WinAPI 一次查询代替子进程。
- **风险**：改按 PID 探活后，游戏重启换 PID 的瞬间可能误判退出——保留「PID 全灭后再扫一次
  目录、连续 2~3 次为空才结束」的确认逻辑即可。

## 2.【高】sentry_log：query_events / get_stats 全表反序列化，分页只在最后 skip/take

- **文件**：`rust/sentry_log/src/storage.rs:111-201`（`query_events`：遍历
  `project_events` 前缀**全表 iter**（redb 无前缀裁剪，`:121-132` 逐 key `starts_with`）
  或 `events` 全表，把每条 JSON `from_str::<SentryEvent>` 后推入 Vec；再 retain 过滤
  （关键词还逐条 `format!` + `to_lowercase`，`:157-181`）；排序后才 `skip(offset).take(limit)`）；
  `:317-362`（`get_stats`：又一轮全表反序列化只为数 level）。
  Dart 侧 `lib/view_models/sentry_log/sentry_log_viewmodel.dart:57` 首屏
  `Future.wait([loadProjects, loadStats, loadEvents])` 一次进页面打两遍全表。
- **触发时机**：首屏 await + 每次翻页/换过滤条件（`loadEvents` 每次都是一轮全表）。
- **量级**：Sentry 事件单条 JSON 可达数 KB~数十 KB（含 exception/stacktrace/breadcrumbs）。
  该模块**没有任何保留期/条数上限清理**（storage.rs 全文无 prune/retention/MAX_EVENTS），
  事件只增不减。1 万条 × 10KB = 100MB JSON 反序列化，每页一次；10 万条即秒级起。
  与媒体库 38 万条整表冷加载同构，只是这里连内存缓存都没有——**每次翻页都重付**。
- **建议修法**：对照定式：① 建按时间排序的二级索引表（key=`timestamp:event_id`），
  查询用 redb `range().rev()` 直接取一页再回表 `db_get_many`；level/project 过滤建独立
  索引表或复合 key；② `get_stats` 改增量维护的聚合小表（store_event 时 +1）；
  ③ 补保留策略（如默认 90 天 / 上限 5 万条，写后台限频清理）。
- **风险**：翻页语义要与旧 total 一致；存量库需一次性回填索引（懒回填 + 幂等标记，
  参照 `media_collection_item_index` 的做法）。

## 3.【高】novel_reader：进书架首屏 await 串行拉全部远程节点的全量封面 base64

- **文件**：`lib/view_models/novel_library_viewmodel.dart:397-398`
  （`onInitAsync` 末尾 `await refreshRemoteNovels()`）、`:417-453`（`for node in
  enabledRemoteNodes` **串行** `fetchNodeNovels`）；节点侧
  `rust/src/node_server/handlers.rs:470-510`（`list_novels` 对**每本书**读封面文件并
  `encode_cover_base64` 塞进列表 JSON）。Dart 侧 `:514-518` 再拼成 data URI 存进
  `NovelMetadata.coverPath`。
- **触发时机**：首屏 await（进书架页 `onInitAsync` 链上）+ 每次
  `libraryMutationTick` 触发（`:393-396`，任何库变更事件都整轮重拉）。
- **量级**：封面压缩上限 400×600 JPEG ≈ 20~60KB，base64 再膨胀 33%。
  远程 500 本 ≈ 20~40MB JSON 单节点；N 个节点串行 = N × (RTT + 传输 + 节点侧逐本读盘)。
  100M 网络下单节点也要数秒，节点在外置盘休眠时再加 4s 唤醒。这与「首屏 await 大传输」
  模式完全同构，且 mutation worker 让它反复重付。
- **建议修法**：① `refreshRemoteNovels` 移出首屏 await（先显示本地书，远程到货再刷新），
  节点间并发 + 失败熔断（复用媒体库远程链路的做法）；② `list_novels` 元数据与封面分离：
  列表只带 `cover_url`（走 `GET /node/media` 类流式接口按需取），或加 `with_cover=false`
  参数 + 封面单独批量接口；③ mutation tick 加防抖/增量（只拉变更节点）。
- **风险**：移动端离线场景 data URI 目前是「一次拿全就能离线显示」，改按需后要接受
  远程封面首见时闪占位图；`remote:` 合成 id 的封面链路（reader/detail）要一并核对。

## 4.【高】music_player：get_playlist_items 整表读 + 绕过缓存 + 主 isolate 同步 FFI

- **文件**：`rust/music_player/src/api.rs:333-346`（`get_playlist_items`：
  `db_list_values(item_table())` 读**整张** music_items 表 → 逐条 JSON 反序列化 →
  `filter(playlist_id)`；**没有**走 `:348-367` 已有的 `get_all_music_items` 内存缓存）。
  FFI 导出 `rust/src/api/music_player.rs:312-313` 是 `#[frb(sync)]`——在主 isolate 执行。
  Dart 调用点：`lib/view_models/music_player_viewmodel.dart:524`（选列表）、`:551`（元数据
  修复后重拉）、`:1285/:1398`（改条目/收藏后重拉）、`playlist_sidebar.dart:342`（批量识别）。
- **触发时机**：首屏（onInit → `_loadPlaylists` → `selectPlaylist` → `_loadPlaylistItems`）
  + 每次切列表 / 收藏一首歌 / 修复完成。全部同步阻塞 UI 线程。
- **量级**：所有播放列表的条目共用一张表。1 万首 × ~1KB JSON = 10MB 反序列化 + FFI 序列化
  在主 isolate；哪怕只看 50 首的列表也读全表 1 万条。收藏/取消收藏一首歌（`:1393-1398`）
  也会整表重读一遍。与媒体库模式 1 同构，且因为 sync FFI 直接卡帧。
- **建议修法**：最小改动：`get_playlist_items` 改调 `get_all_music_items()`（已有缓存，
  写路径已维护失效）；进一步：按 `playlist_id` 建条目索引表（id 列表）+ `db_get_many`
  批量取（完全对照 1c71906 定式），并把 FFI 改 async（Dart 调用点已是 async 上下文）。
- **风险**：缓存失效点分散在 15 处 `music_items_cache` 写入，改索引表后要把这些写路径
  同步维护索引；改 async 要重新生成 FRB 并核对所有调用点（多数已 await，改动面可控）。

## 5.【中】novel_reader：书架卡片 build 期间 O(N) 过滤 + 逐封面 existsSync

- **文件**：`lib/view_models/novel_library_viewmodel.dart:100-134`
  （`getFolderCover/getFolderCovers/getFolderNovelCount` 每次都 `_getBooksInFolder` =
  全量 `novels.where(...)` + `remoteNovels.where(...)`，再逐封面 `File.existsSync`）；
  调用点 `lib/pages/collection/library/components/library_folder_card.dart:202`（build 内
  取 count）、`:242-261`（**Obx build 内**取 covers + 每格再 `existsSync`）；
  `collection_library_screen.dart:49-59`（`_isBookLost/_isFolderLost` 每张卡 build 一次
  existsSync，:1074/:1091 挂进卡片构造）。
- **触发时机**：build（每个文件夹卡每次重建都执行；hover setState、选择态、任何 Rx
  变更都会触发）。
- **量级**：F 个文件夹 × N 本书 = O(F·N) 过滤每帧 + 每卡最多 6+3 次 existsSync。
  本地盘 µs 级尚可；封面在 SMB/外置卷时每次 stat 一趟网络往返（媒体库实测同款），
  10 个文件夹卡重建一轮 = 近百次网络 stat，帧直接掉。`filteredItems`/`displayedItems`
  getter 本身也是每帧全量重算重排序（`:219-288`），N 千本时可感知。
- **建议修法**：文件夹→书籍列表/封面存在性做成派生缓存（novels/remoteNovels 变更时
  失效重算一次，对照 `_itemPathsEpoch` 做法）；存在性检查移出 build（后台批量 stat +
  结果缓存，卡片只读结果，未命中显示占位不 await）。
- **风险**：封面被外部删除时「丢失」标记会延迟到下一轮后台刷新，可接受；注意 GetX
  4.7.3 Obx 依赖收集坑（派生缓存的失效通知别在 initState 里读 rx.value）。

## 6.【中】music_player：进页面同步递归扫描全部路径映射目录

- **文件**：`lib/view_models/music_player_viewmodel.dart:87-118`（`_loadPathMappings`：
  onInit 即调（`:225`），对每个持久化映射目录先 `Directory.existsSync` 再
  **sync FFI** `scanPathMapping`）；Rust 侧 `rust/music_player/src/scanner.rs:395-476`
  （不限深度递归 read_dir，**每个文件一次 `fs::metadata`**（`:447`），整棵树节点
  全部返回）；FFI `rust/src/api/music_player.rs:835-836` `#[frb(sync)]`。
- **触发时机**：首屏（VM onInit，同步阻塞 UI isolate）+ `refreshPathMapping`。
- **量级**：映射的是「拖拽导入的文件夹」，通常整个音乐库根目录。1 万文件 = 1 万次
  stat + 1 万节点树序列化，本地盘 ~百 ms，SMB 卷 = 1 万趟往返（分钟级），外置卷再加
  4s 唤醒。每次进播放器页都重付（无缓存、无 mtime 短路）。
- **建议修法**：① 改 async FFI + 首屏不 await（先渲染空树，到货再刷新）；② 树快照落
  盘 + 目录 mtime 校验短路（对照路径快照表定式）；③ `file_size` 懒取（展开节点时再
  stat），首扫只拿 `read_dir` 自带的 file_type/name。
- **风险**：快照与磁盘不一致需要「刷新」按钮兜底（已有 `refreshPathMapping`）；移动端
  该功能桌面专属则无影响。

## 7.【中】game_library：进库页收藏状态 N+1 串行 FFI；分类页全量重查

- **文件**：`lib/view_models/game_library/game_library_library_viewmodel.dart:62-71`
  （`refresh`：`for (g in all) await _service.isFavorite(g.id)`——**串行** N 次
  sync FFI，每次一条 `SELECT COUNT(*) FROM game_categories WHERE ...`，
  `rust/game_library/src/api.rs:860-870`）；
  `lib/core/services/game_library_service.dart:163-174`（`getGamesByCategory`：全量
  `getGames()` + 每游戏一次分类查询，虽 `Future.wait` 并行但 sync FFI 实际仍串行执行）。
  首页/列表还挂了 `sessionSavedCount` worker（`game_library_home_viewmodel.dart:25-27`），
  每次游戏退出再整轮 refresh 一遍。
- **触发时机**：首屏 await + 每次会话保存事件。
- **量级**：G 个游戏 = G 次 FFI 往返 + G 条 SQL。SQLite 本地小查询单次 ~0.1ms，
  500 游戏 ≈ 50~100ms 尚可，2000+ 游戏或低端机上开始可感知；模式上就是
  「一张 `SELECT game_id FROM game_categories WHERE category_id='system:favorites'`
  能解决的事拆成 N 次」。
- **建议修法**：Rust 加 `game_library_get_favorite_ids()` 一次返回集合（或 get_games
  的 SQL 直接带 `is_favorite` 列——分类表有 `idx_game_categories_category` 索引）；
  分类过滤同理下推 SQL WHERE。
- **风险**：低；纯读路径新增接口，注意 FRB 重生成。

## 8.【中】manga_module：首页封面预取无并发上限 + 60 条 LRU 自我驱逐

- **文件**：`lib/pages/manga/view_models/manga_home_viewmodel.dart:40-44,90-93`
  （首屏拿到 collections+random 后把**全部** thumb 一次性 `prefetchImages`）；
  `lib/core/services/manga_service.dart:287-294`（for 循环对每张图 `fetchImageBytes().ignore()`
  ——无并发闸门，全部同时起飞）、`:84-85`（`_kImageCacheMaxSize = 60`）。
- **触发时机**：首屏后台（不阻塞 await，但同时抢占带宽/连接池）+ 每次「换一批」/加载更多。
- **量级**：首页 collections（每个含若干本）+ random 一批，轻松 100~200 张封面同时发
  HTTP；缓存只容 60 张 ⇒ 预取完前面的已被驱逐，卡片真正显示时（`MangaImageView` 再走
  `fetchImageBytes`）**大概率二次下载**。Pica 图片单张 100~500KB，一轮首页 = 双倍
  流量 + 连接风暴，慢分流下把正文 API 请求也挤慢。
- **建议修法**：预取加并发上限（4~6）+ 只预取可视区/即将滚入的卡片；LRU 上限与
  「首页卡片数 + 阅读器预取 20 张」匹配（如 200），或按字节预算；预取结果与显示共用
  同一缓存 key（现已同 key，保住不被驱逐即可）。
- **风险**：低；注意内存上限（200 × 300KB ≈ 60MB，可接受，或改磁盘缓存）。

## 9.【中】extract_module：选目录即同步 FFI 递归扫描压缩包

- **文件**：`lib/pages/tools/components/extract_params_dialog.dart:401-431`
  （选完目录立刻 `_scanArchives`）；`lib/core/services/extract_service.dart:194-212`
  （`scanArchives` 调 **sync FFI** `extractScanArchivesJson`，`rust/src/api/extract.rs:28-29`）；
  `rust/extract_module/src/extractor.rs:295-375`（递归 read_dir 限深 32、跳软链，
  每个命中的压缩包一次 `fs::metadata`）。
- **触发时机**：用户选目录后的「准首屏」——结果挂在弹窗 setState 前，但 FFI 是 sync，
  **整个扫描期间 UI isolate 冻结**（弹窗连 `_isScanning` 转圈都画不出来）。
- **量级**：解压目标常是下载盘/网络卷大目录。1 万文件的树 = 1 万次 read_dir 条目 +
  命中包 stat；SMB 卷分钟级，期间整个 App 无响应（不是这一个弹窗）。
- **建议修法**：`extract_scan_archives_json` 改 async FFI（Dart 调用点已 async），
  Rust 内部可再加分批进度（复用 PROGRESS_STATE 模式）。扫描逻辑本身防御做得对
  （限深/跳软链），只需移出主 isolate。
- **风险**：低；FRB 重生成 + 弹窗取消时丢弃过期结果（代际号）。
- **另**：进度轮询 `extract_service.dart:255`（200ms `extractGetProgressJson`）打的是
  纯内存小对象（`rust/extract_module/src/api.rs:125-130`），**符合定式，无问题**；
  密码列表 `extract_list_passwords_json` 整表但规模=用户手存密码数，无问题。

## 10.【低】music_player：元数据修复后二次整表；切歌波形/CUE 重付

- `music_player_viewmodel.dart:544-552`：`repairMissingMetadata`（Rust
  `api.rs:1004-1058` 内部又 `get_playlist_items` 整表一遍 + 逐缺失文件读音频标签）完成后
  `:551` 再 `getPlaylistItems` 整表一遍。修 #4 后此处自动受益；修复本身是后台 Future、
  只处理缺失条目，设计合理。
- `:1565-1583` 波形：`extractWaveform` 有磁盘缓存 + 流式解码
  （`rust/src/api/music_player.rs:543-561`），且代际号防过期覆盖——已按定式做，
  仅首次解码一首歌付一次成本，无问题。`:1595` CUE `existsSync` 每次切歌一次，量级 1 次
  stat，可忽略（网络卷曲目才有感）。
- **触发时机**：切歌/切列表。**修法**：随 #4 一并解决；无需单独立项。

## 11.【低】novel_reader：TXT「按需加载」实为整书克隆；内容缓存无上限

- **文件**：`rust/novel_reader/src/api/mod.rs:645-668`（TXT `get_chapter_content` →
  `get_novel_content` 整书缓存命中后 `content.clone()` **整本**再取一章——
  `:554` 缓存命中路径同样 clone 整书过 FFI）；`:97-102` `CONTENT_CACHE` 为
  HashMap，无条数/字节上限、无 LRU（仅手动 `clear_novel_cache`）。
  Dart 首屏 `novel_reader_viewmodel.dart:195` `await getNovelContent` 拿整书
  （EPUB 只有章节目录 `parser_epub.rs:86-91` content=None，没问题；**TXT 章节含全文**
  `parser_txt.rs:121-207`）。
- **触发时机**：打开 TXT 书首屏 await + 每次切章（整书 clone + FFI 序列化）。
- **量级**：网文 TXT 常见 5~20MB；每次切章 clone + 序列化 20MB ≈ 几十 ms 级、内存峰值
  ×3。读了 50 本大 TXT 后缓存常驻数百 MB 不还。单书体验尚可，故列低。
- **建议修法**：缓存命中路径按章切片返回（`get_chapter_content` 直接从缓存取该章，
  不 clone 整书）；`get_novel_content` 对 TXT 返回 content=None 的章节目录（与 EPUB
  对齐，阅读器已按 `getChapterContent` 拿正文）；缓存加 LRU 上限（如 5 本/100MB）。
- **风险**：`search_in_novel`/关键词打标依赖整书 content（`api_search.rs:97-110`、
  `mod.rs:302-318`），改章节目录后这两处要改走逐章接口；Dart 端
  `chapters.value` 有没有直接读 content 的 UI 需核对。

---

## 未发现问题的链路（核查记录）

### ledger_module —— 未发现问题
- 概览首屏 `ledger_viewmodel.dart:46-77`：`statsSummary/statsByDay/statsByCategory`
  均带月份区间过滤，`transactions` 有 `idx_tx_date/idx_tx_status` 等 4 个索引
  （`rust/ledger_module/src/storage.rs:108-111`）；聚合 SQL 在 SQLite 内完成
  （`:874-998`），返回的是按天/按类的小结果集，不是整表出水。
- 最近流水 `list_transactions` 有 `LIMIT/OFFSET`（`:821-834`，默认 500、首页取 12）；
  明细页 `ledger_records_viewmodel.dart:157-158` 按 `_pageSize` 增量分页。
- 收信调度 `scheduler.rs:80-91`：常驻线程 1s 分片 sleep，规则到期才做重活，符合后台限频。
- 备注：`stats_by_month`（`:1002-1011`）的 `substr(bill_date,1,7) <= ?` 谓词吃不到
  `idx_tx_date`，是全表聚合——但账本量级（年千条级）下 ms 级，且只在统计页触发，不构成问题。

### game_library 统计/首页 SQL —— 未发现问题
- `game_library_get_home_page_data`（`rust/game_library/src/api.rs:754-848`）：
  最近游玩一条 JOIN + LIMIT 1，总数/时长走 COUNT/SUM，`play_sessions` 有
  `idx_play_sessions_game/start_time`（`db.rs:71-72`）。本地 SQLite、会话数量级
  （每游戏每天几条）下无全表扫风险。
- 游戏列表 `get_games`（`:174-241`）每行两个相关子查询，但有 game_id 索引，
  游戏库量级（百~千）无碍。
- 封面 `existsSync`（`game_library_home_screen.dart:316/352`、
  `game_library_screen.dart:1157`）每卡一次，封面存本地 App 目录，µs 级；
  仅当用户把封面指到网络卷才放大，未列为发现。
- `_getSystemProxy`（music）与 game 的 `windows_registry_proxy`：均为
  Client 构建期一次性调用 + 单例缓存（`api.rs:1355-1375`），无高频问题。

### manga_module 列表/搜索 API —— 未发现问题
- 一页一请求：`manga_get_comics_by_category/manga_search_comics/manga_get_favourites`
  （`rust/manga_module/src/api.rs:221-326`）都是单条 HTTP，无每卡片详情请求。
- 阅读器 `manga_reader_viewmodel.dart:120-133`：首屏只拉第一页图片 + 第一页章节，
  剩余章节 `_loadRestEps` 后台串行补齐（`getComicEpsAll`，失败退回部分），
  预取 `prefetchAhead` 上限 20 张——链路设计符合定式（问题只在 #8 的首页无上限预取）。
- MangaDownloadService：逐章下载/推送是用户显式排队的长任务，逐张 `exists` 是断点
  续传所需；`_persistMeta` 每章两次全量 JSON 写 SharedPreferences，条目数=下载过的
  漫画数，量级小。未发现需要立项的问题。

### novel_reader 本地书架元数据 —— 未发现问题（就「整表冷加载」而言）
- `get_library()`（`rust/novel_reader/src/api/mod.rs:182-203`）OnceLock 一次加载
  novels 元数据表后常驻，**没有**媒体库那种「空闲 5 分钟释放」机制；书量级（百~千）
  下首次加载 ms 级。元数据不含章节内容，进书架不解析任何书籍文件。
- 章节数有独立 `chapter_counts.json` 缓存（`novel_library_viewmodel_novel.dart:89-111`），
  只在导入/扫描后对**新书**补算（`:125-148`），不在首屏重算。
- 全库内容搜索 `search_in_all_novels_batched` 是用户显式触发的重活，有取消标志 +
  分批（`api_search.rs:164-299`），但注意 Dart 端一次 await 拿全部批次
  （`novel_library_viewmodel_actions.dart:268`），进度条实际动不了——属 UX 问题
  非本次三类模式，顺带记录不立项。

### extract_module 轮询 / 密码库 —— 未发现问题
见 #9 末尾说明。

### sentry_log 远程链路
- 远程节点查询走 `fetchRemoteLogs`（HTTP），分页参数原样透传节点侧同一
  `query_events`——#2 修好后远程链路同时受益，不另立项。

---

## 修复优先级建议（供 Lead 派发）

1. **#4 music get_playlist_items**（最小改动=改走已有缓存，一行级；彻底修=索引表）
2. **#2 sentry_log 真分页 + 聚合小表 + 保留期**（工作量最大，收益随数据增长）
3. **#1 GameProcessTracker 按 PID 探活**（纯 Dart 改动，Windows 收益立竿见影）
4. **#3 远程书架封面分离 + 出首屏 await**（跨 Dart/节点侧，需与任务 C 远程链路协调）
5. #6/#9（sync FFI 改 async，两处 FRB 重生成可合并一个任务）
6. #5/#7/#8（各自独立小任务）；#10/#11 随手修或挂起