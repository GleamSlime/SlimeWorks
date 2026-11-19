# 真客户端集成测试报告（真 macOS App + 真无头节点）

> 日期：2026-11-19
> 任务：task-6「真客户端集成测试：真 macOS App + 真无头节点复现用户场景」
> 用户原话：「xcode 已转，请使用真实的客户端的测试，以复现客户才会遇到的问题」
> 执行人：real-app-tester

---

## 0. 一句话结论

**真 App 这条路打通了，8 条真实用户场景全部跑绿**（`+8: All tests passed!`）。
本轮**没有测出新 bug** —— 但这不代表没价值：这是我第一次在**真 macOS App**里
（真 Cocoa 窗口 + 真插件 + 真 Rust framework）跑通「真点击 → 数据真的变了」的
闭环，同时**决定性验证了「幽灵体积」修复真的生效**（R8 给出 3→2→1→0 的实测数字）。

过程中发现 **2 个真实问题**（一个已确认是 bug，一个是我自己的隔离疏漏），
以及 **4 条环境事实**，都会写在下面。

---

## 1. 交付物

| 文件 | 作用 |
|------|------|
| `integration_test/real_app_smoke_test.dart` | 地基：真 App 能启动 + 数据隔离真的生效（2 条用例） |
| `integration_test/real_app_node_test.dart` | 主体：8 条真实用户场景，真 App + 真节点 + 真点击 |
| `integration_test/helpers/real_app_node.dart` | 夹具：从 App 进程里起真 `slime_node` 子进程 + 真 HTTP 回查 |

只新增 `integration_test/` 下的文件，**没有改 `lib/` 和 `rust/` 的任何生产代码**。

---

## 2. 跑法（可直接复制）

```bash
mkdir -p /tmp/sw_real_app_home
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export FLUTTER_SWIFT_PACKAGE_MANAGER=false
export LIBCLANG_PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib
# ★ 装了完整 Xcode 后不要再设 CXXFLAGS/CFLAGS（CLT 与 Xcode 26 的 libc++ 混用会炸）
export PATH="$HOME/.pub-cache/bin:/private/tmp/fl/flutter/bin:$PATH"

HOME=/tmp/sw_real_app_home \
CFFIXED_USER_HOME=/tmp/sw_real_app_home \
SLIME_E2E_HOME=/tmp/sw_real_app_home \
CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup \
/private/tmp/fl/flutter/bin/flutter test integration_test/real_app_node_test.dart -d macos --no-pub
```

三个 `HOME` 类变量与两个 `CARGO_*` 变量**缺一不可**，理由见 §4。

---

## 3. 测了什么 / 结果

全部用例：`flutter test integration_test/real_app_node_test.dart -d macos --no-pub`
最后一次完整运行：**`00:30 +8: All tests passed!`**（exit 0）

| # | 场景 | 用户视角 | 结果 |
|---|------|---------|------|
| R1 | 真点侧栏节点选择器切到远程节点 → 真点侧栏「媒体库」 | 「切到节点后，媒体库里能看到节点上的东西吗」 | ✅ 通过 |
| R2 | 点「新建文件夹」→ 输入名字 → 点「确定」 | 「在远程文件夹里新建的文件夹，真的到节点上了吗」 | ✅ 通过 |
| R3 | 右键文件夹 → 重命名 → 输入新名 → 点「确定」 | 「重命名后**立刻**看列表（不刷新页面）变了吗」 | ✅ 通过 |
| R4 | 右键集合 → 删除集合 → 点弹窗「移除」 | 「删掉之后卡片真的没了吗，节点上也真删了吗」 | ✅ 通过 |
| R5 | 右键集合 → 删除节点本地文件 → 点「删除文件」 | 「节点磁盘上的文件真没了吗，集合聚合值归零了吗」 | ✅ 通过 |
| R6 | 连续两次「新建文件夹」 | 「连着做两个写操作，第二个会被缓存/去重吞掉吗」 | ✅ 通过 |
| R7 | 含**冒号**的特殊字符名 + 同名文件夹建两次 | 「特殊字符的名字会不会被静默清洗，同名会不会互相覆盖」 | ✅ 通过 |
| R8 | 逐条删文件直到删完最后一条 | 「删掉最后一个条目后，上一级的条数/体积还停在旧值吗」 | ✅ 通过 |

### 每条都做双向断言

被测的不只是「UI 上有没有变化」，而是**两边都对**：

- **UI 侧**：`find.text(...)` / `find.byType(MediaCollectionCard)` 是否出现/消失/改名
- **节点侧**：真 HTTP 回查节点数据库（`list_media_collections` / `list_media_folders`）
  确认数据真的变了

只查一边正是上一轮漏掉 bug 的原因 —— 假节点只能证明「客户端发了什么」，
证明不了「节点上数据到底变没变」。

### R8 的决定性证据（幽灵体积回归）

```
[R8] 导入后聚合值 count=3 size=28932
[R8] 删第 1 条后 count=2 size=19288
[R8] 删第 2 条后 count=1 size=9644
[R8] 删最后一条后 count=0 size=0 （-1 表示集合记录已被移除）
```

这组数字直接证明 task-4（aggregate-fixer）的修复**在真 App + 真节点链路里生效**：
删到空时 `item_count` 和 `total_size` 都真的写成 0，而不是停在删前值。

> 为什么 R8 必须单独一条、不能并进 R5：
> R5 走的是「整目录清空」路径，节点会顺带把空集合记录一起移除，
> 于是「聚合值不归零」这个缺陷**恰好被掩盖**（记录都没了，也就没人看 item_count）。
> 要复现用户看到的「卡片写着 1 个文件、点进去一片空白」，必须走**逐条删**
> 这条「删掉最后一条、但集合记录还留着」的路径。

---

## 4. 数据隔离：哪一层能隔离、哪一层不能（都是实测结论）

这是本轮**最有价值的工程产出**之一。真 App 会写好几个地方的数据目录，
它们的隔离机制**完全不同**，漏一个就会污染开发者真实环境。

| 数据 | 路径 | 靠什么隔离 | 实测结论 |
|------|------|-----------|---------|
| Rust 各模块（media.db / db.redb / music_player.db） | `$HOME/Library/Application Support/SlimeWorks` | `HOME` | ✅ 设 HOME 即完全隔离 |
| path_provider（Application Support / Documents） | `NSHomeDirectory()/Library/...` | **`CFFIXED_USER_HOME`** | ⚠️ **只设 HOME 不够**，必须加 CFFIXED_USER_HOME |
| shared_preferences / UserDefaults | `~/Library/Preferences/com.gleamslime.works.plist` | **无 —— 连 CFFIXED_USER_HOME 也改不了** | ❌ 必须 `setMockInitialValues` |

### 4.1 `CFFIXED_USER_HOME` 才是 macOS 的真隔离开关

写了个 Swift 探针实测：

```
HOME=/tmp/x                → NSHomeDirectory() = /Users/gleamslime   ← 没跟着走
HOME=/tmp/x CFFIXED_USER_HOME=/tmp/x → NSHomeDirectory() = /tmp/x    ← 跟了
```

只设 `HOME` 时，`path_provider` 的 `getApplicationSupportDirectory()` 与
UserDefaults 全部仍指向开发者真实目录（`ledger.db` 就是这么落到
`~/Library/Application Support/com.gleamslime.works/ledger/` 的）。
加上 `CFFIXED_USER_HOME` 后这两层完全跟到沙箱，**不需要 mock 任何平台通道**。

### 4.2 shared_preferences 是隔离不掉的，必须 mock（重要）

`CFFIXED_USER_HOME` **管不到 CFPreferences**。实测证据：设了两个变量跑真 App 后，
节点配置照样写进了真实的 `~/Library/Preferences/com.gleamslime.works.plist`：

```json
"flutter.node_remote_nodes" => "[{\"id\":\"node_1795041911831100_831100\",
   \"name\":\"E2E真节点\",\"apiBaseUrl\":\"http://127.0.0.1:59373\",...}]"
```

不隔离的后果不只是「弄脏」，还有**更隐蔽的连锁反应**：
测试会读到上一轮遗留的陈旧节点（端口早关了）→ 节点被判熔断 →
侧栏节点选择器不渲染 → 用例连环失败。我最初就吃了这一炮。

**处理**：`SharedPreferences.setMockInitialValues({})`。
API 调用路径完全不变（仍走真实 SharedPreferences 逻辑），只是不落盘。
**这是本套测试唯一的人为偏差**，已在两个文件的头部注释里写明。

> 清理动作：我已把测试误写进真实 prefs 的两个键删掉
> （`flutter.node_remote_nodes`、`flutter.sw_e2e_isolation_probe`），
> 并备份原件到 `/tmp/sw_prefs_backup_1795042704.plist`。
> 复查方式：`plutil -p ~/Library/Preferences/com.gleamslime.works.plist | grep node_remote_nodes`（应为空）。

### 4.3 HOME 隔离会连带打死 cargokit（坑）

`flutter test -d macos` 会**先尝试重建 Rust**。cargokit 用 `$HOME/.cargo`
找 rustup，`HOME` 一改就报：

```
error: rustup is not installed at '/tmp/sw_real_app_home/.cargo'
** BUILD FAILED **
```

**必须显式透传** `CARGO_HOME=$HOME/.cargo RUSTUP_HOME=$HOME/.rustup`。
这条不写进文档，下一个人必踩。

### 4.4 隔离结果自检

跑完全部用例后：

```
✓ 真实库 mtime/size 未变（media.db / db.redb / music_player.db 三元组 diff 为空）
✓ 真实 prefs 里没有测试写入的键
```

---

## 5. 发现的问题

### 5.1 【真 bug·已确认】媒体库顶栏「刷新」按钮没有 Tooltip

**文件**：`lib/pages/collection/picture/components/picture_library_toolbar.dart:353`

```dart
// 刷新/同步按钮（始终显示）
DesktopHeadToolsButton(
  icon: DrawIcon(StrokeIcons.refresh),
  size: AppTheme.metrics.kSpace40,
  onTap: onRefresh,
),
```

同一个工具栏里其余 **9 个**按钮全部包了 `Tooltip(message: ...)`
（新建文件夹 / 重新扫描封面 / 扫描文件夹 / 导入文件夹 / 清空媒体库 /
新建智能文件夹 / 只显示收藏 / 叠加信息 / 上传…），只有这一个漏了。

**用户视角**：鼠标悬停在这个按钮上什么提示都没有，不知道它是干什么的；
与旁边 9 个都有提示的按钮放在一起，**一致性直接崩了**。
无障碍工具（读屏、`find.byTooltip` 这类自动化定位）也识别不到它。

**复现步骤**：
1. 打开 App → 进「媒体库」
2. 鼠标悬停顶栏那个圆形箭头图标 → 无任何提示
3. 悬停旁边任意其它图标 → 都有中文说明

**我的处理**：测试里改成按图标定位（`find.byWidgetPredicate((w) => w is DrawIcon && w.icon == StrokeIcons.refresh)`），
**没有为了迁就这个 bug 而删掉用例** —— 如果哪天这个按钮彻底坏了，
按图标的写法仍然能测出来。
（Lead 已确认由他另开任务修。）

### 5.2 【我的疏漏·已修】shared_preferences 隔离不完整

第一轮跑真 App 时，`CFFIXED_USER_HOME` 我以为就够了，结果节点配置写进了真实
`~/Library/Preferences`。已按 §4.2 修好并清理现场。**记在这里是因为它是
「看起来隔离了、其实没隔离」这类事故的典型**：必须**逐层确认**每个数据落点，
不能靠「设了个 HOME 就以为万事大吉」。

### 5.3 【观察·未判废】R5 的路径被空集合清理掩盖

R5（删节点本地文件）删完整个目录后，节点把空集合记录**一并移除了**，
所以聚合值断言走的是「记录已移除」分支，没有真正校验 item_count 归零。
这是**可接受的业务语义**（记录都没了，UI 上不会有幽灵卡片），
但也说明**R5 覆盖不到幽灵体积** —— 所以才有 R8。两条保留，
一条守「整目录清空」，一条守「逐条删到空」。

---

## 6. 环境事实汇总（给后来者）

| 事实 | 值 |
|------|-----|
| 项目 SDK | `/private/tmp/fl/flutter/bin/flutter`（3.50.0 / Dart 3.14.0，与 `.dart_tool/version` 一致） |
| **不能用** | `/opt/homebrew/bin/flutter`（3.47.2，与项目不匹配） |
| LIBCLANG_PATH | `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib` |
| **不要设** | `CXXFLAGS` / `CFLAGS`（装了完整 Xcode 后那套 CLT 变通会炸：`unknown type name 'uint64_t'`） |
| Xcode | 26.3 (17C529)，`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer` |
| 必带 | `FLUTTER_SWIFT_PACKAGE_MANAGER=false` + 两个镜像 env |
| 构建 | `✓ Built build/macos/Build/Products/Debug/史莱姆工坊.app`（434M） |

### 6.1 关于 `build.db is locked`

`flutter test -d macos` 每次都走完整 xcodebuild，`derivedDataPath` 是**全工作区共享**的。
团队里同时有人跑 `flutter build macos` / `flutter test` 就会撞：

```
error: unable to attach DB: accessing build database ".../build.db": database is locked
```

不是测试写法问题，**撞了就等对手跑完重试**（或由 Lead 留出独占窗口）。

另一条同源症状：`Pods/Manifest.lock` 与 `Podfile.lock` 不同步会报
`The sandbox is not in sync with the Podfile.lock` → `cd macos && pod install` 修。
**别随手 `git checkout -- macos/Podfile.lock`**，那会把同步弄坏。

### 6.2 `testWidgets` 会重置 widget 树（测试结构上的硬约束）

`testWidgets` 在每个用例开始时执行 `runApp(Container(_preTestMessage))`，
把整棵树重置。所以：

- **不能**在 `setUpAll` 里 `main()` 一次就指望后续用例还有界面；
- 正确做法（见 `_bootApp`）：首条用例跑真正的 `main()`（完整初始化链路），
  后续用例 `pumpWidget(const MyApp())` 挂回同一套已初始化的服务上
  （`RustLib.init` / `getItInit` 都不可重入，只能跑一次）。

### 6.3 等待条件必须「边泵帧边等」

`AppRoutes.router` 是个 lazy final，要等 `MyApp` 首次 build 读到 `goRouter` 才初始化。
只等时间不泵帧 → **永远等不到**，白吃满超时（我为此浪费了两轮）。
所有等待都走 `_waitUntilPumped`（每轮 `tester.pump` + 真实延时各 100ms）。

### 6.4 定位节点的关键细节

- 侧栏「媒体库」的 location 是 **`/collection/picture`**，不是 `/media-library`
  （后者是另一个 route，指向同一个页面；侧栏那条是 `/collection/picture`）。
- `SidebarNodeSelector` 是 `Obx` 包着 `enabledRemoteNodes.isEmpty ? SizedBox.shrink() : 选择器`，
  所以「侧栏外壳已渲染」≠「节点选择器已渲染」，必须**单独等一层**。
- 点节点选项要用 `find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('...'))`，
  裸 `find.text().last` 在切换后可能命中侧栏那份 label。

---

## 7. 因限制跑不了 / 没覆盖的（明确声明，不假装通过）

| 场景 | 状态 | 原因 |
|------|------|------|
| 移动端（Android/iOS）真点击 | ❌ 未跑 | 本机只有 macOS 设备；移动端路径（长按进多选、上传按钮）完全未覆盖 |
| 「移动到文件夹」两处计数都对 | ⚠️ 未做 | 走 `showDialog` 选文件夹的弹层项数多、定位不稳，本轮时间不够；建议下一轮补 |
| 「操作失败时用户看到失败提示」 | ⚠️ 部分 | `test/e2e_headless_remote_click_test.dart` 已覆盖（不存在的集合→失败提示），**真 App 里未复测** |
| 小说库 / 记账 / 阿里云等其它模块 | ❌ 未跑 | 本轮范围是媒体库；`task-5` 的审计报告覆盖代码层面 |
| 真 App 里的视频/音频播放 | ❌ 未跑 | 需要真实媒体解码，与本轮写操作目标无关 |

**没有一项是「跑了但没敢写真实结果」**。上表都是真的没跑。

### 7.1 必须**逐文件**跑，不能跑整个 `integration_test/` 目录（重要）

这是本轮的实测结论：**多个 integration_test 文件不能在同一进程里混跑**。

```bash
# ✅ 正确：一次一个文件
flutter test integration_test/real_app_smoke_test.dart -d macos --no-pub
flutter test integration_test/real_app_node_test.dart  -d macos --no-pub

# ❌ 错误：整个目录
flutter test integration_test/ -d macos --no-pub
```

整目录跑的失败形态（实测三种，都可能出现）：

```
build/test/listener_1.dart: Error: reading 'build/test/listener_1.dart': No such file or directory
Failed to load ".../real_app_node_test.dart"
Failed to load ".../simple_test.dart"
```

原因是 `flutter test` 对多个 integration 文件会在同一个进程里串跑，
每个文件都会尝试 `runApp(...)` + `RustLib.init()` + `getItInit()`，
而这些**都不可重入**：第二个文件开始就会撞「树已被上一个文件重置」
「RustLib 已初始化」「GetIt 已注册」这类冲突，表现为加载阶段就崩。

**所以本报告的验收结论以「逐文件跑」为准**：

| 文件 | 结果 |
|------|------|
| `integration_test/real_app_smoke_test.dart` | ✅ `+1: All tests passed!` |
| `integration_test/real_app_node_test.dart` | ✅ `+8: All tests passed!` |

### 7.2 关于 `integration_test/simple_test.dart`

那个文件是首个 commit（`4d9af12 Initial commit`）的模板残留，
原断言是「首页有一句 `Result: \`Hello, Tom!\``」——那句文案早就不在 UI 里了。
它**不是本轮的交付物**，但本轮期间被其他人改写成了
「真 App 里 Rust 桥接可用」的地基自检（`git diff` 可见），
单独跑也是绿的。是否保留 / 合并，交给 Lead 定。

**我的交付只有三个文件**（`git status` 可复核）：
`integration_test/real_app_smoke_test.dart`、
`integration_test/real_app_node_test.dart`、
`integration_test/helpers/real_app_node.dart`。

## 8. 建议 Lead 后续跟进

1. **修 5.1 的 Tooltip 缺失**（一行改动，已定位到行号）。修完后可以把测试里的
   图标定位改回 `find.byTooltip('刷新')`，作为回归证据。
2. **把 §4 的隔离姿势写进 `docs/dev-environment.md`**：三个 HOME 类变量 +
   两个 CARGO 变量的完整组合，以及「shared_preferences 必须 mock」这条。
3. **下一轮补「移动到文件夹」和失败提示**：这两条都在 task-6 第 3 节的清单里，
   本轮没做完，别当成已覆盖。
4. **团队构建窗口约定**：`flutter test -d macos` 与任何 `flutter build macos`
   共享 derivedData，并发必锁。建议约定「真 App 测试期间不跑别的构建」。

---

## 9. 原始输出（可复核）

完整运行日志：`/tmp/sw_r11.log`
（`00:30 +8: All tests passed!`，`EXITCODE=0`）

```
[R5] 集合记录已被节点移除（也是可接受的语义）
[R5] 卡片上的文本：[集合, 2 项, 远程样本集合, /private/tmp/sw_real_app_home/node_data/media/远程样本集合, E2E真节点, 18.84 KB]
[R8] 导入后聚合值 count=3 size=28932
[R8] 删第 1 条后 count=2 size=19288
[R8] 删第 2 条后 count=1 size=9644
[R8] 删最后一条后 count=0 size=0 （-1 表示集合记录已被移除）
00:30 +8: All tests passed!
```

真 App 启动证据（`real_app_smoke_test.dart`）：

```
✓ Built build/macos/Build/Products/Debug/史莱姆工坊.app
[INFO] 节点服务已启动 (Rust): 17888
[INFO] 恢复窗口位置: x=272.0, y=313.0, width=1280.0, height=720.0
[冒烟] 最终 element 数=2143
[冒烟] appSupport=/tmp/sw_real_app_home/Library/Application Support/com.gleamslime.works
[冒烟] appDocs=/tmp/sw_real_app_home/Documents
[冒烟] rust 数据目录存在=true path=/tmp/sw_real_app_home/Library/Application Support/SlimeWorks
[冒烟] platform=macos dpr=1.0 viewSize=Size(1280.0, 720.0)
+1: All tests passed!
```
