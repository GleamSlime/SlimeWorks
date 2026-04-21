use std::path::PathBuf;

use anyhow::{Context, Result};
use chrono::Datelike;
use flutter_rust_bridge::frb;
use lazy_static::lazy_static;
use parking_lot::Mutex;
use rusqlite::{params, Connection};
use uuid::Uuid;

use crate::db::init_db;
use crate::types::{
    Category, DayPlayTime, Game, GameProgress, GameStats, GameTimeSummary, HomePageData,
    PlaySession,
};

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
        conn.execute(
            r#"
            INSERT INTO games (id, name, cover_path, company, summary, rating, release_date, path, status, created_at, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
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
                game.updated_at
            ],
        )
        .context("新增游戏失败")?;
        Ok(game)
    })
}

pub async fn game_library_update_game(game: Game) -> Result<()> {
    with_conn(|conn| {
        let now = now_ts();
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
                updated_at = ?10
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
                    ), 0) AS total_play_time_sec
                FROM games g
                ORDER BY g.updated_at DESC
                "#,
            )
            .context("准备查询游戏列表失败")?;

        let rows = stmt
            .query_map([], |row| {
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
                    ), 0) AS total_play_time_sec
                FROM games g
                WHERE g.id = ?1
                LIMIT 1
                "#,
            )
            .context("准备查询游戏详情失败")?;

        let mut rows = stmt.query(params![game_id]).context("查询游戏详情失败")?;
        if let Some(row) = rows.next().context("读取游戏详情失败")? {
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
