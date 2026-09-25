use slime_logger::{sw_info, sw_warn};
use std::path::PathBuf;
use std::sync::OnceLock;

use anyhow::{Context, Result};
use chrono::Datelike;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use parking_lot::Mutex;
use percent_encoding::{utf8_percent_encode, AsciiSet, CONTROLS};

/// Wiki URL 路径编码集：只编码空格、控制字符、# ? %，保留 - . _ ! ~ 等
const WIKI_PATH: &AsciiSet = &CONTROLS.add(b' ').add(b'#').add(b'?').add(b'%');
use reqwest::blocking::Client;
use rusqlite::{params, Connection};
use scraper::{Html, Selector};
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
    let conn = guard
        .as_ref()
        .context("游戏库未初始化，请先调用 game_library_init")?;
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
        conn.execute(
            "DELETE FROM game_progress WHERE game_id = ?1",
            params![game_id.clone()],
        )
        .context("删除游戏进度失败")?;
        conn.execute(
            "DELETE FROM game_categories WHERE game_id = ?1",
            params![game_id.clone()],
        )
        .context("删除游戏分类关联失败")?;
        conn.execute(
            "DELETE FROM play_sessions WHERE game_id = ?1",
            params![game_id.clone()],
        )
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
        let last_played_game = if let Some(row) = rows.next().context("读取首页最近游玩失败")?
        {
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
/// * `use_open`      — macOS 下使用 `open` 命令启动（适合 Wine/Crossover 包装）
pub async fn game_library_launch_game(
    exe_path: String,
    working_dir: String,
    // 该参数仅 macOS 分支使用，其他平台允许未读取，避免条件编译警告
    #[cfg_attr(not(target_os = "macos"), allow(unused_variables))] use_open: bool,
) -> Result<i64> {
    use std::process::Command;

    let exe = exe_path.trim().to_string();
    let work_dir = working_dir.trim().to_string();

    if exe.is_empty() {
        anyhow::bail!("启动路径不能为空");
    }

    #[cfg(target_os = "macos")]
    {
        // .app 包始终用 open；或者用户手动开启了 use_open；
        // .exe 是 Windows 二进制，macOS 无法直接执行，必须走 open（交给 Crossover/Wine）
        let lower = exe.to_lowercase();
        if lower.ends_with(".app") || lower.ends_with(".exe") || use_open {
            let child = Command::new("open")
                .arg(&exe)
                .spawn()
                .context("启动失败（open 命令）")?;
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
                let folder_name =
                    game_library_derive_game_name(path.to_string_lossy().into_owned());
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
                    let folder_name =
                        game_library_derive_game_name(path.to_string_lossy().into_owned());
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
            let name = p
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
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
            use_open_on_macos: false,
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
        // 一次性取出全部 path / game_dir 建集合，替代逐个查库。
        // 原先的 `WHERE LOWER(TRIM(path)) = ?1` 对列套了函数，索引不可用，
        // 每个待校验路径都要全表扫一遍 —— P 个路径就是 P 次全表扫描。
        let mut known: std::collections::HashSet<String> = std::collections::HashSet::new();
        {
            let mut stmt = conn
                .prepare("SELECT path, game_dir FROM games")
                .context("准备游戏路径查询失败")?;
            let mut rows = stmt.query([]).context("读取游戏路径失败")?;
            while let Some(row) = rows.next()? {
                let path: String = row.get(0)?;
                let game_dir: String = row.get(1)?;
                known.insert(path.trim().to_lowercase());
                known.insert(game_dir.trim().to_lowercase());
            }
        }

        let mut existing: Vec<String> = Vec::new();
        for path in &paths {
            let p = path.trim().to_lowercase();
            if p.is_empty() {
                continue;
            }
            if known.contains(&p) {
                existing.push(path.clone());
            }
        }
        Ok(existing)
    })
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP 工具（代理检测 + 浏览器 Client 构建）
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
static BROWSER_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";
#[cfg(target_os = "windows")]
static BROWSER_UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
static BROWSER_UA: &str = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";
static BROWSER_ACCEPT: &str = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7";
static BROWSER_ACCEPT_LANG: &str = "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,ja;q=0.6,zh-TW;q=0.5";

/// 检测系统代理：优先读取环境变量，macOS 额外尝试 `scutil --proxy`，Windows 额外尝试注册表。
fn detect_system_proxy() -> Option<String> {
    // 1. 标准环境变量
    for var in &[
        "HTTPS_PROXY",
        "https_proxy",
        "HTTP_PROXY",
        "http_proxy",
        "ALL_PROXY",
        "all_proxy",
    ] {
        if let Ok(v) = std::env::var(var) {
            if !v.is_empty() {
                return Some(v);
            }
        }
    }

    // 2. macOS 系统代理（scutil --proxy）
    #[cfg(target_os = "macos")]
    {
        if let Some(p) = macos_scutil_proxy() {
            return Some(p);
        }
    }

    // 3. Windows 系统代理（注册表）
    #[cfg(target_os = "windows")]
    {
        if let Some(p) = windows_registry_proxy() {
            return Some(p);
        }
    }

    None
}

#[cfg(target_os = "macos")]
fn macos_scutil_proxy() -> Option<String> {
    let out = std::process::Command::new("scutil")
        .arg("--proxy")
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);

    // 优先 HTTPS
    let enabled = text
        .lines()
        .find(|l| l.contains("HTTPSEnable"))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim() == "1")
        .unwrap_or(false);
    let (host_key, port_key) = if enabled {
        ("HTTPSProxy", "HTTPSPort")
    } else {
        let http_enabled = text
            .lines()
            .find(|l| l.contains("HTTPEnable"))
            .and_then(|l| l.split(':').nth(1))
            .map(|v| v.trim() == "1")
            .unwrap_or(false);
        if !http_enabled {
            return None;
        }
        ("HTTPProxy", "HTTPPort")
    };

    let host = text
        .lines()
        .find(|l| l.contains(host_key))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())?;
    let port = text
        .lines()
        .find(|l| l.contains(port_key))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
        .unwrap_or_else(|| "7890".to_string());

    if host.is_empty() {
        return None;
    }
    Some(format!("http://{}:{}", host, port))
}

#[cfg(target_os = "windows")]
fn windows_registry_proxy() -> Option<String> {
    use std::process::Command;
    let key = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings";
    let out = Command::new("reg")
        .args(["query", key, "/v", "ProxyEnable"])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let enabled = text
        .lines()
        .any(|l| l.contains("ProxyEnable") && l.contains("REG_DWORD") && l.trim().ends_with("0x1"));
    if !enabled {
        return None;
    }
    let out = Command::new("reg")
        .args(["query", key, "/v", "ProxyServer"])
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let server = text
        .lines()
        .find(|l| l.contains("ProxyServer"))?
        .split("REG_SZ")
        .nth(1)?
        .trim()
        .to_string();
    if server.is_empty() {
        return None;
    }
    if server.starts_with("http://")
        || server.starts_with("https://")
        || server.starts_with("socks")
    {
        Some(server)
    } else {
        Some(format!("http://{}", server))
    }
}

/// 构建带浏览器 UA、60s 超时、系统代理的阻塞式 HTTP Client，并缓存为全局单例。
/// 遇到连接级别错误时，可以通过 `reset_browser_client()` 让下次请求重新创建。
static BROWSER_CLIENT: OnceLock<parking_lot::Mutex<Option<Client>>> = OnceLock::new();

fn client_registry() -> &'static parking_lot::Mutex<Option<Client>> {
    BROWSER_CLIENT.get_or_init(|| parking_lot::Mutex::new(None))
}

/// 获取（或首次创建）全局共享的 HTTP Client。
fn get_browser_client() -> Result<Client> {
    let mut guard = client_registry().lock();
    if guard.is_none() {
        *guard = Some(build_browser_client()?);
    }
    // clone() 是轻量级的 Arc 克隆
    Ok(guard.as_ref().unwrap().clone())
}

/// 连接失败后重置 Client，让下次请求重新握手。
fn reset_browser_client() {
    *client_registry().lock() = None;
    sw_info!("[http] Client 已重置，下次请求将重新建立 TLS 连接");
}

/// 执行一次 GET 请求，遇到连接错误时重置 Client 并重试一次。
fn get_with_retry(url: &str) -> Result<reqwest::blocking::Response> {
    let client = get_browser_client()?;
    match client.get(url).send() {
        Ok(r) => Ok(r),
        Err(e) if e.is_connect() || e.is_timeout() => {
            sw_warn!("[http] 连接失败（{}），重置 Client 后重试: {}", url, e);
            reset_browser_client();
            let client2 = get_browser_client()?;
            client2
                .get(url)
                .send()
                .context(format!("请求失败（重试后）: {}", url))
        }
        Err(e) => Err(anyhow::anyhow!(e)),
    }
}

fn build_browser_client() -> Result<Client> {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(reqwest::header::ACCEPT, BROWSER_ACCEPT.parse().unwrap());
    headers.insert(
        reqwest::header::ACCEPT_LANGUAGE,
        BROWSER_ACCEPT_LANG.parse().unwrap(),
    );

    let mut builder = Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .user_agent(BROWSER_UA)
        .default_headers(headers)
        .cookie_store(true)
        .danger_accept_invalid_certs(false)
        .redirect(reqwest::redirect::Policy::limited(10));

    if let Some(proxy_url) = detect_system_proxy() {
        sw_info!("使用系统代理: {}", proxy_url);
        match reqwest::Proxy::all(&proxy_url) {
            Ok(proxy) => {
                builder = builder.proxy(proxy);
            }
            Err(e) => {
                sw_warn!("代理配置失败，跳过: {}", e);
            }
        }
    }

    Ok(builder.build().context("构建 HTTP Client 失败")?)
}

// ─────────────────────────────────────────────────────────────────────────────
// 萌娘百科
// ─────────────────────────────────────────────────────────────────────────────

/// 抓取萌娘百科页面并返回 `#moe-body-content` 下的清洗后 HTML。
pub async fn game_library_fetch_moegirl(game_name: String) -> Result<String> {
    tokio::task::spawn_blocking(move || fetch_moegirl_sync(&game_name)).await?
}

fn fetch_moegirl_sync(game_name: &str) -> Result<String> {
    let encoded = utf8_percent_encode(game_name, WIKI_PATH).to_string();
    let url = format!("https://zh.moegirl.org.cn/{}", encoded);
    let resp = get_with_retry(&url).context("萌娘百科请求失败")?;
    let status = resp.status();
    if !status.is_success() {
        anyhow::bail!("萌娘百科返回 HTTP {}", status);
    }
    let html = resp.text().context("读取响应失败")?;
    let result = clean_moegirl_html(&html);
    if result.is_empty() {
        anyhow::bail!("未找到页面内容（#moe-body-content / #mw-content-text 均不存在）");
    }
    Ok(result)
}

fn clean_moegirl_html(raw: &str) -> String {
    if raw.is_empty() {
        return String::new();
    }
    let doc = Html::parse_document(raw);
    // 按优先级尝试萌娘百科 / MediaWiki 的内容容器
    let candidates = [
        "#moe-body-content",
        "#mw-content-text",
        "#bodyContent",
        "#content",
    ];
    let root_opt = candidates.iter().find_map(|sel| {
        Selector::parse(sel)
            .ok()
            .and_then(|s| doc.select(&s).next())
    });
    let Some(root) = root_opt else {
        return String::new();
    };

    // 收集需要剔除的公告节点（class 以 xUkJeF1d7d_ 开头）
    // scraper 不支持原地修改，直接序列化并在字符串层面移除对应标签块
    // 改用：序列化原始 inner_html，然后用 HTML 解析器二次过滤
    let inner = root.inner_html();

    // 二次解析，移除公告 class 元素
    let Ok(sel_notice) = Selector::parse("[class]") else {
        return inner;
    };
    let fragment = Html::parse_fragment(&inner);
    let mut result = inner.clone();

    // 收集所有需要去除的 html 片段（以其外层 html 为键）
    for el in fragment.select(&sel_notice) {
        let cls = el.value().attr("class").unwrap_or("");
        if cls.split_whitespace().any(|c| c.starts_with("xUkJeF1d7d_")) {
            let outer = el.html();
            result = result.replace(&outer, "");
        }
    }
    // 移除公告 class 元素、<table>、<img>、<style>、<script>
    let result = strip_problematic_tags(&result);
    if result.trim().is_empty() {
        String::new()
    } else {
        result
    }
}

/// 删除会导致 Flutter HtmlWidget / LayoutBuilder 崩溃的标签：
/// - 自闭合：`<img>`
/// - 带内容的块：`<table>…</table>` `<style>…</style>` `<script>…</script>`
fn strip_problematic_tags(html: &str) -> String {
    // style / script 整块删除（内容本身不需要展示）
    let html = strip_paired_tags(html, "style");
    let html = strip_paired_tags(&html, "script");
    // table 只去掉结构标签，保留单元格内文字（避免删得太多）
    let html = strip_table_structure_tags(&html);
    // <img> 保留：已换用完整包 flutter_widget_from_html，可正确渲染网络图片
    html
}

/// 删除 table/thead/tbody/tfoot/tr/td/th/caption/colgroup/col 等结构标签，
/// 但保留这些标签内部的文字内容（只摘掉标签包装，不抹内容）。
fn strip_table_structure_tags(html: &str) -> String {
    const TABLE_TAGS: &[&str] = &[
        "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption", "colgroup", "col",
    ];
    let mut result = html.to_string();
    for tag in TABLE_TAGS {
        result = strip_open_tag_keep_content(&result, tag);
        let close_l = format!("</{}>", tag);
        let close_u = close_l.to_uppercase();
        result = result.replace(&close_l, "").replace(&close_u, "");
    }
    result
}

/// 删除所有 `<TAG ...>` 开标签（含属性），但不删标签内的内容。
fn strip_open_tag_keep_content(html: &str, tag: &str) -> String {
    let open_l = format!("<{}", tag);
    let open_u = open_l.to_uppercase();
    let mut result = String::with_capacity(html.len());
    let mut rest = html;
    loop {
        let pos = find_case_insensitive(rest, &open_l, &open_u);
        let Some(start) = pos else {
            result.push_str(rest);
            break;
        };
        // 确认后跟空白 / > 而非字母（避免误匹配 <tableX>）
        let after = &rest[start + open_l.len()..];
        let boundary = after
            .chars()
            .next()
            .map_or(true, |c| !c.is_alphanumeric() && c != '-' && c != '_');
        if !boundary {
            result.push_str(&rest[..start + open_l.len()]);
            rest = &rest[start + open_l.len()..];
            continue;
        }
        result.push_str(&rest[..start]);
        // 跳过开标签本身（含属性，直到 >）
        if let Some(gt_rel) = rest[start..].find('>') {
            rest = &rest[start + gt_rel + 1..];
        } else {
            break;
        }
    }
    result
}

/// 删除所有 `<TAG ...>…</TAG>`（不区分大小写），返回新字符串。
fn strip_paired_tags(html: &str, tag: &str) -> String {
    let open_lower = format!("<{}", tag);
    let open_upper = open_lower.to_uppercase();
    let close_lower = format!("</{}>", tag);
    let close_upper = close_lower.to_uppercase();

    let mut result = String::with_capacity(html.len());
    let mut rest = html;
    loop {
        // 找最早的开标签
        let pos = find_case_insensitive(rest, &open_lower, &open_upper);
        let Some(start) = pos else {
            result.push_str(rest);
            break;
        };
        // 确认 <tag> 后紧跟空白或 > 而非字母（避免误匹配 <tableX>）
        let boundary = rest[start + open_lower.len()..]
            .chars()
            .next()
            .map_or(true, |c| !c.is_alphanumeric() && c != '-' && c != '_');
        if !boundary {
            result.push_str(&rest[..start + open_lower.len()]);
            rest = &rest[start + open_lower.len()..];
            continue;
        }
        result.push_str(&rest[..start]);
        // 找对应的闭标签（支持嵌套，如 <table> 内嵌 <table>）
        let search_from = &rest[start..];
        let end = find_paired_close(
            search_from,
            &open_lower,
            &open_upper,
            &close_lower,
            &close_upper,
        );
        match end {
            Some(end_pos) => {
                rest = &rest[start + end_pos..];
            }
            None => {
                break;
            } // 没有闭标签，截断
        }
    }
    result
}

/// 在 `haystack` 中不区分大小写查找第一个匹配位置。
fn find_case_insensitive(haystack: &str, lower: &str, upper: &str) -> Option<usize> {
    // 粗略：对字节串执行两次 find，取较小者
    let a = haystack.find(lower);
    let b = haystack.find(upper);
    match (a, b) {
        (Some(x), Some(y)) => Some(x.min(y)),
        (Some(x), None) | (None, Some(x)) => Some(x),
        (None, None) => None,
    }
}

/// 在 `html`（从某个开标签开始）中找到对应的闭标签位置（闭标签结束后的索引），支持同名嵌套。
fn find_paired_close(
    html: &str,
    open_l: &str,
    open_u: &str,
    close_l: &str,
    close_u: &str,
) -> Option<usize> {
    let mut depth = 0usize;
    let mut pos = 0usize;
    while pos < html.len() {
        let rest = &html[pos..];
        let next_open = find_case_insensitive(rest, open_l, open_u);
        let next_close = find_case_insensitive(rest, close_l, close_u);
        match (next_open, next_close) {
            (Some(o), Some(c)) if o < c => {
                // 确认是真正的开标签
                let after = &rest[o + open_l.len()..];
                if after
                    .chars()
                    .next()
                    .map_or(true, |ch| !ch.is_alphanumeric() && ch != '-' && ch != '_')
                {
                    depth += 1;
                }
                pos += o + open_l.len();
            }
            (_, Some(c)) => {
                if depth == 0 {
                    return Some(pos + c + close_l.len());
                }
                depth -= 1;
                if depth == 0 {
                    // 已匹配到对应的闭标签，立即返回
                    return Some(pos + c + close_l.len());
                }
                pos += c + close_l.len();
            }
            _ => return None,
        }
    }
    None
}

/// 删除所有自闭合的 `<TAG ...>` 标签（不区分大小写，无结束标签）。
#[allow(dead_code)]
fn strip_void_tag(html: &str, tag: &str) -> String {
    let open_lower = format!("<{}", tag);
    let open_upper = open_lower.to_uppercase();
    let mut result = String::with_capacity(html.len());
    let mut rest = html;
    loop {
        let pos = find_case_insensitive(rest, &open_lower, &open_upper);
        let Some(start) = pos else {
            result.push_str(rest);
            break;
        };
        let after = &rest[start + open_lower.len()..];
        let boundary = after.chars().next().map_or(true, |c| !c.is_alphanumeric());
        if boundary {
            result.push_str(&rest[..start]);
            if let Some(close) = rest[start..].find('>') {
                rest = &rest[start + close + 1..];
            } else {
                break;
            }
        } else {
            result.push_str(&rest[..start + open_lower.len()]);
            rest = &rest[start + open_lower.len()..];
        }
    }
    result
}

// ─────────────────────────────────────────────────────────────────────────────
// 2DFan
// ─────────────────────────────────────────────────────────────────────────────

const TWODFAN_BASE: &str = "https://2dfan.com";

/// 搜索游戏，返回 subject 路径（如 `/subjects/1497`）；未找到时返回空字符串。
pub async fn game_library_search_2dfan_subject(game_name: String) -> Result<String> {
    tokio::task::spawn_blocking(move || search_2dfan_subject_sync(&game_name)).await?
}

fn search_2dfan_subject_sync(game_name: &str) -> Result<String> {
    let encoded = utf8_percent_encode(game_name, WIKI_PATH).to_string();
    let url = format!("{}/subjects/search?keyword={}", TWODFAN_BASE, encoded);
    let html = get_with_retry(&url)?.text()?;
    let doc = Html::parse_document(&html);
    let Ok(sel) = Selector::parse("#subjects > li a") else {
        return Ok(String::new());
    };
    Ok(doc
        .select(&sel)
        .next()
        .and_then(|el| el.value().attr("href"))
        .unwrap_or("")
        .to_string())
}

/// 给定 subject 路径，抓取 CG/存档下载页，返回第一个下载项路径（如 `/downloads/41956`）。
pub async fn game_library_fetch_2dfan_download_path(subject_path: String) -> Result<String> {
    tokio::task::spawn_blocking(move || fetch_2dfan_download_path_sync(&subject_path)).await?
}

/// 返回下载列表页所有条目：JSON 数组 `[{"path": "...", "title": "..."}]`。
fn fetch_2dfan_download_path_sync(subject_path: &str) -> Result<String> {
    let url = format!("{}{}/downloads/kind/cg_save", TWODFAN_BASE, subject_path);
    let html = get_with_retry(&url)?.text()?;
    let doc = Html::parse_document(&html);

    let mut items: Vec<serde_json::Value> = Vec::new();

    // 尝试按 li 枚举所有条目
    let li_candidates = [
        "#content > div > div > div.block-content.collapse.in > ul > li",
        "#content > div > div > div.block-content.in > ul > li",
        "#content ul li",
    ];
    let a_inner = Selector::parse("div > h4 > a, h4 > a, h4 a").ok();
    for li_s in &li_candidates {
        if let (Ok(li_sel), Some(ref a_sel)) = (Selector::parse(li_s), a_inner.as_ref()) {
            let lis: Vec<_> = doc.select(&li_sel).collect();
            if lis.is_empty() {
                continue;
            }
            for li in lis {
                if let Some(a) = li.select(a_sel).next() {
                    if let Some(href) = a.value().attr("href") {
                        if !href.is_empty() {
                            let title = a.text().collect::<String>();
                            let title = title.trim();
                            let display = if title.is_empty() { href } else { title };
                            items.push(serde_json::json!({ "path": href, "title": display }));
                        }
                    }
                }
            }
            if !items.is_empty() {
                break;
            }
        }
    }

    // 若以上均未找到，回退到旧的单条精确选择
    if items.is_empty() {
        for s in &[
            "#content > div > div > div.block-content.collapse.in > ul > li:nth-child(1) > div > h4 > a",
            "#content ul li h4 a",
        ] {
            if let Ok(sel) = Selector::parse(s) {
                if let Some(el) = doc.select(&sel).next() {
                    if let Some(href) = el.value().attr("href") {
                        let title = el.text().collect::<String>();
                        let title = title.trim();
                        let display = if title.is_empty() { href } else { title };
                        items.push(serde_json::json!({ "path": href, "title": display }));
                        break;
                    }
                }
            }
        }
    }

    Ok(serde_json::to_string(&items).unwrap_or_else(|_| "[]".to_string()))
}

/// 给定下载详情路径，返回 JSON：`{ fileUrl, description }`。
pub async fn game_library_fetch_2dfan_download_info(download_path: String) -> Result<String> {
    tokio::task::spawn_blocking(move || fetch_2dfan_download_info_sync(&download_path)).await?
}

fn fetch_2dfan_download_info_sync(download_path: &str) -> Result<String> {
    let url = format!("{}{}", TWODFAN_BASE, download_path);
    let html = get_with_retry(&url)?.text()?;
    let doc = Html::parse_document(&html);

    // 下载按钮
    let file_url = if let Ok(sel) = Selector::parse(
        "#content > div > div > div:nth-child(3) > div > div > div > div:nth-child(2) > p.tags.link-container > a.btn.btn-primary",
    ) {
        doc.select(&sel).next()
            .and_then(|el| el.value().attr("href"))
            .map(|href| {
                if href.starts_with("http") {
                    href.to_string()
                } else {
                    format!("{}{}", TWODFAN_BASE, href)
                }
            })
            .unwrap_or_default()
    } else {
        String::new()
    };

    // 简介
    let description = if let Ok(sel) = Selector::parse(
        "#content > div > div > div:nth-child(3) > div > div > div > div.control-group.well.well-small",
    ) {
        doc.select(&sel).next()
            .map(|el| el.text().collect::<Vec<_>>().join("").trim().to_string())
            .unwrap_or_default()
    } else {
        String::new()
    };

    Ok(serde_json::json!({ "fileUrl": file_url, "description": description }).to_string())
}

/// 下载文件到指定路径，返回最终保存路径。
pub async fn game_library_download_file(url: String, save_path: String) -> Result<()> {
    tokio::task::spawn_blocking(move || download_file_sync(&url, &save_path)).await?
}

fn download_file_sync(url: &str, save_path: &str) -> Result<()> {
    let client = get_browser_client()?;
    let mut resp = match client.get(url).send() {
        Ok(r) => r,
        Err(e) if e.is_connect() || e.is_timeout() => {
            reset_browser_client();
            get_browser_client()?
                .get(url)
                .send()
                .context("下载请求失败")?
        }
        Err(e) => return Err(anyhow::anyhow!(e)),
    };
    if !resp.status().is_success() {
        anyhow::bail!("下载失败 HTTP {}", resp.status());
    }
    let mut file = std::fs::File::create(save_path).context("创建文件失败")?;
    std::io::copy(&mut resp, &mut file).context("写入文件失败")?;
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
// 单元测试
//
// 说明：本模块 CRUD 函数全部经由全局 DB_CONN（game_library_init 设置），
// cargo test 默认多线程并行执行各 #[test]，因此：
// 1. 所有依赖全局连接的用例用 API_TEST_LOCK 串行化；
// 2. 每个用例在持锁状态下初始化自己专属的临时库文件，互不污染；
// 3. 联网抓取（moegirl/2dfan/Steam）与 launch_game 不在此测试范围。
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard};

    /// 全局 DB_CONN 串行化锁：防止 cargo test 多线程并行操作同一连接
    static API_TEST_LOCK: Mutex<()> = Mutex::new(());

    fn lock_api() -> MutexGuard<'static, ()> {
        API_TEST_LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// 不依赖 tokio macros feature 的简易 block_on（被测函数内部无真实挂起点）
    fn block_on<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .expect("构建 tokio 运行时失败")
            .block_on(f)
    }

    /// 初始化一个全新的临时数据库文件并写入全局连接（须在持锁状态下调用）
    fn init_temp_db() {
        let dir = std::env::temp_dir().join(format!("gamelib_test_{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("创建临时目录失败");
        let path = dir.join("library.db");
        game_library_init(path.to_string_lossy().into_owned()).expect("初始化游戏库失败");
    }

    /// 构造一个仅用于测试的 Game 实体
    fn make_game(id: &str, name: &str) -> Game {
        Game {
            id: id.to_string(),
            name: name.to_string(),
            cover_path: String::new(),
            company: String::new(),
            summary: String::new(),
            rating: 0.0,
            release_date: String::new(),
            path: String::new(),
            status: "not_started".to_string(),
            created_at: 0,
            updated_at: 0,
            last_played_at: None,
            total_play_time_sec: 0,
            tags: vec![],
            exe_paths: vec![],
            game_dir: String::new(),
        }
    }

    /// 构造一条游玩会话（id 留空由服务端生成）
    fn make_session(game_id: &str, start: i64, duration: i64) -> PlaySession {
        PlaySession {
            id: String::new(),
            game_id: game_id.to_string(),
            start_time: start,
            end_time: start + duration,
            duration_sec: duration,
        }
    }

    // ── 游戏 CRUD 完整往返 ────────────────────────────────────────────────

    #[test]
    fn game_crud_round_trip() {
        let _guard = lock_api();
        init_temp_db();
        assert!(game_library_is_ready(), "init 后应处于就绪状态");

        // 1. 空 id 新增 → 服务端应生成 UUID
        let mut new_game = make_game("", "星河叙事曲");
        new_game.cover_path = "/covers/star.png".to_string();
        new_game.company = "Studio Alpha".to_string();
        new_game.summary = "一部视觉小说".to_string();
        new_game.rating = 8.5;
        new_game.release_date = "2021-06-01".to_string();
        new_game.path = "/games/star/game.exe".to_string();
        new_game.status = "playing".to_string();
        new_game.tags = vec!["剧情".to_string(), "R18".to_string()];
        new_game.exe_paths = vec!["/games/star/game.exe".to_string()];
        new_game.game_dir = "/games/star".to_string();
        let added = block_on(game_library_add_game(new_game)).expect("新增游戏失败");
        assert!(!added.id.trim().is_empty(), "空 id 应由服务端生成 UUID");
        assert!(added.created_at > 0, "created_at 应由服务端填充当前时间");
        assert_eq!(added.updated_at, added.created_at);

        // 2. 按 id 查询 → 全字段往返一致（含 tags/exe_paths JSON 列表）
        let fetched = block_on(game_library_get_game_by_id(added.id.clone()))
            .expect("查询游戏失败")
            .expect("新增的游戏应能查到");
        assert_eq!(fetched.name, "星河叙事曲");
        assert_eq!(fetched.cover_path, "/covers/star.png");
        assert_eq!(fetched.company, "Studio Alpha");
        assert_eq!(fetched.summary, "一部视觉小说");
        assert_eq!(fetched.rating, 8.5);
        assert_eq!(fetched.release_date, "2021-06-01");
        assert_eq!(fetched.status, "playing");
        assert_eq!(fetched.tags, vec!["剧情".to_string(), "R18".to_string()]);
        assert_eq!(fetched.exe_paths, vec!["/games/star/game.exe".to_string()]);
        assert_eq!(fetched.game_dir, "/games/star");
        // 无游玩记录时：last_played_at 为 None、总时长为 0
        assert_eq!(fetched.last_played_at, None);
        assert_eq!(fetched.total_play_time_sec, 0);

        // 3. 显式 id 新增 → 保留原 id
        let explicit = block_on(game_library_add_game(make_game("game-fixed-001", "固定ID游戏")))
            .expect("显式 id 新增失败");
        assert_eq!(explicit.id, "game-fixed-001");

        // 4. 更新字段 → 查询反映新值，created_at 不变
        let mut updated = fetched.clone();
        updated.name = "星河叙事曲 全年龄版".to_string();
        updated.rating = 9.0;
        updated.status = "completed".to_string();
        updated.tags = vec!["剧情".to_string()];
        updated.game_dir = "/games/star2".to_string();
        block_on(game_library_update_game(updated)).expect("更新游戏失败");
        let refetched = block_on(game_library_get_game_by_id(added.id.clone()))
            .expect("查询失败")
            .expect("更新后仍可查到");
        assert_eq!(refetched.name, "星河叙事曲 全年龄版");
        assert_eq!(refetched.rating, 9.0);
        assert_eq!(refetched.status, "completed");
        assert_eq!(refetched.tags, vec!["剧情".to_string()]);
        assert_eq!(refetched.game_dir, "/games/star2");
        assert_eq!(
            refetched.created_at, fetched.created_at,
            "更新不应改动 created_at"
        );
        assert!(refetched.updated_at >= fetched.updated_at);

        // 5. 更新不存在的 id → 不报错（UPDATE 影响 0 行），也不产生新数据
        block_on(game_library_update_game(make_game(
            "game-not-exist-999",
            "幽灵游戏",
        )))
        .expect("更新不存在 id 应静默成功");
        assert!(block_on(game_library_get_game_by_id(
            "game-not-exist-999".to_string()
        ))
        .expect("查询失败")
        .is_none());

        // 6. 列表查询：包含全部已录入游戏
        let games = block_on(game_library_get_games()).expect("列表查询失败");
        let ids: Vec<&str> = games.iter().map(|g| g.id.as_str()).collect();
        assert!(ids.contains(&added.id.as_str()), "列表应包含第一个游戏");
        assert!(ids.contains(&"game-fixed-001"), "列表应包含第二个游戏");

        // 7. 查询不存在的 id → Ok(None)
        assert!(block_on(game_library_get_game_by_id(
            "no-such-id".to_string()
        ))
        .expect("查询失败")
        .is_none());

        // 8. 删除不存在的 id → 不报错
        block_on(game_library_delete_game("no-such-id".to_string()))
            .expect("删除不存在 id 应静默成功");

        // 9. 删除已存在游戏 → 查询消失
        block_on(game_library_delete_game("game-fixed-001".to_string()))
            .expect("删除游戏失败");
        assert!(block_on(game_library_get_game_by_id(
            "game-fixed-001".to_string()
        ))
        .expect("查询失败")
        .is_none());
    }

    // ── 删除游戏的级联清理 ────────────────────────────────────────────────

    #[test]
    fn delete_game_cascades_related_rows() {
        let _guard = lock_api();
        init_temp_db();

        let victim = block_on(game_library_add_game(make_game(
            "victim-game",
            "将被删除",
        )))
        .expect("新增游戏失败");
        let survivor = block_on(game_library_add_game(make_game(
            "survivor-game",
            "保留游戏",
        )))
        .expect("新增游戏失败");

        // 关联数据：游玩记录（远古时间戳）、分类、进度
        block_on(game_library_add_play_session(make_session(
            &victim.id,
            1500000000,
            60,
        )))
        .expect("写入游玩会话失败");
        block_on(game_library_add_play_session(make_session(
            &survivor.id,
            1500000001,
            90,
        )))
        .expect("写入游玩会话失败");
        let cat = block_on(game_library_upsert_category(Category {
            id: "cascade-cat".to_string(),
            name: "级联分类".to_string(),
            emoji: "🗂".to_string(),
            is_system: false,
            game_count: 0,
            created_at: 0,
        }))
        .expect("建分类失败");
        block_on(game_library_add_game_to_category(
            victim.id.clone(),
            cat.id.clone(),
        ))
        .expect("关联分类失败");
        block_on(game_library_upsert_progress(GameProgress {
            id: String::new(),
            game_id: victim.id.clone(),
            chapter: "第1章".to_string(),
            route: "A线".to_string(),
            note: String::new(),
            updated_at: 0,
        }))
        .expect("写入进度失败");

        // 前置确认：三类关联数据都在
        assert!(!block_on(game_library_get_play_sessions(victim.id.clone()))
            .expect("查会话失败")
            .is_empty());
        assert!(!block_on(game_library_get_game_categories(victim.id.clone()))
            .expect("查分类失败")
            .is_empty());
        assert!(!block_on(game_library_get_progress(victim.id.clone()))
            .expect("查进度失败")
            .is_empty());

        // 删除并验证级联清理
        block_on(game_library_delete_game(victim.id.clone())).expect("删除游戏失败");
        assert!(block_on(game_library_get_play_sessions(victim.id.clone()))
            .expect("查会话失败")
            .is_empty(),
            "删除游戏后其游玩记录应被清除");
        assert!(block_on(game_library_get_game_categories(victim.id.clone()))
            .expect("查分类失败")
            .is_empty(),
            "删除游戏后其分类关联应被清除");
        assert!(block_on(game_library_get_progress(victim.id.clone()))
            .expect("查进度失败")
            .is_empty(),
            "删除游戏后其进度记录应被清除");

        // 其他游戏数据不受影响
        assert_eq!(
            block_on(game_library_get_play_sessions(survivor.id.clone()))
                .expect("查会话失败")
                .len(),
            1,
            "无关游戏的游玩记录不应被误删"
        );
    }

    // ── 分类 CRUD 与游戏-分类关联 ─────────────────────────────────────────

    #[test]
    fn category_crud_and_game_category_linking() {
        let _guard = lock_api();
        init_temp_db();

        block_on(game_library_add_game(make_game("cat-link-game", "分类测试游戏")))
            .expect("新增游戏失败");

        // 1. 显式 id upsert 新分类
        let c1 = block_on(game_library_upsert_category(Category {
            id: "cat-visual".to_string(),
            name: "视觉小说".to_string(),
            emoji: "📖".to_string(),
            is_system: false,
            game_count: 0,
            created_at: 0,
        }))
        .expect("新增分类失败");
        assert_eq!(c1.id, "cat-visual");

        // 2. 空 id upsert → 生成 UUID
        let c2 = block_on(game_library_upsert_category(Category {
            id: "  ".to_string(),
            name: "随机ID分类".to_string(),
            emoji: String::new(),
            is_system: false,
            game_count: 0,
            created_at: 0,
        }))
        .expect("空 id 建分类失败");
        assert!(!c2.id.trim().is_empty(), "空 id 应生成 UUID");

        // 3. 同 id 再次 upsert → 改名而非重复插入
        block_on(game_library_upsert_category(Category {
            id: "cat-visual".to_string(),
            name: "GalGame".to_string(),
            emoji: "💃".to_string(),
            is_system: false,
            game_count: 0,
            created_at: 0,
        }))
        .expect("更新分类失败");
        let cats = block_on(game_library_get_categories()).expect("查分类列表失败");
        let visual = cats
            .iter()
            .find(|c| c.id == "cat-visual")
            .expect("分类应存在");
        assert_eq!(visual.name, "GalGame", "upsert 同 id 应更新名称");
        assert_eq!(
            cats.iter().filter(|c| c.id == "cat-visual").count(),
            1,
            "upsert 不应产生重复行"
        );

        // 4. 关联游戏 + 重复关联应被 INSERT OR IGNORE 吞掉，game_count 保持 1
        block_on(game_library_add_game_to_category(
            "cat-link-game".to_string(),
            "cat-visual".to_string(),
        ))
        .expect("关联分类失败");
        block_on(game_library_add_game_to_category(
            "cat-link-game".to_string(),
            "cat-visual".to_string(),
        ))
        .expect("重复关联失败（应被忽略）");
        let cats = block_on(game_library_get_categories()).expect("查分类列表失败");
        let visual = cats.iter().find(|c| c.id == "cat-visual").expect("存在");
        assert_eq!(visual.game_count, 1, "重复关联不应增加游戏计数");

        // 5. 按游戏查关联分类
        let game_cats = block_on(game_library_get_game_categories(
            "cat-link-game".to_string(),
        ))
        .expect("查游戏分类失败");
        assert!(game_cats.iter().any(|c| c.id == "cat-visual"));
        // 未关联任何分类的游戏 → 空列表
        assert!(block_on(game_library_get_game_categories("cat-unknown".to_string()))
            .expect("查游戏分类失败")
            .is_empty());

        // 6. 解除关联
        block_on(game_library_remove_game_from_category(
            "cat-link-game".to_string(),
            "cat-visual".to_string(),
        ))
        .expect("解除关联失败");
        assert!(block_on(game_library_get_game_categories(
            "cat-link-game".to_string()
        ))
        .expect("查游戏分类失败")
        .is_empty());
        // 重复解除不报错（DELETE 0 行）
        block_on(game_library_remove_game_from_category(
            "cat-link-game".to_string(),
            "cat-visual".to_string(),
        ))
        .expect("重复解除关联应静默成功");

        // 7. 删除普通分类 / 删除不存在分类；系统分类禁止删除
        block_on(game_library_delete_category(c2.id.clone())).expect("删除分类失败");
        let cats = block_on(game_library_get_categories()).expect("查分类列表失败");
        assert!(!cats.iter().any(|c| c.id == c2.id), "已删除分类不应出现");
        block_on(game_library_delete_category("cat-not-exist".to_string()))
            .expect("删除不存在分类应静默成功");
        let sys_delete = block_on(game_library_delete_category(
            SYSTEM_FAVORITES_ID.to_string(),
        ));
        assert!(sys_delete.is_err(), "系统分类不允许删除");
    }

    // ── 收藏（系统分类）切换 ──────────────────────────────────────────────

    #[test]
    fn favorite_toggle_uses_system_category() {
        let _guard = lock_api();
        init_temp_db();

        block_on(game_library_add_game(make_game("fav-game", "收藏测试")))
            .expect("新增游戏失败");

        // 初始未收藏
        assert!(
            !block_on(game_library_is_favorite("fav-game".to_string()))
                .expect("查询收藏状态失败"),
            "新游戏默认不应是收藏"
        );

        // 收藏 → is_favorite 为 true，且出现在游戏分类里
        block_on(game_library_toggle_favorite("fav-game".to_string(), true))
            .expect("收藏失败");
        assert!(block_on(game_library_is_favorite("fav-game".to_string()))
            .expect("查询失败"));
        let game_cats = block_on(game_library_get_game_categories("fav-game".to_string()))
            .expect("查游戏分类失败");
        assert!(
            game_cats.iter().any(|c| c.id == SYSTEM_FAVORITES_ID),
            "收藏后应关联系统分类"
        );

        // 重复收藏不报错（INSERT OR IGNORE）
        block_on(game_library_toggle_favorite("fav-game".to_string(), true))
            .expect("重复收藏应静默成功");

        // 取消收藏
        block_on(game_library_toggle_favorite("fav-game".to_string(), false))
            .expect("取消收藏失败");
        assert!(
            !block_on(game_library_is_favorite("fav-game".to_string()))
                .expect("查询失败")
        );

        // 不存在的游戏：查询返回 false 而非报错
        assert!(
            !block_on(game_library_is_favorite("no-such-game".to_string()))
                .expect("查询不存在游戏收藏状态失败")
        );
    }

    // ── 游玩记录与 stats 时间窗口聚合 ─────────────────────────────────────

    #[test]
    fn play_sessions_and_stats_time_window() {
        let _guard = lock_api();
        init_temp_db();

        block_on(game_library_add_game(make_game("stats-g1", "统计游戏一")))
            .expect("新增游戏失败");
        block_on(game_library_add_game(make_game("stats-g2", "统计游戏二")))
            .expect("新增游戏失败");

        // 全部用固定远古时间戳（2020-09-13，UTC 同一天），避免污染今日/本周统计。
        // 窗口 [1600000000, 1600003600]：
        //   窗口内 G1：1600000000(7s 边界含) + 1600000100(600s) + 1600001000(1200s)
        //             + 1600003600(11s 边界含) = 1818s
        //   窗口外 G1：1599999999(9999s 早于窗口) + 1600003601(8888s 晚于窗口)
        //   窗口内 G2：1600002000(300s)
        let (w_start, w_end) = (1_600_000_000i64, 1_600_003_600i64);
        let g1_sessions = [
            (w_start, 7i64),
            (1_600_000_100, 600),
            (1_600_001_000, 1200),
            (w_end, 11),
            (1_599_999_999, 9999),
            (1_600_003_601, 8888),
        ];
        for (start, dur) in g1_sessions {
            block_on(game_library_add_play_session(make_session("stats-g1", start, dur)))
                .expect("写入 G1 会话失败");
        }
        block_on(game_library_add_play_session(make_session("stats-g2", 1_600_002_000, 300)))
            .expect("写入 G2 会话失败");

        // 1. 会话列表：全部返回（不分窗口）且按 start_time 降序
        let sessions = block_on(game_library_get_play_sessions("stats-g1".to_string()))
            .expect("查游玩记录失败");
        assert_eq!(sessions.len(), 6, "G1 应有 6 条会话");
        for pair in sessions.windows(2) {
            assert!(
                pair[0].start_time >= pair[1].start_time,
                "游玩记录应按开始时间降序"
            );
        }
        assert_eq!(sessions[0].start_time, 1_600_003_601);
        assert_eq!(sessions.last().expect("非空").start_time, 1_599_999_999);
        // 无会话的游戏 → 空列表
        assert!(block_on(game_library_get_play_sessions("stats-none".to_string()))
            .expect("查询失败")
            .is_empty());

        // 2. stats 窗口聚合：求和只含 [w_start, w_end]（含边界）
        let stats = block_on(game_library_get_stats(w_start, w_end)).expect("统计失败");
        assert_eq!(stats.total_play_time_sec, 1818 + 300, "窗口总时长应为 2118s");
        assert_eq!(stats.session_count, 5, "窗口内会话数应为 5");

        // 3. 时间轴：全部落在 UTC 2020-09-13 一天
        assert_eq!(stats.timeline.len(), 1, "窗口内会话同属一天");
        assert_eq!(stats.timeline[0].date, "2020-09-13");
        assert_eq!(stats.timeline[0].duration_sec, 2118);

        // 4. 游戏维度：按总时长降序 G1 > G2
        assert_eq!(stats.per_game.len(), 2);
        assert_eq!(stats.per_game[0].game_id, "stats-g1");
        assert_eq!(stats.per_game[0].game_name, "统计游戏一");
        assert_eq!(stats.per_game[0].total_sec, 1818);
        assert_eq!(stats.per_game[1].game_id, "stats-g2");
        assert_eq!(stats.per_game[1].total_sec, 300);

        // 5. 今日/本周：目前应为 0；写入一条「现在」的会话后应各为 100
        assert_eq!(stats.today_play_time_sec, 0, "远古数据不应计入今日");
        assert_eq!(stats.week_play_time_sec, 0, "远古数据不应计入本周");
        let now = chrono::Utc::now().timestamp();
        block_on(game_library_add_play_session(make_session("stats-g1", now, 100)))
            .expect("写入当前会话失败");
        let stats2 = block_on(game_library_get_stats(w_start, w_end)).expect("统计失败");
        assert_eq!(stats2.today_play_time_sec, 100, "当前会话应计入今日");
        assert_eq!(stats2.week_play_time_sec, 100, "当前会话应计入本周");
        // 当前会话在远古窗口之外，不影响窗口统计
        assert_eq!(stats2.total_play_time_sec, 2118);
        assert_eq!(stats2.session_count, 5);

        // 6. 空窗口：全零且时间轴/游戏维度为空
        let empty = block_on(game_library_get_stats(1, 2)).expect("统计失败");
        assert_eq!(empty.total_play_time_sec, 0);
        assert_eq!(empty.session_count, 0);
        assert!(empty.timeline.is_empty());
        assert!(empty.per_game.is_empty());

        // 7. 游戏详情聚合：总时长 = 全部会话求和，last_played_at = 最大 end_time
        let g1 = block_on(game_library_get_game_by_id("stats-g1".to_string()))
            .expect("查询失败")
            .expect("游戏存在");
        assert_eq!(g1.total_play_time_sec, 7 + 600 + 1200 + 11 + 9999 + 8888 + 100);
        // last_played_at = 全部会话最大 end_time；now+100 远大于 2020 年的 1600012489
        assert_eq!(g1.last_played_at, Some(now + 100));
    }

    // ── 首页数据 ──────────────────────────────────────────────────────────

    #[test]
    fn home_page_data_aggregates() {
        let _guard = lock_api();
        init_temp_db();

        // 空库：无最近游玩、全零
        let empty = block_on(game_library_get_home_page_data()).expect("查首页数据失败");
        assert!(empty.last_played_game.is_none(), "空库应无最近游玩游戏");
        assert_eq!(empty.total_games, 0);
        assert_eq!(empty.total_play_time_sec, 0);

        block_on(game_library_add_game(make_game("home-g1", "首页游戏一")))
            .expect("新增失败");
        block_on(game_library_add_game(make_game("home-g2", "首页游戏二")))
            .expect("新增失败");
        // 两条会话都用固定远古时间戳（避免跨 UTC 午夜时今日统计抖动）：
        // g1 结束时间晚于 g2 → 最近游玩应为 g1
        block_on(game_library_add_play_session(make_session("home-g1", 1_600_002_000, 50)))
            .expect("写入会话失败");
        block_on(game_library_add_play_session(make_session("home-g2", 1_600_000_000, 30)))
            .expect("写入会话失败");

        let home = block_on(game_library_get_home_page_data()).expect("查首页数据失败");
        assert_eq!(home.total_games, 2);
        assert_eq!(home.total_play_time_sec, 80, "总时长应为全部会话求和");
        assert_eq!(home.today_play_time_sec, 0, "远古数据不应计入今日");
        assert_eq!(home.week_play_time_sec, 0, "远古数据不应计入本周");
        let last = home.last_played_game.expect("应有最近游玩游戏");
        assert_eq!(last.id, "home-g1", "最近游玩应为结束时间最晚的游戏");
    }

    // ── 游戏进度 upsert ───────────────────────────────────────────────────

    #[test]
    fn progress_upsert_round_trip() {
        let _guard = lock_api();
        init_temp_db();

        block_on(game_library_add_game(make_game("prog-game", "进度游戏")))
            .expect("新增失败");

        // 空 id → 生成
        let p1 = block_on(game_library_upsert_progress(GameProgress {
            id: String::new(),
            game_id: "prog-game".to_string(),
            chapter: "第1章".to_string(),
            route: "共通线".to_string(),
            note: "开场".to_string(),
            updated_at: 0,
        }))
        .expect("写入进度失败");
        assert!(!p1.id.trim().is_empty(), "空 id 应生成 UUID");
        assert!(p1.updated_at > 0, "updated_at 应由服务端填充");

        // 同 id 再次 upsert → 更新而非追加
        block_on(game_library_upsert_progress(GameProgress {
            id: p1.id.clone(),
            game_id: "prog-game".to_string(),
            chapter: "第3章".to_string(),
            route: "真结局线".to_string(),
            note: "关键选项".to_string(),
            updated_at: 0,
        }))
        .expect("更新进度失败");
        let list = block_on(game_library_get_progress("prog-game".to_string()))
            .expect("查进度失败");
        assert_eq!(list.len(), 1, "同 id upsert 不应产生第二行");
        assert_eq!(list[0].chapter, "第3章");
        assert_eq!(list[0].route, "真结局线");
        assert_eq!(list[0].note, "关键选项");

        // 无进度的游戏 → 空列表
        assert!(block_on(game_library_get_progress("prog-none".to_string()))
            .expect("查进度失败")
            .is_empty());
    }

    // ── 设置默认值与持久化 ────────────────────────────────────────────────

    #[test]
    fn settings_defaults_and_round_trip() {
        let _guard = lock_api();
        init_temp_db();

        // 未保存过时返回默认设置
        let defaults = block_on(game_library_get_settings()).expect("读默认设置失败");
        assert!(defaults.auto_track_play_time);
        assert_eq!(defaults.default_sort, "updatedAt_desc");
        assert!(defaults.auto_save);
        assert!(defaults.enable_desktop_launch);
        assert!(!defaults.use_open_on_macos);

        // 保存自定义设置 → 读回一致；再次保存 → 覆盖而非报错
        let custom = GameLibrarySettings {
            auto_track_play_time: false,
            default_sort: "name_asc".to_string(),
            auto_save: false,
            enable_desktop_launch: true,
            use_open_on_macos: true,
        };
        block_on(game_library_save_settings(custom.clone())).expect("保存设置失败");
        let loaded = block_on(game_library_get_settings()).expect("读设置失败");
        assert!(!loaded.auto_track_play_time);
        assert_eq!(loaded.default_sort, "name_asc");
        assert!(!loaded.auto_save);
        assert!(loaded.use_open_on_macos);

        let override_settings = GameLibrarySettings {
            default_sort: "rating_desc".to_string(),
            ..custom.clone()
        };
        block_on(game_library_save_settings(override_settings)).expect("覆盖设置失败");
        let reloaded = block_on(game_library_get_settings()).expect("读设置失败");
        assert_eq!(reloaded.default_sort, "rating_desc", "重复保存应覆盖旧值");
    }

    // ── 批量导入去重 check_paths_exist ────────────────────────────────────

    #[test]
    fn check_paths_exist_matches_case_and_trim() {
        let _guard = lock_api();
        init_temp_db();

        // tempdir 中构造混合路径：两个已录入（一存于 path、一存于 game_dir）、其余不存在
        let dir = std::env::temp_dir().join(format!("gamelib_paths_{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("创建临时目录失败");
        let known_exe = dir.join("Alpha/game.exe");
        let known_dir = dir.join("BetaDir");
        let unknown_exe = dir.join("Missing/game.exe");

        let mut g1 = make_game("path-g1", "路径游戏一");
        g1.path = known_exe.to_string_lossy().into_owned();
        g1.game_dir = known_dir.to_string_lossy().into_owned();
        block_on(game_library_add_game(g1)).expect("新增失败");

        // 1. 大小写不同也应命中（内部按 trim+lowercase 比较）
        let query_upper = known_exe.to_string_lossy().to_uppercase();
        let existing = block_on(game_library_check_paths_exist(vec![
            query_upper.clone(),
            format!("  {}  ", unknown_exe.to_string_lossy()), // 带空白的不存在路径
            "".to_string(),                                    // 空串应跳过
            "   ".to_string(),                                 // 纯空白应跳过
        ]))
        .expect("check_paths_exist 失败");
        assert_eq!(
            existing,
            vec![query_upper.clone()],
            "只应返回命中的原始输入；game_dir 也应参与匹配"
        );

        // 2. game_dir 命中：返回原始输入串（保留大小写）
        let existing2 = block_on(game_library_check_paths_exist(vec![known_dir
            .to_string_lossy()
            .into_owned()]))
        .expect("check_paths_exist 失败");
        assert_eq!(existing2.len(), 1, "game_dir 应被视为已录入");

        // 3. 混合：存在 + 不存在 + 重复
        let existing3 = block_on(game_library_check_paths_exist(vec![
            known_exe.to_string_lossy().into_owned(),
            unknown_exe.to_string_lossy().into_owned(),
            known_exe.to_string_lossy().into_owned(),
        ]))
        .expect("check_paths_exist 失败");
        assert_eq!(
            existing3,
            vec![
                known_exe.to_string_lossy().into_owned(),
                known_exe.to_string_lossy().into_owned()
            ],
            "重复输入应分别命中，未录入路径不应出现"
        );

        std::fs::remove_dir_all(&dir).ok();
    }

    // ── 未初始化时的错误路径与关闭 ────────────────────────────────────────

    #[test]
    fn queries_fail_after_close_and_reinit_recovers() {
        let _guard = lock_api();
        init_temp_db();
        assert!(game_library_is_ready());

        // 关闭全局连接后，所有经 with_conn 的查询应报「未初始化」错误
        game_library_close();
        assert!(!game_library_is_ready(), "close 后应未就绪");
        let err = block_on(game_library_get_games()).expect_err("未就绪时查询应失败");
        assert!(
            err.to_string().contains("未初始化"),
            "错误信息应提示未初始化，实际: {err}"
        );
        let add_err = block_on(game_library_add_game(make_game("x", "y")))
            .expect_err("未就绪时新增应失败");
        assert!(add_err.to_string().contains("未初始化"));

        // 重新 init 后恢复可用
        init_temp_db();
        assert!(block_on(game_library_get_games()).is_ok(), "重新初始化后应恢复");
    }

    // ── derive_game_name 纯函数边界（不依赖全局连接） ─────────────────────

    #[test]
    fn derive_game_name_covers_path_shapes() {
        // 空输入
        assert_eq!(game_library_derive_game_name(String::new()), "");
        assert_eq!(game_library_derive_game_name("   ".to_string()), "");

        // macOS .app 包（去后缀）
        assert_eq!(
            game_library_derive_game_name("/Applications/Sample Game.app".to_string()),
            "Sample Game"
        );
        // .app 大小写混合：strip_suffix 依次尝试 .app/.App
        assert_eq!(
            game_library_derive_game_name("/apps/Test.App".to_string()),
            "Test"
        );
        // .app 内含下划线（清理为空格）
        assert_eq!(
            game_library_derive_game_name("/Users/me/Games/My_Game.app".to_string()),
            "My Game"
        );
        // Windows 反斜杠的 .app 也会被归一化
        assert_eq!(
            game_library_derive_game_name("C:\\Apps\\My Game.app".to_string()),
            "My Game"
        );

        // Windows 反斜杠 exe：取父目录名
        assert_eq!(
            game_library_derive_game_name("C:\\Games\\Rance\\game.exe".to_string()),
            "Rance"
        );
        // 父目录名含版本号小数点：'.' 被清理为空格
        assert_eq!(
            game_library_derive_game_name("D:\\Publisher\\Title v1.2\\Game.exe".to_string()),
            "Title v1 2"
        );
        // 父目录名含括号/方括号：替换为空格并压缩
        assert_eq!(
            game_library_derive_game_name(
                "/games/My Game (2024) [CN]/game.exe".to_string()
            ),
            "My Game 2024 CN"
        );
        // 中文全角括号
        assert_eq!(
            game_library_derive_game_name("/games/名作（完全版）/game.exe".to_string()),
            "名作 完全版"
        );

        // 多级 unix 目录：取倒数第二段
        assert_eq!(
            game_library_derive_game_name("/data/games/sub/title/game.bin.x86_64".to_string()),
            "title"
        );

        // 单段文件名（无父目录）：降级为「文件名去可执行后缀」
        assert_eq!(game_library_derive_game_name("game.exe".to_string()), "game");
        assert_eq!(
            game_library_derive_game_name("MyGame.x86_64".to_string()),
            "MyGame"
        );
        assert_eq!(game_library_derive_game_name("start.bat".to_string()), "start");

        // 无后缀且只有一段（隐藏文件形态）：'.' 与 '_' 均被清理
        assert_eq!(
            game_library_derive_game_name("/.hidden_game".to_string()),
            "hidden game"
        );
        // 隐藏目录作为父目录：前导点被清理
        assert_eq!(
            game_library_derive_game_name("/home/u/.hidden/game.exe".to_string()),
            "hidden"
        );

        // 目录本身（无文件段）：仍按「父目录」规则，取到的是上一级
        // ——该行为反映当前实现：/games/my_rpg 的「父目录」是 games
        assert_eq!(
            game_library_derive_game_name("/games/my_rpg".to_string()),
            "games"
        );

        // 首尾空白先被 trim
        assert_eq!(
            game_library_derive_game_name("  /apps/Trim.app  ".to_string()),
            "Trim"
        );
    }

    // ── JSON 列表解析辅助函数 ─────────────────────────────────────────────

    #[test]
    fn json_list_helpers_handle_broken_input() {
        // 合法 JSON 往返
        let list = vec!["a".to_string(), "中文 b".to_string()];
        let json = to_json_str(&list);
        assert_eq!(parse_json_str_list(&json), list);
        // 损坏 JSON / 非字符串数组 → 空列表而非 panic
        assert!(parse_json_str_list("{ 坏数据 }").is_empty());
        assert!(parse_json_str_list("").is_empty());
        assert!(parse_json_str_list("[1, 2]").is_empty(), "非字符串数组按空处理");
        // 空列表序列化为 "[]"
        assert_eq!(to_json_str(&[]), "[]");
    }
}
