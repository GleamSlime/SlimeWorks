# SlimeWorks 设计系统

> 面向 AI 工具类客户端的视觉语言：同色相明度阶梯做层次、半透明状态层做反馈、
> 窗口透出做质感、统一节奏做"跟手"。本文是**取色、取尺寸、取动效的唯一口径来源**。
>
> 代码入口：`lib/core/theme/`（令牌）+ `lib/core/widgets/`（组件）+ `lib/pages/theme_preview_screen.dart`（可视化总览，路由 `/theme-preview`）。

---

## 1. 分层：原始色 → 语义角色 → 组件

```
app_colors.dart     原始调色板：色值本身，不含判断
   ↓ 只被下一层引用
app_semantics.dart  语义角色（ThemeExtension）：明暗在此一次性解析
   ↓ 业务代码只碰这一层
页面 / 组件          AppSemantic.of(context).surface …
```

`app_colors.dart` 里的 `LightColors` / `DarkColors` / `AppSurfaces` / `AppBrand` /
`AppStatus` / `AppGlass` **不是给业务代码用的**，它们只负责被 `AppSemantic` 装配。
业务代码写 `isDark ? DarkColors.x : LightColors.y` 就是绕过了这一层，属于待清理项。

---

## 2. 取色唯一入口：`AppSemantic`

```dart
final s = AppSemantic.of(context);   // 或 context.surface
final m = AppTheme.metrics;
```

以 `ThemeExtension` 注册进 `ThemeData`，因此随明暗自动切换、参与主题过渡动画、
调用点不需要 `brightness` 分支。

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `canvas` | `#F1F1EE` | `#141512` | 窗口画布，最外层底色 |
| `surface` | `#FFFFFF` | `#232420` | 一级表面：卡片 / 面板 |
| `surfaceRaised` | `#FFFFFF` | `#2B2C28` | 二级表面：卡片内嵌块 / 浮起菜单 |
| `surfaceSunken` | `#EBEBE7` | `#1A1B17` | 下沉表面：输入框底 / 图标占位底 |
| `surfaceHover` | `0x14000000` | `0x1CFFFFFF` | 悬停状态层（半透明水洗） |
| `surfaceActive` | `#EDEDFA` | `#322F45` | 选中 / 按压态 |
| `hairline` | `0x0F000000`（6%） | `0x14FFFFFF`（8%） | 发丝分隔线 |
| `border` | `0x1A000000` | `0x24FFFFFF` | 常规描边 |
| `borderStrong` | `0x2E000000` | `0x3DFFFFFF` | 强描边：需要边界感处 |
| `textPrimary` | `#21221E` | `#EDEEE9` | 主文字 |
| `textSecondary` | `#5E5F59` | `#A9AAA3` | 次级文字 / 图标 |
| `textTertiary` | `#74756E` | `#8E8F86` | 说明文字 |
| `textDisabled` | `#B8B9B2` | `#5A5B56` | 禁用 |
| `accent` | `#6656CF` | `#A89FEE` | 强调色：填充、选中、进度 |
| `accentOn` | 白 | 黑 | 强调色之上的文字 |
| `accentText` | `#6656CF` | `#C4BDF5` | 链接 / 选中文字 |
| `accentContainer` | `#EDEAFB` | `#2C2843` | 选中底（低浓度强调） |
| `success/warning/danger/info/neutral` | 见 2.4 | 见 2.4 | 状态色族，`.color` / `.container` / `.containerBorder` |
| `scrim` | `0xB3000000` | `0xB3000000` | 模态遮罩 |
| `glassTint` / `glassBorder` | 白 72% / 白 20% | `#23241F` 62% / 白 14% | 磨砂面板着色与发丝描边 |
| `glassPanelTint` | 白 55% | `#212218` 42% | 常驻面板（比卡片更透，以便透出桌面） |

### 2.1 状态层方向：**水洗永远朝"看得见"那侧走**

这是本项目踩过最深的一个坑，值得单独写死。

- 亮色侧表面本来就是白（`#FFFFFF` 卡片 / `#F1F1EE` 画布），再叠半透明**白**是零反馈。
  历史上 `lightSurfaceHover = 0x2DFFFFFF` 正是这个值——卡片、列表行、菜单在亮色模式
  下**完全没有悬停**。现改为 `0x14000000`，压白得 `#E8E8E8`、压画布得 `#E0E0DC`。
- 暗色侧表面比白暗，所以继续用**提亮**的白水洗 `0x1CFFFFFF`。
- 两侧方向相反是有意为之，不是不一致。

配套两条硬规则：

1. **状态层必须是半透明的**，因为它画在内容**之上**（实心色会把文字整个盖掉）。
   `Hoverable` 用 `Stack` 三层：底色在下 → 内容 → 状态层在上并 `IgnorePointer`。
2. **半透明色不能进 `Color.lerp` 的端点**。骨架屏原先 lerp 到 `surfaceHover`，
   alpha 一起被插值，最亮一帧直接消失；端点必须换成实心色（现用 `surfaceRaised`）。

### 2.2 强调色的对比度下限

`AppBrand.deep` 从 `#6F5FD9`（画布上 4.30）压深到 `#6656CF`（4.89），
因为小字号链接/标签在 4.3 会发灰。**任何新强调色都要过 4.5:1 这条线。**

### 2.3 投影：`s.elevation(Elevation.x)`

五档，key + ambient 双层，替代散落的各写各的 `BoxShadow`：

| 档位 | y / blur / spread | 用途 |
|---|---|---|
| `none` | 0 | 贴平 |
| `raised` | 1 / 2 / 0 | 微浮 |
| `card` | 2 / 8 / 0 | 卡片 |
| `floating` | 6 / 20 / -2 | 悬浮工具条 |
| `overlay` | 16 / 44 / -6 | 弹窗 / 菜单 |

ambient 层自动取 `blur×2`、`y×2`。停靠类控件（如底部播放条）要把 y 翻成负值，
向下的影子落在窗口外等于没有。

### 2.4 状态色族

| 角色 | 亮色 `.color` | 暗色 `.color` |
|---|---|---|
| `success` | `#2E9463` | `#63CB9C` |
| `warning` | `#B57A10` | `#E7B45C` |
| `danger` | `#D24C55` | `#F2838A` |
| `info` | `#3580B8` | `#77BEEA` |
| `neutral` | `#7A7B75` | `#9A9B95` |

容器底与描边从主色派生，不要手写 `withAlpha`：
`container` = 主色 @ 10%（亮）/ 16%（暗），`containerBorder` = @ 22% / 28%。
暗色浓度更高，否则在深灰表面上看不出层次。

> `danger` 只用于**破坏性**操作（删除、从库中移除）。收藏/喜欢这类"选中"状态
> 用 `accent`，不是红——原先播放器里两处 `Colors.redAccent` 就是这个口径错位。

---

## 3. 尺寸令牌：`AppTheme.metrics`

```dart
final m = AppTheme.metrics;
BorderRadius r = m.radiusCard;   // 注意：radius* 是 BorderRadius，不是 double
double sp = m.kSpace16;
```

- **语义圆角**（调用点优先用这组，不要记数字）：
  `radiusControl`(9) 按钮/控件 · `radiusField`(11) 输入框 · `radiusCard`(14) 卡片/列表项 ·
  `radiusPanel`(18) 面板/分栏 · `radiusOverlay`(22) 弹窗/抽屉 · `radiusPill`(999) 胶囊
- **数值圆角**：`radius2/3/4/6/8/10/12/14/16/18/20/22/24/25/28/32/40/100/999`
- **间距**：`kSpace1/2/3/4/5/6/8/10/12/14/16/18/20/24/32/40/44/48/56/64/80`
  （别名 `paddingSmall/Medium/Large/XLarge`、`spacingSmall…`）
  ⚠️ **没有 `kSpace26/36/96`**，超出档位用 `scaleW(n)`
- **字号**：`fontSize9/10/11/12/13/14/15/16/17/18/20/22/24/28/32/36/48/72`
- **图标**：`iconSize12/13/14/15/16/18/20/22/24/28/32/40/44/48/64/96`（**没有 38**）

间距走 `scaleW()`（随窗口宽度折算），字号与图标走 `scaleSWithUserFont()`
（额外乘用户的"界面字号"设置）。

### 3.1 为什么宽度类尺寸要 `scaleW` 而不是 `const`

`scaleW(w) = ScreenUtil().setWidth(w * _adaptiveScaleFactor())`，按**当前窗口宽度**折算。
写死 `const _kSidebarWidth = 220.0` 的话窗口缩小侧边栏不会跟着收，所以这类值要写成
`double get _kSidebarWidth => scaleW(220);`——**用 getter，不是 const**。

规范：禁止裸数字和 `int.w`；`AppTheme.metrics` 里没有的档用 `scaleW()`。

---

## 4. 文本角色：`AppTextStyles`

所有角色都从 `textTheme.bodyMedium` 派生（`_role()`），**不能裸 `TextStyle(...)` 构造**——
裸构造会丢 `fontFamily`，项目自带字体（FZLanTingYuanS-EB-GB）会静默回退成系统字体。

| 角色 | 字号 / 字重 / 色 | 用途 |
|---|---|---|
| `pageTitle` | `headlineMedium` | 页面主标题 |
| `sectionTitle` | 15 / w600 / textPrimary | 小节标题（原 12 种变体统一到此） |
| `cardTitle` | 13 / w600 / textPrimary | 卡片标题 |
| `rowTitle` | 13 / w500 / textPrimary | 列表行标题 |
| `body` | 13 / w400 / textSecondary | 正文 |
| `caption` | 11 / w400 / textTertiary | 次要说明 |
| `overline` | 10 / w600 / textTertiary / +0.9 字距 | 分组标签 |
| `metric` | 28 / w600 / textPrimary | 数据大屏数字 |
| `mono` | Menlo 12 / textSecondary | 日志、路径、代码 |

`rowTitle` 与 `cardTitle` 只差一档字重：整页卡片标题要撑住区块，列表行里几十条同名行
用 w600 会糊成一片黑。

⚠️ `mono` 的 Menlo 是 **macOS 字体**，跨平台的列表行不要用（移动端/Windows 回退不可控）。

---

## 5. 动效：`AppMotion`

原先散落 250/280/300/400/600ms 各自为政，观感"有的跟手、有的迟钝"。

| 场景 | 时长 |
|---|---|
| 反馈类（hover / press / 选中） | `instant`(90ms) / `fast`(160ms) |
| 状态类（展开 / 收起 / 切换） | `base`(220ms) |
| 空间类（页面转场 / 抽屉 / 弹窗） | `slow`(320ms) / `emphasis`(460ms) |
| 列表逐条入场间隔 | `stagger`(45ms) |

曲线：`standard`（通用，起步快收尾稳）、`decelerate`（进场/展开，落位感）、
`accelerate`（退场/收起，不拖尾）。`AnimatedX` 一律用 `AppMotion.defaultDuration` +
`defaultCurve`，不要每处手写。

配套：`AppPageTransitions.fadeUp`（淡入 + 2% 上浮，替代 Material 默认横向推入）、
`StaggerEntrance`（逐条浮现，替代各页手写的 `Future.delayed(300 + i*80)`——
那种写法会造成"可点击但无内容"的空窗）。

---

## 6. 磨砂与窗口透出

"透出应用背后内容"是**两层**结构，缺一层就不成立：

1. **窗口本身透明** —— `macos/Runner/MainFlutterWindow.swift` 往 `NSThemeFrame`
   插 `NSVisualEffectView`（`.fullScreenUI` / `.behindWindow`），负责透出**桌面**。
   该视图重写了 `hitTest` 返回 nil：否则 AppKit 会把事件全吃进原生层，Flutter 收不到点击。
2. **面板再叠 `BackdropFilter`** —— 负责透出**同一 App 内**它下面的内容
   （列表滚到面板下方时能隐约看见，这是层次感的关键来源）。

### 6.1 组件

| 组件 | 签名要点 |
|---|---|
| `GlassSurface(child, blur, tint, borderColor, borderRadius, padding, elevated, asPanel)` | 常驻面板；`asPanel` 用更透的着色 + `radiusPanel` |
| `GlassAppBar(title, leading, actions, bottom)` | 顶/底吸附条，内容从其下方滚过 |
| `GlassFloat(child, padding, borderRadius)` | 命令面板 / 悬浮工具条 / 下拉浮窗 |
| `GlassMenuItem(label, icon, destructive, selected, value, enabled)` | 桌面紧凑菜单行，行高 30（Material 默认 48 是给触屏定的） |

原生模糊不可用时（Windows/旧系统）自动退化为半透明色块，仍然可用。

### 6.2 透明度档位：`WindowGlass`（`lib/components/window/window_backdrop.dart`）

| 档位 | alpha | 生效条件 |
|---|---|---|
| `contentAlpha` | 180 | 仅 macOS（正文密度高，透明度已收敛得很低） |
| `panelAlpha` | 200 | 侧栏/面板 |
| `overlayAlpha` | 242 | 浮层（菜单、弹窗、底部播放条） |

非对应平台一律 255（实心）。模糊半径三档：`AppGlass.blurSoft`(12) / `blurMedium`(24，
语义层默认值) / `blurStrong`(40)。`kWindowsGlassEnabled` 是 Windows 子窗口 HWND 能否透出
的总开关——**该项在 Windows 上尚未实测**，观感异常先把它改成 `false` 退回实心底。

### 6.3 浮层取色禁忌

`GlassMenuItem` **不再自建悬停药丸**：外层 `InkWell` 用的就是 `ThemeData.hoverColor`
（= `surfaceHover`），自己再叠一颗会变成"方块灰 + 药丸灰"两层。
同理，菜单/浮层的底色一律用 `surfaceRaised.withAlpha(WindowGlass.overlayAlpha)`，
不要写死 `Colors.black45` 之类。

---

## 7. 共享组件库

新增 UI 前先在这里找，**找不到再考虑加**——右列是收敛前的重复实现数量
（取自各组件自身的收敛说明注释）。

| 组件 | 位置 | 消灭的重复 |
|---|---|---|
| `AppCard(child, padding, onTap, elevated, selected, hoverable, borderRadius, borderColor, color)` | `app_card.dart` | 95 处手写 `BoxShadow`、三套卡片圆角 |
| `Hoverable` | `app_card.dart` | 各页自建 `MouseRegion + setState` |
| `StatCard(label, value, hint, icon, tone, onTap)` | `app_card.dart` | 6 种统计卡实现 |
| `AppDivider(indent, endIndent, spacing)` | `app_card.dart` | 各写各的 `Divider(height:1)` |
| `StatusChip(label, tone, icon, showDot, dense, onTap)` | `app_chips.dart` | 裸 `Colors.green/orange/red` 手写胶囊 |
| `TagChip(label, onTap, onRemoved, selected)` | `app_chips.dart` | 分类/作者标签的多套实现 |
| `CountBadge(count, tone, max)` | `app_chips.dart` | 未读数徽标 |
| `StatusDot(tone, size, pulsing)` | `app_chips.dart` | 在线/离线指示 |
| `KeyValueRow(label, value, valueColor, copyable)` | `app_chips.dart` | 详情面板的"标签: 值" |
| `ToolIconButton(icon, onPressed, tooltip, selected, size, color)` | `app_chips.dart` | 工具栏小按钮的尺寸/悬停态 |
| `EmptyState(title, description, icon, action, compact, padding)` | `empty_state.dart` | 10 份各写各的空状态 |
| `AppLoading(message, size)` / `Scrim(child, visible)` / `SkeletonBox(width, height, borderRadius)` | `empty_state.dart` | 写死的 `Colors.black.withValues(alpha:.3)` 遮罩 |
| `SectionHeader(title, subtitle, trailing, leading, icon, dense, collapsible, expanded, onToggleExpanded)` / `OverlineLabel(text, spacing)` | `section_header.dart` | 约 12 份小节标题（仅设置模块就 7 份） |
| `ContentContainer(child, width, padding, scrollable, controller, physics)` | `page_container.dart` | 18 种不同 `maxWidth` |
| `AppSplitView(sidebar, body, sidebarWidth, gap, minBodyWidth)` | `page_container.dart` | 各页 `Row + SizedBox(魔数) + Expanded` |
| `GlassSurface` / `GlassAppBar` / `GlassFloat` / `GlassMenuItem` | `glass_surface.dart` / `glass_menu.dart` | 见 §6 |

`Tone` 枚举（`neutral/success/warning/danger/info/accent`）是组件侧的语义档位，
用 `resolveToneColor(s, tone)` 在一帧内解析成具体颜色。

内容宽度只有四档：`ContentWidth.narrow`(460) / `medium`(680) / `regular`(920) / `wide`(1440)。

---

## 8. 编写规范（硬约束）

1. 取色只走 `AppSemantic.of(context)`；**禁止** `isDark ? … : …` 分支和裸 `Colors.*`。
2. 尺寸只走 `AppTheme.metrics`，超档用 `scaleW()`；**禁止**裸数字与 `int.w`。
3. 文字只走 `AppTextStyles.*`；**禁止**裸 `TextStyle(...)`（丢 fontFamily）。
4. 时长/曲线只走 `AppMotion.*`。
5. 弹窗用 `showDialog`，不用 `Get.dialog`。
6. 响应式判断：`SizeUtils.isDesktop / isMobile` 按**平台**分（macOS·Windows / iOS·Android）；
   按**窗口宽度**降级用 `isPhone`（宽 <600），`_adaptiveScaleFactor()` 会自动收紧所有 `scaleW` 值。
7. 注释必须中文，且**不要删除已有注释**——现有注释大量是踩坑记录（本文多条规则就来自它们）。
8. 命名：页面 `_screen.dart` 结尾、class `Screen` 结尾、继承 `BasePage`。
9. Flutter 只做 UI 与 UI 相关数据处理；逻辑/存储/文件/进程一律 Rust（FRB）。
   这条目前仍有违反，见 §10。
10. **不要全仓 `dart format`**：HEAD 本身不是 format-clean，全量格式化会产出上千行噪声 diff。

---

## 9. 视觉验收：离屏 golden

不启第二个 `flutter run`（会抢 redb 单实例锁，且用户自己的会话热重启即可）。
视觉改动一律走 golden：

```bash
flutter test --update-goldens test/design_system_render_test.dart
flutter test test/music_player_render_test.dart
```

现有：`design_system_render_test.dart`（设计系统总览明暗）、`menu_render_test.dart`（菜单）、
`music_player_render_test.dart`（播放器列表行，含悬停态）。产物在 `test/goldens/`。

三个必须知道的坑：

1. **有无限循环动画就不能 `pumpAndSettle`**——正在播放行的跳动指示条、`StatusDot` 的
   脉冲、骨架屏的呼吸都永远 settle 不下来，测试直接超时。改用
   `await tester.pump(); await tester.pump(const Duration(milliseconds: 400));`。
2. **字体要手动加载**：`FontLoader` 挂 `FZLanTingYuanS-EB-GB` + 从
   `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf` 加载图标字体，
   否则中文渲染成豆腐块、图标全是方框。
3. **悬停要真实指针**：`createGesture(kind: PointerDeviceKind.mouse)` **必须 await**，
   再 `addPointer / moveTo / removePointer`，不然 `MouseRegion` 不触发。

`test/failures/`（golden 不匹配时 Flutter 吐的 diff 图）是临时产物，不要提交。

---

## 10. 迁移进度与已知缺口

### 已完成

- 语义色层 + token 地基（`app_semantics.dart` / `app_colors.dart` / `ThemeMetrics` / `AppTextStyles` / `AppMotion`）
- macOS 原生窗口透出与磨砂
- 主题预览页重写为设计系统总览（`/theme-preview`）
- 菜单与浮层精修（`GlassMenuItem`、透明度档位）
- 悬停状态层地基（水洗方向 + `Hoverable` 画层顺序 + 骨架屏 lerp）
- **音乐播放器整模块**接入（9 个文件），顺带修掉两处"界面在骗人"的功能缺陷：
  搜索无结果时连搜索框一起被空状态替换（死路）、沉浸式播放器私有的 EQ 滑块不调
  `applyEqBands`（调了等于没调）

### 未完成（按可见度排序）

| 缺口 | 现状 | 复测方式 |
|---|---|---|
| 全站历史取色未收敛 | `lib/` 内（不含 `core/theme/`）`LightColors.`/`DarkColors.` 385 行、裸 `Colors.{green,red,orange,blue,grey,gray,teal,purple,yellow}` 276 行 | `grep -rn "LightColors\.\|DarkColors\." lib/ --include="*.dart" \| grep -v "lib/core/theme/" \| wc -l`；把 pattern 换成 `"Colors\.\(green\|red\|orange\|blue\|grey\|gray\|teal\|purple\|yellow\)"` 即得后者 |
| 共享组件库未铺满 | 大量页面仍手搓卡片/空状态/小节标题 | 见 §7 右列 |
| 动效体系未铺满 | 除歌词行与 `Hoverable` 外多数页面仍是各自的手写时长 | `grep -rn "Duration(milliseconds:" lib/pages/` |
| `surfaceActive` 仍是实心 | 选中态会打断窗口磨砂（悬停已修，选中未修） | `app_colors.dart:173,205` |
| `textTertiary` 在画布上偏淡 | 亮色 `#74756E` 压白卡片 4.65:1（勉强过 AA），压画布 `#F1F1EE` 只有 4.11:1；`caption` 用它，13px 以下正文场景仍不达标 | `app_colors.dart:214` |
| 真·背景模糊菜单 | `GlassMenuItem` 靠 `ThemeData.hoverColor`，浮层模糊仍需 `MenuAnchor.overlayBuilder` | `glass_menu.dart` |
| Flutter 侧调系统命令 | `music_player_viewmodel.dart:838` 用 `scutil --proxy`、`:1223` 用 `open -R`/`explorer`，违反 §8.9，应下沉 Rust | `grep -rn "Process.run" lib/` |
| 底部播放条重复/空实现 | 播放模式按钮在中间控件排和右侧功能排各出现一次（图标/tooltip/回调全同）；"播放列表"按钮 `onPressed` 是空函数体，侧栏根本没有可切换的显隐状态 | `bottom_player_bar.dart` |
| Windows 透出未实测 | 子窗口 HWND 的 alpha 行为未验证 | `window_backdrop.dart:46` |

---

## 11. 相关提交

```
40452f4 refactor(ui): 音乐播放器整块接进设计系统语义层
e5c94d6 fix(ui): 悬停状态层在亮色下真正可见——水洗方向跟底色走
9534679 feat(ui): 菜单收进设计系统——新增紧凑菜单项，浮层统一玻璃口径
```
