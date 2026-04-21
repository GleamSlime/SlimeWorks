/// 游戏库模块 API
///
/// 将 game_library 子模块能力暴露给 Flutter Rust Bridge。
use anyhow::Result;
use flutter_rust_bridge::frb;

pub use game_library::{
    Category, DayPlayTime, Game, GameProgress, GameStats, GameTimeSummary, HomePageData,
    PlaySession,
};

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

pub async fn game_library_add_game(game: Game) -> Result<Game> {
    game_library::game_library_add_game(game).await
}

pub async fn game_library_update_game(game: Game) -> Result<()> {
    game_library::game_library_update_game(game).await
}

pub async fn game_library_get_games() -> Result<Vec<Game>> {
    game_library::game_library_get_games().await
}

pub async fn game_library_get_game_by_id(game_id: String) -> Result<Option<Game>> {
    game_library::game_library_get_game_by_id(game_id).await
}

pub async fn game_library_delete_game(game_id: String) -> Result<()> {
    game_library::game_library_delete_game(game_id).await
}

pub async fn game_library_upsert_category(category: Category) -> Result<Category> {
    game_library::game_library_upsert_category(category).await
}

pub async fn game_library_get_categories() -> Result<Vec<Category>> {
    game_library::game_library_get_categories().await
}

pub async fn game_library_delete_category(category_id: String) -> Result<()> {
    game_library::game_library_delete_category(category_id).await
}

pub async fn game_library_add_game_to_category(game_id: String, category_id: String) -> Result<()> {
    game_library::game_library_add_game_to_category(game_id, category_id).await
}

pub async fn game_library_remove_game_from_category(
    game_id: String,
    category_id: String,
) -> Result<()> {
    game_library::game_library_remove_game_from_category(game_id, category_id).await
}

pub async fn game_library_get_game_categories(game_id: String) -> Result<Vec<Category>> {
    game_library::game_library_get_game_categories(game_id).await
}

pub async fn game_library_add_play_session(session: PlaySession) -> Result<()> {
    game_library::game_library_add_play_session(session).await
}

pub async fn game_library_get_play_sessions(game_id: String) -> Result<Vec<PlaySession>> {
    game_library::game_library_get_play_sessions(game_id).await
}

pub async fn game_library_upsert_progress(progress: GameProgress) -> Result<GameProgress> {
    game_library::game_library_upsert_progress(progress).await
}

pub async fn game_library_get_progress(game_id: String) -> Result<Vec<GameProgress>> {
    game_library::game_library_get_progress(game_id).await
}

pub async fn game_library_get_stats(start_ts: i64, end_ts: i64) -> Result<GameStats> {
    game_library::game_library_get_stats(start_ts, end_ts).await
}

pub async fn game_library_get_home_page_data() -> Result<HomePageData> {
    game_library::game_library_get_home_page_data().await
}

pub async fn game_library_toggle_favorite(game_id: String, favorite: bool) -> Result<()> {
    game_library::game_library_toggle_favorite(game_id, favorite).await
}
