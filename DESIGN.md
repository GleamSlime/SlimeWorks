---
version: beta
name: SlimeWorks Design System
description: 柔彩氛围底 + 玻璃层 + 渐变强调的界面语言（v2）。取色只走 AppSemantic + AppAtmosphere，尺寸只走 AppTheme.metrics 的 scaleW/scaleS 两族，动效只走 AppMotion；本文是这三者的唯一口径来源，试验田是已验收的电量统计页。
colors:
  # ── 已确认：逐条采自 lib/pages/power_stats/power_stats_theme.dart（本页已出图验收）──
  ink: "#261A3A"
  ink-dark: "#F1EEFA"
  accent: "#2F65DE"
  accent-dark: "#7C9BFF"
  accent-solid: "#2F65DE"
  accent-solid-dark: "#3B63D8"
  accent-on: "#FFFFFF"
  violet: "#715FFD"
  violet-dark: "#9C8CFF"
  data-rise: "#0CA678"
  data-rise-dark: "#3FD19C"
  data-fall: "#F06E81"
  data-fall-dark: "#FF8DA0"
  warm: "#FF855A"
  warm-dark: "#FFA07A"
  cool: "#1B8FB5"
  cool-dark: "#5AC8E0"
  canvas: "#F3E7E4"
  canvas-dark: "#1B1826"
  atmosphere-warm: "#F9DAC4"
  atmosphere-lilac: "#D4D1E9"
  atmosphere-sky: "#D3E4F6"
  atmosphere-dark-warm: "#241C33"
  atmosphere-dark-indigo: "#1A1E2E"
  glass-tint: "#FFFFFF96"
  glass-tint-dark: "#221C38A5"
  glass-border: "#FFFFFFA0"
  glass-border-dark: "#FFFFFF22"
  glass-highlight: "#FFFFFFC8"
  glass-highlight-dark: "#FFFFFF1A"
  chip-rest: "#FFFFFFAA"
  chip-rest-dark: "#FFFFFF18"
  atmosphere-shadow: "#5B4A7F26"
  atmosphere-shadow-dark: "#00000046"
  # ── 派生档（尚未出图确认，落地时按 §11 重跑明暗基线）──
  surface: "#FFFFFF"
  surface-dark: "#221C38"
  surface-sunken: "#F1ECF6"
  surface-sunken-dark: "#1B1728"
  text-secondary: "#5A4C72"
  text-secondary-dark: "#B9B0D0"
  text-tertiary: "#82749B"
  text-tertiary-dark: "#8F86A8"
  text-disabled: "#B3A8C6"
  text-disabled-dark: "#5F587A"
  border: "#DDD5E8"
  border-dark: "#3A3352"
  border-strong: "#A79BC0"
  border-strong-dark: "#5D5480"
  hairline: "#261A3A1A"
  hairline-dark: "#F1EEFA1A"
  scrim: "#000000B3"
  # ── 语义状态色：v2 不动（见 §2.5 的"涨跌不是状态"）──
  success: "#00BB7F"
  warning: "#EDB200"
  danger: "#E40014"
  info: "#8D54FF"
  neutral: "#737373"
typography:
  display-number:
    fontFamily: "Inter, PingFang SC, Hiragino Sans GB, Microsoft YaHei, Noto Sans SC"
    fontSize: 52px
    fontWeight: 700
    lineHeight: 1.02
    letterSpacing: -1.5px
  metric:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 28px
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: -0.2px
  heading-page:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: 0px
  heading-card:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.35
    letterSpacing: 0px
  row-title:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 13px
    fontWeight: 500
    lineHeight: 1.4
    letterSpacing: 0px
  body:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0px
  caption:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 11px
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: 0px
  overline:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: 1.2px
  badge:
    fontFamily: "Inter, PingFang SC, Noto Sans SC"
    fontSize: 11px
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: 0.8px
  code:
    fontFamily: "Menlo, Consolas, DejaVu Sans Mono, Liberation Mono, monospace"
    fontSize: 12px
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: 0px
rounded:
  none: 0px
  xs: 6px
  float: 8px
  sm: 10px
  dense: 14px
  md: 16px
  lg: 20px
  xl: 24px
  full: 999px
spacing:
  xxs: 2px
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  xxl: 20px
  xxxl: 24px
  section: 40px
components:
  glass-card:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "16px"
  glass-card-lifted:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "16px"
  glass-card-glow:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.accent}"
    rounded: "{rounded.md}"
  hero-panel:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.display-number}"
    rounded: "{rounded.md}"
    padding: "16px"
  card-dense:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.dense}"
    padding: "12px 12px 10px"
  glass-card-glow:
    backgroundColor: "{colors.glass-tint}"
    textColor: "{colors.accent}"
    rounded: "{rounded.md}"
  pill-filled:
    backgroundColor: "{colors.accent-solid}"
    textColor: "{colors.accent-on}"
    typography: "{typography.badge}"
    rounded: "{rounded.full}"
    padding: "6px 12px"
  pill-wash:
    textColor: "{colors.accent}"
    typography: "{typography.badge}"
    rounded: "{rounded.full}"
    padding: "6px 12px"
  section-label:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.overline}"
  range-stop:
    backgroundColor: "{colors.warm}"
    textColor: "{colors.accent-on}"
    typography: "{typography.badge}"
    rounded: "{rounded.full}"
    size: "52px x 24px"
  range-stop-rest:
    backgroundColor: "{colors.chip-rest}"
    textColor: "{colors.ink}"
    typography: "{typography.badge}"
    rounded: "{rounded.full}"
    size: "52px x 24px"
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-on}"
    typography: "{typography.row-title}"
    rounded: "{rounded.sm}"
    height: 32px
  text-input:
    backgroundColor: "{colors.surface-sunken}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "8px 12px"
  chart-tooltip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.float}"
    padding: "8px 10px"
  sidebar-row-selected:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.row-title}"
    rounded: "{rounded.sm}"
    height: 30px
  modal:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.heading-card}"
    rounded: "{rounded.lg}"
    padding: "20px"
---

# SlimeWorks 设计系统

> 一套**柔彩氛围底 + 玻璃层 + 渐变强调**的界面语言（v2）：层次靠"透出底色的玻璃 + 有色投影"
> 拉开，不靠灰阶阶梯；反馈靠同一个形状改尺寸/改圆角/改发光，**且只在真的发生了事情时动**。
> 本文是**取色、取尺寸、取动效的唯一口径来源**。
>
> 代码入口：`lib/core/theme/`（令牌：`app_semantics.dart` 角色 + `app_atmosphere.dart` 氛围 +
> `app_viz.dart` 身份 + `app_theme.dart` 尺寸字阶 + `app_motion.dart` 节奏）
> + `lib/core/widgets/`（组件）+ `lib/components/window/`（外壳）
> + `lib/pages/theme_preview_screen.dart`（可视化总览，路由 `/theme-preview`）
> + `lib/pages/motion_lab/`（动效参考集，隔离在主题之外，§12）。
>
> 阅读顺序：§0 总纲 → **§0.5 v2 废除了什么** → §1 分层 → §2 取色 → §3 尺寸 → §4 文字 →
> §5 动效 → §6 外壳 → §7 玻璃 → §8 响应式 → §9 组件 → §10 规范 → §11 验收 →
> §12 动效实验室 → §13 迁移进度 → §14 冲突与待确认。
> 标了 **🔧 待落地** 的条目是已定的契约、代码还没跟上，改动时按契约做，不要按现状反推。

---

## 0. 七条总纲

1. **柔彩底，不是灰底**：画布是一层**氛围**——对角线性渐变打底 + 四角径向色团叠出 mesh 感，
   整个窗口只画一次（§7.4）。低饱和度是硬约束：色团一旦上饱和度，玻璃卡上的小灰字立刻读不出。
2. **卡片是玻璃，密度面仍是实色**：内容卡走玻璃配方（着色 + 发丝描边 + **顶缘高光** + 有色投影），
   底必须透出氛围层的色团；列表行 / 输入框 / 菜单行 / 图标底这类高密度面**一律实色或水洗**，
   把它们玻璃化只会让整页发脏。
3. **主色是柔彩蓝，墨色退成字色**：`accent` 是蓝（亮 `#2F65DE` / 暗 `#7C9BFF`），实心胶囊 + 白字
   表达"这是主动作"；带冷紫相的墨（`#261A3A` / `#F1EEFA`）只做文字与轨道基线。
   渐变里的中间档是紫（`violet`），品牌紫不再单列。
4. **渐变只有三个容身之处**：**氛围层**、**图表填充**、**进度/轨道填充**（都是"同一个动作的起收点"，
   成对给，§2.9.3）。按钮底、卡片底、输入底、图标底一律纯色——渐变铺在 UI 骨架上，
   控件就从"一个形状"变成"一块装饰"。
5. **发光只由事件驱动**：外发光是同一元素投影的一次性抬升（0→1→0）或状态点的呼吸，
   不是装饰。层次仍然主要来自描边——玻璃上的描边是白 60%（亮）/ 白 13%（暗）。
6. **一个形状，永不分裂**：默认/悬停/选中/展开是**同一个元素**在改宽高、圆角、底色、发光，
   内容在切换瞬间糊一下。不叠第二层描边、不加第二颗常驻光晕。
7. **两族尺寸不能混用**（v1 原样继承，仍是本项目最贵的一次翻车）：宽度族 `scaleW` 只跟窗口，
   字号族 `scaleS` 还乘用户的界面字号比例。**展示型数字走宽度族**（§3.1 例外档）：
   大数字要和面板一起长，且绝不允许被用户字号顶破卡片。

---

## 0.5 v2 废除了什么（改动前必读）

v1 是"中性底 + 反相墨"，它的三条禁令正好是 v2 的三条主张。以下是**明确作废**的条目，
读到旧代码/旧注释按这些结论处理，不要来回摆：

| v1 原条 | v1 怎么说 | v2 结论 |
|---|---|---|
| §0.1 中性底 | 所有表面纯灰，不掺色温 | **作废**。掺冷紫相；纯灰只留在实色密度面（§2.1 派生档） |
| §0.2 主色是墨 | 反相墨做主按钮/选中/开关 | **作废**。`accent` 换柔彩蓝，实心胶囊 + 白字（§2.1） |
| §0.3 描边优先于投影 | 投影压到 y1/blur2 | **半作废**。实色面仍描边优先；玻璃面靠**顶缘高光 + 有色投影**（§2.4） |
| §0.6 磨砂只在面板上 | 内容卡片一律实色 | **作废**。内容卡片就是玻璃，§7.1 改成"哪些面**不许**玻璃" |
| §5.1 ❌ UI 骨架铺渐变 | 渐变只活在图表线里 | **收窄**。氛围层 + 图表 + 轨道/进度三处允许，其余仍纯色（§5.1） |
| §5.1 ❌ 发光/glow | 层次只来自描边和投影 | **收窄**。事件驱动的一次性发光与状态点呼吸允许，常驻装饰发光仍禁（§5.1） |
| §4 字重上限 w600 | 不用 w700 及以上 | **作废**。徽标与展示数字到 w700；资产里没有 800 档，现有 17 处 `w800` 全部收到 `w700`（§4） |
| §2.5 状态色族 | 五档语义色 | **不动**。涨跌/多空是**身份**不是**状态**，柔彩的绿/粉/橙/青进 `AppAtmosphere`/`AppViz`（§2.5） |

不变的地基：§1 分层、§2.2 水洗方向、§2.3 对比度下限、§2.7 媒体层 chrome、§2.8 三块自成一体的配色、
§3 两族尺寸、§5.2 时长刻度、§5.3 曲线与弹簧、§6 外壳几何、§8 响应式、§11 验收姿势。

---

## 1. 分层：原始色 → 语义角色 → 组件

```
app_colors.dart      原始调色板：色值本身，不含判断
   ↓ 只被下一层引用
app_semantics.dart   语义**角色**（ThemeExtension）：明暗在此一次性解析
app_atmosphere.dart  语义**氛围**（ThemeExtension，🔧 待落地）：背景分层 / 玻璃配方 /
   ↓                  成对渐变 / 水洗档 / 发光——只有渐变和 composite 装饰
app_viz.dart         身份色（图表线成对色）
   ↓ 业务代码只碰这三层
页面 / 组件           AppSemantic.of(context).surface · AppAtmosphere.of(context).glassCard
```

`app_colors.dart` 里的 `LightColors` / `DarkColors` / `AppSurfaces` / `AppBrand` /
`AppStatus` / `AppGlass` **不是给业务代码用的**，它们只负责被上面三层装配。
业务代码写 `isDark ? DarkColors.x : LightColors.y` 就是绕过了这一层，属于待清理项（§11）。

**为什么氛围要单开一档，而不是塞进 `AppSemantic`**：`AppSemantic` 是"角色"层，
它的每个字段都是一条能在 lerp 里插值的颜色；氛围层的主体是 `LinearGradient` /
`RadialGradient` 和一个 `List<BoxDecoration>`——`lerp` 对渐变只能整条换（现
`accentGradient` 就是这么处理的），塞进角色层会让主题过渡出现"颜色在动、渐变在跳"的
错位。分档之后调用点仍然是两行、两个入口，不存在第三套取色姿势。

`style_tokens.dart` 是**采集自参考实现的令牌底料**（`DesignPalette` / `DesignRadius` /
`DesignShadow` / `DesignType` / `DesignSpace` / `DesignFont`），**故意不接进运行时**：
它只被样式总览页 `style_showcase_screen.dart` 消费，用来对照"参考值 vs 我们的值"。
不要把它当第二套运行时主题用，也不要为了"统一"把它焊到 `AppSemantic` 上。

---

## 2. 取色入口：`AppSemantic`（角色）+ `AppAtmosphere`（氛围）

```dart
final s = AppSemantic.of(context);   // 或 context.semantic.surface
final a = AppAtmosphere.of(context); // 背景层 / 玻璃配方 / 渐变——🔧 待落地
final m = AppTheme.metrics;
```

两档都以 `ThemeExtension` 注册进 `ThemeData`，因此随明暗自动切换、参与主题过渡动画、
调用点不需要 `brightness` 分支。

**v2 的取色分界线**：一个颜色如果是"这块面是什么用途"的答案（字、描边、选中底、报错），
走 `s.`；如果是"这块面用什么材质画"的答案（玻璃着色、顶缘高光、氛围投影、成对渐变），
走 `a.`。`AppViz`（§2.6）管图表身份。三档之外不许再有第四种取色入口。

### 2.1 角色表（v2 目标值）

标 ✅ 的是电量统计页已出图验收的实测值（源：`lib/pages/power_stats/power_stats_theme.dart`）；
标 🔧 的是按同一色相派生、**还没出图**的档——落地那一波必须重跑明暗基线才算定稿。

**表面与描边**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `canvas` | 🔧 `#F3E7E4` | 🔧 `#1B1826` | 氛围层的**实底替身**：不画氛围层时（移动端、低端窗）用它；也是渐变第二档色标 |
| `surface` | ✅ `#FFFFFF` | 🔧 `#221C38` | 实色密度面：列表行 / 选中卡 / 菜单 / 输入框 |
| `surfaceRaised` | `#FFFFFF` | 🔧 `#2A2340` | 二级实色：卡片内嵌块 / 浮起菜单 |
| `surfaceSunken` | 🔧 `#F1ECF6` | 🔧 `#1B1728` | 下沉面：输入框底 / 图标占位底 |
| `surfaceHover` | `0x0A000000` | `0x14FFFFFF` | 悬停水洗（方向见 §2.2，**v2 不改**） |
| `surfaceActive` | `0x14000000` | `0x1FFFFFFF` | 按压态（须改半透明，§13 遗留项） |
| `hairline` | 🔧 `#261A3A1A` | 🔧 `#F1EEFA1A` | 发丝分隔线：实色面之间 |
| `border` | 🔧 `#DDD5E8` | 🔧 `#3A3352` | 实色面描边 |
| `borderStrong` | 🔧 `#A79BC0` | 🔧 `#5D5480` | 强描边：需要边界感处 |

> `canvas` 与 `surface` 的关系换了：v1 靠两者明度差分层，v2 靠**材质差**（氛围 vs 玻璃 vs 实色）。
> 所以 `canvas` 现在必须是氛围渐变的**中间档**，否则氛围层缺席时页面底色和渐变对不上。

**文字（带冷紫相的墨阶）**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `textPrimary` | ✅ `#261A3A`（`ink`） | ✅ `#F1EEFA` | 主文字、大数字、图标默认色 |
| `textSecondary` | 🔧 `#5A4C72` | 🔧 `#B9B0D0` | 次级文字 |
| `textTertiary` | 🔧 `#82749B` | 🔧 `#8F86A8` | 说明文字、分组标签 |
| `textDisabled` | 🔧 `#B3A8C6` | 🔧 `#5F587A` | 禁用 |

> 试验页把弱化的墨一律写成 `p.ink.withAlpha(140 / 120 / 90 / 160)`（小标签、小数位、
> 熄灭的点、单位尾巴）。全局化时**这四档水洗保留算式形式**，不进角色表：
> 它们表达的是"同一个 `ink` 的不同在场程度"，拆成四个命名色反而丢掉了这层关系。
> 只有跨页复用的正文/说明文字才用 `textSecondary/Tertiary`。

**强调色（柔彩蓝）**

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `accent` | ✅ `#2F65DE` | ✅ `#7C9BFF` | 选中指示、滑轨游标、进度终点、刷新闪烁、图表线 |
| `accentSolid` 🔧 | `#2F65DE` | **`#3B63D8`** | **实心胶囊/主按钮的底**（暗色档必须比 `accent` 深一档，见下方 ⚠️） |
| `accentOn` | ✅ `#FFFFFF` | ✅ `#FFFFFF` | 强调实心底上的文字——**配对对象是 `accentSolid`，不是 `accent`** |

⚠️ **暗色档的"实心底 + 白字"是算过的，不是看着像**：白字压 `#7C9BFF` 只有 **2.63:1**
（WCAG AA 正文要 4.5:1），压 `#2F65DE` 是 **5.2:1**，压 `#3B63D8` 是 **5.3:1**。
所以试验页那种"filled 胶囊用 `accent` 底 + 白字"在暗色档**不达标**，全局化时拆成两档：
`accent` 负责"亮着的东西"（线、游标、闪烁、字），`accentSolid` 负责"要压白字的实心底"。
亮色档两者同值。**任何新加的实心底都要回 `AppTheme._ensureContrast()` 走一遍**（§2.3）。
| `accentText` | `#2F65DE` | `#7C9BFF` | 选中文字：**v2 起选中字要变色**（墨色语言才靠加粗，彩色语言靠同色） |
| `accentContainer` | `#2F65DE` @ 13% | `#7C9BFF` @ 18% | 选中底 / 图标底（低浓度强调，浓度规则同 §2.5） |
| `accentContainerBorder` | `#2F65DE` @ 26% | `#7C9BFF` @ 34% | 选中卡描边 |
| `accentGradient` | ✅ `violet → accent`（峰值柱那档） | 同 | v2 起**是真的渐变**，不再是"当纯色用"的兼容档 |

**遮罩 / 投影 / 玻璃**（玻璃配方本体在 §2.9，这里只列角色层保留的那几项）

| 角色 | 亮色 | 暗色 | 用途 |
|---|---|---|---|
| `scrim` | `0xB3000000` | `0xB3000000` | 模态遮罩（不动） |
| `shadowKey` | 🔧 `#5B4A7F26` | ✅ `#00000046` | 投影主层：**带色相**，不再是纯黑（v1 是 `0x0F000000`） |
| `shadowAmbient` | `0x07000000` | `0x33000000` | 扩散层，只服务于 §2.4 的浮层/弹窗两档 |
| `glassTint` | ✅ `#FFFFFF96` | ✅ `#221C38A5` | 玻璃卡着色（= v1 的面板着色升级为默认材质） |
| `glassPanelTint` | 🔧 `#FFFFFF7A` | 🔧 `#1B182685` | 常驻面板（侧栏/顶栏）：比卡片更透，好透出氛围层 |
| `glassBorder` | ✅ `#FFFFFFA0` | ✅ `#FFFFFF22` | 玻璃发丝描边 |
| `glassHighlight` | ✅ `#FFFFFFC8` | ✅ `#FFFFFF1A` | **新增**：顶缘那道比下沿亮的高光线（§7.2） |
| `glassBlur` | `24`（`AppGlass.blurMedium`） | 同 | 背景模糊半径 |

### 2.2 状态层方向：**水洗永远朝"看得见"那侧走**

这是本项目踩过最深的一个坑，值得单独写死。

- 亮色侧表面本来就是白（`#FFFFFF` 实色面 / 近白的氛围渐变），再叠半透明**白**是零反馈。
  历史上 `lightSurfaceHover = 0x2DFFFFFF` 正是这个值——卡片、列表行、菜单在亮色模式
  下**完全没有悬停**。现改为半透明黑，压白得 `#F5F5F5`、压氛围得 `#EDE4EA` 一带，依旧透得下去。
  **v2 不换方向**：氛围层再花，水洗这条仍朝"压深"走；玻璃面上的水洗则走 `a.glassHighlight`
  提亮那一档（§7.2），不要在同一张卡上既压深又提亮。
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

### 2.4 投影：实色面走 `s.elevation()`，玻璃卡走 `a.cardShadow()`

v1 的"投影只负责离地一点点"只对**实色面**成立。玻璃卡必须有能撑住厚度的影子，
但它不是黑影子——是氛围色相压暗后的影子，否则在柔彩底上会成一团脏灰。

**实色面与浮层（继承 v1 五档，`shadowKey` 换带色相值）**

| 档位 | y / blur / spread | 用途 |
|---|---|---|
| `none` | 0 | 贴平 |
| `raised` | 1 / 2 / 0 | 微浮：侧栏选中卡、静止实色卡 |
| `card` | 1 / 3 / 0 | 实色卡悬停 |
| `floating` | 10 / 15 / -3 | 悬浮工具条、命令面板 |
| `overlay` | 20 / 25 / -5 | 弹窗 / 菜单 |

ambient 层自动取 `blur×2`、`y×2`。停靠类控件（如底部播放条）要把 y 翻成负值，
向下的影子落在窗口外等于没有。

**玻璃卡（✅ 已验收，两档）**

| 档 | y / blur / spread | 色 | 用途 |
|---|---|---|---|
| `rest` | `scaleW(6)` / `scaleW(16)` / 0 | 亮 `#5B4A7F`@38、暗 `#000000`@70 | 静止玻璃卡 |
| `lifted` | `scaleW(12)` / `scaleW(28)` / `scaleW(2)` | 同 | 悬停、选中、被事件点亮 |

- 投影的 y/blur **可以**吃 `scaleW`（投影跟窗口一起长是合理的），这和 §3.3 禁止
  **描边**吃 `scaleW` 是同一条规则的两面：线要保住物理像素，影子要保住透视感。
- **事件驱动发光**是同一档投影的连续抬升，不是加一层：`blurRadius = scaleW(30) × g`、
  `spreadRadius = scaleW(1) × g`、`alpha = 110 × g`，`g` 从 0 推到 1 再回落（§5.5 数据事件面）。
- 玻璃的描边**恒定**（`glassBorder`，`strokeUltraThin`），hover 不升粗——粗描边会吃掉
  卡内可用宽度，而玻璃卡本来就是拿来放数据的。要升就升发光与投影那两档。
- ⚠️ 旧的"**描边优先于投影**"从此只约束实色面：玻璃面的层次来自
  **顶缘高光 + 有色投影**两件事，描边只负责"这块玻璃有边"。

### 2.5 状态色族（v2 不动）

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
暗色浓度更高，否则在深灰表面上看不出层次。同一档浓度也是 §2.1 `accentContainer` 的算法，
以及胶囊水洗的写法（`c.withAlpha(暗 46 / 亮 34)` 底、`c.withAlpha(暗 90 / 亮 70)` 描边）。

> `danger` 只用于**破坏性**操作（删除、从库中移除）。收藏/喜欢这类"选中"状态
> 用 `accent`，不是红——原先播放器里两处 `Colors.redAccent` 就是这个口径错位。

🚩 **v2 明确：涨跌 / 多空 / 峰谷不是状态，是身份。** 试验页那套绿 `#0CA678`、
粉 `#F06E81`、橙 `#FF855A`、青 `#1B8FB5` **不进 `AppStatus`**，它们和 `violet` 一起
归 `AppAtmosphere` 的方向色与渐变端点（§2.9.2）。理由很实际：`success` 的 `#00BB7F`
和"用电量上涨"的绿是两个语义，硬合成一档会让"抓取成功"和"消耗变多"在界面上同色；
`danger` 的红和"读数下降"更是相反的意思。判据一句话——**这块颜色在报告"好不好"还是在报告"往哪走"**，
前者上状态族，后者上身份档。

### 2.6 身份色板 `AppViz`：图表和图标底，不进语义层

概览/监控类页面里并排的卡片需要一个"身份"来区分（CPU 是天蓝、内存是暖橙…）。
这些色相**不是语义角色**——既不是"成功/危险"，也不是"强调"——所以单列一档
（`app_viz.dart` 的 `AppVizSet.light` / `.dark`），**别塞进 `AppSemantic` 冒充状态色**。

一个 `AppViz` = `base`（主线/图标色）+ `to`（渐变终点），成对出现：
图标底的水洗色、折线本身、折线末端那个圆点共用同一个身份。

用法固定三件套：图标底 `viz.base.withValues(alpha: 暗 0.18 / 亮 0.12)`、
图标 `viz.base`、图表线 `viz.gradient`。**身份色只出现在图标底和图表里，不做卡片描边、不做按钮底。**

**v2 的分工**：`AppViz` 管"这张卡是谁"（CPU/内存/流量…），`AppAtmosphere` 的方向档
管"这个数往哪走"（涨/跌/越过阈值）。两档都是成对色，都不进角色层；
新页面要加身份优先扩 `AppVizSet`，要加方向优先扩 `AppAtmosphere`，不要就地取 hex。

---

### 2.7 媒体层 chrome：唯一一族**故意不跟主题走**的取色

封面卡、看图器、播放器、朗读页压的是照片/视频/专辑图，底色由内容自己决定。
这里的字必须与任意画面对抗，所以暗色下是白、亮色下**还是白**——拿 `textPrimary` 去顶封面，
切到亮色主题就变成白字白底。历史上这族色一直写成 `Colors.white70` / `Color(0x18000000)`
散在 widget 里，现在一律走 `AppSemantic` 上的 getter（底层是 `app_colors.dart` 的
`AppMediaChrome`，全是 `const`，不参与 `lerp`，也不给"顺手调暗"留口子）：

| 角色 | 值 | 顶替掉的写法 |
|---|---|---|
| `s.onMedia` | `#FFFFFFFF` | `Colors.white` |
| `s.onMediaSecondary` | `#B3FFFFFF` | `Colors.white70` |
| `s.onMediaTertiary` | `#99FFFFFF` | `Colors.white60`、`Colors.white54`（两档已并成一条，5 个透明度单位分不出） |
| `s.onMediaFaint` | `#61FFFFFF` | `Colors.white38` |
| `s.onMediaWash` | `#1FFFFFFF` | `Colors.white12`（悬停/选中水洗） |
| `s.onMediaInk` | `#FF0A0A0A` | 恒白底上的深墨字：看图器改名框、白实心按钮、白色磨砂工具条。原 `Colors.black87` 那一档要保浓度就写算式 `s.onMediaInk.withValues(alpha: .87)` |
| `s.mediaStage` | `#FF000000` | 看图/播放舞台底、`Colors.black.withAlpha(n)` 的基准 |
| `s.mediaScrimTrace/Soft/Medium/Strong/Foot/Veil` | `#18/#22/#8A/#DE/#AA/#BB` 前缀 | 封面遮罩渐变、`black54`≈Medium、`black87`≈Strong |
| `s.immersivePanel` / `s.immersiveBorder` | `#6B000000` / `#26FFFFFF` | 沉浸式黑玻璃浮层与其白 15% 描边 |
| `s.onStatusBadge` | `#FFFFFFFF` | **实心**状态底上的字/图标；半透明容器底仍用 `AppStatusRole.onContainer` |

自定义透明度不许往邻近档上靠，走算式形式保像素一致：`s.onMedia.withAlpha(220)`、
`s.mediaStage.withValues(alpha: .35)`。**取色入口仍然是 `s.`**——业务不需要知道它不跟主题走。

⚠️ **chrome 要成对换，不能只换底**：一处底色落进这一族（恒白输入框、白实心按钮、
白色磨砂条），它的**字/图标也必须同时落进 `onMediaInk`**——底恒白而字取 `textPrimary`，
切到暗色主题就是白字白底。这一类是收编时最容易漏的半个转换，判据只看"底跟不跟主题翻"。

### 2.8 成套但不进语义层的三块

同一批迁移里冒出来的另两类：一处一处看像噪音，成套看才发现是"一整套"。

- `s.iconWashAccent` / `s.bubbleSelf` + `s.bubbleSelfOn`（`AppBrandWash`）：品牌紫的图标底水洗与
  我方聊天气泡。这两族**必须按主题分档**——同一条 12% 紫洗压白卡刚好、压暗面几乎看不见。
- `s.terminal`（`AppTerminalPalette`，11 对亮暗 + 3 颗恒亮窗饰灯）：日志控制台是一整套代码编辑器
  配色。不走 `surface/textSecondary`：界面语义色一改，日志正文跟着失层次，那格也不再像终端。
- `AppReaderPaper`（5 档纸张）：阅读页正文底色是**用户选的**内容主题，选了羊皮纸就一直是羊皮纸，
  不跟明暗翻。两处阅读器共用这一份清单，预设与默认值只有一处出处。

### 2.9 氛围层 `AppAtmosphere`：v2 的材质档（🔧 待落地，源已验收）

这一档目前只存在于试验页（`lib/pages/power_stats/power_stats_theme.dart` 的
`PowerStatsPalette`，✅ 已出图验收）。全局化的动作是**整体上收 + 换名**，不是重新设计：
下表每一项都有实测出处，照抄即可，**不要顺手调色**。

#### 2.9.1 背景：对角基色 + 四角色团

```
一层 LinearGradient(topLeft → bottomRight)
  亮：#F9DAC4 → #F3E7E4 → #D4D1E9 → #D3E4F6   stops 0 / .38 / .72 / 1
  暗：#241C33 → #1B1826 → #1A1E2E → #221B31   stops 0 / .38 / .72 / 1
+ 四团 RadialGradient（左上暖橙、右上天蓝、左下薰衣草、右下粉）
  亮 alpha 140~150、radius 0.7~0.8；暗换深色相（#7A4A2E/#2F4E7A/#4A3A75/#6E3A52）alpha 75~85
```

- **`BoxDecoration` 只吃一个 gradient**，所以分层交给页面/外壳叠 `Stack`，
  色板只交 `List<BoxDecoration>`（`backgroundLayers`）——越靠后越浮在上面。
- 这一层永远 `IgnorePointer`：纯装饰不参与命中。
- **只画一次**，画在外壳（§7.4）。页面再画一层就是两张氛围皮叠在一起，滚动时色差会漂。
- 暗色**不是把亮色反一下**：柔彩底压暗后饱和度必须跟着降（试验页的暗档色团 alpha 只有
  亮档的一半，且换成深色相），否则桃红和薰衣草在深底上会成两块荧光斑。

#### 2.9.2 方向色与强调档（成对，明暗各一档）

| 档 | 亮 | 暗 | 用途 |
|---|---|---|---|
| `ink` | `#261A3A` | `#F1EEFA` | 主字、大数字、轨道基线（= `textPrimary`） |
| `accent` | `#2F65DE` | `#7C9BFF` | 实心胶囊、游标、进度终点、刷新闪烁（= `accent`） |
| `violet` | `#715FFD` | `#9C8CFF` | 渐变中间档、峰值徽章 |
| `rise`（绿） | `#0CA678` | `#3FD19C` | 正向增量、上涨柱 |
| `fall`（粉） | `#F06E81` | `#FF8DA0` | 负向、下降柱、空头标记 |
| `warm`（橙） | `#FF855A` | `#FFA07A` | 轨道起点、被越过的档位 |
| `cool`（青） | `#1B8FB5` | `#5AC8E0` | 横幅渐变起点 |

> `ink`/`accent` 与角色层的 `textPrimary`/`accent` 是**同一个值的两个名字**，
> 落地时以 `AppSemantic` 为准，氛围层只留一个引用；不要让两处各写一遍 hex（那正是 §2.6 说的那种重复）。

#### 2.9.3 成对渐变：六档，全是"同一个动作的起收点"

| 档 | 色标 | 方向 | 用途 |
|---|---|---|---|
| `trackFill` | `warm → violet → accent` | 左→右 | 滑轨已填充段：档位越高越冷 |
| `banner` | `#1897A9 → #466DFD → #715FFD` | 左→右 | 事件横幅（抓取成功那一条） |
| `progress` | `rise → accent` | 左→右 | 进度条 |
| `spark` | `warm → violet → accent` | 左→右 | 迷你趋势线：暖→冷对应"越涨越值钱" |
| `peakBar` | `accent → violet` | 下→上 | 峰值柱 |
| `underline` | `warm → accent` | 左→右 | 卡片底缘那条身份线 |

**三条硬规矩**：① 渐变只在**氛围层 / 图表填充 / 轨道与进度填充**三处出现（§0.4）；
② 端点必须成对给，**不许在页面里现拼色标**（`colors: [x, y]` 出现在页面就是债）；
③ 零宽盒上不挂 gradient——Flutter 会在零尺寸 shader 上断言，
`PsGradientBar` 的 `t <= 0.001 ? null : gradient` 就是这个防波。

#### 2.9.4 静止档：轨道、胶囊、空槽、基线

| 档 | 亮 | 暗 | 用途 |
|---|---|---|---|
| `glassTint` | `#FFFFFF`@150 | `#221C38`@165 | 玻璃卡着色 |
| `glassBorder` | `#FFFFFF`@160 | `#FFFFFF`@34 | 玻璃发丝描边 |
| `glassHighlight` | `#FFFFFF`@200 | `#FFFFFF`@26 | **顶缘高光**（两端 alpha 0、中间全值） |
| `shadow` | `#5B4A7F`@38 | `#000000`@70 | 玻璃投影主层 |
| `trackRest` | `ink`@22 | `#FFFFFF`@28 | 轨道未填充段 |
| `chipRest` / `chipRestBorder` | `#FFFFFF`@170 / @200 | `#FFFFFF`@24 / @38 | 未选中档位胶囊 |
| `slotRest` | `#FFFFFF`@70 | `#FFFFFF`@16 | 空槽（TOP5 未填满那几格） |
| `baseline` | `ink`@40 | `#FFFFFF`@46 | 柱状带基线 |

#### 2.9.5 玻璃卡与发光

`a.cardShadow()` 的几何与"发光就是同一档投影的连续抬升"见 §2.4；顶缘高光的画法
（比下沿亮的一道线，去掉"塑料贴片"感）见 §7.2。磨砂那层**不重写实现**，
`GlassSurface` 已经是全站收敛后的那一份，氛围档只提供 tint/border/highlight 三个值。

---

## 3. 尺寸令牌：`AppTheme.metrics`

```dart
final m = AppTheme.metrics;
BorderRadius r = m.radiusCard;   // 注意：radius* 是 BorderRadius，不是 double
double sp = m.kSpace16;
```

- **语义圆角**（调用点优先用这组，不要记数字）：
  v2 按**材质**分档——玻璃比纸厚，圆角必须更大才不像贴纸；实色密度面维持小圆角保住边界感。

  | 档 | v1 | v2 | 用在 |
  |---|---|---|---|
  | `radiusControl` | 8 | 🔧 10 | 按钮 / 控件 |
  | `radiusField` | 8 | 🔧 10 | 输入框 |
  | `radiusCard` | 10 | 🔧 **16**（✅ 实测：`PsGlassCard` 默认就是 `m.radius16`，`power_stats_widgets.dart:197`） | 玻璃卡 / Hero 面板（列表行仍取 10） |
  | `radiusPanel` | 14 | 🔧 **20**（✅ 实测 `radius20` 只出现在"大按钮"这一档：抓取按钮 `power_stats_screen.dart:216/230`） | 弹窗 / 抽屉 / 大按钮 |

  ⚠️ **实测的例外档：密排小卡收一档。** 六列维度卡用的是 `radius14`（`power_stats_screen.dart:706`），
  不是 16——同一行里并排六颗，圆角再大一档就成六个胶囊，卡片之间的边界读不出来。
  规则：**一行 ≥ 4 张卡时降一档**（16→14），不是随手取数字。
  | `radiusOverlay` | 14 | 🔧 20 | 弹窗 / 抽屉 |
  | `radiusPill` | 999 | 999 | 胶囊、徽标、轨道、滑轨游标 |

  ⚠️ 这三档一改是**全站重排**（56 个 screen/page 文件都会跟着变），必须和 §13 W0 同一批落地、
  同一批出图；不要一边迁页面一边留着旧圆角，那会得到一版"卡片有的厚有的薄"。
  列表行、菜单行（`GlassMenuItem` 行高 30 那一族）**不跟着升**——圆角一大，
  小尺寸控件就变成一颗颗胶囊，列表读不出边界。
- **数值圆角**：`radius2/3/4/6/8/10/12/14/16/18/20/22/24/25/28/32/40/100/999`
- **间距**：`kSpace1/2/3/4/5/6/8/10/12/14/16/18/20/24/32/40/44/48/56/64/80`
  （别名 `paddingSmall/Medium/Large/XLarge`、`spacingSmall…`）
  ⚠️ **没有 `kSpace26/36/96`**，超出档位用 `scaleW(n)`
- **字号**：`fontSize9/10/11/12/13/14/15/16/17/18/20/22/24/28/32/36/48/72`
- **图标**：`iconSize12/13/14/15/16/18/20/22/24/28/32/40/44/48/64/96`（**没有 38**）
- **描边宽度**：`strokeUltraThin`(0.5) · `strokeHairline`(1.0) · `strokeThin`(1.5) ·
  `strokeRegular`(2.0) · `strokeEmphasis`(2.5) · `strokeBold`(3.0)——这六档是**固定值，
  不吃 `scaleW`**（原因见 §3.3），别在调用点裸写 `width: 0.5` / `strokeWidth: 2.5`，
  也别写 `width: scaleW(1)`：后者看着像走了尺寸口径，实际是把"1 这条线"塞进了宽度族，
  窗口一放大描边就跟着变粗。
  **覆盖范围是四个入口**：`Border.all(width:)`、`BorderSide(width:)`、
  `Divider(thickness:)`、`Paint()..strokeWidth` 与 `CircularProgressIndicator(strokeWidth:)`。
  口径：`grep -rn "Border\.all(\|BorderSide(\|strokeWidth\|thickness:" lib/ --include='*.dart' | grep -E "(width|thickness|strokeWidth)[=:] *(scaleW\()?0?[0-9]"`
  剩下的应当只有图表画笔（§2.6 的 `AppViz` 那类：仪表盘环 6、十字线 0.8 这类跟几何走的量）。
  `strokeEmphasis` 是给"2.0 压在封面上细成一条线、3.0 又太笨"那档进度环/选中环的

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

推论（第三次发作，v2 立档）：**图表浮层是"字号族内容 + 宽度族画布"的正面冲突，必须让浮层逃出画布。**
浮层的字取 `m.fontSize*`（吃用户字号），它挂在图表的绘制盒上（`scaleW(126)` 之类，不吃字号），
于是字号一放大就报 `A RenderFlex overflowed by 4.9 pixels on the bottom`。修法不是在盒子里缩字，
而是让浮层**不受画布高度约束**——`SingleChildLayoutDelegate.getConstraintsForChild` 返回
`BoxConstraints(maxWidth: constraints.maxWidth)`。两个坑叠在这里：

1. `constraints.loosen()` 只松掉 min，`maxHeight` 还留着画布那一档；
2. `copyWith(maxHeight: null)` 是"**保持原值**"，不是无穷——必须重新构造 `BoxConstraints`。

浮层本来就该盖在图表外面（父 `Stack` 是 `Clip.none`），所以高度这一档不给上限。
**验收姿势（写死）**：任何带文字浮层的组件，必须有一条 `AppTheme.fontScaleObs.value = 1.6` 的
用例并 `expect(tester.takeException(), isNull)`；只看 1.0 档的出图等于没测（§11 第 7 条）。

**例外档：展示型数字走宽度族。** Hero 大数字是 `scaleW(52)` + `letterSpacing: scaleW(-1.5)`，
小数位 `scaleW(24)`——它和面板一起长，**不跟用户字号长**。理由：这块数字在版式里是图形不是正文，
让它吃字号会把整块 Hero 顶变形，而读屏幕的人真正需要放大的是正文。
约束：这类数字必须待在宽度有界的容器里，并且**必须有 1.6 字阶回归兜底**（因为同卡内的
说明文字会放大，数字不放大，两者会互相挤）。判据一句话——**这串数字是"看量级"的还是"读内容"的**，
前者走宽度族（`display-number` / `metric`），后者走字号族。

### 3.2 为什么宽度类尺寸要 `scaleW` 而不是 `const`

`scaleW(w) = ScreenUtil().setWidth(w * _adaptiveScaleFactor())`，按**当前窗口宽度**折算。
写死 `const _kSidebarWidth = 220.0` 的话窗口缩小侧边栏不会跟着收，所以这类值要写成
`double get _kSidebarWidth => scaleW(220);`——**用 getter，不是 const**。

规范：禁止裸数字和 `int.w`；`AppTheme.metrics` 里没有的档用 `scaleW()`。

### 3.3 高/低分辨率与 DPI：**"看着差不多大"怎么成立**

两条独立的通道，别混：

1. **物理 DPI**（1× / 2× Retina / 4K）：Flutter 的 `devicePixelRatio` 已经把逻辑像素
   折算成物理像素，**这一层不需要项目做任何事**。要防的是"1 物理像素"的东西被抗锯齿
   冲淡——发丝线一律 `width: 1` 固定值（写成 `m.strokeHairline`，别写 `scaleW(1)`，
   主题构建器里那批 `scaleW(1)` 是历史遗留、已收编），**不要写 `1.w`**（缩放后不足 1 物理像素就糊成灰边）。
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

**字重政策（v2）**：`w400` 正文 · `w500` 行标题/按钮/标签 · `w600` 小节与卡片标题 ·
`w700` **只给两类东西**：徽标胶囊里的字、展示型数字。
v1 的"不用 w700 及以上"作废——那条是为"重靠描边和抬升表达"的墨色语言定的，
柔彩玻璃语言里实心胶囊和渐变数字**需要**自身有重量，否则白字压蓝底会显得没劲。
仍然不放开 w800/w900：正文一律够不到那一档，只有"数字当图形"时才用最高档。

⚠️ **实测的资产缺口**：`pubspec.yaml` 与 `assets/fonts/` 里 Inter 只有 **400 / 500 / 600 / 700** 四档，
所以 `FontWeight.w800` 拿不到实体字面、静默降到 Bold。试验页有 15 处、`sentry_log` 有 2 处写着 `w800`
（口径：`grep -rn "FontWeight.w800" lib/ --include='*.dart'`）——**要么把 Inter-ExtraBold 补进资产并登记四档→五档，
要么把这 17 处收编到 `w700`**。在补资产之前，`w800` 不许新增。

**数字排版**：展示型数字与徽标一律开 `FontFeature.tabularFigures()`（等宽数字，
滚动补间时不左右跳），大数字配负字距（`scaleW(-1.5)`），单位尾巴和前缀单独一档
（`0.62` 倍字号 + `alpha 160`）——**别让单位继承父级正文样式**，那会让它在同一行里粗一圈。

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
| `metric` | 28 / w700 / textPrimary / 负字距 / 等宽数字 | 数据大屏数字（🔧 原 w600，v2 升一档） |
| `displayNumber` | `scaleW(44–52)` / w700 / `ink` / height 1.02 / `scaleW(-1.5)` 字距 | Hero 主数字（**宽度族**，见 §3.1 例外档）；小数位另降 `0.46` 倍 |
| `badge` | 10–11 / w700 / 状态或强调色 / `+0.8~1.2` 字距 / 等宽数字 | 胶囊徽标、LIVE、W/L 计数、档位名 |
| `mono` | Menlo 12 / textSecondary | 日志、路径、代码 |

`rowTitle` 与 `cardTitle` 只差一档字重：整页卡片标题要撑住区块，列表行里几十条同名行
用 w600 会糊成一片黑。

⚠️ `mono` 的 Menlo 是 **macOS 字体**，但整块终端/日志区是跨平台成套的：`AppTheme._monoFontFamilyFallback`
已排好 `Consolas`(Win) → `DejaVu Sans Mono`/`Liberation Mono`(Linux) → `monospace`，
字族名单收口在这一处。**不要在调用点手写 `fontFamily: 'Menlo'`**，那等于绕过回退清单。

⚠️ **`TextStyle` 在组件主题里是整条替换，不是叠加**。`ButtonStyle.textStyle`、
`dialogTheme.titleTextStyle`、`popupMenuTheme.textStyle`… 一共 20 处，裸写就会把
主题字阶的 `fontFamily` 丢掉（表现是：只有按钮和菜单里的中文是豆腐块，其余正常）。
统一走 `AppTheme._font(...)` 和 `_buttonTextStyle()`。

⚠️ 反过来说，**裸 `TextStyle(...)` 在 `Text` 里且 `inherit: true`（默认）时是安全的**：
它会和 `DefaultTextStyle` 合并，字族能继承下来。所以日志终端那种"整段继承等宽、
子 span 只改颜色"的写法是合法的——`RichText` 的子 span 千万不要重复写 `fontFamily`。

`AppTextStyles.role(...)` 逃生口除 `fontSize`/`color`/`weight` 外还吃 `decoration`：
"划掉/下划线"这类只改修饰的调用点以前只能 `role(...).copyWith(decoration: …)`，
多一次 `copyWith` 就多一个能跑偏的地方。

---

## 5. 动效：`AppMotion`

### 5.1 语言

**一个形状，永不分裂。** 控件的默认 / 悬停 / 选中 / 展开是同一个元素在改
**宽高、圆角、底色**，内容在切换的那一瞬糊一下（短暂模糊），不是"旧的东西消失、
新的东西出现"。指针要驱动它（悬停即响应），点击和拖拽要有真实的跟手感。

**v2 补的第一原则：动效只由"事情发生了"驱动，不由时间驱动。**
这条是电量统计页整块试验的核心，也是它和"模板动效"的分界线：

- **值没变不起钟**（`didUpdateWidget` 比 `old.value`，相等就直接跟到新终值，不播）。
  数据每 30 秒才回一次真值，所以补间必须**只在拿到新值那一刻**跑——
  常驻跳变是在骗用户"数据一直在涨"。
- **新数据只动尾巴**：抓取到的新段只给那一段做入场，历史段静止。
- **换范围整带重播**：切换区间是"换了一副眼镜看同一件事"，所有图表按 `trigger` 重播一次入场，
  但入场是错峰的一批（§5.2 `stagger`），不是一屏同帧。
- **推完静止**：进度条、滚动数字跑完就停，不循环、不回弹。

允许：
- 弹簧收尾，**最多一次轻微过冲**（overshoot ≤ 6%）。
- 状态切换时**尺寸、圆角、底色、发光同时动**，共用一条时间轴。
- 转场用"镜头拉近"的思路：让**当前状态的那个元素**放大铺满画面，而不是换一张脸。
- **事件驱动的一次性发光**（0→1→0 的投影抬升，§2.4）与**状态点呼吸**（`ambient` 档循环）。
- 渐变只出现在三处：**氛围层**、**图表填充**、**轨道与进度填充**（§0.4、§2.9.3）。

禁止（每一条都是真实翻车过的观感）：
- ❌ 弹跳缓动（bounce）、多次回弹。
- ❌ 粒子、爆花、星星点点。
- ❌ **常驻装饰性发光**、外发光描边、glow 当层次用。发光只在"事件点亮的那一下"存在；
  静止状态下的卡片靠玻璃描边 + 有色投影站立（§2.4）。
- ❌ **UI 骨架铺渐变**：按钮底、卡片底、输入底、侧栏底、图标底一律纯色。
  渐变一旦进控件底，"一个形状永不分裂"就没了——切换状态时用户看到的是换了块装饰。
- ❌ 图标描边粗细不一致（全局图标组件见 §9.1）。
- ❌ **用模糊表达远近**（堆叠越深越糊）。允许的"短暂模糊"只活在状态切换的那一瞬；
  常驻的景深糊在白药丸压近白舞台这种低对比内容上一眼读作"没对齐/渲染坏了"。
  远近只用位移、缩放、变暗三样表达。
  ⚠️ 玻璃的 `BackdropFilter` **不属于这一条**：它是材质（透出背后的氛围），不是深度线索；
  两者的 sigma 也分属两档（§5.4 的对照表）。
- ❌ 无事发生的空等时间；也 ❌ 一眼看出是模板套出来的动效（无数据变化却一直在动，就是模板味）。

### 5.2 时长节奏

原先散落 250/280/300/400/600ms 各自为政，观感"有的跟手、有的迟钝"。

| 档 | 值 | 对标的外部档位 | 用在 |
|---|---|---|---|
| `instant` | 90ms | micro(80) | 颜色/底色换（水洗、hover 起） |
| `fast` | 160ms | quick(150) | press 起、退场统一档、hover 收 |
| `base` | 220ms | fast(250) 减一档 | 状态类：展开/收起/选中/切换 |
| `slow` | 320ms | medium(350) | 空间类：页面转场、抽屉、弹窗进场 |
| `emphasis` | 460ms | very-slow(500) | 一次性的重头动作（启动入场） |
| `stagger` | 45ms | 参考库取 40–90 | 会反复触发的列表逐条入场间隔 |
| `entrance`/`entranceGap` | 600/80ms | — | 开机整块面板入场，只播一次 |
| `cascade` | 900ms | — | 入场级联的**主控轴**（每张卡按 0~1 的 `Interval` 摊在这条轴上，不是单条时长） |
| `roll` 🔧 | 720ms | — | **数据补间专档**（建议新增）：滚动数字、渐变条推满。它必须比 `emphasis` 慢——数字是要读完的，不是闪过的；试验页实测 720ms，比 `emphasis` 长 260ms 是有意的 |

🔧 **档外的两个实测值（落地时必须归位，别原样抄进全局层）**：
`PsRollingNumber.duration` 默认 720ms（→ 新增 `roll` 档）；`PsStagger` 的 `rise: 14` 设计像素
不在位移五档上（→ 收 `travelMedium` 12，见 §5.4）、`fromScale: 0.9` 不在缩放五档上（→ 新增
`scaleBlock`）。**靠档的代价要当场报**：这三处一收，电量统计页的入场会轻微变短变收，
12 张 golden 要重跑基线（§10.17 同一口径）。

**反馈类必须 ≤160ms**。悬停超过这个值就不叫"跟手"，叫"卡了一下才理你"。

**退场一律比进场快**：进场要给"落位感"，退场只要"别挡路"。同一动作的开/收取**相邻两档**
（开 `base` → 收 `fast`；开 `slow` → 收 `base`），曲线跟着换
（`decelerate` 进 / `accelerate` 出）。倒放同一条时间轴是省事，不是正确。

**循环动画和浮层驻留不吃上面这套档位**——它们根本不是 A→B 的过渡，拿 `base`/`slow`
去顶"常驻呼吸"会得到抖得发慌的效果：

| 档 | 值 | 用在 |
|---|---|---|
| `beat` | 800ms | 快节奏循环：打点、节拍、唱盘纹动 |
| `pulse` | 1200ms | 中速循环：加载脉冲、骨架屏呼吸 |
| `ambient` | 1600ms | 慢速常驻环境动效：在线状态点、缓慢呼吸的图标底 |
| `spin` | 8s | 一整圈自转（黑胶那类"要看出在转但不能晕"） |
| `dwell` / `dwellLong` | 2s / 3s | SnackBar·Toast 驻留；带操作入口或信息量大的那条用 `dwellLong` |
| `dwellNotice` | 5s | 正文要逐字读完的通知（失败原因、生成路径、新版本号） |

**不是动效的时长不进这套档位**。网络超时、轮询、防抖、权限重试间隔、播放器 seek、
逐帧节拍（16ms）和"多久没动就进沉浸模式"这类 idle 计时是**数据节奏**，留在各自的
service / 设置项里、各带一句注释说明为什么是这个数；把它们塞进 `AppMotion`
只会让节奏表变成垃圾桶。判据一句话：**这个时长决定的是"画面怎么变"，还是"什么时候再做一次"**
——前者上档，后者不上。同理，用户在设置里可调的那个数（隐私模糊 sigma、自动沉浸秒数）
也不进档位。

### 5.3 曲线与弹簧

现有：`standard`（通用，起步快收尾稳）、`decelerate`（进场/展开，落位感）、
`accelerate`（退场/收起，不拖尾）、`linearish`（进度条）。
`AnimatedX` 一律用 `AppMotion.defaultDuration` + `defaultCurve`，不要每处手写。

**全站 `Curves.*` 已归零**（口径：`grep -rn "Curves\." lib/ --include='*.dart' | grep -v core/theme/`
再排掉 §12.3 的实验室页）。换法是一条固定映射，遇到新的手写曲线按它归位，别新增档位：

| 原来写的 | 收到 |
|---|---|
| `easeOutCubic` / `easeOut` | `decelerate` |
| `easeInCubic` / `easeIn`（含 `reverseCurve`） | `accelerate` |
| `easeInOut` / `easeInOutCubic` | `standard` |
| `easeOutBack` / `elasticOut`（§5.1 禁的多次过冲） | `springCurve` |

弹簧档已落地：`AppMotion.spring`（`mass 1 / stiffness 260 / damping 22`，
阻尼比 ζ≈0.68 → 过冲约 5%，**只回一次**）。两种用法：

- 能手握 `AnimationController` 的走 `animateWith(SpringSimulation(spring, …))`；
- `AnimatedContainer` / `AnimatedSize` 这类只吃 `Curve` 的走 `AppMotion.springCurve`
  （同一条弹簧的近似曲线，过冲量对齐，免得两个档位观感对不上），时长取 `springSettle`。

规则：**只有"状态改变"用弹簧，hover/press 这类高频反馈仍然用短时长曲线档**——
弹簧在 90ms 尺度上看不出过冲，只会让手感发黏。

🔧 待接线：全站绝大多数 `AnimatedX` 还挂在 `standard` 上，按 §5.5 逐面迁到弹簧档。

配套件：

- `StaggerEntrance`（逐条浮现，替代各页手写的 `Future.delayed(300 + i*80)`——
  那种写法会造成"可点击但无内容"的空窗）。
- `StateTransitionAnimation`（图标+文字换脸，已带 in/out 位移与瞬时模糊，
  是 §5.4 那一族唯一的现成消费者）。
- 🔧 `AppPageTransitions.fadeUp` **定义了但没人用**：路由转场现在仍走
  `app_routes.dart` 里两条各自手写的 builder（一条纯淡入，一条淡入 + 0.985 微缩放）。
  曲线已经都在档上（`decelerate` 进 / `accelerate` 出），但 260ms 那一档不在 §5.2 的刻度里，
  0.985 也不在 §5.4 的缩放五档里——两条 builder 合成一条 `fadeUp` 之后，
  这两个数才会自动归位。`StateTransitionAnimation.animationDuration` 的默认值同样还是手写的 400ms。

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

**缩放是无量纲**的，只有五个合法值，别在页面里现写 `0.93`：
`scalePress 0.98`（按压）/ `scaleMenu 0.97`（菜单从触发点长出）/
`scaleEnter 0.96`（浮层进场起点）/ `scaleStage 0.93`（全屏舞台进场：看图器这类整块画面
推近，比浮层要看得出更多位移）/ `scaleRetreat 0.99`（收起终态，留 1% 才看得出是
同一个东西缩回去，而不是消失）。

🔧 **v2 加第六档 `scaleBlock = 0.90`**：整块面板 / 柱状带 / TOP5 槽位这种"一块内容错位进场"
的起点。`scaleStage 0.93` 是给**全屏**画面推近用的，用在一张卡上位移感不够；试验页实测用的
就是 `0.9`（`PsStagger.fromScale`），所以这档照实测落名，别再在页面里现写。
同族里 `travelMedium 12` 收掉试验页的 `rise: 14`——位移差 2 设计像素看不出来，
缩放差 3% 看得出来，所以一个靠档、一个补档。

**瞬时模糊**是这套语言里"内容换脸"的那一下：状态切换的瞬间给旧内容加模糊、新内容从模糊里
结像（`StateTransitionAnimation` 已经是这个做法）。它和磨砂玻璃的
`BackdropFilter` 是**两件事，别互相引用值**：

| 族 | 值 | 对象 |
|---|---|---|
| `AppMotion.blurContent 2 / blurPanel 4 / blurPage 8` | sigma，**几帧之内退干净** | 正在换脸的内容 |
| `AppGlass.blurTrace 3 / blurFeather 8 / blurSoft 12 / blurMedium 24 / blurStrong 40 / blurArtwork 50` | sigma，**常驻** | 玻璃面板背后 |

`blurTrace`/`blurFeather` 是量程下界：封面卡上的浮层（收藏角标、底部磨砂栏）要在
"透出封面才知道是同一张卡"和"压得住白字"之间分 hover 前后两档，`blurSoft` 一起步就糊成一块板。

内容模糊停在半路就是"糊了"，不是"在动"——进出场两侧都必须收到 0。
隐私遮罩的 sigma 是**用户设置值**（`MediaPrefsService.privacyBlurSigma`），不是档位，
不要往 `AppGlass` 上收。

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
| 15 | 数值变化（仪表盘指标、电表读数） | **补间滚动到新值**：整数值 `Tween` 滚动 + 滚动期间染强调色再 lerp 回本色；**等宽数字**（`tabularFigures`）防行抖；不要弹跳计数 | v1 写的是"逐位上滑"，试验页实测改成**整体补间 + 闪烁**（更像电表、且实现只有一条钟）；逐位上滑留给表格里"一列同时刷新"那类 🔧 |
| 16 | 流式输出（Ollama 生成、下载日志） | 按词进：间隔 60ms、单条 `base`、`blurContent` 1 档；状态行换行时进出同时播 | 🔧 |
| 17 | 校验失败抖动 | `travelSmall` 四段往复，末段不回弹；错误态 3s 后自动淡回 | 🔧 |
| 18 | 状态点脉冲（节点/服务在线） | `cycle 1200ms`，只走状态色或 `AppViz`，同族共享节拍、各自延迟 | 试验页 LIVE 点已实测：`ambient` 档呼吸 + 光晕 `blurRadius scaleW(2+8t)`，`isLive=false` 时**完全静止**、灰 `ink@90` ✅ |
| 19 | 通知堆叠（任务队列） | 最多露 3 张：每深一层 `scale 0.94`、Y 抬 `travelMedium`、透明度 0.6、blur 加一档；hover 展开成列并去掉深度缩放 | `floating_task_progress.dart` 现在只显一条、且完全静态 🔧 |
| 20 | 玻璃卡被事件点亮 | `rest → lifted` 的投影抬升 + 发光 `g: 0→1→0`（§2.4），描边同时向强调色 lerp 一档；**一次性**，落回静止 | ✅ 试验页抓取成功那一下（`PsGlassCard.glow`）→ 组件上收 🔧 |
| 21 | 数据刷新闪烁 | 数字滚到新值的同时整块底色做一次 `fast` 水洗，不循环；值未变则**整条不起钟** | ✅ 试验页（`didUpdateWidget` 比 `old.value`）🔧 全局件待上收 |
| 22 | 新增长出来的那一段（时序带、日志列表） | **只给末尾段做入场**（`travelMedium` 上浮 + `scaleBlock`），历史段静止；整带不许跟着重排 | ✅ 试验页柱状带尾巴动画 🔧 |
| 23 | 换范围 / 换数据源 = 整带重播 | `trigger` 变化 → 所有图表按 `stagger` 逐条重播入场；重播是**一次性**的，播完静止 | ✅ 试验页（`_shapeTick = 区间|指标|单位`）🔧 |
| 24 | 图表浮层跟指针 | 浮层贴在焦点列上（`SingleChildLayoutDelegate`），换列只改位置和文字，**不重播**；浮层高度不受画布约束（§3.1 第三次发作） | ✅ 试验页三处浮层，含 1.6 字阶回归 |
| 25 | 档位滑轨 | 填充与游标**共用一条补间**（才像"同一根被推过去的针"）：`base` + `decelerate`，游标 `accent` + 白 2px 圈 + `accent@90` 光晕 | ✅ 试验页 `PsRangeTrack` 🔧 全局件待上收 |

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

## 7. 玻璃、氛围层与窗口透出

"透出背后内容"是**两层**结构，缺一层就不成立：

1. **窗口本身透明** —— `macos/Runner/MainFlutterWindow.swift` 往 `NSThemeFrame`
   插 `NSVisualEffectView`（`.fullScreenUI` / `.behindWindow`），负责透出**桌面**。
   该视图重写了 `hitTest` 返回 nil：否则 AppKit 会把事件全吃进原生层，Flutter 收不到点击。
   Windows 走 DWM 背景材质（申请压克力而非 Mica：Mica 只是壁纸静态着色，不透不糊）。
2. **面板与卡片再叠 `BackdropFilter`** —— 负责透出**同一 App 内**它下面的东西
   （氛围层色团、滚到卡下方的列表），这是 v2 层次感的主要来源。

### 7.1 哪些面**不许**是玻璃（v1 那张表反转了）

| 允许玻璃 | 不许玻璃（一律实色或水洗） |
|---|---|
| 内容卡片、Hero 面板、侧栏、顶栏、悬浮工具条、弹窗/菜单、底部播放条、图表浮层 | **列表行**、**输入框**、**菜单行**、**图标底**、**按钮底**、代码/日志正文区 |

判据是**密度**，不是层级：一张卡里少于 ~20 个可视元素才经得起磨砂，一屏 40 行的列表玻璃化之后
整页发脏、字对比度被吃。所以 v2 是"卡片玻璃化 + 密度面保持实色"，而不是"全都半透明"。
实色密度面继续走 §2.1 的 `surface` / `surfaceSunken` / `surfaceHover`。

### 7.2 组件与档位

| 组件 | 签名要点 |
|---|---|
| `GlassSurface(child, blur, tint, borderColor, borderRadius, padding, elevated, asPanel)` | 全站唯一磨砂实现，**不要另写一份**；v2 起默认 `tint = a.glassTint`、`radius = radiusCard(16)` |
| `GlassCard(child, padding, radius, glow, glowColor, tint, borderColor, onTap)` 🔧 | **由 `PsGlassCard` 上收**：`GlassSurface` + 顶缘高光 + 事件驱动发光三件套（§5.5 的 20） |
| `GlassAppBar(title, leading, actions, bottom)` | 顶/底吸附条，内容从其下方滚过（外壳顶栏应走这个，🔧） |
| `GlassFloat(child, padding, borderRadius)` | 命令面板 / 悬浮工具条 / 下拉浮窗 |
| `GlassMenuItem(label, icon, destructive, selected, value, enabled)` | 桌面紧凑菜单行，行高 30（Material 默认 48 是给触屏定的）——**这一族保持实色**，见 §7.1 |

**顶缘高光是玻璃的必备第三层**（不是可选装饰）：一道 `strokeUltraThin` 的线，
两端 alpha 0、中间全值（`glassHighlight`），左右各留 `radius × 0.6` 的起点。
没有它，玻璃卡读起来就是"贴了片半透明塑料"；有了它，光才像是从氛围层那边过来的。
它必须 `IgnorePointer`，且**永远只在顶缘**——下沿来一道就成了描边，那是 v1 的语言。

| 档位（`WindowGlass`，`window_backdrop.dart`） | alpha | 生效条件 |
|---|---|---|
| `contentAlpha` | 180 | 仅 macOS（正文密度高，透明度已收敛得很低） |
| `panelAlpha` | 200 | 侧栏/面板 |
| `overlayAlpha` | 242 | 浮层（菜单、弹窗、底部播放条） |

非对应平台一律 255（实心）。模糊半径：卡片走 `blurMedium`(24)（即 `s.glassBlur` 默认档），
浮层小片用 `blurSoft`(12)，封面卡上的角标类浮层用 `blurFeather`(8) / `blurTrace`(3) 两档下界。
`kWindowsGlassEnabled` 是 Windows 子窗口 HWND 能否透出的总开关——**该项在 Windows 上尚未实测**，
观感异常先把它改成 `false` 退回实心底。

### 7.3 取色禁忌

- `GlassMenuItem` **不再自建悬停药丸**：外层 `InkWell` 用的就是 `ThemeData.hoverColor`
  （= `surfaceHover`），自己再叠一颗会变成"方块灰 + 药丸灰"两层。
- 菜单/浮层底色一律 `surfaceRaised.withAlpha(WindowGlass.overlayAlpha)`，
  不要写死 `Colors.black45` 之类。
- 玻璃上的描边只用 `a.glassBorder`，不要另配 `Colors.white.withAlpha(180)`——
  那条历史上就是浅色档看不见、深色档过重的一根线。
- **不许玻璃叠玻璃**：玻璃卡内部的小块（内嵌分组、槽位）走 `slotRest` / `chipRest` 水洗档
  （§2.9.4），不再套一层 `BackdropFilter`。两层模糊叠在一起除了贵没有别的效果。
- **发光不靠加粗描边**：事件点亮抬的是投影与发光（§2.4），描边只做颜色 lerp，
  加粗会吃掉卡内可用宽度。

### 7.4 氛围层只画一次：收口位置与预算

- **单一出处**：氛围层画在外壳（`DesktopScaffold` 正文区底 / `ScreenChrome` 的 body 之下），
  页面**不得**再叠一层自己的背景渐变。试验页现在是自己画的（`_buildBackground`），
  这是它在试验期的特权，W0 上收后取消（🔧）。理由见 §2.9.1：两张氛围皮叠着，滚动时色差会漂。
- **性能预算**：同屏 `BackdropFilter` 实例 **≤ 8**。试验页实测 5 张 `PsGlassCard` + 内部件，
  明暗两档出图和真机都跟得住；再往上加要先测帧时间，不要凭感觉加卡。
  需要"很多张卡"的页面（媒体库、账本明细）用**分组长卡**：一张玻璃包住 N 行实色内容。
- **降级**：移动端与窗口 ≤600 时 `GlassSurface` 一律走 `alpha=255` + 跳过 `BackdropFilter`，
  玻璃卡退成 `surface` 实色卡（§8）。氛围层**保留**——它是底色语言，不是效果，
  在移动端换成单层 `canvas` 实底即可（渐变层数按平台裁）。
- **命中**：氛围层与顶缘高光永远 `IgnorePointer`。

---

## 8. 响应式与移动端兼容

- 平台判断：`SizeUtils.isDesktop / isMobile`（macOS·Windows / iOS·Android）。
- 窗口降级：`isPhone`（宽 <600）时 `_adaptiveScaleFactor()` 自动收紧所有 `scaleW` 值。
- 外壳：`DesktopLayout` 在窗口 ≤600 或移动端平台时切 `MobileLayout`——侧栏**浮在内容之上**
  （不是贴在桌面之上），所以那一层必须整窗不透明，否则根 Material 一透明，
  正文就直接压在桌面背景上（这条已经踩过，见 `desktop_layout.dart` 注释）。
- 移动端**没有磨砂**：没有原生振动层，半透明只会透出窗口底色，观感是"脏"。
  所有 `Glass*` 组件在移动端走 `alpha=255` 分支，玻璃卡退成 `surface` 实色卡（§7.4）。
  **但氛围层不降级成 v1 的纯灰**：移动端保留柔彩底，只是把 4 团径向色团裁掉、留单层对角渐变，
  卡片退回实色——换了材质，不换颜色语言。
- 玻璃预算（同屏 `BackdropFilter` ≤ 8）是按桌面定的；移动端一律 0，桌面窄窗（≤600 强制移动模式）
  也按 0 处理。
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
| `AppToast.error(context, message)` / `AppToast.errorBar(s, message, {duration, action})` | `app_toast.dart` | 39 个文件里 111 处手写 `showSnackBar`（时长、图标、颜色各写一套）+ 报错原文铺界面 |
| `SectionHeader` / `OverlineLabel` | `section_header.dart` | 约 12 份小节标题（仅设置模块就 7 份） |
| `ContentContainer` / `AppSplitView` | `page_container.dart` | 18 种不同 `maxWidth`、各页 `Row + SizedBox(魔数) + Expanded` |
| `GlassSurface` / `GlassAppBar` / `GlassFloat` / `GlassMenuItem` | `glass_surface.dart` / `glass_menu.dart` | 见 §7 |
| `GlassCard(child, padding, radius, glow, glowColor, onTap)` 🔧 | 待上收（现 `power_stats/components/power_stats_widgets.dart`） | 每页各写一遍"磨砂 + 高光 + 有色投影" |
| `MetricNumber(value, majorStyle, minorStyle, flashColor, prefix, suffix)` 🔧 | 待上收（现 `PsRollingNumber`） | 各页 `Text('$value')` 硬换值，数据刷新时整块重画 |
| `GradientBar(value, gradient, track, height)` 🔧 | 待上收（现 `PsGradientBar`） | 各写各的 `FractionallySizedBox + 单色` |
| `StaggerBlock(index, trigger, rise, fromScale, child)` 🔧 | 待上收（现 `PsStagger`） | 各页手写的 `Future.delayed(300 + i*80)`（§5.3 点名的空窗写法） |
| `SectionLabel(text, color, trailing)` 🔧 | 待上收（现 `PsSectionLabel`） | 与既有 `SectionHeader` / `OverlineLabel` **合并成一族**，不要三套并立（§9.2） |
| `Pill(label, color, filled, leading, dense)` 🔧 | 待上收（现 `PsPill`） | 与 `StatusChip` 的分工见 §9.2 |
| `RangeTrack(ranges, selected, onChanged)` 🔧 | 待上收（现 `PsRangeTrack`） | 各页分段选择器（§5.5 的 11）与时间范围条 |
| `ChartTooltip(label, valueText, note, color)` + `TooltipLayoutDelegate` 🔧 | 待上收（现 `power_stats_chart.dart`） | 各图表浮层各写各的定位，且都会撞 §3.1 的高度约束坑 |
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

半透明直接传就行：`_StrokePainter` 会把 `color.a` 整枚提到一层 `saveLayer` 上，笔画自己按不透明色画。
调用点**不要**再为"淡化"去拆每条笔画的 alpha——一枚图标是几条分离轮廓各画各的，交叉处会把 alpha 乘两遍，
读起来像图标自己叠出第二层颜色（`close`、图片上压斜杠这类最明显）。守这条的 test：
`半透明上色 自交叉处不叠色`。


---

### 9.2 v2 的组件分工（谁顶掉谁）与数据面约定

**卡片两族**：`GlassCard` 是**数据卡**的默认材质（概览、指标、图表、Hero）；
`AppCard` 保留给**实色面**（列表里的行卡、玻璃卡内嵌的分组块、设置页的密集条目）。
判据还是 §7.1 的密度：同屏可见元素多过 ~20 就往实色族走。两族共用
`radiusCard(16)` / `radiusPanel(20)` 两档圆角，**不要一页里厚薄混排**。

**小节标题合并成一族**：`SectionLabel`（带字距的 overline，§4 `overline` 档）与
`SectionHeader`（带操作区/副标题的区块头）各管一档，`OverlineLabel` 收进 `SectionLabel`。
现在三套并立是 §9 右列那串"约 12 份小节标题"还没清完的直接原因。

**徽标两族**：`StatusChip` 报**状态**（成功/警告/危险/信息，走 §2.5 五档语义）；
`Pill` 报**身份与方向**（涨/跌、计数、LIVE、被越过的档位，走 §2.9.2 方向档）。
两族都有 `filled`（实心底 + 恒白字，字色走 `s.onStatusBadge`）与水洗底（走 §2.5 的浓度档）两种；
**实心与半透明配对不同，别混**——这是历史上白字白底类缺陷的源头。

**数据面四条约定**（电量统计页验收时定下，全站时序类页面照此办）：

1. **时序图必须有跟随指针的浮层**，用 `ChartTooltip` + 不受高度约束的定位委托（§3.1）。
2. **浮层时间标签必须补齐到"哪天 + 周几 + 几点"**：后端只给短标签
   （`%H:%M` 或 `%m-%d`，见 `rust/power_stats/src/aggregator.rs::range_config`），
   前端拿桶上的 `timestamp`（**秒**）补成 `MM-dd 周X HH:mm`（时刻型把日期顶在前面）或
   `MM-dd 周X`（日期型往后挂）。时间戳为 0（桩数据）时**原样返回短标签**，不许编一个 1970 出来。
   现成实现：`psTooltipLabel()`，上收时改名 `formatBucketLabel()` 放进 `core/widgets/`。
3. **零值段不画**：整点级数据里"没用就是 0.00"是噪声，画出来会把有效柱压成一排矮桩；
   过滤发生在**绘图层**，不进统计口径（均值/峰值仍按原始桶算）。
4. **刷新只动新增的那一段**（§5.5 的 22），换范围整带重播一次（§5.5 的 23）。
   数值补间用 `MetricNumber`，值不变一律不起钟。

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
6. **渐变只有三处容身**：氛围层、图表填充、轨道与进度填充（§0.4、§2.9.3），且端点必须成对
   取自令牌，不许页面里 `colors: [x, y]` 现拼。**发光只由事件驱动**（§5.5 的 20），
   常驻装饰性 glow、外发光描边仍然禁止。按钮底 / 卡片底 / 输入底 / 图标底一律纯色。
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
14. **第 1 条的唯一例外是媒体层 chrome**（§2.7）：压在图片/视频/播放器上的白黑族
    （`s.onMedia*`、`s.mediaStage*`、`s.mediaScrim*`、`s.immersive*`）**故意不跟主题走**，
    收口在 `AppMediaChrome`/`AppTerminalPalette`/`AppReaderPaper`。判据是"这层颜色挂在
    什么底上"：挂内容图上→永远走 chrome 族，跟主题走会在浅色封面上直接消失；
    挂窗口底上→必须跟主题。终端语法色是**例外中的例外**：它压的是自己的深/浅底，
    按 `s.terminal` 成套取，不许逐色判主题。
15. **描边粗细走 `m.strokeUltraThin/strokeHairline/strokeThin/strokeRegular/strokeEmphasis/strokeBold`**
    （§3.3）：发丝线是**固定 1**，写成 `1.w`/`scaleW(1)` 会在高分屏上被缩成糊线。
    这六档是固定值、不吃 `scaleW`，别当"漏改的裸数字"收掉。
    四个入口都算：`Border.all(width:)`、`BorderSide(width:)`、`Divider(thickness:)`、
    `Paint()..strokeWidth` 与 `CircularProgressIndicator(strokeWidth:)`。
16. **收编字面色到令牌时必须字节等价**：只有精确对上命名档位才换 token，对不上就写算式
    （`s.onMedia.withAlpha(0x5C)`、`s.mediaStage.withValues(alpha: .35)`），
    **不许往邻近档上靠**。收编是治理，不是重新设计——规范化的同时改了渲染像素就算失败。
17. **动效族反过来：就是要它靠档**。时长、曲线、缩放、sigma、描边这些一档之差看不出来，
    留着 250/260/280/300/400 五种"差不多"才是问题；把 `Curves.easeOutCubic` 换成
    `decelerate`、`sigmaX: 8` 换成 `blurSoft` 是这套语言的落位，不是回归失败（映射见 §5.3）。
    代价必须**当场列出来报给用户**，并且出图的用例要跟着重跑基线。
    颜色不许靠、动效许靠，是同一枚硬币的两面：颜色错了是缺陷，节奏差了是风格。
18. **接口报错一律走 `AppToast` 或干净空态，禁止把异常原文铺在界面上**：`e.toString()` 带着
    FRB 前缀和 ` caused by: …` 链，用户读不下去，还会把正常内容整页盖掉。过一遍
    `MangaErrorText.describe()`：压成一句话、命中关键字表就翻成可行动的中文（"登录已过期，
    请重新登录"），没命中也只截到一行。**弹层（Dialog/Sheet）里走行内提示**——SnackBar 画在
    页面 Scaffold 上，会被整个弹层挡住；弹层内保留行内错误文案（同样过 `describe()`），
    整块列表的失败态用 `EmptyState(compact: true)` 承载，别自己铺一段红字。

**v2 新增（材质与数据面）**

19. **取色三个入口，不许第四个**：角色走 `s.`（`AppSemantic`）、材质走 `a.`（`AppAtmosphere`）、
    图表身份走 `AppViz`（§1、§2.6）。判据是"这块颜色在回答**用途**还是**材质**"；
    同一段颜色在两处各写一遍就是债（`ink`/`textPrimary` 必须同一档值）。
20. **氛围层只画一次**，画在外壳（§7.4）。页面自己叠一层 `DecoratedBox(gradient: …)` 当背景
    就是违规——试验页那一层是试验期特权，W0 上收后取消。
21. **玻璃预算**：同屏 `BackdropFilter` ≤ 8，移动端与窄窗一律 0（走 `alpha=255` 实色分支）；
    **不许玻璃叠玻璃**，玻璃卡内的小块用水洗档（`slotRest`/`chipRest`）。
    新增玻璃卡前先数实例，不要等出图掉帧才发现。
22. **动效只在数据变化时发生**：`didUpdateWidget` 先比值，相等就直接跟到新终值、不起钟；
    新数据只动末尾段；一次性动画播完静止，不循环不倒放（§5.1 第一原则）。
23. **字重上限 w700**，且只有徽标与展示数字能用那一档（§4）。在 Inter-ExtraBold 补进资产之前
    **禁止新增 `FontWeight.w800`**（现在拿不到实体字面，静默降 Bold）。
    口径：`grep -rn "FontWeight.w800" lib/ --include='*.dart'` 应当归零。
24. **带文字的浮层/弹层必须能逃出宿主高度**（§3.1 第三次发作）：定位委托返回
    `BoxConstraints(maxWidth: …)`，不要 `loosen()`、不要 `copyWith(maxHeight: null)`；
    并且**必须有一条 `fontScaleObs = 1.6` 的回归**断言 `takeException()` 为空。
25. **时序图的四条数据面约定**（浮层、日期+周几标签、零值段不画、尾巴动画）见 §9.2，
    新做图表页照抄电量统计页，不要再发明一遍。

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
flutter test test/power_stats_render_test.dart            # 新语言的样板页：11 条含动效与字阶回归
flutter test --update-goldens -t golden test/power_stats_render_test.dart        # 明暗/宽窄/悬停/重播 13 张
```

外壳的验收点是分开的两块：**侧栏**（`sidebar_*`）看 logo、指示条、行末箭头、子项连接线；
**顶栏标题格**（`shell_topbar_*`）看单级标题 / 面包屑各是哪张脸、上级叫法是否跟侧栏一致。
标题格那三张按 `find.byType(DesktopTopBar)` 截，但页面体是个空的 `SizedBox.expand`，
所以产物是整窗尺寸、内容只占顶上 60——看图只看那一条，别以为漏画了。

产物在 `test/goldens/`；改版前的对照基线在 `test/goldens/before/`，
左右拼图在 `test/goldens/compare/`。`test/failures/`（不匹配时 Flutter 吐的 diff 图）
是临时产物，不要提交。

八个必须知道的坑：

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
7. **字阶放大档必须进验收矩阵**：把用户的"界面字号"比例顶到 1.6 再跑一遍真实页面，
   每个浮层/悬停态后面补一条 `expect(tester.takeException(), isNull)`。
   只出 1.0 档的图等于没测——§3.1 那次 `overflowed by 4.9 pixels` 在 1.0 档是**完全看不见的**。
   写法：`AppTheme.fontScaleObs.value = 1.6;` + `addTearDown(() => AppTheme.fontScaleObs.value = 1.0);`
   （`fontScaleObs` 是全局 ValueNotifier，不复位会污染下一个用例）。
8. **时序类 golden 的数据不许拿 `DateTime.now()` 造**：桶的 `timestamp` 一旦跟着真实日期走，
   周几标签、日期标签就会**一周后全部错位**，基线自己变红且看不出是谁改坏的。
   固定基准（样板页用 `DateTime(2026, 10, 13)`，周二）再往后推小时；桩数据给 0 时
   标签函数必须原样返回短标签（§9.2 第 2 条）。

---

## 12. 动效实验室（隔离案例集）

`lib/pages/motion_lab/` 是一页 44 格的动效参考集：每格一个独立组件，照外部参考稿逐像素还原
尺寸/颜色/时长/曲线/关键帧。**它是只读参考，不是产品 UI**——§5.1 的禁令按 v2 收窄后在这里依然成立：
粒子爆炸、多次回弹、**常驻装饰性发光**、把渐变铺在控件底上，搬进真页面仍然是违规。
v2 新允许的只有两样：**事件驱动的一次性发光**（§5.5 的 20）和**三处容身的渐变**（§0.4）；
lab 里那些为"演示某种效果"而生的常驻 glow / 渐变底，属于实验道具，不进产品。

**v2 的样板页不是这三页 lab，是 `lib/pages/power_stats/`**（已验收的新语言整页实现）。
要看"这块面该长什么样、该怎么动"，先查样板页，再查 lab；lab 只回答"这种动效怎么做"。

同一套接线方式后来复用了两遍，长出了三页（`/motion-lab` 44 格、`/interaction-lab` 13 格、
`/surface-lab` 7 格）。**加一格或加一页照 `docs/ui_labs.md` §1 走**（目录骨架、本地令牌底座、
单向隔离墙、注册表、路由四落点、每格四道验收），三页全部组件的功能与样式台账也在
`docs/ui_labs.md` §2。本节只记坑：§12.1–12.6 是动效页，§12.7 交互页，§12.8 表面页。

### 12.1 结构

- `lab_kit.dart`：这一页自己的 token 层（`LabColor` / `LabFont` / `LabEase` / `LabSize` /
  `LabShadow` / `LabText` / `LabStage` / `LabCard` / `LabAnimateButton` / `LabIconButton` /
  `LabStageFooter` / `LabBlur` / `LabTween` / `LabIcon`）。
- `cases/case_NN_*.dart`：44 个文件，一格一个 class，互不引用。
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
16. **会"回头"的调制一律被读成倒播**：44 号声波连着错两版 —— 先做绕中轴的坐标胀缩（`sin²`：推出去
    还要收回来），再做音量包（高斯：长起来还要落下去），眼睛锁定的那一排腹中途换成前一排，看着就是
    倒放。方向感要靠**单调**：载波坐标取 `|u − 0.5| − speed·t`，`speed` 是每圈走的整数个周期，接缝上
    两帧重合，压根没有倒退那一段；"往两边开"的闸门只涨不落，收尾只降高度。验方向也别比两张静止帧——
    连拍的每列包络叠成时空图，条纹一路往外斜才是往外走（往内是反斜，来回是横纹）。
    推论：往这一类波上再加调制（随机峰高、包络起伏）时，**只许挂在载波坐标上**（跟着波一起走），
    一旦挂成时间，它就是第二路会回头的运动。
17. **`Wrap` 里的子项会铺满整幅**：`Center` / `Align`（`widthFactor` 为空）见着**有界**宽度就撑满，
    而 `Wrap` 给子项的正是有界约束 → 药丸一颗变整幅、多颗叠成一列。动效页那颗 `Animate` 早就是整幅宽，
    只是单颗看不出来；一排档位药丸要按内容收，得换 `Row`（给子项无界宽）。

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
flutter test -t golden test/motion_lab_all_cases_test.dart              # 132 张 = 44 格 × 静止/途中/终态
flutter test --update-goldens -t golden test/motion_lab_all_cases_test.dart
flutter test --update-goldens -t golden test/motion_lab_all_cases_test.dart --plain-name 'Confetti burst'  # 单格重出
```

- 触发方式按格子写死在 `_acts`：点按钮 / 点可点区 / 压悬停 / 什么都不做只推进时间。
  可点、可拖的元素靠 `cursor: click|grab` 的 `MouseRegion` 找，比猜坐标可靠（拖拽格是 `grab`）。
- **一帧一个 test**：出过图之后同一个 test 里的第二次点击就不再接到了。
- 途中帧默认 150ms；还在 delay 里的慢启动格、以及刚炸开挤成一团的格子，另写进 `_midOverride`。
- **只看静止帧证明不了动效存在**。审计口径：44 格的 idle / mid 两张取哈希比对，
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
- **`ColorFilter.matrix` 的平移列是 0..255，不是归一化**（9 号）：SVG `feColorMatrix` 的 alpha 行
  `0 0 0 24 -12` 直抄成 `-12` 时阈值掉到 α≈0.002，整层等于没滤——要写 `-12 * 255`。goo 的
  "两坨白互相吸过去"全靠这道 α 硬阈值，写错不会报错、只会安静地不拉丝。`IlGoo.ramp()` 是
  CSS `contrast()` 的式子，和这条不是一个形状，别复用。
- **goo 阈值两边各吃掉约 1px**（9 号）：36 的格子量到 35、7 的缝量到 8，全白包围盒因此是 164
  列。反过来这也是一条实证：静止态 7px 的缝在 σ=3 之后**仍然透**（缝里读到舞台底 237），
  靠近到 6px 以内才糊起来——所以"四段 + 三段 237"就是 goo 没在静止态偷偷合并的证据。
- **CSS 的 `animation-fill-mode: both` 压过作者声明**（9 号）：入场动画跑完之后
  `opacity:1 / transform:none` 永久钉住那一层，内联的 `opacity: 1-a` 根本吃不到，作者只能改走
  独立的 `translate` 属性。落到手感上就是**判错时数字只往下掉 8px、不淡出**，到 960ms 才随整串
  清空一起没。照抄成"掉下去顺便淡出"就丢了这层味道—— golden 也看不出来，只有逐帧读 opacity 才抓得住。
- **钳位要分家：位置读钳过的、宽高读没钳的**（9 号）：融合进度 `k = m.clamp(0,1)` 管 X 和圆角，
  而胶囊宽高吃的是未截断的 `m-1`（还带 `max(-.12, …)` 的下限）。于是到位前先"窄一点、高一点"、
  再冲过头变"宽一点、扁一点"、最后落回。两张 golden 一边一张：`c09_tall` 整块白区竖高 46 > 44，
  `c09_overshoot` 最长游程 144 > 128。全用 `k` 的话这一拍直接被削平。
- **形变中的块要取"整带最长游程"，不是某一行**（9 号）：中线被 19 号数字切成十几段、
  圆角又在吃宽度（r=22 的胶囊在顶边下 8px 处只剩 118）。定三条：静止态走中线，
  格子里有数字走顶边+10（数字顶在 +12.5、弧只吃 0.17px），融合途中取整带最长的一段。
  圆角一律用"弧上几行左端点 vs `base + r − √(r²−(r−dy)²)`"对表，9 号用这条同时验掉 12 和 22。
- **墙钟驱动的波在一个窗口里只够扫到一格**（9 号）：900ms 的呼吸波扫完整行，每格被压的窗口只有
  2 格宽，而 check 只持续 420ms。所以"四格一起呼吸"是错的，逐帧断言只能要求"最短那颗 ≤.93、
  最长那颗 ==1"。
- **所有延迟挂组件自己的 Ticker 累计钟，别用 `Timer`**（9 号）：`_now += dt` 一套（填满 420ms
  才出结论、抖动 960ms 才清空、右→左每格晚 45ms）在 test 收尾时还挂着 `Timer` 就直接报
  "Timer is still pending"，而假时钟推进行为也只认 pump 的时长。
- **`sendKeyEvent` 不等帧**（9 号）：按键回调里只 `setState`，紧跟的 `find.byKey` 读到的是**上一棵**
  树——表现为"敲了三位只量到两颗"。一次性探针脚本里每字都 pump 一帧就看不出来，合进 helper 就炸。
  所有敲键盘之后补一帧。同理，出图 helper 的"字符间隔"只能加在两位**之间**：加在末位后面
  等于把末位的 300ms 入场等完，`c09_entry` 第一次拍到的就是两颗都已经落定的数字。
- **goo 的拉丝窗口只有 3.66px 宽，所以"接上了"要两行一起量才算数**（9 号）：σ=3 配
  `24α−12` 那道硬阈值，两格中点的 α = `erfc(g/(2σ√2))` 要留到 (1+12)/24 = .542 才算实心，
  反解就是缝 `g ≤ 3.66px`。静止态 g=7 接不上（缝里读舞台底 237），起手那一帧 g=3 直边接上；
  但**圆角 12 在顶边下 6 行处又把缝撑到 6.1px**，那一行仍然是 4 段。只看中线连着 = 什么都
  没证明（四格叠上之后也连着），"直边连着 + 弧还开着"这一对读数才把 goo 单独钉出来。
- **整步采样会把弹簧的中间态整个跨过去**（9 号）：那条离散弹簧一步就从 dx 40.5 跳到 36.3，
  "缝还在（36 > dx < 39.66）"那一帧在 16ms 整步下**根本采不到**——逐帧断言于是恒假。
  改成 8ms 半步推就落在窗口里；出图那边正好相反，`shootIlCase` 末段按余数收尾
  （408 = 25×16 + 8），那半步恰好把画面停在拉丝窗口内，所以 `thenMs` 要挑带余数的数。
- **`thenMs` 是从交互结束算的，不是从组件的钟算的**（9 号）：这一格的结论拍本身压着 420ms
  延迟，加上 helper 的 48ms 铺垫，`thenMs: 64/300` 两张拍到的都还是 check 期的呼吸帧——
  图看着"动到了"（一格被压扁），其实融合一秒都没开始。定帧先算 `thenMs − 铺垫 − 组件延迟`。
- **`clip-path` 不改布局，但改命中**（10 号）：`inset(0 0 54 round 20)` 只是把底下 54px 藏掉，
  盒子占位仍 224 → 量 CTA 要用**布局底边**（顶+224−1），拿白区包围盒当底边量到的是裁口。
  反过来 `RenderClipPath.hitTest` 和浏览器一样把裁掉的区域挡在命中之外，所以收起态的 CTA
  是"真点不到"，不是 `Opacity(0)` 那种还在吃指针的假收起——这一条值得单独断言一次。
- **flex gap 的条数是"子元素数 − 1"**（10 号）：3 行 + CTA = 4 个子元素 → 3 条 4px，CTA 另带
  `margin-top:10`，盒高 224。按 `rows+1` 算成 4 条就多 4px，而 `Column` 只发 3 条 →
  外层 `SizedBox` 的固定高把这 4px 吃成底部空隙，**golden 完全看不出来**，只有量包围盒才抓到。
- **共一根弹簧的三条派生量，逐帧断言要按"钳过之后"的读数写**（10 号）：`useTransform` 把输入夹在
  [0,54]，弹簧尾部十几帧在零以下，从 CTA 的 y 反推 p 只数得出 22 个不同值。阈值按这个写，
  不然 FAIL 的是断言不是动效。
- **alpha 硬阈值在直边上外扩、在圆盘上不放大**（10 号）：`16a−6.17`（α≥0.386）配 σ=4，
  直边该外扩 1.4px/边；但 R=9.5 只有 2.4σ，曲率把边缘的 alpha 峰压回 0.5 以下 → golden 量回来
  **正好是盒子原尺寸 19**。别拿直边的算法给圆盘写断言，拉丝只在两块挨近时才看得见（9 号那条）。
- **`color-mix` 的近似 hex 会骗人**（10 号）：采集表里写 `#b4b5b7`，实际
  `255 − 0.26·232 = 194.7` → golden 芯色 `(195,195,195)`。照表的写 180±4 永远 FAIL，
  一律按 `color-mix` 的式子重算再定容差。
- **亚像素描边量不出"画到几成"，量最右列**（10 号）：勾宽 1.75·(19/24) = 1.38px，画到一半和
  画满的"盘心被画白像素数"是 13 vs 14，分不开；勾是从左往右画的，改成"被画白的最右一列"
  就量到 314（拐点 314.6 之前）→ 319（终点 318.4）。
- **出图铺垫自带 ~48ms，`thenMs` 要扣掉它**（10 号）：`shootIlCase` 在 `act` 之后先推两帧 16ms
  再走 `thenMs`，所以"勾刚画了个零头"那拍得写 40（总 ≈88ms，60ms delay 刚过），写 96 拍到的是
  已经画满的勾。按压弹簧同理：`{500,30}` 的收敛判据 2e-4 要 ~320ms 才真钉在 .975，
  `thenMs:48` 读到的是 0.981 —— 量"压下去多少"的帧按弹簧的**走完时间**等，不是按动作名等。
- **`Positioned.left` 和 `getRect` 不在一个坐标系**（11 号）：前者相对所在 `Stack`，后者是窗口
  绝对坐标。这一格两者相减就是"缝"，直接混算会把 goo 层那 69 的滤镜留白和舞台那 26 的偏移
  一起吃进来 —— 静止态读成 −21 而不是 −40，**而且错得很稳定**，五条断言一起挂。缝一律写成
  `go-pos.left − slab-bar.width`（同一个组件栈内）。
- **按 dt 累计的补间，`sendKeyEvent` 推不动**（11 号）：§12.4.3 那条对表帧在值到值补间上是双份的
  —— 按键只发零时长帧，`_tick` 里 `e - _last` 恒为 0，所以敲完一个字符连 pump 五六帧，
  底色读数还是 0.0。中途值一律先 `_pump(64)` 再断言；要钉"多长走完"就按 8ms 半步记序列、
  取**最后一次还在变**的那一拍（150/160/340/340/520，容差 ±24）。
- **`keyLabel` 的字母永远是大写**（11 号）：它是**键名**，不含 Shift / 输入法；真实字符在
  `KeyEvent.character`。只读 `keyLabel` 会安静地把 "Ask anything..." 敲成 "ASK ANYTHING"，
  golden 里差别只是几个字母的高度。另外别只喂合成的 `PhysicalKeyboardKey(n)` ——
  模拟器要查 scanCode 表，查不到直接 assert，用 `character:` 才走得通。
- **goo 的等值线在横边上外扩得最凶**（11 号）：`22α − 8.67` 把阈值设在 α=0.394（低于 0.5），
  半平面那条等值线落在几何边**外** 0.27px；沿水平扫描线读数还要再除以法线的水平分量，
  于是弧顶/弧底几行多带 2~3px、上下横边各多 1px，只有竖直边正好（50/323 分毫不差）。
  容差按 `1.2 + 0.5/|n_x|` 给，别一律写 1.5。
- **`cubic-bezier(.22,1.3,.71,1)` 起手极陡，`thenMs:16` 拍的已经不是静止态**（11 号）：
  算上铺垫约 40ms 时 p≈0.36、缝 = 48p−40 = −22，钮已经从条的右缘探头到 336（到位档 369）。
  想拍"只有透明度在交叉"就得接受位移先走 —— 这一帧的价值是**两条时长差 3~4 倍**这件事本身。
- **深色底上的白描边在 1x 屏没有满白列**（11 号）：20px 图标里 1.67px 的竖笔读回两列 217/216，
  纯白只剩人字尖那 12 个像素 —— 按"≥250 计数"断言箭头存在，永远像是没画。改成
  ≥200 计数 + 竖笔连续行数 + 左右质心对称三条一起钉。同理，`ink` 掩码整幅搜会把 'hi'
  两个字母算进圆盘包围盒（46 → 66），量圆盘必须从条右缘之外开始搜。
- **一个 `step` 里合几条补间，`||` 会把后面那条整个饿死**（12 号）：`_OpFx.step` 写成
  `hov.step(dt) || prs.step(dt)`，于是 hover 还活着的那 160ms 里**按压缩放一帧都不走** ——
  悬停着按住钮，读数停在 0.982（只走了 8ms）而不是 0.9。不报错、不抛异常，golden 也只在
  "边悬边按"这一档才露馅。同一函数里并列的多路时间线一律用 `|`。
- **`sin(π)` 在 Dart 里是 1.2e-16，不是 0**（12 号）：`sin(πr)` 这条包络要担的正是
  "两端严格为 0 → 连点两次一定落回原样"，结果 `rotDeg` 收尾读回 1.1e-15，一条 `== 0`
  的断言永远挂。改成 `_env(r) => (r<=0 || r>=1) ? 0 : sin(πr)`，把"归位"从浮点余量里
  拿回来。测试要复现同一条式子，不然恒等式对不上。
- **带 `Transform` 的祖先会让 `getRect` 整体缩水**（12 号）：盒子外面压了一层落位回弹
  （最低 .965），`getRect` 连它一起算 → 260×98 量成 250×94。所以"形状走了几成"这类读数
  一律取**布局参数**（`SizedBox.height` / `Positioned.left/width`），只有确认 scale=1 的档
  才用 rect；用 rect 时还要减掉盒左上角换算回组件坐标系，否则圆心 (206,30) 读成 (286,162)。
- **回弹吃线性读数，不吃主进度**（12 号）：收回方向 `v = (1-p)⁴` 已经掉到 .18，而包络的
  `y = 1-p` 正走到峰值附近 → 实测量表 scale 0.965。拿 `v` 去反推回弹会算出 0.979，
  差的那 1.4% 看着像"渲染错了"，其实是两条读数被搞混。
- **`tester.tap` 之后不推帧**（12 号）：`onTap` 里只 `setState`，紧跟的读数还是上一棵树 ——
  Next 归零那条量回 3.36（3 秒的进度）而不是 0。和 §12.4 的 `sendKeyEvent` 是同一个坑的两张脸。
- **半步扫的帧数要按 tween 时长给足**（12 号）：300ms 的形变只推 30 个 8ms 半步（240ms），
  `rs.last` 停在 0.047，看着像"落不到位"，其实是钟没走完。凡"两端精确归位"的断言先算
  `帧数 ≥ 时长 / 步长 + 1`（对表帧那一拍不计时）。
- **`fill` 和 `stroke` 同色会把字形四边各外扩半个描边**（12 号）：lucide 那两条四边形
  本来是 4/4/4（条宽/间隙/条宽），叠上 `stroke:2` 之后读回 6/2/6 —— 按 12/24·size 写期望
  永远短 1.5px。浏览器里同一件事，所以这不是偏差而是原稿味道，量之前先把它折进式子。
- **程序画封面时，模糊半径要跟着边长乘**（12 号）：`background-size:cover` 落在正方形上
  等价于按 0..1 归一画，所以封套必须整张随边长缩放；`MaskFilter.blur` 给死 px 的话
  40 档糊成一团、64 档又太锐，两档看到的不是同一张图。同理 `RadialGradient.createShader`
  要按光晕自己的 `Rect.fromCircle` 建，用整张画布的盒会把圆心挪到画面正中。
- **外环和轨道是叠在舞台底上的，不是叠在白盒上**（12 号）：`box-shadow:0 0 0 1px` 那圈
  `pane-edge`(α=.078) 合成在舞台 237 上是 **220**，按"白底 255 起步"算成 237 就一条都过不了。
  先量一块实底舞台色再合成，是这一格唯一稳的取色办法。
- **`RenderMouseRegion.hitTest` 只认自己那一格框**（13 号）：参考稿的扇出区是一组
  `position:absolute` 的圆点，飘在卡片盒外也能悬停；Flutter 里 `MouseRegion` 的命中先过
  `size.contains(自己的盒)`，**盒外的后代永远收不到指针**。做法是把悬停盒开成"卡片 ∪ reach"
  的并集框，再配一条几何谓词（`Path` 命中）把并集里那块不属于 reach 的空角剔掉。
- **并集框会顶出 Stack，而 Flutter 没有负 margin**（13 号）：多出来的那截只能
  `Padding(top: overY)` 往下垫、外面再 `Transform.translate(+overX/2, −overY/2)` 把画面拉回
  舞台正中。代价是同一份 `fanAt` 有了两套坐标系（Stack 坐标 vs 悬停盒坐标），差值正好是
  `overY` —— 平移量漏加这一截，扇出就整体下沉 2px，而且只在展开态看得见。
- **`Transform.scale` 的 `origin` 会和默认 `alignment: center` 相加**（13 号）：
  `_effectiveTransform` 的支点是 `origin + alignment.alongSize(size)`，36 的盒再给
  `origin:(18,18)` 就把支点推到右下角 (36,36)，1.12 倍时圆心偏 −2.16 = −(s−1)·18。
  **默认那档已经是盒中心，别叠 origin**。测试读矩阵标量看不出偏移，只有量像素才露馅。
- **带 scale 的盒子不能用 `getRect` 定圆心**（13 号）：`getRect` 给的是"变换后的左上 +
  未变换的宽高"，量出来的中心是假的。圆心一律从 `Positioned.left/top` 加半格、再叠
  `Transform` 矩阵里那一格缩放自己算。
- **锚点要抗"抬起"**（13 号）：卡片悬停时整块抬 1px，拿 `getRect(_card).top` 反推扇出原点
  就会在展开态少 1px。锚点改从 `IlStage` 的中心推（舞台不参与位移），抬起那一档另开一条
  断言单独钉"就是 1px"。
- **暗色舞台要写"已经叠完"的不透明值**（13 号）：参考稿是 `rgba(ink,.06)` 压在 `--bg` 上，
  而 golden 只拍舞台那一块、底下没有页面底，留半透明色就拍成一层白。浅色那档不用换 ——
  它压的是纯白，叠完和直接画一样。
- **行盒会被摊成整像素，0.75px 的差是引擎的**（13 号）：`fontSize 13.5 × height 1.5 = 20.25`
  三行落回 60.0 而不是 60.75，`strutStyle(forceStrutHeight: true)` 走的是同一条路。
  整张卡因此是 179.0 而参考稿 179.75 —— **别拿 `SizedBox` 去补**，补了换一行文案就露馅。
- **帧模式弹簧吃不得大步 `pump`**（13 号）：`tester.pump(900ms)` 只出**一帧**，弹簧把 dt 钳到
  2.5，整条时间线在这一拍里走完 → 悬停放大读到 0.833 而不是 1.0。测试里一律按 ≤16ms 步进推，
  `shootIlCase` 也是这么算的，所以 golden 标称的"96ms"实际墙钟是 96 + 两帧铺垫。

### 12.8 表面实验室：形状自己长过去的那几格

第三块参考页（`/surface-lab`，`lib/pages/surface_lab/`，9 格）。底座、注册表、路由和
§12.7 同构（`kit.dart` 的 `Sv*`、`cases/surface_lab_cases.dart`、`test/helpers/sv_golden.dart`），
同样不读也不写全局主题、尺寸写字面 px。这一页的主题是**同一块表面在两种形状之间长过去**
（按钮 ⇄ 面板、条 ⇄ 卡片），所以描边、圆角、命中区这些"表面属性"会全程处在变化中 ——
坑几乎都出在这里。

- **`DecoratedBox` 的描边只画不让**（1 号）：`RenderDecoratedBox` 就是一层 `RenderProxyBox`，
  子节点拿到的约束和外框**同一份**，`BoxDecoration` 在这个 SDK 里根本没有 `getInsets`。
  CSS 的 border-box 里那 1px 边框是把内容盒往里顶一格的，所以照着参考稿摆 padding 会整体
  偏高 1px（这里表现为 Label 顶边 +8 量成 +7）。做法：外层 `Padding(EdgeInsets.all(1))`
  把这一格钉进布局，自适应宽度的框再补 `+2`（左右各一条边）。
- **`Listener` 默认 `deferToChild`，点空白关不掉面板**（1 号）：`onPointerDown` 挂在铺满舞台的
  `Listener` 上想做"点外面就收起"，可命中测试先要子节点认领 —— 光标落在面板和按钮之外的
  透明区时事件根本不到这一层。这类"兜底命中"必须显式 `behavior: HitTestBehavior.opaque`。
- **`late final Ticker = createTicker(...)` 是一颗雷**（1 号）：没人碰过它，`dispose()` 里读一次
  就是在"树已经拆完"的时刻去查祖先（`TickerMode` 内部要的 notifier），直接抛
  *Looking up a deactivated widget's ancestor is unsafe*，还会顺着泄漏的 `ScreenUtilInit`
  metrics observer 把**后面所有** test 一起带崩。凡 `late final` 的 ticker / controller 一律在
  `initState()` 里建。
- **`onTapDown` 不是 mousedown**（1 号）：手势竞技场要到松手才判胜负，`onTapDown` 于是也拖到
  松手才响；参考稿的 `active:` 是按下即缩。按下档只能挂裸 `Listener(onPointerDown:)`，
  外加 `onPointerUp` / `onPointerCancel` 两个复位口。
- **拍完就拆树的 helper 碰不得"按住"这一帧**（1 号）：`shootSvCase` 出图后立刻 unmount，
  而指针还按着 —— 之后松手，`PointerUp` 会沿**按下时**那条命中路径送到已 dispose 的
  `RenderPointerListener`，报 `setState() called after dispose()`。按住态的 golden 要自己
  mount → 补帧 → `matchesGoldenFile` → `svDrop` → unmount，按这个顺序写。
- **`getMaxScaleOnAxis()` 量不出 `Transform.scale(.98)`**（1 号）：它取的是三轴最大值，而
  z 轴恒为 1，于是永远回 1.0。要读矩阵标量就拿 `transform.entry(0, 0)`。
- **1px 头发丝骑在两个像素上会被摊平**（1 号）：光标按"文字推进宽度"定位，落点是亚像素，
  出图读回来是两根 50% 的灰列，按 1px×17 断言永远挂。把落点 `.roundToDouble()`（最多偏半格），
  树那一侧的断言则放宽到 `caret.left − note.right ∈ [0,1]` —— 亚像素这件事本来就不该钉死。
- **弹簧的 `rest` 是位置阈值（px），不是比例**（1 号）：用 0→1 进度驱动就等于把收口设成行程的
  0.02%，行程 164px 时进度弹簧提前两百多毫秒就"落定"，末端看起来是硬切。改成直接喂高度像素，
  再拿假时钟（4ms 子步）扫参数定档：参考稿 `{type:'spring', bounce:.05, duration:.3}` 读成
  ζ = 1−bounce = .95，阻尼比一定就只剩刚度可调，S=1500 / D=73.5 在 0.02px 收口下落定 304ms。
  顺手记一条：离散积分比解析包络（`2.0225·A·e^{-(ζ-√(ζ²-1))ωt} − 1.0225·A·e^{-(ζ+√…)`）
  先落定，别拿包络的数当实测。
- **`sendKeyEvent` 的 logicalKey 只认小写码位**（1 号）：喂 `'H'`(0x48) 撞
  *not found in android keyCode map* 断言。键位换成 `rune + 0x20`、`character` 仍给原字符，
  大写就打进去了。
- **半透明描边的颜色是底的函数**（1 号）：`rgba(9,9,11,.1)` 压在白面板上是 230，压在
  `#F4F4F5` 的 hover 底上是 221 —— 同一条边框在两帧里不是一个色，按固定色掩码找盒会直接找不到。
  而且量 hover 填充时容差必须是 0：描边外圈与面板交界的混合灰能落到 242，tol 给到 2 就把 AA
  一起圈进来，64px 的盒量成"没缩"。这一格真正稳的量法是量**底色整块** + 比对两帧的
  **中心是否没跑**（缩放绕中心，跑没跑比 1px 的宽度差有说服力）。
- **两张出图的舞台不在同一格**（1 号）：golden 拍的是整块格子，格高不同 → 舞台左上角在
  画布里的 y 就不同（这里 47 vs 55）。跨帧比任何读数之前，一律先减掉各自的舞台原点。
- **圆角只能多行拟合**（1 号）：逐行反解"白从哪一列开始"，单行会被 AA 带偏整格（8 和 12
  都能拟出 12 的假解）；对 `1 + ri − √(ri² − (ri−(y−1))²)`（ri = r−1，1 是描边让的那格）
  做 5 行最小二乘才顶得住。中途帧的圆角只断言"在两档之间"，具体档留给出图眼睛。
- **共享元素的行程要写在**屏幕**坐标里**（2 号）：那行字是从按钮飞到面板，可它此刻住在还在
  `.9 → 1` 缩放的表面里 —— 直接把"目标减起点"当局部偏移，字会被父级缩放一起带跑（起跳那一帧
  屏幕落点量到 29.6，参考稿是 16）。正确写法是先算屏幕落点，再除以**此刻**的倍率换算回局部：
  `local = (screen − 面板原点) / scale − 静态内边距`。落定帧再拿"横移为 0、纵移恰好 45"验收。
- **CSS 的 `gap` 在 Flutter 里要显式补一格**（2 号）：`grid-cols-3 gap-2` 是三条 68.67 的轨道
  **之间**再夹 8，只把轨道宽度写对等于把 8 吞掉 —— 圆点间距从 76.67 缩成 68.67，出图上第二、
  三列各左移 8、16。`Expanded`/`flex` 都补不出来，只能 `...[SizedBox(_track), if (c < 2) SizedBox(_colGap)]`
  手动夹，且 gap 只在两列之间（首尾不留）。
- **淡入和位移共用一条进度时，可以互相验算**（2 号）：参考稿的 `{opacity:0, y:10}` 是两个通道
  读同一个 spring。出图上拿圆心色反解 α = (255 − g)/168，树上拿圆心得知下挪 off，断
  `α == 1 − off/10` 就能钉死"是不是同一条弹簧"，比各自给容差强得多。
- **中途帧的断言要写成"时序无关"式**（2 号）：弹簧走过的路程和 `pump` 的时长不是一回事（假时钟
  每帧还先跑一次 tick），写死"pump 32ms 后顶边在 61.6"必然挂。正确做法是**从测到的位置反解进度**
  （`u = 顶边 − 53`，`p = 1 − u/10`），再验宽高等于同一个倍率 `254·(0.9+0.1p)`、横移恒为 0。
- **`aim()` 不建帧，`pump(Duration.zero)` 不走钟**（2 号）：`aim()` 只把树标脏，紧接着读新挂载的
  面板就是 *Found 0 widgets* —— 中间必须 `pump()` 一帧。反过来 `pump(Duration.zero)` 假时钟没动，
  ticker 首个回调 `dt=0`，值门控的那一层（这里是 `4p > 0.01` 的模糊层）此刻**本来就不该存在**，
  断 `findsOneWidget` 会挂。先断"没有"，再 `run(t, 48)` 断"有"。
- **模糊量有多大，树里读不出来**（2 号）：`ImageFilter` 的 σ 是私有字段。能断的只有挂载时机和
  `getRect(blurKey) == getRect(SvStage)`（铺满才对得上 `backdrop-blur`），糊没糊只能给出图：
  同一条 1px 描边，静止版压到 220，模糊版最暗只到 242。
- **`Opacity` 是祖先还是子孙要看树**（2 号）：`find.ancestor(of: 按钮, matching: Opacity)` 最近优先
  且可能好几层，要 `widgetList(...).first`；而按钮的淡入层其实包在它**自己内部**（`Opacity` 是
  `btnKey` 的子孙），这条查询根本找不到，得另写一个 `find.descendant` 版本。
- **常量表达式的两处硬限制**（2 号）：`const` 列表里不能有 `for` 元素（六把 key 写成
  `static ValueKey<String> swatchKey(int i)`），`const` 里也不能取 `Offset.dx`（测试里那个
  `Offset(origin.dx, panelTop)` 只能去 `const`）。
- **收起态别拿绝对坐标断言**（2 号）：面板还在退场 transform 里，正文/页脚的屏幕位置一定在动。
  要断的是它们**自身** opacity 仍是 1（收起没有 exit 档，跟着母体淡掉就对了）、面板 opacity < 1、
  字飞回按钮，以及落定后面板拆掉、按钮淡层回到 1。
- **像素复核自己的三条掩膜坑**（2 号）：① 舞台 `#F5F5F5` 和 `bg-secondary #F4F4F5` 只差 1，
  容差给 1 就把整块舞台认成按钮；② 彩度掩膜必须 `max−min`，拿 `R − min` 的话 `(51,255,87)`
  这种 R 就是最小值的色块一律得 0，绿蓝两颗直接消失；③ 行距 56、圆点 48，纵向窗口留 ±14 会把
  邻行圈进来（48 量成 62），只能收在 ±4，需要容错时改量**中心**而不是上缘。
- **没声明 `MotionConfig` 的 `layoutId` 吃的是布局动画默认弹簧**（3 号）：`{stiffness:300,
  damping:30, mass:1}` → ζ=.866，156px 行程 608ms 落定、过冲 0.43%（0.67px）。它和这一页别格用的
  `{bounce,duration}` 档不是一个东西，形变那一轴必须单独按这档复刻，"顺手统一"就等于换了一条曲线。
- **形变只钉左上角，宽和高共用一条进度**（3 号）：框是 `LTWH(4, 24, 按钮宽 + (364−按钮宽)·p, 高度)`，
  `p` 只有一个。中途帧的复核就落在这一点上：从"非白外沿"反解宽和高，`(w−91)/273` 与 `(h−36)/156`
  必须咬得上（实测差 0.005）。另外形变途中框的右/下沿落在半格上，AA 把 245 摊成一片糊，
  这时候只能认"非白"再往里收 1（紧贴面板那圈环影压出来也是非白）。
- **内容是按终态排版的，框只是在外面裁**（3 号）：`OverflowBox(364×192)` 里排好整张卡，
  `ClipRRect` 跟着进度缩 —— 于是页脚那条虚线在盒子长到一半时就出现在**最终**那一行（stage y156），
  不是跟着下沿往下走。参考稿的 layoutId 就是这个语义，做成"内容跟着长"反而错。
- **`z-index` 挂在 static 元素上是空操作**（3 号）：Label 是绝对定位、白卡没有自建层叠上下文，
  所以 Label 真的画在卡**上面**；加上它只在 success 那一档才透明
  （`data-[success]:text-transparent`），打字时正文和 Label 叠在同一行是参考稿的原样行为。
  出图上表现为同一片墨里混着 10 和 115 两档 —— 别当缺陷"顺手修"。
- **`overflow:hidden` 把骑在边框上的把手裁掉半截**（3 号）：`-top-[5px]` 的 12×26 探出面板上沿那
  5px 在浏览器里就没有。复核要断两件事：面板上沿以上只剩环影那一档（235，不是墨），
  面板以内那半截有墨。成功页整只把手跟着摘掉。
- **inset box-shadow 没有等价物，页脚也没有 flex-grow**（3 号）：`0 0 0 1px rgba(0,0,0,.08)` 的内
  环只能用一档灰描边近似。而 textarea 128 + 页脚 48 = 176 < 卡内容 182 —— 参考稿没给页脚
  `flex-grow`，那 6px 死带就这么空在页脚**下面**，于是"盒子底边减页脚底边"量出来是 11
  （6 空 + 1 描边让的 + 4 灰框），按 6 断言必挂。
- **两块表面吃同一条进度，就能互相验算**（3 号）：换脸那一档的 q 有两条独立读出 —— 卡心从白走到
  `--muted`：`(255−v)/10`；成功页那圈蓝淡进来：`(245−R)/(245−32)`。两条曲线在出图上给 0.90 / 0.94，
  差值落在容差里就说明"确实是同一条弹簧"。比各自给一档容差强得多。
- **过冲的弹簧不能断"单调"**（3 号）：形变峰值实测 192.274（多过 0.27px），"高度一路上去不回落"
  这种断言必挂。改成断**峰值 ∈ [192, 192.8]** 加"峰值以前不减"。
- **从成功页收起时不要把表单翻回来**（3 号）：参考稿只给 success 写了 enter 档，没有 exit。
  所以关闭时得记住"这一刻是哪一张"（`_fromSuccess`）并把换脸进度冻住，否则收起那一帧会闪回白卡。
- **1px 虚线和环影撞在同一档灰上**（3 号）：`M0 1H352` + `strokeDasharray="4 4"` 的一根线跨两行各吃
  一半（242 那档，两行必须成对相同），而面板那圈 1px 环影压出来正好也是 245 == `--muted` ——
  整图找 245 会把框撑大 1px。框只能走"中间行/中间列的连续段"。虚线窗口要精确切在 stage x 17..357：
  多 1 格就混进 3px 的假段，少 1 格就丢掉最后一段；43 段而不是 44，因为两头各被缺口盖掉一段。
- **自带 `--muted` 的组件要换白舞台**（3 号）：`SvStage` 的默认底就比页面浅一档，格子再自带一圈
  灰就完全看不出框。给 `kit.dart` 的 `SvStage` 开了 `color` 覆盖，这一格铺白。顺带两条 SDK 硬限制：
  `KeyEvent` 没有修饰键 getter（拿 `HardwareKeyboard.instance.isMetaPressed`），`Column` 没有
  `clipBehavior` 参数。
- **15fps 节流不能拿单拍取整**（4 号）：`_onTick` 里若写 `tick = dt.inMs ~/ frameMs`，真机 60fps
  每拍只有 16.7ms，`floor` 永远是 0 —— 时钟从头到尾不动，测试却照样"通过"（它也只 pump 16ms）。
  余数必须留在累加器里：`_rawMs += dt`，拍号取 `_rawMs / frameMs`。这条只在真机暴露，出图环境
  每拍 30ms 反而看不出来。
- **圆角矩形 SDF 不能按"直边段/圆角段"分支写**（4 号）：直边段里另一个分量是负的，直接取模长
  会把距离算大，于是整段弧上的环带被判成"盒子外"漏画 —— 只有四个角对、四条直边全错。必须用
  标准式 `sqrt(ox²+oy²) + min(max(qx,qy), 0) - r`。
- **着色器里有三套 uv，混用就全跑偏**（4 号）：条纹场吃 `objectUV`（除以短边）、遮罩吃各自边长
  归一的 `responsiveUV`、`edge` 又用另一组。参考稿的 y 是**正向朝下**的（`uv.y = 1 - uv.y` 之后
  又翻回来），照直觉写朝上会让条纹在圆钮上反着走。`fwidth` 是 `|dFdx| + |dFdy|`，不是单项 ×2。
- **参考稿的糊光表是它自己 SVG 的用户单位**（4 号）：那四档 `(26.4, 8.4) (15.6, 4.8) …` 照搬成
  px，压在 40 高的胶囊上就是一条横穿预览块的白带。按短边等比缩（`min(w,h)/100 × 0.4`）之后才
  是"贴着环走的小火花"；同表里那颗 extra 火花本来就是 px 量级，不能一起缩。
- **糊光的外扩量得自己裁，不能指望 blur 收敛**（4 号）：同一套档位，离屏 Skia 逐相位扫 90 拍
  （1× 和 4× 倍率都扫）盒外 3px 以后墨量为 0；真机放大视图量到右缘外 12~15 逻辑 px 还有光，
  浅色行压暗 31~34、暗底提到 97~103，而上下方向始终 0（光点那一拍只在右端头上）。也就是
  `MaskFilter.blur` 的实际扩散随渲染器和缩放倍率变，档位表算出来的 6px 只是下限。改成把光环
  裁到"盒子外扩 ≤4px"（`haloSpread`，取各档 半线宽+2σ 的最大值再钉绝对上限）：裁剪只往框外扩，
  框内画层一点不动，所以 8 张 golden 里 7 张字节不变。缝宽 12，两侧各 4 才留得住干净的一条。
- **`Transform.scale` 的读数在 `entry(0,0)`**（4 号）：它铺的是对角矩阵、z 轴恒为 1，所以
  `getMaxScaleOnAxis()` 永远读到 1.0；`WidgetTester` 也没有 `getTransform`，只能
  `find.descendant` 拿 `Transform` 自己读。
- **Row 居中对齐会让"同一基线"差 4px**（4 号）：40 的胶囊和 32 的圆钮并排，比 `top` 必错，
  要比 `center.dy`。同理胶囊整行居中时，断言右缘留白要用"行中点对齐舞台中点"而不是行宽。
- **复核冻结帧时，裁剪框别盖住按钮自己的字形**（4 号）：暂停键会翻成播放三角，idle 与 paused
  在整行上有 67 个像素不同 —— 那全是它。金属面冻没冻住要单独裁胶囊那 145×50 比字节。
- **减弱动效没有现成的 tester 开关**（4 号）：这版 SDK 只暴露 `accessibilityFeaturesTestValue`
  （单数），断言"从头就没有一拍"得自己套一层 `MediaQuery(disableAnimations: true)`。
- **5 号岛里的内容按**该档终态**排版，中途只让黑盒子裁**（5 号）：宽/高/圆角是三条独立弹簧，
  走到一半 `Column` 拿到 311×140 的约束而内容要 168 —— 直接抛 RenderFlex overflow，整格出图
  全废。参考稿靠 DOM 每帧重排、途中 `clipPath:none` 落定才套 squircle，我们没有重排这一步，
  只能把每一面钉死在 `w-2 × h-2` 的 `OverflowBox` 上（3 号那条同因，区别是这里约束每帧都在变）。
  落定那一帧两种做法一模一样。
- **只有 `Positioned` 孩子的 `Stack` 会缩成 0×0**（5 号）：compact 那挡的图标和文字全绝对定位，
  `Stack` 拿不到任何 intrinsic 尺寸，`OverflowBox` 让出来的宽高也传不下去 —— 得写
  `fit: StackFit.expand`。
- **控制带那两拨控件是"分行"不是"分组"**（5 号）：参考稿按钮 `top-12 left-12` + `mt-4`
  （=48,64）、两枚角标 `top-1 right-2`（=4,8），横向投影本来就重叠，隔开它们的是那 60px 行距。
  图省事把两拨都塞进 12px 的同一条带，角标就整个骑在按钮上（第一版 golden 就是这么烂的）。
  这条同时定了舞台高度：最高的岛 210 + 底部让 28 + 按钮底沿 100，`stageH` 不给到 344 就要撞。
- **`FontWeight` 没有 `.w(int)`**（5 号）：只有 `FontWeight.values[weight ~/ 100 - 1]` 这条路。
  更要紧的是打包进来的 Inter 只带 400/500/600/700，`font-black`(900) 在真机和 golden 上都落到
  700 —— 别拿字重当像素对齐的依据，量文字外接框要按 700 的推进宽度留余量。
- **假时钟得自己记增量**（5 号）：`to(t, T)` 若写成 `run(t, T - 360)`，第二次调用起就是在
  "从挂载算起"倒着推 —— `run` 的 `while (left > 0)` 把负数吞成空转，于是"推到 2200"其实停在
  原地，读回来的是上一档。用一个 `nowMs` 累加器加 `expect(T >= nowMs)` 的单调断言，开场队列
  那种"五档按绝对时刻落"才量得准。
- **角标的 key 挂在 `Container` 上**（5 号）：`t.widget<Text>(find.byKey(k))` 直接抛
  *Container is not a subtype of Text*，读文本得 `find.descendant(matching: find.byType(Text))`。
- **量尺：外接框会把 AA 灰边当成邻居**（5 号）：岛那圈 1px 半透明描边压在 `#F5F5F5` 上，糊出来
  的灰正好落进 `#404040 ± 10` —— 拿近色外接框去量 neutral-700 那块，四条边距全成 0。改成"沿一条
  线扫连续 n 个同色"，1px 的边就甩掉了。反过来，禁用态按钮是 `#171717` 打五折 = 134 的灰，
  外接框阈值给 90 会整颗找不到。
- **定长那一段别去量**（6 号）：卡高是弹簧值，中段只能按"内容盒 − 页眉 − 页脚"算，而页眉的
  自然高要 post-frame 才读得到 —— 首帧读回 0，那一帧的 `Column` 就比内容盒高出整整一个页眉，
  RenderFlex 报溢出 106px（正好是页眉高）。badge + 标题这种由 class 直接算得出的段，写成常量
  （`headH = 22 + 8 + 28 + 24×2`）比量更准；只有真会随宽度换行的段才值得挂量尺。
- **钳负值要钳两处**（6 号）：目标 0 的高度弹簧会先冲过 0 再荡回来。渲染侧
  （`SizedBox.height`）钳了，参与算术的那一侧（中段减去的页脚高）没钳 → 中段被凭空撑高，
  照样溢出，而且只在收起途中某几帧出现，三帧采样全绿。
- **补间的收尾帧要留一帧余量**（6 号）：`_tick` 只在"还在走"时 `setState`，判定写成
  `elapsed < 150` 时，最后一帧落在 148.7ms，进度 0.997，之后再也没有第二帧 —— 画面永远停在
  差 0.023px 的地方（tooltip 那条 `closeTo(…, 0.01)` 就是被它抓到的）。判定加 32ms 余量，
  让"跨过终点那一帧"至少重建一次。
- **`{expanded && <Button/>}` 在树上是摘掉，不是裁掉**（6 号）：参考稿那枚描边钮挂在 stagger
  的最后一个孩子里，收起那一瞬就整棵子树没了。断言只能用 `findsNothing` / `findsOneWidget`，
  拿高度或位置判等于什么都没判；自然高那一路仍按"有"来量，靠 `OverflowBox` 兜住缩的那一瞬。
- **参考稿自己就把内容裁掉一截**（6 号）：展开态白卡内容盒 432，页眉 106 + 中段 290 + 页脚 36
  正好占满，而中段的内容要 288、可用只有 266 —— 最后一枚钮被 `overflow-hidden` 吃掉 13px。
  这是它 `flex-grow` 的既定行为，照抄，别"顺手修好"（像素量尺实测：钮可见段 405→428）。
- **行盒按整像素取整，排版流会把钉死的盒子顶爆半格**（8 号）：`fontSize 20 / height 27.5`
  实测行盒是 28.0，`14 / 22.75` 两行是 46.0（不是 45.5）。参考稿内容区那 194 是量出来的死数，
  四段照 CSS 那样流式往下排就凭空多出 0.5px，直接报 RenderFlex overflow。做法：四段改成
  量到的**绝对落点**（24 / 59.5 / 121 / 138）摆进 `Stack` —— 段落多出来的那半格本来就落在
  段与段之间的空隙里，换摆法一格不挪。于是断言只钉落点，行高那两侧给 ±1 的容差。
- **接缝的垫角要锚在标签自己那条边上**（8 号）：标签的宽是内衬撑出来的（`px-5` 包一行 11px
  的字），字形换一档就跟量到的 105.1 差几像素。垫角若照量到的横坐标摆（图坐标 −1 和 104.1），
  接缝处就留一道白缝或压出一道白边；改成"相对标签自己的边探出 31、回叠 1"之后宽度怎么变都
  咬住。这条同时定了个规矩：**量到的宽度只能当测试预期，不能当布局输入**。

### 12.9 触屏这一路（三页共同的账）

三页最初都是照"有鼠标、有物理键盘"那台机器做的：**看得见不等于能操作**。补触屏时定下的
口径都收在这一节，新格照抄；逐格的触屏状态记在 `docs/ui_labs.md` §2 台账那一列里。

- **假输入在触屏上是死的**（交互 1/9/11、表面 1/3）：那几格打字走 `Focus.onKeyEvent`，
  只吃物理键，指尖 `requestFocus()` 什么也不弹。补法是压一颗全透明的真 `TextField`
  接管焦点，字经 `onChanged` 喂回内部那份读数。**只在安卓/iOS 挂**（`IlTouch.softKeyboard`
  / `SvTouch.softKeyboard`），桌面那条路一字不改 —— 代价是这条分支在离屏测不到（桌面恒
  为 false），只能真机验收。所以"桌面 golden 一像素不动"是它的保险，不是它的证明。
- **悬停驱动的格子给不出 enter，就用点按顶替，但判据不许换**（交互 13、表面 8、动效页那批
  `LabHoverRegion` / `SvHoverRegion`）：指尖点一下卡片当"指针进来并停在原地"、再点一下当离开；收不收仍走
  原来那套几何（交互 13 是 `_zone` 那条 path，点在钮与钮之间那块 reach 里算"还没走"）。
  **只认 `PointerDeviceKind.touch`**，桌面鼠标点击不改变悬停语义，两件事各走各的。
- **跟手那几格会被整页滚走，而且是两种输法**（动效 20、交互 4/6）：① 交互 4/6 跟手走的是裸
  `Listener`（要的是"按住就是我的"那种语义），它**不进手势竞技场**，外层
  `SingleChildScrollView` 那颗 `VerticalDragGestureRecognizer` 一过 slop 就把整笔赢走；
  ② 动效 20 的图块用的是 `onPan*`，**进了竞技场照样输** —— 页面那颗滚动的 slop 更短，先起步的
  成了它。所以"我这格用的是正规 `GestureDetector`"不构成安全证明。补法是一枚计数锁：按下
  `*TouchLock.acquire()`、抬起和取消都 `release()`，页面外壳读 `held` 把滚动物理换成
  `NeverScrollableScrollPhysics`。
  锁必须幂等（`_locked` 一档）并在 `dispose` 兜底 —— 漏还一次整页永久滚不动。桌面鼠标走
  滚轮，计数挂着不改变手感，所以这条对 golden 也没有影响。
- **这一条测得出来，别默认"只能真机"**：`tester.startGesture()` 默认就是
  `PointerDeviceKind.touch`，只要挂的是**整页**（不是单格），竞技场、slop、滚动全是真的。
  `test/motion_lab_touch_trigger_test.dart` 20 号那条就是这样验的：按下读数 → 拖完页面
  `pixels` 没动 → 图块自己跟手 → 松手归还。44 号"按住说话"是同一验法的第二个实例，而且它
  那一侧是**裸 `Listener`**（连竞技场都不进），锁只能靠按下那一下主动给出。裸 `Listener`
  会留 pending 微任务，收尾要
  `TestAsyncUtils.guard()` 包住 `up()` + 推帧，否则报的是铺垫造成的假红。
- **受理区不能压在脸自己身上**（表面 4）：把透明命中层叠在脸上面，视觉对、静止帧 golden
  也对，唯独**按下的那一档慢半拍** —— 脸自己的 `onTapDown` 要等竞技场分出胜负（松手那一瞬）
  才发。`sv_c04_press` 那一帧整块压印没亮起来，就是这么抓到的。改法：把外扩那一圈拆成
  **四条互不重叠的带子**（上/下/左/右），带子各占各的点，脸上那一下仍由脸自己接
  （`svTapBands` / `ilTapBands`，`SvTapGrow` 同理）。
- **探出宿主盒子的命中压根收不到**：`RenderBox.hitTest` 第一句就拿自己的 `size` 判这个点
  在不在框里，祖先链上有一环没框住，事件根本走不到探出去那一层 —— `Clip.none` + 负 inset
  的 `Positioned` 是**只画不收**：看着挺对，点上去是死的。所以扩命中必须占一格真实布局，
  三条路：① 宿主本来就够大（页脚 56、整块内容）→ 带子铺在同一层 `Stack` 里、排在脸前面；
  ② 撑脸自己的盒子 → 撑出去的量要从邻隙里**如数扣回**（`gapAfter` / `rowGapAfter`），
  否则居中那一排脸全跟着平移；③ 没有大宿主就自己铺一层（表面 2 把 16×16 的箭头铺在整块
  内容上、按内容坐标定位，因为页脚总共 40 高装不下 44 那一格）。
- **44 是下限、圆心距是上限**：邻居只隔 12 时，相邻两颗受理圆各只能探 6 —— 越过中线就是
  替对面按了。交互 12 折叠态那三颗因此封顶 32 宽（`min(44, 本脸/2 + 间距 + 邻脸/2)`）。
  凑不满 44 说明几何不够，别叠透明层硬凑：要么改间距，要么这格在触屏上换一档布局。
- **别拿"这格历史上没写锁"当安全证明**（表面页）：逐格要验的是"这一格跟手的那条识别器
  参不参与竞技场"，不是"有没有锁"。表面页六格逐格查过，今天没有一格把表面本身拖着跟手
  （岛的拖拽、大卡的悬停、浮层的点外面收回，都只改内部读数），所以那把锁是空挂的。
  接线留着：以后加真跟手的格子（形变面板那类）必须同帧上锁。

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
- **动效实验室**（§12）：44 格参考案例全部落地，一格一个组件、零全局主题耦合，
  132 张 golden（每格静止/途中/终态）可复现；途中帧哈希比对证明 44 格**全部**在动

- **媒体层 chrome 整族收编**（§2.7）：封面卡/看图器/播放器/朗读页/漫画阅读器的
  `Colors.white*`·`Colors.black*`·`Color(0x…)` 遮罩全部落进 `AppMediaChrome`（经 `s.` 暴露），
  并补齐"底恒白则字恒深"的配对（改名框、白实心按钮、白色磨砂工具条）；日志控制台整块
  换 `s.terminal`（`AppTerminalPalette`），两处阅读器纸张底色换 `AppReaderPaper` 单一出处。
- **动效档位补齐**（§5.2）：循环动画（`beat/pulse/ambient/spin`）与浮层驻留（`dwell/dwellLong`）
  从过渡档位里分出来——它们不是 A→B 的时长，以前一律拿 `base/slow` 顶，常驻呼吸就抖得发慌。
- **描边宽度成阶梯**（§3.3）：`strokeUltraThin/Hairline/Thin/Regular/Emphasis/Bold` 六档固定值、
  不吃 `scaleW`；主题自身的 11 处发丝线已从 `scaleW(1)` 换成 `m.strokeHairline`。
  这一族**全部四个入口**（`Border.all`/`BorderSide`/`Divider(thickness:)`/`Paint..strokeWidth`
  与 `CircularProgressIndicator(strokeWidth:)`）已整体落到档上：生产代码里剩下的数值描边
  只有图表几何两处（仪表盘环 6、十字线 0.8，§2.6 口径），约 60 处 `scaleW(1)/(2)` 边框已改掉
  （**副作用**：边框不再随窗口缩放变粗，高分屏上是有意为之）。
- **曲线全归 AppMotion**（§5.3）：`Curves.*` 在生产代码归零，映射一条不加新档
  （`easeOutCubic/easeOut→decelerate`、`easeIn*/reverseCurve→accelerate`、
  `easeInOut*→standard`、`easeOutBack/elasticOut→springCurve`）。
  多次过冲那两处（gooey 下拉的 `elasticOut`、传输气泡的 `easeOutBack`）按 §5.1 换成弹簧近似档。
- **磨砂 sigma 全归 AppGlass**（§5.4）：12 处裸 sigma（6/8/10/12/20/30）收进现有档，
  并补了下界两档 `blurTrace 3` / `blurFeather 8` 给封面卡浮层；漫画阅读器两条
  `scaleW(18)` 磨砂换成 `blurMedium`（描边/磨砂不吃 `scaleW` 的同一理由）。
- **驻留与循环补齐调用点**（§5.2）：SnackBar 默认值、导入状态自动清除、节点面板自收、
  局域网扫描雷达那类改走 `dwell/dwellLong/dwellNotice/ambient`；
  同时把"不是动效的时长"（超时/轮询/防抖/seek/idle 计时）划出档位之外并写明判据。
- **两处白字白底类缺陷**：标签色板的勾（`#F6BD16` 这类亮黄上恒白看不见）改按底色亮度取
  `s.onMediaInk`/`s.onMedia`；关于页品牌标 tint 换 `s.onMedia`。
- **看图器进场缩放成档**：`AppMotion.scaleStage 0.93`（三处入口原本各写各的 0.93）。
- **等宽字族单一出处**：`AppTheme._monoFontFamily` + `_monoFontFamilyFallback`（Menlo → Consolas →
  DejaVu/Liberation → monospace），调用点只走 `AppTextStyles.mono(context, …)`。
- **v2 试验田整页验收**（`lib/pages/power_stats/`）：柔彩氛围底 + 玻璃卡 + 事件驱动动效
  在一页上跑通，11 条用例 + 13 张 golden（明/暗/宽/窄 + 三处悬停浮层 + 四个事件帧 +
  区间重播 + 尾巴动画 + **1.6 字阶无溢出回归**）。色板出处 `power_stats_theme.dart`，
  通用件出处 `power_stats/components/`——**这两处就是 §2.9 与 §9 上收前的唯一实体来源**。

### v2 全局化波次（本节是执行计划，不是历史）

**关键杠杆**：619 处 `AppSemantic.of(context)` 取色入口**不用逐页改**——换掉令牌值，它们自动跟着换
（口径：`grep -rn "AppSemantic\.of" lib --include='*.dart' | wc -l`，其中约 20 处就在 `core/theme/` 自己）。
所以每个波次只有两种动作：**W0 换值**（一次性、全局生效），**W1+ 换表面**（逐页：加氛围层接收、
卡片换 `GlassCard`、数据面接 §9.2 四条）。`lib/pages/**` 下共 56 个 `*_screen.dart` / `*_page.dart`，
扣掉豁免树（`backup` 1、`demo` 2、三页 lab 3）与死文件 1，**待铺 48 页 / 已完成 1 页（样板页）**。

| 波 | 范围 | 页量 | 出口判据 |
|---|---|---|---|
| **W0 地基** | 新建 `app_atmosphere.dart`（§2.9 全表上收）+ `AppSemantic` 换值 + `ThemeMetrics` 圆角三档升档（§3）+ 字重与 `w800` 收编（§4）+ `AppMotion` 补 `roll`/`scaleBlock` 两档（§5.2/§5.4）+ **§9 通用件上收** + **外壳收口氛围层**（§7.4）+ `PowerStatsPalette` 改为消费全局层 | — | 全仓 `dart analyze` 分域干净；样板页 11 条用例与 13 张 golden 全部重跑并**逐张看图**（令牌换值必然改基线）；`s.`/`a.` 双入口文档化 |
| **W1 门面** | `components/window/*`（侧栏/顶栏/把手/浮层）+ `dashboard_screen` + `theme_preview_screen`（新令牌可视化总览） | 1 + 外壳 | `shell_chrome_*` / `sidebar_*` / `dashboard_*` 出图重跑；外壳同屏 `BackdropFilter` ≤ 8 实测计数 |
| **W2 高密度业务** | `ledger`(9) / `manga`(8) / `game_library`(8) / `collection`(3) | 28 | 每模块明暗各一张 + 一条 1.6 字阶回归；列表族**保持实色**（§7.1），只有卡族换玻璃 |
| **W3 内容与播放** | `novel_library`(1) / `novel_reader`(1) / `music_player`(2) / `about`(1) | 5 | 阅读器纸张族（`AppReaderPaper`）与媒体 chrome（§2.7）**不受本次影响**，只换外壳与卡片 |
| **W4 工具与运维** | `tools` / `sentry_log` / `aliyun_ddns` / `lan_transfer`(2) / `ncm_decrypt` / `module_management` / `settings` / `websocket_test` / `http_bridge_test` / `capture_screen_page` | 11 | 日志控制台仍走 `s.terminal`（§2.8），别把终端格玻璃化 |
| **W5 清账** | 死文件 `lib/pages/novel_library_page.dart` 删除（**需用户确认**）+ §13 残余豁免复账 + 旧语言注释清理 | — | §10 全部 grep 口径复跑一遍归零或记账 |

每波结束跑 W0 的三件套：analyze 分域、golden 明暗重跑、玻璃预算与旧语言 grep 复账（§11 的命令口径）。
**不要跨波混做**：令牌值没定稿就逐页换玻璃，会得到"卡片有的厚有的薄、有的透有的实"的中间态。

### 未完成（按可见度排序）

| 缺口 | 现状 | 复测方式 |
|---|---|---|
| 📐 外壳 logo / 面包屑 / 子项连接线 | 代码与出图都已就位（§6.2/§6.3/§6.5：`sidebar_expanded_*` / `sidebar_tree_light` / `shell_topbar_*`）；剩连接线"自上而下描出 + 横枝 stagger"和面包屑末端换脸两组动效未做 | §5.5 的 3、5，§6.5 |
| 🔧 弹簧档已有、调用点未接线 | `AppMotion.spring` / `springCurve` 已落地，全站 `AnimatedX` 仍挂 `Cubic` | §5.3、§5.5 的 1/3/7/10/11/12 |
| 🔧 DPI 档位偏少 | `_adaptiveScaleFactor()` 只四档、上限 1.14 | §3.3 |
| 图标残留：`IconData` 形参的-helper | `Icon(Icons.*)` 直接渲染只剩 5 处（`node_directory_picker` 2、看图器三个 part 各 1），但**私有 helper 用 `IconData` 收参数、内部再 `Icon(icon)`** 的写法在看图器那组 `part` 里成窝（`_GlassIconButton` 收 4 个 `Icons.*_rounded`）。§13 早先记的"图标全部收敛"指的是渲染点，这一类是漏网的签名层 | `rg -o 'Icon\(Icons\.[a-zA-Z_]+' lib --no-heading \| wc -l`；再逐处查 `final IconData` 形参 |
| 历史取色的**残余豁免**（收编已到底，剩下的是记账） | 生产代码（排 `core/theme/`、`lib/gen/`、§12.3 实验室与两张展示页）里：① 裸 hex **21 处**全部在命名常量族内——黑胶盘面 `_DiscMaterial` 10、搜索高亮 `_SearchHighlight` 4、小说卡 3、漫画条按钮 `_BarBtn` 3、音频舞台渐变 1；② 裸 `Colors.*`（非 `transparent`）**26 处**各有豁免理由——启动图 5（`runApp` 前禁 `AppTheme.metrics`）、强调色选择器的原始色板 12（这个面的职责就是摆色板）、按亮度反差挑勾字 2（`computeLuminance()`）、死文件 7、设备头像 HSL 派生 1；③ `LightColors.`/`DarkColors.` **12 行** = 色板 10 + `live_frost` 窗口底 1 + 死文件 1；④ `Colors.transparent` 82 处不是取色，是"这里没底"，不进这套账。`brandColor` 已 0 处 | `grep -rn "Color(0x[0-9A-Fa-f]\{8\})" lib --include='*.dart' \| grep -vE "core/theme/\|lib/gen/" \| grep -v ":[ ]*//"`；`grep -rn "Colors\.[a-z]" lib --include='*.dart' \| grep -v Colors.transparent \| grep -vE "core/theme/\|pages/(backup\|demo\|surface_lab\|motion_lab\|interaction_lab\|theme_preview_screen\|style_showcase_screen)"` |
| 死文件待清 | `lib/pages/novel_library_page.dart`（根级，10KB，路由实际指向 `pages/novel_library/novel_library_page.dart`，全仓零引用）带着 7 处裸 `Colors.*` + 1 处 `LightColors/DarkColors` 三元分支（另 2 处 `transparent`），收编时按"死代码"跳过 | `rg -n 'pages/novel_library_page' lib/ test/` 应为空 |
| 其余 48 个页面仍是 **v1 语言**（中性底 + 实色卡 + 墨主色） | 与样板页并排会明显不一致；这是**预期中的中间态**。好消息是"换值"一步（W0）就能把它们整体带到 v2，剩下的全是"换表面" | §13 的 v2 波次表 W1–W5；单页判据三件事：卡片是否 `GlassCard`、氛围层是否只由外壳画、§9.2 四条数据面约定 |
| **v2 地基四处待接线** | ① `AppAtmosphere` 尚未建（§2.9 全表还活在 `power_stats_theme.dart`）；② `AppSemantic` 的柔彩档值未替换（现在仍是 v1 灰阶）；③ 圆角三档升档未做（`radiusCard` 仍 10）；④ `AppMotion` 缺 `roll` / `scaleBlock` 两档 | W0；每项都要跟着重跑对应 golden |
| **氛围层还在页面自画** | `desktop_scaffold.dart:180` 目前刷 `canvas` 实底，样板页自己叠了 5 层渐变；外壳收口后页面那一层要撤（§7.4） | W0/W1；`grep -rn "backgroundLayers\|RadialGradient(" lib/pages --include='*.dart'` 应当只剩外壳 |
| **玻璃预算未实测** | 同屏 `BackdropFilter` ≤ 8 是按样板页（5 张卡）推的，没在 Windows / 低端机 / 大列表页验过帧时间 | W1 起每波首次出图时顺手记一次帧时间 |
| **Inter 缺 800 档** | 资产只有 Regular/Medium/SemiBold/Bold（`pubspec.yaml` 181–187 行），17 处 `FontWeight.w800` 静默降 Bold（试验页 15 处 + `sentry_log` 2 处） | §4；要么补 `Inter-ExtraBold.ttf` 进 `pubspec.yaml`，要么 17 处收 `w700` |
| **暗色实心胶囊对比度不达标**（实测算出来的，不是猜的） | 白字压 `#7C9BFF` 只有 **2.63:1**（WCAG 需 4.5:1）；压 `#2F65DE` 是 5.2:1。所以暗色档"实心底 + 白字"必须换深一档蓝 | 已定方案：新增 `accentSolid`（暗 `#3B63D8`，5.3:1），`accent` 在暗色档只承担线/游标/字（§2.1、§14 冲突 C3） |
| 共享组件库未铺满 | 大量页面仍手搓卡片/空状态/小节标题（~25 套卡片、`_GlassCard` 两处重复、`EmptyState` 两套打架） | 见 §9 右列 |
| 动效**字面量已清零，编排还没统一** | 时长/曲线/描边/sigma 四类字面量都落档了（口径见 §5.3、§3.3、§5.4 的 grep），剩下的不是数字而是编排：① 绝大多数 `AnimatedX` 还挂 `standard`，弹簧档只接到 §5.5 点名的几面；② 退场普遍还在倒放同一条时间轴（该取相邻低档，§5.2）；③ 路由转场两条手写 builder 没并给 `AppPageTransitions.fadeUp`（260ms 与 0.985 因此还在档外，§5.3）；④ `StateTransitionAnimation.animationDuration` 默认仍是手写 400ms。另：`StateTransitionAnimation` 已随图标迁移换签名（`icon`/`hoverIcon` 现为 `StrokeIcon?`），图标固定 `StrokeTrigger.none`（§9.1 的"一个主角"） | §5.5 逐面 + §5.6 逐输入；字面量账：`grep -rn "Duration(milliseconds:\|Curves\.\|sigmaX: [0-9]\|Border\.all(.*width: [0-9]" lib/pages lib/components --include='*.dart'`（曲线 / sigma / 描边三项应只剩 §12.3 实验室页与图表几何两处；`Duration(milliseconds:` 剩下的 18 处全是 §5.2 划出去的"数据节奏"——超时、轮询、防抖、重试、逐帧节拍、idle 计时，逐处自解释） |
| 自选强调色仍会覆盖新主色 | 用户以前存过自定义强调色的话，除非改选第一档"跟随主题"，否则旧色仍生效。**v2 起这条更要紧**：存过的品牌紫/旧墨色会直接顶掉柔彩蓝，整页看着还是 v1 | 设置页 → 主题 → 第一档；`AppTheme.kFollowThemeAccent` 哨兵（§2.3） |
| `surfaceActive` 仍是实心 | 按压态会打断窗口磨砂（悬停已修，按压未修） | `app_colors.dart` |
| 仪表盘卡片是死控件 | `onTap: () {}`；指标卡在 300px 封顶，宽窗留白 | `dashboard_screen.dart` |
| 仪表盘 golden 里数值是 `--` | `SystemMetricsService.lastSnapshot` 没有测试桩 | 需要时补注入点 |
| 真·背景模糊菜单 | `GlassMenuItem` 靠 `ThemeData.hoverColor`，浮层模糊仍需 `MenuAnchor.overlayBuilder` | `glass_menu.dart` |
| Flutter 侧调系统命令 | `music_player_viewmodel.dart:838` 用 `scutil --proxy`、`:1223` 用 `open -R`/`explorer`，违反 §10.10，应下沉 Rust | `grep -rn "Process.run" lib/` |
| 底部播放条重复/空实现 | 播放模式按钮出现两次（全同）；"播放列表"按钮 `onPressed` 空函数体 | `bottom_player_bar.dart` |
| Windows 透出未实测 | 子窗口 HWND 的 alpha 行为未验证 | `window_backdrop.dart:46` |

---

## 14. 冲突与待确认

这一节只干一件事：**把"试验页已验收"和"全站现状"打架的地方列出来，并给出实测代价**。
试验页证明的是这套语言**能成立**，不是它**能和现有 48 页无痛共存**。下面五条里，
C3 已经当场解决（记录结论供复核），C1/C2/C4/C5 **需要你拍板**——我在 W0 动工前不会自己选。

### C1 `danger` 与"下跌"撞车：错误红 vs 走势rose  `needs-decision`

| | v1 状态色 | v2 方向色（试验页实测） |
|---|---|---|
| 用途 | "这块数据有问题" | "这块数据在往下走" |
| 亮 | `danger #E40014` | `data-fall #F06E81` |
| 暗 | `danger` 同一支 | `data-fall-dark #FF8DA0` |

- **冲突点**：两个都是红族，小尺寸徽标上肉眼分不出"故障"和"跌了"。试验页里 `data-fall` 出现频率远高于
  `danger`，因为它要给每一根下行柱上色；而同一屏的事件流水里失败项就挂着 `s.danger`
  （`power_stats_screen.dart:1047`：`success ? s.success.color : s.danger.color`）——那一屏里红有两种意思。
- **实测代价**：`grep -rn "s\.danger" lib --include='*.dart'` → **142 处 / 54 个文件**。
  这不是要改这些点，而是说：任何"红族重新分工"的方案都要在这 54 个文件的出图里被验证，
  改一支等于 54 个文件的 golden 重看。
- **我的建议**：`danger` 保留且**只**给"操作失败/不可用/超阈值"；`data-fall` 永远不进状态角色层
  （它在 `AppAtmosphere`/`AppViz`，§2.5 的判据"这块颜色在报告'好不好'还是在报告'往哪走'"）。
  记账页的收入/支出、电量的峰/谷一律走方向色，**不许借用 `success`/`danger` 当涨跌**——
  这条已经写进 §2.5，此处只是把代价说明白。

### C2 `info` 的紫与 `violet` 的紫几乎是同一支  `needs-decision`

- **现状**：`AppSemantic.info` = `#8D54FF`（`app_colors.dart` 的 `lightInfo`）；
  试验页的 `violet` = `#715FFD`，暗档 `#9C8CFF`。相差不到一档明度，同屏放一起会被读成"同一个紫用错了"。
- **实测代价**：`grep -rn "s\.info" lib --include='*.dart'` → **75 处 / 38 个文件**。
- **三条路**：
  1. **info 归并到 violet**（推荐）：`info` 换值成 `#715FFD`，两族合成一族。代价是 38 个文件跟着换值，
     且"提示"从此没有独立色相可用。
  2. **info 换色相**：把 info 挪到青蓝一侧（例如与 `cool #1B8FB5` 同族），紫整个让给氛围。
     代价：38 处的语义色彩全部重认一遍，历史截图失去可比性。
  3. **两者都留**：靠"info 只用于文字/图标点缀、violet 只用于渐变与身份"分工。
     代价：这条分工只能靠 §10 的规矩维持，最容易在后续页面破功。
- **我的建议**：走 1，但**留 `info` 这个名字**（业务代码不动），只换值。这样 38 处调用点零改动。

### C3 暗色实心胶囊的对比度（**已解**，记录供复核）

- **问题**：白字压试验页的 `accent-dark #7C9BFF` 只有 **2.63:1**，WCAG AA 要求 4.5:1，不达标。
- **实测**：压 `#2F65DE`（亮档）= **5.2:1**；压 `#3B63D8` = **5.3:1**。
- **结论**：拆两档——`accent` 负责"亮着的东西"（线、游标、字、洗底），
  新增 **`accentSolid`** 负责"要压白字的实心底"（实心胶囊、主按钮），暗档取深一档的 `#3B63D8`。
  已落 §2.1 表格与 frontmatter。

### C4 圆角整体升档是**全站重排**，不是一页的事  `needs-decision`

- **现状**：`ThemeMetrics` 里 `radiusControl = scaleW(8)`、`radiusCard = scaleW(10)`
  （`app_theme.dart:1177/1179`），试验页实测：所有玻璃卡走 `radius16`（`PsGlassCard` 默认），
  六列维度卡走 `radius14`，抓取按钮走 `radius20`。v2 §3 把三档定为 `10 / 16 / 20`。
- **实测代价**：`grep -rn "radiusCard\|radiusPanel\|radiusControl" lib --include='*.dart'` →
  **66 处 / 20 个文件**，其中 `app_theme.dart` 主题自己占 **17 处**，业务调用点 **49 处 / 19 个文件**。
  改值即**所有明暗基线重拍**，包括与 v2 无关的旧页面——它们会在同一次提交里变圆。
- **待确认**：是接受"一次把 20 个文件一起变圆"，还是**只对上了玻璃的卡升档**（其余暂时留着旧 8/10）。
  我建议前者：混用会得到"卡片有的厚有的薄"，而 §13 的波次表本来就是按"令牌先定稿"排的。

### C5 用户自选强调色会顶掉柔彩蓝  `needs-decision`

- **机制**：`AppTheme.kFollowThemeAccent` 是"跟随主题"哨兵（`app_theme.dart:34`）；只有选到第一档时
  `buildCustom*` 才短路（`app_theme.dart:117` 的 `followTheme` 判定），否则用存的色覆盖 `semantic.accent`。
- **实测代价**：`accent` 相关取色点 **537 处 / 96 个文件**（`grep -rn "s\.accent" lib --include='*.dart'`）。
  也就是说：**只要用户以前存过一档自定义强调色，v2 换底在他机器上等于没换**——整屏还是 v1 的墨/紫。
  选择器里存的还是旧色板（`theme_settings_tab.dart:20` 的 `_accentPalette`，10 档原始色）。
- **三条路**：
  1. **迁移一次**：读到存的值等于旧色板任意一档时，重置为"跟随主题"；用户真自定义过的保留。
  2. **换色板**：`_accentPalette` 换成 v2 的六支（accent/violet/warm/cool/data-rise/data-fall），
     存过的旧值自动失效，但不通知用户。
  3. **只改文档**：让用户自己去设置页点第一档（§13 现在的口径）。
- **我的建议**：1 + 2 同做——换色板，并把旧值映射到最近的新一档（而不是直接重置），迁移完在设置页留一行说明。
  这条涉及用户存的偏好，所以我**不擅自动手**。

### 已定不再议（本页已出图验收，改动前请先看 §11）

| # | 结论 | 出处 |
|---|---|---|
| D1 | 状态色族五档不动，涨跌/峰谷是**身份**不是**状态** | §2.5、§0.5 末行 |
| D2 | 氛围层只在**外壳画一次**，页面不许自铺背景；同屏 `BackdropFilter` ≤ 8 | §7.4、§10 第 20/21 条 |
| D3 | 移动端保留柔彩**颜色**、去掉**模糊**、玻璃退化实色 | §8 |
| D4 | 展型大数字走宽度族（`scaleW(52)`，实测 `power_stats_hero.dart:77`） | §3.1 例外档 |

---

## 15. 相关提交

```
72316ae feat(power_stats): 电量统计页改成柔彩氛围底 + 玻璃卡，动效改为数据驱动
40452f4 refactor(ui): 音乐播放器整块接进设计系统语义层
e5c94d6 fix(ui): 悬停状态层在亮色下真正可见——水洗方向跟底色走
9534679 feat(ui): 菜单收进设计系统——新增紧凑菜单项，浮层统一玻璃口径
383dfa6 docs: 新增 DESIGN.md，把设计系统的取色/尺寸/动效口径与踩坑写成唯一规范
```
