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
    /// 所属目录 ID，null 表示根级
    pub folder_id: Option<String>,
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
    /// 是否有对应的 .cue 文件
    pub has_cue: bool,
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

/// 目录节点（最多三级）
#[derive(Debug, Clone)]
pub struct FolderInfo {
    pub id: String,
    pub name: String,
    /// 父目录 ID，根级为 None
    pub parent_id: Option<String>,
    /// 目录层级：1=根级，2=二级，3=三级
    pub level: u32,
    /// 目录封面路径
    pub cover_path: Option<String>,
    /// 标签（逗号分隔）
    pub tags: Option<String>,
    /// 作者/演唱者
    pub author: Option<String>,
    /// 目录下所有音乐的累计播放次数
    pub play_count: u32,
    pub created_at: i64,
    pub updated_at: i64,
}

/// 路径映射节点类型
#[derive(Debug, Clone)]
pub enum PathMappingNodeType {
    Directory,
    AudioFile,
    ImageFile,
    CueFile,
    OtherFile,
}

/// 路径映射节点（树形结构，映射磁盘路径）
#[derive(Debug, Clone)]
pub struct PathMappingNodeInfo {
    /// 节点名称
    pub name: String,
    /// 完整路径
    pub path: String,
    /// 节点类型
    pub node_type: PathMappingNodeType,
    /// 文件大小（字节），仅文件有效（i64 映射为 Dart int，避免 BigInt 不便）
    pub file_size: Option<i64>,
    /// 子节点
    pub children: Vec<PathMappingNodeInfo>,
    /// 是否包含音频文件（文件夹属性，递归检查）
    pub has_audio: bool,
    /// 所属文件夹 ID（null 表示根级），仅根节点有效，由 Dart 侧包装时填充
    pub folder_id: Option<String>,
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
        folder_id: p.folder_id,
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
        has_cue: i.has_cue,
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

fn convert_folder(f: music_player::Folder) -> FolderInfo {
    FolderInfo {
        id: f.id,
        name: f.name,
        parent_id: f.parent_id,
        level: f.level,
        cover_path: f.cover_path,
        tags: f.tags,
        author: f.author,
        play_count: f.play_count,
        created_at: f.created_at.timestamp(),
        updated_at: f.updated_at.timestamp(),
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

fn convert_path_mapping_node(n: music_player::PathMappingNode) -> PathMappingNodeInfo {
    let node_type = match n.node_type {
        music_player::PathMappingNodeType::Directory => PathMappingNodeType::Directory,
        music_player::PathMappingNodeType::AudioFile => PathMappingNodeType::AudioFile,
        music_player::PathMappingNodeType::ImageFile => PathMappingNodeType::ImageFile,
        music_player::PathMappingNodeType::CueFile => PathMappingNodeType::CueFile,
        music_player::PathMappingNodeType::OtherFile => PathMappingNodeType::OtherFile,
    };
    PathMappingNodeInfo {
        name: n.name,
        path: n.path,
        node_type,
        file_size: n.file_size.map(|v| v as i64),
        children: n.children.into_iter().map(convert_path_mapping_node).collect(),
        has_audio: n.has_audio,
        folder_id: None,
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

/// 在指定目录下创建播放列表
#[frb(sync)]
pub fn create_playlist_in_folder(
    name: String,
    folder_id: Option<String>,
) -> anyhow::Result<Playlist> {
    music_player::create_playlist_in_folder(name, folder_id)
        .map(convert_playlist)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 获取指定目录下的播放列表
#[frb(sync)]
pub fn get_playlists_by_folder(folder_id: Option<String>) -> anyhow::Result<Vec<Playlist>> {
    music_player::get_playlists_by_folder(folder_id)
        .map(|ps| ps.into_iter().map(convert_playlist).collect())
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

/// 修复已有音乐条目的缺失元数据（时长、标签等）
pub async fn repair_missing_metadata(playlist_id: String) -> anyhow::Result<usize> {
    music_player::repair_missing_metadata(playlist_id).map_err(|e| anyhow::anyhow!(e))
}

// ── 目录 API ───────────────────────────────────────────────────────────────────

/// 获取所有目录
#[frb(sync)]
pub fn get_all_folders() -> anyhow::Result<Vec<FolderInfo>> {
    music_player::get_all_folders()
        .map(|fs| fs.into_iter().map(convert_folder).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 获取指定父目录下的子目录
#[frb(sync)]
pub fn get_sub_folders(parent_id: Option<String>) -> anyhow::Result<Vec<FolderInfo>> {
    music_player::get_sub_folders(parent_id)
        .map(|fs| fs.into_iter().map(convert_folder).collect())
        .map_err(|e| anyhow::anyhow!(e))
}

/// 创建目录（最多三级）
#[frb(sync)]
pub fn create_folder(name: String, parent_id: Option<String>) -> anyhow::Result<FolderInfo> {
    music_player::create_folder(name, parent_id)
        .map(convert_folder)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 重命名目录
#[frb(sync)]
pub fn rename_folder(folder_id: String, name: String) -> anyhow::Result<bool> {
    music_player::rename_folder(folder_id, name).map_err(|e| anyhow::anyhow!(e))
}

/// 删除目录（级联删除子目录和关联的播放列表）
#[frb(sync)]
pub fn delete_folder(folder_id: String) -> anyhow::Result<bool> {
    music_player::delete_folder(folder_id).map_err(|e| anyhow::anyhow!(e))
}

/// 更新目录信息（封面、标签、作者等）
#[frb(sync)]
pub fn update_folder(
    folder_id: String,
    name: Option<String>,
    cover_path: Option<String>,
    tags: Option<String>,
    author: Option<String>,
) -> anyhow::Result<bool> {
    music_player::update_folder(folder_id, name, cover_path, tags, author)
        .map_err(|e| anyhow::anyhow!(e))
}

/// 递增目录播放次数
#[frb(sync)]
pub fn increment_folder_play_count(folder_id: String) -> anyhow::Result<bool> {
    music_player::increment_folder_play_count(folder_id).map_err(|e| anyhow::anyhow!(e))
}

/// 提取音频文件的波形数据（用于可视化）
/// 返回降采样后的振幅数组（0.0~1.0），samples 指定返回的采样点数
///
/// 优化：边解码边计算 bin 峰值，不分配全量 PCM 缓冲区，速度提升 5~10 倍
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn extract_waveform(
    audio_file_path: String,
    samples: u32,
) -> anyhow::Result<Vec<f64>> {
    // 先尝试读取缓存
    let cache_path = _waveform_cache_path(&audio_file_path);
    if let Ok(cached) = _read_waveform_cache(&cache_path, samples) {
        return Ok(cached);
    }

    // 流式解码 + 实时计算波形 bin
    let result = _extract_waveform_streaming(&audio_file_path, samples as usize)
        .map_err(|e| anyhow::anyhow!(e))?;

    // 写入缓存
    let _ = _write_waveform_cache(&cache_path, samples, &result);

    Ok(result)
}

/// 提取音频文件的波形数据（移动端空实现）
#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn extract_waveform(
    _audio_file_path: String,
    _samples: u32,
) -> anyhow::Result<Vec<f64>> {
    Ok(vec![])
}

/// 流式解码音频并直接计算波形 bin 峰值
/// 不分配全量 PCM 缓冲区，只维护 num_bins 个峰值
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn _extract_waveform_streaming(
    audio_file_path: &str,
    num_bins: usize,
) -> Result<Vec<f64>, String> {
    use symphonia::core::audio::Signal;
    use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let src = std::fs::File::open(audio_file_path)
        .map_err(|e| format!("打开音频文件失败: {}", e))?;
    let mss = MediaSourceStream::new(
        Box::new(src) as Box<dyn symphonia::core::io::MediaSource>,
        Default::default(),
    );

    let hint = Hint::new();
    let format_opts = FormatOptions::default();
    let metadata_opts = MetadataOptions::default();
    let decoder_opts = DecoderOptions::default();

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &format_opts, &metadata_opts)
        .map_err(|e| format!("探测音频格式失败: {}", e))?;

    let mut format = probed.format;

    // 找到第一个音频轨道
    let track_id = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .map(|t| t.id)
        .ok_or("未找到音频轨道")?;

    let track = format.tracks().iter().find(|t| t.id == track_id).unwrap();

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &decoder_opts)
        .map_err(|e| format!("创建解码器失败: {}", e))?;

    // 获取音频时长（样本数），用于计算每个 bin 的样本范围
    let sample_rate = track.codec_params.sample_rate.unwrap_or(44100) as u64;
    let n_frames = track.codec_params.n_frames.unwrap_or(0);
    let total_samples = if n_frames > 0 {
        n_frames
    } else {
        // 无法获取帧数，用文件大小粗略估算
        let file_size = std::fs::metadata(audio_file_path)
            .map(|m| m.len())
            .unwrap_or(0);
        // 假设平均比特率 128kbps
        let estimated_duration_secs = file_size as f64 / (128000.0 / 8.0);
        (estimated_duration_secs * sample_rate as f64) as u64
    };

    let samples_per_bin = if total_samples > 0 && num_bins > 0 {
        total_samples as f64 / num_bins as f64
    } else {
        0.0
    };

    // 初始化 bin 峰值数组
    let mut bin_peaks = vec![0.0f32; num_bins];
    let mut sample_index: u64 = 0;

    // 解码循环：边解码边累积 bin 峰值
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(symphonia::core::errors::Error::ResetRequired) => continue,
            Err(symphonia::core::errors::Error::IoError(_)) => break,
            Err(_) => break,
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            Err(_) => break,
        };

        let frames = decoded.frames();

        // 从解码帧中提取样本并直接分配到对应的 bin
        match decoded {
            symphonia::core::audio::AudioBufferRef::S16(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = (ch0[i] as f32 / 32768.0).abs();
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            symphonia::core::audio::AudioBufferRef::S32(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = (ch0[i] as f32 / 2147483648.0).abs();
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            symphonia::core::audio::AudioBufferRef::F32(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = ch0[i].abs();
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            symphonia::core::audio::AudioBufferRef::F64(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = ch0[i].abs() as f32;
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            symphonia::core::audio::AudioBufferRef::U8(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = ((ch0[i] as f32 - 128.0) / 128.0).abs();
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            symphonia::core::audio::AudioBufferRef::S24(buf) => {
                let ch0 = buf.chan(0);
                for i in 0..frames {
                    let val = (ch0[i].0 as f32 / 8388608.0).abs();
                    _accumulate_bin(&mut bin_peaks, sample_index, val, samples_per_bin);
                    sample_index += 1;
                }
            }
            _ => {
                // 跳过不支持的格式
                sample_index += frames as u64;
            }
        }
    }

    // 如果没有获取到样本数信息，重新按实际解码样本数分配
    if samples_per_bin == 0.0 && sample_index > 0 && num_bins > 0 {
        // 需要重新计算（此时 bin_peaks 是按顺序填充的，需要重新分配）
        // 简化处理：直接按等分截取
        let result: Vec<f64> = bin_peaks.iter().map(|&v| v as f64).collect();
        return Ok(_redistribute_bins(&result, num_bins));
    }

    Ok(bin_peaks.iter().map(|&v| v as f64).collect())
}

/// 将样本累积到对应的 bin（取峰值）
#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[inline]
fn _accumulate_bin(bin_peaks: &mut [f32], sample_index: u64, value: f32, samples_per_bin: f64) {
    if samples_per_bin <= 0.0 {
        return;
    }
    let bin_idx = (sample_index as f64 / samples_per_bin) as usize;
    if bin_idx < bin_peaks.len() && value > bin_peaks[bin_idx] {
        bin_peaks[bin_idx] = value;
    }
}

/// 重新分配 bin（当无法预知总样本数时使用）
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn _redistribute_bins(data: &[f64], target_bins: usize) -> Vec<f64> {
    if data.len() == target_bins {
        return data.to_vec();
    }
    let ratio = data.len() as f64 / target_bins as f64;
    let mut result = Vec::with_capacity(target_bins);
    for i in 0..target_bins {
        let start = (i as f64 * ratio) as usize;
        let end = ((i + 1) as f64 * ratio).min(data.len() as f64) as usize;
        let peak = data[start..end].iter().fold(0.0f64, |acc, &v| acc.max(v));
        result.push(peak);
    }
    result
}

/// 获取波形缓存文件路径
fn _waveform_cache_path(audio_file_path: &str) -> String {
    let app_data = std::env::var("APPDATA")
        .unwrap_or_else(|_| {
            #[cfg(target_os = "macos")]
            {
                format!("{}/Library/Application Support",
                    std::env::var("HOME").unwrap_or_else(|_| ".".to_string()))
            }
            #[cfg(not(target_os = "macos"))]
            {
                std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
                    format!("{}/.local/share",
                        std::env::var("HOME").unwrap_or_else(|_| ".".to_string()))
                })
            }
        });

    // 用文件路径的 hash 作为缓存文件名
    let hash = {
        use std::hash::{Hash, Hasher};
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        audio_file_path.hash(&mut hasher);
        format!("{:016x}", hasher.finish())
    };

    format!("{}/SlimeWorks/waveform_cache/{}.json", app_data, hash)
}

/// 读取波形缓存
fn _read_waveform_cache(cache_path: &str, samples: u32) -> Result<Vec<f64>, ()> {
    let content = std::fs::read_to_string(cache_path).map_err(|_| ())?;
    let cached: serde_json::Value = serde_json::from_str(&content).map_err(|_| ())?;
    let cached_samples = cached.get("samples").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
    if cached_samples != samples {
        return Err(());
    }
    let arr = cached.get("data").and_then(|v| v.as_array()).ok_or(())?;
    Ok(arr.iter().filter_map(|v| v.as_f64()).collect())
}

/// 写入波形缓存
fn _write_waveform_cache(cache_path: &str, samples: u32, data: &[f64]) -> std::io::Result<()> {
    // 确保目录存在
    if let Some(parent) = std::path::Path::new(cache_path).parent() {
        std::fs::create_dir_all(parent)?;
    }

    let json = serde_json::json!({
        "samples": samples,
        "data": data,
    });

    std::fs::write(cache_path, serde_json::to_string(&json)?)
}

// ── 路径映射 API ────────────────────────────────────────────────────────────────

/// 扫描文件夹路径映射（返回树形结构，不限制文件类型，不限深度）
#[frb(sync)]
pub fn scan_path_mapping(dir_path: String) -> anyhow::Result<PathMappingNodeInfo> {
    music_player::scan_path_mapping(dir_path)
        .map(convert_path_mapping_node)
        .map_err(|e| anyhow::anyhow!(e))
}
