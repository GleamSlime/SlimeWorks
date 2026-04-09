# PicACG 模块文档

## 模块概述

PicACG 是 SlimeWorks 内嵌的漫画阅读模块，通过 Dart 层的 `PicAcgService` 调用 Rust 侧提供的 HTTP 接口（picacg_module），实现账号登录、首页推荐、漫画搜索、章节阅读、收藏管理等功能。

本模块仅在移动端（iOS/Android）和桌面端（Windows/macOS）均可使用，图片拉取统一走 Rust 代理节点。

---

## 目录结构

```
lib/pages/picacg/
├── components/                    # 共享 UI 组件
│   ├── picacg_comic_card.dart     # 漫画网格卡片
│   ├── picacg_image_view.dart     # 异步图片加载组件
│   └── picacg_login_dialog.dart   # 登录对话框
├── models/
│   └── picacg_models.dart         # 所有 Dart 数据模型
├── view_models/                   # ViewModel（GetX Controller）
│   ├── picacg_home_viewmodel.dart
│   ├── picacg_reader_viewmodel.dart
│   ├── picacg_comic_detail_viewmodel.dart
│   ├── picacg_search_viewmodel.dart
│   └── picacg_favourites_viewmodel.dart
├── reader/
│   └── picacg_reader_screen.dart  # 漫画阅读器页面
├── search/
│   └── picacg_search_screen.dart  # 搜索页面
├── picacg_home_screen.dart        # 主页（推荐 + 随机）
├── picacg_comic_detail_screen.dart # 漫画详情页
└── picacg_favourites_screen.dart  # 收藏夹页面
```

---

## 核心组件说明

### PicAcgService（`lib/core/services/picacg_service.dart`）

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

---

## 页面路由

所有路由通过 GoRouter TypedGoRoute 定义，位于 `lib/core/routes/app_routes.dart`：

| 路由类 | 路径示例 | 说明 |
|--------|----------|------|
| `PicAcgHomeRoute` | `/picacg` | 主页 |
| `PicAcgComicDetailRoute` | `/picacg/comic/:id` | 漫画详情 |
| `PicAcgReaderRoute` | `/picacg/reader/:id/:eps` | 阅读器 |
| `PicAcgSearchRoute` | `/picacg/search` | 搜索 |

---

## 数据模型（`picacg_models.dart`）

| 类 | 说明 |
|----|------|
| `PicAcgImage` | 图片资源（originalName / path / fileServer） |
| `PicAcgComic` | 漫画信息（id / title / author / thumb / categories / tags…） |
| `PicAcgEps` | 章节（id / title / order / updatedAt） |
| `PicAcgPage` | 章节中的单张图片 |
| `PicAcgPagination` | 分页元数据（total / limit / page / pages） |
| `PicAcgUser` | 用户信息（id / name / level…） |
| `PicAcgCollection` | 推荐集合（title / comics） |
| `PicAcgSortOrder` | 排序枚举（dateDescending / likeDescending…） |

---

## 状态管理规范

每个页面对应一个 ViewModel（继承 `BaseViewModel` → `GetxController`），放置于 `view_models/` 目录。

### 响应式策略

| 状态类型 | 容器 | 触发重建方式 |
|----------|------|-------------|
| 加载/错误状态（isLoading / errorMessage） | 普通 `bool` / `String?` | `setLoading()` / `setError()` 调用 `update()` → 外层 `GetBuilder` |
| 分页列表（pages / results / comics） | `RxList<T>` | `Obx(() => ListView/GridView)` 响应式重建 |
| 分页元数据（pagination） | `Rx<PicAcgPagination?>` | 同上，在 `Obx` 内读取 |
| UI 状态（showToolbar / isLoadingMore） | `RxBool` | `Obx` 响应式重建 |

> **注意**：`loadMore()` 通过 `RxList.addAll()` 追加数据，新条目依赖 `Obx` 检测变化并刷新 UI；**不要**在 `loadMore()` 中调用 `setLoading()`（会触发全局加载遮罩），改用 `isLoadingMore`。

---

## 阅读器设计说明（PicAcgReaderScreen）

### 沉浸模式
- 进入阅读器：`SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`
- 退出阅读器：恢复 `SystemUiMode.edgeToEdge`

### 滚动设计
```
Stack
├── Obx(ListView.builder)          ← 图片列表，用 Obx 响应分页追加
├── Positioned.fill(GestureDetector, behavior: translucent)  ← 点击检测层
│     onTap → toggleToolbar()      ← 不直接包裹 ListView，避免手势竞争
└── Obx(IgnorePointer + AnimatedOpacity + AppBar)  ← 工具栏
      IgnorePointer(ignoring: !showToolbar)  ← 隐藏时穿透，允许重新唤起
```

**为什么不用 `GestureDetector` 包裹 `ListView`？**

将 `GestureDetector.onTap` 嵌套在 `ListView` 外层时，桌面端（鼠标/触控板）和部分移动端场景下 `TapGestureRecognizer` 与 `VerticalDragGestureRecognizer` 在手势竞争池（Arena）中存在冲突，导致 ListView 无法响应滚动手势。正确做法是将点击检测器作为独立透明层放在 Stack 中，通过 `HitTestBehavior.translucent` 确保滑动事件穿透到下方 ListView。

### 错误处理
阅读器使用独立的 `readerError: Rx<String?>` 而非基类的 `setError()`，原因是基类 `_buildBody` 的 GetBuilder 在检测到 `errorMessage != null` 时会异步调用 `clearError()`（通过 SnackBar 回调），导致自定义错误页面一帧后消失。`readerError` 不走基类清除机制，生命周期完全由阅读器自身管理。

---

## 图片加载（PicAcgImageView）

`PicAcgImageView` 是一个 `StatefulWidget`，内部通过 `FutureBuilder<Uint8List>` 调用 `PicAcgService.fetchImageBytes()` 异步拉取图片字节流（走 Rust 节点代理），然后用 `Image.memory()` 渲染。

- 支持自定义 `loadingBuilder` 和 `errorBuilder`
- 通过 `didUpdateWidget` 检测 `image.path` / `image.fileServer` 变化，自动重新拉取
- `gaplessPlayback: true` 避免图片切换时闪烁

---

## 已知限制

- 章节列表仅加载第一页 eps（`getComicEps(comicId, page: 1)`），大量章节的漫画不会自动翻页载入更多章节
- 图片拉取完全依赖 Rust 侧节点代理，节点不可用时所有图片均加载失败

---

## 修改入口速查

| 需求 | 入口文件 |
|------|----------|
| 修改登录逻辑 | `lib/core/services/picacg_service.dart` |
| 修改首页布局 | `lib/pages/picacg/picacg_home_screen.dart` |
| 修改阅读器交互 | `lib/pages/picacg/reader/picacg_reader_screen.dart` |
| 修改图片加载策略 | `lib/pages/picacg/components/picacg_image_view.dart` |
| 修改搜索逻辑 | `lib/pages/picacg/view_models/picacg_search_viewmodel.dart` |
| 修改 Rust 侧接口 | `rust/picacg_module/src/` |
