use std::io;

#[cfg(any(target_os = "macos", target_os = "windows"))]
use std::process::Command;

#[cfg(target_os = "windows")]
fn decode_gbk(bytes: &[u8]) -> String {
    use encoding_rs::GBK;
    let (decoded, _, _) = GBK.decode(bytes);
    decoded.into_owned()
}

/// Minimal system proxy helper used instead of the broken module.
/// On macOS uses `networksetup`; on Windows uses `reg` to set HKCU Internet Settings.
pub async fn set_proxy(host: &str, port: u16, _network: Option<&str>) -> io::Result<()> {
    #[cfg(target_os = "macos")]
    {
        let nets = get_mac_available_networks().await?;
        if nets.is_empty() {
            return Err(io::Error::new(io::ErrorKind::Other, "无网络"));
        }
        for net in nets {
            println!("[系统代理] 为网络{}设置Mac代理 {}:{}", net, host, port);
            let out = Command::new("networksetup")
                .arg("-setsecurewebproxy")
                .arg(&net)
                .arg(host)
                .arg(port.to_string())
                .output()?;
            println!(
                "[系统代理] networksetup 输出: {}",
                String::from_utf8_lossy(&out.stdout)
            );
            println!(
                "[系统代理] networksetup 错误: {}",
                String::from_utf8_lossy(&out.stderr)
            );
            let out2 = Command::new("networksetup")
                .arg("-setwebproxy")
                .arg(&net)
                .arg(host)
                .arg(port.to_string())
                .output()?;
            println!(
                "[系统代理] networksetup 输出: {}",
                String::from_utf8_lossy(&out2.stdout)
            );
            println!(
                "[系统代理] networksetup 错误: {}",
                String::from_utf8_lossy(&out2.stderr)
            );
        }
        return Ok(());
    }

    #[cfg(target_os = "windows")]
    {
        let proxy_server = format!("{}:{}", host, port);
        println!("[系统代理] 设置Windows代理 {}", proxy_server);
        let out = Command::new("reg")
            .args(&[
                "add",
                "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                "/v",
                "ProxyServer",
                "/t",
                "REG_SZ",
                "/d",
                &proxy_server,
                "/f",
            ])
            .output()?;
        let stdout_text = decode_gbk(&out.stdout);
        let stderr_text = decode_gbk(&out.stderr);
        if !stdout_text.trim().is_empty() {
            println!("[系统代理] 注册表输出: {}", stdout_text);
        }
        if !stderr_text.trim().is_empty() {
            println!("[系统代理] 注册表错误: {}", stderr_text);
        }
        let out2 = Command::new("reg")
            .args(&[
                "add",
                "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                "/v",
                "ProxyEnable",
                "/t",
                "REG_DWORD",
                "/d",
                "1",
                "/f",
            ])
            .output()?;
        let stdout_text2 = decode_gbk(&out2.stdout);
        let stderr_text2 = decode_gbk(&out2.stderr);
        if !stdout_text2.trim().is_empty() {
            println!("[系统代理] 注册表输出: {}", stdout_text2);
        }
        if !stderr_text2.trim().is_empty() {
            println!("[系统代理] 注册表错误: {}", stderr_text2);
        }
        return Ok(());
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        println!("[系统代理] 当前平台不支持系统代理设置: {}:{}", host, port);
        Ok(())
    }
}

pub async fn close_proxy() -> io::Result<()> {
    #[cfg(target_os = "macos")]
    {
        let nets = get_mac_available_networks().await?;
        for net in nets {
            let _ = Command::new("networksetup")
                .arg("-setsecurewebproxystate")
                .arg(&net)
                .arg("off")
                .status()?;
            let _ = Command::new("networksetup")
                .arg("-setwebproxystate")
                .arg(&net)
                .arg("off")
                .status()?;
        }
        return Ok(());
    }

    #[cfg(target_os = "windows")]
    {
        let _ = Command::new("reg")
            .args(&[
                "add",
                "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
                "/v",
                "ProxyEnable",
                "/t",
                "REG_DWORD",
                "/d",
                "0",
                "/f",
            ])
            .status()?;
        return Ok(());
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    {
        println!("[系统代理] 当前平台不支持关闭系统代理");
        Ok(())
    }
}

#[cfg(target_os = "macos")]
async fn get_mac_available_networks() -> io::Result<Vec<String>> {
    use tokio::process::Command as TokioCommand;
    let out = TokioCommand::new("networksetup")
        .arg("-listallnetworkservices")
        .output()
        .await?;
    let s = String::from_utf8_lossy(&out.stdout);
    let mut nets = Vec::new();
    for line in s.lines() {
        let name = line.trim().to_string();
        if name.is_empty() {
            continue;
        }
        let info = TokioCommand::new("networksetup")
            .arg("getinfo")
            .arg(&name)
            .output()
            .await?;
        let info_s = String::from_utf8_lossy(&info.stdout);
        if info_s.contains("IP address:") {
            nets.push(name);
        }
    }
    Ok(nets)
}
