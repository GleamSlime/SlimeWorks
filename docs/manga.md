# Manga 模块文档

## 模块概述

Manga 是 SlimeWorks 内嵌的漫画阅读模块，通过 Dart 层的 `MangaService` 调用 Rust 侧提供的 HTTP 接口（manga_module），实现账号登录、首页推荐、漫画搜索、章节阅读、收藏管理等功能。

本模块仅在移动端（iOS/Android）和桌面端（Windows/macOS）均可使用，图片拉取统一走 Rust 代理节点。

---

## 目录结构

```
lib/pages/manga/
├── components/                    # 共享 UI 组件
│   ├── manga_comic_card.dart     # 漫画网格卡片
│   ├── manga_image_view.dart     # 异步图片加载组件
│   ├── manga_login_dialog.dart   # 登录对话框
│   └── manga_block_words_dialog.dart  # 屏蔽词管理对话框
├── models/
│   └── manga_models.dart         # 所有 Dart 数据模型
├── view_models/                   # ViewModel（GetX Controller）
│   ├── manga_home_viewmodel.dart
│   ├── manga_reader_viewmodel.dart
│   ├── manga_comic_detail_viewmodel.dart
│   ├── manga_search_viewmodel.dart
│   ├── manga_history_viewmodel.dart  # 观看记录 ViewModel
│   └── manga_favourites_viewmodel.dart
├── reader/
│   └── manga_reader_screen.dart  # 漫画阅读器页面
├── search/
│   └── manga_search_screen.dart  # 搜索页面
├── manga_home_screen.dart        # 主页（推荐 + 随机）
├── manga_comic_detail_screen.dart # 漫画详情页
├── manga_history_screen.dart     # 观看记录页面
└── manga_favourites_screen.dart  # 收藏夹页面
```

---

## 核心组件说明

### MangaService（`lib/core/services/manga_service.dart`）

通过 GetIt 注册的服务单例，所有网络请求均从此发起。核心方法：

| 方法 | 说明 |
|------|------|
| `login(email, password)` | 账号登录 |
| `logout()` | 退出登录 |
| `getCollections()` | 获取首页推荐集合 |
| `getRandomComics()` | 获取随机漫画列表 |
| `getComicDetail(comicId)` | 获取漫画详情 |
| `getComicEps(comicId, page)` | 获取章节列表 |
| `getEpsPages(comicId, epsOrder, page)` | 获取章节图片列表 |
| `searchComics(keyword, categories, page, sort)` | 搜索漫画 |
| `getFavourites(page, sort)` | 获取收藏列表 |
| `toggleFavourite(comicId)` | 收藏/取消收藏 |
| `fetchImageBytes(image)` | 拉取图片原始字节（走 Rust 节点代理） |
| `cacheComicMeta(comicId, title, thumbUrl)` | 缓存漫画基本信息（供历史记录用） |
| `getComicMeta(comicId)` | 从内存缓存读取漫画基本信息 |

---

## 页面路由

所有路由通过 GoRouter TypedGoRoute 定义，位于 `lib/core/routes/app_routes.dart`：

| 路由类 | 路径示例 | 说明 |
|--------|----------|------|
| `MangaHomeRoute` | `/manga` | 主页 |
| `MangaComicDetailRoute` | `/manga/comic/:id` | 漫画详情 |
| `MangaReaderRoute` | `/manga/reader/:id/:eps` | 阅读器 |
| `MangaSearchRoute` | `/manga/search` | 搜索 |
| `MangaHistoryRoute` | `/manga/history` | 观看记录 |

---

## 数据模型（`manga_models.dart`）

| 类 | 说明 |
|----|------|
| `MangaImage` | 图片资源（originalName / path / fileServer） |
| `MangaComic` | 漫画信息（id / title / author / thumb / categories / tags…） |
| `MangaEps` | 章节（id / title / order / updatedAt） |
| `MangaPage` | 章节中的单张图片 |
| `MangaPagination` | 分页元数据（total / limit / page / pages） |
| `MangaUser` | 用户信息（id / name / level…） |
| `MangaCollection` | 推荐集合（title / comics） |
| `MangaSortOrder` | 排序枚举（dateDescending / likeDescending…） |

---

## 状态管理规范

每个页面对应一个 ViewModel（继承 `BaseViewModel` → `GetxController`），放置于 `view_models/` 目录。

### 响应式策略

| 状态类型 | 容器 | 触发重建方式 |
|----------|------|-------------|
| 加载/错误状态（isLoading / errorMessage） | 普通 `bool` / `String?` | `setLoading()` / `setError()` 调用 `update()` → 外层 `GetBuilder` |
| 分页列表（pages / results / comics） | `RxList<T>` | `Obx(() => ListView/GridView)` 响应式重建 |
| 分页元数据（pagination） | `Rx<MangaPagination?>` | 同上，在 `Obx` 内读取 |
| UI 状态（showToolbar / isLoadingMore） | `RxBool` | `Obx` 响应式重建 |

> **注意**：`loadMore()` 通过 `RxList.addAll()` 追加数据，新条目依赖 `Obx` 检测变化并刷新 UI；**不要**在 `loadMore()` 中调用 `setLoading()`（会触发全局加载遮罩），改用 `isLoadingMore`。

### 章节列表的分页语义（详情页）

上游章节接口每页只给 20 章，**页内按 `order` 倒序**返回，页与页之间仍是倒序。详情页不吃这个顺序：

- `eps` 是规范序（`order` **升序**）——阅读器的上一话/下一话靠 `indexWhere(order==x)` 再取 `list[i±1]`，下载队列也按它排队，所以这一份必须升序。
- `epsDesc`（`eps.reversed`）才是界面读的展示序（最新一章在最前）。章节网格与下载弹层的章节网格都用这一份，两边看到的是同一个顺序。
- 补页只做**尾部追加再重排**（`_ascending([...eps, ...next.eps])`），因此首屏那 20 章的位置在补齐过程中不会变；翻车的写法是把补齐后的升序整表直接给界面——用户会看到"加载完突然整表翻面"。
- 触发方式是滚动到章节表尾部自动补下一页（`extentAfter < scaleW(300)`），没有"加载更多"按钮；`_epsPageLoading` 让并发触发共用同一页请求，重复滚动只发一跳。
- `loadDetail` **不**抢跑补齐：几百章的本子不该开机就连发十几个请求。
- 只有下载弹层需要全量（全选与章节计数），走 `ensureAllEps()` 循环补页，并先挂一个"正在补齐章节…"的常驻进度框；某页拉失败就停止循环，否则原地打转。
- 补页失败只 `setError` 一句提示，**不**把已渲染的整页打成错误页。
- 阅读器仍是一次性 `getComicEpsAll()` 拿全量（跨章导航要全局下标），与详情页的增量策略不同。

守这条的 test：`test/manga_chapter_list_test.dart`。

---

## 阅读器设计说明（MangaReaderScreen）

### 沉浸模式
- 使用 `ScreenChromeData(enableMobileImmersiveMode: true)` —— 由 `MobileLayout` 管理顶部/底部工具栏的统一显隐。
- `mobileAppBarColor: Color(0xE6121212)` 覆盖默认头部色，顶部与底部使用同一深色背景，保持视觉一致。
- 顶部与底部收起逻辑**完全同步**：上划隐藏两者，点击显示两者，由 `ScreenChromeData.bottomBar` 持有底部控件，无独立动画控制器。

### 阅读器内存优化（_ComicPageImage）
- **已移除** `AutomaticKeepAliveClientMixin`（`wantKeepAlive = true`），允许 ListView 回收屏幕外的图片 Widget，避免大量图片常驻内存触发 OOM（高水位 3GB 内存超限崩溃）。
- 图片字节由 `MangaService` 侧的 LRU 缓存（上限 60 条）持有；Widget 被回收后再次滚动到视口时仍能命中缓存，快速恢复显示。
- `_pageHeights` Map 在 Screen State 中按页码索引保存已渲染高度，作为 `initialHeight` 传入各页图片 Widget 的 `loadingBuilder` 占位高度，最小化布局抖动。
- 切换章节时 `_pageHeights.clear()`，防止旧章节高度污染新章节占位。

### 图片加载失败重试
- `MangaImageView` 新增 `onLoad` 回调和 `errorBuilder` 第三参数 `VoidCallback onRetry`。
- `_MangaImageViewState._retry()` 通过重置 `_future` 重新发起图片请求。
- 阅读器中加载失败时展示图片序号 + **重试按钮**，点击后调用 `onRetry` 重试。

### 返回导航 Chrome Race Condition 修复
- **场景**：从详情页 push 进阅读器后极快返回，`initState` 的 `addPostFrameCallback` 在 `_handleBack` 调用 `clearScreenChrome` 之后才触发，导致阅读器的 Chrome 重新注册到 chrome stack 顶部，详情页頭部消失或卡住。
- **修复**：`_backHandled` 布尔标志——`_handleBack` 和 `dispose` 中置 `true`，`addPostFrameCallback` 回调中检查该标志，若已置 true 则跳过注册。

**为什么不用 `GestureDetector` 包裹 `ListView`？**

将 `GestureDetector.onTap` 嵌套在 `ListView` 外层时，桌面端（鼠标/触控板）和部分移动端场景下 `TapGestureRecognizer` 与 `VerticalDragGestureRecognizer` 在手势竞争池（Arena）中存在冲突，导致 ListView 无法响应滚动手势。正确做法是将点击检测器作为独立透明层放在 Stack 中，通过 `HitTestBehavior.translucent` 确保滑动事件穿透到下方 ListView。

### 错误处理
阅读器使用独立的 `readerError: Rx<String?>` 而非基类的 `setError()`，原因是基类 `_buildBody` 的 GetBuilder 在检测到 `errorMessage != null` 时会异步调用 `clearError()`（通过 SnackBar 回调），导致自定义错误页面一帧后消失。`readerError` 不走基类清除机制，生命周期完全由阅读器自身管理。

因为不走基类，toast 也得自己接：`_errorToastWorker = ever(viewModel.readerError, …)` 在 `onPageInit` **加载之前**就挂上监听，首话就失败也能有提示；`dispose` 里 `worker.dispose()`。

### 报错文案：一律一句话（`MangaErrorText.describe`）
Rust 侧的 `MangaError` 会带 `网络错误: … caused by: client error (Connect) caused by: tcp connect error` 这种链，FRB 到 Dart 又套一层 `Exception: ` 前缀。整段铺在界面上既读不下去，又会把正常内容盖掉，所以所有漫画报错都过 `MangaErrorText.describe()`：剥前缀、把换行/制表压成空格、命中关键字表翻成可行动的中文（401→"登录已过期，请重新登录"、超时→"请求超时，可切换分流节点后重试"），没命中也只截到一行。规则表按顺序匹配，超时排在连接类前面才不会把 timeout 报成"连不上服务器"。

展示层：页面级报错走 `AppToast.errorBar`（`BasePage` 的自动错误条已换成它，`AppMotion.dwellLong` 驻留 + 语义图标），阅读器走 `AppToast.error`，整块内容读不到时用 `EmptyState` 的重试空态。**Dialog/Sheet 里只能走行内提示**——SnackBar 画在页面 Scaffold 上，会被弹层挡住。

---

## 图片加载（MangaImageView）

`MangaImageView` 是一个 `StatefulWidget`，内部通过 `FutureBuilder<Uint8List>` 调用 `MangaService.fetchImageBytes()` 异步拉取图片字节流（走 Rust 节点代理），然后用 `Image.memory()` 渲染。

- 支持自定义 `loadingBuilder` 和 `errorBuilder`
- 通过 `didUpdateWidget` 检测 `image.path` / `image.fileServer` 变化，自动重新拉取
- `gaplessPlayback: true` 避免图片切换时闪烁

---

## 已知限制

- 章节列表由详情页滚动到尾部时逐页补齐（见"章节列表的分页语义"）；只有阅读器仍是一次性拉全量，几百章的本子进阅读器会连发十几个分页请求
- 图片拉取完全依赖 Rust 侧节点代理，节点不可用时所有图片均加载失败

---

## 修改入口速查

| 需求 | 入口文件 |
|------|----------|
| 修改登录逻辑 | `lib/core/services/manga_service.dart` |
| 修改首页布局 | `lib/pages/manga/manga_home_screen.dart` |
| 修改阅读器交互 | `lib/pages/manga/reader/manga_reader_screen.dart` |
| 修改图片加载策略 | `lib/pages/manga/components/manga_image_view.dart` |
| 修改搜索逻辑 | `lib/pages/manga/view_models/manga_search_viewmodel.dart` |
| 修改观看记录逻辑 | `lib/pages/manga/view_models/manga_history_viewmodel.dart` |
| 修改章节列表加载策略 | `lib/pages/manga/view_models/manga_comic_detail_viewmodel.dart` |
| 修改报错文案/新增错误关键字规则 | `lib/core/services/manga_error_text.dart` |
| 修改屏蔽词管理 | `lib/pages/manga/components/manga_block_words_dialog.dart` |
| 修改 Rust 侧接口 | `rust/manga_module/src/` |

---

## 搜索页（MangaSearchScreen）

- 搜索输入框位于 `ScreenChromeData.titleWidget`，符合头部规范（不使用 AppBar）。
- **搜索历史**：最多存 20 条，持久化于 `SharedPreferences`（key: `manga_search_history`）；支持单条删除和全部清空。
- **排序**：支持 dd（最新）、da（最早）、ld（最多点赞）、vd（最多浏览）四种排序，通过右上角 `PopupMenuButton` 切换。
- **屏蔽词过滤**：搜索返回结果均经 `MangaBlockWordsService.shouldBlock()` 过滤，命中标题/分类/标签屏蔽词的漫画不会显示。

---

## 观看记录（MangaHistoryScreen）

存储于 `SharedPreferences`（key: `manga_history_list`），最多保留 200 条，序列化为 JSON 数组。

每条记录字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `comicId` | String | 漫画 ID |
| `comicTitle` | String | 漫画标题 |
| `thumbUrl` | String | 封面图 URL（缓存自 `MangaService._comicMetaCache`） |
| `epsOrder` | int | 最后阅读的章节序号 |
| `epsTitle` | String | 最后阅读的章节标题 |
| `tick` | int | 记录时的时间戳（毫秒） |

- 阅读器每次进入章节时通过 `MangaHistoryViewModel.saveRecord()` 自动保存记录（静态方法）。
- 点击记录直接跳转到对应章节继续阅读（`MangaReaderRoute`）。
- 支持左滑删除单条记录，右上角可清空全部。

---

## 屏蔽词管理（MangaBlockWordsDialog）

持久化于 `SharedPreferences`（key: `manga_block_words`），序列化为 JSON 对象。

支持三种维度的屏蔽词：

| 维度 | 说明 |
|------|------|
| 标题（title） | 漫画标题包含屏蔽词时过滤 |
| 分类（category） | 漫画分类列表中任一分类命中时过滤 |
| 标签（tag） | 漫画标签列表中任一标签命中时过滤 |

- `MangaBlockWordsService` 用内存缓存（`_cache`）减少 SharedPreferences 读取；`invalidateCache()` 可强制重新加载。
- 通过主页用户菜单中"屏蔽词管理"菜单项打开。
