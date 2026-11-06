# SlimeWorks 性能 · 隐藏 Bug · UI 修复台账

> 状态：**已落地的批次已合并进主干**（`a8e7d34` 与 `1dfc859` / `e9b9c59` / `43f09ce`）。
> 本文分三段：**① 已修复（含落点与验证方式）**、**② 待办（含精确文件行号与验收口径）**、
> **③ 回归清单**。第 ② 段是本轮评审确认「问题成立、但本轮刻意未改」的条目，
> 不是「猜测」；每条都附了核对过的代码位置，照着改即可。

---

## 0. 一句话结论

这轮改动把三件事分开了：**能当场改对的（崩溃、并发、脏色）** 已经改；
**需要协议变更或要换语言库（鉴权、上传落点白名单）** 单独列进 `docs/node_server_security.md`；
**本文第 ② 段** 是「性能/健壮性缺口」，改动小、风险低，但不属于本轮 UI 主题，留作待办。

---

## 1. 已修复（已完成，可供回归对照）

### 1.1 Flutter 侧

| # | 问题 | 根因 | 落点 | 验证 |
|---|------|------|------|------|
| F1 | 电量统计页退出时可能抛 `LateInitializationError` | 14 个 `late final StreamSubscription` 只在 `onInitAsync` 里赋值；`_service.ensureInitialized()` 未完成就退出页面时，`onClose()` 读未初始化的 `late` 字段 | `lib/view_models/power_stats_viewmodel.dart:121-134`（改可空）、`:327-346`（`?.cancel()`） | 进页面 → 立刻返回 → 反复 10 次无异常 |
| F2 | 远程缩略图进度空闲时仍在狂刷节点 | `Timer.periodic(2s)` 无条件轮询 `/node/call get_thumb_progress` | `lib/view_models/media_library_viewmodel.dart:438-441`（改一次性 `Timer` + `_scheduleRemoteThumbPoll`，启动点 `:650`）、`lib/view_models/media_library_vm_remote.dart:38-55`（生成中 2s / 完成或空闲 15s） | 空闲时抓节点请求数，应≈每 15s 一次 |
| F3 | 概览页「功能模块」六张卡点击无反应 | `GestureDetector(onTap: () {})` 是空回调 | `lib/pages/dashboard_screen.dart:352-396`（补齐 `CaptureRoute/LedgerRoute/AliyunDdnsRoute/ToolsRoute/CollectionPictureRoute/LanTransferRoute`） | 六张卡逐一点击均能跳转 |
| F4 | 卡片悬停无位移反馈，读起来「按了没动」 | 只换了描边色 | `lib/pages/dashboard_screen.dart` 指标卡/功能卡、`lib/pages/tools/components/*_card.dart` 三张工具卡（`Matrix4.translationValues(0, -2, 0)`） | 悬停时卡片上浮 2px，投影加深 |
| F5 | 工具页三张卡与全站材质不同口径 | 仍在用 `Card` + `RoundedRectangleBorder` 手写描边 | `lib/pages/tools/components/extract_card.dart`、`ncm_decrypt_card.dart`、`sentry_log_card.dart` 统一走 `AppCard.glassDecoration` | 目视一致：同圆角、同描边、同投影 |
| F6 | 侧栏选中项与背景层次混同 | 选中态用了过淡的 `surface.withAlpha(100)` | `lib/components/window/collapsible_sidebar.dart:1333-1356`（改 `surfaceRaised`/`surface` + 自定义柔影） | 明暗两套主题下选中项都能一眼拎出来 |
| F7 | `dashboard_screen.dart` 有未使用的 import | 早先引入 `RoleManager` 做权限过滤，后来卡片列表改成静态、权限判断移除，import 忘删 | `lib/pages/dashboard_screen.dart:12`（删 `role_manager.dart` 一行） | `dart analyze lib/pages/dashboard_screen.dart` → `No issues found!` |

### 1.2 Rust 侧

| # | 问题 | 根因 | 落点 | 验证 |
|---|------|------|------|------|
| R1 | 并发上传归档时临时 zip 撞名 → 上传直接失败 | `temp_zip_path()` 只用毫秒时间戳拼 `sw_upload_<millis>.zip`，配合 `create_new(true)` 一撞就 `AlreadyExists` | `rust/src/node_server/upload_handler.rs:54-64`（加 PID + `AtomicU64` 计数） | 并发 8 路上传同一目录全部成功 |
| R2 | 媒体端点接受相对路径 | 只判了 `path.exists()` | `rust/src/node_server/media_handler.rs:106-116`（拒 NUL、要求绝对路径） | `?path=../../etc/passwd` 返回 400 |
| R3 | 大文件直读把 worker 线程堵住 | 同步 `fs::read` 在 async 上下文里跑 | `rust/src/node_server/media_handler.rs:170-190`（`spawn_blocking` + 50MB 上限） | 拉取 200MB 文件返回 413，其它请求不受影响 |
| R4 | 小说 txt 首个章节之前的正文被丢弃 | 切片从第一个章节标题开始 | `rust/novel_reader/src/parser/parser_txt.rs:11-20`（`clamp_char_boundary`）、`:174-193`（序言/前言分支） | 造一份「简介 + 第1章」的 txt，章节数应为 2 |
| R5 | 章节切片可能跨 UTF-8 字符边界 panic | 直接用正则给的字节偏移切片 | 同上 `clamp_char_boundary` 在 `:176`、`:192`、`:198` 三处兜底 | 中文/日文/emoji 混排 txt 解析不 panic |
| R6 | 一处 panic 让数据库互斥锁永久中毒 | `lock().unwrap()` | `rust/db_module/src/storage.rs`（全文改 `unwrap_or_else(|e| e.into_inner())`）、`rust/media_collection/src/api.rs:85-110` | 注入一次 panic 后续写入仍可用 |
| R7 | 缩略图许可计数可能下溢 | `*count -= 1` | `rust/media_collection/src/api.rs:102`（`saturating_sub`） | release 构建下反复 acquire/release 无 panic |

### 1.3 视觉体系（v2 → 现代通透）

| 项 | 旧值 | 新值 | 落点 |
|----|------|------|------|
| 亮色画布 | `#FAFAFA` 纯灰 → 后又试过 `#F3E7E4` 暖粉 | `#F4F6F9` 冷灰白 | `lib/core/theme/app_colors.dart:151` |
| 暗色画布 | `#0A0A0A` 死黑 → 后又试过 `#1B1826` 暗紫 | `#0F1117` 深空曜石 | `lib/core/theme/app_colors.dart:177` |
| 表面层次 | 画布/卡片都是近白 | 卡片 `#FFFFFF` / 内嵌 `#EEF2F6` | `app_colors.dart:154-160` |
| 描边 | `#E5E5E5` 灰阶 | `#E2E8F0` / `#CBD5E1`（Slate） | `app_colors.dart:170-173` |
| 文字 | 纯灰 `#525252` | Slate `#0F172A / #475569 / #64748B` | `app_colors.dart:195-205` |
| 氛围色团 | 4 团高饱和桃红/薰衣草（alpha 0x96） | 4 团极淡蓝/青/紫（alpha 0x10~0x15） | `app_colors.dart:645-688` |
| 对角基色 | 粉→紫→蓝 | `#F9FAFC → #EBF0F8` 近无彩色 | `app_colors.dart:621-643` |
| 投影 | 单层泛紫硬影 `0x265B4A7F` | 双层弥散（主影 + 贴地） | `lib/core/theme/app_atmosphere.dart` `cardShadow()` |
| 玻璃着色 | `0x96FFFFFF`（透到发飘） | `0xCCFFFFFF`（实到能压字） | `lib/core/theme/app_semantics.dart:103-106`、`:160-163` |

> ⚠️ **已知不一致（见 §2.7）**：`DESIGN.md` 的 front-matter 仍记着旧值
> （`canvas: "#F3E7E4"`、`atmosphere-warm: "#F9DAC4"` 等），与 `app_colors.dart`
> 现有取值对不上。DESIGN.md 自称「唯一口径来源」，这一条得补。

---

## 2. 待办（问题成立，本轮未改）

### 2.1 【高】节点 `POST /node/call` 请求体无长度上限

**现状**：`rust/src/node_server/mod.rs:352` 是 `vec![0u8; content_length]`，
`content_length` 直接取自客户端声明的 `Content-Length` 头（`:314`）。
申报 1 GiB 就真的分配 1 GiB，10 秒读超时救不了**已经完成的分配**。

**为什么本轮没改**：需要同时定「上限多少」与「超限返回什么」，属协议决定。

**建议**：加 `MAX_BODY_BYTES = 8 MiB`（`/node/call` 全是 JSON，8 MiB 已经很宽松），
超限在**读体之前**返回 413，与授权检查同一位置（`:327-339` 那一段之后）。

**验收**：`curl -X POST /node/call -H 'Content-Length: 2147483648'` 立即 413，
进程 RSS 不涨。

---

### 2.2 【高】生产媒体路径缺体积上限与路径白名单（与 R2/R3 同族，但落点不同）

**现状**：R2/R3 改的是 `handle_media_request`（hyper 版），
但**实际在跑的**是原生 TCP 服务器 → `handle_media_query`（`:432`）→
`handle_media_query_blocking`（`:457`）。后者：

- `:482` `std::fs::read(path)` 无体积上限（50MB 上限在 hyper 分支，没覆盖到这里）；
- `:464-467` 只判 `path.exists()`，不要求绝对路径（路径校验也没覆盖到）。

**为什么本轮没改**：改 `handle_media_query_blocking` 会影响所有封面/预览请求，
需要连 `serve_media_file_with_range`（`:493`）一起过一遍回归。

**建议**：
1. 把 `validate_media_path()` 抽成公共函数（NUL 检查 + 绝对路径），
   hyper 分支（`:104`）与原生分支（`:464`）都调它；
2. `:482` 前加体积判断：超过 `MAX_DIRECT_READ_BYTES`（复用 50 MiB）返回错误字符串，
   由 `mod.rs` 转成 413；
3. 顺带统一错误语义（现在 hyper 版文案是英文、原生版是 `file not found: <path>`）。

**验收**：`/node/media?path=相对路径` → 400；超大图片 → 413；一屏 60 张封面仍全部出图。

---

### 2.3 【中】非音视频文件的无 Range 请求被截断到 2 MB

**现状**：`rust/src/node_server/media_handler.rs:512-519`，无 Range 时一律
`clamp_range(0, VIDEO_CHUNK_SIZE - 1, …)`，把**任何**文件都截到 2 MB。
注释写的是「促使播放器转用 Range 请求」，但这条分支对普通文件（非 AV）也生效。

**为什么本轮没改**：需要确认客户端到底有没有「非 AV + 无 Range」的调用方；
盲改会影响现有媒体预览。

**建议**：分成两支——AV 保留 2 MB 首切片；非 AV 直接 200 + 全长
（或也走 Range，但 `Content-Range` 要给全量）。

**验收**：请求一张 5 MB 的 PNG（不带 Range），`Content-Length` 应为 5242880 而非 2097152。

---

### 2.4 【中】共享日志写盘：每条日志一次 `lock + flush`

**现状**：`rust/slime_logger/src/lib.rs:49-59`，`write_log` 每条都 `flush()`，
且 `LOG_FILE` 是全局 `Mutex`。媒体库缩略图热路径上有 `sw_info!`
（`rust/media_collection/src/api.rs:93`、`:104` 的 `[thumb-permit] acquired/released`），
每张图两条 → 一屏 60 张就是 120 次 `fsync` + 120 次全局锁争用。

**为什么本轮没改**：日志行为是排障生命线，改缓冲策略要定「掉电丢多少行可接受」。

**建议**：分两档——
- `sw_info!` / `sw_debug!` 走行缓冲，满 64 KiB 或 500ms 定时 flush；
- `sw_warn!` / `sw_error!` 保持立即 flush（错误必须落盘）。
另外把 `[thumb-permit]` 两条从 `sw_info!` 降到 `sw_debug!`——它本来就是排障打点。

**验收**：导入 500 张图，日志文件仍有完整记录；`log` 目录的 `fsync` 次数（`fs_usage`）下降一个量级。

---

### 2.5 【中】电量统计页双 30 秒定时器

**现状**：两处独立的 `Timer.periodic(30s)`：
- `lib/pages/power_stats/power_stats_screen.dart:97` → `refreshAggregated()`
- `lib/view_models/power_stats_viewmodel.dart:149` → `refreshStatus()`

页面一打开就有两条 30s 心跳，而 VM 是 GetX 托管的、页面 dispose 后定时器还在
（只靠 `onClose` 收）。

**建议**：删掉页面里那条，只留 VM 的；VM 那条按「页面可见」决定启停
（`Get.put` 时 start、`onClose` 时 cancel，现在 `onClose` 已经有 cancel 了）。

**验收**：进页面 90 秒，抓 `/api/power/*` 请求应为 3 次而非 6 次。

---

### 2.6 【低】Dashboard 卡片动画用 `Opacity` + `Transform` 包整棵树

**现状**：`lib/pages/dashboard_screen.dart` 每张卡外层
`AnimatedBuilder → Opacity → Transform.translate`。11 张卡 = 11 个独立保存图层，
首帧入场那一下会连开 11 层离屏缓冲。

**建议**：入场只做一次 `FadeTransition`（整块），或改用 `AnimatedSlide` 只做位移。
进入稳定态后这层 `Opacity(1.0)` 仍在树上，建议用 `if (anim.value < 1)` 摘掉。

**验收**：DevTools 的 `Repaint Boundaries` 叠加层，稳定态下不该看到每张卡各一个边界。

---

### 2.7 【低】`DESIGN.md` 与 `app_colors.dart` 取值已分叉

**现状**：`DESIGN.md:27-43` 的 front-matter 仍是旧调色板：

| 键 | DESIGN.md | app_colors.dart 现值 |
|----|-----------|----------------------|
| `canvas` | `#F3E7E4` | `#F4F6F9` |
| `canvas-dark` | `#1B1826` | `#0F1117` |
| `atmosphere-warm` | `#F9DAC4` | 已并入 `washesLight[0]`（`0x153B82F6`） |
| `glass-tint` | `#FFFFFF96` | `0xCCFFFFFF` |
| `glass-border` | `#FFFFFFA0` | `0x80E2E8F0` |
| `atmosphere-shadow` | `#5B4A7F26` | `0x0E0F172A` / `0x080F172A` |

而 DESIGN.md 第 4 行自称「本文是这三者的唯一口径来源」。

**建议**：三选一——
1. 把 front-matter 更新成现值（最快，但 §11 的「出图确认」流程要重跑）；
2. 在 front-matter 顶部加一行 `# ⚠️ 本节为 v2 存档，现值见 app_colors.dart`；
3. 把 front-matter 直接删掉，只留正文引用代码常量。

推荐 **2**：保留历史，同时不会误导下一个读文档的人。

---

### 2.8 【低】`handle_media_request`（hyper 版）已成死代码

**现状**：`rust/src/node_server/media_handler.rs:92` 的 `handle_media_request`
只被 `router.rs:29` 引用，而 `router.rs` 的 `route_request` 全仓只有
`router.rs:113`（测试）在调——生产路径是 `mod.rs` 里的原生 TCP 服务器。

R2/R3 的修复改在这个死代码分支上，**修得对，但没生效**。

**建议**：二选一——
1. 把 `handle_media_request` 的校验逻辑搬进 `handle_media_query_blocking`（并做 2.2）；
2. 删掉 hyper 分支与 `router.rs`，同步删对应测试，减少一处「两套实现」的坑。

推荐 **1**：删代码风险更大，而校验逻辑本身是对的。

---

### 2.9 【已修复，见 F7】~~`lib/pages/dashboard_screen.dart` 有未使用的 import~~

本轮已顺手删掉 `role_manager.dart` 那一行，`dart analyze lib/pages/dashboard_screen.dart`
已返回 `No issues found!`。留这一节只为记录「为什么曾经有这行」：
卡片列表早先按 `RoleManager` 做权限过滤，后来改成静态列表、判断移除，import 忘删。

---

### 2.10 【低】`power_stats_screen` 与 ViewModel 的刷新职责重叠

见 2.5。补一条实现细节：VM 的 `_autoRefreshTimer` 是在
`_service.ensureInitialized().then(...)` 里创建的（`power_stats_viewmodel.dart:149`），
若 `ensureInitialized()` 抛错，这个 `.then` 不会执行，但 `onClose()` 里的
`_autoRefreshTimer?.cancel()` 是安全的（可空）。这处已经是对的，
只是提醒：**新加的异步初始化也要走同一套可空/可选收尾**，别再退回 `late final`。

---

## 3. 回归清单（改完任一条都要跑）

```bash
# Dart 静态检查（本机 flutter wrapper 在沙箱里会写 engine.stamp，用 dart-sdk 直调）
/Users/shilaimu/development/flutter/bin/cache/dart-sdk/bin/dart analyze lib/

# Rust 构建 + 测试
cd rust && cargo build --workspace && cargo test --workspace

# Flutter 测试（含 404 张 golden）
flutter test

# 只跑与本文改动相关的
flutter test test/dashboard_render_test.dart test/ledger_render_test.dart \
             test/power_stats_render_test.dart test/media_card_cutout_render_test.dart
```

**golden 基线注意**：配色改动会整体刷新 `test/goldens/*.png`（共 404 张）。
确认新图目视正确后一次性提交，别只提交一部分——半新半旧的基线会让
`flutter test` 间歇性失败。

---

## 4. 已确认「不是问题」（避免下一轮重复排查）

| 看似问题 | 实测结论 |
|----------|----------|
| `AtmosphereBackdrop` 叠 5 层全屏渐变 = GPU 负担 | 已加 `RepaintBoundary`；且 `layered: false`（窄窗/移动端）只画 1 层。静止态不触发重绘 |
| `system_metrics_service` 每秒 `notifyListeners` | 已用 `Isolate.run` 把 FFI 挪出主线程；Dashboard 侧用 `ListenableBuilder` 只重建指标区，不重建整树 |
| `live_frost` 200ms 定时器 | 每次 tick 先比对窗口矩形，没变就直接 return，静止时零抓帧 |
| `_SparklinePainter.shouldRepaint` | 有实现且比较了 `data` 与两端色；不是每帧重绘 |
| `serve_media_file_with_range` 的 u64 下溢 | 已有 `clamp_range` 保证 `start <= capped_end`，且 `resolve_range` 有测试 |
| `Range` 正则每请求重编译 | `RANGE_RE` 已是 `OnceLock` |
