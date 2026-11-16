//! 无头节点进程：只跑 Rust 节点服务，不带 Flutter 壳。
//!
//! 面向 NAS / 服务器这类不需要界面的部署：进程常驻、内存占用只有节点本身，
//! 客户端（桌面端 / 移动端）通过远程节点连过来。
//!
//! 配置来源优先级：命令行参数 > 环境变量 `SLIME_NODE_*` > JSON 配置文件 > 默认值。
//! JSON 文件用 `--config /path/node.json` 指定，键名与下面的结构体字段一致。

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use serde::Deserialize;

/// JSON 配置文件结构。未知字段直接忽略，方便前后版本混用。
#[derive(Debug, Default, Deserialize)]
struct NodeConfigFile {
    host: Option<String>,
    port: Option<u16>,
    name: Option<String>,
    /// 授权码明文；节点侧只保存它的 sha256 摘要
    auth: Option<String>,
    #[serde(alias = "dataDir")]
    data_dir: Option<String>,
    ffmpeg: Option<String>,
    ffprobe: Option<String>,
    #[serde(alias = "logDir")]
    log_dir: Option<String>,
}

/// 命令行参数（全部可缺省）。
#[derive(Debug, Default)]
struct CliOptions {
    config: Option<String>,
    host: Option<String>,
    port: Option<u16>,
    name: Option<String>,
    auth: Option<String>,
    data_dir: Option<String>,
    ffmpeg: Option<String>,
    ffprobe: Option<String>,
    log_dir: Option<String>,
    help: bool,
    version: bool,
}

const HELP: &str = "\
SlimeWorks 无头节点

用法: slime_node [选项]

选项:
  --config <path>     JSON 配置文件路径
  --host <addr>       监听地址（默认 0.0.0.0）
  --port <port>       监听端口（默认 17888）
  --name <name>       节点显示名称（默认 本机节点）
  --auth <code>       授权码；留空表示不校验
  --data-dir <dir>    数据目录（数据库、日志、缩略图都落在这里）
  --ffmpeg <path>     ffmpeg 可执行文件路径，缺省走 PATH
  --ffprobe <path>    ffprobe 可执行文件路径，缺省走 PATH
  --log-dir <dir>     日志目录，缺省与数据目录相同
  -h, --help          显示帮助
  -V, --version       显示版本

环境变量: SLIME_NODE_HOST / PORT / NAME / AUTH / DATA_DIR / FFMPEG / FFPROBE / LOG_DIR / CONFIG
";

fn main() -> ExitCode {
    let cli = match parse_args() {
        Ok(cli) => cli,
        Err(err) => {
            eprintln!("参数错误: {err}\n\n{HELP}");
            return ExitCode::from(2);
        }
    };
    if cli.help {
        print!("{HELP}");
        return ExitCode::SUCCESS;
    }
    if cli.version {
        println!("slime_node {}", env!("CARGO_PKG_VERSION"));
        return ExitCode::SUCCESS;
    }

    let config_path = cli
        .config
        .clone()
        .or_else(|| std::env::var("SLIME_NODE_CONFIG").ok())
        .filter(|v| !v.trim().is_empty());
    let file = match config_path.as_deref().map(load_config_file) {
        Some(Ok(cfg)) => cfg,
        Some(Err(err)) => {
            eprintln!("读取配置文件失败: {err}");
            return ExitCode::FAILURE;
        }
        None => NodeConfigFile::default(),
    };

    // ── 解析最终配置 ─────────────────────────────────────────────────────
    let host = pick_string(cli.host, "SLIME_NODE_HOST", file.host)
        .unwrap_or_else(|| "0.0.0.0".to_string());
    let port = cli
        .port
        .or_else(|| env_parse::<u16>("SLIME_NODE_PORT"))
        .or(file.port)
        .unwrap_or(17888);
    let name = pick_string(cli.name, "SLIME_NODE_NAME", file.name)
        .unwrap_or_else(|| "本机节点".to_string());
    let auth = pick_string(cli.auth, "SLIME_NODE_AUTH", file.auth).unwrap_or_default();
    let data_dir = pick_string(cli.data_dir, "SLIME_NODE_DATA_DIR", file.data_dir);
    let ffmpeg = pick_string(cli.ffmpeg, "SLIME_NODE_FFMPEG", file.ffmpeg);
    let ffprobe = pick_string(cli.ffprobe, "SLIME_NODE_FFPROBE", file.ffprobe);
    let log_dir = pick_string(cli.log_dir, "SLIME_NODE_LOG_DIR", file.log_dir);

    // 数据目录必须在任何业务模块初始化之前落到环境变量里：
    // 各模块的数据路径都是从 HOME/APPDATA/XDG_DATA_HOME 推导的。
    if let Some(dir) = data_dir.as_deref() {
        let dir = PathBuf::from(dir);
        if let Err(err) = std::fs::create_dir_all(&dir) {
            eprintln!("创建数据目录失败 {}: {err}", dir.display());
            return ExitCode::FAILURE;
        }
        apply_data_dir_env(&dir);
    }

    let base_dir = data_dir
        .clone()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(db_module::paths::app_data_base()));
    let log_dir = log_dir.map(PathBuf::from).unwrap_or_else(|| base_dir.clone());
    if let Err(err) = std::fs::create_dir_all(&log_dir) {
        eprintln!("创建日志目录失败 {}: {err}", log_dir.display());
        return ExitCode::FAILURE;
    }
    if let Err(err) = rust_lib_slime_works::api::logger::init_logger(
        &log_dir.to_string_lossy(),
    ) {
        // 日志初始化失败不致命：节点照样能跑，只是没有文件日志
        eprintln!("初始化日志失败（继续运行）: {err}");
    }

    if let Some(path) = ffmpeg.as_deref() {
        db_module::ffmpeg::register_ffmpeg_path(path.to_string());
    }
    if let Some(path) = ffprobe.as_deref() {
        db_module::ffmpeg::register_ffprobe_path(path.to_string());
    }

    println!("[slime_node] 版本 {}", env!("CARGO_PKG_VERSION"));
    println!("[slime_node] 监听 {host}:{port}");
    println!("[slime_node] 节点名称 {name}");
    println!("[slime_node] 数据目录 {}", base_dir.display());
    // slime_logger 会在传入目录下再建 logs 子目录
    println!("[slime_node] 日志目录 {}", log_dir.join("logs").display());
    println!(
        "[slime_node] 授权校验 {}",
        if auth.trim().is_empty() { "关闭" } else { "开启" }
    );

    if let Err(err) = rust_lib_slime_works::node_server::start_node_server(
        host,
        port,
        name,
        auth,
    ) {
        eprintln!("启动节点服务失败: {err}");
        return ExitCode::FAILURE;
    }

    println!("[slime_node] 节点已启动，按 Ctrl+C 退出");
    // start_node_server 内部已经起了 accept 线程，主线程只需要保持进程存活
    loop {
        std::thread::sleep(Duration::from_secs(3600));
    }
}

/// 把数据目录写进各平台推导用的环境变量。
fn apply_data_dir_env(dir: &std::path::Path) {
    let dir = dir.to_string_lossy().to_string();
    #[cfg(target_os = "windows")]
    {
        std::env::set_var("APPDATA", &dir);
    }
    #[cfg(target_os = "macos")]
    {
        std::env::set_var("HOME", &dir);
    }
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        // Linux/其它：XDG 决定多数模块的根目录，HOME 兜住自己拼路径的模块
        std::env::set_var("XDG_DATA_HOME", &dir);
        std::env::set_var("HOME", &dir);
    }
}

fn pick_string(
    cli: Option<String>,
    env_key: &str,
    file: Option<String>,
) -> Option<String> {
    cli.or_else(|| std::env::var(env_key).ok())
        .filter(|v| !v.trim().is_empty())
        .or(file)
}

fn env_parse<T: std::str::FromStr>(key: &str) -> Option<T> {
    std::env::var(key).ok()?.trim().parse().ok()
}

fn load_config_file(path: &str) -> Result<NodeConfigFile, String> {
    let raw = std::fs::read_to_string(path)
        .map_err(|e| format!("{path}: {e}"))?;
    serde_json::from_str(&raw).map_err(|e| format!("{path}: {e}"))
}

fn parse_args() -> Result<CliOptions, String> {
    let mut cli = CliOptions::default();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        // 同时支持 `--key value` 与 `--key=value`
        let (key, inline_value) = match arg.split_once('=') {
            Some((k, v)) => (k.to_string(), Some(v.to_string())),
            None => (arg.clone(), None),
        };
        let mut value = |what: &str| -> Result<String, String> {
            if let Some(v) = inline_value.clone() {
                return Ok(v);
            }
            args.next()
                .ok_or_else(|| format!("{what} 缺少取值"))
        };
        match key.as_str() {
            "--config" => cli.config = Some(value("--config")?),
            "--host" => cli.host = Some(value("--host")?),
            "--port" => {
                cli.port = Some(value("--port")?.parse().map_err(|_| "端口必须是数字".to_string())?)
            }
            "--name" => cli.name = Some(value("--name")?),
            "--auth" => cli.auth = Some(value("--auth")?),
            "--data-dir" => cli.data_dir = Some(value("--data-dir")?),
            "--ffmpeg" => cli.ffmpeg = Some(value("--ffmpeg")?),
            "--ffprobe" => cli.ffprobe = Some(value("--ffprobe")?),
            "--log-dir" => cli.log_dir = Some(value("--log-dir")?),
            "-h" | "--help" => cli.help = true,
            "-V" | "--version" => cli.version = true,
            other => return Err(format!("未知参数 {other}")),
        }
    }
    Ok(cli)
}
