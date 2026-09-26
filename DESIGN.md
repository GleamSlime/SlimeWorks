# SlimeWorks 设计系统

> 一套**中性底 + 反相墨主色**的界面语言：层次靠明度阶梯和 1px 实心描边拉开，不靠染色；
> 反馈靠同一个形状改尺寸/改圆角/改颜色，不靠加东西。本文是**取色、取尺寸、取动效的唯一口径来源**。
>
> 代码入口：`lib/core/theme/`（令牌）+ `lib/core/widgets/`（组件）+ `lib/components/window/`（外壳）
> + `lib/pages/theme_preview_screen.dart`（可视化总览，路由 `/theme-preview`）
> + `lib/pages/motion_lab/`（动效参考集，隔离在主题之外，§12）。
>
> 阅读顺序：§1 分层 → §2 取色 → §3 尺寸 → §4 文字 → §5 动效 → §6 外壳 → §7 磨砂 → §8 响应式
> → §9 组件 → §10 规范 → §11 验收 → §12 动效实验室 → §13 进度。
> 标了 **🔧 待落地** 的条目是已定的契约、代码还没跟上，改动时按契约做，不要按现状反推。

---

## 0. 六条总纲

1. **中性底**：所有表面都是纯灰，不掺色温。灰一旦带暖，卡片和画布的分层就发"糊"，状态色也跟着串味。
2. **主色是墨，不是品牌色**：主按钮、选中态、开关走"反相"——浅色档压成近黑，深色档提为近白。
   品牌紫退出主色位，只活在 `info` 和图表里当点缀。
3. **描边承担层次，投影只承担"离地一点点"**：`border` 是实心灰阶、能独立成立；
   投影整体压到极轻（`raised` 只有 y1/blur2）。投得越重越像贴了张纸上去。
4. **一个形状，永不分裂**：一个控件的默认/悬停/选中/展开是**同一个元素**在改宽高、改圆角、
   改底色，内容在切换瞬间糊一下。不叠第二层描边、不加第二颗光晕。
5. **两族尺寸不能混用**：宽度族 `scaleW` 只跟窗口，字号族 `scaleS` 还乘用户的界面字号比例。
   混用是本项目最贵的一次翻车（侧栏图标条被顶穿）。
6. **桌面留磨砂，但磨砂只在"面板"上**：内容卡片一律实色，只有侧栏、顶栏、浮层这类
   常驻/悬浮的面板透出底下内容。实色卡片叠模糊只会两头都不像。

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
业务代码写 `isDark ? DarkColors.x : LightColors.y` 就是绕过了这一层，属于待清理项（§11）。

`style_tokens.dart` 是**采集自参考实现的令牌底料**（`DesignPalette` / `DesignRadius` /
`DesignShadow` / `DesignType` / `DesignSpace` / `DesignFont`），**故意不接进运行时**：
它只被样式总览页 `style_showcase_screen.dart` 消费，用来对照"参考值 vs 我们的值"。
不要把它当第二套运行时主题用，也不要为了"统一"把它焊到 `AppSemantic` 上。

---

## 2. 取色唯一入口：`AppSemantic`

```dart
final s = AppSemantic.of(context);   // 或 context.semantic.surface
final m = AppTheme.metrics;
```

以 `ThemeExtension` 注册进 `ThemeData`，因此随明暗自动切换、参与主题过渡动画、
调用点不需要 `brightness` 分支。

### 2.1 角色表（当前真实值）

**表面与描边**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `canvas` | `#FAFAFA` | `#0A0A0A` | 窗口画布，最外层底色 |
| `surface` | `#FFFFFF` | `#171717` | 一级表面：卡片 / 面板 / 选中白卡 |
| `surfaceRaised` | `#FFFFFF` | `#262626` | 二级表面：卡片内嵌块 / 浮起菜单 |
| `surfaceSunken` | `#F5F5F5` | `#0F0F0F` | 下沉表面：输入框底 / 图标占位底 |
| `surfaceHover` | `0x0A000000` | `0x14FFFFFF` | 悬停状态层（半透明水洗） |
| `surfaceActive` | `0x14000000` | `0x1FFFFFFF` | 按压态 |
| `hairline` | `0x0D000000`（5%） | `0x14FFFFFF`（8%） | 发丝分隔线：相邻表面几乎无接缝处 |
| `border` | `#E5E5E5` | `0x1AFFFFFF` | 常规描边（亮色档是**实心灰**，不是半透明黑） |
| `borderStrong` | `#A3A3A3` | `0x33FFFFFF` | 强描边：需要边界感处 |

> `darkSurfaceSunken` 不能等于 `darkCanvas`：否则"下沉"控件（输入框 / 图标底板 / 侧栏）
> 贴在画布上完全隐形，落在卡片上又像一个挖空的洞。

**文字**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `textPrimary` | `#0A0A0A` | `#FAFAFA` | 主文字、图标默认色 |
| `textSecondary` | `#525252` | `#A3A3A3` | 次级文字 |
| `textTertiary` | `#737373` | `#737373` | 说明文字、分组标签 |
| `textDisabled` | `#A3A3A3` | `#525252` | 禁用 |

**强调色（反相墨）**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `accent` | `#171717`（`AppBrand.ink`） | `#E5E5E5`（`AppBrand.inkInverse`） | 主按钮底、选中指示器、开关滑块 |
| `accentOn` | `#FAFAFA` | `#171717` | 强调底上的文字 |
| `accentText` | `textPrimary` | `textPrimary` | 选中文字（墨色语言里选中字不需要变色，只加粗） |
| `accentContainer` | `#F5F5F5` | `#262626` | 选中底 / 图标底（低浓度强调） |
| `accentContainerBorder` | `#E5E5E5` | `#404040` | 选中白卡的描边 |
| `accentGradient` | 两端同色 `ink` | 两端同色 `inkInverse` | 只为还吃 `LinearGradient` 的老签名保留，**当纯色用** |

**遮罩 / 投影 / 玻璃**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `scrim` | `0xB3000000` | `0xB3000000` | 模态遮罩 |
| `shadowKey` | `0x0F000000` | `0x66000000` | 投影主层 |
| `shadowAmbient` | `0x07000000` | `0x33000000` | 投影扩散层（自动 blur×2、y×2） |
| `glassTint` | `0xB8FFFFFF` | `0x9E171717` | 玻璃面板着色 |
| `glassPanelTint` | `0x8CFFFFFF` | `0x6B171717` | 常驻面板（比卡片更透，以便透出桌面） |
| `glassBorder` | `border` | `border` | 玻璃上的发丝描边 |
| `glassBlur` | `24`（`AppGlass.blurMedium`） | 同 | 背景模糊半径 |

### 2.2 状态层方向：**水洗永远朝"看得见"那侧走**

这是本项目踩过最深的一个坑，值得单独写死。

- 亮色侧表面本来就是白（`#FFFFFF` 卡片 / `#FAFAFA` 画布），再叠半透明**白**是零反馈。
  历史上 `lightSurfaceHover = 0x2DFFFFFF` 正是这个值——卡片、列表行、菜单在亮色模式
  下**完全没有悬停**。现改为半透明黑，压白得 `#F5F5F5`、压画布得 `#F0F0F0`，依旧透得下去。
- 暗色侧表面比白暗，所以继续用**提亮**的白水洗。
- 两侧方向相反是有意为之，不是不一致。

配套两条硬规则：

1. **状态层必须是半透明的**，因为它画在内容**之上**（实心色会把文字整个盖掉）。
   `Hoverable` 用 `Stack` 三层：底色在下 → 内容 → 状态层在上并 `IgnorePointer`。
2. **半透明色不能进 `Color.lerp` 的端点**。骨架屏原先 lerp 到 `surfaceHover`，
   alpha 一起被插值，最亮一帧直接消失；端点必须换成实心色（现用 `surfaceRaised`）。

### 2.3 强调色的对比度下限

墨色主色天然满足（`#171717` 压 `#FAFAFA` ≈ 16:1）。**用户自选强调色**仍要过 4.5:1：
`AppTheme._ensureContrast()` 在填进 `semantic.accent` 前按底色压深/提亮。

一个必须知道的例外：设置页第一档"跟随主题"是**哨兵值**而不是真颜色
（`AppTheme.kFollowThemeAccent`）。近黑在明暗两档是两个值，硬把 `#171717` 送进
`_ensureContrast` 会在暗色档被提成中灰，所以 `_applyCustomization` 里对它短路，
直接把语义层自己的 `accent` 填回去。加新"语义档"强调色时照这个模式办，不要塞真色值。

### 2.4 投影：`s.elevation(Elevation.x)`

五档，key + ambient 双层，替代散落的各写各的 `BoxShadow`：

| 档位 | y / blur / spread | 用途 |
|---|---|---|
| `none` | 0 | 贴平 |
| `raised` | 1 / 2 / 0 | 微浮：侧栏选中白卡、静止卡片 |
| `card` | 1 / 3 / 0 | 卡片悬停 |
| `floating` | 10 / 15 / -3 | 悬浮工具条、命令面板 |
| `overlay` | 20 / 25 / -5 | 弹窗 / 菜单 |

ambient 层自动取 `blur×2`、`y×2`。停靠类控件（如底部播放条）要把 y 翻成负值，
向下的影子落在窗口外等于没有。

**描边优先于投影**：卡片默认是 `surface` 底 + `border` 描边 + `raised`，
悬停才把描边升到 `borderStrong`、投影升到 `card`。只升投影不升描边，在浅色档几乎看不出来。

### 2.5 状态色族

每个状态给两档：**主色**（点、图标、图表线）和**容器上的文字色**。
文字必须单独压深/提亮：状态主色是给"点"用的，直接拿它当小字号文字，
亮色下 `#00BB7F` 在白底只有 2.4:1，读起来是一片糊。

| 角色 | 亮 `.color` | 亮 `.onContainer` | 暗 `.color` | 暗 `.onContainer` |
|---|---|---|---|---|
| `success` | `#00BB7F` | `#004E3B` | `#00BB7F` | `#5EEAD4` |
| `warning` | `#EDB200` | `#733E0A` | `#EDB200` | `#FCD34D` |
| `danger` | `#E40014` | `#9F0712` | `#FF6568` | `#FFB4B6` |
| `info` | `#8D54FF` | `#4D179A` | `#AC4BFF` | `#D6BBFE` |
| `neutral` | `#737373` | `#404040` | `#A1A1A1` | `#D4D4D4` |

容器底与描边从主色派生，**不要手写 `withAlpha`**：
`role.container` = 主色 @ 10%（亮）/ 16%（暗），`role.containerBorder` = @ 22%（亮）/ 28%（暗）。
暗色浓度更高，否则在深灰表面上看不出层次。

> `danger` 只用于**破坏性**操作（删除、从库中移除）。收藏/喜欢这类"选中"状态
> 用 `accent`，不是红——原先播放器里两处 `Colors.redAccent` 就是这个口径错位。

### 2.6 身份色板 `AppViz`：图表和图标底，不进语义层

概览/监控类页面里并排的卡片需要一个"身份"来区分（CPU 是天蓝、内存是暖橙…）。
这些色相**不是语义角色**——既不是"成功/危险"，也不是"强调"——所以单列一档
（`app_viz.dart` 的 `AppVizSet.light` / `.dark`），**别塞进 `AppSemantic` 冒充状态色**。

一个 `AppViz` = `base`（主线/图标色）+ `to`（渐变终点），成对出现：
图标底的水洗色、折线本身、折线末端那个圆点共用同一个身份。

用法固定三件套：图标底 `viz.base.withValues(alpha: 暗 0.18 / 亮 0.12)`、
图标 `viz.base`、图表线 `viz.gradient`。**身份色只出现在图标底和图表里，不做卡片描边、不做按钮底。**

---

## 3. 尺寸令牌：`AppTheme.metrics`

```dart
final m = AppTheme.metrics;
BorderRadius r = m.radiusCard;   // 注意：radius* 是 BorderRadius，不是 double
double sp = m.kSpace16;
```

- **语义圆角**（调用点优先用这组，不要记数字）：
  `radiusControl`(8) 按钮/控件 · `radiusField`(8) 输入框 · `radiusCard`(10) 卡片/列表项 ·
  `radiusPanel`(14) 面板/分栏 · `radiusOverlay`(14) 弹窗/抽屉 · `radiusPill`(999) 胶囊
  —— 整体刻意收得很小：圆角一大，小尺寸控件就变成一颗颗胶囊，列表读不出边界。
- **数值圆角**：`radius2/3/4/6/8/10/12/14/16/18/20/22/24/25/28/32/40/100/999`
- **间距**：`kSpace1/2/3/4/5/6/8/10/12/14/16/18/20/24/32/40/44/48/56/64/80`
  （别名 `paddingSmall/Medium/Large/XLarge`、`spacingSmall…`）
  ⚠️ **没有 `kSpace26/36/96`**，超出档位用 `scaleW(n)`
- **字号**：`fontSize9/10/11/12/13/14/15/16/17/18/20/22/24/28/32/36/48/72`
- **图标**：`iconSize12/13/14/15/16/18/20/22/24/28/32/40/44/48/64/96`（**没有 38**）

### 3.1 两族尺寸：宽度族 vs 字号族（最贵的一个坑）

| 族 | 函数 | 受什么影响 | 用在 |
|---|---|---|---|
| 宽度族 | `scaleW(n)` / `scaleH(n)`，`m.kSpace*`、`m.radius*` | 只跟**窗口宽度** | 间距、尺寸、圆角、描边、图标盒 |
| 字号族 | `scaleS(n)` → `scaleSWithUserFont(n)`，`m.fontSize*`、`m.iconSize*` | 窗口宽度 **× 用户的"界面字号"比例（0.5–2.0）** | 文字、跟随文字的图标 |

**一个容器里不能混用两族**。真实事故：收起态图标条只有 75 设计像素宽，
图标原先走字号族的 `fontSize22`，于是"栏宽不动、图标跟着字体长"，字号比例只要不是 1
就把那一行顶破（`RenderFlex overflowed by 1.1 pixels`）。修法是把图标盒整体换成宽度族
`scaleW(22)`。同理，macOS 三颗窗口灯也只跟 `scaleW`——系统的红黄绿从不随字体变大。

规则：**会随用户字号变长的东西，不能塞进一个宽度固定的窄栏里。** 窄栏（图标条、
工具栏、状态条）内的一切尺寸走宽度族。

推论（同一条坑的第二次发作）：**行尾那簇附属内容必须封顶。** 侧栏主行的标签是
`Expanded`（会被压），后面跟的计数徽章 / 状态点 / 版本号是 `Text`（不会被压），
于是字号比例 2.0 时版本号自己就能吃掉整行——`A RenderFlex overflowed by 15 pixels`。
一律套 `ConstrainedBox(maxWidth: m.kSpace56) + ClipRect`（上限走宽度族，跟行宽同比），
并且源头的 `Text` 自己写 `maxLines: 1, overflow: ellipsis`。**宁可截断，不许顶破。**

### 3.2 为什么宽度类尺寸要 `scaleW` 而不是 `const`

`scaleW(w) = ScreenUtil().setWidth(w * _adaptiveScaleFactor())`，按**当前窗口宽度**折算。
写死 `const _kSidebarWidth = 220.0` 的话窗口缩小侧边栏不会跟着收，所以这类值要写成
`double get _kSidebarWidth => scaleW(220);`——**用 getter，不是 const**。

规范：禁止裸数字和 `int.w`；`AppTheme.metrics` 里没有的档用 `scaleW()`。

### 3.3 高/低分辨率与 DPI：**"看着差不多大"怎么成立**

两条独立的通道，别混：

1. **物理 DPI**（1× / 2× Retina / 4K）：Flutter 的 `devicePixelRatio` 已经把逻辑像素
   折算成物理像素，**这一层不需要项目做任何事**。要防的是"1 物理像素"的东西被抗锯齿
   冲淡——发丝线一律 `width: 1` 固定值，**不要写 `1.w`**（缩放后不足 1 物理像素就糊成灰边）。
2. **窗口尺寸**（同一台机器把窗口拖大拖小）：由 `_adaptiveScaleFactor()` 处理，
   它按 `ScreenUtil().screenWidth` 分档给 `scaleW` 一个 0.94–1.14 的放大系数，
   窄窗（<600）反过来收到 0.94–1.0。字号族再叠一档 `_adaptiveFontScaleFactor()`，
   **放大只吃 70%、缩小只吃 60%**——这是"看着差不多大"的关键：
   窗口翻倍时字不跟着翻倍，否则大屏上全是标题。

由此定三条口径：

- **控件高度、间距、图标盒**：宽度族，随窗口线性走（1920 档约 +8%，1366 档约 +12%）。
- **文字**：字号族，随窗口**亚线性**走，且吃用户字号比例。
- **发丝线/描边**：固定 1 逻辑像素，不吃任何缩放。

🔧 **待落地**：`_adaptiveScaleFactor()` 目前只分四档且上限 1.14，超宽屏（2560+）
与 4K 物理 2× 下仍偏小；外壳改造时一并把档位补齐，并把 `collapsible_sidebar.dart`
里残留的 `1.w` 收掉。

### 3.4 侧栏宽度

- 展开态：`SidebarController.expandedWidth`，用户可拖，默认 240、范围 160–420（设计像素），
  且**不超过窗口宽度的 45%**。
- 收起态：图标条固定 75 设计像素。
- 存的值是设计像素，渲染仍走 `scaleW`，所以窄窗自动收缩的行为不变。

---

## 4. 文本角色：`AppTextStyles`

**字族**：Latin 用内置 `Inter`（400/500/600/700 四档，`pubspec.yaml` 声明），
中文走系统（`PingFang SC` → `Hiragino Sans GB` → `Microsoft YaHei` → `Noto Sans SC`），
最后兜底到内置的 `FZLanTingYuanS-EB-GB`。定义在 `AppTheme._fontFamily` / `_fontFamilyFallback`。

**字重政策**：只用 `w400`（正文）/ `w500`（行标题、按钮、标签）/ `w600`（标题、强调）。
不用 w700 及以上——墨色语言里"重"靠描边和抬升表达，字重拉满只会糊成一片黑。

所有角色都从 `textTheme.bodyMedium` 派生（`_role()`），**不能裸 `TextStyle(...)` 构造**——
裸构造会丢 `fontFamily` 和回退清单，中文会静默落到引擎兜底字上。

| 角色 | 字号 / 字重 / 色 | 用途 |
|---|---|---|
| `pageTitle` | `headlineMedium` | 页面主标题（外壳里由面包屑承担，见 §6.3） |
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

⚠️ **`TextStyle` 在组件主题里是整条替换，不是叠加**。`ButtonStyle.textStyle`、
`dialogTheme.titleTextStyle`、`popupMenuTheme.textStyle`… 一共 20 处，裸写就会把
主题字阶的 `fontFamily` 丢掉（表现是：只有按钮和菜单里的中文是豆腐块，其余正常）。
统一走 `AppTheme._font(...)` 和 `_buttonTextStyle()`。

---

## 5. 动效：`AppMotion`

### 5.1 语言

**一个形状，永不分裂。** 控件的默认 / 悬停 / 选中 / 展开是同一个元素在改
**宽高、圆角、底色**，内容在切换的那一瞬糊一下（短暂模糊），不是"旧的东西消失、
新的东西出现"。指针要驱动它（悬停即响应），点击和拖拽要有真实的跟手感。

允许：
- 弹簧收尾，**最多一次轻微过冲**（overshoot ≤ 6%）。
- 状态切换时**尺寸、圆角、颜色同时动**，共用一条时间轴。
- 转场用"镜头拉近"的思路：让**当前状态的那个元素**放大铺满画面，而不是换一张脸。

禁止（每一条都是真实翻车过的观感）：
- ❌ 弹跳缓动（bounce）、多次回弹。
- ❌ 粒子、爆花、星星点点。
- ❌ 发光 / glow / 外发光描边。层次只允许来自描边和投影。
- ❌ **UI 骨架上铺渐变**（按钮底、卡片底、侧栏底一律纯色）。渐变只活在图表线里。
- ❌ 图标描边粗细不一致（正在做全局图标组件，见 §9.11）。
- ❌ **用模糊表达远近**（堆叠越深越糊）。上面允许的"短暂模糊"只活在状态切换的那一瞬；
  常驻的景深糊在白药丸压近白舞台这种低对比内容上一眼读作"没对齐/渲染坏了"。
  远近只用位移、缩放、变暗三样表达。
- ❌ 无事发生的空等时间；也 ❌ 一眼看出是模板套出来的动效。

### 5.2 时长节奏

原先散落 250/280/300/400/600ms 各自为政，观感"有的跟手、有的迟钝"。

| 档 | 值 | 对标的外部档位 | 用在 |
|---|---|---|---|
| `instant` | 90ms | micro(80) | 颜色/底色换（水洗、hover 起） |
| `fast` | 160ms | quick(150) | press 起、退场统一档、hover 收 |
| `base` | 220ms | fast(250) 减一档 | 状态类：展开/收起/选中/切换 |
| `slow` | 320ms | medium(350) | 空间类：页面转场、抽屉、弹窗进场 |
| `emphasis` | 460ms | very-slow(500) | 一次性的重头动作（启动入场） |
| `stagger` | 45ms | 参考库取 40–90 | 列表逐条入场间隔 |
| `entrance`/`cascade` | 600/900ms | — | 开机整块面板入场，只播一次 |

**反馈类必须 ≤160ms**。悬停超过这个值就不叫"跟手"，叫"卡了一下才理你"。

**退场一律比进场快**：进场要给"落位感"，退场只要"别挡路"。同一动作的开/收取**相邻两档**
（开 `base` → 收 `fast`；开 `slow` → 收 `base`），曲线跟着换
（`decelerate` 进 / `accelerate` 出）。倒放同一条时间轴是省事，不是正确。

### 5.3 曲线与弹簧

现有：`standard`（通用，起步快收尾稳）、`decelerate`（进场/展开，落位感）、
`accelerate`（退场/收起，不拖尾）、`linearish`（进度条）。
`AnimatedX` 一律用 `AppMotion.defaultDuration` + `defaultCurve`，不要每处手写。

弹簧档已落地：`AppMotion.spring`（`mass 1 / stiffness 260 / damping 22`，
阻尼比 ζ≈0.68 → 过冲约 5%，**只回一次**）。两种用法：

- 能手握 `AnimationController` 的走 `animateWith(SpringSimulation(spring, …))`；
- `AnimatedContainer` / `AnimatedSize` 这类只吃 `Curve` 的走 `AppMotion.springCurve`
  （同一条弹簧的近似曲线，过冲量对齐，免得两个档位观感对不上），时长取 `springSettle`。

规则：**只有"状态改变"用弹簧，hover/press 这类高频反馈仍然用短时长 `Curves`**——
弹簧在 90ms 尺度上看不出过冲，只会让手感发黏。

🔧 待接线：全站绝大多数 `AnimatedX` 还挂在 `standard` 上，按 §5.5 逐面迁到弹簧档。

配套件：

- `StaggerEntrance`（逐条浮现，替代各页手写的 `Future.delayed(300 + i*80)`——
  那种写法会造成"可点击但无内容"的空窗）。
- `StateTransitionAnimation`（图标+文字换脸，已带 in/out 位移与瞬时模糊，
  是 §5.4 那一族唯一的现成消费者）。
- 🔧 `AppPageTransitions.fadeUp` **定义了但没人用**：路由转场现在走
  `app_routes.dart:275` 手写的 320/260ms + `easeOutCubic/easeInCubic` 淡入
  （另有一条带 0.985 微缩放的 builder）。260 不在 §5.2 的档位上，两条口径要合一条；
  `StateTransitionAnimation.animationDuration` 的默认值同样是手写的 400ms。

### 5.4 位移 / 缩放 / 瞬时模糊：三族新档

**位移走宽度族**，一律是 getter（`AppMotion.travelBase => scaleW(8)`），
不是 `const`——原因和 §3.2 同一条：窗口从 1366 拖到 2560，8 设计像素的位移要跟着长，
否则大屏上动作"小到看不见"，就退化成了淡入淡出。

| 档 | 值（设计像素） | 用在 |
|---|---|---|
| `travelMicro` | 4 | 文字/图标换脸、hover 时箭头让位 |
| `travelSmall` | 6 | 按压下沉、校验失败抖动 |
| `travelBase` | 8 | 页面转场上浮、抽屉入场 |
| `travelMedium` | 12 | 面板从触发点下方展开 |
| `travelLarge` | 30 | 整块内容换脸（列表↔详情这类） |

**缩放是无量纲**的，只有四个合法值，别在页面里现写 `0.93`：
`scalePress 0.98`（按压）/ `scaleMenu 0.97`（菜单从触发点长出）/
`scaleEnter 0.96`（浮层进场起点）/ `scaleRetreat 0.99`（收起终态，留 1% 才看得出是
同一个东西缩回去，而不是消失）。

**瞬时模糊**是这套语言里"内容换脸"的那一下：状态切换的瞬间给旧内容加模糊、新内容从模糊里
结像（`StateTransitionAnimation` 已经是这个做法）。它和磨砂玻璃的
`BackdropFilter` 是**两件事，别互相引用值**：

| 族 | 值 | 对象 |
|---|---|---|
| `AppMotion.blurContent 2 / blurPanel 4 / blurPage 8` | sigma，**几帧之内退干净** | 正在换脸的内容 |
| `AppGlass.blurSoft 12 / blurMedium 24 / blurStrong 40` | sigma，**常驻** | 玻璃面板背后 |

内容模糊停在半路就是"糊了"，不是"在动"——进出场两侧都必须收到 0。

### 5.5 场景对照：每一面具体怎么动

按可见度排序，不是按参考库编号。**「现状」列是实测，不是计划**。

| # | 场景（本项目落点） | 参数口径 | 现状 |
|---|---|---|---|
| 1 | 侧栏选中：白卡抬起 + 墨条长高 | 底色/圆角/描边/投影同一条时间轴，指示条 `height 0→20` 用 `spring`；不加位移 | 尺寸齐、曲线是 `standard` 🔧 |
| 2 | 侧栏 hover 水洗 | `instant` 进 / `fast` 出，只改底色 | ✅ |
| 3 | 侧栏分组展开 + 子项连接线 | `AnimatedSize(slow)` + 行末箭头 `›`↔`⌄` 转 90° 同一时间轴；竖干**自上而下描出**、横枝按 `stagger` 依次长出；折叠整族一起收，不逐条退 | 静态几何已出图验收（`sidebar_tree_light`），描干/stagger 未做 🔧（§6.5） |
| 4 | 侧栏宽度拖拽 | 拖拽期间 `Duration.zero` 跟手，松手用 `spring` 落到目标宽 | ✅（`kWidthAnimation`） |
| 5 | 顶栏面包屑层级切换 | 末端文字换脸：`travelMicro` + `blurContent`，上级药丸 hover `instant` | 两态已出图（`shell_topbar_title_light` / `shell_topbar_breadcrumb_*`），换脸动效未做 🔧 |
| 6 | 页面转场 | 进场 `slow` 退场 `base`，淡入 + `travelBase` 上浮（或 0.985 微缩放，二选一）+ `blurPage` 的一下 | 时长已并到 token 档（`kSlowTransitionDuration = slow`、退场取 `base`），仍无上浮无模糊 🔧 |
| 7 | 弹窗 / 浮层 / 菜单 | 从触发点为原点缩放：菜单 `scaleMenu`、弹窗 `scaleEnter`，开 `base`~`slow`、收 `fast`；`ClipRect` 要留出投影扩散位 | 只有淡入，缩放原点未接 🔧 |
| 8 | 面板从按钮下方展开（筛选、工具面板） | 位移取**面板高的一半**（`travelMedium` 起），靠淡出+模糊补，不做整高硬推；开 `slow` 收 `base` | 🔧 |
| 9 | Toast / 任务进度条 | `travelBase` 上浮 + `scaleMenu` + `blurContent`，开 `slow` 收 `fast` | `floating_task_progress.dart` 目前**整块静态**（无一个 `Animated*`）🔧 |
| 10 | 通知计数徽章（侧栏、托盘） | 外圈让位用位移、内圈缩放+淡入分开两条钟；**用 `spring` 不用 bounce**，收 180ms 级 | 🔧 |
| 11 | Tab / 分段选择器 | 滑块单元素平移 + 改宽（`spring`），未选不描边（同 §6.4） | 手 🔧 |
| 12 | 开关 Toggle | 滑块 `spring` 单次轻微过冲；轨道底色**独立时间轴**交叉淡入 | 🔧 |
| 13 | 勾选 / 成功反馈 | 底色 150ms 填充 + 勾线**描出来**（`stroke-dashoffset` 等价：`DrawIcon` 的 path 进度）350ms；**退场不倒放**，只淡出 | `DrawIcon` 已具备底料 🔧 |
| 14 | 骨架屏 → 真内容 | 骨架只脉冲一次就交叉淡入（两层同 blur）；**回退时关掉所有过渡**，否则反向闪 | `Hoverable` 骨架 lerp ✅ / 回退抑制 🔧 |
| 15 | 数值变化（仪表盘指标） | 逐位上滑 `travelBase`，位间 `stagger`，**等宽数字**（`tabularFigures`，§6.5）防行抖；不要弹跳计数 | 🔧 |
| 16 | 流式输出（Ollama 生成、下载日志） | 按词进：间隔 60ms、单条 `base`、`blurContent` 1 档；状态行换行时进出同时播 | 🔧 |
| 17 | 校验失败抖动 | `travelSmall` 四段往复，末段不回弹；错误态 3s 后自动淡回 | 🔧 |
| 18 | 状态点脉冲（节点/服务在线） | `cycle 1200ms`，只走状态色或 `AppViz`，同族共享节拍、各自延迟 | 🔧 |
| 19 | 通知堆叠（任务队列） | 最多露 3 张：每深一层 `scale 0.94`、Y 抬 `travelMedium`、透明度 0.6、blur 加一档；hover 展开成列并去掉深度缩放 | `floating_task_progress.dart` 现在只显一条、且完全静态 🔧 |

### 5.6 按输入方式补齐覆盖

上面那张表是"哪一面怎么动"，这一张是"**每一种输入都得有真实反馈**"——
动效是不是"活"的，取决于这七行有没有漏，而不是单点做得多花。

| 输入 | 最低承诺 | 档位 | 现状 |
|---|---|---|---|
| 悬停 Hover | 底色换水洗 + **光标形状换**（可点用 `click`、可拖用 resize 档），不改尺寸 | `instant` 进 / `fast` 出 | 侧栏、面包屑药丸、把手已做；仍有控件挂着默认光标 🔧 |
| 键入 Type | 光标闪烁不属于动效、不许给它加曲线；校验提示/补全走**文字换脸**（§5.5 的 5） | `fast` | 校验提示是整块重画 🔧 |
| 按压 Press | 按下即变：`surfaceActive` + `scalePress`（或 `travelSmall` 下沉），抬起即回；**水波纹在有形状反馈的地方一律 `NoSplash`** | `instant` 进 / `fast` 出 | 侧栏已 `NoSplash`；Material 默认涟漪仍散在各处 🔧 |
| 拖拽 Drag | **1:1 跟手**（拖拽期间时长为 0），松手才交给弹簧落到目标；过程中给实时读数 | 拖中 `Duration.zero` → 松手 `spring` | 侧栏宽度 ✅ |
| 滑抹 Swipe | 移动端列表项侧滑、页面横滑：位移跟手，越过 1/3 才算成行，否则弹回 | `spring` | 阅读器/列表未接 🔧 |
| 选择 Select | **同一个元素换态**（抬升 + 描边 + 指示条），不允许多长出一个新形状来表意 | `spring` / `base` | 侧栏 ✅；卡片多选仍各写各的 🔧 |
| 推移 Slide | 面板、抽屉、页面转场：从**触发它的方向**进来，位移取该方向尺寸的一半、用淡出和模糊补，不做整尺寸硬推 | `slow` 进 / `base` 收 | 侧栏 ✅；页面转场只有淡入 🔧 |

### 5.7 触摸端与性能的折价

参考库是 Web 的、以 hover 为中心，本项目含移动端，两条必须改：

- **hover 档在触摸端不存在**。凡"hover 才动"的（§5.5 的 2 / 5 / 7），移动端改成
  **press 起、release 收**，时长取 `fast` 档；`Tooltip` 类只在长按后显，短按直接执行。
- **`ImageFilter.blur` 是每帧一次的着色器**，代价远高于位移/缩放。三条硬线：
  ① 滚动列表的**行内**禁瞬时模糊（几十行同时糊 = 掉帧），行内只允许位移和底色；
  ② 移动端内容模糊降一档（`blurContent`→1，`blurPage`→`blurPanel`），壁纸本身糊的
  玻璃（§7）在移动端一律换成实色；③ 常驻模糊只允许出现在面板层，且数量按 §7.1 计。

### 5.8 明确不收的

参考库里这些**看着热闹，但不进本项目**（每一条都对应 §5.1 的禁止项）：

- ❌ 多次回弹的 bounce 曲线（参考里徽章、开关、点赞都在用）→ 换成 `spring` 的一次轻微过冲。
- ❌ 粒子爆花、星星点点（点赞、成功特效）→ 反馈只允许来自形状、颜色、描边。
- ❌ 跟随指针的 3D 倾斜卡 + 高光（glare）→ 违反"骨架不铺渐变/不发光"，且在密集列表里跟不手。
- ❌ 扫光 shimmer 用在静态标题上 → 只允许出现在真正"还在加载"的东西上（§5.5 的 14/16）。
- ❌ 文字外发光、霓虹描边、渐变填充 UI 骨架。

---

## 6. 应用外壳（布局契约）

外壳是这版语言的**门面**，六个必要元素，缺一个就不算这套语言：

```
┌──┬────────────┬──────────────────────────────────────────┐
│灯│  LOGO      │  拖拽把手                                  │
│  ├────────────┤  ┌────────────────────────────────────┐  │
│  │ 分组标签    │  │ 面包屑  A / B / C        [actions] │  │ ← 顶栏：标题 + 面包屑
│  │ ▍选中项     │  ├────────────────────────────────────┤  │
│  │  └─ 子项    │  │                                    │  │
│  │  └─ 子项    │  │            内容区                   │  │
│  ├────────────┤  │                                    │  │
│  │ 底部固定项  │  └────────────────────────────────────┘  │
└──┴────────────┴──────────────────────────────────────────┘
```

代码位置：`lib/components/window/`（`desktop_layout.dart` 装配、`collapsible_sidebar.dart`
侧栏、`desktop_scaffold.dart` 的 `DesktopTopBar`、`sidebar_resize_handle.dart` 把手、
`screen_top_bar.dart` 窗口灯）。

### 6.1 侧边栏

- **底色 = `canvas`**，与内容区同底，只靠右缘一条 `glassBorder` 发丝线分栏。
  不用 `glassTint`：它在浅色档合成后接近纯白，和卡片同色，侧栏就读不出是一个独立面板。
  也不用 `surfaceSunken`：栏底一旦下沉，选中白卡和栏底就糊成一片。
- 贴窗口左/上/下边缘，**不自带圆角**——圆角交给 macOS 的窗口蒙版裁。
  历史上 `margin + radius12` 的浮卡比窗口角（实测半径约 19pt）更方，两条弧在角上会分叉。
- 透明度只在 macOS 上留（透出原生振动层）：浅色 120 / 深色 175，
  设了全局封面图时统一 100。深浅不对称是有实测依据的：深色玻璃压在亮壁纸上会被
  提亮到中灰、浅色字只剩 2.8:1。
- 收起态 = 75 设计像素的图标条，内部一切尺寸走**宽度族**（§3.1）。
- **层级只从路由元数据读一份**（`app_sidebars.dart`）：`showInSidebar` 的含义是
  "这一页能从侧栏点到"——站在顶层和站在父项展开里都算，**具体在哪一层由 `sidebarParent` 决定**。
  父项没进侧栏名单（没列进来、或被权限挡了）时，子项退回顶层显示：静默丢掉的话，
  症状是"某个页面从侧栏消失了"，很难往层级元数据上想。
- 展开箭头（`expandMore`）在**行末右端**，不在行首：行首那一格是图标和选中指示条的位置，
  再塞一个箭头会先撞车，读起来也像两列。收合 `›`、展开 `⌄`，和分组标题那枚是**同一个图形**——
  用带杆的整支箭头会读成"往下跳"，而且两枚箭头的笔画粗细不一样，一眼就是拼的（§9.1）。

### 6.2 侧边栏 logo 区 ✅ 已落地已出图（`_SidebarLogo`）

位置在窗口灯之下、分组标签之上，图标 + 字标（"史莱姆工坊"）+ 折叠按钮一条 `Row`。契约：

- 位置：窗口灯之下、分组标签之上；展开态显示图标 + 字标，收起态只显示图标。
- 图标尺寸走宽度族（展开 22 / 收起 22），字标 `fontSize14` w600，字标用 `AnimatedSize` 收放。
- 点击 = 回首页（`DashboardRoute`），和选中指示器共用同一套形变（§6.4）。
- 收起↔展开之间**不重排、不淡出重进**：头部始终是一条 `Row`，图标是同一个元素平移 +
  字标宽度收放；换成 Column/Row 两套结构会让整块重排，就不是"同一个形状形变"了。

### 6.3 标题与面包屑 ✅ 已落地已出图（面包屑为新增）

顶栏（`DesktopTopBar`，高 60 设计像素）从左到右：**leading → 标题/面包屑 → actions → toolbar**。

- 内容区**只有一个标题位**：有层级时用面包屑，没有层级时用单级标题，二者互斥、
  占据同一格，切换时同一形状形变（§5.1），不要上下叠两行。
- 面包屑组成：`模块 / 集合 / 当前项`，由 `AppRouteData.sidebarParent` 反查父链
  （`AppRoutes.breadcrumbFor`）生成——**侧栏的嵌套层级和面包屑是同一份数据**，
  各写一遍迟早对不上。页面要自己指定时走 `ScreenChromeData.breadcrumb`。
  只有一级时返回 `null`，顶栏回落到单级标题。
- **末端的名字取页面自己报出的 `chrome.title`**（详情页的实体名，如某个游戏标题），
  静态路由在那一格上的名字是废话；**上级各取 `sidebarLabel`**，跟侧栏叫法一致。
  页面给了 `titleWidget`（自定义标题位，里面带控件）时外壳不抢。
- 分隔符是 `/`（`textDisabled`，比正文再退一档，`fontSize13` 但不加粗），当前项 `textPrimary` w500 且**不可点**，
  其余各级 `textSecondary`、可点、悬停出水洗药丸。
- **分隔符的样式必须从 role 复制**（`AppTextStyles.rowTitle(context).copyWith(...)`），
  不能现写一个裸 `TextStyle`：裸的没有 `fontFamily`，会落到环境默认字体上——真机也许看不出来，
  离屏出图直接是一个豆腐块；而且 `_measure` 量的是 role 的宽度，量与画分家之后，
  折叠判定（下面那条）算出来的宽度是假的。
- 溢出：中间层级折叠成 `…`，首尾两级永不折叠。窄窗（<900）只显当前项 + 返回箭头。
- 移动端：面包屑收成"← 当前项"，层级由返回手势承担。
- 现有可参考的实现：`pages/collection/library/components/library_folder_breadcrumb.dart`
  （集合内的文件夹路径），外壳面包屑应把它抽成 `core/widgets/breadcrumb.dart` 复用，
  而不是再造一套。

### 6.4 选中指示器：一个形状形变

侧栏菜单项的选中态**不是"加一层品牌色底"**，而是这一行本身抬起成一张卡：

```dart
color:   isSelected ? s.surface : hovered ? s.surfaceHover : transparent
border:  isSelected ? Border.all(color: s.accentContainerBorder) : null   // 只有选中项描边
radius:  m.radiusControl
shadow:  isSelected ? s.elevation(Elevation.raised) : const []
```

外加一根 3 设计像素宽的墨色竖条（`s.accent`，`scaleW(3)`），高度从 0 长到 20：
**它就是指示器本体**，靠高度形变进出，不靠透明度淡入淡出。

- **未选中项不画描边**：每行都套一个框，一列看下去全是格子，抬升关系反而读不出来。
- 悬停只有水洗（`surfaceHover`），不加描边、不加投影。
- 图标底（`accentContainer` + 圆角 `radius8`）在选中时长出来，与白卡同一条时间轴。

### 6.5 展开的子项：**连接线成组**

一个可展开项（有 `children`）展开后，子项必须用**树形连接线**和父项串成一族，
让"这三行属于上面那一行"在视觉上成立，而不是靠缩进猜：

```
◉  Saving goals                              ⌃
│
├─╴ House rent                    ◔ 20%
│
├─ Workspace setup               ● 45%
│
└─ Birthday gift                  88%
```

契约：

> 📐 **实现状态**：连接线本体已落地并出图验收（`sidebar_tree_light.png`）——`TreeConnector` 把整族
> 子项套在**一层** `CustomPaint` 底下，竖干/横枝按调用方给的 `rowHeight` 一次算完，不会逐行漂移。
> 两条踩过的几何口径写死在这：**竖干起于本层顶端（`y = 0`，也就是父项那一行的下沿），不是第一枝
> 的中心**——从中心起的话，只有一个子项时竖干短到看不见，多个子项时父项和第一枝之间断一截；
> **只有一个子项也要画干**（"只有一枝就跳过竖干"读起来是一个悬空的小钩）。还缺两条：
> 下面的"动画"（描干 + stagger）和子项右侧状态位（`_SidebarChildItem` 目前没有那个槽）。

- **竖干**：从父项图标底部中心起，画到最后一个子项的横线处**为止**（不穿过末项）。
  线色 `s.border`，宽度固定 1 逻辑像素（§3.3，不写 `1.w`）。
- **横枝**：每个子项一行，从竖干向右伸出到子项图标左缘，长度 10–12 设计像素，
  末端带圆角（`radiusControl` 的 1/4），是"括号"不是"直角折线"。
- **缩进**：子项整体相对父项缩进一档（`kSpace20` 量级），图标左缘对齐横枝末端。
- **子项文字**：`AppTextStyles.rowTitle`（13 / w500），色 `textSecondary`；
  选中子项才升 `textPrimary`。**子项不画白卡**——一族里只允许一个抬升主体，
  否则连接线和白卡会打架。选中子项的反馈：文字升色 + 图标底出水洗。
- **右侧状态位**（如进度环 + 百分比）：进度环用 `AppViz` / 状态色，
  百分比数字 `caption` 且**必须 tabular figures**（`fontFeatures: [tabularFigures()]`），
  否则数值一变行就抖。
- 🔧 **动画（未做）**：展开时竖干**从上往下描出来**（高度 0→满），横枝按 `stagger` 依次长出；
  折叠时整族一起收，不逐条退。箭头（chevron）旋转 90°，与 `AnimatedSize` 同一条时间轴。
- 收起态（图标条）**画不出竖干**：75 设计像素里没有横枝的容身位置，子项仍逐条排在父项下面，
  只是退成纯图标行 + `Tooltip` 补名。
- 连接线只在**一层**内画。多层嵌套（≥2 层）目前不支持，需要时先补契约再写代码。

---

## 7. 磨砂与窗口透出（桌面专属，移动端一律实色）

"透出应用背后内容"是**两层**结构，缺一层就不成立：

1. **窗口本身透明** —— `macos/Runner/MainFlutterWindow.swift` 往 `NSThemeFrame`
   插 `NSVisualEffectView`（`.fullScreenUI` / `.behindWindow`），负责透出**桌面**。
   该视图重写了 `hitTest` 返回 nil：否则 AppKit 会把事件全吃进原生层，Flutter 收不到点击。
   Windows 走 DWM 背景材质（申请压克力而非 Mica：Mica 只是壁纸静态着色，不透不糊）。
2. **面板再叠 `BackdropFilter`** —— 负责透出**同一 App 内**它下面的内容
   （列表滚到面板下方时能隐约看见，这是层次感的关键来源）。

### 7.1 哪些面允许是玻璃

| 允许 | 不允许 |
|---|---|
| 侧栏、顶栏、悬浮工具条、弹窗/菜单、底部播放条 | 内容卡片、列表行、输入框、图标底 |

内容卡片一律实色 `surface` + 描边 + 极轻投影。半透明卡片叠背景模糊在这套中性底上
只会两头都不像：既看不出透，又把文字对比度吃掉。

### 7.2 组件与档位

| 组件 | 签名要点 |
|---|---|
| `GlassSurface(child, blur, tint, borderColor, borderRadius, padding, elevated, asPanel)` | 常驻面板；`asPanel` 用更透的着色 + `radiusPanel` |
| `GlassAppBar(title, leading, actions, bottom)` | 顶/底吸附条，内容从其下方滚过（外壳顶栏应走这个，🔧） |
| `GlassFloat(child, padding, borderRadius)` | 命令面板 / 悬浮工具条 / 下拉浮窗 |
| `GlassMenuItem(label, icon, destructive, selected, value, enabled)` | 桌面紧凑菜单行，行高 30（Material 默认 48 是给触屏定的） |

| 档位（`WindowGlass`，`window_backdrop.dart`） | alpha | 生效条件 |
|---|---|---|
| `contentAlpha` | 180 | 仅 macOS（正文密度高，透明度已收敛得很低） |
| `panelAlpha` | 200 | 侧栏/面板 |
| `overlayAlpha` | 242 | 浮层（菜单、弹窗、底部播放条） |

非对应平台一律 255（实心）。模糊半径三档：`AppGlass.blurSoft`(12) / `blurMedium`(24，
语义层默认值) / `blurStrong`(40)。`kWindowsGlassEnabled` 是 Windows 子窗口 HWND 能否透出
的总开关——**该项在 Windows 上尚未实测**，观感异常先把它改成 `false` 退回实心底。

### 7.3 取色禁忌

- `GlassMenuItem` **不再自建悬停药丸**：外层 `InkWell` 用的就是 `ThemeData.hoverColor`
  （= `surfaceHover`），自己再叠一颗会变成"方块灰 + 药丸灰"两层。
- 菜单/浮层底色一律 `surfaceRaised.withAlpha(WindowGlass.overlayAlpha)`，
  不要写死 `Colors.black45` 之类。
- 玻璃上的描边只用 `s.glassBorder`，不要另配 `Colors.white.withAlpha(180)`——
  那条历史上就是浅色档看不见、深色档过重的一根线。

---

## 8. 响应式与移动端兼容

- 平台判断：`SizeUtils.isDesktop / isMobile`（macOS·Windows / iOS·Android）。
- 窗口降级：`isPhone`（宽 <600）时 `_adaptiveScaleFactor()` 自动收紧所有 `scaleW` 值。
- 外壳：`DesktopLayout` 在窗口 ≤600 或移动端平台时切 `MobileLayout`——侧栏**浮在内容之上**
  （不是贴在桌面之上），所以那一层必须整窗不透明，否则根 Material 一透明，
  正文就直接压在桌面背景上（这条已经踩过，见 `desktop_layout.dart` 注释）。
- 移动端**没有磨砂**：没有原生振动层，半透明只会透出窗口底色，观感是"脏"。
  所有 `Glass*` 组件在移动端走 `alpha=255` 分支。
- 触控目标最小 44×44 逻辑像素（桌面可小到 30，见 `GlassMenuItem`）。
- 内容宽度只有四档：`ContentWidth.narrow`(460) / `medium`(680) / `regular`(920) / `wide`(1440)。

---

## 9. 共享组件库

新增 UI 前先在这里找，**找不到再考虑加**——右列是收敛前的重复实现数量。

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
| `AppLoading` / `Scrim` / `SkeletonBox` | `empty_state.dart` | 写死的 `Colors.black.withValues(alpha:.3)` 遮罩 |
| `SectionHeader` / `OverlineLabel` | `section_header.dart` | 约 12 份小节标题（仅设置模块就 7 份） |
| `ContentContainer` / `AppSplitView` | `page_container.dart` | 18 种不同 `maxWidth`、各页 `Row + SizedBox(魔数) + Expanded` |
| `GlassSurface` / `GlassAppBar` / `GlassFloat` / `GlassMenuItem` | `glass_surface.dart` / `glass_menu.dart` | 见 §7 |
| `Breadcrumb({entries})` / `BreadcrumbEntry(label, {onTap})` | `core/widgets/breadcrumb.dart` | 外壳顶栏层级位；宽度不够只折中间级、首尾不折（§6.3） |
| `TreeConnector({childCount, rowHeight, spacing, child})` | `core/widgets/tree_connector.dart` | 侧栏子项连接线，整族一层 `CustomPaint` 画完（§6.5） |
| `DrawIcon` / `StrokeZone` / `StrokeIconButton` | `components/icons/`、`components/buttons/` | 全站图标：`Icon(Icons.*)` 与 41 张自绘 svg 一起换掉（§9.1） |

`Tone` 枚举（`neutral/success/warning/danger/info/accent`）是组件侧的语义档位，
用 `resolveToneColor(s, tone)` 在一帧内解析成具体颜色。

### 9.1 图标：`DrawIcon` + 描边动画

全站图标只剩一种写法：`DrawIcon(StrokeIcons.x)`。**没有 `Icon`、没有 `SvgPicture.asset`、
没有 icon font**——唯一保留的 svg 是 `assets/image/svg/top_bar_logo.svg`（品牌标，不是图标）。

| 件 | 位置 | 职责 |
|---|---|---|
| `DrawIcon(icon, {size, color, weight, trigger, effect, duration, curve, controller, semanticLabel})` | `components/icons/draw_icon.dart` | 单个图标：按弧长顺序描出来，`size`/`color` 缺省跟 `IconTheme`，从 `Icon` 直接换过来外观不变 |
| `StrokeTrigger`（`auto/appear/press/hover/manual/none`） | 同上 | 什么时候播：见下表 |
| `StrokeEffect`（`draw/blur/flow`） | 同上 | 怎么播：描边 / 描+模糊收敛 / 画完接一段沿笔画流动的高光（"进行中"） |
| `StrokeController` + `StrokeTrigger.manual` | 同上 | 外部驱动进度：滚动进度、入场级联、录制时长 |
| `StrokeZone(child, {broadcastPress, broadcastHover, enabled})` | `components/icons/stroke_zone.dart` | 事件源：整行/整卡按下时，让**内部所有**图标一起重播 |
| `StrokeIconButton(icon, {onTap, size, color, hoverColor, scaleOnPress})` | `components/buttons/stroke_icon_button.dart` | 图标即按钮：悬停换色 + 按下缩放 + 自己就是事件源 |
| `StrokeIcons`（239 几何 + 338 别名） | `components/icons/stroke_icons.g.dart` | 构建期生成的常量，**勿手改** |
| 生成器 + 映射表 | `tool/stroke_icons/generate.dart`、`data/icon_map.json` | 换图标/加图标只改映射表再重跑 |
| `StrokeIcon.viewBox`（默认 24） | `components/icons/stroke_geometry.dart` | 非 Tabler 的自绘图形按资产自己的坐标系走，笔宽自动折算回 24 口径 |

**为什么是构建期常量而不是 icon font 或 svg 资产**：只有这一条路能做到"没引用的图标不进产物"。
icon font 整包进 `pubspec`，svg 目录整目录进 bundle；生成出来的 Dart 常量没被 import 的符号会被
tree-shake 掉，mac/windows/ios 三端同理。代价是多一个构建期步骤，换来的是产物里图标体积 = 用到的图标体积。

触发口径按"这个图标可不可点"收敛，不设第二套规则：

| 场景 | 写法 |
|---|---|
| 99% 的调用点 | 不写 `trigger`（= `auto`）：出现时播一次，按下再重播 |
| 密集列表 / 装饰性图标 | `StrokeTrigger.appear`，避免满屏乱闪 |
| 大容器里的图标（卡片、菜单行、侧栏行） | 容器包 `StrokeZone`，图标仍用默认 `auto` |
| 只读状态图标 | `StrokeTrigger.none` 或 `appear` |
| 换图标（展开/收起、播放/暂停、选中态） | 直接换 `icon`，`DrawIcon` 自己走"旧的擦回去 + 新的描出来" |
| 悬停才浮现的符号（macOS 窗口灯） | `manual` + 外层一个 `AnimationController` 写 `StrokeController.progress`：进场描出、离场擦回 |
| 笔画数远超一枚图标的整幅标记（侧栏品牌标记 45 笔） | `appear` + `duration: AppMotion.entrance`：只在自己挂载那一下描，不吃容器脉冲 |

动效叠加的上限：**一个转场里只允许一个主角**。`StateTransitionAnimation` 已经有位移 + 模糊 +
淡入三层，里面的图标就固定 `StrokeTrigger.none`，再描一遍会糊成一团。


---

## 10. 编写规范（硬约束）

1. 取色只走 `AppSemantic.of(context)`；**禁止** `isDark ? … : …` 分支和裸 `Colors.*`。
2. 尺寸只走 `AppTheme.metrics`，超档用 `scaleW()`；**禁止**裸数字与 `int.w`。
3. **两族尺寸不混用**（§3.1）：窄栏内一切尺寸走宽度族。
4. 文字只走 `AppTextStyles.*`；**禁止**裸 `TextStyle(...)`（丢 fontFamily）。组件主题里的
   `textStyle` 是整条替换，必须过 `AppTheme._font(...)`。
5. 时长/曲线/位移/缩放/瞬时模糊只走 `AppMotion.*`（§5.2–§5.4，别在页面里现写 `0.93`、
   `Duration(milliseconds: 260)`）；反馈类 ≤160ms；退场取进场的下一档。
   位移族是**宽度族 getter**，和 §3.2 同一条理由。
6. **UI 骨架不铺渐变、不加发光**（§5.1）。渐变只允许出现在图表线里。
7. 弹窗用 `showDialog`，不用 `Get.dialog`。
8. 注释必须中文，且**不要删除已有注释**——现有注释大量是踩坑记录（本文多条规则就来自它们）。
   注释只写"为什么"，一句话；**不要在代码/注释/命名/提交信息里点名任何参考实现**。
9. 命名：页面 `_screen.dart` 结尾、class `Screen` 结尾、继承 `BasePage`。
10. Flutter 只做 UI 与 UI 相关数据处理；逻辑/存储/文件/进程一律 Rust（FRB）。
11. **不要全仓 `dart format`**：HEAD 本身不是 format-clean，全量格式化会产出上千行噪声 diff。
12. 图标一律走 `DrawIcon(StrokeIcons.*)`（§9.1）：尺寸走宽度族、颜色走语义色，
    描边粗细统一 2（小尺寸才提权）。**禁止**再引入 `Icon(Icons.*)`、icon font 或
    svg 资产图标；换图标/加图标只改 `tool/stroke_icons/data/icon_map.json` 再重跑生成器，
    不要手改 `stroke_icons.g.dart`。
    品牌标记那种自绘资产走生成器的 `_svgMarks`：生成器直接读那张 svg 的 `<path>`
    裁成 `StrokeIcons.brandMark`（`viewBox` 跟着资产走），**资产仍是唯一来源**，
    不要手抄 d 字符串。全站只剩关于页那枚大图还直接画 `SvgPicture`——它不需要描边，
    留着是为了保资产的多色。
13. 系统平台自带的控件外观**不为了统一而动**：macOS 三颗窗口灯仍是红黄绿实心圆，
    符号只在悬停时描出来（`_MacLight`，走 `manual` 由悬停驱动）——平台约定优先于组件统一。

---

## 11. 视觉验收：离屏 golden

**不启第二个 `flutter run`**（会抢 redb 单实例锁，且用户自己的会话热重启即可）。
视觉改动一律走 golden，真机报错也要先在离屏复现。

```bash
flutter test --update-goldens test/design_system_render_test.dart
flutter test test/music_player_render_test.dart
flutter test test/sidebar_collapsed_layout_test.dart      # 布局回归（快，CI 跑）
flutter test --update-goldens -t golden test/sidebar_collapsed_layout_test.dart  # 出图
flutter test --update-goldens -t golden test/shell_chrome_render_test.dart       # 顶栏标题格两态
```

外壳的验收点是分开的两块：**侧栏**（`sidebar_*`）看 logo、指示条、行末箭头、子项连接线；
**顶栏标题格**（`shell_topbar_*`）看单级标题 / 面包屑各是哪张脸、上级叫法是否跟侧栏一致。
标题格那三张按 `find.byType(DesktopTopBar)` 截，但页面体是个空的 `SizedBox.expand`，
所以产物是整窗尺寸、内容只占顶上 60——看图只看那一条，别以为漏画了。

产物在 `test/goldens/`；改版前的对照基线在 `test/goldens/before/`，
左右拼图在 `test/goldens/compare/`。`test/failures/`（不匹配时 Flutter 吐的 diff 图）
是临时产物，不要提交。

六个必须知道的坑：

1. **有无限循环动画就不能 `pumpAndSettle`**——正在播放行的跳动指示条、`StatusDot` 的
   脉冲、骨架屏的呼吸都永远 settle 不下来，测试直接超时。改用
   `await tester.pump(); await tester.pump(const Duration(milliseconds: 400));`
   或 `advance(tester, steps: 35)` 一小步一小步走（入场级联最后一条要 900ms+ 才起跳，
   中途每一帧都排过版，窄宽度下的溢出才藏不住）。
2. **改窗口尺寸必须 `AppTheme.resetMetrics()`**：`AppTheme.metrics` 是缓存下来的常量，
   真机靠窗口变化回调刷新。测试里先泵一个 const `ScreenUtilInit` 再调它，
   否则拿上一台"窗口"的数排版，报出来的是铺垫造成的**假溢出**。
3. **字体要手动加载**：统一走 `helpers/page_golden.dart` 的 `loadAppFonts()`。
   它加载 Inter 四档 + MaterialIcons，并把 `PingFang SC` 钉到内置中文上——
   出图环境没有系统中文字体，不钉这一份中文整页变豆腐块（真机由系统字提供，不需要）。
   代价：**golden 里的中文和真机不是同一款字**，验收只看版式不看字形。
4. **悬停要真实指针**：`createGesture(kind: PointerDeviceKind.mouse)` **必须 await**，
   再 `addPointer / moveTo / removePointer`，不然 `MouseRegion` 不触发。
   `onEnter/onExit` 是在**这一帧的 hitTest** 里派发、下一帧才建出来的，
   所以 `moveTo` 之后要连泵两下（`pump()` 再 `pump(时长)`）才读得到状态变化。
5. **`takeException()` 会吞掉 dump**：溢出断言要单独一条 `expect(tester.takeException(), isNull)`，
   别和 golden 混在同一个用例里；golden 用例要 `tags: 'golden'`，CI 用 `--exclude-tags golden` 跳过。
6. **`Get.put` 返回的是"已注册的那个"**：`GetInstance.put` 内部会先 `find`，同类型已经注册过
   就把传进去的新实例丢掉、返回旧的。所以谁往公共铺垫 `registerPageServices()` 里塞
   `Get.put(SidebarController())`，就会把用例里自己配好的那个（收起态、选中项）顶掉，
   出图直接变成另一种布局。要补的依赖在**自己的测试文件里**注册，并且先
   `SharedPreferences.setMockInitialValues({})`——`SidebarController.onInit` 要读持久化栏宽，
   没有假 prefs 第一帧就抛 `MissingPluginException`。

---

## 12. 动效实验室（隔离案例集）

`lib/pages/motion_lab/` 是一页 43 格的动效参考集：每格一个独立组件，照外部参考稿逐像素还原
尺寸/颜色/时长/曲线/关键帧。**它是只读参考，不是产品 UI**——§5.1 的禁令在这里依然成立，
发光、粒子爆炸、骨架渐变搬进真页面仍然是违规。

### 12.1 结构

- `lab_kit.dart`：这一页自己的 token 层（`LabColor` / `LabFont` / `LabEase` / `LabSize` /
  `LabShadow` / `LabText` / `LabStage` / `LabCard` / `LabAnimateButton` / `LabIconButton` /
  `LabStageFooter` / `LabBlur` / `LabTween` / `LabIcon`）。
- `cases/case_NN_*.dart`：43 个文件，一格一个 class，互不引用。
- `cases/motion_lab_cases.dart`：注册表 `kLabCases`（`seq` / `title` / `subtitle` / `cat` / `build`），
  页面和测试都只认这张表——加一格只加文件 + 加一条注册。

### 12.2 隔离：一堵单向墙

- **不读也不写** `AppTheme` / `AppSemantic` / `AppMotion`，也不碰 `LightColors` / `AppTextStyles`。
- 依赖只能单向流入：`lib/pages/motion_lab/**` 之外不许 import 它，唯一的入边是路由注册。
  真页面要用某个效果，把算法搬过去按 §5 的口径重写，不要直接引用。
- 复测：`grep -rln "motion_lab" lib/ | grep -v "^lib/pages/motion_lab/"` 只应剩 `core/routes/app_routes.dart`。

### 12.3 字面 px 是**记录在案的例外**

§10.2 禁裸数字，这一页**故意**全是裸数字（`style_showcase_screen` 同理）：参考稿给的就是绝对
像素，乘上 `scaleW` 之后 1440 窗口下整套尺寸会缩到 75%，那就不是还原了。例外只圈在
`lib/pages/motion_lab/**`，越界即违规。

### 12.4 动效坑（都是这一页里真炸过的）

1. **`build()` 里读控制器 ≠ 会重绘**：`_c.value` 直接读进 build，没挂 `AnimatedBuilder` /
   `ListenableBuilder` / `addListener`，画面就永远停在挂载那一帧。测试里表现为"动效完全不存在"，
   真机上偶尔被别的 `setState` 顺带刷一帧——最难查。`repeat()` 的循环钟尤其如此。
2. **`TweenAnimationBuilder` 只在 `begin != end` 时起钟**（SDK 的 `initState` 里就一句
   `if (_currentTween!.begin != _currentTween!.end) controller.forward();`）。入场补间首帧两个值
   常常都是 0，下一帧把 `end` 换成 1 时**钟已经不会再转**，界面永远停在 0。
   → 用 `LabTween` / `_ValueTween`（值到值补间，自己挂监听，首帧直接落目标）。
3. **零时长 `pump()` 是"对表帧"**：刚 `forward()` 的钟会把这一帧当成对表，进度仍是 0；而
   `addPostFrameCallback` 里改的目标要下一帧才生效。所以 `shootLabCase` 在交互之后固定推
   **两帧真实时间**（2×16ms），只推一帧就拍到"没动"。
4. **`Cubic.transform` 对 [0,1] 之外直接断言**：行程比例（`elapsed / 总时长`）一律
   `.clamp(0.0, 1.0)` 再喂进去，否则回弹曲线一过冲就抛。同理，过冲曲线算出来的**透明度**
   也会顶出 [0,1]，喂给 `Opacity` 前必须 `clamp`（32 号）。
5. **`AnimationController.repeat()` 永远到不了 `completed`**：状态一路是 `forward`，挂在
   "播完一次再往下走"上的收尾逻辑一次都不跑（17 号骨架屏揭示完不出文字就是这么来的）。
   要循环就自己 `forward(from: 0)` 重启。
6. **一次 `pump(时长)` 只出一帧**：假异步里 `pump(600ms)` 是把表推 600ms 后画**一张**，
   中间过程不存在。要看途中帧得按 16ms 步进循环推。
7. **`CustomPaint(repaint: X)` 只重画、不重建 painter**：painter 是旧实例、读的还是旧值时
   照样白干（31 号的对勾就是这么消失的）。用 `ListenableBuilder` 把父节点一起重建才算。
8. **舞台外的 `Text` 会去接 `MaterialApp` 的兜底字样式**：`app.dart` 里那份 `_errorTextStyle`
   是黄字双下划线，专门提醒"把文字放进 Material"。隔离层没有 Material，于是 129 张 golden 里
   113 张白带一条黄杠。`LabStage` / `LabCard` 各自钉一层 `DefaultTextStyle` 才干净。
9. **`Stack` 里的 `Positioned` 只给 `width` 不给 `height`** → 子节点收到 `h: 0..∞` 的 loose
   约束，`OverflowBox` 会去要"允许范围内最大"，直接无限高断言（23 号）。用它撑"宽度不占槽"
   的效果时，高度必须给死。
10. **`Row` 里的 `Column` 必须写 `mainAxisSize.min`**：Row 给子节点的是"高度上限 = 自己可用的
    那一段"，`Column` 默认 `max` 就正好顶满，于是文字贴到最上、图标按交叉轴居中，一行散成两截
    （32 号）。父链上限是无限时看不出问题，一进 `Center` 就炸——所以别等断言，写的时候就带上。
11. **`late final` 控制器在 `dispose()` 里被构造出来**：`late final _c = AnimationController(...)`
    谁先摸谁负责建。`dispose` 里写 `_c.dispose()` 之前没碰过它（动效一次没播）就是"挂载即建钟"，
    测试里表现为 `A Ticker was not disposed`，且报的行号指向 dispose，看着像销毁写错了。
12. **弹簧不推进就是冻住的**：`IlSpring` 是个 `ChangeNotifier`，自己不知道时间。只 `aim()` 不接
    `Ticker`/`addListener` 驱动，画面停在起点，`atRest` 也永远是 false——比"没动"更难查，因为它
    自称还在动。要么挂驱动，要么一开始就用 `jumpTo`。
13. **`Center` 会悄悄夹住超本子节点**：子节点比 `Center` 给的可用空间大时不报溢出，只按父约束
    缩放定位。要"放得下就居中、放不下就溢出去"得用 `UnconstrainedBox`——而它自己会报溢出，
    纯粹想撑宽不给尺寸时用 `OverflowBox`（3 号松手后的 `✓ Confirmed` 就是这么处理的）。
14. **`addPointer` 不等于按下**：`TestGesture.addPointer()` 只发 `PointerAddedEvent`（等价悬停
    进入），拖拽识别器根本不会进拖拽态，图却拍得出一张静止的"看起来没问题"。按下要另写
    `down(point)`。同页的鼠标手势**共用 device 1**，一根手指没 `removePointer()` 就再起第二根，
    `MouseTracker` 直接断言 `'(event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent)'`
    ——所以 `ilDrop` 收尾时 `up()` 之后必须 `removePointer()`。
15. **按 16ms 步进推进时最后一段要按余数收尾**：`for (left=n; left>0; left-=16)` 会把"120ms 那一帧"
    拍成 128ms（16 的整倍数）。要求精确对表的帧，末段得 `pump(余数)`。

形变面板另有一条：CSS 的 `overflow: hidden` 在 Flutter 里要给子节点按**展开尺寸**定死
`Positioned(width/height)`、由外层 `ClipRRect` 裁掉多出来的部分；`Positioned.fill` 和
`UnconstrainedBox` 在 morph 途中必然溢出断言。

### 12.5 局部工具为什么不用现成的

| 工具 | 干什么 | 为什么单独一份 |
|---|---|---|
| `LabIcon` | 按 path 数据现画的描边图标 | 全局 `DrawIcon` 的尺寸走宽度族、颜色走语义色，这一页两样都不许碰 |
| `LabBlur` | `ImageFiltered` 糊本地图层 | 不依赖主题 |
| `LabTween` / `_ValueTween` | 值到值补间 | 见 §12.4 的 2 |

### 12.6 验收：一帧一个 test

```bash
flutter test -t golden test/motion_lab_all_cases_test.dart              # 129 张 = 43 格 × 静止/途中/终态
flutter test --update-goldens -t golden test/motion_lab_all_cases_test.dart
flutter test --update-goldens -t golden test/motion_lab_all_cases_test.dart --plain-name 'Confetti burst'  # 单格重出
```

- 触发方式按格子写死在 `_acts`：点按钮 / 点可点区 / 压悬停 / 什么都不做只推进时间。
  可点、可拖的元素靠 `cursor: click|grab` 的 `MouseRegion` 找，比猜坐标可靠（拖拽格是 `grab`）。
- **一帧一个 test**：出过图之后同一个 test 里的第二次点击就不再接到了。
- 途中帧默认 150ms；还在 delay 里的慢启动格、以及刚炸开挤成一团的格子，另写进 `_midOverride`。
- **只看静止帧证明不了动效存在**。审计口径：43 格的 idle / mid 两张取哈希比对，
  `mid == idle` 必须为空集；`end == idle` 只允许是"落定后本来就该没有"的格子（6 号纸屑落完）。
- **三帧采样也证明不了"途中不炸"**：过冲顶出的非法透明度、只在某几帧出现的溢出断言，
  三帧全都恰好躲过去。所以每格还有一条不带 `golden` 标签的**逐帧扫**：按 16ms 推到 3000ms，
  任何一帧 `takeException()` 非空就 fail。`flutter test --exclude-tags golden` 单跑它。
  真机报的缺陷里有两成是这条路先抓到的。
- 确定性：随机只许 `math.Random(固定种子)`；出现 `DateTime.now()` 或依赖真实窗口的 `MediaQuery`
  就会第二次跑挂。不带 `--update-goldens` 重跑一遍即是一次复现检验。

### 12.7 交互实验室：会被人按住拖的那些

第二块参考页（`/interaction-lab`，`lib/pages/interaction_lab/`）。规矩和 §12 同一套：
自己的局部底座（`kit.dart` 的 `Il*`），一格一个独立组件，**不读也不写** `AppTheme` /
`AppSemantic` / `AppMotion`，尺寸写字面 px（§12.3 的同一条例外）。

差别只在**这一页的格子要真的能操作**，不是循环播放的演示：搜索框要真输入、把手要真按住拖、
列表要真拖拽换序。于是验收口径也多一条——不能只拍"动到了"，要拍"按哪儿动哪儿"：

- 用 `ilGrab` / `ilDragTo` / `ilDrop`（`test/helpers/il_golden.dart`）逐位移喂事件，坑见 §12.4 的 14。
- **`ilDragTo` 的起点在进函数时就钉死**：拿"上一帧落点"再乘 `i/steps`，每步只走完*剩余*
  距离的一成，到末帧指针几乎不动——静止在末帧上拍，速度驱动的形变量恒为 0。
- **弹簧驱动的量不许再套 `Animated*`**：药丸宽度已经在吃弹簧的值，每帧都变一次就会
  每帧重启一遍自己的 220ms 补间，于是永远追不上（量到的是"走了 16%"的宽度）。
  只有颜色那一档是补间。
- **按在远处不许瞬移**：按住点与把手中心拉开距离再拖，`press_far` 帧必须和 `idle` 帧**哈希相同**
  （跟手的语义是"位移 = 指针位移"，不是"把手跳到指针"）。
- **跟手用像素量**：拖 `dx` 之后量黑色水洗带的游程端点，端点差要等于 `dx`。
- **钉边用像素量**：松手那刻右边缘定住，`far` / `morph` / `done` 三帧的游程右端必须是同一个数。
- 回弹的挤压看包围盒高度：静止 `y147..194`，回弹帧 `y145..196` 才说明真的鼓起来了。
- **形变看同一颗药丸的三个读数**（4 号）：静止 `196×44`、慢拖（每帧 1.5px）`190×47`、
  快甩（每帧 30px，撞 ±3 钳位）`176×52`——宽和反比地高，面积守恒才算"拉长"而不是"缩放"。
  拍这两张要先按着不动等 260ms 让抬起弹簧走完，否则宽度还没到 208，`scaleX` 就量不准。
- **停过再起的 Ticker 必须显式 `start()`**（`IlSpringDrive`，5 号把它逼出来的）：
  `_ticker ??= createTicker(..)..start()` 只在第一回建表，走完一次就 `stop()` 了，
  之后每次换目标只是 notify，表不再跑——**第二次动作的弹簧恒停在起点**（收起/返回整段不动）。
  重启时 `_last` 也要归零，否则第一帧拿到"距上次起跑"的整个时长，弹簧一步到底。
- **透明度 0 不等于不存在**：`Opacity(0)` 的子树照样吃指针。参考稿那层是**真卸载**的，
  所以淡没了的 `Undo` 不会隔着半条药丸抢点击——这里得配 `IgnorePointer`，
  并且用 `find.text(..).hitTestable()` 断言两态各自只在有货时受理指针。
- **交接帧要"零暗像素"**（5 号）：点完 60ms 那一帧白底还在 112→206 的路上，
  标签却已经瞬移到目标矩形、淡入还压着 100ms 延后 → 量 `y140..205` 带里暗像素必须为 0。
  这一帧是"只有背景药丸吃弹簧"这条口径唯一的实证。
- **欠阻尼看会不会短过静止位**：去那条 `{460,30,.9}` 干脆，回那条 `{420,20,.9}` 带一点回送，
  收回中段量到 `102` 宽（< 静止的 `112`）才证明它真的弹过了头。
- 出图坐标系是**整个窗口 420×342**，不是舞台：舞台心 = `(210, 171)`，
  井 260×96 坐在舞台正中 → 胶囊 idle `x154..266`、done `x107..313`、`y149..193`。
  倒计时条按行量（`y191..192`）：`177@560ms`、`100@2064ms`，和 `206·(1-t/4000)` 对得上。

- **Flutter 的命中盒是半开区间**（6 号）：正好压在右边界上的那次 pointer 事件送不进图里
  （浏览器里 `clientX-left` 是可以等于宽度的），而且还会顺手触发 `MouseRegion.onExit`。
  扫读格的 `_plotAt(f)` 右端因此退 0.01px，左端 `dx=0` 本来在盒内不用退。
- **切片偏移是"首点的下标"，不是"偏移量"**（6 号）：时间轴按整条 34 点铺，换窗口只换读数窗口。
  `_slice.off` 取 `from` 而不是 `length-from`，否则 1H 那 5 个点会被拉回 `09:00` 起。
- **CSS 的外描边不等于 Flutter 的内描边**（6 号）：`box-shadow:0 0 0 2px` 画在 9px 元素的盒子
  **外面**、配 `margin:-4.5` 对盒心；换成 `Border.all(width:2)` 画在 13px 盒**内**，
  要退的是外沿一半 `6.5`，照抄 `4.5` 就整体右下偏 2px。
- **拍"落定"帧要按弹簧的走完时间等**（6 号）：`{.1728,.736}` 从 58 回 0 是 50 帧 ≈ 800ms。
  抢拍的话整张 sheet 还沉着 3~4px，会被量曲线的脚本当成"曲线画歪了"。
- **量曲线：覆盖率加权，并且补 0.5 的行中修正**。二值掩码的行均值只有 0.5px 档，
  量出来的"最大偏差 0.5px"全是量化噪声；改成覆盖率质心后同一个 case 从 ±0.5 收到 ±0.26。
- **末点的提示圈不能用包围盒定圆心**（6 号）：曲线正从左边同一行插进来，把左沿拉长。
  只用**顶帽三行**的覆盖率质心取 x——那是圈上唯一线够不着的地方；底帽不行，线就趴在那一档。
- **Catmull-Rom 的首末段 `x(t)` 不线性**（6 号）：端点用重复点兜底之后
  `c1.x = a.x + step/6`、`c2.x = b.x - step/6`（中间段才正好三等分）。按 x 线性反解 `t`
  在 34 点窗口只错 0.26px，到 5 点窗口就是 1.81px 的假偏差。比对脚本要把 path 稠密采样再插值。

- **位移探针的 key 要挂在 `Transform` 的内侧**（7 号）：`RenderTransform` 自己的坐标系**不含**
  它正在算的那道矩阵，把 key 挂在外层 `Positioned` 上，`getTransformTo(祖先)` 拿到的永远是
  未位移的那一份，量出来全程恒为 0。挂进子树（这里是 `Opacity`）才对。
- **定时补间每次 `aim` 同值都要短路**（7 号）：悬停水洗的目标每帧都被重发一次，若 `aim` 无条件
  重置起点和已过时间，钟就永远走不完——表现为"底色一直停在半途"且 Ticker 不停。
  `if (_to == target) return this;`，构造函数里也要把 `_to` 初始化成 `from`。
- **退场中的元素被再次选中时只能捞回来重播**（7 号）：直接新建就会有两颗同 key 的 `Positioned`
  并列在同一个 `Stack` 里，Flutter 当场抛 duplicate keys。`revive()` 把退场标志清掉、
  四个量各归进场起点，比"先删后建"少一帧闪。
- **量像素的三条基线**（7 号）：golden 里窗口画布 250、舞台卡底 237，所以"白"必须 `min≥254`
  才排得掉卡底；`spreadRadius:1` 的 1px 外环不是白，用白色包围盒量药丸会少 2px，要另开一条
  "与 237 有差"的掩码才量得到 46；圆形要沿**中轴列**量竖向直径，偏 6px 的列被弧切掉只剩 24。
- **半像素落位会把 103 宽削成 102 列满白**（8 号）：奇数宽坐在 `158.5–261.5` 上，两端各差半格。
  量的尺寸一律给 ±1 容差，别把抗锯齿当成尺寸错。同理，圆角不要靠数白点反推（文字也是墨），
  改成"取弧上几行采样列的左端点，和 `cx − √(r² − (cy − y)²)` 对表"，只有对的 r 才全行对上。
- **CSS 的 `:hover` 和 `:focus-visible` 是两条规则，别只认一条**（8 号）：行底那层水洗两条都绑，
  而且 `:hover` 把时长盖成 140ms、基础规则留 220ms → **进快出慢**。只读 `:focus-visible`
  那条会漏掉鼠标悬停时最显眼的一层，而且 golden 看不出来（静止帧本来就一样）。
- **同参数弹簧的不同量，归一化进度只在"三条都还在路上"时相等**（8 号）：弹簧的静止阈值是绝对量
  （0.02px），跨度 9px 的圆角比跨度 128px 的高度早落定十几帧。拿归一化进度做 `closeTo` 断言，
  必须在任何一条已经到位之后停下来，否则拍到的是阈值差而不是曲线差。
- **逐帧扫的两条读数纪律**（8 号）：① `Size.toString()` 只留一位小数，弹簧尾帧每帧只挪
  0.006~0.02px，会被压成同一行、误判成"卡住"——按全精度记；② 扫的帧数必然比动画长，
  尾巴全是一模一样的静止帧，那是跑完了不是卡住，平帧只数到"最后一次还在动"为止。
- **量途中帧的行墨点，采样窗口必须先把自己框进白块内部**（8 号）：白块那 1px `pane-edge` 外环
  是灰的，窗口一越过白块底边就把外环读成"这一行亮了"，量出"第 4 行比第 3 行先进"的假象。
- **按压帧要卡在门槛前一格**（8 号）：60ms 之后尺寸弹簧立刻起步，`thenMs` 多给一帧拍到的就是
  "已经在长"，压下去的那点 scale 白测。先用一次性 test 把逐帧读数打出来再定 `thenMs`。

---

## 13. 迁移进度与已知缺口

### 已完成

- 语义色层 + token 地基（`app_semantics.dart` / `app_colors.dart` / `ThemeMetrics` / `AppTextStyles` / `AppMotion`）
- macOS 原生窗口透出与磨砂
- 悬停状态层地基（水洗方向 + `Hoverable` 画层顺序 + 骨架屏 lerp）
- 菜单与浮层精修（`GlassMenuItem`、透明度档位）
- 音乐播放器整模块接入语义层（9 个文件），顺带修掉两处"界面在骗人"的功能缺陷
- **设计语言换底**：中性灰阶表面 + 反相墨主色 + Inter 字族 + 圆角整体收小
- **默认强调色的运行时 bug**：`buildCustom*` 会用旧品牌紫覆盖 `semantic.accent`，
  导致换底在真机上完全不生效；现由 `kFollowThemeAccent` 哨兵 + 短路解决
- **组件主题丢字族的 bug**：20 处 `textStyle` 整条替换处已补 `_font()`
- 外壳样板：侧栏（画布底 + 发丝右缘 + 选中白卡 + 墨色指示条）、仪表盘（实色卡片）、
  共享组件主题；侧栏收起态 9 条布局回归 + 明暗出图
- **全站图标收敛**（§9.1）：`Icon(Icons.*)` 与 `assets/image/svg` 的 41 张自绘图标全部换成
  构建期生成的 `DrawIcon(StrokeIcons.*)` + 描边动画，122 个调用点一遍过；只保留品牌标
  `top_bar_logo.svg`。产物里"没引用的图标不进包"（mac/windows/ios 三端同理）
- **动效实验室**（§12）：43 格参考案例全部落地，一格一个组件、零全局主题耦合，
  129 张 golden（每格静止/途中/终态）可复现；途中帧哈希比对证明 43 格**全部**在动

### 未完成（按可见度排序）

| 缺口 | 现状 | 复测方式 |
|---|---|---|
| 📐 外壳 logo / 面包屑 / 子项连接线 | 代码与出图都已就位（§6.2/§6.3/§6.5：`sidebar_expanded_*` / `sidebar_tree_light` / `shell_topbar_*`）；剩连接线"自上而下描出 + 横枝 stagger"和面包屑末端换脸两组动效未做 | §5.5 的 3、5，§6.5 |
| 🔧 弹簧档已有、调用点未接线 | `AppMotion.spring` / `springCurve` 已落地，全站 `AnimatedX` 仍挂 `Cubic` | §5.3、§5.5 的 1/3/7/10/11/12 |
| 🔧 DPI 档位偏少 | `_adaptiveScaleFactor()` 只四档、上限 1.14 | §3.3 |
| 全站历史取色未收敛 | `lib/`（不含 `core/theme/`）`LightColors.`/`DarkColors.` 385 行、裸 `Colors.{green,red,…}` 276 行；约 30 处 `brandColor` | `grep -rn "LightColors\.\|DarkColors\." lib/ \| grep -v "lib/core/theme/" \| wc -l` |
| 其余 ~29 个页面仍是旧语言 | 和新外壳并排看会明显不一致（这是**预期中的中间态**） | 逐模块迁移，见任务 Stage 4–10 |
| 共享组件库未铺满 | 大量页面仍手搓卡片/空状态/小节标题（~25 套卡片、`_GlassCard` 两处重复、`EmptyState` 两套打架） | 见 §9 右列 |
| 动效体系未铺满 | 除歌词行与 `Hoverable` 外多数页面仍是各自的手写时长；`StateTransitionAnimation` 已随图标迁移换签名（`icon`/`hoverIcon` 现为 `StrokeIcon?`），图标固定 `StrokeTrigger.none`（§9.1 的"一个主角"） | §5.5 逐面 + §5.6 逐输入，`grep -rn "Duration(milliseconds:" lib/pages/` |
| 自选强调色仍会覆盖新墨色 | 用户以前存过自定义强调色的话，除非改选第一档"跟随主题"，否则旧色仍生效 | 设置页 → 主题 → 第一档 |
| `surfaceActive` 仍是实心 | 按压态会打断窗口磨砂（悬停已修，按压未修） | `app_colors.dart` |
| 仪表盘卡片是死控件 | `onTap: () {}`；指标卡在 300px 封顶，宽窗留白 | `dashboard_screen.dart` |
| 仪表盘 golden 里数值是 `--` | `SystemMetricsService.lastSnapshot` 没有测试桩 | 需要时补注入点 |
| 真·背景模糊菜单 | `GlassMenuItem` 靠 `ThemeData.hoverColor`，浮层模糊仍需 `MenuAnchor.overlayBuilder` | `glass_menu.dart` |
| Flutter 侧调系统命令 | `music_player_viewmodel.dart:838` 用 `scutil --proxy`、`:1223` 用 `open -R`/`explorer`，违反 §10.10，应下沉 Rust | `grep -rn "Process.run" lib/` |
| 底部播放条重复/空实现 | 播放模式按钮出现两次（全同）；"播放列表"按钮 `onPressed` 空函数体 | `bottom_player_bar.dart` |
| Windows 透出未实测 | 子窗口 HWND 的 alpha 行为未验证 | `window_backdrop.dart:46` |

---

## 14. 相关提交

```
40452f4 refactor(ui): 音乐播放器整块接进设计系统语义层
e5c94d6 fix(ui): 悬停状态层在亮色下真正可见——水洗方向跟底色走
9534679 feat(ui): 菜单收进设计系统——新增紧凑菜单项，浮层统一玻璃口径
383dfa6 docs: 新增 DESIGN.md，把设计系统的取色/尺寸/动效口径与踩坑写成唯一规范
```
