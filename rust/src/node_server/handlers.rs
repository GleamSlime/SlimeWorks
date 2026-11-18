use super::types::*;
use super::NodeServerConfig;
use hyper::{Body, Request, Response};
use media_collection::api as media_api;
use music_player as music_api;
use novel_reader::api as novel_api;
use serde_json::{json, Value};
use std::convert::Infallible;
use std::fs;
use std::path::{Path, PathBuf};

// ── 流水账（ledger）动作的公共收口 ────────────────────────────────────────────

fn s_field(params: &Value, key: &str) -> String {
    params[key].as_str().unwrap_or("").to_string()
}

fn i_field(params: &Value, key: &str) -> i64 {
    params[key].as_i64().unwrap_or(0)
}

fn b_field(params: &Value, key: &str) -> bool {
    params[key].as_bool().unwrap_or(false)
}

fn u_field(params: &Value, key: &str) -> u64 {
    params[key].as_u64().unwrap_or(0)
}

/// 收信与连接自检走的是 std::net 的阻塞 TLS，必须挪出 tokio worker 线程
async fn ledger_blocking<T>(what: &str, f: impl FnOnce() -> Result<T, String> + Send + 'static) -> Result<T, String>
where
    T: Send + 'static,
{
    tokio::task::spawn_blocking(f)
        .await
        .map_err(|e| format!("{}后台任务失败: {}", what, e))?
}

/// 节点侧账本兜底：桌面端从没打开过记账页时，用本节点数据目录自己开一份，
/// 否则移动端第一次调用只会吃一句"未初始化"。
fn ensure_ledger_ready() -> Result<(), String> {
    if ledger_module::api::ledger_is_ready() {
        return Ok(());
    }
    let path = get_app_data_path("ledger/ledger.db");
    let cfg = json!({ "db_path": path.to_string_lossy().to_string() });
    ledger_module::api::ledger_init(cfg.to_string())?;
    Ok(())
}

// ── 其它全局模块的惰性兜底 ───────────────────────────────────────────────────
// 这几家的单例都由「桌面端页面打开时」初始化，而无头节点从来不跑 Flutter，
// 于是全新 `--data-dir` 起一个节点后它们的 action 全部回「模块未初始化」：
// 客户端 `checkNodeXxxAvailable` 探测失败 → 页面显示「该节点不支持此功能」，
// 功能在远程模式下彻底不可用，且没有任何操作能让它跑起来。
//
// 这里一律仿 `ensure_ledger_ready`：第一次被调用时用本节点数据目录自己开一份。
// 惰性而不是启动时全量 init 的理由：节点可能只用来存媒体，没必要为三个从没被
// 用过的模块各建一套库；真要用时再付这一次开销。
//
// ★ 验收必须用**全新空 data-dir** 起的节点跑，否则模块单例是热的，症状会被
//   完全掩盖 —— 这正是这条缺陷长期没被发现的原因。

/// 阿里云 DDNS 兜底：无配置时用一份关闭态的空配置初始化。
/// 用户未配置 DDNS 时也应当能「打开页面看到空状态」，而不是看到「不支持」。
fn ensure_aliyun_ready() -> Result<(), String> {
    // 没有 is_ready 探针，用 get_status 的返回判断：未初始化会直接 Err。
    match aliyun_module::api::aliyun_ddns_get_status() {
        Ok(_) => return Ok(()),
        // 只有「未初始化」才兜底；其它错误（配置损坏等）要原样透出，
        // 不要在兜底里把它盖成一句成功。
        Err(e) if !e.contains("未初始化") => return Ok(()),
        Err(_) => {}
    }
    let cfg = json!({
        // 必填字段必须给全：DdnsConfig 的 access_key_id/secret 没有 serde default，
        // 少给一个就变成「解析DDNS配置失败」，等于又一次「功能不可用」。
        "access_key_id": "",
        "access_key_secret": "",
        "watch_domains": [],
        "interval_secs": 300,
        "enabled": false,
    });
    aliyun_module::api::aliyun_ddns_init(cfg.to_string())?;
    Ok(())
}

/// 电力统计兜底：节点是无头常驻的，理应持久化（persist=true + 独立 db_path），
/// 否则每次重启节点历史读数全丢。
fn ensure_power_stats_ready() -> Result<(), String> {
    match power_stats::api::power_stats_get_status() {
        Ok(_) => return Ok(()),
        Err(e) if !e.contains("未初始化") => return Ok(()),
        Err(_) => {}
    }
    let db_path = get_app_data_path("power_stats/power_stats.db");
    let cfg = json!({
        // meter_id 是必填（无 serde default），给空串表示「还没配置电表」，
        // 页面据此显示空状态，而不是报「解析配置失败」。
        "meter_id": "",
        "persist": true,
        "db_path": db_path.to_string_lossy().to_string(),
        "enabled": false,
        "interval_secs": 60,
    });
    power_stats::api::power_stats_init(cfg.to_string())?;
    Ok(())
}

/// Sentry 日志存储兜底：节点侧自建一份，供客户端远程查看。
fn ensure_sentry_ready() -> Result<(), String> {
    if sentry_log::api::sentry_log_is_ready() {
        return Ok(());
    }
    let db_path = get_app_data_path("sentry_log/sentry_log.redb");
    sentry_log::api::sentry_log_init(db_path.to_string_lossy().to_string())?;
    Ok(())
}

/// ledger 的 FFI 面统一是 JSON 文本，这里集中解码并把错误文案包好
fn ledger_json(raw: Result<String, String>, what: &str) -> Result<Value, String> {
    let text = raw.map_err(|e| format!("{}失败: {}", what, e))?;
    serde_json::from_str(&text).map_err(|e| format!("解析{}结果失败: {}", what, e))
}

fn ledger_text(raw: Result<String, String>, what: &str) -> Result<Value, String> {
    let text = raw.map_err(|e| format!("{}失败: {}", what, e))?;
    Ok(json!({ "text": text }))
}

fn ledger_scalar(raw: Result<i64, String>, key: &str, what: &str) -> Result<Value, String> {
    let v = raw.map_err(|e| format!("{}失败: {}", what, e))?;
    Ok(json!({ key: v }))
}

fn ledger_flag(raw: Result<bool, String>, what: &str) -> Result<Value, String> {
    let v = raw.map_err(|e| format!("{}失败: {}", what, e))?;
    Ok(json!({ "value": v }))
}

fn ledger_void(raw: Result<(), String>, what: &str) -> Result<Value, String> {
    raw.map_err(|e| format!("{}失败: {}", what, e))?;
    Ok(json!({ "ok": true }))
}

// ── mutation 动作的结果收口 ──────────────────────────────────────────────────
// media_collection / novel_reader 的一批写接口统一返回 `Result<bool, String>`：
// 只有真正改到了数据才回 true，false 表示「目标不存在、什么都没动」。
// 早期 handler 用 `.map_err(...)?` 把 bool 直接丢掉，再无条件回 `{"ok": true}`，
// 于是对不存在的 id 做重命名/删除/移动时节点回 success:true，而数据毫无变化
// —— 正是用户报的「提示操作成功、实际数据没变」。下面几个小函数统一把 false
// 翻成带具体 id 的中文错误，避免再逐个漏掉。

/// 必填 ID 参数校验：空 id 直接报错，别让错误文案里留一个空 id
fn require_id(id: &str, subject: &str) -> Result<(), String> {
    if id.trim().is_empty() {
        return Err(format!("{} ID 不能为空", subject));
    }
    Ok(())
}

/// 把 `Result<bool, String>` 的 false 翻成「<对象>不存在 <id>」错误。
/// `what` 沿用各分支原有的错误前缀（如「删除文件夹失败」），`missing` 由调用方
/// 拼好带 id 的赘述（如「文件夹不存在 media_folder_x」）。
fn require_changed(raw: Result<bool, String>, what: &str, missing: String) -> Result<(), String> {
    let changed = raw.map_err(|e| format!("{}失败: {}", what, e))?;
    if !changed {
        return Err(format!("{}失败: {}", what, missing));
    }
    Ok(())
}

/// 媒体文件夹存在性校验（media_collection 没有单个查询接口，只能查全表：
/// 文件夹是小表，全量取一次比让调用方拼出幽灵父子关系便宜）。
fn ensure_media_folder_exists(folder_id: &str, what: &str) -> Result<(), String> {
    require_id(folder_id, "文件夹")?;
    let exists = media_api::get_all_media_folders()
        .map_err(|e| format!("{}失败: {}", what, e))?
        .iter()
        .any(|folder| folder.id == folder_id);
    if !exists {
        return Err(format!("{}失败: 文件夹不存在 {}", what, folder_id));
    }
    Ok(())
}

/// 小说文件夹存在性校验。
///
/// novel_reader 没有单查文件夹的接口，只能 `get_all_folders()` 全量取一次比对
/// ——文件夹是小表，全量取一次比让调用方拼出「parent_id 指向幽灵夹」或者把
/// 不存在的夹当「删成功」便宜。给这几类底层接口用：
/// `delete_folder_with_novels` 回 `Result<()>`（不存在也是静默 no-op）、
/// `create_child_folder` 不校验父夹、`move_novel_to_folder` 不校验目标夹。
fn ensure_novel_folder_exists(folder_id: &str, what: &str) -> Result<(), String> {
    require_id(folder_id, "小说文件夹")?;
    let exists = novel_api::get_all_folders()
        .map_err(|e| format!("{}失败: {}", what, e))?
        .iter()
        .any(|folder| folder.id == folder_id);
    if !exists {
        return Err(format!("{}失败: 小说文件夹不存在 {}", what, folder_id));
    }
    Ok(())
}

/// 小说文件夹 → 节点 JSON。
/// 字段风格与 `list_media_folders` 对齐：created_at 用 Unix 秒（本地 FFI 也是秒）。
fn novel_folder_json(folder: novel_reader::types::NovelFolder) -> Value {
    json!({
        "id": folder.id,
        "name": folder.name,
        "created_at": folder.created_at.timestamp(),
        "order": folder.order,
        "parent_id": folder.parent_id,
    })
}

/// 媒体集合存在性校验：给「底层不报缺失」的接口用
/// （`delete_collection_local_files` 对不存在的集合只会回 deleted:0）。
fn ensure_media_collection_exists(collection_id: &str, what: &str) -> Result<(), String> {
    require_id(collection_id, "集合")?;
    let exists = media_api::get_all_media_collections()
        .map_err(|e| format!("{}失败: {}", what, e))?
        .iter()
        .any(|collection| collection.id == collection_id);
    if !exists {
        return Err(format!("{}失败: 集合不存在 {}", what, collection_id));
    }
    Ok(())
}

/// 分发动作到对应的处理函数
pub async fn dispatch_action(
    action: &str,
    params: Value,
    config: &NodeServerConfig,
) -> Result<Value, String> {
    // 账本动作统一先确保库已打开：移动端不会替节点做初始化，兜底见 ensure_ledger_ready
    if action.starts_with("ledger_") {
        ensure_ledger_ready()?;
    }
    // 其它全局模块同理：无头节点不跑 Flutter，这些单例没人初始化。
    // 不兜底的话，全新 data-dir 起的节点上这些功能一律「模块未初始化」，
    // 客户端探测后会把整块功能判成「该节点不支持」（见各 ensure_* 的注释）。
    if action.starts_with("aliyun_") {
        ensure_aliyun_ready()?;
    }
    if action.starts_with("power_stats_") {
        ensure_power_stats_ready()?;
    }
    if action.starts_with("sentry_") {
        ensure_sentry_ready()?;
    }
    match action {
        // ── 状态查询 ─────────────────────────────────────────────────────────
        "ping" => Ok(json!({"pong": true})),

        "get_status" => Ok(json!({
            "name": config.name,
            "port": config.port,
            // 协议版本，客户端据此判断接口兼容性
            "version": "1.0",
            // 节点构建版本（形如 1.0.0+20261117.abcdef），用于对比是否该更新
            "build_version": crate::build_version::BUILD_VERSION,
        })),

        // ── 系统指标 ─────────────────────────────────────────────────────────
        // 客户端处于全局远程节点模式时，概览面板显示的必须是节点机器的指标，
        // 不能是本机进程的。字段与 FRB 的 SystemResourceSnapshot 一一对应。
        "get_system_metrics" => {
            let snapshot = crate::api::system_metrics::get_system_resource_snapshot()
                .map_err(|e| format!("采集系统指标失败: {}", e))?;
            Ok(json!({
                "cpu_usage_percent": snapshot.cpu_usage_percent,
                "memory_used_mb": snapshot.memory_used_mb,
                "memory_total_mb": snapshot.memory_total_mb,
                "rx_kbps": snapshot.rx_kbps,
                "tx_kbps": snapshot.tx_kbps,
            }))
        }

        // ── 设备唤醒 ─────────────────────────────────────────────────────────
        // 魔术包必须从目标主机所在局域网发出，外网客户端经此动作中继
        "wake_host" => {
            let mac = s_field(&params, "mac");
            let target = s_field(&params, "target");
            let port = params["port"].as_u64().unwrap_or(9) as u16;
            let count = params["count"].as_u64().unwrap_or(3) as u8;
            let result = tokio::task::spawn_blocking(move || {
                super::wake::send_magic_packet(&mac, &target, port, count)
            })
            .await
            .map_err(|e| format!("唤醒任务失败: {}", e))?;
            let (target, sent) = result?;
            Ok(json!({ "target": target, "sent": sent }))
        }

        // ── 媒体集合操作 ─────────────────────────────────────────────────────
        // 节点端缩略图生成进度（客户端轮询展示状态，移动端经节点取数时同样可见）
        "get_thumb_progress" => {
            let (total, completed) = super::media_handler::thumb_generation_progress();
            Ok(json!({
                "total": total.to_string(),
                "completed": completed.to_string(),
            }))
        }

        // ── 视频/音频振幅（波形）─────────────────────────────────────────
        // 客户端只要几 KB 的 JSON：解码在本节点做，绝不让客户端（尤其移动端）
        // 把整段视频拉过去自己跑 ffmpeg。
        // read=只读缓存（没有就回 null，不触发计算）；ensure=没有则生成并落盘。
        "read_media_waveform" | "ensure_media_waveform" => {
            let file_path = params["file_path"].as_str().unwrap_or("").to_string();
            if file_path.is_empty() {
                return Err("missing file_path".to_string());
            }
            let bins = params["bins"].as_u64().unwrap_or(1200) as u32;
            let data = if action == "read_media_waveform" {
                crate::api::media_collection::read_video_waveform(file_path, bins)
            } else {
                crate::api::media_collection::ensure_video_waveform(file_path, bins)
                    .map_err(|e| format!("生成振幅失败: {}", e))?
                    .into()
            };
            Ok(json!({ "data": data, "bins": bins }))
        }

        // 重新扫描封面：客户端指定范围（集合 id 列表 / 文件夹子树 / 不传=全部），
        // 后台按客户端封面宽度补生成缺失的封面，进度由 get_thumb_progress 上报。
        // force=true 为覆盖模式：先清掉这些集合已有的节点缩略图缓存再重生成。
        "rescan_media_covers" => {
            let width = params["width"].as_u64().unwrap_or(240) as u32;
            let force = params["force"].as_bool().unwrap_or(false);
            let collections = media_api::get_all_media_collections()
                .map_err(|e| format!("获取媒体集合失败: {}", e))?;
            let wanted_ids: Option<std::collections::HashSet<String>> = params
                ["collection_ids"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str())
                        .map(|s| s.to_string())
                        .collect()
                });
            let targets: Vec<_> = if let Some(wanted) = wanted_ids {
                collections
                    .into_iter()
                    .filter(|c| wanted.contains(&c.id))
                    .collect()
            } else if let Some(folder_id) = params["folder_id"].as_str().filter(|s| !s.is_empty()) {
                let subtree = collect_descendant_folder_ids(folder_id);
                collections
                    .into_iter()
                    .filter(|c| c.folder_id.as_ref().is_some_and(|f| subtree.contains(f)))
                    .collect()
            } else {
                collections
            };
            let count = targets.len();
            if force {
                // 覆盖模式：集合封面与集合内资源的节点缓存都要先作废，
                // 否则 generate_thumbnail_bytes 三级缓存命中会原样吐回旧图
                for collection in &targets {
                    if let Some(cover) = collection.cover_path.as_ref() {
                        if !cover.is_empty() {
                            media_api::invalidate_node_thumbnail(cover.clone(), width);
                        }
                    }
                    if let Ok(items) = media_api::get_media_collection_items(collection.id.clone()) {
                        for item in items {
                            media_api::invalidate_node_thumbnail(item.file_path, width);
                        }
                    }
                }
            }
            spawn_import_thumbnail_generation(&targets, width);
            Ok(json!({ "count": count.to_string() }))
        }

        "list_media_collections" => {
            let collections = media_api::get_all_media_collections()
                .map_err(|e| format!("获取媒体集合失败: {}", e))?;
            // 体积/条数直接查聚合表（写入路径维护），不再为了填一个 total_size
            // 把整张 media_items 冷加载进内存 —— 那是闲置后首次取数的主要耗时。
            let aggregates: std::collections::HashMap<_, _> =
                media_api::get_all_collection_aggregates()
                    .map_err(|e| format!("获取集合聚合失败: {}", e))?
                    .into_iter()
                    .map(|a| (a.collection_id.clone(), a))
                    .collect();

            let result: Vec<Value> = collections
                .into_iter()
                .map(|c| {
                    let aggregate = aggregates.get(&c.id);
                    // 口径与本地一致：stat 过就用现存值（失效资源不计），没 stat 过退回条目记录值
                    let total_size = aggregate.map(|a| a.display_size()).unwrap_or(0);
                    let item_count = aggregate
                        .and_then(|a| a.live_count)
                        .unwrap_or(c.item_count as u32);
                    // 时间戳与本地 FFI 保持一致（Unix 秒），避免客户端解析失败导致排序错乱
                    json!({
                        "id": c.id,
                        "title": c.title,
                        "folder_path": c.folder_path,
                        "folder_id": c.folder_id,
                        "cover_path": c.cover_path,
                        "item_count": item_count.to_string(),
                        "created_at": c.created_at.timestamp(),
                        "updated_at": c.updated_at.timestamp(),
                        "total_size": total_size.to_string(),
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "list_media_folders" => {
            let folders = media_api::get_all_media_folders()
                .map_err(|e| format!("获取媒体文件夹失败: {}", e))?;
            let result: Vec<Value> = folders
                .into_iter()
                .map(|f| {
                    // 时间戳与本地 FFI 保持一致（Unix 秒）
                    json!({
                        "id": f.id,
                        "name": f.name,
                        "created_at": f.created_at.timestamp(),
                        "order": f.order,
                        "parent_id": f.parent_id,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "get_media_collection_items" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            let items = media_api::get_media_collection_items(collection_id)
                .map_err(|e| format!("获取媒体项失败: {}", e))?;
            let result: Vec<Value> = items
                .into_iter()
                .map(|item| {
                    json!({
                        "id": item.id,
                        "collection_id": item.collection_id,
                        "title": item.title,
                        "file_path": item.file_path,
                        "kind": item.kind.as_str(),
                        "file_size": item.file_size.to_string(),
                        "modified_at": item.modified_at,
                        "width": item.width,
                        "height": item.height,
                        "duration_ms": item.duration_ms.map(|d| d.to_string()),
                        "order": item.order,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "create_media_folder" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let folder = media_api::create_media_folder(name)
                .map_err(|e| format!("创建文件夹失败: {}", e))?;
            Ok(json!({
                "id": folder.id,
                "name": folder.name,
                "created_at": folder.created_at.timestamp(),
                "order": folder.order,
                "parent_id": folder.parent_id,
            }))
        }

        "create_child_media_folder" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let parent_id = params["parent_id"].as_str().unwrap_or("").to_string();
            // 父夹必须先存在：create_child_media_folder 底层不校验 parent_id，
            // 对幽灵 id 会「成功」建出一个 parent_id 指向不存在文件夹的孤儿夹
            // （客户端拿到 success 后刷新列表看不到它，表现为新建子文件夹没生效）。
            ensure_media_folder_exists(&parent_id, "创建子文件夹")?;
            let folder = media_api::create_child_media_folder(name, parent_id)
                .map_err(|e| format!("创建子文件夹失败: {}", e))?;
            Ok(json!({
                "id": folder.id,
                "name": folder.name,
                "created_at": folder.created_at.timestamp(),
                "order": folder.order,
                "parent_id": folder.parent_id,
            }))
        }

        "rename_media_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            let name = params["name"].as_str().unwrap_or("").to_string();
            // false = 没有这个文件夹：必须报错，不能回 ok:true 骗客户端
            require_changed(
                media_api::rename_media_folder(folder_id.clone(), name),
                "重命名文件夹",
                format!("文件夹不存在 {}", folder_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "delete_media_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            require_changed(
                media_api::delete_media_folder(folder_id.clone()),
                "删除文件夹",
                format!("文件夹不存在 {}", folder_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "scan_media_folders" => {
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            let collections = media_api::scan_media_folders(folder_path)
                .map_err(|e| format!("扫描媒体文件夹失败: {}", e))?;
            let result: Vec<Value> = collections
                .into_iter()
                .map(|c| {
                    // 时间戳与本地 FFI 保持一致（Unix 秒）
                    json!({
                        "id": c.id,
                        "title": c.title,
                        "folder_path": c.folder_path,
                        "folder_id": c.folder_id,
                        "cover_path": c.cover_path,
                        "item_count": c.item_count.to_string(),
                        "created_at": c.created_at.timestamp(),
                        "updated_at": c.updated_at.timestamp(),
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "import_media_folder" => {
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            let generate_thumbnails = params["generate_thumbnails"].as_bool().unwrap_or(false);
            let preserve_structure = params["preserve_structure"].as_bool().unwrap_or(false);
            // 缩略图预生成宽度：客户端按自己的封面请求宽度传入，
            // 保证节点内存缓存 key 命中；缺省 240 与封面请求的默认宽度一致。
            let cover_width = params["cover_width"].as_u64().unwrap_or(240) as u32;
            // 归档目标文件夹（库内 ID）：客户端在某个远程文件夹内导入时带上，
            // 集合就落在该文件夹下，而不是节点库根目录。
            let base_folder_id = params["base_folder_id"]
                .as_str()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            // 库内显示名：客户端上传时为防磁盘覆盖可能把落盘目录唯一化
            // （照片 → 照片 (2)），库内仍按原目录名显示（同名允许共存）；
            // 旧客户端不传则维持原行为（以磁盘目录名为准）。
            let display_name = params["display_name"]
                .as_str()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            // 归档目标夹必须在导入**之前**校验：扁平导入路径下，import_media_folder
            // 已经落库了才去移动集合，父夹不存在时就会留下一条「已导入」却没挂到
            // 目标夹的集合，用户重试还会撞「该文件夹已导入」。先失败，不留副作用。
            if let Some(pid) = &base_folder_id {
                ensure_media_folder_exists(pid, "导入媒体文件夹")?;
            }
            // 按原始目录导入：扫描子目录集合，并按目录层级创建文件夹归档
            if preserve_structure {
                let collections = media_api::scan_media_folders(folder_path.clone())
                    .map_err(|e| format!("导入媒体文件夹失败: {}", e))?;
                let imported = import_collections_with_structure(
                    &folder_path,
                    collections,
                    &base_folder_id,
                    display_name.as_deref(),
                )?;
                if generate_thumbnails {
                    spawn_import_thumbnail_generation(&imported, cover_width);
                }
                return Ok(json!({
                    "id": "",
                    "title": "",
                    "folder_path": folder_path,
                    "folder_id": base_folder_id,
                    "cover_path": Value::Null,
                    "item_count": imported.len().to_string(),
                    "created_at": chrono::Utc::now().timestamp(),
                    "updated_at": chrono::Utc::now().timestamp(),
                }));
            }
            let mut collection = media_api::import_media_folder(folder_path)
                .map_err(|e| format!("导入媒体文件夹失败: {}", e))?;
            // 客户端指定显示名：磁盘目录被唯一化过，库内标题仍用原名（同名共存）
            if let Some(name) = &display_name {
                if &collection.title != name {
                    // 集合刚由 import_media_folder 建出来，false 只可能是并发被删，
                    // 这一步失败就不该继续往下假装导入成功
                    require_changed(
                        media_api::rename_media_collection(collection.id.clone(), name.clone()),
                        "重命名媒体集合",
                        format!("集合不存在 {}", collection.id),
                    )?;
                    collection.title = name.clone();
                }
            }
            let mut folder_id = collection.folder_id.clone();
            if let Some(pid) = &base_folder_id {
                // 父夹存在性已在导入前校验过（见上），这里只需确认集合本身还在
                require_changed(
                    media_api::move_media_collection_to_folder(
                        collection.id.clone(),
                        Some(pid.clone()),
                    ),
                    "移动集合",
                    format!("集合不存在 {}", collection.id),
                )?;
                folder_id = Some(pid.clone());
            }
            if generate_thumbnails {
                spawn_import_thumbnail_generation(std::slice::from_ref(&collection), cover_width);
            }
            Ok(json!({
                "id": collection.id,
                "title": collection.title,
                "folder_path": collection.folder_path,
                "folder_id": folder_id,
                "cover_path": collection.cover_path,
                "item_count": collection.item_count.to_string(),
                "created_at": collection.created_at.timestamp(),
                "updated_at": collection.updated_at.timestamp(),
            }))
        }

        // 重新扫描**已导入过**的媒体目录：绕开 import 的「该文件夹已导入」拦截，
        // 对同一 folder_path 做 upsert 覆盖。用途是「用户在节点磁盘上直接增删
        // 文件后让库同步」——这是远程/无头模式下唯一能达成该目的的入口。
        //
        // 用 `rescan_media_folder_allow_empty` 而不是裸的 `rescan_media_folder`：
        // 后者在「目录里一条媒体都不剩」时提前 Err（upsert 的 early return），
        // 而把节点上的文件全删掉恰恰是用户会主动做的事，此时必须回「集合还在、
        // item_count=0」并让聚合值/条目写实归零，既不能报成失败（那会让人以为
        // 重扫没生效），也不能假成功（留着旧条目和旧体积）。
        "rescan_media_folder" => {
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            require_id(&folder_path, "媒体文件夹路径")?;
            // 缩略图预生成：盘上新增的文件必然没有旁路缓存，不预热的话客户端
            // 点进去才开始出图。宽度必须与客户端封面请求一致（缓存 key 含宽度）。
            let generate_thumbnails = params["generate_thumbnails"].as_bool().unwrap_or(false);
            let cover_width = params["cover_width"].as_u64().unwrap_or(240) as u32;
            let collection = media_api::rescan_media_folder_allow_empty(folder_path.clone())
                .map_err(|e| format!("重新扫描媒体文件夹失败: {}", e))?;
            if generate_thumbnails {
                spawn_import_thumbnail_generation(std::slice::from_ref(&collection), cover_width);
            }
            Ok(json!({
                "id": collection.id,
                "title": collection.title,
                "folder_path": collection.folder_path,
                "folder_id": collection.folder_id,
                "cover_path": collection.cover_path,
                "item_count": collection.item_count.to_string(),
                "created_at": collection.created_at.timestamp(),
                "updated_at": collection.updated_at.timestamp(),
            }))
        }

        "rename_media_collection" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            let title = params["title"].as_str().unwrap_or("").to_string();
            require_changed(
                media_api::rename_media_collection(collection_id.clone(), title),
                "重命名媒体集合",
                format!("集合不存在 {}", collection_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "delete_media_collection" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            require_changed(
                media_api::delete_media_collection(collection_id.clone()),
                "删除媒体集合",
                format!("集合不存在 {}", collection_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "move_media_collection_to_folder" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            // 空串等同于「移到根目录」，不能当成一个要校验的 folder_id
            let folder_id = params["folder_id"]
                .as_str()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            // 目标文件夹不存在时底层照样回 true（它只改 collection.folder_id），
            // 集合会挂到一个看不见的父 id 上：必须自己先校验。
            if let Some(pid) = &folder_id {
                ensure_media_folder_exists(pid, "移动媒体集合")?;
            }
            require_changed(
                media_api::move_media_collection_to_folder(collection_id.clone(), folder_id),
                "移动媒体集合",
                format!("集合不存在 {}", collection_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "delete_collection_local_files" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            // delete_collection_local_files 对不存在的集合回 Ok(0)，与「集合在但文件早被
            // 外部清空」同形（都是 deleted:0）。先查存在性，否则客户端会收到一个
            // 看起来正常的 deleted:0 而不知道目标根本没删。
            ensure_media_collection_exists(&collection_id, "删除集合本地文件")?;
            // 复用本机 FFI 那套实现：除了删物理文件，它还会收掉目录树内的 .SlimeWorks
            // 缓存目录、清空后的集合目录，并把聚合表里这条集合的现存体积/条数改写掉。
            // 少了最后一步，客户端删完文件返回上一级看到的仍是删除前的旧体积。
            let deleted = media_api::delete_collection_local_files(collection_id)
                .map_err(|e| format!("删除集合本地文件失败: {}", e))?;
            Ok(json!({"deleted": deleted}))
        }

        // 删除单个条目的物理文件，但**保留集合记录**（客户端 media_library_vm_actions
        // 的 deleteRemoteItemLocalFile 走这里）。
        "delete_media_item_local_file" => {
            let item_id = params["item_id"].as_str().unwrap_or("").to_string();
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            require_id(&item_id, "媒体条目")?;
            require_id(&collection_id, "集合")?;
            // 先判集合存在：集合被删/传错时 get_media_collection_items 只会回空列表，
            // 若不先判就会把「集合不存在」错报成「条目不存在」，排查时指向错误的对象。
            ensure_media_collection_exists(&collection_id, "删除条目本地文件")?;
            // 通过集合条目表定位 file_path：客户端只给条目 id，节点不能凭 id 猜路径。
            // 条目已不在库里（重复点删除、或文件早被别的流程清掉）必须报错，
            // 不能静默成功——否则用户看到「已删除」但列表里那一条还在。
            let items = media_api::get_media_collection_items(collection_id.clone())
                .map_err(|e| format!("删除条目本地文件失败: {}", e))?;
            let Some(item) = items.iter().find(|item| item.id == item_id) else {
                return Err(format!(
                    "删除条目本地文件失败: 媒体条目不存在 {}",
                    item_id
                ));
            };
            let file_path = item.file_path.clone();
            // 与 FFI 版 deleteMediaItemFile 用同一个底层函数：它负责删物理文件、
            // 清缩略图任务记录、重扫「拥有该条目的集合根目录」（不是文件父目录，
            // 否则会在中间层新建幽灵集合），最后把该路径从所有集合里摘掉。
            //
            // 与 delete_collection_local_files 的差别（后者刻意保留条目记录、
            // 只重算聚合表的 live 值）：这里是单条目删除，客户端删完会立刻
            // 重新拉列表，条目随重扫/purge 自然消失才符合「删掉了」的预期；
            // 若强留条目记录，点开集合仍能看到一个指向已删路径的幽灵项。
            // 返回的 bool 是「物理文件是否真被删掉」：文件早已不在时它回 false，
            // 但条目记录同样已被清理，所以这里不当错误处理，只如实回给客户端。
            let removed_file = media_api::delete_media_item_file(file_path.clone())
                .map_err(|e| format!("删除条目本地文件失败: {}", e))?;
            Ok(json!({
                "ok": true,
                "deleted_file": removed_file,
                "file_path": file_path,
            }))
        }

        // ── 目录扫描 ─────────────────────────────────────────────────────────
        // 反推「把本地目录拖进远程文件夹」时的落点：MediaFolder 只有库内 ID，没有磁盘路径，
        // 因此从该文件夹下已有集合的磁盘位置反推（集合目录的父目录 = 文件夹目录）。
        // 空 folder_id 表示「媒体库根目录」：所有集合的父目录即库根候选。
        "resolve_folder_upload_target" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            let (target_dir, candidates) = resolve_folder_target_dir(&folder_id)?;
            Ok(json!({
                "target_dir": target_dir,
                // 候选父目录：target_dir 为空时（空文件夹/歧义）供客户端走目录浏览器兜底
                "candidates": candidates,
            }))
        }

        "list_directories" => {
            let path = params["path"].as_str().unwrap_or("/");
            let dir_path = Path::new(path);
            if !dir_path.exists() {
                return Ok(json!([]));
            }
            let mut entries: Vec<String> = fs::read_dir(dir_path)
                .map(|rd| {
                    rd.filter_map(|e| e.ok())
                        .filter(|e| e.path().is_dir())
                        .map(|e| e.path().to_string_lossy().to_string())
                        .collect()
                })
                .unwrap_or_default();
            entries.sort();
            Ok(json!(entries))
        }

        "create_directory" => {
            let path = params["path"].as_str().unwrap_or("");
            if path.is_empty() {
                return Ok(json!(false));
            }
            fs::create_dir_all(Path::new(path)).map_err(|e| format!("创建目录失败: {}", e))?;
            Ok(json!(true))
        }

        "rename_directory" => {
            let old_path = params["old_path"].as_str().unwrap_or("");
            let new_path = params["new_path"].as_str().unwrap_or("");
            if old_path.is_empty() || new_path.is_empty() {
                return Ok(json!(false));
            }
            fs::rename(Path::new(old_path), Path::new(new_path))
                .map_err(|e| format!("重命名目录失败: {}", e))?;
            Ok(json!(true))
        }

        // ── 小说操作 ─────────────────────────────────────────────────────────
        "list_novels" => {
            // with_cover 默认 true：旧客户端不带该参数时行为完全不变（列表内嵌封面 base64）。
            // 新客户端传 false 时跳过逐本封面读盘 + base64 编码——N 本 × ~40KB 的列表
            // 传输是远程书架首屏卡顿的主因；封面改由 GET /node/novel_cover 按需流式取。
            let novels =
                novel_api::get_all_novels().map_err(|e| format!("获取小说列表失败: {}", e))?;
            let folders = novel_api::get_all_folders().unwrap_or_default();
            let folder_map: std::collections::HashMap<_, _> = folders
                .into_iter()
                .map(|f| (f.id.clone(), f.name))
                .collect();
            let chapter_counts = load_chapter_count_map();

            let result = build_novel_list_json(novels, &folder_map, &chapter_counts, &params);
            Ok(json!(result))
        }

        "search_all_novels" => {
            let keyword = params["keyword"].as_str().unwrap_or("");
            if keyword.is_empty() {
                return Ok(json!([]));
            }
            let results = novel_api::search_in_all_novels(keyword.to_string())
                .map_err(|e| format!("搜索小说失败: {}", e))?;
            let folders = novel_api::get_all_folders().unwrap_or_default();
            let folder_map: std::collections::HashMap<_, _> = folders
                .into_iter()
                .map(|f| (f.id.clone(), f.name))
                .collect();
            let chapter_counts = load_chapter_count_map();

            let result: Vec<Value> = results
                .into_iter()
                .map(|r| {
                    let n = r.novel;
                    let cover_base64 = encode_cover_base64(&n.cover_path);
                    let cover_ext =
                        extract_image_ext(n.cover_path.as_deref().unwrap_or("")).to_string();
                    json!({
                        "id": n.id,
                        "title": n.title,
                        "author": n.author,
                        "file_path": n.file_path,
                        "format": n.format.as_str(),
                        "file_size": n.file_size.to_string(),
                        "modified_at": n.modified_at.to_string(),
                        "added_at": n.added_at.to_string(),
                        "progress": n.progress,
                        "last_read_at": n.last_read_at.map(|t| t.to_string()),
                        "cover_path": n.cover_path,
                        "cover_base64": cover_base64,
                        "cover_ext": cover_ext,
                        "folder_id": n.folder_id,
                        "folder_name": n.folder_id.as_ref().and_then(|fid| folder_map.get(fid).cloned()),
                        "chapter_count": chapter_counts.get(n.id.as_str()).copied(),
                        "custom_order": n.custom_order,
                        "is_favorite": n.is_favorite,
                        "tags": n.tags,
                        "notes": n.notes,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "search_in_novel" => {
            let file_path = params["file_path"].as_str().unwrap_or("").to_string();
            let keyword = params["keyword"].as_str().unwrap_or("").to_string();
            let matches = novel_api::search_in_novel(file_path, keyword)
                .map_err(|e| format!("搜索小说内容失败: {}", e))?;
            let result: Vec<Value> = matches
                .into_iter()
                .map(|m| {
                    json!({
                        "chapter_index": m.chapter_index,
                        "chapter_title": m.chapter_title,
                        "position": m.position,
                        "snippet": m.snippet,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "get_novel_content" => {
            let file_path = params["file_path"].as_str().unwrap_or("").to_string();
            let content = novel_api::get_novel_content(file_path)
                .map_err(|e| format!("获取小说内容失败: {}", e))?;
            Ok(json!({
                "novel_id": content.novel_id,
                "chapters": content.chapters.into_iter().map(|c| json!({
                    "id": c.id,
                    "title": c.title,
                    "content": c.content,
                    "index": c.index.to_string(),
                })).collect::<Vec<_>>(),
            }))
        }

        "get_chapter_content" => {
            let file_path = params["file_path"].as_str().unwrap_or("").to_string();
            let chapter_index = params["chapter_index"].as_u64().unwrap_or(0) as usize;
            let content = novel_api::get_chapter_content(file_path, chapter_index)
                .map_err(|e| format!("获取章节内容失败: {}", e))?;
            Ok(json!(content))
        }

        // ── 小说文件夹（本机 FFI 的小说库文件夹能力在无头模式下的镜像）──────
        // 客户端在远程模式下把文件夹操作分流到这里；合成 id
        // `remote-folder:<nodeId>:<rawFolderId>` 的 rawId 就是这里的 folder_id。
        "list_novel_folders" => {
            let folders =
                novel_api::get_all_folders().map_err(|e| format!("获取小说文件夹失败: {}", e))?;
            // get_all_folders 已按 order 排好；逐项转 JSON 保持与 list_media_folders 同形
            Ok(json!(folders
                .into_iter()
                .map(novel_folder_json)
                .collect::<Vec<_>>()))
        }

        "create_novel_folder" => {
            let name = params["name"].as_str().unwrap_or("").trim().to_string();
            if name.is_empty() {
                return Err("创建小说文件夹失败: 文件夹名称不能为空".to_string());
            }
            // 底层 create_folder 是顶级文件夹（parent_id = None）；子夹走 create_child_folder。
            // 客户端若传了 parent_id 就按父子语义建，避免建出来却挂不到期望位置。
            let parent_id = params["parent_id"]
                .as_str()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            let folder = match parent_id {
                Some(parent_id) => {
                    // ★ create_child_folder 不校验父夹：不先判会建出 parent_id
                    //   指向幽灵夹的孤儿文件夹（UI 上永远看不见、也进不去）
                    ensure_novel_folder_exists(&parent_id, "创建子小说文件夹")?;
                    novel_api::create_child_folder(name, parent_id)
                        .map_err(|e| format!("创建小说文件夹失败: {}", e))?
                }
                None => novel_api::create_folder(name)
                    .map_err(|e| format!("创建小说文件夹失败: {}", e))?,
            };
            Ok(novel_folder_json(folder))
        }

        "rename_novel_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            let name = params["name"].as_str().unwrap_or("").trim().to_string();
            require_id(&folder_id, "小说文件夹")?;
            if name.is_empty() {
                return Err("重命名小说文件夹失败: 文件夹名称不能为空".to_string());
            }
            // rename_folder 回 Result<bool>：false = 夹不存在（底层已有正确语义）
            require_changed(
                novel_api::rename_folder(folder_id.clone(), name),
                "重命名小说文件夹",
                format!("小说文件夹不存在 {}", folder_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "delete_novel_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            require_id(&folder_id, "小说文件夹")?;
            // 底层语义：删除文件夹本身，其中的书籍移回根目录（不是删书）
            require_changed(
                novel_api::delete_folder(folder_id.clone()),
                "删除小说文件夹",
                format!("小说文件夹不存在 {}", folder_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "delete_novel_folder_with_novels" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            // 底层 delete_folder_with_novels 回 Result<()>：夹不存在时是静默 no-op
            //（"没删掉任何东西"和"删成功了"同形），必须自己先判存在性
            ensure_novel_folder_exists(&folder_id, "删除小说文件夹及书籍")?;
            novel_api::delete_folder_with_novels(folder_id)
                .map_err(|e| format!("删除小说文件夹及书籍失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "reorder_novel_folders" => {
            // 客户端拖拽排序：folder_ids 是按新顺序排好的完整 id 列表。
            // batch_update_folder_orders 回 Result<()>，对不存在的 id 静默跳过，
            // 所以这里先校验——列表里出现不存在的夹说明客户端状态过期，
            // 静默跳过会让「排序保存成功」与「顺序其实没变」同形。
            let folder_ids: Vec<String> = params["folder_ids"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            if folder_ids.is_empty() {
                return Err("排序小说文件夹失败: folder_ids 不能为空".to_string());
            }
            // 一次性建存在性集合，避免逐个全表扫
            let existing: std::collections::HashSet<String> = novel_api::get_all_folders()
                .map_err(|e| format!("排序小说文件夹失败: {}", e))?
                .into_iter()
                .map(|f| f.id)
                .collect();
            for folder_id in &folder_ids {
                if !existing.contains(folder_id) {
                    return Err(format!("排序小说文件夹失败: 小说文件夹不存在 {}", folder_id));
                }
            }
            novel_api::batch_update_folder_orders(folder_ids)
                .map_err(|e| format!("排序小说文件夹失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "delete_novel" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            // remove_novel 对不存在的 id 回 Ok(false)：那是「没这本书」，
            // 不是「删成功了」，必须翻成错误否则书架一直报删除成功。
            require_changed(
                novel_api::remove_novel(novel_id.clone()),
                "删除小说",
                format!("小说不存在 {}", novel_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "update_novel_tags" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let tags: Vec<String> = params["tags"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();
            require_changed(
                novel_api::update_novel_tags(novel_id.clone(), tags),
                "更新小说标签",
                format!("小说不存在 {}", novel_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "set_novel_favorite" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let is_favorite = params["is_favorite"].as_bool().unwrap_or(false);
            require_changed(
                novel_api::set_novel_favorite(novel_id.clone(), is_favorite),
                "设置收藏状态",
                format!("小说不存在 {}", novel_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "update_novel_info" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let title = params["title"].as_str().map(|s| s.to_string());
            let author = params["author"].as_str().map(|s| s.to_string());
            let notes = params["notes"].as_str().map(|s| s.to_string());
            let tags: Option<Vec<String>> = params.get("tags").map(|v| {
                v.as_array()
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default()
            });

            // 先查存在性：update_novel_info 本身返回 Result<()>，对不存在的 id
            // 是静默 no-op，不先判就会把「书不存在」当成功回给客户端。
            let novel_exists = novel_api::get_all_novels()
                .map_err(|e| format!("更新小说信息失败: {}", e))?
                .iter()
                .any(|novel| novel.id == novel_id);
            if !novel_exists {
                return Err(format!("更新小说信息失败: 小说不存在 {}", novel_id));
            }

            // 如果有 is_favorite 字段则先更新收藏状态
            if let Some(is_favorite) = params.get("is_favorite").and_then(|v| v.as_bool()) {
                // 不再 `let _ =` 吞错：写失败要让调用方知道这次更新没全成
                require_changed(
                    novel_api::set_novel_favorite(novel_id.clone(), is_favorite),
                    "设置收藏状态",
                    format!("小说不存在 {}", novel_id),
                )?;
            }

            novel_api::update_novel_info(novel_id.clone(), title, author, notes, tags)
                .map_err(|e| format!("更新小说信息失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "move_novel_to_folder" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            // 空串等同于「移到未分组的根」，不当作一个要校验的 folder_id
            let folder_id = params["folder_id"]
                .as_str()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty());
            // 目标夹不存在时 move_novel_to_folder 只把 folder_id 写进书里就回 true：
            // 书会挂到一个再也不会有卡片的幽灵夹上（正文还在，但用户在 UI 里"丢了"书）。
            // 所以移入非根目录前先判目标夹存在。
            if let Some(target) = folder_id.as_deref() {
                ensure_novel_folder_exists(target, "移动小说到文件夹")?;
            }
            require_changed(
                novel_api::move_novel_to_folder(novel_id.clone(), folder_id),
                "移动小说到文件夹",
                format!("小说不存在 {}", novel_id),
            )?;
            Ok(json!({"ok": true}))
        }

        "update_novel_cover_base64" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let image_base64 = params["image_base64"].as_str().unwrap_or("");
            let ext = params["image_ext"].as_str().unwrap_or("png");

            if novel_id.is_empty() || image_base64.is_empty() {
                return Err("novel_id or image_base64 is empty".to_string());
            }

            // 解码并保存到临时文件
            let bytes =
                base64::Engine::decode(&base64::engine::general_purpose::STANDARD, image_base64)
                    .map_err(|e| format!("Base64 解码失败: {}", e))?;

            let temp_path = write_temp_image(&bytes, ext)?;
            let copy_path = temp_path.clone();
            let result = novel_api::update_novel_cover(novel_id, temp_path)
                .map_err(|e| format!("更新小说封面失败: {}", e));
            // 临时文件用完即删：不清理会随每次封面上传无限堆积在系统临时目录
            let _ = fs::remove_file(&copy_path);
            result?;
            Ok(json!({"ok": true}))
        }

        // ── 智能文件夹（通过 media_collection redb 存储） ────────────────────
        "list_smart_folders" => {
            let smart_folders = media_api::get_all_smart_folders()
                .map_err(|e| format!("获取智能文件夹失败: {}", e))?;
            let result: Vec<Value> = smart_folders
                .iter()
                .map(|sf| {
                    json!({
                        "id": sf.id,
                        "name": sf.name,
                        "regexPattern": sf.regex_pattern,
                        "keywords": sf.keywords,
                        "targetFolderIds": sf.target_folder_ids,
                        "regexTarget": sf.regex_target.as_str(),
                        "fileTypeFilter": sf.file_type_filter.as_str(),
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "create_smart_folder" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let regex_pattern = params["regex_pattern"].as_str().unwrap_or("").to_string();
            let keywords: Vec<String> = params["keywords"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let regex_target = params["regex_target"]
                .as_str()
                .unwrap_or("collectionName")
                .to_string();
            let file_type_filter = params["file_type_filter"]
                .as_str()
                .unwrap_or("all")
                .to_string();
            let target_folder_ids: Vec<String> = params["target_folder_ids"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let sf = media_api::create_smart_folder(
                name,
                regex_pattern,
                keywords,
                regex_target,
                file_type_filter,
                target_folder_ids,
            )
            .map_err(|e| format!("创建智能文件夹失败: {}", e))?;
            Ok(json!({
                "id": sf.id,
                "name": sf.name,
                "regexPattern": sf.regex_pattern,
                "keywords": sf.keywords,
                "targetFolderIds": sf.target_folder_ids,
                "regexTarget": sf.regex_target.as_str(),
                "fileTypeFilter": sf.file_type_filter.as_str(),
            }))
        }

        "update_smart_folder" => {
            let id = params["id"].as_str().unwrap_or("").to_string();
            let name = params["name"].as_str().unwrap_or("").to_string();
            let regex_pattern = params["regex_pattern"].as_str().unwrap_or("").to_string();
            let keywords: Vec<String> = params["keywords"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let regex_target = params["regex_target"]
                .as_str()
                .unwrap_or("collectionName")
                .to_string();
            let file_type_filter = params["file_type_filter"]
                .as_str()
                .unwrap_or("all")
                .to_string();
            let target_folder_ids: Vec<String> = params["target_folder_ids"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let sf = media_api::update_smart_folder(
                id,
                name,
                regex_pattern,
                keywords,
                regex_target,
                file_type_filter,
                target_folder_ids,
            )
            .map_err(|e| format!("更新智能文件夹失败: {}", e))?;
            Ok(json!({
                "id": sf.id,
                "name": sf.name,
                "regexPattern": sf.regex_pattern,
                "keywords": sf.keywords,
                "targetFolderIds": sf.target_folder_ids,
                "regexTarget": sf.regex_target.as_str(),
                "fileTypeFilter": sf.file_type_filter.as_str(),
            }))
        }

        "delete_smart_folder" => {
            let target_id = params["id"].as_str().unwrap_or("").to_string();
            // 与 A 组同一类缺陷：delete_smart_folder 回 Result<bool>，
            // false = 没有这个智能文件夹，以前被 map_err 丢掉后照样回 ok:true。
            require_changed(
                media_api::delete_smart_folder(target_id.clone()),
                "删除智能文件夹",
                format!("智能文件夹不存在 {}", target_id),
            )?;
            Ok(json!({"ok": true}))
        }

        // ── 阿里云 DDNS 操作 ─────────────────────────────────────────────────
        "aliyun_get_status" => {
            let status = aliyun_module::api::aliyun_ddns_get_status()
                .map_err(|e| format!("获取阿里云状态失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&status).map_err(|e| format!("解析阿里云状态失败: {}", e))?;
            Ok(parsed)
        }

        "aliyun_get_logs" => {
            let logs = aliyun_module::api::aliyun_ddns_get_logs()
                .map_err(|e| format!("获取阿里云日志失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&logs).map_err(|e| format!("解析阿里云日志失败: {}", e))?;
            Ok(parsed)
        }

        "aliyun_get_watch_domains" => {
            let config = aliyun_module::api::aliyun_ddns_get_config()
                .map_err(|e| format!("获取阿里云配置失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&config).map_err(|e| format!("解析阿里云配置失败: {}", e))?;
            Ok(parsed.get("watch_domains").cloned().unwrap_or(json!([])))
        }

        "aliyun_check_and_update" => {
            let result = aliyun_module::api::aliyun_ddns_check_and_update()
                .await
                .map_err(|e| format!("阿里云检查更新失败: {}", e))?;
            Ok(json!({"result": result}))
        }

        // ── 电力定时统计操作 ───────────────────────────────────────────────────
        "power_stats_get_status" => {
            let status = power_stats::api::power_stats_get_status()
                .map_err(|e| format!("获取电力统计状态失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&status).map_err(|e| format!("解析状态失败: {}", e))?;
            Ok(parsed)
        }

        "power_stats_get_summary" => {
            let summary = power_stats::api::power_stats_get_summary()
                .map_err(|e| format!("获取电力统计汇总失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&summary).map_err(|e| format!("解析汇总失败: {}", e))?;
            Ok(parsed)
        }

        "power_stats_get_aggregated" => {
            let range = params["range"].as_str().unwrap_or("1day").to_string();
            let aggregated = power_stats::api::power_stats_get_aggregated(range)
                .map_err(|e| format!("获取电力聚合数据失败: {}", e))?;
            let parsed: Value = serde_json::from_str(&aggregated)
                .map_err(|e| format!("解析聚合数据失败: {}", e))?;
            Ok(parsed)
        }

        "power_stats_get_logs" => {
            let logs = power_stats::api::power_stats_get_logs()
                .map_err(|e| format!("获取电力抓取日志失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&logs).map_err(|e| format!("解析日志失败: {}", e))?;
            Ok(parsed)
        }

        "power_stats_fetch_once" => {
            let result = power_stats::api::power_stats_fetch_once()
                .await
                .map_err(|e| format!("电力抓取失败: {}", e))?;
            let parsed: Value =
                serde_json::from_str(&result).map_err(|e| format!("解析读数失败: {}", e))?;
            Ok(parsed)
        }

        "power_stats_start_polling" => {
            power_stats::api::power_stats_start_polling()
                .await
                .map_err(|e| format!("启动电力轮询失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "power_stats_stop_polling" => {
            power_stats::api::power_stats_stop_polling()
                .await
                .map_err(|e| format!("停止电力轮询失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "power_stats_set_enabled" => {
            let enabled = params["enabled"].as_bool().unwrap_or(false);
            power_stats::api::power_stats_set_enabled(enabled)
                .map_err(|e| format!("设置电力统计开关失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        // ── 音乐播放器操作 ─────────────────────────────────────────────────────
        "music_list_playlists" => {
            let playlists =
                music_api::get_all_playlists().map_err(|e| format!("获取播放列表失败: {}", e))?;
            let result: Vec<Value> = playlists
                .into_iter()
                .map(|p| {
                    json!({
                        "id": p.id,
                        "name": p.name,
                        "cover_path": p.cover_path,
                        "item_count": p.item_count.to_string(),
                        "created_at": p.created_at.timestamp(),
                        "updated_at": p.updated_at.timestamp(),
                        "is_default": p.is_default,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_create_playlist" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let playlist =
                music_api::create_playlist(name).map_err(|e| format!("创建播放列表失败: {}", e))?;
            Ok(json!({
                "id": playlist.id,
                "name": playlist.name,
                "cover_path": playlist.cover_path,
                "item_count": playlist.item_count.to_string(),
                "created_at": playlist.created_at.timestamp(),
                "updated_at": playlist.updated_at.timestamp(),
                "is_default": playlist.is_default,
            }))
        }

        "music_delete_playlist" => {
            let playlist_id = params["playlist_id"].as_str().unwrap_or("").to_string();
            music_api::delete_playlist(playlist_id)
                .map_err(|e| format!("删除播放列表失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "music_rename_playlist" => {
            let playlist_id = params["playlist_id"].as_str().unwrap_or("").to_string();
            let name = params["name"].as_str().unwrap_or("").to_string();
            music_api::rename_playlist(playlist_id, name)
                .map_err(|e| format!("重命名播放列表失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "music_get_playlist_items" => {
            let playlist_id = params["playlist_id"].as_str().unwrap_or("").to_string();
            let items = music_api::get_playlist_items(playlist_id)
                .map_err(|e| format!("获取音乐列表失败: {}", e))?;
            let result: Vec<Value> = items
                .into_iter()
                .map(|i| {
                    json!({
                        "id": i.id,
                        "playlist_id": i.playlist_id,
                        "title": i.title,
                        "artist": i.artist,
                        "album": i.album,
                        "file_path": i.file_path,
                        "duration_ms": i.duration_ms.map(|d| d.to_string()),
                        "track_number": i.track_number,
                        "disc_number": i.disc_number,
                        "year": i.year,
                        "genre": i.genre,
                        "cover_path": i.cover_path,
                        "file_size": i.file_size.to_string(),
                        "modified_at": i.modified_at.timestamp(),
                        "order": i.order,
                        "is_favorite": i.is_favorite,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_import_folder" => {
            let playlist_id = params["playlist_id"].as_str().unwrap_or("").to_string();
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            let items = music_api::import_music_folder(playlist_id, folder_path)
                .map_err(|e| format!("导入音乐文件夹失败: {}", e))?;
            let result: Vec<Value> = items
                .into_iter()
                .map(|i| {
                    json!({
                        "id": i.id,
                        "playlist_id": i.playlist_id,
                        "title": i.title,
                        "artist": i.artist,
                        "album": i.album,
                        "file_path": i.file_path,
                        "duration_ms": i.duration_ms.map(|d| d.to_string()),
                        "cover_path": i.cover_path,
                        "file_size": i.file_size.to_string(),
                        "order": i.order,
                        "is_favorite": i.is_favorite,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_import_paths" => {
            let playlist_id = params["playlist_id"].as_str().unwrap_or("").to_string();
            let paths: Vec<String> = params["paths"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let items = music_api::import_music_paths(playlist_id, paths)
                .map_err(|e| format!("导入音乐文件失败: {}", e))?;
            let result: Vec<Value> = items
                .into_iter()
                .map(|i| {
                    json!({
                        "id": i.id,
                        "playlist_id": i.playlist_id,
                        "title": i.title,
                        "artist": i.artist,
                        "album": i.album,
                        "file_path": i.file_path,
                        "duration_ms": i.duration_ms.map(|d| d.to_string()),
                        "cover_path": i.cover_path,
                        "file_size": i.file_size.to_string(),
                        "order": i.order,
                        "is_favorite": i.is_favorite,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_delete_item" => {
            let item_id = params["item_id"].as_str().unwrap_or("").to_string();
            music_api::delete_music_item(item_id)
                .map_err(|e| format!("删除音乐条目失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "music_update_item" => {
            let item_id = params["item_id"].as_str().unwrap_or("").to_string();
            let title = params["title"].as_str().map(String::from);
            let artist = params["artist"].as_str().map(String::from);
            let album = params["album"].as_str().map(String::from);
            let is_favorite = params["is_favorite"].as_bool();
            music_api::update_music_item(item_id, title, artist, album, is_favorite)
                .map_err(|e| format!("更新音乐信息失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "music_toggle_favorite" => {
            let item_id = params["item_id"].as_str().unwrap_or("").to_string();
            let is_favorite = music_api::toggle_favorite(item_id)
                .map_err(|e| format!("切换收藏状态失败: {}", e))?;
            Ok(json!({"is_favorite": is_favorite}))
        }

        "music_get_favorites" => {
            let items =
                music_api::get_favorite_items().map_err(|e| format!("获取收藏音乐失败: {}", e))?;
            let result: Vec<Value> = items
                .into_iter()
                .map(|i| {
                    json!({
                        "id": i.id,
                        "playlist_id": i.playlist_id,
                        "title": i.title,
                        "artist": i.artist,
                        "album": i.album,
                        "file_path": i.file_path,
                        "duration_ms": i.duration_ms.map(|d| d.to_string()),
                        "cover_path": i.cover_path,
                        "file_size": i.file_size.to_string(),
                        "is_favorite": i.is_favorite,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_get_recent_played" => {
            let limit = params["limit"].as_u64().unwrap_or(50) as u32;
            let records = music_api::get_recent_played(limit)
                .map_err(|e| format!("获取最近播放失败: {}", e))?;
            let result: Vec<Value> = records
                .into_iter()
                .map(|r| {
                    json!({
                        "id": r.id,
                        "music_id": r.music_id,
                        "played_at": r.played_at.timestamp(),
                        "play_count": r.play_count,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_record_play" => {
            let music_id = params["music_id"].as_str().unwrap_or("").to_string();
            let record =
                music_api::record_play(music_id).map_err(|e| format!("记录播放失败: {}", e))?;
            Ok(json!({
                "id": record.id,
                "music_id": record.music_id,
                "played_at": record.played_at.timestamp(),
                "play_count": record.play_count,
            }))
        }

        "music_parse_cue" => {
            let cue_path = params["cue_path"].as_str().unwrap_or("").to_string();
            let sheet =
                music_api::parse_cue(cue_path).map_err(|e| format!("解析 CUE 文件失败: {}", e))?;
            Ok(json!({
                "title": sheet.title,
                "performer": sheet.performer,
                "audio_file": sheet.audio_file,
                "tracks": sheet.tracks.into_iter().map(|t| json!({
                    "title": t.title,
                    "performer": t.performer,
                    "start_ms": t.start_ms,
                    "end_ms": t.end_ms,
                    "track_number": t.track_number,
                })).collect::<Vec<_>>(),
            }))
        }

        "music_get_eq_presets" => {
            let presets =
                music_api::get_eq_presets().map_err(|e| format!("获取均衡器预设失败: {}", e))?;
            let result: Vec<Value> = presets
                .into_iter()
                .map(|p| {
                    json!({
                        "id": p.id,
                        "name": p.name,
                        "bands": p.bands,
                        "is_builtin": p.is_builtin,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "music_save_eq_preset" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let bands: Vec<f32> = params["bands"]
                .as_array()
                .map(|arr| {
                    arr.iter()
                        .filter_map(|v| v.as_f64().map(|f| f as f32))
                        .collect()
                })
                .unwrap_or_default();
            let preset = music_api::save_eq_preset(name, bands)
                .map_err(|e| format!("保存均衡器预设失败: {}", e))?;
            Ok(json!({
                "id": preset.id,
                "name": preset.name,
                "bands": preset.bands,
                "is_builtin": preset.is_builtin,
            }))
        }

        "music_delete_eq_preset" => {
            let preset_id = params["preset_id"].as_str().unwrap_or("").to_string();
            music_api::delete_eq_preset(preset_id)
                .map_err(|e| format!("删除均衡器预设失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        // ── 流水账（记账 + 邮件账单自动入账）───────────────────────────────────
        "ledger_list_accounts" => ledger_json(ledger_module::api::ledger_list_accounts(), "获取账户列表"),
        "ledger_upsert_account" => ledger_scalar(
            ledger_module::api::ledger_upsert_account(s_field(&params, "account_json")),
            "id",
            "保存账户",
        ),
        "ledger_delete_account" => ledger_text(ledger_module::api::ledger_delete_account(i_field(&params, "id")), "删除账户"),

        "ledger_list_categories" => ledger_json(
            ledger_module::api::ledger_list_categories(s_field(&params, "direction")),
            "获取类别列表",
        ),
        "ledger_upsert_category" => ledger_scalar(
            ledger_module::api::ledger_upsert_category(s_field(&params, "category_json")),
            "id",
            "保存类别",
        ),
        "ledger_delete_category" => ledger_text(ledger_module::api::ledger_delete_category(i_field(&params, "id")), "删除类别"),
        "ledger_list_merchant_memory" => {
            ledger_json(ledger_module::api::ledger_list_merchant_memory(), "获取商户记忆")
        }
        "ledger_forget_merchant" => ledger_void(
            ledger_module::api::ledger_forget_merchant(s_field(&params, "merchant_key")),
            "清除商户记忆",
        ),

        "ledger_list_transactions" => ledger_json(
            ledger_module::api::ledger_list_transactions(s_field(&params, "filter_json")),
            "获取流水",
        ),
        "ledger_count_transactions" => ledger_scalar(
            ledger_module::api::ledger_count_transactions(s_field(&params, "filter_json")),
            "count",
            "统计流水条数",
        ),
        "ledger_add_transaction" => ledger_scalar(
            ledger_module::api::ledger_add_transaction(s_field(&params, "tx_json")),
            "id",
            "新增流水",
        ),
        "ledger_update_transaction" => ledger_void(
            ledger_module::api::ledger_update_transaction(s_field(&params, "tx_json")),
            "修改流水",
        ),
        "ledger_delete_transaction" => ledger_flag(
            ledger_module::api::ledger_delete_transaction(i_field(&params, "id")),
            "删除流水",
        ),
        "ledger_check_duplicate" => ledger_json(
            ledger_module::api::ledger_check_duplicate(s_field(&params, "dup_json")),
            "流水查重",
        ),

        "ledger_stats_by_day" => ledger_json(
            ledger_module::api::ledger_stats_by_day(s_field(&params, "filter_json")),
            "按天统计",
        ),
        "ledger_stats_by_category" => ledger_json(
            ledger_module::api::ledger_stats_by_category(s_field(&params, "filter_json")),
            "按类别统计",
        ),
        "ledger_stats_by_merchant" => ledger_json(
            ledger_module::api::ledger_stats_by_merchant(
                s_field(&params, "filter_json"),
                i_field(&params, "top"),
            ),
            "按商户统计",
        ),
        "ledger_stats_summary" => ledger_json(
            ledger_module::api::ledger_stats_summary(s_field(&params, "filter_json")),
            "区间汇总",
        ),
        "ledger_stats_by_month" => ledger_json(
            ledger_module::api::ledger_stats_by_month(i_field(&params, "months")),
            "按月统计",
        ),

        "ledger_list_rules" => ledger_json(ledger_module::api::ledger_list_rules(), "获取邮箱规则"),
        "ledger_upsert_rule" => ledger_scalar(
            ledger_module::api::ledger_upsert_rule(
                s_field(&params, "rule_json"),
                s_field(&params, "password"),
            ),
            "id",
            "保存邮箱规则",
        ),
        "ledger_delete_rule" => {
            ledger_void(ledger_module::api::ledger_delete_rule(i_field(&params, "id")), "删除邮箱规则")
        }
        "ledger_set_rule_enabled" => ledger_void(
            ledger_module::api::ledger_set_rule_enabled(i_field(&params, "id"), b_field(&params, "enabled")),
            "切换邮箱规则开关",
        ),
        "ledger_has_rule_password" => ledger_flag(
            ledger_module::api::ledger_has_rule_password(i_field(&params, "rule_id")),
            "查询邮箱口令状态",
        ),
        "ledger_templates" => ledger_json(ledger_module::api::ledger_templates(), "获取解析模板"),
        "ledger_parse_preview" => ledger_text(
            ledger_module::api::ledger_parse_preview(
                s_field(&params, "html"),
                s_field(&params, "template_id"),
                s_field(&params, "template_config"),
            ),
            "解析预览",
        ),

        // 联网的三个动作：阻塞 TLS 必须离开 worker 线程，口令只在这一跳短暂出现
        "ledger_check_rule" => {
            let rule_id = i_field(&params, "rule_id");
            let password = s_field(&params, "password");
            let text = ledger_blocking("邮件收信", move || {
                ledger_module::api::ledger_check_rule(rule_id, password)
            })
            .await?;
            Ok(json!({ "text": text }))
        }
        "ledger_backfill_rule" => {
            let rule_id = i_field(&params, "rule_id");
            let password = s_field(&params, "password");
            let limit = u_field(&params, "limit");
            let text = ledger_blocking("邮件历史回补", move || {
                ledger_module::api::ledger_backfill_rule(rule_id, password, limit)
            })
            .await?;
            Ok(json!({ "text": text }))
        }
        "ledger_fetch_emails" => {
            let config_json = s_field(&params, "config_json");
            let password = s_field(&params, "password");
            let limit = u_field(&params, "limit");
            let text = ledger_blocking("邮件试收取", move || {
                ledger_module::api::ledger_fetch_emails(config_json, password, limit)
            })
            .await?;
            ledger_json(Ok(text), "邮件试收取")
        }
        "ledger_test_connection" => {
            let config_json = s_field(&params, "config_json");
            let password = s_field(&params, "password");
            let want_folders = b_field(&params, "want_folders");
            let text = ledger_blocking("邮箱连接自检", move || {
                ledger_module::api::ledger_test_connection(config_json, password, want_folders)
            })
            .await?;
            ledger_json(Ok(text), "邮箱连接自检")
        }

        "ledger_list_pending" => ledger_json(
            ledger_module::api::ledger_list_pending(i_field(&params, "limit")),
            "获取待确认账单",
        ),
        "ledger_list_received_emails" => ledger_json(
            ledger_module::api::ledger_list_received_emails(i_field(&params, "limit")),
            "获取已收邮件",
        ),
        "ledger_email_transactions" => ledger_json(
            ledger_module::api::ledger_email_transactions(i_field(&params, "email_id")),
            "获取邮件对应流水",
        ),
        "ledger_pending_count" => {
            ledger_scalar(ledger_module::api::ledger_pending_count(), "count", "统计待确认数")
        }
        "ledger_confirm_tx" => ledger_void(
            ledger_module::api::ledger_confirm_tx(
                i_field(&params, "tx_id"),
                s_field(&params, "patch_json"),
            ),
            "确认入账",
        ),
        "ledger_confirm_all" => ledger_scalar(
            ledger_module::api::ledger_confirm_all(
                i_field(&params, "email_id"),
                s_field(&params, "patch_json"),
            ),
            "count",
            "整封确认入账",
        ),
        "ledger_ignore_tx" => ledger_void(
            ledger_module::api::ledger_ignore_tx(i_field(&params, "tx_id")),
            "忽略流水",
        ),
        "ledger_ignore_email" => ledger_scalar(
            ledger_module::api::ledger_ignore_email(i_field(&params, "email_id")),
            "count",
            "忽略整封邮件",
        ),
        "ledger_purge_email" => ledger_scalar(
            ledger_module::api::ledger_purge_email(i_field(&params, "email_id")),
            "count",
            "清除邮件流水",
        ),

        "ledger_scheduler_start" => ledger_void(ledger_module::api::ledger_scheduler_start(), "启动自动收信"),
        "ledger_scheduler_stop" => ledger_void(ledger_module::api::ledger_scheduler_stop(), "停止自动收信"),
        "ledger_scheduler_status" => {
            ledger_json(ledger_module::api::ledger_scheduler_status(), "获取调度状态")
        }
        "ledger_get_logs" => ledger_json(
            ledger_module::api::ledger_get_logs(i_field(&params, "limit")),
            "获取收信日志",
        ),
        "ledger_clear_logs" => ledger_void(ledger_module::api::ledger_clear_logs(), "清空收信日志"),

        // ── 未知动作 ─────────────────────────────────────────────────────────
        _ => Err(format!("不支持的动作: {}", action)),
    }
}

/// 按原始目录结构导入：以导入根目录名在 [base_folder_id] 下**新建**同名包裹
/// 文件夹（同名允许共存，不与既有文件夹合并），再按相对层级建树并移入集合；
/// 集合目录不在根目录之下时直接挂到包裹文件夹下；返回归档后的集合列表。
fn import_collections_with_structure(
    root: &str,
    collections: Vec<media_collection::MediaCollection>,
    base_folder_id: &Option<String>,
    display_name: Option<&str>,
) -> Result<Vec<media_collection::MediaCollection>, String> {
    let root_norm = root.trim_end_matches(['/', '\\']);
    // 每次导入独立成树：根层新建同名夹（与客户端本地导入语义一致），
    // 树内层级只复用本次新建的节点，绝不落进用户既有的同名旧夹。
    // 显示名优先用客户端传入的原目录名（磁盘目录可能被唯一化过）。
    let root_name = display_name
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| {
            root_norm
                .rsplit(['/', '\\'])
                .find(|s| !s.is_empty())
                .unwrap_or("")
                .to_string()
        });
    let effective_base: Option<String> = if root_name.is_empty() {
        base_folder_id.clone()
    } else {
        Some(create_folder(&root_name, base_folder_id)?)
    };
    let mut folder_cache: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    let mut imported = Vec::new();
    for collection in collections {
        // 集合目录相对导入根目录的路径（非后代目录时跳过层级创建）
        let rel = collection
            .folder_path
            .trim_end_matches(['/', '\\'])
            .strip_prefix(root_norm)
            .map(|r| r.trim_start_matches(['/', '\\']).to_string());
        let mut parent_id: Option<String> = effective_base.clone();
        if let Some(rel) = rel {
            let mut acc = String::new();
            for segment in rel.split(['/', '\\']).filter(|s| !s.is_empty()) {
                if !acc.is_empty() {
                    acc.push('/');
                }
                acc.push_str(segment);
                let folder_id = match folder_cache.get(&acc) {
                    Some(id) => id.clone(),
                    None => {
                        let folder = find_or_create_folder(segment, &parent_id)?;
                        folder_cache.insert(acc.clone(), folder.clone());
                        folder
                    }
                };
                parent_id = Some(folder_id);
            }
        }
        if let Some(pid) = parent_id {
            require_changed(
                media_api::move_media_collection_to_folder(collection.id.clone(), Some(pid)),
                "移动集合",
                format!("集合不存在 {}", collection.id),
            )?;
        }
        imported.push(collection);
    }
    Ok(imported)
}

/// 在指定父文件夹下无条件新建文件夹（同名允许共存）；返回文件夹 ID。
fn create_folder(name: &str, parent_id: &Option<String>) -> Result<String, String> {
    let folder = match parent_id {
        Some(pid) => {
            // 导入树挂在 base_folder_id 之下：那个夹必须真存在，
            // 否则整棵新树会挂到一个看不见的父 id 上（列表刷新后消失）
            ensure_media_folder_exists(pid, "创建文件夹")?;
            media_api::create_child_media_folder(name.to_string(), pid.clone())
                .map_err(|e| format!("创建文件夹失败: {}", e))?
        }
        None => media_api::create_media_folder(name.to_string())
            .map_err(|e| format!("创建文件夹失败: {}", e))?,
    };
    Ok(folder.id)
}

/// 在指定父文件夹下查找同名子文件夹，不存在时创建；返回文件夹 ID。
/// 仅供「同一棵导入树内部」的层级复用（父节点是本次新建的夹）；
/// 跨次导入的根层一律走 [create_folder]，避免把新内容混进旧夹。
fn find_or_create_folder(name: &str, parent_id: &Option<String>) -> Result<String, String> {
    let existing = match parent_id {
        Some(pid) => media_api::get_child_media_folders(pid.clone())
            .map_err(|e| format!("获取子文件夹失败: {}", e))?
            .into_iter()
            .find(|f| f.name == name),
        None => media_api::get_all_media_folders()
            .map_err(|e| format!("获取文件夹失败: {}", e))?
            .into_iter()
            .find(|f| f.parent_id.is_none() && f.name == name),
    };
    if let Some(folder) = existing {
        return Ok(folder.id);
    }
    create_folder(name, parent_id)
}

/// 由文件夹下已有集合的磁盘位置反推「上传落点」。
///
/// `MediaFolder` 只有库内 ID，没有磁盘路径，所以唯一的线索是：
/// 该文件夹下每个集合的 `folder_path` 的**父目录**就是这个文件夹在磁盘上的目录。
///
/// 返回 `(落点, 候选目录)`：
/// - 落点非空 = 该文件夹的集合都在同一个父目录，可以直接用；
/// - 落点为空 = 文件夹还没有集合、或集合散落在多个父目录（歧义），
///   此时把候选目录交给客户端，由它走节点目录浏览器让用户手选。
fn resolve_folder_target_dir(folder_id: &str) -> Result<(String, Vec<String>), String> {
    let collections = media_api::get_all_media_collections()
        .map_err(|e| format!("获取媒体集合失败: {}", e))?;
    Ok(pick_folder_target_dir(folder_id, &collections))
}

/// `resolve_folder_target_dir` 的纯函数部分（不碰数据库，便于测试）。
fn pick_folder_target_dir(
    folder_id: &str,
    collections: &[media_collection::MediaCollection],
) -> (String, Vec<String>) {
    /// 收集去重后的父目录，保持出现顺序
    fn push_unique(list: &mut Vec<String>, value: String) {
        if !value.is_empty() && !list.contains(&value) {
            list.push(value);
        }
    }

    let mut own_parents: Vec<String> = Vec::new();
    let mut all_parents: Vec<String> = Vec::new();
    for collection in collections {
        let Some(parent) = Path::new(&collection.folder_path).parent() else {
            continue;
        };
        let parent = parent.to_string_lossy().to_string();
        push_unique(&mut all_parents, parent.clone());
        if collection.folder_id.as_deref() == Some(folder_id) {
            push_unique(&mut own_parents, parent);
        }
    }

    // 只有一个父目录才算无歧义；多个父目录时宁可让用户确认，也不猜一个写进去
    if own_parents.len() == 1 {
        let target = own_parents.remove(0);
        return (target, Vec::new());
    }
    if own_parents.len() > 1 {
        return (String::new(), own_parents);
    }
    (String::new(), all_parents)
}

/// 收集某文件夹及其全部子孙文件夹的库内 ID（用于按子树重扫封面）。
fn collect_descendant_folder_ids(root_id: &str) -> std::collections::HashSet<String> {
    let mut ids = std::collections::HashSet::new();
    let mut stack = vec![root_id.to_string()];
    while let Some(cur) = stack.pop() {
        if !ids.insert(cur.clone()) {
            continue;
        }
        if let Ok(children) = media_api::get_child_media_folders(cur) {
            stack.extend(children.into_iter().map(|f| f.id));
        }
    }
    ids
}

/// 导入后全量生成缩略图：收集集合内全部媒体文件与集合封面，
/// 后台线程按客户端封面请求宽度逐个生成并计入进度统计。
fn spawn_import_thumbnail_generation(
    collections: &[media_collection::MediaCollection],
    cover_width: u32,
) {
    let mut files = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for collection in collections {
        // 集合封面（视频首帧/音频内嵌封面）也一并预生成：
        // 否则客户端打开文件夹时仍要现场生成，表现为「点进去才开始出图」。
        if let Some(cover) = collection.cover_path.as_ref() {
            if !cover.is_empty() && seen.insert(cover.clone()) {
                files.push(cover.clone());
            }
        }
        if let Ok(items) = media_api::get_media_collection_items(collection.id.clone()) {
            for item in items {
                if seen.insert(item.file_path.clone()) {
                    files.push(item.file_path);
                }
            }
        }
    }
    super::media_handler::spawn_bulk_thumbnail_generation(files, cover_width);
}

/// 处理文件上传请求（待完善 multipart 解析）
pub async fn handle_upload(_req: Request<Body>) -> Result<Response<Body>, Infallible> {
    let response = NodeResponse::error("上传功能暂未实现（Rust 端）".to_string());
    Ok(Response::builder()
        .header("Content-Type", "application/json")
        .body(Body::from(serde_json::to_string(&response).unwrap()))
        .unwrap())
}

// ── 工具函数 ─────────────────────────────────────────────────────────────────

/// 读取章节计数缓存
pub fn load_chapter_count_map() -> std::collections::HashMap<String, i32> {
    let path = get_app_data_path("chapter_counts.json");
    if let Ok(content) = fs::read_to_string(&path) {
        if let Ok(map) = serde_json::from_str(&content) {
            return map;
        }
    }
    std::collections::HashMap::new()
}

/// 获取应用数据路径
pub fn get_app_data_path(filename: &str) -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        let home = std::env::var("HOME").unwrap_or_default();
        PathBuf::from(home)
            .join("Library/Application Support/com.slime.works")
            .join(filename)
    }
    #[cfg(target_os = "windows")]
    {
        let appdata = std::env::var("APPDATA").unwrap_or_default();
        PathBuf::from(appdata).join("slimeworks").join(filename)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        let home = std::env::var("HOME").unwrap_or_default();
        PathBuf::from(home)
            .join(".local/share/slimeworks")
            .join(filename)
    }
}

/// 编码封面图片到 Base64（仅限小于 256KB 的图片）
pub fn encode_cover_base64(cover_path: &Option<String>) -> Option<String> {
    let path = cover_path.as_ref()?;
    if path.is_empty() {
        return None;
    }
    let file_path = Path::new(path);
    if !file_path.exists() {
        return None;
    }
    let metadata = fs::metadata(file_path).ok()?;
    if metadata.len() > 256 * 1024 {
        return None;
    }
    let bytes = fs::read(file_path).ok()?;
    Some(base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        &bytes,
    ))
}

/// 提取图片扩展名
pub fn extract_image_ext(path: &str) -> &'static str {
    let lower = path.to_lowercase();
    if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "jpg"
    } else if lower.ends_with(".webp") {
        "webp"
    } else {
        "png"
    }
}

/// 解析 list_novels 的 with_cover 参数。
///
/// 缺省（旧客户端不带参数）必须是 true——列表继续内嵌封面 base64，行为逐字节不变；
/// 只有显式传 false（布尔或字符串 "false"，兼容不同客户端的 JSON 习惯）才跳过封面。
pub fn novels_with_cover(params: &Value) -> bool {
    match params.get("with_cover") {
        None | Some(Value::Null) => true,
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => !s.eq_ignore_ascii_case("false"),
        // 其它类型按「未显式关闭」处理，保持旧口径
        Some(_) => true,
    }
}

/// 组装小说列表 JSON（list_novels 专用，独立成函数便于用纯内存数据做兼容测试）。
///
/// with_cover=false 时 cover_base64 恒为 null 且不读盘；其余字段
/// （含 cover_path/cover_ext，供客户端拼按需封面 URL 或判有无封面）两种模式完全一致。
pub fn build_novel_list_json(
    novels: Vec<novel_reader::types::NovelMetadata>,
    folder_map: &std::collections::HashMap<String, String>,
    chapter_counts: &std::collections::HashMap<String, i32>,
    params: &Value,
) -> Vec<Value> {
    let with_cover = novels_with_cover(params);
    novels
        .into_iter()
        .map(|n| {
            let cover_base64 = if with_cover {
                encode_cover_base64(&n.cover_path)
            } else {
                None
            };
            let cover_ext = extract_image_ext(n.cover_path.as_deref().unwrap_or("")).to_string();
            json!({
                "id": n.id,
                "title": n.title,
                "author": n.author,
                "file_path": n.file_path,
                "format": n.format.as_str(),
                "file_size": n.file_size.to_string(),
                "modified_at": n.modified_at.to_string(),
                "added_at": n.added_at.to_string(),
                "progress": n.progress,
                "last_read_at": n.last_read_at.map(|t| t.to_string()),
                "cover_path": n.cover_path,
                "cover_base64": cover_base64,
                "cover_ext": cover_ext,
                "folder_id": n.folder_id,
                "folder_name": n.folder_id.as_ref().and_then(|fid| folder_map.get(fid).cloned()),
                "chapter_count": chapter_counts.get(n.id.as_str()).copied(),
                "custom_order": n.custom_order,
                "is_favorite": n.is_favorite,
                "tags": n.tags,
                "notes": n.notes,
            })
        })
        .collect()
}

/// 封面读取失败类别（语义与 media_handler::MediaPathError 同一套路，映射各自处理）。
#[derive(Debug, PartialEq, Eq)]
pub enum NovelCoverError {
    /// 缺 novel_id 参数 → 400
    MissingId,
    /// 库中无此书 → 404
    NotFound,
    /// 书存在但没有封面（字段为空/文件缺失）→ 404
    NoCover,
}

impl NovelCoverError {
    pub fn message(&self) -> String {
        match self {
            NovelCoverError::MissingId => "missing novel_id".to_string(),
            NovelCoverError::NotFound => "novel not found".to_string(),
            NovelCoverError::NoCover => "no cover available".to_string(),
        }
    }
}

/// 按需读取小说封面字节（GET /node/novel_cover 的实现体）。
///
/// 路径只从书库元数据反查，绝不接受客户端直接传文件路径——授权语义与 /node/media
/// 一致（mod.rs 连接层统一校验 X-SW-Auth / ?sw_auth），但攻击面更小：
/// 拿到授权也只能取「已入库书籍的封面」，不能借道读任意文件。
/// width>0 时复用媒体线的缩略图链路（内存缓存 + JPEG），失败回退读原图。
pub fn read_novel_cover_bytes(
    novel_id: &str,
    width: u32,
) -> Result<(Vec<u8>, String), NovelCoverError> {
    if novel_id.is_empty() {
        return Err(NovelCoverError::MissingId);
    }
    let novels = novel_api::get_all_novels().map_err(|_| NovelCoverError::NotFound)?;
    let novel = novels
        .into_iter()
        .find(|n| n.id == novel_id)
        .ok_or(NovelCoverError::NotFound)?;
    let cover_path = novel
        .cover_path
        .filter(|p| !p.is_empty())
        .ok_or(NovelCoverError::NoCover)?;
    // 封面文件可能已被外部删除：与「无封面」同一语义，客户端显示占位即可
    let path = Path::new(&cover_path);
    if !path.is_file() {
        return Err(NovelCoverError::NoCover);
    }
    if width > 0 {
        if let Some(bytes) = media_api::generate_thumbnail_bytes(cover_path.clone(), width) {
            return Ok((bytes, "image/jpeg".to_string()));
        }
    }
    let bytes = fs::read(path).map_err(|_| NovelCoverError::NoCover)?;
    let content_type = super::media_handler::guess_media_content_type(&cover_path);
    Ok((bytes, content_type))
}

/// 写入临时图片文件
fn write_temp_image(bytes: &[u8], ext: &str) -> Result<String, String> {
    // 扩展名白名单：ext 来自请求参数，直接拼进文件名可被塞进路径片段
    let safe_ext = match ext.trim().trim_start_matches('.').to_lowercase().as_str() {
        "jpg" | "jpeg" => "jpg",
        "png" => "png",
        "webp" => "webp",
        "gif" => "gif",
        "bmp" => "bmp",
        _ => "png",
    };
    let temp_dir = std::env::temp_dir().join("slime_node_cover");
    fs::create_dir_all(&temp_dir).map_err(|e| format!("创建临时目录失败: {}", e))?;
    // 文件名必须唯一：固定 cover.ext 会让并发封面上传互相覆盖，
    // 结果是小说 A 配上小说 B 的封面
    let unique = format!(
        "cover_{}_{}.{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0),
        safe_ext
    );
    let file_path = temp_dir.join(unique);
    fs::write(&file_path, bytes).map_err(|e| format!("写入临时文件失败: {}", e))?;
    Ok(file_path.to_string_lossy().to_string())
}

#[cfg(test)]
mod folder_target_tests {
    use super::*;
    use chrono::TimeZone;
    use media_collection::MediaCollection;

    fn collection(id: &str, folder_path: &str, folder_id: Option<&str>) -> MediaCollection {
        let ts = chrono::Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap();
        MediaCollection {
            id: id.to_string(),
            title: id.to_string(),
            folder_path: folder_path.to_string(),
            folder_id: folder_id.map(|s| s.to_string()),
            cover_path: None,
            item_count: 0,
            created_at: ts,
            updated_at: ts,
        }
    }

    #[test]
    fn single_parent_dir_is_the_target() {
        let collections = vec![
            collection("c1", "/library/Lori/AlbumA", Some("f1")),
            collection("c2", "/library/Lori/AlbumB", Some("f1")),
            collection("c3", "/library/Other/AlbumC", Some("f2")),
        ];
        let (target, candidates) = pick_folder_target_dir("f1", &collections);
        assert_eq!(target, "/library/Lori");
        assert!(candidates.is_empty());
    }

    #[test]
    fn ambiguous_folder_returns_candidates_and_no_target() {
        let collections = vec![
            collection("c1", "/diskA/Lori/AlbumA", Some("f1")),
            collection("c2", "/diskB/Lori/AlbumB", Some("f1")),
        ];
        let (target, candidates) = pick_folder_target_dir("f1", &collections);
        assert_eq!(target, "");
        assert_eq!(candidates, vec!["/diskA/Lori".to_string(), "/diskB/Lori".to_string()]);
    }

    #[test]
    fn empty_folder_falls_back_to_all_library_roots() {
        let collections = vec![
            collection("c1", "/library/A/x", Some("f1")),
            collection("c2", "/media/B/y", Some("f2")),
        ];
        let (target, candidates) = pick_folder_target_dir("f-empty", &collections);
        assert_eq!(target, "");
        // 没有该文件夹的集合时，给出所有集合的父目录供用户手选
        assert_eq!(candidates, vec!["/library/A".to_string(), "/media/B".to_string()]);
    }

    #[test]
    fn empty_folder_id_means_library_root() {
        // 空 folder_id 表示「媒体库根目录」：无匹配集合 → 空 target + 全部库根候选
        let collections = vec![
            collection("c1", "/library/A/x", Some("f1")),
            collection("c2", "/media/B/y", Some("f2")),
        ];
        let (target, candidates) = pick_folder_target_dir("", &collections);
        assert_eq!(target, "");
        assert_eq!(candidates, vec!["/library/A".to_string(), "/media/B".to_string()]);
    }

    #[test]
    fn collection_without_parent_is_skipped() {
        let collections = vec![collection("c1", "orphan", Some("f1"))];
        let (target, candidates) = pick_folder_target_dir("f1", &collections);
        assert_eq!(target, "");
        assert!(candidates.is_empty());
    }
}

// ── dispatch_action 分发层测试（仅覆盖不触碰 media_collection / novel 真实 DB 的分支）──
#[cfg(test)]
mod dispatch_action_tests {
    use super::*;

    /// 构造测试用节点配置（全部显式赋值，避免依赖 Default 细节）
    fn test_config() -> NodeServerConfig {
        NodeServerConfig {
            host: "127.0.0.1".to_string(),
            port: 19999,
            name: "单元测试节点".to_string(),
            auth_code_hash: None,
        }
    }

    /// 同步驱动 async dispatch_action：复用 node_server 的全局共享 runtime
    fn call(action: &str, params: Value) -> Result<Value, String> {
        super::super::shared_runtime()
            .block_on(dispatch_action(action, params, &test_config()))
    }

    /// 生成本次测试专属临时目录（唯一后缀，避免并发测试互相踩踏）
    fn fresh_temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "slime_handlers_test_{}_{}",
            tag,
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    // ── 状态查询类（纯内存分支） ────────────────────────────────────────────

    #[test]
    fn ping_returns_pong() {
        // ping 不依赖任何外部状态，仅验证 success 包装格式
        assert_eq!(call("ping", Value::Null), Ok(json!({"pong": true})));
    }

    #[test]
    fn get_status_echoes_config_name_and_port() {
        // get_status 直接回显传入的 config，验证分发层能把配置透传进包装 JSON
        let result = call("get_status", Value::Null).expect("get_status 应成功");
        assert_eq!(result["name"], json!("单元测试节点"));
        assert_eq!(result["port"], json!(19999));
        assert_eq!(result["version"], json!("1.0"));
    }

    #[test]
    fn get_thumb_progress_returns_string_counters() {
        // 只读全局进度计数器（不落盘不查库）；不断言具体值，
        // 因为同进程其他测试可能并发触碰缩略图计数。
        let result = call("get_thumb_progress", Value::Null).expect("thumb progress 应成功");
        let total = result["total"].as_str().expect("total 应为字符串");
        let completed = result["completed"].as_str().expect("completed 应为字符串");
        assert!(total.parse::<u64>().is_ok());
        assert!(completed.parse::<u64>().is_ok());
    }

    // ── 未知 action 与参数校验分支 ─────────────────────────────────────────

    #[test]
    fn unknown_action_returns_unsupported_error() {
        // 未知 action 走 match 兜底分支，错误文案含原 action 名
        let err = call("no_such_action", json!({"foo": 1})).unwrap_err();
        assert!(err.contains("不支持的动作"), "实际错误: {}", err);
        assert!(err.contains("no_such_action"));
    }

    #[test]
    fn search_all_novels_with_empty_keyword_short_circuits() {
        // keyword 为空时在触达 novel DB 之前短路返回空数组（可安全断言）
        assert_eq!(
            call("search_all_novels", json!({"keyword": ""})).unwrap(),
            json!([])
        );
        // 缺参数（None as_str → ""）同样短路
        assert_eq!(
            call("search_all_novels", json!({})).unwrap(),
            json!([])
        );
    }

    #[test]
    fn update_novel_cover_base64_param_validation_before_any_db_write() {
        // novel_id / image_base64 为空的校验发生在解码与写盘之前
        let err = call("update_novel_cover_base64", json!({"novel_id": "", "image_base64": "aGk="}))
            .unwrap_err();
        assert!(err.contains("novel_id or image_base64 is empty"), "实际: {}", err);
        let err = call("update_novel_cover_base64", json!({"novel_id": "n1"})).unwrap_err();
        assert!(err.contains("novel_id or image_base64 is empty"));

        // 非法 Base64：解码错误在触达 novel DB 之前返回（不会写入临时文件之后更新库）
        let err = call(
            "update_novel_cover_base64",
            json!({"novel_id": "n1", "image_base64": "!!!不是合法base64!!!"}),
        )
        .unwrap_err();
        assert!(err.contains("Base64 解码失败"), "实际: {}", err);
    }

    // ── list_directories：纯文件系统分支（不查库） ─────────────────────────

    #[test]
    fn list_directories_nonexistent_path_returns_empty_array() {
        // 不存在的路径短路返回空数组（Ok 包装而非 Err）
        let result = call(
            "list_directories",
            json!({"path": "/definitely/not/exist/slime_works_test"}),
        )
        .expect("不存在路径应返回 Ok 空数组");
        assert_eq!(result, json!([]));
    }

    #[test]
    fn list_directories_returns_sorted_dirs_only() {
        // 真实临时目录：只列子目录、按字符串升序
        let root = fresh_temp_dir("list_dirs");
        let beta = root.join("beta");
        let alpha = root.join("Alpha");
        fs::create_dir_all(&beta).unwrap();
        fs::create_dir_all(&alpha).unwrap();
        fs::write(root.join("a_file.txt"), b"x").unwrap();

        let result = call("list_directories", json!({"path": root.to_string_lossy()}))
            .expect("list_directories 应成功");
        let list = result.as_array().expect("应返回数组");
        assert_eq!(
            list,
            &vec![
                json!(alpha.to_string_lossy()),
                json!(beta.to_string_lossy()),
            ]
        );

        fs::remove_dir_all(&root).ok();
    }

    #[test]
    fn list_directories_missing_path_defaults_to_root() {
        // 缺 path 参数时默认 "/"：目录存在，应返回数组（内容不做断言，跨平台不稳定）
        let result = call("list_directories", json!({})).expect("默认路径应成功");
        assert!(result.is_array());
    }

    // ── list_novels with_cover 兼容性（纯内存组装，不触 novel DB） ──────────

    /// 构造一本带真实封面文件的测试书元数据
    fn novel_with_cover(dir: &Path) -> novel_reader::types::NovelMetadata {
        let cover = dir.join("cover.png");
        fs::write(&cover, b"fake-png-bytes").unwrap();
        novel_reader::types::NovelMetadata {
            id: "n1".to_string(),
            title: "带封面书".to_string(),
            author: None,
            file_path: dir.join("book.txt").to_string_lossy().into_owned(),
            format: novel_reader::types::NovelFormat::Txt,
            file_size: 10,
            modified_at: chrono::Utc::now(),
            is_favorite: false,
            tags: vec![],
            added_at: chrono::Utc::now(),
            progress: 0.0,
            current_chapter_id: None,
            last_read_at: None,
            cover_path: Some(cover.to_string_lossy().into_owned()),
            folder_id: None,
            custom_order: None,
            notes: None,
        }
    }

    #[test]
    fn novels_with_cover_defaults_true_for_legacy_clients() {
        // 旧客户端不带参数：必须保持 true（行为不变的关键约定）
        assert!(novels_with_cover(&json!({})));
        assert!(novels_with_cover(&Value::Null));
        assert!(novels_with_cover(&json!({"with_cover": null})));
        // 显式 true / false
        assert!(novels_with_cover(&json!({"with_cover": true})));
        assert!(!novels_with_cover(&json!({"with_cover": false})));
        // 字符串形式（不同客户端 JSON 习惯）
        assert!(!novels_with_cover(&json!({"with_cover": "false"})));
        assert!(novels_with_cover(&json!({"with_cover": "true"})));
    }

    #[test]
    fn list_novels_without_param_keeps_cover_base64() {
        // 兼容性硬约束：不带 with_cover 时列表必须仍内嵌封面 base64（旧客户端唯一来源）
        let dir = fresh_temp_dir("list_novels_legacy");
        let novels = vec![novel_with_cover(&dir)];
        let folders = std::collections::HashMap::new();
        let counts = std::collections::HashMap::new();

        let legacy = build_novel_list_json(novels.clone(), &folders, &counts, &json!({}));
        assert_eq!(legacy.len(), 1);
        assert!(
            legacy[0]["cover_base64"].is_string(),
            "旧口径必须内嵌封面 base64: {}",
            legacy[0]
        );
        assert!(legacy[0]["cover_path"].is_string());

        // 显式 true 与缺省逐字段一致
        let explicit = build_novel_list_json(novels, &folders, &counts, &json!({"with_cover": true}));
        // modified_at/added_at 用同一元数据实例生成，值应一致
        assert_eq!(legacy[0]["cover_base64"], explicit[0]["cover_base64"]);
        assert_eq!(legacy[0]["id"], explicit[0]["id"]);
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn list_novels_with_cover_false_skips_base64_keeps_metadata() {
        let dir = fresh_temp_dir("list_novels_nocover");
        let novels = vec![novel_with_cover(&dir)];
        let folders = std::collections::HashMap::new();
        let counts = std::collections::HashMap::new();

        let lite = build_novel_list_json(novels.clone(), &folders, &counts, &json!({"with_cover": false}));
        assert_eq!(lite.len(), 1);
        assert!(lite[0]["cover_base64"].is_null(), "false 时不得内嵌 base64");
        // 其余元数据字段保留：客户端靠 cover_path 判有无封面
        assert!(lite[0]["cover_path"].is_string());
        assert_eq!(lite[0]["title"], json!("带封面书"));
        assert_eq!(lite[0]["format"], json!("txt"));

        // 除封面 base64 外，两种模式的字段集合与取值一致
        let full = build_novel_list_json(novels, &folders, &counts, &json!({}));
        let mut lite_map = lite[0].as_object().unwrap().clone();
        let mut full_map = full[0].as_object().unwrap().clone();
        lite_map.remove("cover_base64");
        full_map.remove("cover_base64");
        assert_eq!(lite_map, full_map);
        fs::remove_dir_all(&dir).ok();
    }
}
