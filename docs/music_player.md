# 音乐播放器模块（Music Player）

## 简介

音乐播放器模块用于管理和播放本地及远程节点上的音乐文件。支持播放列表管理、黑胶唱片动效、封面背景模糊（网易音乐风格）、CUE 文件解析、嵌入封面提取、均衡器、收藏、最近播放等功能。核心存储与扫描逻辑由 Rust 的 `music_player` 模块实现，节点功能支持移动端通过 HTTP 请求获取远程设备的音乐列表。

## 文件位置

### Flutter UI 层

| 文件 | 说明 |
|------|------|
| `lib/pages/music_player/music_player_screen.dart` | 主页面（桌面端左右分栏，移动端全屏+底部控制栏） |
| `lib/pages/music_player/components/vinyl_disc_animation.dart` | 黑胶唱片动效组件（旋转唱片+唱臂动画） |
| `lib/pages/music_player/components/music_list_item.dart` | 音乐列表条目（封面、标题、播放指示器动效） |
| `lib/pages/music_player/components/playlist_sidebar.dart` | 播放列表侧边栏（桌面端左侧） |
| `lib/pages/music_player/components/player_controls.dart` | 播放控制按钮组（播放模式、上下曲、进度条） |
| `lib/pages/music_player/components/eq_panel.dart` | 均衡器面板（10 段均衡器+预设管理） |
| `lib/view_models/music_player_viewmodel.dart` | ViewModel（播放列表、播放状态、导入、搜索） |
| `lib/view_models/music_player_vm_remote.dart` | 远程节点数据访问扩展 |
| `lib/core/routes/routes/music_player_routes.dart` | GoRouter 路由定义（`/music`） |

### Rust 层

| 文件 | 说明 |
|------|------|
| `rust/music_player/src/types.rs` | 数据结构定义（Playlist, MusicItem, CueSheet 等） |
| `rust/music_player/src/scanner.rs` | 音频文件扫描、CUE 文件解析、封面查找 |
| `rust/music_player/src/api.rs` | CRUD API、封面缩略图生成、批量封面提取 |
| `rust/src/api/music_player.rs` | FRB 绑定层（FFI 类型转换，i64 时间戳） |
| `rust/src/node_server/handlers.rs` | 节点服务器 action 分发（18 个音乐播放器 action） |

## 数据模型

### `Playlist`（播放列表）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `name` | `String` | 播放列表名称 |
| `cover_path` | `Option<String>` | 封面图路径 |
| `item_count` | `u64` | 音乐数量 |
| `created_at` / `updated_at` | `DateTime<Utc>` | 创建/更新时间 |
| `is_default` | `bool` | 是否为默认列表（不可删除） |

### `MusicItem`（音乐条目）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `playlist_id` | `String` | 所属播放列表 |
| `title` | `String` | 标题 |
| `artist` | `Option<String>` | 艺术家 |
| `album` | `Option<String>` | 专辑 |
| `file_path` | `String` | 文件绝对路径 |
| `duration_ms` | `Option<u64>` | 时长（毫秒） |
| `track_number` | `Option<u32>` | 音轨号 |
| `disc_number` | `Option<u32>` | 碟片号 |
| `year` | `Option<i32>` | 年份 |
| `genre` | `Option<String>` | 流派 |
| `cover_path` | `Option<String>` | 封面路径 |
| `file_size` | `u64` | 文件大小（字节） |
| `modified_at` | `DateTime<Utc>` | 文件修改时间 |
| `order` | `i32` | 列表内排序 |
| `is_favorite` | `bool` | 是否收藏 |

### `CueSheet` / `CueTrack`（CUE 文件）

| 字段 | 类型 | 说明 |
|------|------|------|
| `file_path` | `String` | CUE 文件路径 |
| `title` | `Option<String>` | 专辑标题 |
| `performer` | `Option<String>` | 表演者 |
| `tracks` | `Vec<CueTrack>` | 音轨列表 |

### `PlayRecord`（播放记录）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `music_id` | `String` | 音乐 ID |
| `played_at` | `DateTime<Utc>` | 播放时间 |
| `play_count` | `u32` | 累计播放次数 |

### `EqualizerPreset`（均衡器预设）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | UUID |
| `name` | `String` | 预设名称 |
| `bands` | `Vec<f32>` | 10 段增益值（-12 ~ +12 dB） |
| `is_builtin` | `bool` | 是否为内置预设 |

## 核心功能

### 1. 播放列表管理

- 创建/重命名/删除播放列表
- 首次启动自动创建"默认列表"（`is_default = true`，不可删除）
- 桌面端左侧侧边栏展示，移动端通过底部导航访问

### 2. 音乐导入

| 导入方式 | 调用函数 | 说明 |
|----------|----------|------|
| 文件选择器 | `pickAndImportFiles()` | 支持多选，过滤音频扩展名 |
| 文件夹选择器 | `pickAndImportFolder()` | 递归扫描子目录 |
| 拖拽导入 | `importDroppedPaths()` | 自动区分文件/文件夹 |
| 单文件导入 | `importMusicFile()` | Rust 层直接导入 |

导入流程：
1. 扫描音频文件（`scanner::scan_audio_files`）
2. 解析 CUE 文件并合并元数据（`scan_cue_files` + `find_cue_for_item`）
3. 保存到数据库（`db_set`）
4. 后台异步提取嵌入封面（`batch_extract_covers`，ffmpeg）
5. 导入状态实时反馈（`isImporting` + `importingStatus`）

### 3. 黑胶唱片动效

- 播放时唱片旋转（8 秒一圈），唱臂摆到唱片上方
- 暂停时唱片停止旋转，唱臂移开
- 唱片中心显示封面图（圆形裁剪）
- 封面背景模糊（`ImageFilter.blur(sigmaX: 20, sigmaY: 20)`）

### 4. 播放控制

| 功能 | 说明 |
|------|------|
| 播放/暂停 | `togglePlayPause()` |
| 上一曲/下一曲 | `playPrevious()` / `playNext()` |
| 播放模式切换 | 顺序 → 列表循环 → 单曲循环 → 随机 |
| 进度条拖拽 | `seekTo(positionMs)` |
| 自动切歌 | 歌曲播放完毕后根据播放模式自动切换 |

> 注：当前为模拟播放（`Timer.periodic` 驱动进度条），实际音频播放需接入 `just_audio` 等播放器库。

### 5. 封面提取

| 方式 | 优先级 | 说明 |
|------|--------|------|
| 目录封面文件 | 高 | `cover.jpg`, `folder.jpg`, `front.jpg` 等 |
| ffmpeg 嵌入封面 | 低 | `ensure_music_cover_thumbnail()`，生成 300px 缩略图缓存 |

封面缩略图缓存路径：`{appData}/SlimeWorks/library/music/covers/{hash}_w300.jpg`

### 6. CUE 文件解析

- 自动查找与音频同名的 `.cue` 文件
- 解析 `TITLE`、`PERFORMER`、`TRACK` 等标签
- 合并音轨信息到 `MusicItem`

### 7. 节点功能（远程访问）

移动端通过 `NodeSettingsService.callNodeAction` 访问远程节点的音乐数据：

| Action | 说明 |
|--------|------|
| `music_list_playlists` | 获取远程播放列表 |
| `music_get_playlist_items` | 获取远程音乐列表 |
| `music_import_folder` | 远程导入文件夹 |
| `music_toggle_favorite` | 切换远程收藏 |
| ... | 共 18 个 action |

远程播放列表 ID 以 `remote-music:` 前缀标识。

### 8. 均衡器

- 10 段均衡器：32Hz ~ 16kHz
- 6 个内置预设：平坦、低音增强、高音增强、人声增强、摇滚、古典
- 支持保存自定义预设

### 9. 收藏与最近播放

- 切换收藏状态（`toggle_favorite`）
- 收藏列表（`get_favorite_items`）
- 播放计数与时间记录（`record_play` / `get_recent_played`）

## 数据库表

| 表名 | Key | Value |
|------|-----|-------|
| `music_playlists` | 播放列表 ID | `Playlist` JSON |
| `music_items` | 音乐条目 ID | `MusicItem` JSON |
| `music_play_records` | 记录 ID | `PlayRecord` JSON |
| `music_eq_presets` | 预设 ID | `EqualizerPreset` JSON |

使用 `db_module`（redb KV 存储），通过 `db_set`/`db_get`/`db_list_all`/`db_delete`/`db_register_table` 操作。

## 内存缓存

| 缓存 | 类型 | 策略 |
|------|------|------|
| `playlists_cache` | `OnceLock<Mutex<Option<Vec<Playlist>>>>` | 写入后清空，读取时重建 |
| `music_items_cache` | `OnceLock<Mutex<Option<Vec<MusicItem>>>>` | 同上 |

## FRB 绑定层

位于 `rust/src/api/music_player.rs`，负责：

- Rust `DateTime<Utc>` ↔ Dart `i64` 时间戳转换
- Rust `Vec<f32>` ↔ Dart `List<double>` 均衡器频段
- 24 个公开 FFI 函数（`#[frb(sync)]` 标注同步函数）
- `usize` 自动映射为 Dart `BigInt`

## 路由

| 路由 | 页面 | 侧边栏分组 |
|------|------|------------|
| `/music` | `MusicPlayerScreen` | `music`（sort: 42） |

侧边栏图标：`assets/image/svg/menu_music_player.svg`（音符图标）

## 已知限制与后续计划

| 项目 | 状态 | 说明 |
|------|------|------|
| 实际音频播放 | 待实现 | 需接入 `just_audio` 或 `audioplayers` 库 |
| 歌词显示 | 待实现 | LRC 文件解析 + 逐行高亮 |
| 音频元数据解析 | 部分 | 当前仅从 CUE 和文件名提取，需 ffprobe 完整解析 |
| 播放进度持久化 | 待实现 | 记忆上次播放位置 |
| 均衡器实时调节 | 待实现 | 需实际音频播放器支持 |
