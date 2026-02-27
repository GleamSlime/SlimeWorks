use flutter_rust_bridge::frb;

use crate::types::{NovelFolder, NovelMetadata};

use super::{
    add_novel, get_app_data_dir, get_folder_list, get_library, move_novel_to_folder, remove_novel,
};

/// 更新阅读进度
#[frb(sync)]
pub fn update_reading_progress(novel_id: String, progress: f32) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.progress = progress.clamp(0.0, 1.0);
        novel.last_read_at = Some(chrono::Utc::now());

        // 持久化到数据库
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }

        Ok(true)
    } else {
        Ok(false)
    }
}

/// 移动书籍到文件夹
#[frb(sync)]
pub fn move_novel_to_folder_fn(
    novel_id: String,
    folder_id: Option<String>,
) -> Result<bool, String> {
    move_novel_to_folder(novel_id, folder_id)
}

/// 更新书籍排序
#[frb(sync)]
pub fn update_novel_order(novel_id: String, order: i32) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.custom_order = Some(order);

        // 持久化
        if let Ok(json) = serde_json::to_string(&novel) {
            let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
        }

        Ok(true)
    } else {
        Ok(false)
    }
}

/// 设置书籍收藏状态
#[frb(sync)]
pub fn set_novel_favorite(novel_id: String, is_favorite: bool) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.is_favorite = is_favorite;
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
        Ok(true)
    } else {
        Ok(false)
    }
}

/// 更新书籍标签列表
#[frb(sync)]
pub fn update_novel_tags(novel_id: String, tags: Vec<String>) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.tags = tags;
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
        Ok(true)
    } else {
        Ok(false)
    }
}

/// 批量更新书籍排序
#[frb(sync)]
pub fn batch_update_novel_orders(novel_ids: Vec<String>) -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;

    for (index, novel_id) in novel_ids.iter().enumerate() {
        if let Some(novel) = library.iter_mut().find(|n| n.id == *novel_id) {
            novel.custom_order = Some(index as i32);

            // 持久化
            if let Ok(json) = serde_json::to_string(&novel) {
                let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
            }
        }
    }

    Ok(())
}

/// 重命名书籍标题
#[frb(sync)]
pub fn rename_novel(novel_id: String, title: String) -> Result<bool, String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.title = title;
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
        Ok(true)
    } else {
        Ok(false)
    }
}

/// 更新书籍封面（接受一个图片路径，压缩后保存到 covers 目录，更新 cover_path）
#[frb(sync)]
pub fn update_novel_cover(novel_id: String, image_path: String) -> Result<(), String> {
    use image::imageops::FilterType;
    use std::path::Path;

    let src_path = Path::new(&image_path);
    let ext = src_path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("jpg")
        .to_lowercase();

    // 目标目录（使用应用数据目录而非临时目录）
    let dst_dir = get_app_data_dir().join("covers");
    let _ = std::fs::create_dir_all(&dst_dir);
    let dst_path = dst_dir.join(format!("{}.{}", novel_id, ext));

    // 压缩图片（最大 400x600）
    let compressed_path = match image::open(&image_path) {
        Ok(img) => {
            let (w, h) = (img.width(), img.height());
            let img = if w > 400 || h > 600 {
                img.resize(400, 600, FilterType::Lanczos3)
            } else {
                img
            };
            let dst_str = dst_path.to_string_lossy().to_string();
            img.save(&dst_path).map_err(|e| e.to_string())?;
            dst_str
        }
        Err(_e) => {
            // 如果 image 无法解码（例如 webp 格式），直接复制原文件
            std::fs::copy(&image_path, &dst_path).map_err(|e| e.to_string())?;
            dst_path.to_string_lossy().to_string()
        }
    };

    // 更新数据库
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.cover_path = Some(compressed_path);
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 更新书籍作者
#[frb(sync)]
pub fn update_novel_author(novel_id: String, author: String) -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.author = if author.is_empty() {
            None
        } else {
            Some(author)
        };
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 更新书籍备注
#[frb(sync)]
pub fn update_novel_notes(novel_id: String, notes: String) -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        novel.notes = if notes.is_empty() { None } else { Some(notes) };
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 批量更新书籍（标题、作者、备注、标签、封面）
#[frb(sync)]
pub fn update_novel_info(
    novel_id: String,
    title: Option<String>,
    author: Option<String>,
    notes: Option<String>,
    tags: Option<Vec<String>>,
) -> Result<(), String> {
    let mut library = get_library().lock().map_err(|e| e.to_string())?;
    if let Some(novel) = library.iter_mut().find(|n| n.id == novel_id) {
        if let Some(t) = title {
            if !t.is_empty() {
                novel.title = t;
            }
        }
        if let Some(a) = author {
            novel.author = if a.is_empty() { None } else { Some(a) };
        }
        if let Some(n) = notes {
            novel.notes = if n.is_empty() { None } else { Some(n) };
        }
        if let Some(t) = tags {
            novel.tags = t;
        }
        let json = serde_json::to_string(novel).map_err(|e| e.to_string())?;
        db_module::db_set("novels".to_string(), novel.id.clone(), json)
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
// 文件夹管理
// ─────────────────────────────────────────────────────────────────────────────

/// 创建文件夹
#[frb(sync)]
pub fn create_folder(name: String) -> Result<NovelFolder, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;

    let folder = NovelFolder {
        id: format!("folder_{}", uuid::Uuid::new_v4()),
        name,
        created_at: chrono::Utc::now(),
        order: folders.len() as i32,
        parent_id: None,
    };

    folders.push(folder.clone());

    // 持久化
    if let Ok(json) = serde_json::to_string(&folder) {
        let _ = db_module::db_set("novel_folders".to_string(), folder.id.clone(), json);
    }

    Ok(folder)
}

/// 获取所有文件夹
#[frb(sync)]
pub fn get_all_folders() -> Result<Vec<NovelFolder>, String> {
    let folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    let mut result = folders.clone();
    result.sort_by_key(|f| f.order);
    Ok(result)
}

/// 删除文件夹
#[frb(sync)]
pub fn delete_folder(folder_id: String) -> Result<bool, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    let initial_len = folders.len();
    folders.retain(|f| f.id != folder_id);
    let removed = folders.len() < initial_len;

    if removed {
        let _ = db_module::db_delete("novel_folders".to_string(), folder_id.clone());

        // 将该文件夹下的书籍移到根目录
        let mut library = get_library().lock().map_err(|e| e.to_string())?;
        for novel in library.iter_mut() {
            if novel.folder_id.as_ref() == Some(&folder_id) {
                novel.folder_id = None;
                if let Ok(json) = serde_json::to_string(&novel) {
                    let _ = db_module::db_set("novels".to_string(), novel.id.clone(), json);
                }
            }
        }
    }

    Ok(removed)
}

/// 重命名文件夹
#[frb(sync)]
pub fn rename_folder(folder_id: String, name: String) -> Result<bool, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    if let Some(folder) = folders.iter_mut().find(|f| f.id == folder_id) {
        folder.name = name;
        if let Ok(json) = serde_json::to_string(&folder) {
            let _ = db_module::db_set("novel_folders".to_string(), folder.id.clone(), json);
        }
        Ok(true)
    } else {
        Ok(false)
    }
}

/// 批量更新文件夹排序
#[frb(sync)]
pub fn batch_update_folder_orders(folder_ids: Vec<String>) -> Result<(), String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    for (index, folder_id) in folder_ids.iter().enumerate() {
        if let Some(folder) = folders.iter_mut().find(|f| f.id == *folder_id) {
            folder.order = index as i32;
            if let Ok(json) = serde_json::to_string(&folder) {
                let _ = db_module::db_set("novel_folders".to_string(), folder.id.clone(), json);
            }
        }
    }
    Ok(())
}

/// 删除文件夹及其内所有书籍
#[frb(sync)]
pub fn delete_folder_with_novels(folder_id: String) -> Result<(), String> {
    // 先删除该文件夹下的所有书籍
    let novel_ids: Vec<String> = {
        let library = get_library().lock().map_err(|e| e.to_string())?;
        library
            .iter()
            .filter(|n| n.folder_id.as_ref() == Some(&folder_id))
            .map(|n| n.id.clone())
            .collect()
    };
    for novel_id in novel_ids {
        remove_novel(novel_id)?;
    }
    // 再删除文件夹本身（此处不把书移回根目录，因为已经删了）
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    folders.retain(|f| f.id != folder_id);
    let _ = db_module::db_delete("novel_folders".to_string(), folder_id);
    Ok(())
}

/// 创建子文件夹
#[frb(sync)]
pub fn create_child_folder(name: String, parent_id: String) -> Result<NovelFolder, String> {
    let mut folders = get_folder_list().lock().map_err(|e| e.to_string())?;

    let folder = NovelFolder {
        id: format!("folder_{}", uuid::Uuid::new_v4()),
        name,
        created_at: chrono::Utc::now(),
        order: folders
            .iter()
            .filter(|f| f.parent_id.as_deref() == Some(&parent_id))
            .count() as i32,
        parent_id: Some(parent_id),
    };

    folders.push(folder.clone());
    if let Ok(json) = serde_json::to_string(&folder) {
        let _ = db_module::db_set("novel_folders".to_string(), folder.id.clone(), json);
    }
    Ok(folder)
}

/// 获取指定父文件夹的子文件夹列表
#[frb(sync)]
pub fn get_child_folders(parent_id: String) -> Result<Vec<NovelFolder>, String> {
    let folders = get_folder_list().lock().map_err(|e| e.to_string())?;
    let mut result: Vec<NovelFolder> = folders
        .iter()
        .filter(|f| f.parent_id.as_deref() == Some(&parent_id))
        .cloned()
        .collect();
    result.sort_by_key(|f| f.order);
    Ok(result)
}

/// 添加书籍并立即关联到指定文件夹
#[frb(sync)]
pub fn add_novel_to_folder(
    file_paths: Vec<String>,
    folder_id: String,
) -> Result<Vec<NovelMetadata>, String> {
    let added = add_novel(file_paths)?;
    for novel in &added {
        let _ = move_novel_to_folder(novel.id.clone(), Some(folder_id.clone()));
    }
    // 重新获取最新元数据（含 folder_id）
    let library = get_library().lock().map_err(|e| e.to_string())?;
    let result: Vec<NovelMetadata> = added
        .iter()
        .filter_map(|n| library.iter().find(|m| m.id == n.id).cloned())
        .collect();
    Ok(result)
}
