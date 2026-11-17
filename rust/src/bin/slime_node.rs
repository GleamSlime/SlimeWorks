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

// 二进制 crate 的子模块默认在同目录找；这里显式指到子目录，
// 避免 src/bin/*.rs 被 Cargo 当成第二个可执行目标
#[path = "slime_node/self_update.rs"]
mod self_update;

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
    /// 是否开启自更新（默认关闭：节点是常驻服务，升级时机应由运维决定）
    #[serde(alias = "autoUpdate")]
    auto_update: Option<bool>,
    /// 自更新检查间隔（小时），默认 6
    #[serde(alias = "updateIntervalHours")]
    update_interval_hours: Option<u64>,
    /// GitHub API 根地址，可换成镜像/代理
    #[serde(alias = "updateApiBase")]
    update_api_base: Option<String>,
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
    auto_update: Option<bool>,
    update_interval_hours: Option<u64>,
    update_api_base: Option<String>,
    check_update: bool,
    self_update: bool,
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
  --auto-update       开启自更新（默认关闭）
  --no-auto-update    关闭自更新
  --update-interval <小时>  自更新检查间隔（默认 6）
  --update-api-base <url>   GitHub API 地址，可指向镜像（默认 https://api.github.com）
  --check-update      只检查是否有新版本，不安装
  --self-update       检查并立即安装（交给 slime_node_updater 完成替换与重启）
  -h, --help          显示帮助
  -V, --version       显示版本

环境变量: SLIME_NODE_HOST / PORT / NAME / AUTH / DATA_DIR / FFMPEG / FFPROBE / LOG_DIR / CONFIG
         SLIME_NODE_AUTO_UPDATE / SLIME_NODE_UPDATE_INTERVAL_HOURS / SLIME_NODE_UPDATE_API_BASE

自更新需要同目录的 slime_node_updater：节点只负责查版本、下载与自检，
替换和重启由它在本进程退出后完成。
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
        // 打印构建版本而不是 crate 版本，自更新比对的就是这一串
        println!(
            "slime_node {}",
            rust_lib_slime_works::build_version::BUILD_VERSION
        );
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

    // ── 自更新配置（默认关闭，需显式开启）──────────────────────────────
    let auto_update = cli
        .auto_update
        .or_else(|| env_bool("SLIME_NODE_AUTO_UPDATE"))
        .or(file.auto_update)
        .unwrap_or(false);
    let update_interval_hours = cli
        .update_interval_hours
        .or_else(|| env_parse::<u64>("SLIME_NODE_UPDATE_INTERVAL_HOURS"))
        .or(file.update_interval_hours)
        .filter(|hours| *hours > 0)
        .unwrap_or(6);
    let update_api_base = pick_string(
        cli.update_api_base,
        "SLIME_NODE_UPDATE_API_BASE",
        file.update_api_base,
    )
    .unwrap_or_else(|| "https://api.github.com".to_string());
    let update_opts = self_update::UpdateOptions {
        api_base: update_api_base,
        interval: Duration::from_secs(update_interval_hours.saturating_mul(3600)),
        port,
    };

    // 一次性动作：查完/装完就退出，不启动服务，方便 cron 或人工调用
    if cli.check_update {
        return self_update::run_check(&update_opts);
    }
    if cli.self_update {
        return self_update::run_once(&update_opts);
    }

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

    println!("[slime_node] 版本 {}", rust_lib_slime_works::build_version::BUILD_VERSION);
    println!("[slime_node] 监听 {host}:{port}");
    println!("[slime_node] 节点名称 {name}");
    println!("[slime_node] 数据目录 {}", base_dir.display());
    // slime_logger 会在传入目录下再建 logs 子目录
    println!("[slime_node] 日志目录 {}", log_dir.join("logs").display());
    println!(
        "[slime_node] 授权校验 {}",
        if auth.trim().is_empty() { "关闭" } else { "开启" }
    );
    println!(
        "[slime_node] 自更新 {}",
        if auto_update {
            format!(
                "开启（每 {} 小时检查一次）",
                update_opts.interval.as_secs() / 3600
            )
        } else {
            "关闭".to_string()
        }
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
    if auto_update {
        self_update::start_auto_update(update_opts);
    }
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

/// 布尔型环境变量：接受 1/0、true/false、yes/no、on/off。
fn env_bool(key: &str) -> Option<bool> {
    let raw = std::env::var(key).ok()?;
    match raw.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
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
            "--auto-update" => cli.auto_update = Some(true),
            "--no-auto-update" => cli.auto_update = Some(false),
            "--update-interval" => {
                cli.update_interval_hours = Some(
                    value("--update-interval")?
                        .parse()
                        .map_err(|_| "更新间隔必须是小时数".to_string())?,
                )
            }
            "--update-api-base" => cli.update_api_base = Some(value("--update-api-base")?),
            "--check-update" => cli.check_update = true,
            "--self-update" => cli.self_update = true,
            "-h" | "--help" => cli.help = true,
            "-V" | "--version" => cli.version = true,
            other => return Err(format!("未知参数 {other}")),
        }
    }
    Ok(cli)
}
