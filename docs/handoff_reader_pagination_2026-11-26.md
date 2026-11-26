# 移动端阅读器「微信读书式」改造 — 交接文档

> 导出时间：2026-11-26
> 仓库：`/Users/gleamslime/Desktop/SlimeWorks`（branch `main`，HEAD `f4db3e3`）
> 目标：把移动端远程阅读页从「上下滚动」改成微信读书式「分页 + 左右翻页」并优化交互

---

## 一、用户需求（原始描述）

> 「移动端阅读书籍体验仍然很糟糕，再参照微信读书 APP 优化一下交互」

经确认，范围锁定为：

1. **改成微信读书式分页 + 左右翻页**（不是滚动阅读）
2. 点屏幕中央：呼出/隐藏顶部底栏
3. 左右滑动：切换上一章/下一章
4. 底部显示真实页码/进度条
5. 目录抽屉：显示当前阅读位置 + 已读标记
6. 长按正文：复制/选中菜单

---

## 二、当前进度

### ✅ 已完成（未提交）

**分页引擎** `lib/core/utils/reader_paginator.dart`（新建，约 160 行）

- 纯函数、无 widget 依赖，可单测
- API：
  ```dart
  ReaderPaginator.paginate({
    required String text,
    required Size size,        // 正文可视区域（已扣工具栏/安全区/内边距）
    required TextStyle style,  // 必须与最终渲染完全一致
    double textScale = 1.0,
  }) → List<String>            // 每页一个字符串，至少 1 页
  ```
- **回归测试** `test/reader_paginator_test.dart`（5 条，全绿）：
  1. 切页后拼回去必须与原文逐字一致（不丢字、不重复字）
  2. 每页内容高度都不得超过页高
  3. 空文本返回单页空串，不返回空列表
  4. 短文本只占一页
  5. 字号变大时页数必须变多

验证方式：
```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH="$HOME/flutter_sdk/flutter/bin:$PATH"
HOME=/tmp/sw_pg $HOME/flutter_sdk/flutter/bin/flutter test test/reader_paginator_test.dart --no-pub
```

### ⏳ 待办（本次未开始）

| # | 任务 | 说明 |
|---|---|---|
| 1 | 阅读页改 `PageView` 左右翻页 | 接入分页器，替换现有 `SingleChildScrollView` |
| 2 | 点中央呼出/隐藏工具栏 | 目前点正文只能「退出沉浸」，不能双向切换 |
| 3 | 左右滑翻章 | 到首/末页时滑出切换章节 |
| 4 | 底部页码 + 进度条 | 现在底栏中间已是 `1/12`（章节进度），还需**页内进度** `3/12` |
| 5 | 目录抽屉已读标记 | 抽屉在 `Scaffold.drawer`，`ListTile` 列表 |
| 6 | 长按复制/选中菜单 | 现在正文是 `SelectableText`，需自定义 `contextMenuBuilder` |

---

## 三、关键文件与位置

| 文件 | 作用 | 关键位置 |
|---|---|---|
| `lib/core/utils/reader_paginator.dart` | **新建** 分页引擎 | 全部 |
| `lib/pages/collection/library/components/remote_novel_reader_dialog.dart` | 阅读页（核心改造对象） | 见下 |
| `test/reader_paginator_test.dart` | **新建** 分页测试 | 全部 |
| `lib/pages/novel_reader/novel_reader_page.dart` | 本地阅读器（**可参考的成熟实现**） | 沉浸模式 `_isImmersive`、覆盖层动画 |

### `remote_novel_reader_dialog.dart` 关键结构

该文件有 **2 个 State 类 + 1 个底栏 widget**，改造只动第二个 State：

- `_RemoteNovelReaderDialogState`（第 35 行）— 桌面弹窗版（已废弃，`library_book_card.dart` 不再调用）
- `_RemoteNovelReaderPageState`（第 271 行）— **移动端全屏页，本次改造对象**
- `_RemoteReaderBottomBar`（第 1079 行）— 底栏 widget（StatelessWidget，需要加页码参数）

```
_RemoteNovelReaderPageState
├─ 字段（约 275-305 行）
│   ├─ _loading / _error / _chapterLoading / _chapterError
│   ├─ _chapters / _selected / _chapterText
│   ├─ _readerBgColor / _readerFontSize / _readerLineHeight
│   ├─ _isImmersive (RxBool) / _immersiveTimer
│   └─ _isFavorite
├─ _load()                    // 取章节骨架 → 按 progress 恢复章节 → _loadChapter
├─ _loadChapter(int index)    // 取单章正文 → setState(_chapterText)
├─ _persistProgress()         // 写节点，用 _rawNovelIdFor 还原原始 id
├─ _rawNovelIdFor(String)     // remote:<node>:<raw> → <raw>
├─ _toggleFavorite()
├─ _showInBookSearch()        // 书中搜索（节点 search_in_novel）
├─ _showReaderSettingsSheet() // 字号/行距/背景色
├─ _mobileReaderContentPadding(context)  // 正文内边距（覆盖层不占布局）
├─ _setImmersive(bool) / _scheduleImmersiveIdle()
├─ _handleChapterSwipeNotification()     // 现在靠 overscroll 翻章
└─ build()                    // Stack + Positioned 覆盖层
```

### 当前 build 结构（改造前）

```dart
ScreenChrome(data: ScreenChromeData.empty, child: Scaffold(
  drawer: Drawer(...),                    // 章节列表
  body: Obx(() {
    final isImmersive = _isImmersive.value;
    return Stack(
      fit: StackFit.expand,               // ★ 必须 expand，否则塌成 0（踩过）
      children: [
        Positioned.fill(child: ...正文...),          // ← 改这里
        Positioned(top: 0, child: ...顶栏覆盖层...),
        Positioned(bottom: 0, child: ...底栏覆盖层...),
      ],
    );
  }),
))
```

正文当前是 `SingleChildScrollView` + `SelectableText`（`_buildChapterContent` 第 1045/1070 行）。

---

## 四、改造要点与已踩过的坑

### 坑 1：`Stack` 必须 `fit: StackFit.expand`
全 `Positioned` 子元素 + 默认 loose → Stack 塌成 0 尺寸，**文字在树里但屏幕空白**（宽度算成 0）。
已修（`d6b1310`），改动时不要动掉这行。

### 坑 2：验证「可见」必须量尺寸
`find.textContaining` 命中 ≠ 可见。查 `tester.getRect(...)`，尤其看 `left == right`（宽度 0）。

### 坑 3：分页切点不能用「上一行末尾」推算
前一版算法实测产生「第 2 页高度 609 > 页高 600」（渲染被裁）。
现版改为「累加行高，超页就把该行之前的归为一页，切点取该行行首偏移」，
并加了「拼回原文一致」兜底校验。

### 坑 4：`LineMetrics` 不带字符索引
只能靠 `getPositionForOffset` 探测行首。探测位置用「垂直中心 + x≈0.5」最稳。

### 坑 5：书卡片外层是 `Draggable`，会吞 `tester.drag`
验证滚动/翻页要用 `position.jumpTo(...)` 或直接调 State 方法，不要靠 drag。

---

## 五、环境与验证姿势

### SDK（**不要用 `/private/tmp/fl`**，会被系统清理）
```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export PATH="$HOME/flutter_sdk/flutter/bin:$PATH"
```

### 单元测试
```bash
HOME=/tmp/sw_x $HOME/flutter_sdk/flutter/bin/flutter test test/xxx_test.dart --no-pub
```

### 真 iOS 模拟器验证（本机可用）
```bash
# 1. 起节点（必须 0.0.0.0 + 宿主 LAN IP，模拟器访问不到 127.0.0.1）
cd rust && ./target/debug/slime_node --host 0.0.0.0 --port 18390 \
  --data-dir /tmp/sw_x/data --name 验证

# 2. 宿主 IP
ipconfig getifaddr en1        # 本机 → 192.168.3.252

# 3. 跑探针
HOME=/tmp/e2e CFFIXED_USER_HOME=/tmp/e2e SLIME_E2E_HOME=/tmp/e2e \
CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
LIBCLANG_PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib \
FLUTTER_SWIFT_PACKAGE_MANAGER=false \
$HOME/flutter_sdk/flutter/bin/flutter test integration_test/x.dart \
  -d B10C3765-A69F-4A51-A6AE-6BD750C40025 --no-pub
```

探针写法规矩（否则必然报错）：
- **必须** `app.main()` 启动（否则 `ScreenUtil._data` / `DotEnv` 未初始化直接崩）
- **必须第一行** `SharedPreferences.setMockInitialValues({})`（否则污染开发者真实配置，这是**踩过大坑**的）
- 真实导航：`goRouter.go('/novel-library')` → `tester.tap(...)` 点书
- 真机 `iPhone 13 Pro Max (wireless)` 需要设备端开 Developer Mode，否则拒绝

### 提交前
```bash
$HOME/flutter_sdk/flutter/bin/flutter analyze --no-pub     # 必须 No issues
# 全量测试 + 基线对照（golden 失败属既有环境问题，判据是「不得新增」）
```
基线 worktree 三件套（缺任一都会整片 loading error）：
```bash
git worktree add /tmp/sw_base <commit>
cp .env /tmp/sw_base/
cd /tmp/sw_base && dart run tool/stroke_icons/generate.dart
cd /tmp/sw_base && dart run build_runner build --delete-conflicting-outputs
```

---

## 六、微信读书交互参考

| 操作 | 行为 |
|---|---|
| 点屏幕**中央** | 呼出/隐藏顶部底栏（双向切换） |
| 点屏幕**左侧 1/3** | 上一页 |
| 点屏幕**右侧 1/3** | 下一页 |
| **左右滑动** | 上一页/下一页（到边界切章） |
| **上下滑动** | 进入沉浸模式（隐藏工具栏） |
| 底栏 | 目录 · 阅读进度 · 设置 |
| 顶栏 | 返回 · 书名 · 更多 |
| 无操作若干秒 | 自动隐藏工具栏 |

当前实现与它的差距：无分页、点中央只能退出沉浸、翻页只能靠 overscroll 触发（难发现）。

---

## 七、建议实施顺序

1. **接入分页器**（改动最小、可独立验证）：
   在 `_loadChapter` 成功后，按正文区域尺寸切页，存 `_pages`；
   正文区换成 `PageView`，`onPageChanged` 更新 `_pageIndex`。
2. **点中央切换**：`GestureDetector.onTapUp` 判 `dx` 落在左/中/右 → 翻页或切工具栏。
3. **页码 + 进度条**：底栏中间改 `页/总页`，再加一条细进度条。
4. **目录已读标记**：`ListTile` 已读章节加淡色/勾。
5. **长按菜单**：`SelectableText.contextMenuBuilder` 或换 `SelectionArea`。

每步都先跑 `test/reader_paginator_test.dart` + 真机探针，再进下一步。

---

## 八、当前工作区状态

```
?? lib/core/utils/reader_paginator.dart      ← 新建，已完成并通过测试
?? test/reader_paginator_test.dart           ← 新建，5 条全绿
?? rust/.cargo_update_dry.txt                ← 无关，勿提交
```

未提交任何改动，HEAD 仍在 `f4db3e3`。
