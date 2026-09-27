# 实验室页面：对接流程与组件清单

> 三块隔离展示页（动效 / 交互 / 表面）的共用接线方式，以及现有 62 格组件的功能与样式台账。
>
> 追加新格、新页时照着第一节走一遍即可；踩坑记录不在这份文档里，见 `DESIGN.md` §12.4 / §12.7 / §12.8。

---

## 0. 三页一览

| 页 | 路由 | 目录 | 本地令牌前缀 | 注册表 | 已实现 | 分类 |
|----|------|------|--------------|--------|--------|------|
| 动效实验室 | `/motion-lab` | `lib/pages/motion_lab/` | `Lab*`（`lab_kit.dart`） | `kLabCases` | 43 格 | essential / texts / effects / ai |
| 交互实验室 | `/interaction-lab` | `lib/pages/interaction_lab/` | `Il*`（`kit.dart`） | `kIlCases` | 13 格 | 按压 / 拖拽 / 选择 / 输入 / 悬停 |
| 表面实验室 | `/surface-lab` | `lib/pages/surface_lab/` | `Sv*`（`kit.dart`） | `kSvCases` | 6 格（计划 9 格，7/8/9 号待写） | 浮层 / 拖拽 / 按压 / 形变 / 输入 / 揭示 |

三页的定位完全一致：**看的东西，不是用的东西**。每一格复刻参考稿的一个组件，尺寸/圆角/颜色/时长/弹簧参数全部自带，不读也不写任何全局主题。

三页的分工：

- 动效实验室——"一个属性怎么从 A 补间到 B"，点一下 `Animate` 就成立。
- 交互实验室——每一格要真的按住、拖、敲键盘，**判定和阈值与动画参数同等重要**。
- 表面实验室——一块表面怎么变成另一块，主角是共享元素、裁切、投影这三族。

---

## 1. 对接流程（新增一页或一格都可复用）

### 1.1 目录骨架

一页一个目录，四样东西，缺一不可：

```
lib/pages/<name>_lab/
├── kit.dart                     # 本地令牌底座 + 本地壳组件（前缀统一，见 1.2）
├── <name>_lab_screen.dart       # 页面外壳：页头 / 分类筛选 / 卡片流 / 放大层
└── cases/
    ├── <name>_lab_cases.dart    # 分类枚举 + Case 记录类 + k<Name>Cases 常量表
    └── case_NN_<slug>.dart      # 一格一个文件，一格一个组件
```

命名纪律：文件 `case_NN_<slug>.dart`（NN 两位补零）、类 `CaseNN<Slug>`、golden `lab_cNN_<frame>.png` / `il_cNN_<frame>.png` / `sv_cNN_<frame>.png`、测试 `test/<name>_lab_caseNN_<slug>_test.dart`。

案例文件之间**互不引用**，只被 `cases/<name>_lab_cases.dart` 点名。

### 1.2 本地令牌底座 `kit.dart`

三页各有一份，前缀不同、成员同构。追加新页时照抄这一套类名，把前缀换掉：

| 类 | 作用 |
|----|------|
| `*Color` / `*DarkColor` | 页面自带的一整套色值（`page`/`pane`/`card`/`border`/`text`/`textMuted`/`primary`/…），暗色档单独一组 |
| `*Font` | `family`（Inter）+ `fallback`（PingFang SC） |
| `*Text` | `title` / `subtitle` / `body` 等本地字样式，`TextStyle` 直接给死 |
| `*Ease` | 参考稿的曲线表（顺出、过冲几档） |
| `*Size` | 舞台与卡片尺度：`gutter 12` / `cardRadius 24` / `stageRadius 28` / `stageW 372` / `stageH 232` / `headH 62`，并有 `cardW([w])` / `cardH([h])` 派生（动效页那一档是 `cardW 320 / cardH 344 / stageW 296 / stageH 260 / stageRadius 14`，卡片尺寸是常量不是函数） |
| `*Shadow` | 材料投影组（浮层/菜单用的一到三层）；表面页另有 `SvShadow.ring`——1px 边框环（`blurRadius 0, spreadRadius 1`），浅色表面全靠这一圈在灰舞台上分层 |
| `*Stage` | 舞台容器：`{width, height, center, clip, dark, color, padding}`，负责圆角、底色、投影、裁剪 |
| `*Card` | 卡片外壳：`seq` 角标 + 标题 + 副标题 + 舞台 + 右下角放大钮 |
| `*IconButton` | 本地描边图标钮（含悬停/按下态） |
| `*Spring` / `*SpringDrive` | 显式弹簧积分器（`phys({stiffness, damping, mass, from, rest})`）；形变格用它，不用 `AnimatedContainer` |
| `*Tween` | 单值补间工具（关键帧表 + 分段套曲线） |
| `*Goo` | 液体粘连滤镜（`ImageFiltered(blur)` 套 `ColorFiltered(阈值矩阵)`） |
| `*Icon` | 本地图标常量 |

三页的成员并非一字不差：动效页那份最早，额外有 `LabAnimateButton`（每格右下角那颗 `Animate`）、
`LabStageFooter`、`LabHoverRegion`、`LabBlur`，但没有暗色组、`*Spring`、`*Goo`；后两页才有
`*DarkColor` / `*Spring` / `*SpringDrive` / `*Goo`，交互页还多一个 `IlTouchLock`（裸 `Listener`
接管手指期间把外层滚动锁死）。新页按后两页这一套抄，再按需要补外壳件。

关键约定：

- **字面 px 是记录在案的例外**（`DESIGN.md` §12.3），只允许出现在 `lib/pages/interaction_lab/**`、`lib/pages/surface_lab/**` 和动效实验室目录里；产品 UI 一律 `AppTheme.metrics` / `scaleW()`。发丝线宽度恒为 1。
- 页头/卡片标题必须挂 `fontFamilyFallback`，否则中文在离屏出图里是一排豆腐块。

### 1.3 单向隔离墙

`DESIGN.md` §12.2 的规矩，新页同样适用：

1. 实验室**不读也不写** `AppTheme` / `AppSemantic` / `AppMotion` / `LightColors` / `DarkColors` / `AppTextStyles`；
2. 目录之外**不许 import** 实验室的任何文件；
3. 唯一入边是路由注册（`core/routes/`）。

自检（每页一条，结果只应剩路由文件）：

```bash
grep -rln "surface_lab" lib/ | grep -v "^lib/pages/surface_lab/"
# 期望只剩一行：lib/core/routes/app_routes.dart（那行 import 页面）
# demo_routes.dart 是 `part of`，路由里写的又是带连字符的 '/surface-lab'，所以它不会出现在结果里
```

页面本身**不继承 `BasePage`**：没有 ViewModel、不取服务、不参与权限链路之外的东西。

### 1.4 注册表 `cases/<name>_lab_cases.dart`

三页同构的记录类：

```dart
enum SvCat {
  pop('浮层'),
  drag('拖拽'),
  press('按压'),
  morph('形变'),
  input('输入'),
  reveal('揭示');

  const SvCat(this.label);
  final String label;
}

@immutable
class SvCase {
  const SvCase({
    required this.seq,
    required this.title,
    required this.subtitle,
    required this.cat,
    required this.build,
    // 舞台尺寸整页统一，量出来更宽/更高的格子自己报
    this.stageW = SvSize.stageW,
    this.stageH = SvSize.stageH,
    this.dark = false,
  });

  final int seq;
  final String title;
  final String subtitle;
  final SvCat cat;
  final Widget Function() build;
  final double stageW, stageH;
  final bool dark;
}

final List<SvCase> kSvCases = <SvCase>[ /* 按 seq 升序逐条列出 */ ];
// 三张表都是 `final … = <XCase>[…]` 而不是 const：条目里有构造函数 tear-off，
// 还引用了 `CaseNN.stageW/stageH` 这类跨文件常量，const 串不起来
```

动效页额外多一个 `pro` 字段（页头有「仅 Pro」筛选）。

`subtitle` 是这格的**一句话契约**：写清楚"谁动、按什么时序动、多少像素"，页面副标题、golden 说明、测试名都读它。交互页和表面页的 subtitle 直接用中文写死操作方式（要按住拖、要敲键盘、点谁）。

### 1.5 案例文件本体

一格一个 `StatefulWidget`，纪律：

- 时钟只留**一条主时钟**（`AnimationController` 或一个自增毫秒数），多组属性各自从它换算——多个 controller 各自为政就拢不住"中途再点一次"的重播。
- 需要过冲的形变走 `animateTo(curve:)` 之外的路：`AnimationController` 会把 spring 的过冲截平，所以用 `*Spring` 自己积分。
- **确定性**：随机只来自 `math.Random(固定 seed)` 的预生成常量表；禁用 `DateTime.now()`；不读真实窗口的 `MediaQuery`。
- 交互判定（阈值、吸附、松手回收）和动画参数一起写死在类里，并在测试里断言。
- 公开 `static const ValueKey<String>` 的锚点键（如 `Case04MetalButton.pillKey`），测试按键取矩形，不靠猜坐标。可点/可拖元素统一挂 `SystemMouseCursors.click / grab`，测试用光标 predicate 找触发点。
- 减弱动效（`MediaQuery.disableAnimations`）要有明确行为：要么整段不打拍，要么只留状态切换。

### 1.6 页面外壳 `<name>_lab_screen.dart`

结构三页一致，抄一个改前缀即可：

```
DefaultTextStyle(style: *Text.body)            // 少了这行，无 Material 祖先时接住兜底样式：黄色双下划线
└── Stack
    ├── ColoredBox(*Color.page)
    │   └── SafeArea > Column
    │       ├── _buildHeader()                 // 页名 20/w600 + "N / M 格…" + 分类 chip 行
    │       └── Expanded > SingleChildScrollView(padding: 24,8,24,40)
    │           └── Center > Wrap(spacing 24, runSpacing 24, alignment: center)
    │               └── for (final c in _shown) *Card(seq, title, subtitle, stageW, stageH, dark, onEnlarge, stage: c.build())
    └── if (_focused != null) _buildFocus(c)    // 放大层
```

- 筛选：`_cat`（和动效页的 `_proOnly`）只过滤 `_shown`，页头计数读 `_shown.length / kXxCases.length`。
- 动效页是这套的最早版本，`LabCard` 只接 `seq/title/subtitle/pro/onEnlarge/stage`（舞台尺寸写死在
  `LabSize`）；后两页的 `IlCard` / `SvCard` 才多了 `stageW/stageH/dark` 三栏。新页按后一种抄。
- `_chip`：`GestureDetector(opaque)` + `AnimatedContainer(150ms)`，圆角 40，选中换底色。
- **放大层**：`Positioned.fill` → 点空白关闭 → `ColoredBox(dark ? 0xE60A0A0A : 0xE6FFFFFF)` → 内层 `GestureDetector(onTap: {})`（点案例本身不关）→ `Column(标题/副标题)` + `SizedBox(stageW*2, stageH*2)` → `FittedBox(contain)` → `Material(transparent)` → `c.build()`。放大走 `FittedBox` 而不是让组件自改尺寸：2 倍是整数缩放，组件不用知道自己在被放大。
- 只有交互页多一处：`ValueListenableBuilder<int>(IlTouchLock.held)` 把外层滚动的 physics 换成 `NeverScrollableScrollPhysics`——那几格用裸 `Listener` 跟手、不进竞技场，接管手指期间不能让整页被拖走。

### 1.7 路由接线：四个落点 + 一次代码生成

1. `lib/core/routes/routes/demo_routes.dart`——加 `@TypedGoRoute<XxxRoute>(path: '/xxx-lab')` 类，继承 `AppRouteData`、`with $XxxRoute`，实现 `title` / `sidebarLabel` / `sidebarIcon`（`StrokeIcons.playCircleOutline`）/ `sidebarGroupId => 'lab'` / `static const Permission routePermission = Permission.accessDemo`，`buildPage` 返回 `AppRoutes.buildPage(context, state, const XxxScreen())`。
2. `lib/core/routes/app_routes.dart`——顶部 import 页面，并在 `@TypedShellRoute<AppShellRouteData>`
   注解的 `routes:` 列表里加 `TypedGoRoute<XxxRoute>(path: '/xxx-lab')`（这张表编译期生成 `$appRoutes`，
   运行期由 `...$appRoutes` 挂进 `GoRouter`）。
3. `lib/core/routes/app_sidebars.dart`——`buildSidebarGroupsFromRoutes()` 的 `shellRoutes` 名单里加 `const XxxRoute()`。分组配置 `'lab'`（实验室，sort 55，`Permission.accessDemo`）已经存在，新页挂上去即可；不想默认展开的话再考虑 `kSidebarDefaultHiddenPaths`。
4. `flutter pub run build_runner build`——生成 `app_routes.g.dart` 里的 `$XxxRoute` mixin（没有这步编译不过）。

### 1.8 测试底座与每格验收

离屏出图是唯一验收口径（不启第二个 `flutter run`）：

- `test/helpers/page_golden.dart`（三页共用）：`kTestWindowSize = 1440×900`、`loadAppFonts()`、`registerPageServices()`、`pumpAppPage()`（强制 `devicePixelRatio = 1.0`）、`advance({steps 12, ms 30})`、`unmountPage()`。
- 每页一个薄封装：`test/helpers/{lab,il,sv}_golden.dart`，公开同名三件套——
  - `mountXCase(tester, child, {window})`：加载字体 → `pumpAppPage(Center(child))` → `advance()`。
    窗口按 `*Size.cardW(stageW) + 24 × cardH(stageH) + 24` 算（`il`/`sv` 页默认档都是 420×342），
    动效页固定 320×284。
  - 出图取的是 `find.byType(*Stage)`，落到的其实是**整张窗口**（`sv_c01_idle.png` 实测 420×342
    = 窗口尺寸，不是舞台的 372×232）。量像素时按图内实际色块边界定位，别拿公式推偏移。
    另外 `pumpAppPage` 会把页面套进带 `AppTheme` 的 `MaterialApp` 里——那是**测试底座**，
    不是页面去读主题，隔离墙仍然成立。
  - `shootXCase(tester, {name, child, window, act, thenMs})`：挂载 → 触发 → `pump 16ms ×2` → 按 16ms 步进推进 `thenMs` → `matchesGoldenFile('goldens/<prefix>_$name.png')` → `expect(takeException(), isNull)` → 卸载。
  - 触发器：`*Tap`（优先找 `click`/`grab` 光标的 `MouseRegion`，找不到就点舞台中心）、`*HoverAt`、`ilGrab/ilDragTo/ilDrop`、`svDragTo/svDrop`、`svType`。

每格必过的四道：

1. **三帧 golden**：`idle` / `mid` / `end`（动效页统一这三档；交互页和表面页按各格真实阶段命名，
   如 `press` / `lean` / `stretch` / `overshoot` / `settle` / `fly` / `typing` / `sent`，帧数也不止三张）。
   **一帧一个 test**（出过图之后同一 test 里的点击就不再接到）。`mid` 默认 150ms，慢启动或爆得太快的格子按 seq 写进 `_midOverride`；悬停格默认 250ms。
2. **逐帧扫**：16ms 一步推到 3000ms，`takeException()` 全程为 null。三帧采样测不出"只有途中某几帧会炸"（过冲把透明度顶出 [0,1]、形变途中溢出）。
3. **树级断言**：按 key 取矩形/读数，断言几何与状态机（谁在动、动到多少、阈值卡在哪、减弱动效从头就没一拍）。
4. **量像素**：`/tmp/mNN.py` 之类的一次性脚本对参考帧做逐点测量（颜色、留白、墨量、对齐基线），结论要有数字支撑。仓库里的临时测试（`test/tmp_*`、`test/scratch_*`）用完即删，`/tmp` 脚本永不入库。

触发方式按各格参考稿写死在一张 `_acts` 表里（`animate` / `toggleModal` / `togglePanel` / `play` / `clickable` / `hoverClickable` / `auto`），别在每个 test 里重复写。

验收命令：

```bash
# 出图（首次或改了视觉）
/Users/shilaimu/fvm/versions/3.41.5/bin/flutter test --update-goldens -t golden test/motion_lab_all_cases_test.dart
# 复验
/Users/shilaimu/fvm/versions/3.41.5/bin/flutter test -t golden test/motion_lab_all_cases_test.dart
# 单格
/Users/shilaimu/fvm/versions/3.41.5/bin/flutter test --plain-name '4. Metal button'
# 逐帧扫（排除 golden）
/Users/shilaimu/fvm/versions/3.41.5/bin/flutter test --exclude-tags golden test/motion_lab_all_cases_test.dart
# 表面页
/Users/shilaimu/fvm/versions/3.41.5/bin/flutter test test/surface_lab_case04_metal_button_test.dart
```

审计：`idle` 与 `mid` 的 golden 哈希必须不同——相同就说明这格的动效没被拍到。

### 1.9 追加一格的最短清单

1. `cases/case_NN_<slug>.dart`：类、主时钟、公开 key。
2. `cases/<name>_lab_cases.dart`：`kXxCases` 末尾加一条（seq、title、subtitle、cat、build、必要时 `stageW/stageH/dark` 覆写）。
3. `test/helpers` 够用就不动；需要新触发器就在本页的 helper 里加。
4. `test/<name>_lab_caseNN_<slug>_test.dart`：三帧 golden + 逐帧扫 + 树级断言。
5. `--update-goldens` 出图 → 肉眼对参考稿 → `/tmp/mNN.py` 量像素 → 复验。
6. 踩到的坑**追加进 `DESIGN.md`** 对应小节（动效 §12.4、交互 §12.7、表面 §12.8），格式是「粗体一句话 + 为什么」，不重复代码。
7. 本文件第 2 节的台账补一行。

禁止：全仓 `dart format`（只格式化新建文件）、启第二个 `flutter run`、在代码/注释/命名/commit 里写外部参考站名。

---

## 2. 组件台账

### 2.1 动效实验室 `/motion-lab`（43 格，舞台 296×260）

分类：`essential 必备` / `texts 文本` / `effects 效果` / `ai AI`。每格带 `Animate`/`Play`/可点元素，出图为 idle/mid/end 三帧。

| # | 名称 | 类别 | 功能 | 样式与构成 |
|---|------|------|------|-----------|
| 1 | Card resize | essential | 卡片宽高一起补间，骨架跟着宽度重新量 | 一张卡 + 内部骨架条；条长写成 `calc((100% - 28px) * 0.526)` 这种相对宽，被动跟卡片收，300ms 顺出 |
| 2 | Number pop-in | texts | 换数字时整组带模糊从下方弹入，末两位错峰 | 5 个字符，位移 8px、模糊 3.5px、错峰 70ms、500ms 弹；旧数字快照成 ghost 层向上弹出，与新数字并行 |
| 3 | Notification badge | essential | 徽标斜向滑入 + 弹性放大 | 外框只做一次位移（260ms 顺出），圆点同时走 scale/blur(500ms 弹) + opacity(400ms)；收时三条一起退到 180ms |
| 4 | Text states swap | essential | 旧字收上去、换字、新字从下面回位 | 三段：收 150ms（上 4px + 糊 4px + 淡出）→ 瞬移到下方 4px → 150ms 回位 |
| 5 | Menu dropdown | essential | 以顶边中心为锚点的展开/收起 | 234×136 浮层，圆角 12、材料底 + 三层投影、内部三根定位骨架条；开 250ms（0.97→1）、收 150ms（退到 0.99），锚点 top center |
| 6 | Confetti burst | effects | 彩带从按钮上方喷出、重力下坠、1.5s 淡没 | 铺满画布（z 比按钮低一层）+ Animate 按钮；从按钮顶边成扇面向上喷，自由落体，随机来自固定种子表 |
| 7 | Modal open/close | essential | 0.96 起幅的缩放 + 淡入淡出 | 同一个 tween 走 0↔1，只把时长按方向换：开 250ms、收 150ms，两端都停 0.96 |
| 8 | Panel reveal | essential | 半张高的行程 + 同步收模糊 | 位移/透明/模糊同时长同曲线（开 400ms、收 350ms），行程只有面板高一半（blur 4 补齐），到位后整体下坐 28 |
| 9 | Gooey plus menu | effects | 液滴从中心炸开成扇形三个动作 | 一层模糊液体 + 一层清晰按钮：4 颗 r=20 圆 → `blur 6` → 阈值矩阵 `18A-7` 拉硬边，重叠处粘成桥，原图形再叠回上方 |
| 10 | Page side-by-side | essential | 前后两页错位 8px 交棒 | 两页都是铺满容器的绝对层，未选页停在 `translateX(±8)` + blur 3 + 透明 0；位移/模糊/淡入共用 250ms 同一根曲线，返回键只跟 opacity |
| 11 | Icon swap | essential | 两个图标叠同一格，一个淡掉一个亮起 | 32 方格内两张 svg 绝对定位；250ms 内 opacity、scale(1↔0.25)、blur(0↔4) 一起走 |
| 12 | Success check | essential | 绿盘从下方浮起、边转边糊，勾沿路径描出 | 48 绿盘 + 白勾；淡入/80° 转回/10px 糊/上 40px 落回四路并行 500ms，描线晚 80ms 走 500ms；退场只淡出 + 糊到 4 |
| 13 | Avatar group hover | effects | 邻接头像按距离衰减抬起，回程带过冲 | 一颗圆头像排；被指的 scale 1.05，其余只按 `lift × falloff^距离` 平移，每颗各挂一条 tween |
| 14 | Card stack hover | effects | 悬停把三张叠牌弹开成扇形 | 开 410ms 强过冲、回 360ms 收敛一档；单卡 scale 是另一条独立 610ms 顺出 |
| 15 | Error state shake | essential | 报错时横向抖一下，边框和文案各自淡 | 一条主时钟：抖 280ms → 停 3000ms → 280ms 淡回中性；每段各套一次 shake-ease |
| 16 | Input clear with dissolve | essential | 清空时逐词消散 | 旧值退场（下移 12 + 淡 + 糊 2，400ms）、假占位进场（-12 落回 + 0.9→1.0 + 收糊，400ms）两条并行；词底微光挂 1000ms 线、15% 处冲峰值 0.42 |
| 17 | Skeleton loader and reveal | essential | 骨架屏脉冲后交叉淡入正文 | 骨架与正文同坐标系叠放（骨架 z 低），换内容不动布局：骨架淡出+糊开、正文淡入+收糊，同一个 400ms；脉冲只作用骨架条 `opacity 1→0.5→1` |
| 18 | Texts reveal | texts | 两行文字错峰上浮进场，收时原地淡出 | 进 500ms 顺出、位移 12px、模糊 5px，第二行晚 40ms；收场 Y/模糊钉在终值，只有透明度 200ms 一起淡 |
| 19 | Tabs sliding | essential | 药丸指示条跟着选中 tab 走 | 条 3 内衬、档间 3、高 30、左右各 12；`translateX` 与 `width` 一起补间 250ms，每档宽按 `文字宽 + 24` 自量 |
| 20 | Drag & drop with physics | effects | 拖拽方块，落区"吞"下图片再回弹 | 2950ms 脚本时间线驱动：抬起 200ms、落回 500ms 过冲、源图淡没 450ms+blur2、落图淡入 400ms、落定弹 250ms + 收尾 450ms |
| 21 | Shimmer text | texts | 一道渐变高光横掠正文，文字本体始终在场 | 双层：正文常显 + 复刻同一串字把"透明→高光→透明"渐变裁进字形，4 倍宽渐变带从 100% 滑到 0%，2000ms 线性无限；暂停把带子停回画外 |
| 22 | Organic shimmer | effects | 灰板下有彩斑，斜向"雨刷"周期性扫过，边缘带彩光 | 三层：6 个固定位大彩斑 + 5% 灰水；近不透明骨架色蒙皮，沿 135° 留一条约 187px 软边透明带扫过 |
| 23 | Tooltip open/close | essential | 延时出现、跨触发器行进、秒退 | 三条时间线：出现 80ms 延时 + 150ms ease-out（0.98→1，锚点底边中心）、离开 50ms 立即收、换目标落点单独 160ms 滑行；宽度不预量不补间 |
| 24 | 3D tilt | effects | 卡片跟指针连续倾斜，高光跟着指针跑 | `rotateX/rotateY` 由悬停局部坐标归一化直接算，两端各 ±max/2；移动中 400ms、离开归位 1000ms（归位比跟随慢是关键） |
| 25 | Dropdown menu morph | essential | 圆钮长成菜单面板，加号转成 × 滑走 | 面板尺寸/圆角 350ms 带过冲弹（宽先顶过头再坐回 183）、位移/缩放/旋转 350ms 顺出、透明度与模糊只给 200ms；一条 linear 主时钟三组各自换算 |
| 26 | Accordion | essential | 面板从 0 长到满，V 形箭头顶翻成 ^ | `0fr→1fr` 等价写法：外层给补间高度、内层始终按完整高度排版再裁掉；展开/收起/箭头同为 250ms 顺出，箭头 `scaleY(1→-1)` 且描边恒定宽 |
| 27 | Toast open/close | essential | 从下方升起，淡入 + 消模糊 + 微放大 | 261×46 药丸吐司，材料底 + 三层投影，20 圆头像 + 178 骨架条；位移 16 / scale 0.97→1 / blur 2→0 / opacity 同一进度，开 350ms 收 250ms |
| 28 | Like button | effects | 点亮：变色、回弹、随机炸点，四条独立时间线 | 变色填充 150ms 先染红，图标同时弹 350ms（过冲 1.96），粒子再飞 600ms ease-out 末段淡出；弹和炸只在点亮那次播 |
| 29 | Image open tilt | effects | 缩略图放大展开，中途甩一次 3D 倾转 + 画面弯曲 | 开 450ms 顺出、收 350ms 带过冲，scale/圆角/倾转共用关键帧；倾转三段式（0→45→100%），`translateZ` -70 → -28 → 0 |
| 30 | Learn more hover | essential | 箭头右移一档，两条臂同时绕尖端张开 | 只有两个量：整颗 `translateX(2px)` + 两臂各 `rotate(±8°)`，支点在箭头尖端；进出同为 350ms 顺出 |
| 31 | Checkbox check | essential | 框先填色，勾再顺路径画出 | 整行自己是开关（无 Animate 按钮）；描线勾上 350ms、取消只给 150ms，且走同一个 progress（中途反悔从当前笔画位置倒收）；底色/描边环固定 150ms |
| 32 | Spinner to check morph | ai | 转圈 loader 弹成绿盘，勾再从盘里描出 | 绿盘 350ms 淡入、轨道环 245ms 淡出、转圈 175ms 淡出并就地冻住；标记先抬 3px(250ms) 再落回(300ms)，放大到 1.09，描线晚 230ms 走 600ms |
| 33 | Spinning counter | texts | 每位数字一条卷轴，转三圈后各自落定 | 单元高 30、单圈 1400ms、逐列错峰 90ms、目标 100；每位剪 30px 窗口塞 0-9×(spins+1) 数字带整带上移；拖影是**纵向**高斯模糊，窗口上下 22% 渐变软收边 |
| 34 | Toggle | essential | 滑块冲过头再荡回来，轨道底色瞬时换 | 一条 0→1 linear 主时钟 + 关键帧表（`t` 停 55%/80%），每段各套一次过冲曲线 → "冲过头→荡回→落定"双弹；开/收是两张表，不是倒放 |
| 35 | Pro gradient text | texts | 七团彩色水绕着字跑，色相自己也在转 | `background-clip: text` + 透明字色；1 层灰纵向渐变打底 + 7 层彩色径向，每层占 180%，靠背景位从 0% 推到 100%；四档关键帧排成环，每段 1250ms、整圈 5000ms，另有一条 4000ms 转色相 |
| 36 | Delete with smoky dissolve | effects | 图片碎成瓦片往下掉，越掉越糊成一团烟 | 120×120 圆角卡；碎掉在 canvas 里画：按行错开起步（下排先走）、每片落程 560ms、位移平方、同时缩小+淡掉，整层再补一遍随时间加深的糊；"复活"是 CSS 那 250ms |
| 37 | Thinking states | ai | 状态行先被扫光刷过，再整行换成下一条 | 扫光是常驻 2000ms 循环（400% 宽渐变带，只作用字形）；换行只在每轮末尾 200ms：出场 150ms 上飘 8px + 糊 2px，入场延 50ms 从下方 8px 顶回；一条 3×2200ms 主循环 |
| 38 | Reasoning stream | ai | 推理稿每停一下往上走两行 | 固定高窗口 + 比它高得多的稿子；每 840ms 上推两行(36.4px)、走 500ms 顺出；稿子复制一份接在下面，满一份高度整体回绕；上下各 28px 渐隐是 dstIn 遮罩 |
| 39 | Streaming text | ai | 词一个接一个从模糊里定下来 | 点一次把所有词抹掉重来：每 60ms 放行一个词，每词 350ms 顺出走 opacity 0→1 + 1px 模糊→0；一条补间 + `i*gap` 相位差 |
| 40 | Matrix dot loader | ai | 四个 16 点阵各自按不同延迟脉冲 | 4 个 4×4 的 2px 点、2px 间距点阵，只差一张延迟表：scan 按列 120ms、twinkle 乱序 75ms、orbit 外环 150ms(中心不动)、pulse 内圈先亮外圈晚 192ms；共用 1200ms 色循环（0→15% 亮、15→45% 暗、45% 后保持） |
| 41 | Banner stacking | essential | 吐司式堆叠，最多三层 | 新的从下方 60px + 0.97 缩放升起(350ms)，老的每退一层上移 12px、缩 0.06、按 0.4 步长变暗；挤出第三层的用另一只 250ms 钟往深处淡没；悬停全部摊开 |
| 42 | Image generation placeholder | ai | 一片噪点先醒，再把整张图接出来 | 1.5px 圆点阵，静止按各自 `--v` 停在半隐档（透明度与 scale 都随 `--v`，`--pv6a=0` 所以既淡又小）；播放后每点跑 1400ms×倍率并错开延迟，0/100% 透明缩到 0、50% 满亮满大 |
| 43 | Get Pro button | effects | 同一套彩色水，只从药丸的边上透出来 | 与 35 号共用背景配方（7 层径向、180% 尺寸、5000ms 走位 + 4000ms 转色相），外面罩一层 `radial-gradient(ellipse 46% 46%, transparent 50%, black 200%)`，字心恒白、只有周一圈接住颜色 |

### 2.2 交互实验室 `/interaction-lab`（13 格，舞台 372×232）

分类：`press 按压` / `drag 拖拽` / `select 选择` / `input 输入` / `hover 悬停`。每格都要真的按住、拖或敲键盘。

| # | 名称 | 类别 | 交互 | 样式与构成 |
|---|------|------|------|-----------|
| 1 | Search | press | 按下先压一下（90ms、0.93），松手弹簧展开；收起态整颗朝指针磁吸 | 胶囊搜索框；宽度是隐式弹簧（k=0.16 / d=0.72，收敛阈值 0.02px），没有"时长"概念。文案淡入挂在弹簧进度 `E=(宽-64)/256`、`say=clamp((E-.55)/.45)` → 走完 55% 才露字 |
| 2 | Icon bar | select | 底部导航条切档 | 滑块是**两相位**：stretch 190ms（`cubic-bezier(.32,.72,.24,1)`）把起点换成"旧槽与新槽的并集区间"，一次盖住中间跨过的格子；保持 150ms 后再带过冲弹回目标格 |
| 3 | Slide to confirm | drag | 真按住拖到底松手才确认 | 拖时 1:1 跟手、无补间，`speed` 只管松手后；确认时右边缘钉住、把手在身后摊平。偏移在**第一次移动时**才取（`grab = n - p`），不在按下时 |
| 4 | Reorder list | drag | 按住整行拖，其余让开，松手吸附，靠近 6px 内药丸熔化接上 | 色块与文字**分两层**：下层只有四颗药丸，整层过 `blur(2.6) + alpha×28−14` 硬阈值；上层是不进滤镜的头像和姓名，靠同一 y 对齐。文字绝不能进滤镜 |
| 5 | Inline confirm | press | 一按就删，白药丸弹簧长大 4 秒，Undo 或倒计时归零收回 | 无二次确认：点 Delete 直接进 done 态同时起 4000ms 钟。只有背景药丸被弹簧驱动，标签两层是"整块瞬移到目标矩形、只补透明度"，所以交接那瞬白底还在长大、字已就位 |
| 6 | Pull to refresh | drag | 按住卡片往下拽，越过 65px 阈值松手才刷新（1.15s 转圈换一条数据）；图上可横扫读数 | 一个可动部件同时驱动四个读数：手指位移 → 橡皮筋 `D=510c/(510+c)` → 弹簧（只在回弹时走）→ 同帧改卡片白底高度、内容下沉像素、液滴环透明度/半径/转角 |
| 7 | Assignees | select | 点头像条展开选人 | 四套互不同步的运动挂在同一状态：rail 宽度是定时补间（300ms `cubic-bezier(.33,.55,.2,1)` 无过冲，pill 是 inline-flex 被顶开），每张脸四路弹簧（x/y/scale 走 `{660,34,.7}`、rotate 走 `{600,21,.8}`），靠前者压住后者 |
| 8 | Create menu | press | 按下先压 60ms 再自己展开成菜单 | 一颗药丸长成菜单：`width/height/borderRadius` 三个量吃三条同参数弹簧，四行内容按 22ms 逐个进；压下那一档用 `cubic-bezier(.25,.1,.25,1)`（CSS 不写缓动名那条），`[data-sink=true]` 的 `scale` 只给 .12s |
| 9 | One-time code | input | 点一下再敲四位：先看一遍呼吸波，对了四格拉丝融成胶囊，错了抖散 | 组件本体只有 165×44 一行（`4×36 + 3×7`），无背景无边框；四格和胶囊共用一个 goo 底（blur σ=3 → `24a-12` 硬阈值），靠近 6px 内真接上；数字只掉不淡 |
| 10 | Selection list | select | 多选名单，勾第一个就长出深色 CTA | 268 宽、盒子 224 高（`10+46+4+46+4+46+4+10+44+10`），未选中时 `clip-path: inset(0 0 54 round 20)` 把底部 54px 连 CTA 一起裁掉、只留 170 可见；裁切不改布局。勾是描边画进去的 |
| 11 | Command bar | input | 点一下发送钮就从条里走出来，敲字翻深底、提交又翻回白底 | 白色形状一个都不是画出来的：条自己 `background: 0 0`，条和按钮各往 goo 层投一块白剪影（`z-index:-1`），blur σ=3 后过 `22α − 8.67` 硬阈值；形状只有两条读数——缝 ≤5px 就接上、松开各自成胶囊 |
| 12 | Now playing | press | 点整条长开成完整播放器 | 78 高的播放条 → 189 展开；整块只有一个状态数 `v`（0→1，460ms quart-out），盒高、圆角、封面、文字、进度条、操作组圆心、每个按钮边长、图标尺寸全读成 `mix(折叠值, 展开值, v)`；不许哪一块单独起钟，时间和喜欢只走最后 40% |
| 13 | Action node | hover | 指针一进，四个钮沿"绕着圆角"那条弧从卡片底下甩出来 | 参考稿本身是暗色档。四个圆钮平时藏在卡片右上角底下——不是淡出，是靠层叠压住（卡片 z1 盖扇形 z0，全程没有透明度通道）；贴着圆角外侧 30px 的倒角线滑出，每钮一根弹簧，起跳按 49.5ms 错开，离开倒序收回；位移能冲到 1.4 倍、缩放只到 1 |

### 2.3 表面实验室 `/surface-lab`（已 6 格，计划 9 格，舞台 372×232 起）

分类：`pop 浮层` / `drag 拖拽` / `press 按压` / `morph 形变` / `input 输入` / `reveal 揭示`。共享元素、裁切、投影是这三族的主角。

| # | 名称 | 类别 | 舞台 | 功能 | 样式与构成 |
|---|------|------|------|------|-----------|
| 1 | Popover | pop | 372×248 | 按钮和面板是同一块：点开是同一个盒子从 36 高长到 200 高，那行字跟着飞过去 | `layoutId` 共享元素形变：按钮与面板挂同一个 id，面板 Label 又与按钮文字挂同一个 id；四条量（左/上/宽/高）吃同一条弹簧（零初速线性系统里归一化进度一样），不是"淡入一层新东西" |
| 2 | Floating panel | pop | 372×288 | 面板不是从按钮里长的，是落在按钮下面；只有那行字飞过去，内容按 .2/.3 分两批进来 | 按钮 `h-9` + `px-4`、圆角 8；面板 `w-64`=256、圆角 12、挂按钮下缘再往下 8（`top: rect.bottom + 8`）；与按钮左缘对齐、整块右挪 `(372−256)/2`；1px 描边那一格要自己钉进布局（`DecoratedBox` 只画不让）；标题行 `px-4 py-2` + 14/20，正文 `p-4` 里三列 `gap-2` 的 48 圆点两行 |
| 3 | Popover form | pop | 372×232 | 面板外圈还套 4px 灰框；交完表是两块表面互相顶替 | 与 1 号同为 `layoutId` 形变，多三件事：面板自带 `p-1`，外圈那 4px 是 `--muted` 灰框（白卡只有 356×184）；页脚上沿是一条 352 的**虚线**，两端各咬一个 6×12 缺口（卡边绕着缺口弯过去）；表单提交后整张卡换成完成态表面 |
| 4 | Metal button | press | 372×232 | 金属描边钮 + 光环；条纹跟着时钟走，暂停只冻画面不冻按钮 | 参考稿是 GLSL + `destination-out` 挖洞：画满整块盒子再挖掉 `ringPx` 以内，留下贴外缘那一圈（胶囊 1px、圆钮 2px）。这里形状是精确的（两道圆角矩形差集 + 逐像素覆盖度），着色器降级为本地近似。15fps 量化时钟；画层顺序 面底色 → 1px 稳定边 → 条纹带 → 暗色发丝线 →  veil（σ13 且裁在盒内）→ 光环 → 内圈描边。糊光分四档（半线宽+2σ），并裁到"盒子外扩 ≤4px"——钮间距 12，两侧各 4 才留得住干净的一条。混合：暗底 screen、浅底 multiply |
| 5 | Dynamic island | morph | 372×344 | 一块黑盒子换档，岛贴住下沿；换档时旧内容糊 10px 退场、新内容落进来 | 宽、高、圆角是**三条独立弹簧同时走**（不是同一条进度）；内容按该档终态排版，中途只让黑盒子裁（否则途中约束会抛 RenderFlex overflow）；`large`/`long` 几何相同（371×84 r42，换的是内容）、`tall`/`medium` 相同（371×210，圆角 42 / 22） |
| 6 | Expandable | morph | 484×544 | 一颗盒子从 320×240 长到 420×480，里面三段内容各自从 0 长出自然高 | 外壳宽/高是两条独立弹簧；三段内容各自量自然高、从 0 长出，淡入按 .2s 一段段错开。底是 `bg-white` 卡片、`ring-border/50` 描边、黑底白字 tooltip，投影照 Tailwind `shadow-md`/`shadow-xl` 两层 |
| 7 | 形变面板 | morph | — | **待写**：一块表面翻成另一块（含打字态、发送态、收回延迟） | 设计已定：八档几何 + ζ=1.147/0.935/0.492 三条弹簧 + 80ms 关闭延迟（`_shellHold`），底部圆点按 lerp 跟随；golden 计划 `c07_idle/open/fly/typing/sent/closing/reduced` |
| 8 | 镂空卡 | reveal | — | **待写**：卡片上挖出镂空、内容从洞里露出来 | 未开工 |
| 9 | 文字入场 | reveal | — | **待写**：文字按位入场 | 未开工 |

9 格齐了之后再补整页 golden（`test/surface_lab_page_test.dart` 目前还不存在，`sv_page_light.png` / `sv_page_dark.png` 是留给它的）。

---

## 3. 现存 golden 数量

```
lab_*  135 张（43 格 × idle/mid/end，个别格另有加拍）
il_*   109 张（13 格，帧名按各格真实阶段命名：press/lean/stretch/overshoot/settle/…）
sv_*    42 张（6 格：5/6/7/8/9/7 张）
```

复验前先确认帧名与阶段对得上，别把没触发的帧当"动效正确"。
