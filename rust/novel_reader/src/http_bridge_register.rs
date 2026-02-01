/// HTTP Bridge注册模块
/// 将novel_reader的FRB接口注册到HTTP Bridge
use serde_json::{json, Value};
use std::sync::Arc;

/// 注册所有novel_reader的接口到HTTP Bridge
pub async fn register_all_handlers() -> anyhow::Result<()> {
    // 获取所有小说
    http_bridge::register_handler(
        "novel_reader".to_string(),
        "get_all_novels".to_string(),
        Arc::new(|_params: Value| match crate::api::get_all_novels() {
            Ok(novels) => {
                let json_novels = novels
                    .iter()
                    .map(|n| {
                        json!({
                            "id": n.id,
                            "title": n.title,
                            "author": n.author,
                            "file_path": n.file_path,
                            "format": format!("{:?}", n.format),
                            "progress": n.progress,
                            "added_at": n.added_at.to_rfc3339(),
                            "last_read_at": n.last_read_at.map(|dt| dt.to_rfc3339()),
                            "custom_order": n.custom_order,
                            "folder_id": n.folder_id,
                        })
                    })
                    .collect::<Vec<_>>();

                Ok(json!(json_novels))
            }
            Err(e) => Err(e),
        }),
    )
    .await?;

    // 添加小说
    http_bridge::register_handler(
        "novel_reader".to_string(),
        "add_novel".to_string(),
        Arc::new(|params: Value| {
            let file_path = params["file_path"]
                .as_str()
                .ok_or("Missing file_path parameter")?;

            match crate::api::add_novel(file_path.to_string()) {
                Ok(novel) => Ok(json!({
                    "id": novel.id,
                    "title": novel.title,
                    "author": novel.author,
                })),
                Err(e) => Err(e),
            }
        }),
    )
    .await?;

    // 获取章节内容
    http_bridge::register_handler(
        "novel_reader".to_string(),
        "get_chapter_content".to_string(),
        Arc::new(|params: Value| {
            let file_path = params["file_path"]
                .as_str()
                .ok_or("Missing file_path parameter")?
                .to_string();
            let chapter_index = params["chapter_index"]
                .as_u64()
                .ok_or("Missing chapter_index parameter")? as usize;

            match crate::api::get_chapter_content(file_path, chapter_index) {
                Ok(content) => Ok(json!(content)),
                Err(e) => Err(e),
            }
        }),
    )
    .await?;

    // 搜索小说内容
    http_bridge::register_handler(
        "novel_reader".to_string(),
        "search_in_novel".to_string(),
        Arc::new(|params: Value| {
            let file_path = params["file_path"]
                .as_str()
                .ok_or("Missing file_path parameter")?
                .to_string();
            let keyword = params["keyword"]
                .as_str()
                .ok_or("Missing keyword parameter")?
                .to_string();

            match crate::api::search_in_novel(file_path, keyword) {
                Ok(matches) => {
                    let json_matches = matches
                        .iter()
                        .map(|m| {
                            json!({
                                "chapter_index": m.chapter_index,
                                "chapter_title": m.chapter_title,
                                "position": m.position,
                                "snippet": m.snippet,
                            })
                        })
                        .collect::<Vec<_>>();
                    Ok(json!(json_matches))
                }
                Err(e) => Err(e),
            }
        }),
    )
    .await?;

    // 更新阅读进度
    http_bridge::register_handler(
        "novel_reader".to_string(),
        "update_reading_progress".to_string(),
        Arc::new(|params: Value| {
            let novel_id = params["novel_id"]
                .as_str()
                .ok_or("Missing novel_id parameter")?
                .to_string();
            let progress = params["progress"]
                .as_f64()
                .ok_or("Missing progress parameter")? as f32;

            match crate::api::update_reading_progress(novel_id, progress) {
                Ok(success) => Ok(json!({"success": success})),
                Err(e) => Err(e),
            }
        }),
    )
    .await?;

    log::info!("novel_reader: Registered 5 HTTP bridge handlers");
    Ok(())
}
