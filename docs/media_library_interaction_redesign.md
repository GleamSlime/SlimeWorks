# 资源库页面交互重构方案

> 起因：桌面端资源库交互体感差，具体表现为三类「点了没反应 / 点错东西」：
> 点返回反而拖动或最大化窗口；全屏后缩窗再点全屏图标行为不对；拖拽区域抢事件。

## 一、根因（逐条定位到代码）

### 病灶 1：整个窗口左上角压着一条 40 高的隐形拖拽条

`desktop_scaffold.dart:209` 在 Stack 最顶层（`widget.child` 之后）放了一条：

```dart
const Positioned(left: 0, top: 0, child: ScreenTopBar()),
```

`screen_top_bar.dart` 里它是 `width: MediaQuery.sizeOf(context).width`、`height: scaleH(40)`
的透明容器，包在 `GestureDetector(onDoubleTap: 最大化/还原, onPanStart: startDragging)` 里。

它**盖在 DesktopTopBar（高 60）的上半部分**，而 DesktopTopBar 里的
`PictureActionBar` 的返回按钮（`DesktopHeadToolsButton`，尺寸 kSpace40）正好落在
这一条内。于是：

- 单击返回按钮 → 拖拽条先吃到 pan 手势 → `windowManager.startDragging()` 被调用
- 双击返回按钮 → 拖拽条吃 doubleTap → 窗口最大化/还原

这就是「点一下返回结果拖动窗口或者放大窗口了」。

**注意**：这不是资源库独有，全站所有页面的顶栏左上角控件都被它盖着。
资源库因为返回键最靠左、点得最频繁，才被用户先发现。

### 病灶 2：全屏是「新压一条 route」，与窗口状态互不知情

`media_kit_video` 的 `enterFullscreen()` 是
`Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(...))` —— 它压的是一个
**新的全屏 route**，不是把窗口放大，也不改 `desktopImmersiveMode`。

于是出现用户描述的现象：

1. 预览里点全屏 → 压入全屏 route，视觉上「全屏了」
2. 用户拖窗口把窗口缩小（窗口层行为，route 层完全不知道）
3. 点底栏右侧的全屏图标 → `isFullscreen(context)` 仍然为 true（route 还在栈上）
   → 走 `exitFullscreen()` → pop 掉 route

用户期望的「按窗口当前状态决定」根本没有参与判断。

### 病灶 3：拖拽导入区的命中范围是整页，且与网格交互抢事件

`collection_picture_screen.dart:531` 的 `DropTarget` 包住了整个正文
（`body` + 覆盖层）。行为本身没错（整页可拖入是合理的），
但它和 `SelectionMarquee`（拖框多选）、网格自身的手势是**同一层**叠加的：

- 拖入文件时，`SelectionMarquee` 会同时把鼠标拖动当成框选
- 拖拽悬停高亮层是 `IgnorePointer`，但 `DropTarget` 的 enter/exit 会
  在划过每个子项时反复触发 → 高亮闪烁
- 桌面端点一下空白处再点返回，`_bodyFocusNode` 的焦点归属不稳定

### 病灶 4：返回语义分散在三处，谁都不知道全貌

返回这件事现在有三套实现：

| 位置 | 实现 |
|---|---|
| `PictureActionBar` 返回键 | 读 `_viewerActiveFlag` 判断关预览还是退集合 |
| 正文 `Focus` 的 ESC | `_onEscapeKey` 逐级：多选 → 集合 → 文件夹 |
| `PopScope` | 同 ESC 逻辑再写一遍 |

三者对「预览是否压在顶上」「是否全屏」「是否在画中画」都各有一套判断，
新增状态必然漏一处。全屏压在预览之上时，操作栏返回键的行为尤其含糊。

## 二、设计原则

1. **窗口拖拽区只留真正空白处**：任何可点击控件所在矩形都必须从拖拽区里挖掉。
2. **全屏 = 窗口状态，不是路由**：桌面端全屏统一走窗口最大化 + 隐藏侧栏/顶栏，
   与移动端（真正的 route 全屏）分开实现。
3. **返回只认一个栈**：页面自己维护一份 nav stack 快照，所有返回入口读同一份。
4. **拖拽导入与框选互斥**：外部文件拖入时，框选层让位。

## 三、改法

### 改动 A：拖拽条挖洞（改 `screen_top_bar.dart` + `desktop_scaffold.dart`）✅ 已实施

把「一条通栏透明的 GestureDetector 压在页面之上」改成「压在页面之下」：

- `desktop_scaffold.dart` 的 Stack 顺序改为 `拖拽条 → widget.child → 悬浮进度`。
  这样任何真正可点的控件天然优先命中，拖拽/双击只落在没被控件覆盖的空白区，
  不需要维护任何「控件矩形注册表」。
- `ScreenTopBar` 高度由 `scaleH(40)` 改为 `scaleW(60)`，与 `DesktopTopBar` 等高：
  太矮会让顶栏下半截拖不动窗口。改为纯空白容器（不再画 macOS 灯位占位，
  那份让位由侧栏与 `DesktopTopBar.lightsHere` 承担）。
- 修 `ScreenTopBar.isMaximized` 的静态缓存语义：它只在双击时更新，
  用户用系统按钮或快捷键改状态后就错（Windows 三颗自绘灯读它）。
  改为「仅作最后已知状态」，判断一律 `await windowManager.isMaximized()`。

### 改动 B：桌面端全屏改窗口语义（改 `media_viewer_video.dart`）✅ 已实施

底栏右侧那颗全屏按钮不再用 `MaterialDesktopFullscreenButton`（它只会 push route），
换成本项目自己的 `_VideoFullscreenButton` + `_toggleDesktopFullscreen()`：

```
全屏 = windowManager.maximize() + desktopImmersiveMode = true（隐侧栏/顶栏）
再点 = unmaximize + immersive = false
```

- 图标按 `windowManager.isMaximized()` **现查**并监听 `WindowListener` 的
  `onWindowMaximize/onWindowUnmaximize`：用户拖窗口缩小后图标立刻变回「全屏」，
  不再自说自话。
- `_ownFullscreen` 只做**归属标记**：只还原本页开的那一份，不动用户从别处
  （音乐播放器沉浸模式等）带来的状态。
- 预览页 `dispose` 时若 `_ownFullscreen` 为真则复位，避免返回列表后侧栏消失。
- 移动端继续用 `MaterialFullscreenButton`（route 全屏才是移动端正确语义）。

### 改动 C：拖拽导入让位给框选（改 `collection_picture_screen.dart` + `selection_marquee.dart`）✅ 已实施

- `SelectionMarquee` 新增 `enabled` 参数；`_isDraggingFiles` 时置 false，
  停用态直接 `KeyedSubtree` 透传子件，不挂任何手势。
- `DropTarget` 外包 `Listener(onPointerDown: 收回 _bodyFocusNode)`：
  点正文任何位置都收回焦点，保证 ESC 一定可达。

### 改动 D：返回语义单点化（改 `collection_picture_screen.dart` + `picture_action_bar.dart`）✅ 已实施

新增 `_handleBack()` 作为**唯一**返回入口（预览层 → 集合 → 文件夹）：

- `PictureActionBar` 的 `isViewerActive/onExitCollection/onExitFolder` 三个参数
  收成一个 `onBack`，栏内不再做任何层级判断。
- 正文 ESC、`PopScope`、移动端左滑手势全部改调 `_handleBack()`。

### 不做的事

- 不动 `SelectionMarquee` 的框选算法本身。
- 不动 `AnimatedSwitcher` 转场与滚动位置恢复（已调优过，注释里有踩坑记录）。
- 不动移动端 AppBar 布局。
- 不改 `MediaViewerPage` 的跟手拖动/缩放。

## 四、验收

1. 桌面端点顶栏返回键 → 只退一层，窗口不动；双击返回键不放大窗口。
2. 拖窗口顶栏空白处 → 正常拖动；双击空白处 → 放大/还原。
3. 预览视频点全屏 → 窗口最大化且侧栏隐藏；再点 → 还原窗口、侧栏回来。
4. 全屏状态下拖窗口缩小 → 沉浸模式退出，按钮状态与实际一致。
5. 拖入文件时框选层不响应；松开后正常导入。
6. `flutter analyze` 干净；全量 `flutter test` 失败集合与基线 389 持平。
