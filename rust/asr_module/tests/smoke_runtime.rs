// 手动冒烟测试：需联网下载组件、并准备一段带语音的音频，默认被 ignore。
//   ASR_TEST_AUDIO=D:\sample.wav ASR_TEST_LANG=ko cargo test -p asr_module -- --ignored --nocapture
use std::path::Path;
use std::process::Command;

#[test]
#[ignore]
fn download_runtime_and_print_sidecar_help() {
    let exec = asr_module::runtime::download_runtime().expect("运行时下载失败");
    println!("sidecar = {}", exec.display());

    let mut cmd = Command::new(&exec);
    cmd.arg("--help");
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000);
    }
    let out = cmd.output().expect("sidecar 启动失败");
    let text = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    for line in text.lines() {
        if line.contains("sense-voice") || line.contains("vad-model") || line.contains("tokens") {
            println!("FLAG> {}", line.trim());
        }
    }
    println!("exit = {:?}", out.status.code());
}

/// 真跑一遍 SenseVoice：绕过 ffmpeg 抽轨，直接把 wav 交给 sidecar，
/// 检查段落切分与 SRT 落盘是否符合预期
#[test]
#[ignore]
fn transcribe_sample_audio_to_srt() {
    let audio = std::env::var("ASR_TEST_AUDIO").expect("未设置 ASR_TEST_AUDIO");
    let lang = std::env::var("ASR_TEST_LANG").unwrap_or_else(|_| "auto".into());
    let wav = Path::new(&audio);
    assert!(wav.exists(), "测试音频不存在: {audio}");

    let (segments, wall) =
        asr_module::sidecar::recognize(wav, None, Some(&lang), None).expect("识别失败");
    println!("语言 {lang}，耗时 {wall:.1}s，共 {} 段", segments.len());
    for seg in &segments {
        println!("[{} → {}] {}", seg.start_ms, seg.end_ms, seg.text);
    }

    let out_dir = std::env::temp_dir().join("asr_smoke");
    let _ = std::fs::create_dir_all(&out_dir);
    let srt = asr_module::srt::write_srt(&audio, &segments, &out_dir).expect("SRT 写入失败");
    let content = std::fs::read_to_string(&srt).unwrap();
    println!("{content}");
    assert!(content.contains("-->"), "SRT 缺少时间轴");

    // 写出后读回来：翻译流程完全依赖 parse，这里验证时间轴与文本无损
    let reread = asr_module::srt::read_srt(&srt).expect("SRT 回读失败");
    assert_eq!(reread.len(), segments.len(), "回读段数与识别结果不一致");
    for (a, b) in reread.iter().zip(&segments) {
        assert_eq!((a.start_ms, a.end_ms), (b.start_ms, b.end_ms), "时间轴错位");
        assert_eq!(a.text.trim(), b.text.trim(), "文本错位");
    }
    println!("SRT 回读校验通过: {} 段，srt = {srt}", reread.len());
}

/// 走完整链路（ffprobe 探时长 → ffmpeg 抽音轨 → sidecar → SRT），
/// 需要容器格式（mp4/mkv）才能验证抽轨这一步
#[test]
#[ignore]
fn transcribe_media_file_end_to_end() {
    let media = std::env::var("ASR_TEST_MEDIA").expect("未设置 ASR_TEST_MEDIA");
    let ffmpeg = std::env::var("ASR_FFMPEG").unwrap_or_else(|_| "ffmpeg".into());
    let ffprobe = std::env::var("ASR_FFPROBE").unwrap_or_else(|_| "ffprobe".into());
    asr_module::audio::set_ffmpeg_paths(Some(ffmpeg), Some(ffprobe));

    let result = asr_module::api::transcribe_to_srt(media, None, Some("auto".into()))
        .expect("端到端识别失败");
    println!(
        "字幕: {}\n段数: {}，音频 {:.1}s，耗时 {:.1}s",
        result.srt_path,
        result.segment_count,
        result.audio_duration_secs.unwrap_or(0.0),
        result.wall_time_secs
    );
    println!("{}", std::fs::read_to_string(&result.srt_path).unwrap());
}
