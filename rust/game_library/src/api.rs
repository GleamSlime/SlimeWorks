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
/// * `use_open`      — macOS 下使用 `open` 命令启动（适合 Wine/Crossover 包装）
pub async fn game_library_launch_game(
    exe_path: String,
    working_dir: String,
    use_open: bool,
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

// ─────────────────────────────────────────────────────────────────────────────
// HTTP 工具（代理检测 + 浏览器 Client 构建）
// ─────────────────────────────────────────────────────────────────────────────

static BROWSER_UA: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";
static BROWSER_ACCEPT: &str = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7";
static BROWSER_ACCEPT_LANG: &str = "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,ja;q=0.6,zh-TW;q=0.5";

/// 检测系统代理：优先读取环境变量，macOS 额外尝试 `scutil --proxy`。
fn detect_system_proxy() -> Option<String> {
    // 1. 标准环境变量
    for var in &["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy"] {
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
    let enabled = text.lines()
        .find(|l| l.contains("HTTPSEnable"))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim() == "1")
        .unwrap_or(false);
    let (host_key, port_key) = if enabled {
        ("HTTPSProxy", "HTTPSPort")
    } else {
        let http_enabled = text.lines()
            .find(|l| l.contains("HTTPEnable"))
            .and_then(|l| l.split(':').nth(1))
            .map(|v| v.trim() == "1")
            .unwrap_or(false);
        if !http_enabled { return None; }
        ("HTTPProxy", "HTTPPort")
    };

    let host = text.lines()
        .find(|l| l.contains(host_key))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())?;
    let port = text.lines()
        .find(|l| l.contains(port_key))
        .and_then(|l| l.split(':').nth(1))
        .map(|v| v.trim().to_string())
        .unwrap_or_else(|| "7890".to_string());

    if host.is_empty() { return None; }
    Some(format!("http://{}:{}", host, port))
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
    log::info!("[http] Client 已重置，下次请求将重新建立 TLS 连接");
}

/// 执行一次 GET 请求，遇到连接错误时重置 Client 并重试一次。
fn get_with_retry(url: &str) -> Result<reqwest::blocking::Response> {
    let client = get_browser_client()?;
    match client.get(url).send() {
        Ok(r) => Ok(r),
        Err(e) if e.is_connect() || e.is_timeout() => {
            log::warn!("[http] 连接失败（{}），重置 Client 后重试: {}", url, e);
            reset_browser_client();
            let client2 = get_browser_client()?;
            client2.get(url).send().context(format!("请求失败（重试后）: {}", url))
        }
        Err(e) => Err(anyhow::anyhow!(e)),
    }
}

fn build_browser_client() -> Result<Client> {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(reqwest::header::ACCEPT, BROWSER_ACCEPT.parse().unwrap());
    headers.insert(reqwest::header::ACCEPT_LANGUAGE, BROWSER_ACCEPT_LANG.parse().unwrap());

    let mut builder = Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .user_agent(BROWSER_UA)
        .default_headers(headers)
        .cookie_store(true)
        .danger_accept_invalid_certs(false)
        .redirect(reqwest::redirect::Policy::limited(10));

    if let Some(proxy_url) = detect_system_proxy() {
        log::info!("使用系统代理: {}", proxy_url);
        match reqwest::Proxy::all(&proxy_url) {
            Ok(proxy) => { builder = builder.proxy(proxy); }
            Err(e) => { log::warn!("代理配置失败，跳过: {}", e); }
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
    log::info!("[moegirl] 请求 URL: {}", url);
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
    if raw.is_empty() { return String::new(); }
    let doc = Html::parse_document(raw);
    // 按优先级尝试萌娘百科 / MediaWiki 的内容容器
    let candidates = ["#moe-body-content", "#mw-content-text", "#bodyContent", "#content"];
    let root_opt = candidates.iter().find_map(|sel| {
        Selector::parse(sel).ok().and_then(|s| doc.select(&s).next())
    });
    let Some(root) = root_opt else { return String::new(); };

    // 收集需要剔除的公告节点（class 以 xUkJeF1d7d_ 开头）
    // scraper 不支持原地修改，直接序列化并在字符串层面移除对应标签块
    // 改用：序列化原始 inner_html，然后用 HTML 解析器二次过滤
    let inner = root.inner_html();

    // 二次解析，移除公告 class 元素
    let Ok(sel_notice) = Selector::parse("[class]") else { return inner; };
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
    if result.trim().is_empty() { String::new() } else { result }
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
        "table", "thead", "tbody", "tfoot", "tr", "td", "th",
        "caption", "colgroup", "col",
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
        let boundary = after.chars().next()
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
        let end = find_paired_close(search_from, &open_lower, &open_upper, &close_lower, &close_upper);
        match end {
            Some(end_pos) => { rest = &rest[start + end_pos..]; }
            None => { break; } // 没有闭标签，截断
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
fn find_paired_close(html: &str, open_l: &str, open_u: &str, close_l: &str, close_u: &str) -> Option<usize> {
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
                if after.chars().next().map_or(true, |ch| !ch.is_alphanumeric() && ch != '-' && ch != '_') {
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
    let html = get_with_retry(&url)?.text()?;;
    let doc = Html::parse_document(&html);
    let Ok(sel) = Selector::parse("#subjects > li a") else { return Ok(String::new()); };
    Ok(doc.select(&sel).next()
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
    let html = get_with_retry(&url)?.text()?;;
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
            if lis.is_empty() { continue; }
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
            if !items.is_empty() { break; }
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
    let html = get_with_retry(&url)?.text()?;;
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
            get_browser_client()?.get(url).send().context("下载请求失败")?}
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
// 游戏元数据搜索（Steam / VNDB / Bangumi）
// ─────────────────────────────────────────────────────────────────────────────

/// 元数据搜索结果（用于 Dart 层解析）
#[derive(serde::Serialize)]
struct GameMetadata {
    name: String,
    #[serde(rename = "coverUrl")]
    cover_url: String,
    company: String,
    summary: String,
    rating: f64,
    #[serde(rename = "releaseDate")]
    release_date: String,
    source: String,
    #[serde(rename = "sourceId")]
    source_id: String,
}

/// 用游戏名在 Steam / VNDB / Bangumi 中搜索元数据。
/// 找到则返回 JSON 字符串，未找到或全部失败则返回空字符串。
pub async fn game_library_search_metadata_by_name(name: String) -> Result<String> {
    tokio::task::spawn_blocking(move || search_metadata_by_name_sync(&name)).await?
}

fn search_metadata_by_name_sync(raw_name: &str) -> Result<String> {
    let queries = build_search_candidates(raw_name);
    for query in &queries {
        if let Ok(Some(meta)) = search_steam_sync(query) {
            return Ok(serde_json::to_string(&meta).context("序列化 Steam 元数据失败")?);
        }
        if let Ok(Some(meta)) = search_vndb_sync(query) {
            return Ok(serde_json::to_string(&meta).context("序列化 VNDB 元数据失败")?);
        }
        if let Ok(Some(meta)) = search_bangumi_sync(query) {
            return Ok(serde_json::to_string(&meta).context("序列化 Bangumi 元数据失败")?);
        }
    }
    Ok(String::new())
}

/// 构建搜索候选词列表（标准化 + 变体）
fn build_search_candidates(raw_name: &str) -> Vec<String> {
    let mut set: Vec<String> = Vec::new();
    let normalized = normalize_game_name(raw_name);
    let add = |s: &str, v: &mut Vec<String>| {
        let t = s.trim().to_string();
        if !t.is_empty() && !v.contains(&t) {
            v.push(t);
        }
    };
    add(&normalized, &mut set);
    add(raw_name, &mut set);
    let with_space = normalized.replace('-', " ");
    add(&with_space, &mut set);
    let with_dash = normalized.replace(' ', "-");
    add(&with_dash, &mut set);
    // 按长度降序（更长的名字匹配精度更高）
    set.sort_by(|a, b| b.len().cmp(&a.len()));
    set
}

/// 标准化游戏名：去掉括号内容、特殊符号替换为空格
fn normalize_game_name(raw: &str) -> String {
    let v = raw.trim();
    if v.is_empty() {
        return String::new();
    }
    let mut result = String::with_capacity(v.len());
    let mut depth = 0i32;
    for ch in v.chars() {
        match ch {
            '[' | '(' | '【' | '（' => { depth += 1; }
            ']' | ')' | '】' | '）' => { if depth > 0 { depth -= 1; } }
            _ if depth > 0 => {}
            '_' | '.' | '-' => result.push(' '),
            c => result.push(c),
        }
    }
    // 压缩多余空格
    let mut out = String::with_capacity(result.len());
    let mut last_space = false;
    for ch in result.chars() {
        if ch == ' ' {
            if !last_space { out.push(' '); }
            last_space = true;
        } else {
            out.push(ch);
            last_space = false;
        }
    }
    let trimmed = out.trim().to_string();
    if trimmed.len() > 80 { trimmed[..80].trim().to_string() } else { trimmed }
}

/// 在 Steam 搜索游戏元数据
fn search_steam_sync(query: &str) -> Result<Option<GameMetadata>> {
    let client = get_browser_client()?;
    let search_url = format!(
        "https://store.steampowered.com/api/storesearch/?term={}&l=schinese&cc=cn",
        utf8_percent_encode(query, WIKI_PATH)
    );
    let search_resp = client
        .get(&search_url)
        .header("Referer", "https://store.steampowered.com/")
        .header("Accept", "application/json")
        .send()
        .context("Steam 搜索请求失败")?;
    if !search_resp.status().is_success() {
        return Ok(None);
    }
    let search_text = search_resp.text().context("读取 Steam 搜索响应失败")?;
    let search_root: serde_json::Value =
        serde_json::from_str(&search_text).context("解析 Steam 搜索 JSON 失败")?;
    let items = match search_root["items"].as_array() {
        Some(a) if !a.is_empty() => a,
        _ => return Ok(None),
    };
    let first = &items[0];
    let app_id = match first["id"].as_u64() {
        Some(id) => id.to_string(),
        None => return Ok(None),
    };

    let detail_url = format!(
        "https://store.steampowered.com/api/appdetails?appids={}&l=schinese&cc=cn",
        app_id
    );
    let detail_resp = client
        .get(&detail_url)
        .header("Referer", format!("https://store.steampowered.com/app/{}/", app_id))
        .header("Accept", "application/json")
        .send()
        .context("Steam 详情请求失败")?;
    if !detail_resp.status().is_success() {
        return Ok(None);
    }
    let detail_text = detail_resp.text().context("读取 Steam 详情响应失败")?;
    let detail_root: serde_json::Value =
        serde_json::from_str(&detail_text).context("解析 Steam 详情 JSON 失败")?;
    let app_root = &detail_root[&app_id];
    if app_root["success"].as_bool() != Some(true) {
        return Ok(None);
    }
    let data = &app_root["data"];
    let title = data["name"].as_str().unwrap_or("").trim().to_string();
    if title.is_empty() {
        return Ok(None);
    }
    let company = data["developers"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|e| e.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let mut rating = data["metacritic"]["score"].as_f64().unwrap_or(0.0);
    if rating > 0.0 { rating /= 10.0; }
    let cover = if data["header_image"].as_str().unwrap_or("").is_empty() {
        first["tiny_image"].as_str().unwrap_or("").to_string()
    } else {
        data["header_image"].as_str().unwrap_or("").to_string()
    };
    Ok(Some(GameMetadata {
        name: title,
        cover_url: cover,
        company,
        summary: data["short_description"].as_str().unwrap_or("").to_string(),
        rating,
        release_date: data["release_date"]["date"].as_str().unwrap_or("").to_string(),
        source: "steam".to_string(),
        source_id: app_id,
    }))
}

/// 在 VNDB 搜索视觉小说元数据
fn search_vndb_sync(query: &str) -> Result<Option<GameMetadata>> {
    let client = get_browser_client()?;
    let body = serde_json::json!({
        "filters": ["search", "=", query],
        "fields": "id,title,image.url,description,rating,released,developers.name,titles.lang,titles.title,titles.latin,titles.main,titles.official"
    });
    let body_str = serde_json::to_string(&body).context("序列化 VNDB 请求体失败")?;
    let resp = client
        .post("https://api.vndb.org/kana/vn")
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .body(body_str)
        .send()
        .context("VNDB 请求失败")?;
    if !resp.status().is_success() {
        return Ok(None);
    }
    let text = resp.text().context("读取 VNDB 响应失败")?;
    let root: serde_json::Value = serde_json::from_str(&text).context("解析 VNDB JSON 失败")?;
    let results = match root["results"].as_array() {
        Some(a) if !a.is_empty() => a,
        _ => return Ok(None),
    };
    let first = &results[0];
    let title = pick_vndb_title(first);
    if title.is_empty() {
        return Ok(None);
    }
    let company = first["developers"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|e| e["name"].as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .unwrap_or_default();
    let rating = first["rating"].as_f64().unwrap_or(0.0).min(100.0) / 10.0;
    Ok(Some(GameMetadata {
        name: title,
        cover_url: first["image"]["url"].as_str().unwrap_or("").to_string(),
        company,
        summary: first["description"].as_str().unwrap_or("").to_string(),
        rating,
        release_date: first["released"].as_str().unwrap_or("").to_string(),
        source: "vndb".to_string(),
        source_id: first["id"].as_str().unwrap_or("").to_string(),
    }))
}

/// 从 VNDB 条目的 titles 列表中选取最优标题
fn pick_vndb_title(result: &serde_json::Value) -> String {
    if let Some(titles) = result["titles"].as_array() {
        let mut sorted = titles.to_vec();
        sorted.sort_by(|a, b| {
            let score_a = if a["main"].as_bool().unwrap_or(false) { 2 } else { 0 }
                + if a["official"].as_bool().unwrap_or(false) { 1 } else { 0 };
            let score_b = if b["main"].as_bool().unwrap_or(false) { 2 } else { 0 }
                + if b["official"].as_bool().unwrap_or(false) { 1 } else { 0 };
            score_b.cmp(&score_a)
        });
        for t in &sorted {
            if let Some(s) = t["title"].as_str() {
                if !s.is_empty() { return s.to_string(); }
            }
            if let Some(s) = t["latin"].as_str() {
                if !s.is_empty() { return s.to_string(); }
            }
        }
    }
    result["title"].as_str().unwrap_or("").to_string()
}

/// 在 Bangumi 搜索游戏元数据
fn search_bangumi_sync(query: &str) -> Result<Option<GameMetadata>> {
    let client = get_browser_client()?;
    let encoded = utf8_percent_encode(query, WIKI_PATH).to_string();
    let url = format!(
        "https://api.bgm.tv/search/subject/{}?type=4&responseGroup=medium",
        encoded
    );
    let resp = client
        .get(&url)
        .header("Accept", "application/json")
        .send()
        .context("Bangumi 请求失败")?;
    if !resp.status().is_success() {
        return Ok(None);
    }
    let text = resp.text().context("读取 Bangumi 响应失败")?;
    let root: serde_json::Value =
        serde_json::from_str(&text).context("解析 Bangumi JSON 失败")?;
    let list = match root["list"].as_array() {
        Some(a) if !a.is_empty() => a,
        _ => return Ok(None),
    };
    let first = &list[0];
    let name_cn = first["name_cn"].as_str().unwrap_or("").trim().to_string();
    let name = if name_cn.is_empty() {
        first["name"].as_str().unwrap_or("").trim().to_string()
    } else {
        name_cn
    };
    if name.is_empty() {
        return Ok(None);
    }
    let cover = {
        let large = first["images"]["large"].as_str().unwrap_or("");
        if large.is_empty() {
            first["images"]["common"].as_str().unwrap_or("").to_string()
        } else {
            large.to_string()
        }
    };
    let company = extract_bangumi_company(&first["infobox"]);
    let rating = first["score"].as_f64().unwrap_or(0.0).min(10.0);
    Ok(Some(GameMetadata {
        name,
        cover_url: cover,
        company,
        summary: first["summary"].as_str().unwrap_or("").to_string(),
        rating,
        release_date: first["air_date"].as_str().unwrap_or("").to_string(),
        source: "bangumi".to_string(),
        source_id: first["id"].to_string(),
    }))
}

/// 从 Bangumi infobox 提取制作公司名称
fn extract_bangumi_company(infobox: &serde_json::Value) -> String {
    if let Some(arr) = infobox.as_array() {
        for item in arr {
            let key = item["key"].as_str().unwrap_or("").to_lowercase();
            if key.contains("开发") || key.contains("制作") || key.contains("厂商") || key.contains("company") {
                if let Some(s) = item["value"].as_str() {
                    let t = s.trim().to_string();
                    if !t.is_empty() { return t; }
                }
                if let Some(arr) = item["value"].as_array() {
                    let joined: Vec<&str> = arr.iter()
                        .filter_map(|e| e["v"].as_str())
                        .filter(|s| !s.is_empty())
                        .collect();
                    if !joined.is_empty() { return joined.join(", "); }
                }
            }
        }
    }
    String::new()
}

// ─────────────────────────────────────────────────────────────────────────────
// 进程监控（PID 检测 & 目录进程扫描）
// ─────────────────────────────────────────────────────────────────────────────

/// 检测指定 PID 的进程是否仍在运行
pub async fn game_library_is_pid_alive(pid: i64) -> Result<bool> {
    tokio::task::spawn_blocking(move || is_pid_alive_sync(pid)).await?
}

fn is_pid_alive_sync(pid: i64) -> Result<bool> {
    #[cfg(target_os = "windows")]
    {
        let output = std::process::Command::new("tasklist")
            .args(&["/FI", &format!("PID eq {}", pid), "/NH", "/FO", "CSV"])
            .output()
            .context("执行 tasklist 失败")?;
        Ok(String::from_utf8_lossy(&output.stdout).contains(&format!("\"{}\"", pid)))
    }
    #[cfg(not(target_os = "windows"))]
    {
        // Unix/macOS: kill -0 不发送信号，只检查进程是否存在
        let output = std::process::Command::new("kill")
            .args(&["-0", &pid.to_string()])
            .output()
            .context("执行 kill -0 失败")?;
        Ok(output.status.success())
    }
}

/// 查找运行中且路径位于指定目录下的进程 PID 列表（仅 Windows；其他平台返回空列表）
pub async fn game_library_find_processes_in_dir(game_dir: String) -> Result<Vec<i64>> {
    tokio::task::spawn_blocking(move || find_processes_in_dir_sync(&game_dir)).await?
}

fn find_processes_in_dir_sync(game_dir: &str) -> Result<Vec<i64>> {
    #[cfg(target_os = "windows")]
    {
        let normalized = game_dir.replace('/', "\\");
        let script = format!(
            r#"Get-Process | Where-Object {{ $_.Path -and $_.Path.StartsWith("{}") }} | Select-Object -ExpandProperty Id | Out-String"#,
            normalized
        );
        let output = std::process::Command::new("powershell")
            .args(&["-NoProfile", "-NonInteractive", "-Command", &script])
            .output()
            .context("执行 PowerShell 失败")?;
        if !output.status.success() {
            return Ok(vec![]);
        }
        let pids: Vec<i64> = String::from_utf8_lossy(&output.stdout)
            .split(|c: char| c == '\r' || c == '\n')
            .filter_map(|line| line.trim().parse::<i64>().ok())
            .filter(|&id| id > 0)
            .collect();
        Ok(pids)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = game_dir;
        Ok(vec![])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 存档目录检测
// ─────────────────────────────────────────────────────────────────────────────

/// 启发式检测游戏存档目录：扫描游戏根目录下的常见存档文件夹名。
/// 返回检测到的存档目录路径，未找到则返回空字符串。
#[frb(sync)]
pub fn game_library_detect_save_folder(game_dir: String) -> String {
    let dir = game_dir.trim().to_string();
    if dir.is_empty() { return String::new(); }

    let base = std::path::Path::new(&dir);
    if !base.exists() { return String::new(); }

    // 精确名称候选
    let candidates = [
        "save", "saves", "savegames", "savedata",
        "Save", "Saves", "Saved Games", "UserData", "userdata",
    ];
    for name in &candidates {
        let candidate = base.join(name);
        if candidate.is_dir() {
            return candidate.to_string_lossy().into_owned();
        }
    }

    // 启发式：遍历子目录，名字含 save / userdata / saves
    if let Ok(entries) = std::fs::read_dir(base) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                let lower = entry.file_name().to_string_lossy().to_lowercase();
                if lower.contains("save") || lower.contains("userdata") || lower.contains("saves") {
                    return p.to_string_lossy().into_owned();
                }
            }
        }
    }

    String::new()
}
