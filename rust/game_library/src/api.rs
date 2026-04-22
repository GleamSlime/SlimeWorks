use std::path::PathBuf;

use anyhow::{Context, Result};
use chrono::Datelike;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use parking_lot::Mutex;
use rusqlite::{params, Connection};
use serde_json;
use uuid::Uuid;

use crate::db::init_db;
use crate::types::{
    Category, DayPlayTime, Game, GameLibrarySettings, GameProgress, GameStats, GameTimeSummary,
    HomePageData, PlaySession, ScannedGame,
};

/// 解析 JSON 字符串为 Vec<String>，失败时返回空列表
fn parse_json_str_list(s: &str) -> Vec<String> {
    serde_json::from_str::<Vec<String>>(s).unwrap_or_default()
}

/// 将 Vec<String> 序列化为 JSON 字符串
fn to_json_str(list: &[String]) -> String {
    serde_json::to_string(list).unwrap_or_else(|_| "[]".to_string())
}

lazy_static! {
    static ref DB_CONN: Mutex<Option<Connection>> = Mutex::new(None);
}

const SYSTEM_FAVORITES_ID: &str = "system:favorites";

fn now_ts() -> i64 {
    chrono::Utc::now().timestamp()
}

fn open_db(db_path: &str) -> Result<Connection> {
    let path = PathBuf::from(db_path);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).context("创建数据库目录失败")?;
    }
    let conn = Connection::open(path).context("打开游戏库数据库失败")?;
    init_db(&conn)?;
    Ok(conn)
}

fn with_conn<T>(f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
    let guard = DB_CONN.lock();
    let conn = guard.as_ref().context("游戏库未初始化，请先调用 game_library_init")?;
    f(conn)
}

#[frb(sync)]
pub fn game_library_init(db_path: String) -> Result<()> {
    let conn = open_db(&db_path)?;
    let mut guard = DB_CONN.lock();
    *guard = Some(conn);
    Ok(())
}

#[frb(sync)]
pub fn game_library_is_ready() -> bool {
    DB_CONN.lock().is_some()
}

#[frb(sync)]
pub fn game_library_close() {
    let mut guard = DB_CONN.lock();
    *guard = None;
}

pub async fn game_library_add_game(mut game: Game) -> Result<Game> {
    with_conn(|conn| {
        let now = now_ts();
        if game.id.trim().is_empty() {
            game.id = Uuid::new_v4().to_string();
        }
        game.created_at = now;
        game.updated_at = now;
        let tags_json = to_json_str(&game.tags);
        let exe_paths_json = to_json_str(&game.exe_paths);
        conn.execute(
            r#"
            INSERT INTO games (id, name, cover_path, company, summary, rating, release_date, path, status, created_at, updated_at, tags, exe_paths, game_dir)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
            "#,
            params![
                &game.id,
                &game.name,
                &game.cover_path,
                &game.company,
                &game.summary,
                game.rating,
                &game.release_date,
                &game.path,
                &game.status,
                game.created_at,
                game.updated_at,
                &tags_json,
                &exe_paths_json,
                &game.game_dir,
            ],
        )
        .context("新增游戏失败")?;
        Ok(game)
    })
}

pub async fn game_library_update_game(game: Game) -> Result<()> {
    with_conn(|conn| {
        let now = now_ts();
        let tags_json = to_json_str(&game.tags);
        let exe_paths_json = to_json_str(&game.exe_paths);
        conn.execute(
            r#"
            UPDATE games
            SET name = ?2,
                cover_path = ?3,
                company = ?4,
                summary = ?5,
                rating = ?6,
                release_date = ?7,
                path = ?8,
                status = ?9,
                updated_at = ?10,
                tags = ?11,
                exe_paths = ?12,
                game_dir = ?13
            WHERE id = ?1
            "#,
            params![
                game.id,
                game.name,
                game.cover_path,
                game.company,
                game.summary,
                game.rating,
                game.release_date,
                game.path,
                game.status,
                now,
                &tags_json,
                &exe_paths_json,
                &game.game_dir,
            ],
        )
        .context("更新游戏失败")?;
        Ok(())
    })
}

pub async fn game_library_get_games() -> Result<Vec<Game>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT
                    g.id,
                    g.name,
                    g.cover_path,
                    g.company,
                    g.summary,
                    g.rating,
                    g.release_date,
                    g.path,
                    g.status,
                    g.created_at,
                    g.updated_at,
                    (
                        SELECT MAX(ps.end_time)
                        FROM play_sessions ps
                        WHERE ps.game_id = g.id
                    ) AS last_played_at,
                    COALESCE((
                        SELECT SUM(ps.duration_sec)
                        FROM play_sessions ps
                        WHERE ps.game_id = g.id
                    ), 0) AS total_play_time_sec,
                    COALESCE(g.tags, '[]') AS tags,
                    COALESCE(g.exe_paths, '[]') AS exe_paths,
                    COALESCE(g.game_dir, '') AS game_dir
                FROM games g
                ORDER BY g.updated_at DESC
                "#,
            )
            .context("准备查询游戏列表失败")?;

        let rows = stmt
            .query_map([], |row| {
                let tags_str: String = row.get(13)?;
                let exe_paths_str: String = row.get(14)?;
                Ok(Game {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    cover_path: row.get(2)?,
                    company: row.get(3)?,
                    summary: row.get(4)?,
                    rating: row.get(5)?,
                    release_date: row.get(6)?,
                    path: row.get(7)?,
                    status: row.get(8)?,
                    created_at: row.get(9)?,
                    updated_at: row.get(10)?,
                    last_played_at: row.get(11)?,
                    total_play_time_sec: row.get(12)?,
                    tags: parse_json_str_list(&tags_str),
                    exe_paths: parse_json_str_list(&exe_paths_str),
                    game_dir: row.get(15)?,
                })
            })
            .context("查询游戏列表失败")?;

        let mut games = Vec::new();
        for row in rows {
            games.push(row.context("读取游戏记录失败")?);
        }
        Ok(games)
    })
}

pub async fn game_library_get_game_by_id(game_id: String) -> Result<Option<Game>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT
                    g.id,
                    g.name,
                    g.cover_path,
                    g.company,
                    g.summary,
                    g.rating,
                    g.release_date,
                    g.path,
                    g.status,
                    g.created_at,
                    g.updated_at,
                    (
                        SELECT MAX(ps.end_time)
                        FROM play_sessions ps
                        WHERE ps.game_id = g.id
                    ) AS last_played_at,
                    COALESCE((
                        SELECT SUM(ps.duration_sec)
                        FROM play_sessions ps
                        WHERE ps.game_id = g.id
                    ), 0) AS total_play_time_sec,
                    COALESCE(g.tags, '[]') AS tags,
                    COALESCE(g.exe_paths, '[]') AS exe_paths,
                    COALESCE(g.game_dir, '') AS game_dir
                FROM games g
                WHERE g.id = ?1
                LIMIT 1
                "#,
            )
            .context("准备查询游戏详情失败")?;

        let mut rows = stmt.query(params![game_id]).context("查询游戏详情失败")?;
        if let Some(row) = rows.next().context("读取游戏详情失败")? {
            let tags_str: String = row.get(13)?;
            let exe_paths_str: String = row.get(14)?;
            let game = Game {
                id: row.get(0)?,
                name: row.get(1)?,
                cover_path: row.get(2)?,
                company: row.get(3)?,
                summary: row.get(4)?,
                rating: row.get(5)?,
                release_date: row.get(6)?,
                path: row.get(7)?,
                status: row.get(8)?,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
                last_played_at: row.get(11)?,
                total_play_time_sec: row.get(12)?,
                tags: parse_json_str_list(&tags_str),
                exe_paths: parse_json_str_list(&exe_paths_str),
                game_dir: row.get(15)?,
            };
            return Ok(Some(game));
        }
        Ok(None)
    })
}

pub async fn game_library_delete_game(game_id: String) -> Result<()> {
    with_conn(|conn| {
        conn.execute("DELETE FROM game_progress WHERE game_id = ?1", params![game_id.clone()])
            .context("删除游戏进度失败")?;
        conn.execute(
            "DELETE FROM game_categories WHERE game_id = ?1",
            params![game_id.clone()],
        )
        .context("删除游戏分类关联失败")?;
        conn.execute("DELETE FROM play_sessions WHERE game_id = ?1", params![game_id.clone()])
            .context("删除游玩记录失败")?;
        conn.execute("DELETE FROM games WHERE id = ?1", params![game_id])
            .context("删除游戏失败")?;
        Ok(())
    })
}

pub async fn game_library_upsert_category(category: Category) -> Result<Category> {
    with_conn(|conn| {
        let category_name = category.name.clone();
        let category_emoji = category.emoji.clone();
        let category_is_system = category.is_system;
        let now = now_ts();
        let id = if category.id.trim().is_empty() {
            Uuid::new_v4().to_string()
        } else {
            category.id.clone()
        };
        conn.execute(
            r#"
            INSERT INTO categories (id, name, emoji, is_system, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                emoji = excluded.emoji,
                updated_at = excluded.updated_at
            "#,
            params![
                &id,
                &category_name,
                &category_emoji,
                if category_is_system { 1 } else { 0 },
                now,
                now,
            ],
        )
        .context("保存分类失败")?;

        Ok(Category {
            id,
            name: category_name,
            emoji: category_emoji,
            is_system: category_is_system,
            game_count: 0,
            created_at: now,
        })
    })
}

pub async fn game_library_get_categories() -> Result<Vec<Category>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT
                    c.id,
                    c.name,
                    c.emoji,
                    c.is_system,
                    COALESCE(COUNT(gc.game_id), 0) AS game_count,
                    c.created_at
                FROM categories c
                LEFT JOIN game_categories gc ON gc.category_id = c.id
                GROUP BY c.id, c.name, c.emoji, c.is_system, c.created_at
                ORDER BY c.is_system DESC, c.created_at ASC
                "#,
            )
            .context("准备查询分类失败")?;

        let rows = stmt
            .query_map([], |row| {
                let is_system_num: i64 = row.get(3)?;
                Ok(Category {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    emoji: row.get(2)?,
                    is_system: is_system_num == 1,
                    game_count: row.get(4)?,
                    created_at: row.get(5)?,
                })
            })
            .context("查询分类失败")?;

        let mut categories = Vec::new();
        for row in rows {
            categories.push(row.context("读取分类记录失败")?);
        }
        Ok(categories)
    })
}

pub async fn game_library_delete_category(category_id: String) -> Result<()> {
    if category_id == SYSTEM_FAVORITES_ID {
        anyhow::bail!("系统分类不允许删除");
    }

    with_conn(|conn| {
        conn.execute(
            "DELETE FROM game_categories WHERE category_id = ?1",
            params![category_id.clone()],
        )
        .context("删除分类关联失败")?;
        conn.execute("DELETE FROM categories WHERE id = ?1", params![category_id])
            .context("删除分类失败")?;
        Ok(())
    })
}

pub async fn game_library_add_game_to_category(game_id: String, category_id: String) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            r#"
            INSERT OR IGNORE INTO game_categories (game_id, category_id, created_at)
            VALUES (?1, ?2, ?3)
            "#,
            params![game_id, category_id, now_ts()],
        )
        .context("添加游戏到分类失败")?;
        Ok(())
    })
}

pub async fn game_library_remove_game_from_category(
    game_id: String,
    category_id: String,
) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            "DELETE FROM game_categories WHERE game_id = ?1 AND category_id = ?2",
            params![game_id, category_id],
        )
        .context("移除游戏分类失败")?;
        Ok(())
    })
}

pub async fn game_library_get_game_categories(game_id: String) -> Result<Vec<Category>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT c.id, c.name, c.emoji, c.is_system, c.created_at
                FROM categories c
                INNER JOIN game_categories gc ON gc.category_id = c.id
                WHERE gc.game_id = ?1
                ORDER BY c.is_system DESC, c.created_at ASC
                "#,
            )
            .context("准备查询游戏分类失败")?;

        let rows = stmt
            .query_map(params![game_id], |row| {
                let is_system_num: i64 = row.get(3)?;
                Ok(Category {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    emoji: row.get(2)?,
                    is_system: is_system_num == 1,
                    game_count: 0,
                    created_at: row.get(4)?,
                })
            })
            .context("查询游戏分类失败")?;

        let mut categories = Vec::new();
        for row in rows {
            categories.push(row.context("读取游戏分类记录失败")?);
        }
        Ok(categories)
    })
}

pub async fn game_library_add_play_session(session: PlaySession) -> Result<()> {
    with_conn(|conn| {
        conn.execute(
            r#"
            INSERT INTO play_sessions (id, game_id, start_time, end_time, duration_sec, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            "#,
            params![
                if session.id.trim().is_empty() {
                    Uuid::new_v4().to_string()
                } else {
                    session.id
                },
                session.game_id,
                session.start_time,
                session.end_time,
                session.duration_sec,
                now_ts(),
            ],
        )
        .context("新增游玩会话失败")?;
        Ok(())
    })
}

pub async fn game_library_get_play_sessions(game_id: String) -> Result<Vec<PlaySession>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, game_id, start_time, end_time, duration_sec
                FROM play_sessions
                WHERE game_id = ?1
                ORDER BY start_time DESC
                "#,
            )
            .context("准备查询游玩记录失败")?;

        let rows = stmt
            .query_map(params![game_id], |row| {
                Ok(PlaySession {
                    id: row.get(0)?,
                    game_id: row.get(1)?,
                    start_time: row.get(2)?,
                    end_time: row.get(3)?,
                    duration_sec: row.get(4)?,
                })
            })
            .context("查询游玩记录失败")?;

        let mut sessions = Vec::new();
        for row in rows {
            sessions.push(row.context("读取游玩记录失败")?);
        }
        Ok(sessions)
    })
}

pub async fn game_library_upsert_progress(progress: GameProgress) -> Result<GameProgress> {
    with_conn(|conn| {
        let progress_game_id = progress.game_id.clone();
        let progress_chapter = progress.chapter.clone();
        let progress_route = progress.route.clone();
        let progress_note = progress.note.clone();
        let id = if progress.id.trim().is_empty() {
            Uuid::new_v4().to_string()
        } else {
            progress.id.clone()
        };
        let now = now_ts();

        conn.execute(
            r#"
            INSERT INTO game_progress (id, game_id, chapter, route, note, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(id) DO UPDATE SET
                chapter = excluded.chapter,
                route = excluded.route,
                note = excluded.note,
                updated_at = excluded.updated_at
            "#,
            params![
                &id,
                &progress_game_id,
                &progress_chapter,
                &progress_route,
                &progress_note,
                now
            ],
        )
        .context("保存进度失败")?;

        Ok(GameProgress {
            id,
            game_id: progress_game_id,
            chapter: progress_chapter,
            route: progress_route,
            note: progress_note,
            updated_at: now,
        })
    })
}

pub async fn game_library_get_progress(game_id: String) -> Result<Vec<GameProgress>> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT id, game_id, chapter, route, note, updated_at
                FROM game_progress
                WHERE game_id = ?1
                ORDER BY updated_at DESC
                "#,
            )
            .context("准备查询进度失败")?;

        let rows = stmt
            .query_map(params![game_id], |row| {
                Ok(GameProgress {
                    id: row.get(0)?,
                    game_id: row.get(1)?,
                    chapter: row.get(2)?,
                    route: row.get(3)?,
                    note: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            })
            .context("查询进度失败")?;

        let mut progress = Vec::new();
        for row in rows {
            progress.push(row.context("读取进度记录失败")?);
        }
        Ok(progress)
    })
}

pub async fn game_library_get_stats(start_ts: i64, end_ts: i64) -> Result<GameStats> {
    with_conn(|conn| {
        let total_play_time_sec: i64 = conn
            .query_row(
                r#"
                SELECT COALESCE(SUM(duration_sec), 0)
                FROM play_sessions
                WHERE start_time >= ?1 AND start_time <= ?2
                "#,
                params![start_ts, end_ts],
                |row| row.get(0),
            )
            .context("统计总时长失败")?;

        let session_count: i64 = conn
            .query_row(
                r#"
                SELECT COUNT(*)
                FROM play_sessions
                WHERE start_time >= ?1 AND start_time <= ?2
                "#,
                params![start_ts, end_ts],
                |row| row.get(0),
            )
            .context("统计会话数失败")?;

        let now = chrono::Local::now();
        let today_start = now
            .date_naive()
            .and_hms_opt(0, 0, 0)
            .context("构建今日起始时间失败")?
            .and_utc()
            .timestamp();
        let week_start = (now
            - chrono::Duration::days(i64::from(now.weekday().num_days_from_monday())))
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .context("构建本周起始时间失败")?
        .and_utc()
        .timestamp();

        let today_play_time_sec: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(duration_sec), 0) FROM play_sessions WHERE start_time >= ?1",
                params![today_start],
                |row| row.get(0),
            )
            .context("统计今日时长失败")?;

        let week_play_time_sec: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(duration_sec), 0) FROM play_sessions WHERE start_time >= ?1",
                params![week_start],
                |row| row.get(0),
            )
            .context("统计本周时长失败")?;

        let mut timeline_stmt = conn
            .prepare(
                r#"
                SELECT strftime('%Y-%m-%d', datetime(start_time, 'unixepoch')) AS d,
                       COALESCE(SUM(duration_sec), 0)
                FROM play_sessions
                WHERE start_time >= ?1 AND start_time <= ?2
                GROUP BY d
                ORDER BY d ASC
                "#,
            )
            .context("准备时间线查询失败")?;

        let timeline_rows = timeline_stmt
            .query_map(params![start_ts, end_ts], |row| {
                Ok(DayPlayTime {
                    date: row.get(0)?,
                    duration_sec: row.get(1)?,
                })
            })
            .context("查询时间线失败")?;

        let mut timeline = Vec::new();
        for row in timeline_rows {
            timeline.push(row.context("读取时间线记录失败")?);
        }

        let mut per_game_stmt = conn
            .prepare(
                r#"
                SELECT g.id, g.name, COALESCE(SUM(ps.duration_sec), 0) AS total_sec
                FROM games g
                INNER JOIN play_sessions ps ON ps.game_id = g.id
                WHERE ps.start_time >= ?1 AND ps.start_time <= ?2
                GROUP BY g.id, g.name
                ORDER BY total_sec DESC
                "#,
            )
            .context("准备游戏维度统计失败")?;

        let per_game_rows = per_game_stmt
            .query_map(params![start_ts, end_ts], |row| {
                Ok(GameTimeSummary {
                    game_id: row.get(0)?,
                    game_name: row.get(1)?,
                    total_sec: row.get(2)?,
                })
            })
            .context("查询游戏维度统计失败")?;

        let mut per_game = Vec::new();
        for row in per_game_rows {
            per_game.push(row.context("读取游戏维度统计记录失败")?);
        }

        Ok(GameStats {
            total_play_time_sec,
            today_play_time_sec,
            week_play_time_sec,
            session_count,
            timeline,
            per_game,
        })
    })
}

pub async fn game_library_get_home_page_data() -> Result<HomePageData> {
    with_conn(|conn| {
        let mut stmt = conn
            .prepare(
                r#"
                SELECT
                    g.id,
                    g.name,
                    g.cover_path,
                    g.company,
                    g.summary,
                    g.rating,
                    g.release_date,
                    g.path,
                    g.status,
                    g.created_at,
                    g.updated_at,
                    MAX(ps.end_time) AS last_played_at,
                    COALESCE(SUM(ps.duration_sec), 0) AS total_play_time_sec
                FROM games g
                LEFT JOIN play_sessions ps ON ps.game_id = g.id
                GROUP BY g.id, g.name, g.cover_path, g.company, g.summary, g.rating, g.release_date, g.path, g.status, g.created_at, g.updated_at
                ORDER BY last_played_at DESC
                LIMIT 1
                "#,
            )
            .context("准备查询首页最近游玩失败")?;

        let mut rows = stmt.query([]).context("查询首页最近游玩失败")?;
        let last_played_game = if let Some(row) = rows.next().context("读取首页最近游玩失败")? {
            Some(Game {
                id: row.get(0)?,
                name: row.get(1)?,
                cover_path: row.get(2)?,
                company: row.get(3)?,
                summary: row.get(4)?,
                rating: row.get(5)?,
                release_date: row.get(6)?,
                path: row.get(7)?,
                status: row.get(8)?,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
                last_played_at: row.get(11)?,
                total_play_time_sec: row.get(12)?,
                tags: vec![],
                exe_paths: vec![],
                game_dir: String::new(),
            })
        } else {
            None
        };

        let total_games: i64 = conn
            .query_row("SELECT COUNT(*) FROM games", [], |row| row.get(0))
            .context("统计游戏总数失败")?;

        let total_play_time_sec: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(duration_sec), 0) FROM play_sessions",
                [],
                |row| row.get(0),
            )
            .context("统计总游玩时长失败")?;

        let now = chrono::Local::now();
        let today_start = now
            .date_naive()
            .and_hms_opt(0, 0, 0)
            .context("构建今日起始时间失败")?
            .and_utc()
            .timestamp();
        let week_start = (now
            - chrono::Duration::days(i64::from(now.weekday().num_days_from_monday())))
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .context("构建本周起始时间失败")?
        .and_utc()
        .timestamp();

        let today_play_time_sec: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(duration_sec), 0) FROM play_sessions WHERE start_time >= ?1",
                params![today_start],
                |row| row.get(0),
            )
            .context("统计今日时长失败")?;

        let week_play_time_sec: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(duration_sec), 0) FROM play_sessions WHERE start_time >= ?1",
                params![week_start],
                |row| row.get(0),
            )
            .context("统计本周时长失败")?;

        Ok(HomePageData {
            last_played_game,
            today_play_time_sec,
            week_play_time_sec,
            total_games,
            total_play_time_sec,
        })
    })
}

pub async fn game_library_toggle_favorite(game_id: String, favorite: bool) -> Result<()> {
    if favorite {
        game_library_add_game_to_category(game_id, SYSTEM_FAVORITES_ID.to_string()).await
    } else {
        game_library_remove_game_from_category(game_id, SYSTEM_FAVORITES_ID.to_string()).await
    }
}

/// 查询指定游戏是否已收藏
pub async fn game_library_is_favorite(game_id: String) -> Result<bool> {
    with_conn(|conn| {
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM game_categories WHERE game_id = ?1 AND category_id = ?2",
                params![game_id, SYSTEM_FAVORITES_ID],
                |row| row.get(0),
            )
            .context("查询收藏状态失败")?;
        Ok(count > 0)
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// 游戏启动（OS 进程管理）
// ─────────────────────────────────────────────────────────────────────────────

/// 启动游戏进程，返回进程 PID。
/// 桌面端专用：移动端无法直接启动本地进程。
///
/// * `exe_path`      — 可执行文件路径（Windows: .exe；macOS: .app 或原生二进制）
/// * `working_dir`   — 工作目录（通常为游戏根目录）
pub async fn game_library_launch_game(exe_path: String, working_dir: String) -> Result<i64> {
    use std::process::Command;

    let exe = exe_path.trim().to_string();
    let work_dir = working_dir.trim().to_string();

    if exe.is_empty() {
        anyhow::bail!("启动路径不能为空");
    }

    #[cfg(target_os = "macos")]
    {
        if exe.to_lowercase().ends_with(".app") {
            // macOS .app 包使用 open 命令启动
            let child = Command::new("open")
                .arg(&exe)
                .spawn()
                .context("启动 .app 包失败")?;
            return Ok(child.id() as i64);
        }
    }

    let mut cmd = Command::new(&exe);
    if !work_dir.is_empty() {
        cmd.current_dir(&work_dir);
    }

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        // 不弹出 CMD 窗口
        cmd.creation_flags(0x08000000);
    }

    let child = cmd.spawn().context("启动游戏进程失败")?;
    Ok(child.id() as i64)
}

// ─────────────────────────────────────────────────────────────────────────────
// 目录扫描 & 游戏名推导
// ─────────────────────────────────────────────────────────────────────────────

/// 从路径推导游戏显示名（去掉括号/版本号/后缀等干扰字符）
#[frb(sync)]
pub fn game_library_derive_game_name(path: String) -> String {
    let p = path.trim().to_string();
    if p.is_empty() {
        return String::new();
    }

    let lower = p.to_lowercase();

    // macOS .app 包：去掉 .app 后缀
    if lower.ends_with(".app") {
        let seg = p.replace('\\', "/");
        let last = seg.split('/').last().unwrap_or(&p);
        return clean_game_name(
            &last
                .strip_suffix(".app")
                .or_else(|| last.strip_suffix(".App"))
                .unwrap_or(last),
        );
    }

    // 从父目录名推导（"Publisher/GameName/game.exe" → "GameName"）
    let normalized = p.replace('\\', "/");
    let segs: Vec<&str> = normalized.split('/').filter(|s| !s.is_empty()).collect();
    if segs.len() >= 2 {
        let parent = segs[segs.len() - 2];
        let cleaned = clean_game_name(parent);
        if !cleaned.is_empty() {
            return cleaned;
        }
    }

    // 降级：用文件名去掉已知后缀
    let file_name = segs.last().copied().unwrap_or(&p);
    let without_ext = strip_exe_ext(file_name);
    clean_game_name(without_ext)
}

fn strip_exe_ext(name: &str) -> &str {
    let lower = name.to_lowercase();
    for ext in &[".exe", ".app", ".sh", ".bat", ".cmd", ".x86_64"] {
        if lower.ends_with(ext) {
            return &name[..name.len() - ext.len()];
        }
    }
    name
}

fn clean_game_name(raw: &str) -> String {
    // 将常见分隔符/括号替换为空格，然后压缩多余空格
    let mut result = String::with_capacity(raw.len());
    for ch in raw.chars() {
        if "[]（）()【】_.".contains(ch) {
            result.push(' ');
        } else {
            result.push(ch);
        }
    }
    // 压缩连续空格
    let mut out = String::with_capacity(result.len());
    let mut last_was_space = false;
    for ch in result.chars() {
        if ch == ' ' {
            if !last_was_space {
                out.push(' ');
            }
            last_was_space = true;
        } else {
            out.push(ch);
            last_was_space = false;
        }
    }
    out.trim().to_string()
}

/// 扫描给定路径列表，识别其中包含游戏的候选目录并返回。
///
/// 规则：
/// 1. 路径本身是文件且为可执行后缀 → 直接作为候选
/// 2. 路径是 `.app` 目录 → macOS 应用包，直接作为候选
/// 3. 路径是普通目录 → 递归（最多 3 层）寻找含有可执行文件的子目录
pub async fn game_library_scan_directory(paths: Vec<String>) -> Result<Vec<ScannedGame>> {
    use std::fs;

    fn is_exe(name: &str) -> bool {
        let lower = name.to_lowercase();
        lower.ends_with(".exe")
            || lower.ends_with(".app")
            || lower.ends_with(".sh")
            || lower.ends_with(".bat")
            || lower.ends_with(".cmd")
            || lower.ends_with(".x86_64")
    }

    fn find_top_exes(dir: &std::path::Path) -> Vec<String> {
        let Ok(entries) = fs::read_dir(dir) else {
            return vec![];
        };
        entries
            .flatten()
            .filter_map(|e| {
                let p = e.path();
                if p.is_file() && is_exe(&e.file_name().to_string_lossy()) {
                    Some(p.to_string_lossy().into_owned())
                } else {
                    None
                }
            })
            .collect()
    }

    fn scan_recursive(dir: &std::path::Path, depth: usize, out: &mut Vec<ScannedGame>) {
        if depth == 0 {
            return;
        }
        let Ok(entries) = fs::read_dir(dir) else {
            return;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();

            // macOS .app 包
            if path.is_dir() && name.to_lowercase().ends_with(".app") {
                let folder_name = game_library_derive_game_name(path.to_string_lossy().into_owned());
                out.push(ScannedGame {
                    folder_path: path.to_string_lossy().into_owned(),
                    folder_name,
                    exe_paths: vec![path.to_string_lossy().into_owned()],
                });
                continue;
            }

            if path.is_dir() {
                let exes = find_top_exes(&path);
                if !exes.is_empty() {
                    // 当前目录含有可执行文件 → 视为游戏根目录，不再继续向下
                    let folder_name = game_library_derive_game_name(path.to_string_lossy().into_owned());
                    out.push(ScannedGame {
                        folder_path: path.to_string_lossy().into_owned(),
                        folder_name,
                        exe_paths: exes,
                    });
                } else {
                    // 无可执行文件 → 继续向下
                    scan_recursive(&path, depth - 1, out);
                }
            }
        }
    }

    let mut result: Vec<ScannedGame> = Vec::new();

    for raw_path in &paths {
        let p_str = raw_path.trim();
        if p_str.is_empty() {
            continue;
        }
        let p = std::path::Path::new(p_str);

        if p.is_file() {
            let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            if is_exe(&name) {
                let folder_name = game_library_derive_game_name(p_str.to_string());
                result.push(ScannedGame {
                    folder_path: p_str.to_string(),
                    folder_name,
                    exe_paths: vec![p_str.to_string()],
                });
            }
            continue;
        }

        if p.is_dir() {
            let lower = p_str.to_lowercase();
            if lower.ends_with(".app") {
                // macOS .app 包
                let folder_name = game_library_derive_game_name(p_str.to_string());
                result.push(ScannedGame {
                    folder_path: p_str.to_string(),
                    folder_name,
                    exe_paths: vec![p_str.to_string()],
                });
                continue;
            }
            // 普通目录 → 扫描子目录（最多 3 层）
            scan_recursive(p, 3, &mut result);
        }
    }

    Ok(result)
}

// ─────────────────────────────────────────────────────────────────────────────
// 游戏库设置
// ─────────────────────────────────────────────────────────────────────────────

const SETTINGS_KEY: &str = "game_library_settings";

/// 读取游戏库设置，不存在时返回默认值
pub async fn game_library_get_settings() -> Result<GameLibrarySettings> {
    with_conn(|conn| {
        let result: Option<String> = conn
            .query_row(
                "SELECT value FROM game_settings WHERE key = ?1",
                params![SETTINGS_KEY],
                |row| row.get(0),
            )
            .ok();

        if let Some(json) = result {
            let settings: GameLibrarySettings =
                serde_json::from_str(&json).context("解析游戏库设置失败")?;
            return Ok(settings);
        }

        Ok(GameLibrarySettings {
            auto_track_play_time: true,
            default_sort: "updatedAt_desc".to_string(),
            auto_save: true,
            enable_desktop_launch: true,
        })
    })
}

/// 保存游戏库设置
pub async fn game_library_save_settings(settings: GameLibrarySettings) -> Result<()> {
    with_conn(|conn| {
        let json = serde_json::to_string(&settings).context("序列化游戏库设置失败")?;
        conn.execute(
            r#"
            INSERT INTO game_settings (key, value) VALUES (?1, ?2)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            "#,
            params![SETTINGS_KEY, &json],
        )
        .context("保存游戏库设置失败")?;
        Ok(())
    })
}

/// 检查路径列表中哪些已录入（用于批量导入去重），返回已存在的路径
pub async fn game_library_check_paths_exist(paths: Vec<String>) -> Result<Vec<String>> {
    with_conn(|conn| {
        let mut existing: Vec<String> = Vec::new();
        for path in &paths {
            let p = path.trim().to_lowercase();
            if p.is_empty() {
                continue;
            }
            let count: i64 = conn
                .query_row(
                    "SELECT COUNT(*) FROM games WHERE LOWER(TRIM(path)) = ?1 OR LOWER(TRIM(game_dir)) = ?1",
                    params![&p],
                    |row| row.get(0),
                )
                .unwrap_or(0);
            if count > 0 {
                existing.push(path.clone());
            }
        }
        Ok(existing)
    })
}
