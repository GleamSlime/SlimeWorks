use anyhow::{Context, Result};
use rusqlite::{params, Connection};

const SYSTEM_FAVORITES_ID: &str = "system:favorites";

pub fn init_db(conn: &Connection) -> Result<()> {
    // WAL：默认 journal_mode=delete 下任何写操作都会阻塞读，且每次提交都要
    // 创建/重命名日志文件。游戏库同时存在「进程追踪持续写时长」和「界面频繁读」，
    // 开 WAL + synchronous=NORMAL 可显著减少互相阻塞。
    // 某些网络文件系统不支持 WAL，失败时静默退回默认模式即可。
    let _ = conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;");

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
            updated_at INTEGER NOT NULL,
            tags TEXT NOT NULL DEFAULT '[]',
            exe_paths TEXT NOT NULL DEFAULT '[]',
            game_dir TEXT NOT NULL DEFAULT ''
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

        CREATE TABLE IF NOT EXISTS game_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_play_sessions_game ON play_sessions(game_id);
        CREATE INDEX IF NOT EXISTS idx_play_sessions_start_time ON play_sessions(start_time);
        CREATE INDEX IF NOT EXISTS idx_game_categories_category ON game_categories(category_id);
        CREATE INDEX IF NOT EXISTS idx_game_progress_game ON game_progress(game_id);
        "#,
    )
    .context("初始化游戏库数据库失败")?;

    // 为旧数据库做列迁移（新增字段）
    migrate_games_table(conn)?;
    ensure_system_categories(conn)?;
    Ok(())
}

/// 为已有 games 表添加缺失的新列（兼容旧数据库）
fn migrate_games_table(conn: &Connection) -> Result<()> {
    let migrations = [
        "ALTER TABLE games ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE games ADD COLUMN exe_paths TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE games ADD COLUMN game_dir TEXT NOT NULL DEFAULT ''",
    ];
    for sql in &migrations {
        // 列已存在时 SQLite 会报错，忽略该错误即可
        let _ = conn.execute(sql, []);
    }
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

// ─────────────────────────────────────────────────────────────────────────────
// 单元测试：init_db 建表/索引、系统分类、幂等、旧库迁移
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// 收集库中全部对象（表+索引）名称，便于断言
    fn all_object_names(conn: &Connection) -> Vec<String> {
        let mut stmt = conn
            .prepare("SELECT name FROM sqlite_master WHERE type IN ('table', 'index')")
            .expect("查询 sqlite_master 失败");
        let rows = stmt
            .query_map([], |row| row.get::<_, String>(0))
            .expect("读取 sqlite_master 失败");
        rows.map(|r| r.expect("读取对象名失败"))
            .collect()
    }

    /// 读取 categories 表中的一行分类记录（name, emoji, is_system）
    fn fetch_category(conn: &Connection, id: &str) -> Option<(String, String, i64)> {
        conn.query_row(
            "SELECT name, emoji, is_system FROM categories WHERE id = ?1",
            params![id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .ok()
    }

    // ── 全部表与索引建立 ──────────────────────────────────────────────────

    #[test]
    fn init_db_creates_all_tables_and_indexes() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");
        let names = all_object_names(&conn);
        // 6 张业务表
        for expected in [
            "games",
            "categories",
            "game_categories",
            "play_sessions",
            "game_progress",
            "game_settings",
        ] {
            assert!(
                names.iter().any(|n| n == expected),
                "缺少表 {expected}，实际对象: {names:?}"
            );
        }
        // 4 个索引
        for idx in [
            "idx_play_sessions_game",
            "idx_play_sessions_start_time",
            "idx_game_categories_category",
            "idx_game_progress_game",
        ] {
            assert!(
                names.iter().any(|n| n == idx),
                "缺少索引 {idx}，实际对象: {names:?}"
            );
        }
    }

    // ── 系统分类（收藏）初始化 ────────────────────────────────────────────

    #[test]
    fn init_db_seeds_system_favorites_category() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");
        let row = fetch_category(&conn, SYSTEM_FAVORITES_ID);
        assert!(row.is_some(), "初始化后应存在 system:favorites 分类");
        let (name, emoji, is_system) = row.expect("上面的断言已保证存在");
        assert_eq!(name, "最喜欢的游戏");
        assert_eq!(emoji, "⭐");
        assert_eq!(is_system, 1, "系统分类 is_system 必须为 1");
        // 系统分类应有且仅有一条
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM categories WHERE id = ?1",
                params![SYSTEM_FAVORITES_ID],
                |row| row.get(0),
            )
            .expect("统计系统分类失败");
        assert_eq!(count, 1);
    }

    // ── 幂等性 ────────────────────────────────────────────────────────────

    #[test]
    fn init_db_is_idempotent() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        // 连续多次调用不应报错（CREATE IF NOT EXISTS + INSERT ON CONFLICT）
        init_db(&conn).expect("第一次初始化失败");
        init_db(&conn).expect("第二次初始化失败");
        init_db(&conn).expect("第三次初始化失败");

        // 重复初始化不应重置或删除已有数据
        conn.execute(
            "INSERT INTO games (id, name, created_at, updated_at) VALUES ('g1', '游戏一', 100, 100)",
            [],
        )
        .expect("插入测试游戏失败");
        init_db(&conn).expect("插入数据后再次初始化失败");
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM games WHERE id = 'g1'",
                [],
                |row| row.get(0),
            )
            .expect("统计游戏失败");
        assert_eq!(count, 1, "重复 init_db 不应影响已有数据");

        // 系统分类也不应被重复插入
        let sys_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM categories", [], |row| row.get(0))
            .expect("统计分类失败");
        assert_eq!(
            sys_count, 1,
            "重复 init_db 后 categories 表应只有一条系统分类"
        );
    }

    // ── 旧库迁移路径 ──────────────────────────────────────────────────────

    #[test]
    fn init_db_migrates_legacy_games_table() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        // 模拟旧版库：手工创建缺少 tags / exe_paths / game_dir 三列的旧 games 表
        conn.execute_batch(
            r#"
            CREATE TABLE games (
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
            INSERT INTO games (id, name, created_at, updated_at) VALUES ('old1', '旧数据', 1, 1);
            "#,
        )
        .expect("构造旧版 games 表失败");

        // 旧表上执行 init_db：应触发 ALTER TABLE 补列且不报错
        init_db(&conn).expect("旧库迁移初始化失败");

        let cols: Vec<String> = {
            let mut stmt = conn.prepare("PRAGMA table_info(games)").expect("PRAGMA 失败");
            stmt.query_map([], |row| row.get::<_, String>(1))
                .expect("读取列信息失败")
                .map(|r| r.expect("读取列名失败"))
                .collect()
        };
        for new_col in ["tags", "exe_paths", "game_dir"] {
            assert!(
                cols.iter().any(|c| c == new_col),
                "迁移后应新增列 {new_col}，实际列: {cols:?}"
            );
        }

        // 旧数据应保留，新列自动获得默认值
        let (tags, exe_paths, game_dir): (String, String, String) = conn
            .query_row(
                "SELECT tags, exe_paths, game_dir FROM games WHERE id = 'old1'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("读取旧数据新列失败");
        assert_eq!(tags, "[]", "旧行的 tags 应为默认空 JSON 数组");
        assert_eq!(exe_paths, "[]", "旧行的 exe_paths 应为默认空 JSON 数组");
        assert_eq!(game_dir, "", "旧行的 game_dir 应为默认空字符串");
    }

    #[test]
    fn init_db_tolerates_legacy_table_already_having_new_columns() {
        // 全新库上重复迁移（列已存在，ALTER 报"duplicate column"应被静默忽略）
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化失败");
        init_db(&conn).expect("在全新库上重复初始化失败");

        // 模拟列顺序不同但三列齐全的历史版本，迁移仍应成功
        let conn2 = Connection::open_in_memory().expect("打开内存库失败");
        conn2
            .execute_batch(
                r#"
                CREATE TABLE games (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    tags TEXT NOT NULL DEFAULT '[]',
                    exe_paths TEXT NOT NULL DEFAULT '[]',
                    game_dir TEXT NOT NULL DEFAULT '',
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
                "#,
            )
            .expect("构造三列齐全的历史表失败");
        init_db(&conn2).expect("三列齐全的历史表迁移失败");
    }

    // ── 系统分类自愈（被误删/误改后恢复） ─────────────────────────────────

    #[test]
    fn init_db_restores_system_category_after_manual_damage() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");

        // 模拟用户误操作系统分类：改名并取消系统标记
        conn.execute(
            "UPDATE categories SET name = '被改名', is_system = 0 WHERE id = ?1",
            params![SYSTEM_FAVORITES_ID],
        )
        .expect("模拟破坏系统分类失败");

        // 重新初始化应把系统分类恢复回来（INSERT ON CONFLICT DO UPDATE）
        init_db(&conn).expect("恢复性初始化失败");
        let (name, _, is_system) = fetch_category(&conn, SYSTEM_FAVORITES_ID).expect("系统分类应存在");
        assert_eq!(name, "最喜欢的游戏", "被改名的系统分类应在重新初始化后恢复");
        assert_eq!(is_system, 1, "被取消标记的系统分类应恢复为 1");

        // 模拟彻底删除系统分类后也应重建
        conn.execute(
            "DELETE FROM categories WHERE id = ?1",
            params![SYSTEM_FAVORITES_ID],
        )
        .expect("删除系统分类失败");
        init_db(&conn).expect("重建系统分类失败");
        assert!(
            fetch_category(&conn, SYSTEM_FAVORITES_ID).is_some(),
            "系统分类应被重建"
        );
    }

    // ── 表结构约束 ────────────────────────────────────────────────────────

    #[test]
    fn games_table_enforces_required_columns() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");

        // name 为 NOT NULL，缺失应报错
        let missing_name = conn.execute(
            "INSERT INTO games (id, created_at, updated_at) VALUES ('g1', 1, 1)",
            [],
        );
        assert!(missing_name.is_err(), "name NOT NULL 约束应生效");

        // 正常插入：可选列应取默认值
        conn.execute(
            "INSERT INTO games (id, name, created_at, updated_at) VALUES ('g2', '默认值测试', 1, 1)",
            [],
        )
        .expect("最小列插入 games 失败");
        let (status, cover_path, rating, tags): (String, String, f64, String) = conn
            .query_row(
                "SELECT status, cover_path, rating, tags FROM games WHERE id = 'g2'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("读取默认值失败");
        assert_eq!(status, "not_started");
        assert_eq!(cover_path, "");
        assert_eq!(rating, 0.0);
        assert_eq!(tags, "[]");

        // 主键唯一：重复 id 应报错
        let duplicated = conn.execute(
            "INSERT INTO games (id, name, created_at, updated_at) VALUES ('g2', '重复', 1, 1)",
            [],
        );
        assert!(duplicated.is_err(), "games.id 主键唯一约束应生效");
    }

    #[test]
    fn game_categories_table_enforces_composite_primary_key() {
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");
        conn.execute(
            "INSERT INTO game_categories (game_id, category_id, created_at) VALUES ('g1', 'c1', 1)",
            [],
        )
        .expect("插入游戏分类关联失败");
        // (game_id, category_id) 复合主键：重复插入应报错
        let duplicated = conn.execute(
            "INSERT INTO game_categories (game_id, category_id, created_at) VALUES ('g1', 'c1', 2)",
            [],
        );
        assert!(duplicated.is_err(), "复合主键唯一约束应生效");
        // 只重复 game_id 不冲突
        conn.execute(
            "INSERT INTO game_categories (game_id, category_id, created_at) VALUES ('g1', 'c2', 1)",
            [],
        )
        .expect("同游戏不同分类关联应允许插入");
    }

    #[test]
    fn pragma_wal_fallback_keeps_db_usable() {
        // init_db 内部尝试开启 WAL：内存库不支持 WAL 时会静默退回默认模式，
        // 本用例保证退回路径下库依然可读写
        let conn = Connection::open_in_memory().expect("打开内存库失败");
        init_db(&conn).expect("初始化数据库失败");
        let mode: String = conn
            .query_row("PRAGMA journal_mode", [], |row| row.get(0))
            .expect("读取 journal_mode 失败");
        // 内存库通常是 "memory"，文件库是 "wal"，两者都属合法结果
        assert!(
            ["memory", "wal", "delete"]
                .iter()
                .any(|m| mode.eq_ignore_ascii_case(m)),
            "journal_mode 应为合法值，实际: {mode}"
        );
        conn.execute(
            "INSERT INTO game_settings (key, value) VALUES ('k', 'v')",
            [],
        )
        .expect("初始化后写入应正常");
    }
}
