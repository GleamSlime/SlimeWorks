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
            media_api::delete_smart_folder(target_id)
                .map_err(|e| format!("删除智能文件夹失败: {}", e))?;
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
            let parsed: Value =
                serde_json::from_str(&aggregated).map_err(|e| format!("解析聚合数据失败: {}", e))?;
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

        // ── 未知动作 ─────────────────────────────────────────────────────────
        _ => Err(format!("不支持的动作: {}", action)),
    }
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

/// 写入临时图片文件
fn write_temp_image(bytes: &[u8], ext: &str) -> Result<String, String> {
    let temp_dir = std::env::temp_dir().join("slime_node_cover");
    fs::create_dir_all(&temp_dir).map_err(|e| format!("创建临时目录失败: {}", e))?;
    let file_path = temp_dir.join(format!("cover.{}", ext));
    fs::write(&file_path, bytes).map_err(|e| format!("写入临时文件失败: {}", e))?;
    Ok(file_path.to_string_lossy().to_string())
}
