# 游戏库模块（Game Library）

## 模块概述

游戏库是 SlimeWorks 的 Galgame / PC 游戏管理模块，从 LunaBox 项目迁移而来。支持：

- 游戏录入、编辑、删除
- 封面展示（本地文件 + 网络 URL）
- 元数据自动拉取（Steam / VNDB / Bangumi）
- 游戏分类（支持「最喜欢」系统分类 + 用户自定义分类）
- 游玩时间追踪（进程监听自动记录，支持手动补录）
- 游玩进度备注（章节 / 路线 / 笔记）
- 统计面板（今日 / 本周 / 总时长）

---

## 目录结构

```
lib/
  pages/game_library/
    home/          - 首页（最近游玩、统计卡）
    library/       - 游戏列表（网格视图）
    detail/        - 游戏详情（统计、编辑、启动、分类、进度 5 个 Tab）
    categories/    - 分类管理
    settings/      - 设置页
    stats/         - 统计页
    models/        - 数据模型（GameItem、PlaySession 等）
  core/services/
    game_library_service.dart        - 业务逻辑（SharedPreferences 持久化）
    game_library_metadata_api.dart   - 元数据 API（Steam、VNDB、Bangumi）
    game_process_tracker.dart        - 游戏进程生命周期追踪 ← 新增
  view_models/game_library/
    game_library_library_viewmodel.dart  - 游戏列表 VM
    game_library_detail_viewmodel.dart   - 游戏详情 VM
    game_library_home_viewmodel.dart     - 首页 VM
    game_library_categories_viewmodel.dart
    game_library_stats_viewmodel.dart
    game_library_settings_viewmodel.dart
```

---

## 核心数据模型

### GameItem

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | UUID |
| `name` | String | 游戏名 |
| `coverPath` | String | 封面路径（本地文件 or HTTP URL）|
| `company` | String | 开发商 |
| `summary` | String | 简介 |
| `rating` | double | 评分 (0–10) |
| `releaseDate` | String | 发售日期 |
| `path` | String | **默认启动 exe 路径** |
| `exePaths` | List\<String\> | 游戏目录下的所有顶层 exe（批量导入时填写） |
| `gameDir` | String | 游戏根目录（用于设置工作目录，批量导入时填写） |
| `status` | GameStatus | 游玩状态（未开始/游玩中/已通关/搁置/弃坑）|
| `totalPlayTimeSec` | int | 累计游玩秒数 |
| `lastPlayedAt` | DateTime? | 最近游玩时间 |
| `tags` | List\<String\> | 标签 |

---

## 批量导入流程

**批量导入** 按钮选择「包含多个游戏的父目录」（如 `D:\Games\`），逻辑如下：

1. 扫描父目录的**直属子目录**（不递归）
2. 对每个子目录，检查是否有**顶层 exe 文件**（不递归进子目录）
3. 有 exe 的子目录视为候选游戏文件夹，用**文件夹名**调用元数据 API 搜索
4. API 有返回结果 → 确认为游戏文件夹，自动录入（包含封面、公司、简介等元数据）
5. API 无返回 → 跳过（可手动添加）
6. 每个游戏文件夹**只录入一次**，所有顶层 exe 存入 `exePaths`
7. `path` 字段自动选当前最合适的默认 exe（优先与文件夹同名，其次文件名最短）

> 拖拽导入同样支持此逻辑（拖入父目录时扫描子目录）。

---

## 游戏启动

### 工作目录修复

旧逻辑直接 `Process.start(path, [])` 不设置工作目录，导致游戏找不到相对路径资源，报错退出。

新逻辑：
- **gameDir 不为空**（批量导入的游戏）→ 使用 `gameDir` 作为工作目录
- **gameDir 为空**（手动添加的游戏）→ 使用 `File(path).parent.path`（exe 所在目录）

### 多 exe 选择

详情页「启动」Tab 展示 `exePaths` 列表：

- 当前默认 exe 标星显示
- 每行可点击「**启动**」单独启动该 exe
- 可点击「**设为默认**」将其设为 `path`，后续一键启动使用该 exe
- 从游戏卡片菜单启动时：若有多 exe 但无默认，弹出选择对话框

---

## 游玩时间追踪

由 `GameProcessTracker`（GetIt 单例）负责：

1. 调用 `launchAndTrack()` → 启动进程，记录 `startTime`，将 `gameId` 加入 `runningGameIds`
2. 监听 `process.exitCode` Future（进程退出时自动触发）
3. 退出后自动调用 `GameLibraryService.addPlaySession(startTime, endTime)`，更新 `totalPlayTimeSec` 并改状态至「游玩中」

### 运行中状态显示

- **游戏列表卡片**：封面上方显示半透明遮罩 + 加载圈 + "游戏运行中"文字
- **游戏详情页头部**：启动按钮变为绿色禁用状态，显示"游戏运行中..."
- **启动 Tab**：顶部绿色提示卡"游戏运行中... 退出后将自动记录游玩时间"

状态通过 GetX `RxSet<String> runningGameIds` 响应式驱动，所有 `Obx()` 自动更新，无需手动 setState。

---

## 关键服务

### GameLibraryService
- 数据持久化：`SharedPreferences`（JSON 序列化）
- 提供 `addPlaySession`、`getPlaySessionsByGameId`、`addGame`、`updateGame` 等接口

### GameLibraryMetadataApi
- 搜索顺序：Steam → VNDB → Bangumi（短路：第一个有结果即返回）
- 超时：5 秒连接 + 5 秒接收

### GameProcessTracker
- GetIt 懒加载单例
- `runningGameIds: RxSet<String>` — 当前运行游戏集合（响应式）
- `sessionSavedCount: RxInt` — 每保存一次 session 自增，VM 通过 `ever()` 订阅触发刷新
