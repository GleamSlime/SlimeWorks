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

// ─────────────────────────────────────────────────────────────────────────────
// 元数据层 DB 测试（全部走隔离 HOME，见 crate::api::test_env）
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::super::test_env::*;
    use super::*;
    use crate::api::get_all_novels;

    /// 从 DB 读回某本书的元数据（验证真的落盘）
    fn stored_novel(id: &str) -> NovelMetadata {
        let raw = db_row("novels", id).expect("该书记录应已落库");
        serde_json::from_str(&raw).expect("DB 中存的应是合法 NovelMetadata JSON")
    }

    /// 从 DB 读回某个文件夹
    fn stored_folder(id: &str) -> NovelFolder {
        let raw = db_row("novel_folders", id).expect("该文件夹应已落库");
        serde_json::from_str(&raw).expect("DB 中存的应是合法 NovelFolder JSON")
    }

    fn find_in_lib(id: &str) -> Option<NovelMetadata> {
        get_all_novels()
            .unwrap()
            .into_iter()
            .find(|n| n.id == id)
    }

    // ── 阅读进度 ───────────────────────────────────────────────────────────

    #[test]
    fn reading_progress_upserts_clamps_and_persists() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_progress");
        let p = write_novel_txt(&dir, "进度书", "甲。", "乙。");
        let novel = add_single_novel(&p);

        // 初次写入进度
        assert!(update_reading_progress(novel.id.clone(), 0.35).unwrap());
        let updated = find_in_lib(&novel.id).unwrap();
        assert!((updated.progress - 0.35).abs() < 1e-6);
        assert!(updated.last_read_at.is_some(), "更新进度应刷新最后阅读时间");
        assert!((stored_novel(&novel.id).progress - 0.35).abs() < 1e-6, "进度必须落库");

        // upsert：再次更新覆盖旧值
        assert!(update_reading_progress(novel.id.clone(), 0.8).unwrap());
        assert!((stored_novel(&novel.id).progress - 0.8).abs() < 1e-6);

        // 越界值夹紧到 [0,1]
        assert!(update_reading_progress(novel.id.clone(), 5.0).unwrap());
        assert!((stored_novel(&novel.id).progress - 1.0).abs() < 1e-6);
        assert!(update_reading_progress(novel.id.clone(), -3.0).unwrap());
        assert!((stored_novel(&novel.id).progress - 0.0).abs() < 1e-6);

        // 非法 id → false 且不新增记录
        assert!(!update_reading_progress("查无此书".to_string(), 0.5).unwrap());
        assert_eq!(db_rows("novels").len(), 1);
    }

    // ── 收藏 / 标签 / 标题 ─────────────────────────────────────────────────

    #[test]
    fn favorite_tags_and_rename_persist() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_basic");
        let p = write_novel_txt(&dir, "基础字段书", "甲。", "乙。");
        let novel = add_single_novel(&p);

        // 收藏开 / 关
        assert!(set_novel_favorite(novel.id.clone(), true).unwrap());
        assert!(find_in_lib(&novel.id).unwrap().is_favorite);
        assert!(stored_novel(&novel.id).is_favorite);
        assert!(set_novel_favorite(novel.id.clone(), false).unwrap());
        assert!(!stored_novel(&novel.id).is_favorite);

        // 标签整体替换（含清空）
        assert!(update_novel_tags(novel.id.clone(), vec!["收藏级".to_string(), "二刷".to_string()]).unwrap());
        assert_eq!(stored_novel(&novel.id).tags, vec!["收藏级".to_string(), "二刷".to_string()]);
        assert!(update_novel_tags(novel.id.clone(), vec![]).unwrap());
        assert!(stored_novel(&novel.id).tags.is_empty());

        // 改名
        assert!(rename_novel(novel.id.clone(), "新标题".to_string()).unwrap());
        assert_eq!(stored_novel(&novel.id).title, "新标题");
        // 空串改名也照写（api 层不做非空校验，留档实际行为）
        assert!(rename_novel(novel.id.clone(), String::new()).unwrap());
        assert_eq!(stored_novel(&novel.id).title, "");

        // 非法 id 分支
        assert!(!set_novel_favorite("未知id".to_string(), true).unwrap());
        assert!(!update_novel_tags("未知id".to_string(), vec!["x".to_string()]).unwrap());
        assert!(!rename_novel("未知id".to_string(), "x".to_string()).unwrap());
    }

    // ── 作者 / 备注 ────────────────────────────────────────────────────────

    #[test]
    fn author_and_notes_empty_string_clears_field() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_author");
        let p = write_novel_txt(&dir, "作者备注书", "甲。", "乙。");
        let novel = add_single_novel(&p);

        update_novel_author(novel.id.clone(), "某作者".to_string()).unwrap();
        assert_eq!(stored_novel(&novel.id).author.as_deref(), Some("某作者"));
        update_novel_notes(novel.id.clone(), "值得一读".to_string()).unwrap();
        assert_eq!(stored_novel(&novel.id).notes.as_deref(), Some("值得一读"));

        // 传空串 → 字段清空为 None
        update_novel_author(novel.id.clone(), String::new()).unwrap();
        assert_eq!(stored_novel(&novel.id).author, None);
        update_novel_notes(novel.id.clone(), String::new()).unwrap();
        assert_eq!(stored_novel(&novel.id).notes, None);

        // 非法 id：api 返回 Ok 但什么都不写（不落库、不 panic）
        let before = db_rows("novels").len();
        update_novel_author("未知id".to_string(), "幽灵".to_string()).unwrap();
        update_novel_notes("未知id".to_string(), "幽灵".to_string()).unwrap();
        assert_eq!(db_rows("novels").len(), before);
    }

    #[test]
    fn update_novel_info_applies_only_present_fields() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_info");
        let p = write_novel_txt(&dir, "批量信息书", "甲。", "乙。");
        let novel = add_single_novel(&p);

        // 四个字段一起给
        update_novel_info(
            novel.id.clone(),
            Some("信息标题".to_string()),
            Some("信息作者".to_string()),
            Some("信息备注".to_string()),
            Some(vec!["标签A".to_string()]),
        )
        .unwrap();
        let stored = stored_novel(&novel.id);
        assert_eq!(stored.title, "信息标题");
        assert_eq!(stored.author.as_deref(), Some("信息作者"));
        assert_eq!(stored.notes.as_deref(), Some("信息备注"));
        assert_eq!(stored.tags, vec!["标签A".to_string()]);

        // 只给部分：None 字段保持不变；空串 title 被忽略；空串 author/notes 清空
        update_novel_info(
            novel.id.clone(),
            Some(String::new()),
            Some(String::new()),
            None,
            Some(vec![]),
        )
        .unwrap();
        let stored = stored_novel(&novel.id);
        assert_eq!(stored.title, "信息标题", "空标题应被忽略");
        assert_eq!(stored.author, None, "空作者表示清除");
        assert_eq!(stored.notes.as_deref(), Some("信息备注"), "None 表示不修改");
        assert!(stored.tags.is_empty());

        // 全部 None → 只重写一次相同内容，数据不变
        update_novel_info(novel.id.clone(), None, None, None, None).unwrap();
        assert_eq!(stored_novel(&novel.id).title, "信息标题");

        // 非法 id → Ok 静默返回
        let before = db_rows("novels").len();
        update_novel_info("未知id".to_string(), Some("x".to_string()), None, None, None).unwrap();
        assert_eq!(db_rows("novels").len(), before);
    }

    // ── 排序 ───────────────────────────────────────────────────────────────

    #[test]
    fn novel_order_single_and_batch_persist() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_order");
        let a = write_novel_txt(&dir, "排序甲", "甲。", "乙。");
        let b = write_novel_txt(&dir, "排序乙", "甲。", "乙。");
        let na = add_single_novel(&a);
        let nb = add_single_novel(&b);

        assert!(update_novel_order(na.id.clone(), 7).unwrap());
        assert_eq!(stored_novel(&na.id).custom_order, Some(7));
        // 负数原样保存（前端可用来置顶）
        assert!(update_novel_order(na.id.clone(), -1).unwrap());
        assert_eq!(stored_novel(&na.id).custom_order, Some(-1));
        assert!(!update_novel_order("未知id".to_string(), 3).unwrap());

        // 批量：按传入顺序写 0..n，未知 id 被忽略
        batch_update_novel_orders(vec![
            nb.id.clone(),
            na.id.clone(),
            "未知id".to_string(),
        ])
        .unwrap();
        assert_eq!(stored_novel(&nb.id).custom_order, Some(0));
        assert_eq!(stored_novel(&na.id).custom_order, Some(1));
        assert_eq!(find_in_lib(&nb.id).unwrap().custom_order, Some(0));

        // 空列表 → 不动任何记录
        batch_update_novel_orders(vec![]).unwrap();
        assert_eq!(stored_novel(&na.id).custom_order, Some(1));
    }

    // ── 封面 ───────────────────────────────────────────────────────────────

    #[test]
    fn cover_is_resized_into_isolated_app_dir() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_cover");
        let p = write_novel_txt(&dir, "封面对象", "甲。", "乙。");
        let novel = add_single_novel(&p);

        // 超大源图 → 缩到 400x600 以内
        let big = dir.join("大图.png");
        write_test_png(&big, 800, 1000);
        update_novel_cover(novel.id.clone(), big.to_string_lossy().into_owned()).unwrap();

        let stored = stored_novel(&novel.id);
        let cover = stored.cover_path.clone().expect("封面路径应写回元数据");
        let cover_path = std::path::Path::new(&cover);
        assert!(cover_path.exists(), "封面文件必须真实生成");
        assert!(
            cover.starts_with(db_test_env().home.to_string_lossy().as_ref()),
            "封面只能写进隔离 HOME，实际: {cover}"
        );
        let (w, h) = image::image_dimensions(cover_path).expect("封面应可解码");
        assert!(w <= 400 && h <= 600, "封面应被压缩到 400x600 内，实际 {w}x{h}");
        assert!(w < 800, "尺寸必须小于原图");

        // 小图 → 原样保存
        let small = dir.join("小图.png");
        write_test_png(&small, 100, 80);
        update_novel_cover(novel.id.clone(), small.to_string_lossy().into_owned()).unwrap();
        let (w2, h2) = image::image_dimensions(std::path::Path::new(
            &stored_novel(&novel.id).cover_path.unwrap(),
        ))
        .unwrap();
        assert_eq!((w2, h2), (100, 80));

        // 删除书籍时应连带清理封面文件
        assert!(remove_novel(novel.id.clone()).unwrap());
        assert!(
            !std::path::Path::new(&cover).exists(),
            "remove_novel 必须删除 cover_path 指向的文件"
        );
    }

    #[test]
    fn cover_errors_and_noop_branches() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_cover_err");
        let p = write_novel_txt(&dir, "封面无关书", "甲。", "乙。");
        let novel = add_single_novel(&p);

        // 源图不存在 → image 解码失败后复制也失败 → Err
        let missing = dir.join("根本没有.png");
        assert!(update_novel_cover(novel.id.clone(), missing.to_string_lossy().into_owned()).is_err());
        assert!(stored_novel(&novel.id).cover_path.is_none(), "失败时不应改动元数据");

        // 源图无法解码（内容不是图片）→ 走「直接复制」分支
        let fake = dir.join("假图.png");
        write_text(&fake, "这不是图片");
        update_novel_cover(novel.id.clone(), fake.to_string_lossy().into_owned()).unwrap();
        let cover = stored_novel(&novel.id).cover_path.expect("复制回退也应写回路径");
        assert!(std::path::Path::new(&cover).exists());

        // 未知 novel id → Ok 但不写任何书记录（封面文件仍会生成，留档实际行为）
        let before = db_rows("novels").len();
        update_novel_cover("未知id".to_string(), fake.to_string_lossy().into_owned()).unwrap();
        assert_eq!(db_rows("novels").len(), before);
        assert!(find_in_lib(&novel.id).unwrap().cover_path == Some(cover));
    }

    // ── 文件夹树 ───────────────────────────────────────────────────────────

    #[test]
    fn folder_tree_crud_and_persistence() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        // 两个根文件夹，order 依次为 0/1
        let root1 = create_folder("言情".to_string()).unwrap();
        let root2 = create_folder("悬疑".to_string()).unwrap();
        assert!(root1.id.starts_with("folder_"));
        assert_eq!(root1.parent_id, None);
        assert_eq!(root1.order, 0);
        assert_eq!(root2.order, 1);
        assert_eq!(stored_folder(&root1.id).name, "言情");

        // 子文件夹：order 只在同级内计数
        let child_a = create_child_folder("古代".to_string(), root1.id.clone()).unwrap();
        let child_b = create_child_folder("现代".to_string(), root1.id.clone()).unwrap();
        let other_child = create_child_folder("本格".to_string(), root2.id.clone()).unwrap();
        assert_eq!(child_a.parent_id.as_deref(), Some(root1.id.as_str()));
        assert_eq!(child_a.order, 0);
        assert_eq!(child_b.order, 1);
        assert_eq!(other_child.order, 0, "不同父目录下的计数互不影响");
        assert_eq!(stored_folder(&child_b.id).parent_id.as_deref(), Some(root1.id.as_str()));

        // 子节点查询：只返回直接子节点并按 order 排序
        let children = get_child_folders(root1.id.clone()).unwrap();
        assert_eq!(children.len(), 2);
        assert_eq!(children[0].id, child_a.id);
        assert_eq!(children[1].id, child_b.id);
        assert!(get_child_folders("未知folder".to_string()).unwrap().is_empty());

        // 全量列表按 order 排序
        let all = get_all_folders().unwrap();
        assert_eq!(all.len(), 5);
        let orders: Vec<i32> = all.iter().map(|f| f.order).collect();
        assert!(orders.windows(2).all(|w| w[0] <= w[1]), "get_all_folders 必须按 order 升序");

        // 重命名 + 落库
        assert!(rename_folder(child_a.id.clone(), "架空".to_string()).unwrap());
        assert_eq!(stored_folder(&child_a.id).name, "架空");
        assert!(!rename_folder("未知folder".to_string(), "x".to_string()).unwrap());

        // 批量重排：反转根目录顺序
        batch_update_folder_orders(vec![root2.id.clone(), root1.id.clone()]).unwrap();
        assert_eq!(stored_folder(&root2.id).order, 0);
        assert_eq!(stored_folder(&root1.id).order, 1);
        // 未知 id 被忽略，已知 id 仍按位赋值
        batch_update_folder_orders(vec!["未知folder".to_string(), child_a.id.clone()]).unwrap();
        assert_eq!(stored_folder(&child_a.id).order, 1);
        // 空列表不改动
        batch_update_folder_orders(vec![]).unwrap();
        assert_eq!(stored_folder(&child_a.id).order, 1);

        // 删除（空文件夹）
        assert!(delete_folder(other_child.id.clone()).unwrap());
        assert_eq!(db_row("novel_folders", &other_child.id), None);
        assert!(!delete_folder(other_child.id.clone()).unwrap());
        assert!(!delete_folder("未知folder".to_string()).unwrap());
        assert_eq!(get_all_folders().unwrap().len(), 4, "5 个文件夹删掉 1 个应剩 4 个");
    }

    #[test]
    fn delete_folder_moves_books_back_to_root() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_del_folder");
        let in1 = write_novel_txt(&dir, "夹内一", "甲。", "乙。");
        let in2 = write_novel_txt(&dir, "夹内二", "甲。", "乙。");
        let outside = write_novel_txt(&dir, "夹外书", "甲。", "乙。");
        let n1 = add_single_novel(&in1);
        let n2 = add_single_novel(&in2);
        let n3 = add_single_novel(&outside);
        let folder = create_folder("临时分类".to_string()).unwrap();
        move_novel_to_folder(n1.id.clone(), Some(folder.id.clone())).unwrap();
        move_novel_to_folder(n2.id.clone(), Some(folder.id.clone())).unwrap();

        assert!(delete_folder(folder.id.clone()).unwrap());

        // 策略一：书不删，退回根目录
        let lib = get_all_novels().unwrap();
        assert_eq!(lib.len(), 3, "delete_folder 不应删除书籍");
        for id in [&n1.id, &n2.id] {
            assert_eq!(find_in_lib(id).unwrap().folder_id, None, "folder_id 应被清空");
            assert!(!stored_novel(id).file_path.is_empty());
            let raw = db_row("novels", id).unwrap();
            assert!(!raw.contains(&folder.id), "DB JSON 里不应再残留已删文件夹 id");
        }
        // 夹外的书不受影响
        assert_eq!(find_in_lib(&n3.id).unwrap().folder_id, None);
        assert_eq!(db_row("novel_folders", &folder.id), None);
    }

    #[test]
    fn delete_folder_with_novels_removes_books_but_keeps_files() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_del_with");
        let in1 = write_novel_txt(&dir, "随夹删一", "甲。", "乙。");
        let in2 = write_novel_txt(&dir, "随夹删二", "甲。", "乙。");
        let outside = write_novel_txt(&dir, "幸存书", "甲。", "乙。");
        let n1 = add_single_novel(&in1);
        let n2 = add_single_novel(&in2);
        let n3 = add_single_novel(&outside);
        let folder = create_folder("整体删除".to_string()).unwrap();
        move_novel_to_folder(n1.id.clone(), Some(folder.id.clone())).unwrap();
        move_novel_to_folder(n2.id.clone(), Some(folder.id.clone())).unwrap();

        delete_folder_with_novels(folder.id.clone()).unwrap();

        // 策略二：书从库中删除（但 delete_folder_with_novels 走 remove_novel，不删磁盘源文件）
        let lib = get_all_novels().unwrap();
        assert_eq!(lib.len(), 1);
        assert_eq!(lib[0].id, n3.id);
        assert_eq!(db_row("novels", &n1.id), None);
        assert_eq!(db_row("novels", &n2.id), None);
        assert!(in1.exists() && in2.exists(), "该接口按设计不删源文件");
        assert_eq!(db_row("novel_folders", &folder.id), None, "文件夹本身也要删除");

        // 未知文件夹 → 幂等 Ok
        let before = get_all_novels().unwrap().len();
        delete_folder_with_novels("未知folder".to_string()).unwrap();
        assert_eq!(get_all_novels().unwrap().len(), before);
    }

    #[test]
    fn add_novel_to_folder_links_and_persists() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_add_to_folder");
        let a = write_novel_txt(&dir, "入夹一", "甲。", "乙。");
        let b = write_novel_txt(&dir, "入夹二", "甲。", "乙。");
        let folder = create_folder("新书夹".to_string()).unwrap();

        let added = add_novel_to_folder(
            vec![a.to_string_lossy().into_owned(), b.to_string_lossy().into_owned()],
            folder.id.clone(),
        )
        .unwrap();
        assert_eq!(added.len(), 2);
        for novel in &added {
            assert_eq!(novel.folder_id.as_deref(), Some(folder.id.as_str()), "返回值应带 folder_id");
            assert_eq!(stored_novel(&novel.id).folder_id.as_deref(), Some(folder.id.as_str()));
        }

        // 非法路径被跳过，不影响其它文件
        let missing = dir.join("不存在.txt");
        let partial = add_novel_to_folder(
            vec![missing.to_string_lossy().into_owned(), a.to_string_lossy().into_owned()],
            folder.id.clone(),
        )
        .unwrap();
        assert_eq!(partial.len(), 1);

        // 已知行为：不校验 folder_id 是否存在，直接写入悬空引用
        let ghost = add_novel_to_folder(vec![b.to_string_lossy().into_owned()], "不存在folder".to_string()).unwrap();
        assert_eq!(ghost[0].folder_id.as_deref(), Some("不存在folder"));
    }

    #[test]
    fn move_novel_to_folder_fn_wrapper_behaviour() {
        let _serial = lock_db_test_serial();
        assert_db_isolated();
        reset_library_state();

        let dir = case_dir("md_move_fn");
        let p = write_novel_txt(&dir, "移动函数书", "甲。", "乙。");
        let novel = add_single_novel(&p);
        let folder = create_folder("目标夹".to_string()).unwrap();

        assert!(move_novel_to_folder_fn(novel.id.clone(), Some(folder.id.clone())).unwrap());
        assert_eq!(find_in_lib(&novel.id).unwrap().folder_id.as_deref(), Some(folder.id.as_str()));
        assert!(move_novel_to_folder_fn(novel.id.clone(), None).unwrap());
        assert_eq!(find_in_lib(&novel.id).unwrap().folder_id, None);
        assert!(!move_novel_to_folder_fn("未知id".to_string(), Some(folder.id)).unwrap());

        // add_novel 的原始入口也应能直接加入多本
        let extra = write_novel_txt(&dir, "多路径一", "甲。", "乙。");
        let extra2 = write_novel_txt(&dir, "多路径二", "甲。", "乙。");
        let many = add_novel(vec![
            extra.to_string_lossy().into_owned(),
            extra2.to_string_lossy().into_owned(),
            dir.join("不存在.txt").to_string_lossy().into_owned(),
        ])
        .unwrap();
        assert_eq!(many.len(), 2);
        assert_eq!(get_all_novels().unwrap().len(), 3);
    }
}
