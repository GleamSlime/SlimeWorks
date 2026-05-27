use super::types::*;
use super::NodeServerConfig;
use hyper::{Body, Request, Response};
use media_collection::api as media_api;
use novel_reader::api as novel_api;
use serde_json::{json, Value};
use std::convert::Infallible;
use std::fs;
use std::path::{Path, PathBuf};

/// 分发动作到对应的处理函数
pub async fn dispatch_action(
    action: &str,
    params: Value,
    config: &NodeServerConfig,
) -> Result<Value, String> {
    match action {
        // ── 状态查询 ─────────────────────────────────────────────────────────
        "ping" => Ok(json!({"pong": true})),

        "get_status" => Ok(json!({
            "name": config.name,
            "port": config.port,
            "version": "1.0",
        })),

        // ── 媒体集合操作 ─────────────────────────────────────────────────────
        "list_media_collections" => {
            let collections = media_api::get_all_media_collections()
                .map_err(|e| format!("获取媒体集合失败: {}", e))?;
            let stats = media_api::get_all_collection_stats()
                .map_err(|e| format!("获取集合统计失败: {}", e))?;
            let stats_map: std::collections::HashMap<_, _> = stats
                .into_iter()
                .map(|s| (s.collection_id.clone(), s))
                .collect();

            let result: Vec<Value> = collections
                .into_iter()
                .map(|c| {
                    let total_size = stats_map.get(&c.id).map(|s| s.total_size).unwrap_or(0);
                    json!({
                        "id": c.id,
                        "title": c.title,
                        "folder_path": c.folder_path,
                        "folder_id": c.folder_id,
                        "cover_path": c.cover_path,
                        "item_count": c.item_count.to_string(),
                        "created_at": c.created_at,
                        "updated_at": c.updated_at,
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
                    json!({
                        "id": f.id,
                        "name": f.name,
                        "created_at": f.created_at,
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
                "created_at": folder.created_at,
                "order": folder.order,
                "parent_id": folder.parent_id,
            }))
        }

        "create_child_media_folder" => {
            let name = params["name"].as_str().unwrap_or("").to_string();
            let parent_id = params["parent_id"].as_str().unwrap_or("").to_string();
            let folder = media_api::create_child_media_folder(name, parent_id)
                .map_err(|e| format!("创建子文件夹失败: {}", e))?;
            Ok(json!({
                "id": folder.id,
                "name": folder.name,
                "created_at": folder.created_at,
                "order": folder.order,
                "parent_id": folder.parent_id,
            }))
        }

        "rename_media_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            let name = params["name"].as_str().unwrap_or("").to_string();
            media_api::rename_media_folder(folder_id, name)
                .map_err(|e| format!("重命名文件夹失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "delete_media_folder" => {
            let folder_id = params["folder_id"].as_str().unwrap_or("").to_string();
            media_api::delete_media_folder(folder_id)
                .map_err(|e| format!("删除文件夹失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "scan_media_folders" => {
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            let collections = media_api::scan_media_folders(folder_path)
                .map_err(|e| format!("扫描媒体文件夹失败: {}", e))?;
            let result: Vec<Value> = collections
                .into_iter()
                .map(|c| {
                    json!({
                        "id": c.id,
                        "title": c.title,
                        "folder_path": c.folder_path,
                        "folder_id": c.folder_id,
                        "cover_path": c.cover_path,
                        "item_count": c.item_count.to_string(),
                        "created_at": c.created_at,
                        "updated_at": c.updated_at,
                    })
                })
                .collect();
            Ok(json!(result))
        }

        "import_media_folder" => {
            let folder_path = params["folder_path"].as_str().unwrap_or("").to_string();
            let collection = media_api::import_media_folder(folder_path)
                .map_err(|e| format!("导入媒体文件夹失败: {}", e))?;
            Ok(json!({
                "id": collection.id,
                "title": collection.title,
                "folder_path": collection.folder_path,
                "folder_id": collection.folder_id,
                "cover_path": collection.cover_path,
                "item_count": collection.item_count.to_string(),
                "created_at": collection.created_at,
                "updated_at": collection.updated_at,
            }))
        }

        "rename_media_collection" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            let title = params["title"].as_str().unwrap_or("").to_string();
            media_api::rename_media_collection(collection_id, title)
                .map_err(|e| format!("重命名媒体集合失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "delete_media_collection" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            media_api::delete_media_collection(collection_id)
                .map_err(|e| format!("删除媒体集合失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "move_media_collection_to_folder" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            let folder_id = params["folder_id"].as_str().map(|s| s.to_string());
            media_api::move_media_collection_to_folder(collection_id, folder_id)
                .map_err(|e| format!("移动媒体集合失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "delete_collection_local_files" => {
            let collection_id = params["collection_id"].as_str().unwrap_or("").to_string();
            let items = media_api::get_media_collection_items(collection_id).unwrap_or_default();
            let mut deleted_count = 0;
            for item in items {
                if fs::remove_file(&item.file_path).is_ok() {
                    deleted_count += 1;
                }
            }
            Ok(json!({"deleted": deleted_count}))
        }

        // ── 目录扫描 ─────────────────────────────────────────────────────────
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

        // ── 小说操作 ─────────────────────────────────────────────────────────
        "list_novels" => {
            let novels =
                novel_api::get_all_novels().map_err(|e| format!("获取小说列表失败: {}", e))?;
            let folders = novel_api::get_all_folders().unwrap_or_default();
            let folder_map: std::collections::HashMap<_, _> = folders
                .into_iter()
                .map(|f| (f.id.clone(), f.name))
                .collect();
            let chapter_counts = load_chapter_count_map();

            let result: Vec<Value> = novels
                .into_iter()
                .map(|n| {
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

        "delete_novel" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            novel_api::remove_novel(novel_id).map_err(|e| format!("删除小说失败: {}", e))?;
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
            novel_api::update_novel_tags(novel_id, tags)
                .map_err(|e| format!("更新小说标签失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "set_novel_favorite" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let is_favorite = params["is_favorite"].as_bool().unwrap_or(false);
            novel_api::set_novel_favorite(novel_id, is_favorite)
                .map_err(|e| format!("设置收藏状态失败: {}", e))?;
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

            // 如果有 is_favorite 字段则先更新收藏状态
            if let Some(is_favorite) = params.get("is_favorite").and_then(|v| v.as_bool()) {
                let _ = novel_api::set_novel_favorite(novel_id.clone(), is_favorite);
            }

            novel_api::update_novel_info(novel_id, title, author, notes, tags)
                .map_err(|e| format!("更新小说信息失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        "move_novel_to_folder" => {
            let novel_id = params["novel_id"].as_str().unwrap_or("").to_string();
            let folder_id = params["folder_id"].as_str().map(|s| s.to_string());
            novel_api::move_novel_to_folder(novel_id, folder_id)
                .map_err(|e| format!("移动小说到文件夹失败: {}", e))?;
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
            novel_api::update_novel_cover(novel_id, temp_path)
                .map_err(|e| format!("更新小说封面失败: {}", e))?;
            Ok(json!({"ok": true}))
        }

        // ── 智能文件夹（存储本地 JSON，保持与 Dart 端兼容） ─────────────────
        "list_smart_folders" => {
            let smart_folders = load_smart_folders();
            Ok(json!(smart_folders))
        }

        "create_smart_folder" => {
            let mut folders = load_smart_folders();
            let new_folder = json!({
                "id": format!("sf_{}", chrono::Utc::now().timestamp_millis()),
                "name": params["name"].as_str().unwrap_or(""),
                "regexPattern": params["regex_pattern"].as_str().unwrap_or(""),
                "targetFolderIds": params["target_folder_ids"].as_array().cloned().unwrap_or_default(),
                "regexTarget": params["regex_target"].as_str().unwrap_or("collectionName"),
                "fileTypeFilter": params["file_type_filter"].as_str().unwrap_or("all"),
            });
            folders.push(new_folder);
            save_smart_folders(&folders);
            Ok(json!(folders))
        }

        "update_smart_folder" => {
            let mut folders = load_smart_folders();
            let target_id = params["id"].as_str().unwrap_or("");
            if let Some(idx) = folders
                .iter()
                .position(|f| f["id"].as_str() == Some(target_id))
            {
                folders[idx] = json!({
                    "id": target_id,
                    "name": params["name"].as_str().unwrap_or(""),
                    "regexPattern": params["regex_pattern"].as_str().unwrap_or(""),
                    "targetFolderIds": params["target_folder_ids"].as_array().cloned().unwrap_or_default(),
                    "regexTarget": params["regex_target"].as_str().unwrap_or("collectionName"),
                    "fileTypeFilter": params["file_type_filter"].as_str().unwrap_or("all"),
                });
                save_smart_folders(&folders);
                Ok(json!(folders))
            } else {
                Err(format!("智能文件夹不存在: {}", target_id))
            }
        }

        "delete_smart_folder" => {
            let mut folders = load_smart_folders();
            let target_id = params["id"].as_str().unwrap_or("");
            folders.retain(|f| f["id"].as_str() != Some(target_id));
            save_smart_folders(&folders);
            Ok(json!({"ok": true}))
        }

        // ── 阿里云 DDNS 操作 ─────────────────────────────────────────────────
        "aliyun_get_status" => {
            let status = aliyun_module::api::aliyun_ddns_get_status()
                .map_err(|e| format!("获取阿里云状态失败: {}", e))?;
            let parsed: Value = serde_json::from_str(&status)
                .map_err(|e| format!("解析阿里云状态失败: {}", e))?;
            Ok(parsed)
        }

        "aliyun_get_logs" => {
            let logs = aliyun_module::api::aliyun_ddns_get_logs()
                .map_err(|e| format!("获取阿里云日志失败: {}", e))?;
            let parsed: Value = serde_json::from_str(&logs)
                .map_err(|e| format!("解析阿里云日志失败: {}", e))?;
            Ok(parsed)
        }

        "aliyun_get_watch_domains" => {
            let config = aliyun_module::api::aliyun_ddns_get_config()
                .map_err(|e| format!("获取阿里云配置失败: {}", e))?;
            let parsed: Value = serde_json::from_str(&config)
                .map_err(|e| format!("解析阿里云配置失败: {}", e))?;
            Ok(parsed.get("watch_domains").cloned().unwrap_or(json!([])))
        }

        "aliyun_check_and_update" => {
            let result = aliyun_module::api::aliyun_ddns_check_and_update().await
                .map_err(|e| format!("阿里云检查更新失败: {}", e))?;
            Ok(json!({"result": result}))
        }

        // ── 未知动作 ─────────────────────────────────────────────────────────
        _ => Err(format!("不支持的动作: {}", action)),
    }
}

/// 处理文件上传请求（待完善 multipart 解析）
pub async fn handle_upload(req: Request<Body>) -> Result<Response<Body>, Infallible> {
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

/// 读取智能文件夹列表
fn load_smart_folders() -> Vec<Value> {
    let path = get_app_data_path("smart_folders_data.json");
    if let Ok(content) = fs::read_to_string(&path) {
        if let Ok(folders) = serde_json::from_str(&content) {
            return folders;
        }
    }
    vec![]
}

/// 保存智能文件夹列表
fn save_smart_folders(folders: &[Value]) {
    let path = get_app_data_path("smart_folders_data.json");
    if let Some(parent) = Path::new(&path).parent() {
        let _ = fs::create_dir_all(parent);
    }
    let _ = fs::write(
        &path,
        serde_json::to_string_pretty(folders).unwrap_or_default(),
    );
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

/// 写入临时图片文件
fn write_temp_image(bytes: &[u8], ext: &str) -> Result<String, String> {
    let temp_dir = std::env::temp_dir().join("slime_node_cover");
    fs::create_dir_all(&temp_dir).map_err(|e| format!("创建临时目录失败: {}", e))?;
    let file_path = temp_dir.join(format!("cover.{}", ext));
    fs::write(&file_path, bytes).map_err(|e| format!("写入临时文件失败: {}", e))?;
    Ok(file_path.to_string_lossy().to_string())
}
