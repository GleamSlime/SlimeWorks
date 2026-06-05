use flutter_rust_bridge::frb;

// ── FFI 数据类型（与内部类型对应，使用 i64 时间戳） ──────────────────────────

#[derive(Debug, Clone)]
pub enum PlayMode {
    Sequential,
    Loop,
    SingleLoop,
    Shuffle,
}

#[derive(Debug, Clone)]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub item_count: usize,
    pub created_at: i64,
    pub updated_at: i64,
    pub is_default: bool,
}

#[derive(Debug, Clone)]
pub struct MusicItem {
    pub id: String,
    pub playlist_id: String,
    pub title: String,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub file_path: String,
    pub duration_ms: Option<u64>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<u32>,
    pub genre: Option<String>,
    pub cover_path: Option<String>,
    pub file_size: u64,
    pub modified_at: i64,
    pub order: i32,
    pub is_favorite: bool,
}

#[derive(Debug, Clone)]
pub struct CueTrackInfo {
    pub title: String,
    pub performer: Option<String>,
    pub start_ms: u64,
    pub end_ms: Option<u64>,
    pub track_number: u32,
}

#[derive(Debug, Clone)]
pub struct CueSheetInfo {
    pub title: Option<String>,
    pub performer: Option<String>,
    pub audio_file: String,
    pub tracks: Vec<CueTrackInfo>,
}

#[derive(Debug, Clone)]
pub struct PlayRecordInfo {
    pub id: String,
    pub music_id: String,
    pub played_at: i64,
    pub play_count: u32,
}

#[derive(Debug, Clone)]
pub struct EqualizerPresetInfo {
    pub id: String,
    pub name: String,
    pub bands: Vec<f32>,
    pub is_builtin: bool,
}

// ── 类型转换 ──────────────────────────────────────────────────────────────────

fn convert_playlist(p: music_player::Playlist) -> Playlist {
    Playlist {
        id: p.id,
        name: p.name,
        cover_path: p.cover_path,
        item_count: p.item_count,
        created_at: p.created_at.timestamp(),
        updated_at: p.updated_at.timestamp(),
        is_default: p.is_default,
    }
}

fn convert_item(i: music_player::MusicItem) -> MusicItem {
    MusicItem {
        id: i.id,
        playlist_id: i.playlist_id,
        title: i.title,
        artist: i.artist,
        album: i.album,
        file_path: i.file_path,
        duration_ms: i.duration_ms,
        track_number: i.track_number,
        disc_number: i.disc_number,
        year: i.year,
        genre: i.genre,
        cover_path: i.cover_path,
        file_size: i.file_size,
        modified_at: i.modified_at.timestamp(),
        order: i.order,
        is_favorite: i.is_favorite,
    }
}

fn convert_record(r: music_player::PlayRecord) -> PlayRecordInfo {
    PlayRecordInfo {
        id: r.id,
        music_id: r.music_id,
        played_at: r.played_at.timestamp(),
        play_count: r.play_count,
    }
}

fn convert_eq_preset(p: music_player::EqualizerPreset) -> EqualizerPresetInfo {
    EqualizerPresetInfo {
        id: p.id,
        name: p.name,
        bands: p.bands,
        is_builtin: p.is_builtin,
    }
}

fn convert_cue_sheet(s: music_player::CueSheet) -> CueSheetInfo {
    CueSheetInfo {
        title: s.title,
        performer: s.performer,
        audio_file: s.audio_file,
        tracks: s
            .tracks
            .into_iter()
            .map(|t| CueTrackInfo {
                title: t.title,
                performer: t.performer,
                start_ms: t.start_ms,
                end_ms: t.end_ms,
                track_number: t.track_number,
            })
            .collect(),
    }
}

// ── FFI API ───────────────────────────────────────────────────────────────────

/// 初始化音乐播放器数据库
#[frb(sync)]
pub fn music_initialize_db() -> anyhow::Result<()> {
    music_player::initialize_db().map_err(|e| anyhow::anyhow!(e))
}

/// 获取所有播放列表
#[frb(sync)]
pub fn get_all_playlists() -> anyhow::Result<Vec<Playlist>> {
    music_player::get_all_playlists()
        .map(|ps| ps.into_iter().map(convert_playlist).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 创建播放列表
#[frb(sync)]
pub fn create_playlist(name: String) -> anyhow::Result<Playlist> {
    music_player::create_playlist(name)
        .map(convert_playlist)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 确保默认播放列表存在
#[frb(sync)]
pub fn ensure_default_playlist() -> anyhow::Result<Playlist> {
    music_player::ensure_default_playlist()
        .map(convert_playlist)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 重命名播放列表
#[frb(sync)]
pub fn rename_playlist(playlist_id: String, name: String) -> anyhow::Result<bool> {
    music_player::rename_playlist(playlist_id, name).map_err(|e| anyhow::anyhow!(e))
}

/// 删除播放列表
#[frb(sync)]
pub fn delete_playlist(playlist_id: String) -> anyhow::Result<bool> {
    music_player::delete_playlist(playlist_id).map_err(|e| anyhow::anyhow!(e))
}

/// 获取播放列表内的音乐条目
#[frb(sync)]
pub fn get_playlist_items(playlist_id: String) -> anyhow::Result<Vec<MusicItem>> {
    music_player::get_playlist_items(playlist_id)
        .map(|items| items.into_iter().map(convert_item).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 获取所有音乐条目
#[frb(sync)]
pub fn get_all_music_items() -> anyhow::Result<Vec<MusicItem>> {
    music_player::get_all_music_items()
        .map(|items| items.into_iter().map(convert_item).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 导入音乐文件夹到播放列表
pub fn import_music_folder(
    playlist_id: String,
    folder_path: String,
) -> anyhow::Result<Vec<MusicItem>> {
    music_player::import_music_folder(playlist_id, folder_path)
        .map(|items| items.into_iter().map(convert_item).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 导入单个音乐文件
#[frb(sync)]
pub fn import_music_file(playlist_id: String, file_path: String) -> anyhow::Result<MusicItem> {
    music_player::import_music_file(playlist_id, file_path)
        .map(convert_item)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 批量导入音乐文件路径
pub fn import_music_paths(
    playlist_id: String,
    paths: Vec<String>,
) -> anyhow::Result<Vec<MusicItem>> {
    music_player::import_music_paths(playlist_id, paths)
        .map(|items| items.into_iter().map(convert_item).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 删除音乐条目
#[frb(sync)]
pub fn delete_music_item(item_id: String) -> anyhow::Result<bool> {
    music_player::delete_music_item(item_id).map_err(|e| anyhow::anyhow!(e))
}

/// 清空播放列表内所有音乐
#[frb(sync)]
pub fn clear_playlist_items(playlist_id: String) -> anyhow::Result<u32> {
    music_player::clear_playlist_items(playlist_id).map_err(|e| anyhow::anyhow!(e))
}

/// 更新音乐条目信息
#[frb(sync)]
pub fn update_music_item(
    item_id: String,
    title: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    is_favorite: Option<bool>,
) -> anyhow::Result<bool> {
    music_player::update_music_item(item_id, title, artist, album, is_favorite)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 保存播放列表排序
#[frb(sync)]
pub fn save_playlist_order(playlist_id: String, item_ids: Vec<String>) -> anyhow::Result<()> {
    music_player::save_playlist_order(playlist_id, item_ids).map_err(|e| anyhow::anyhow!(e))
}

/// 解析 CUE 文件
#[frb(sync)]
pub fn parse_cue_file(cue_path: String) -> anyhow::Result<CueSheetInfo> {
    music_player::parse_cue(cue_path)
        .map(convert_cue_sheet)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 获取最近播放记录
#[frb(sync)]
pub fn get_recent_played(limit: u32) -> anyhow::Result<Vec<PlayRecordInfo>> {
    music_player::get_recent_played(limit)
        .map(|records| records.into_iter().map(convert_record).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 记录播放
#[frb(sync)]
pub fn record_play(music_id: String) -> anyhow::Result<PlayRecordInfo> {
    music_player::record_play(music_id)
        .map(convert_record)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 获取收藏的音乐
#[frb(sync)]
pub fn get_favorite_items() -> anyhow::Result<Vec<MusicItem>> {
    music_player::get_favorite_items()
        .map(|items| items.into_iter().map(convert_item).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 切换收藏状态
#[frb(sync)]
pub fn toggle_favorite(item_id: String) -> anyhow::Result<bool> {
    music_player::toggle_favorite(item_id).map_err(|e| anyhow::anyhow!(e))
}

/// 获取均衡器预设
#[frb(sync)]
pub fn get_eq_presets() -> anyhow::Result<Vec<EqualizerPresetInfo>> {
    music_player::get_eq_presets()
        .map(|presets| presets.into_iter().map(convert_eq_preset).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 保存均衡器预设
#[frb(sync)]
pub fn save_eq_preset(name: String, bands: Vec<f32>) -> anyhow::Result<EqualizerPresetInfo> {
    music_player::save_eq_preset(name, bands)
        .map(convert_eq_preset)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 删除均衡器预设
#[frb(sync)]
pub fn delete_eq_preset(preset_id: String) -> anyhow::Result<bool> {
    music_player::delete_eq_preset(preset_id).map_err(|e| anyhow::anyhow!(e))
}

/// 生成音乐封面缩略图
#[frb(sync)]
pub fn ensure_music_cover_thumbnail(file_path: String, width: u32) -> Option<String> {
    music_player::ensure_music_cover_thumbnail(file_path, width)
}

/// 批量提取封面（后台调用，不阻塞导入流程）
pub async fn batch_extract_covers(playlist_id: String) -> anyhow::Result<usize> {
    music_player::batch_extract_covers(playlist_id).map_err(|e| anyhow::anyhow!(e))
}
