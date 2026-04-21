use anyhow::{Context, Result};
use rusqlite::{params, Connection};

const SYSTEM_FAVORITES_ID: &str = "system:favorites";

pub fn init_db(conn: &Connection) -> Result<()> {
    conn.execute_batch(
        r#"
        CREATE TABLE IF NOT EXISTS games (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cover_path TEXT NOT NULL DEFAULT '',
            company TEXT NOT NULL DEFAULT '',
            summary TEXT NOT NULL DEFAULT '',
            rating REAL NOT NULL DEFAULT 0,
            release_date TEXT NOT NULL DEFAULT '',
            path TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'not_started',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            emoji TEXT NOT NULL DEFAULT '',
            is_system INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS game_categories (
            game_id TEXT NOT NULL,
            category_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (game_id, category_id)
        );

        CREATE TABLE IF NOT EXISTS play_sessions (
            id TEXT PRIMARY KEY,
            game_id TEXT NOT NULL,
            start_time INTEGER NOT NULL,
            end_time INTEGER NOT NULL,
            duration_sec INTEGER NOT NULL,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS game_progress (
            id TEXT PRIMARY KEY,
            game_id TEXT NOT NULL,
            chapter TEXT NOT NULL DEFAULT '',
            route TEXT NOT NULL DEFAULT '',
            note TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_play_sessions_game ON play_sessions(game_id);
        CREATE INDEX IF NOT EXISTS idx_play_sessions_start_time ON play_sessions(start_time);
        CREATE INDEX IF NOT EXISTS idx_game_categories_category ON game_categories(category_id);
        CREATE INDEX IF NOT EXISTS idx_game_progress_game ON game_progress(game_id);
        "#,
    )
    .context("初始化游戏库数据库失败")?;

    ensure_system_categories(conn)?;
    Ok(())
}

fn ensure_system_categories(conn: &Connection) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    conn.execute(
        r#"
        INSERT INTO categories (id, name, emoji, is_system, created_at, updated_at)
        VALUES (?1, ?2, ?3, 1, ?4, ?4)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            emoji = excluded.emoji,
            is_system = 1,
            updated_at = excluded.updated_at
        "#,
        params![SYSTEM_FAVORITES_ID, "最喜欢的游戏", "⭐", now],
    )
    .context("确保系统分类失败")?;
    Ok(())
}
