/// 游戏库模块 API（FRB 桥接层）
///
/// 使用 JSON 字符串作为 Rust ↔ Dart 边界，保持与现有 Dart GameItem 模型兼容。
use anyhow::{Context, Result};
use flutter_rust_bridge::frb;
use serde_json::Value;

#[frb(sync)]
pub fn game_library_init(db_path: String) -> Result<()> {
    game_library::game_library_init(db_path)
}

#[frb(sync)]
pub fn game_library_is_ready() -> bool {
    game_library::game_library_is_ready()
}

#[frb(sync)]
pub fn game_library_close() {
    game_library::game_library_close()
}

fn game_to_json(g: &game_library::Game) -> Value {
    serde_json::json!({
        "id": g.id,
        "name": g.name,
        "coverPath": g.cover_path,
        "company": g.company,
        "summary": g.summary,
        "rating": g.rating,
        "releaseDate": g.release_date,
        "path": g.path,
        "status": g.status,
        "createdAt": g.created_at * 1000,
        "updatedAt": g.updated_at * 1000,
        "lastPlayedAt": g.last_played_at.map(|t| t * 1000),
        "totalPlayTimeSec": g.total_play_time_sec,
        "tags": g.tags,
        "exePaths": g.exe_paths,
        "gameDir": g.game_dir,
    })
}

fn ms_to_sec(v: &Value, key: &str) -> i64 {
    v[key].as_i64().map(|t| if t > 9_999_999_999 { t / 1000 } else { t }).unwrap_or(0)
}
fn ms_to_sec_opt(v: &Value, key: &str) -> Option<i64> {
    v[key].as_i64().map(|t| if t > 9_999_999_999 { t / 1000 } else { t })
}
fn sv(v: &Value, key: &str) -> String { v[key].as_str().unwrap_or("").to_string() }
fn svs(v: &Value, key: &str) -> Vec<String> {
    v[key].as_array()
        .map(|a| a.iter().filter_map(|e| e.as_str()).map(String::from).collect())
        .unwrap_or_default()
}

fn json_to_game(v: &Value) -> game_library::Game {
    game_library::Game {
        id: sv(v, "id"),
        name: sv(v, "name"),
        cover_path: sv(v, "coverPath"),
        company: sv(v, "company"),
        summary: sv(v, "summary"),
        rating: v["rating"].as_f64().unwrap_or(0.0),
        release_date: sv(v, "releaseDate"),
        path: sv(v, "path"),
        status: sv(v, "status"),
        created_at: ms_to_sec(v, "createdAt"),
        updated_at: ms_to_sec(v, "updatedAt"),
        last_played_at: ms_to_sec_opt(v, "lastPlayedAt"),
        total_play_time_sec: v["totalPlayTimeSec"].as_i64().unwrap_or(0),
        tags: svs(v, "tags"),
        exe_paths: svs(v, "exePaths"),
        game_dir: sv(v, "gameDir"),
    }
}

fn category_to_json(c: &game_library::Category) -> Value {
    serde_json::json!({
        "id": c.id, "name": c.name, "emoji": c.emoji,
        "isSystem": c.is_system,
        "createdAt": c.created_at * 1000,
        "gameCount": c.game_count,
    })
}

fn json_to_category(v: &Value) -> game_library::Category {
    game_library::Category {
        id: sv(v, "id"), name: sv(v, "name"), emoji: sv(v, "emoji"),
        is_system: v["isSystem"].as_bool().unwrap_or(false),
        game_count: v["gameCount"].as_i64().unwrap_or(0),
        created_at: ms_to_sec(v, "createdAt"),
    }
}

fn session_to_json(s: &game_library::PlaySession) -> Value {
    serde_json::json!({
        "id": s.id, "gameId": s.game_id,
        "startTime": s.start_time * 1000,
        "endTime": s.end_time * 1000,
        "durationSec": s.duration_sec,
    })
}

fn json_to_session(v: &Value) -> game_library::PlaySession {
    game_library::PlaySession {
        id: sv(v, "id"), game_id: sv(v, "gameId"),
        start_time: ms_to_sec(v, "startTime"),
        end_time: ms_to_sec(v, "endTime"),
        duration_sec: v["durationSec"].as_i64().unwrap_or(0),
    }
}

fn progress_to_json(p: &game_library::GameProgress) -> Value {
    serde_json::json!({
        "id": p.id, "gameId": p.game_id,
        "chapter": p.chapter, "route": p.route, "note": p.note,
        "updatedAt": p.updated_at * 1000,
    })
}

fn json_to_progress(v: &Value) -> game_library::GameProgress {
    game_library::GameProgress {
        id: sv(v, "id"), game_id: sv(v, "gameId"),
        chapter: sv(v, "chapter"), route: sv(v, "route"), note: sv(v, "note"),
        updated_at: ms_to_sec(v, "updatedAt"),
    }
}

pub async fn game_library_get_games_json() -> Result<String> {
    let games = game_library::game_library_get_games().await?;
    let arr: Vec<Value> = games.iter().map(game_to_json).collect();
    Ok(serde_json::to_string(&arr).context("序列化游戏列表失败")?)
}

pub async fn game_library_get_game_by_id_json(game_id: String) -> Result<String> {
    match game_library::game_library_get_game_by_id(game_id).await? {
        Some(g) => Ok(serde_json::to_string(&game_to_json(&g)).context("序列化游戏失败")?),
        None => Ok(String::new()),
    }
}

pub async fn game_library_add_game_json(game_json: String) -> Result<String> {
    let v: Value = serde_json::from_str(&game_json).context("解析游戏 JSON 失败")?;
    let created = game_library::game_library_add_game(json_to_game(&v)).await?;
    Ok(serde_json::to_string(&game_to_json(&created)).context("序列化新游戏失败")?)
}

pub async fn game_library_update_game_json(game_json: String) -> Result<()> {
    let v: Value = serde_json::from_str(&game_json).context("解析游戏 JSON 失败")?;
    game_library::game_library_update_game(json_to_game(&v)).await
}

pub async fn game_library_delete_game(game_id: String) -> Result<()> {
    game_library::game_library_delete_game(game_id).await
}

pub async fn game_library_get_categories_json() -> Result<String> {
    let cats = game_library::game_library_get_categories().await?;
    let arr: Vec<Value> = cats.iter().map(category_to_json).collect();
    Ok(serde_json::to_string(&arr).context("序列化分类列表失败")?)
}

pub async fn game_library_upsert_category_json(category_json: String) -> Result<String> {
    let v: Value = serde_json::from_str(&category_json).context("解析分类 JSON 失败")?;
    let saved = game_library::game_library_upsert_category(json_to_category(&v)).await?;
    Ok(serde_json::to_string(&category_to_json(&saved)).context("序列化分类失败")?)
}

pub async fn game_library_delete_category(category_id: String) -> Result<()> {
    game_library::game_library_delete_category(category_id).await
}

pub async fn game_library_add_game_to_category(game_id: String, category_id: String) -> Result<()> {
    game_library::game_library_add_game_to_category(game_id, category_id).await
}

pub async fn game_library_remove_game_from_category(game_id: String, category_id: String) -> Result<()> {
    game_library::game_library_remove_game_from_category(game_id, category_id).await
}

pub async fn game_library_get_game_category_ids(game_id: String) -> Result<Vec<String>> {
    let cats = game_library::game_library_get_game_categories(game_id).await?;
    Ok(cats.into_iter().map(|c| c.id).collect())
}

pub async fn game_library_toggle_favorite(game_id: String, favorite: bool) -> Result<()> {
    game_library::game_library_toggle_favorite(game_id, favorite).await
}

pub async fn game_library_is_favorite(game_id: String) -> Result<bool> {
    game_library::game_library_is_favorite(game_id).await
}

pub async fn game_library_add_play_session_json(session_json: String) -> Result<()> {
    let v: Value = serde_json::from_str(&session_json).context("解析会话 JSON 失败")?;
    game_library::game_library_add_play_session(json_to_session(&v)).await
}

pub async fn game_library_get_play_sessions_json(game_id: String) -> Result<String> {
    let sessions = game_library::game_library_get_play_sessions(game_id).await?;
    let arr: Vec<Value> = sessions.iter().map(session_to_json).collect();
    Ok(serde_json::to_string(&arr).context("序列化游玩记录失败")?)
}

pub async fn game_library_upsert_progress_json(progress_json: String) -> Result<String> {
    let v: Value = serde_json::from_str(&progress_json).context("解析进度 JSON 失败")?;
    let saved = game_library::game_library_upsert_progress(json_to_progress(&v)).await?;
    Ok(serde_json::to_string(&progress_to_json(&saved)).context("序列化进度失败")?)
}

pub async fn game_library_get_progress_json(game_id: String) -> Result<String> {
    let list = game_library::game_library_get_progress(game_id).await?;
    let arr: Vec<Value> = list.iter().map(progress_to_json).collect();
    Ok(serde_json::to_string(&arr).context("序列化进度列表失败")?)
}

pub async fn game_library_get_stats_json(start_ts_sec: i64, end_ts_sec: i64) -> Result<String> {
    let stats = game_library::game_library_get_stats(start_ts_sec, end_ts_sec).await?;
    let v = serde_json::json!({
        "totalPlayTimeSec": stats.total_play_time_sec,
        "todayPlayTimeSec": stats.today_play_time_sec,
        "weekPlayTimeSec": stats.week_play_time_sec,
        "sessionCount": stats.session_count,
        "timeline": stats.timeline.iter().map(|d| serde_json::json!({"date": d.date, "durationSec": d.duration_sec})).collect::<Vec<_>>(),
        "perGame": stats.per_game.iter().map(|p| serde_json::json!({"gameId": p.game_id, "gameName": p.game_name, "totalSec": p.total_sec})).collect::<Vec<_>>(),
    });
    Ok(serde_json::to_string(&v).context("序列化统计数据失败")?)
}

pub async fn game_library_get_home_page_data_json() -> Result<String> {
    let data = game_library::game_library_get_home_page_data().await?;
    let v = serde_json::json!({
        "lastPlayedGame": data.last_played_game.as_ref().map(game_to_json),
        "todayPlayTimeSec": data.today_play_time_sec,
        "weekPlayTimeSec": data.week_play_time_sec,
        "totalGames": data.total_games,
        "totalPlayTimeSec": data.total_play_time_sec,
    });
    Ok(serde_json::to_string(&v).context("序列化首页数据失败")?)
}

pub async fn game_library_launch_game(exe_path: String, working_dir: String) -> Result<i64> {
    game_library::game_library_launch_game(exe_path, working_dir).await
}

#[frb(sync)]
pub fn game_library_derive_game_name(path: String) -> String {
    game_library::game_library_derive_game_name(path)
}

pub async fn game_library_scan_directory_json(paths: Vec<String>) -> Result<String> {
    let result = game_library::game_library_scan_directory(paths).await?;
    let arr: Vec<Value> = result.iter().map(|s| serde_json::json!({
        "folderPath": s.folder_path,
        "folderName": s.folder_name,
        "exePaths": s.exe_paths,
    })).collect();
    Ok(serde_json::to_string(&arr).context("序列化扫描结果失败")?)
}

pub async fn game_library_check_paths_exist(paths: Vec<String>) -> Result<Vec<String>> {
    game_library::game_library_check_paths_exist(paths).await
}

pub async fn game_library_get_settings_json() -> Result<String> {
    let s = game_library::game_library_get_settings().await?;
    let v = serde_json::json!({
        "autoTrackPlayTime": s.auto_track_play_time,
        "defaultSort": s.default_sort,
        "autoSave": s.auto_save,
        "enableDesktopLaunch": s.enable_desktop_launch,
    });
    Ok(serde_json::to_string(&v).context("序列化设置失败")?)
}

pub async fn game_library_save_settings_json(settings_json: String) -> Result<()> {
    let v: Value = serde_json::from_str(&settings_json).context("解析设置 JSON 失败")?;
    let s = game_library::GameLibrarySettings {
        auto_track_play_time: v["autoTrackPlayTime"].as_bool().unwrap_or(true),
        default_sort: v["defaultSort"].as_str().unwrap_or("updatedAt_desc").to_string(),
        auto_save: v["autoSave"].as_bool().unwrap_or(true),
        enable_desktop_launch: v["enableDesktopLaunch"].as_bool().unwrap_or(true),
    };
    game_library::game_library_save_settings(s).await
}
