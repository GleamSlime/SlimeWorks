//! 独立更新程序：等主进程退出后替换可执行文件并重新拉起。
//!
//! 单独成文件是为了绕开「运行中的程序不能覆盖自己」这个限制——Windows 上
//! 文件被锁死时只能由另一个进程动手；Unix 上也让重启责任从服务进程里剥离，
//! 主进程只管退出，替换失败与否都不影响它已经写下的日志。
//!
//! 刻意不依赖 rust_lib_slime_works：这个二进制要足够小、自包含，
//! 才能在节点自身被替换的场景里稳稳跑起来。
//!
//! 用法：
//!   slime_node_updater --pid <主进程pid> --target <slime_node路径> [--new <新文件>]
//!                      [--expect <版本>] [--port <端口>] [--timeout <秒>] -- <原启动参数...>
//!
//! 任何一步失败都会把备份换回去并尝试用旧版本拉起，避免节点一直处于停止状态。

use std::ffi::OsString;
use std::fs;
use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::time::{Duration, Instant};

struct Options {
    pid: u32,
    target: PathBuf,
    new_file: Option<PathBuf>,
    expect_version: Option<String>,
    /// 主进程端口：若端口已被别的进程（如 systemd 重启）服务，就不再重复拉起
    port: Option<u16>,
    wait_timeout: Duration,
    /// `--` 之后原样传给 slime_node 的启动参数
    node_args: Vec<OsString>,
}

fn main() -> ExitCode {
    let opts = match parse_args() {
        Ok(o) => o,
        Err(err) => {
            eprintln!("[更新器] 参数错误: {err}");
            return ExitCode::from(2);
        }
    };

    println!("[更新器] 等待主进程 {} 退出", opts.pid);
    if !wait_process_exit(opts.pid, opts.wait_timeout) {
        eprintln!(
            "[更新器] 等待 {} 秒后主进程仍在运行，放弃本次更新，保持现状",
            opts.wait_timeout.as_secs()
        );
        return ExitCode::FAILURE;
    }

    let backup = backup_path(&opts.target);
    if let Some(new_file) = opts.new_file.as_deref() {
        if let Err(err) = replace(&opts.target, new_file, &backup, opts.expect_version.as_deref())
        {
            // 替换失败：旧文件没被动过，直接按原参数把服务拉回来
            eprintln!("[更新器] 替换失败: {err}");
            return start_node(&opts, None);
        }
        println!("[更新器] 已替换为 {}", opts.expect_version.as_deref().unwrap_or("新版本"));
    }

    // 有些部署（systemd Restart=always）会在主进程退出后自己把服务拉起来。
    // 端口已经有人应答就不再启动第二个实例，免得抢端口后双双退出。
    if let Some(port) = opts.port {
        if wait_port_serving(port, Duration::from_secs(5)) {
            println!("[更新器] 端口 {port} 已被服务占用，无需重复启动");
            return ExitCode::SUCCESS;
        }
    }

    start_node(&opts, Some(&backup))
}

/// 替换：先备份旧文件，再把新文件 rename 到位。
fn replace(
    target: &Path,
    new_file: &Path,
    backup: &Path,
    expect_version: Option<&str>,
) -> Result<(), String> {
    // 自检：新文件至少得能报出版本号
    let probe = Command::new(new_file)
        .arg("--version")
        .output()
        .map_err(|e| format!("新版本自检失败: {e}"))?;
    let probe_text = String::from_utf8_lossy(&probe.stdout);
    if !probe.status.success() {
        return Err("新版本无法执行".to_string());
    }
    if let Some(expected) = expect_version {
        if !probe_text.contains(expected) {
            return Err(format!(
                "新版本自检版本不符（期望 {expected}，实际 {}）",
                probe_text.trim()
            ));
        }
    }

    if backup.exists() {
        let _ = fs::remove_file(backup);
    }
    fs::rename(target, backup).map_err(|e| {
        format!(
            "备份旧版本失败: {e}；请确认 {} 所在目录可写",
            target.display()
        )
    })?;
    if let Err(err) = fs::rename(new_file, target) {
        // 换回去，保证还有可执行的旧版本
        let _ = fs::rename(backup, target);
        return Err(format!("替换可执行文件失败: {err}"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(meta) = fs::metadata(target) {
            let mut perms = meta.permissions();
            perms.set_mode(0o755);
            let _ = fs::set_permissions(target, perms);
        }
    }
    Ok(())
}

/// 拉起节点；失败时若还有备份就回滚并重试一次。
fn start_node(opts: &Options, backup: Option<&Path>) -> ExitCode {
    match spawn_node(&opts.target, &opts.node_args) {
        Ok(mut child) => {
            // 新版本起来后立刻退出的情况（依赖缺失、参数不兼容等）要能自动回滚
            std::thread::sleep(Duration::from_secs(2));
            if let Ok(Some(status)) = child.try_wait() {
                if let Some(backup) = backup {
                    if backup.exists() {
                        eprintln!("[更新器] 新版本启动即退出（{status}），回滚到旧版本");
                        let _ = fs::remove_file(&opts.target);
                        if fs::rename(backup, &opts.target).is_ok() {
                            return match spawn_node(&opts.target, &opts.node_args) {
                                Ok(_) => {
                                    println!("[更新器] 已用旧版本重新启动");
                                    ExitCode::SUCCESS
                                }
                                Err(err) => {
                                    eprintln!("[更新器] 旧版本启动失败: {err}");
                                    ExitCode::FAILURE
                                }
                            };
                        }
                    }
                }
                eprintln!("[更新器] 节点启动后立即退出: {status}");
                return ExitCode::FAILURE;
            }
            println!("[更新器] 节点已启动（pid {}）", child.id());
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("[更新器] 启动节点失败: {err}");
            if let Some(backup) = backup {
                if backup.exists() {
                    let _ = fs::remove_file(&opts.target);
                    if fs::rename(backup, &opts.target).is_ok() {
                        if spawn_node(&opts.target, &opts.node_args).is_ok() {
                            println!("[更新器] 已回滚并启动旧版本");
                            return ExitCode::SUCCESS;
                        }
                    }
                }
            }
            ExitCode::FAILURE
        }
    }
}

fn spawn_node(target: &Path, node_args: &[OsString]) -> std::io::Result<std::process::Child> {
    Command::new(target)
        .args(node_args)
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
}

fn backup_path(target: &Path) -> PathBuf {
    let name = target
        .file_name()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "slime_node".to_string());
    target.with_file_name(format!("{name}.bak"))
}

/// 轮询直到进程消失；超时返回 false。
fn wait_process_exit(pid: u32, timeout: Duration) -> bool {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if !process_alive(pid) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}

#[cfg(unix)]
fn process_alive(pid: u32) -> bool {
    // kill -0 只探测存在性，不发信号；无权限时同样算存在
    Command::new("kill")
        .arg("-0")
        .arg(pid.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

#[cfg(windows)]
fn process_alive(pid: u32) -> bool {
    let output = Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/NH"])
        .output();
    match output {
        Ok(out) => String::from_utf8_lossy(&out.stdout).contains(&pid.to_string()),
        Err(_) => false,
    }
}

#[cfg(not(any(unix, windows)))]
fn process_alive(_pid: u32) -> bool {
    false
}

fn wait_port_serving(port: u16, timeout: Duration) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if TcpStream::connect_timeout(&addr, Duration::from_millis(300)).is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    false
}

fn parse_args() -> Result<Options, String> {
    let mut pid: Option<u32> = None;
    let mut target: Option<PathBuf> = None;
    let mut new_file: Option<PathBuf> = None;
    let mut expect_version: Option<String> = None;
    let mut port: Option<u16> = None;
    let mut wait_timeout = Duration::from_secs(60);
    let mut node_args: Vec<OsString> = Vec::new();

    let mut args = std::env::args_os().skip(1);
    while let Some(arg) = args.next() {
        let text = arg.to_string_lossy().to_string();
        if text == "--" {
            node_args.extend(args);
            break;
        }
        let mut take = |what: &str| -> Result<OsString, String> {
            args.next().ok_or_else(|| format!("{what} 缺少取值"))
        };
        match text.as_str() {
            "--pid" => {
                pid = Some(
                    take("--pid")?
                        .to_string_lossy()
                        .trim()
                        .parse()
                        .map_err(|_| "--pid 必须是数字".to_string())?,
                )
            }
            "--target" => target = Some(PathBuf::from(take("--target")?)),
            "--new" => new_file = Some(PathBuf::from(take("--new")?)),
            "--expect" => {
                expect_version = Some(take("--expect")?.to_string_lossy().to_string())
            }
            "--port" => {
                port = Some(
                    take("--port")?
                        .to_string_lossy()
                        .trim()
                        .parse()
                        .map_err(|_| "--port 必须是数字".to_string())?,
                )
            }
            "--timeout" => {
                let secs: u64 = take("--timeout")?
                    .to_string_lossy()
                    .trim()
                    .parse()
                    .map_err(|_| "--timeout 必须是秒数".to_string())?;
                wait_timeout = Duration::from_secs(secs.max(1));
            }
            other => return Err(format!("未知参数 {other}")),
        }
    }

    let target = target.ok_or_else(|| "缺少 --target".to_string())?;
    if !target.exists() {
        return Err(format!("目标文件不存在: {}", target.display()));
    }
    if let Some(new_file) = new_file.as_deref() {
        if !new_file.exists() {
            return Err(format!("新文件不存在: {}", new_file.display()));
        }
    }
    Ok(Options {
        pid: pid.ok_or_else(|| "缺少 --pid".to_string())?,
        target,
        new_file,
        expect_version,
        port,
        wait_timeout,
        node_args,
    })
}
