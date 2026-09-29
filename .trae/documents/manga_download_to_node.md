# 漫画章节下载到节点

## Context

阅读器的「下载」弹层目前只能把章节下载到本机。用户希望在下载时可选一个已连接的节点，把章节下载到**节点的媒体库目录**。动机：漫画代理通道通常只有下载设备能访问，远程设备可能因网络问题拉不到图片，所以必须由本机完成下载后，再把成果推送到节点。

已与用户确认的决策：
- 推送成功后**删除本地**章节文件（调用现有 `deleteDownload`，同时清理下载记录）；
- 目标目录 = **节点媒体库文件夹**（含「媒体库根目录」选项），复用现有 `resolve_folder_upload_target` 反推磁盘落点；
- 打包粒度 = **每章一个 zip**，逐章增量：下载完成 → 打包 → 上传 → 节点解压导入 → 删本地。

顺带说明：本次会话早期已修复 `_showMoreMenu` 中点击「下载」时 `_isBottomSheetOpen` 未释放、导致下载弹层不弹出的 bug（manga_reader_screen.dart:322-327），与本功能无耦合。

## 现有可复用链路（不要重造）

- 打包：`extract_api.zipDirectoryToTmp(srcDir: dir, entryRoot: 名称)` → 本地目录打成 zip（media_library_vm_collections.dart:793 同款用法）。
- 上传+节点解压：`NodeSettingsService.uploadArchiveToNode(nodeId, zipPath, destDir)` → 节点 `POST /node/upload/archive?dest=`（upload_handler.rs，流式落盘 + `extract_archive`）。
- 节点导入媒体库：`NodeSettingsService.importNodeMediaFolder(nodeId, folderPath, {generateThumbnails, baseFolderId})` → 节点 `import_media_folder` action（handlers.rs:255）。
- 节点目录选择：`fetchNodeMediaFolders(node)`（node_settings_service.dart:759）列库内文件夹；`resolveNodeUploadTarget(nodeId, folderId)`（:1030）反推磁盘目录，歧义时返回 `candidates`。
- 节点列表：`NodeSettingsService.enabledNodes`（:372）。
- 本地章节目录：`{doc}/manga_downloads/{comicId}/{epsOrder}/p{index}.jpg`（manga_download_service.dart 内部 `_epsDir`）。
- 整条"本地目录→zip→上传→导入"的参照实现：`importPathsToNodeFolder`（media_library_vm_collections.dart:747-860）。

## 实现步骤

### 1. 服务层：`MangaDownloadService`（lib/core/services/manga_download_service.dart）

新增（依赖注入 `getIt<NodeSettingsService>()`，懒取，不在构造器里强依赖）：

- 进度 Rx：`nodePushRunning`(RxBool)、`nodePushStage`(RxString，如「下载 2/10 · 打包 · 上传 · 节点导入」)、`nodePushDone/Total`。
- 入口 `downloadEpsToNode(MangaComic comic, List<MangaEps> epsList, {required String nodeId, required String targetDir, String? baseFolderId})`：
  1. 逐个 `downloadEps` 入本地队列；
  2. 新增私有 `_waitEpsDone(comicId, epsOrder)`：监听 `entries[comicId].episodes[epsOrder]` 状态直到 `completed`/`error`（带超时），复刻现有 `_downloadEpsImpl` 的完成语义；
  3. 每章 completed 后走 `_pushEpsToNode`：`_epsDir` → `zipDirectoryToTmp(srcDir: epsDir, entryRoot: 清洗后的章节名)` → `uploadArchiveToNode(destDir: targetDir)` → `importNodeMediaFolder(folderPath: 节点路径拼接(targetDir, 章节名), generateThumbnails: true, baseFolderId: baseFolderId)` → 删除临时 zip → 成功则 `deleteDownload(comicId, epsOrder)`（删本地+清记录）；失败保留本地并累计错误；
  4. 全部结束后置 `nodePushRunning=false`，返回 `(成功数, 失败数)` 汇总。
- 私有小工具：节点路径拼接（兼容 `/` 与 `\`，参考 media_library_vm_collections.dart 的 `_joinNodePath` 实现思路，但复制为服务内私有方法）；章节名清洗（去掉 Windows 非法字符 `\ / : * ? " < > |`，空则退回 `第{order}话`）。

### 2. 阅读器 UI：`_showDownloadSheet`（lib/pages/manga/reader/manga_reader_screen.dart）

在标题 Row 下方新增一行目标选择（`SegmentedButton` 或两个 `ChoiceChip`）：**本机 / 节点**。

节点模式下显示两行选择器：
- 「节点」行 → 弹层列出 `enabledNodes`（名称 + 地址），选中即记录 `nodeId`；
- 「目标目录」行 → 弹层列出节点媒体库文件夹（`fetchNodeMediaFolders`）+ 置顶「媒体库根目录」项；选中文件夹后调 `resolveNodeUploadTarget`：
  - `targetDir` 非空 → 直接采用；
  - `targetDir` 为空但 `candidates` 非空 → 弹出候选目录列表让用户确认；
  - 两者皆空 → 提示「节点媒体库为空」。
  - 根目录项 → 以空 folderId 走 `resolveNodeUploadTarget`（依赖第 3 步的 Rust 放宽），同样按候选逻辑处理。
- 记录 `(nodeId, targetDir, baseFolderId)`，行内显示已选节点名 + 目录名。

「下载 N 章」按钮：本机模式保持现状 `downloadEpsMultiple`；节点模式下按钮启用需 `nodeId`+`targetDir` 齐备，点击后：
- `Navigator.pop()` 关闭弹层 → `dl.downloadEpsToNode(...)`；
- 同时 `showDialog(barrierDismissible: false)` 弹一个绑定 `dl.nodePushStage/nodePushRunning` 的进度对话框（小 StatefulWidget，监听 Rx 刷新文本），`nodePushRunning` 变 false 自动关闭；
- 结束后用文件内既有 toast 方式（`ScaffoldMessenger`/EasyLoading）汇总「成功 N 章，失败 M 章」。

弹层锁注意：下载弹层打开期间 `_isBottomSheetOpen` 为 true，内部的节点/目录选择是**嵌套弹层**，必须用独立的标志位（如 `_isSubPickerOpen`）或直接不加锁，避免被 `if (_isBottomSheetOpen) return` 拦掉。

### 3. Rust：根目录支持（rust/src/node_server/handlers.rs）

`resolve_folder_upload_target`（:346）目前对空 `folder_id` 直接报错。放宽为空 folderId 表示「媒体库根目录」：`pick_folder_target_dir("", ...)`（:1380）在 folder_id 无匹配集合时会返回 `("", all_parents)`（所有集合父目录 = 库根目录候选），正好符合需求。

- 去掉 handler 里的空值校验，让空 folderId 走 `resolve_folder_target_dir`；
- 更新测试 `resolve_folder_upload_target_requires_folder_id`（:1663）：空/空白 folderId 从「报错」改为「返回空 targetDir + 库根候选」。

### 4. iOS 兼容（本功能硬性要求）

已核实：`extract_module`（打包用 `zipDirectoryToTmp`）与 `manga_module`（下载用 `rust.mangaFetchImage`）都是 `rust_lib_slime_works` 的**无条件依赖**（rust/Cargo.toml:71、125），iOS 构建同样编译；仅 whisper/asr/symphonia 是桌面端独占（Cargo.toml:95）。因此本功能全链路在 iOS 可用，**不需要** Dart 侧 zip 兜底（pubspec 也无 archive 包，勿引入）。

实现时的 iOS 约束：
- **下载**：复用现有 `downloadEps`/`downloadEpsMultiple` 全链路（FFI 下载 + `getApplicationDocumentsDirectory()/manga_downloads/...`，iOS 沙箱内一致），本功能不新增桌面端专属逻辑。
- **打包**：直接用 `extract_api.zipDirectoryToTmp`（FRB，iOS 已编译 extract_module）；**不要**用 `PlatformUtil.isDesktop` 之类守卫把节点推送功能在移动端藏起来。
- **上传/导入**：`uploadArchiveToNode` 走 Dio 流式（纯 Dart HTTP）+ `importNodeMediaFolder` 走 `/node/call`，iOS 可用。
- **UI**：下载弹层新增的目标选择/节点选择/目录选择行须适配移动端窄屏（全宽行、文本 Expanded 截断），弹层本身已是 `isScrollControlled`，无桌面依赖。

### 5. 校验

- `flutter analyze`；
- `cd rust && cargo test`（重点 resolve_folder_upload_target 相关）；
- 桌面手动联调：节点设置里添加一个可用的远程节点 → 阅读器下载弹层切「节点」→ 选节点 → 选媒体库文件夹（或根目录）→ 选章节下载 → 观察进度对话框走完「下载→打包→上传→节点导入」→ 节点媒体库出现对应漫画集合、本地 `manga_downloads` 对应章节目录被删除；
- iOS 验证：`flutter run -d ios`（或按项目 iOS CI 流程出真机构建包），在 iOS 上跑一遍同一流程——确认下载弹层正常、打包不报错（extract_module FFI 可用）、Dio 上传与节点导入成功。
