/// MITM (中间人) 处理模块 - 拦截和分析HTTPS流量
use crate::capture::add_captured_item;
use hyper_util::rt::TokioIo;
use rustls::pki_types::ServerName;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio_rustls::{TlsAcceptor, TlsConnector};

/// 处理CONNECT请求的MITM拦截
pub async fn handle_connect_mitm(
    upgraded: hyper::upgrade::Upgraded,
    authority: String,
    acceptor: Arc<TlsAcceptor>,
    connector: Arc<TlsConnector>,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // 将 Upgraded 转换为 TokioIo
    let upgraded = TokioIo::new(upgraded);
    
    // 与客户端建立TLS连接
    let client_tls = acceptor.accept(upgraded).await?;

    // 解析目标地址
    let mut parts = authority.split(':');
    let host = parts.next().ok_or("无效的authority")?.to_string();
    let port = parts
        .next()
        .and_then(|p| p.parse::<u16>().ok())
        .unwrap_or(443);

    // 连接上游服务器
    let upstream_tcp = TcpStream::connect((host.as_str(), port)).await?;
    let dnsname = ServerName::try_from(host.as_str())
        .map_err(|_| "无效的DNS名称")?
        .to_owned();
    let upstream_tls = connector.connect(dnsname, upstream_tcp).await?;

    // 分离读写流
    let (mut client_r, mut client_w) = tokio::io::split(client_tls);
    let (mut up_r, mut up_w) = tokio::io::split(upstream_tls);

    let last_req = Arc::new(Mutex::new(None::<String>));
    let lr1 = last_req.clone();
    let authority1 = authority.clone();

    // 客户端到上游：读取HTTP请求
    let client_to_up = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut tmp = [0u8; 4096];
        loop {
            match client_r.read(&mut tmp).await {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&tmp[..n]);
                    if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                Err(_) => break,
            }
        }

        // 解析请求URL
        if let Ok(s) = String::from_utf8(buf.clone()) {
            if let Some(first_line) = s.lines().next() {
                let parts: Vec<&str> = first_line.split_whitespace().collect();
                if parts.len() >= 2 {
                    let path = parts[1];
                    let host_line = s.lines().find(|l| l.to_lowercase().starts_with("host:"));
                    let full = if let Some(hline) = host_line {
                        let h = hline.splitn(2, ':').nth(1).unwrap_or("").trim();
                        format!("https://{}{}", h, path)
                    } else {
                        format!("https://{}{}", authority1, path)
                    };
                    *lr1.lock().unwrap() = Some(full);
                }
            }
        }
        if !buf.is_empty() {
            let _ = up_w.write_all(&buf).await;
        }
        let _ = tokio::io::copy(&mut client_r, &mut up_w).await;
    });

    let lr2 = last_req.clone();
    // 上游到客户端：读取HTTP响应并捕获数据
    let up_to_client = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut tmp = [0u8; 4096];
        loop {
            match up_r.read(&mut tmp).await {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&tmp[..n]);
                    if buf.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                Err(_) => break,
            }
        }

        let url = lr2.lock().unwrap().clone().unwrap_or_default();

        // 解析响应头
        let header_end = buf
            .windows(4)
            .position(|w| w == b"\r\n\r\n")
            .unwrap_or(buf.len());
        let headers_only = &buf[..header_end];

        if let Ok(s) = String::from_utf8(headers_only.to_vec()) {
            if let Some(status_line) = s.lines().next() {
                let status_parts: Vec<&str> = status_line.split_whitespace().collect();
                let status_code = status_parts
                    .get(1)
                    .and_then(|c| c.parse::<u16>().ok())
                    .unwrap_or(0);

                let ctype_line = s
                    .lines()
                    .find(|l| l.to_lowercase().starts_with("content-type:"));
                if let Some(ctype) = ctype_line {
                    let ctype_value = ctype.splitn(2, ':').nth(1).unwrap_or("").trim();

                    // 根据Content-Type捕获不同类型的资源
                    // 捕获视频
                    if ctype_value.to_lowercase().contains("video/")
                        && (status_code == 200 || status_code == 206)
                    {
                        println!("[捕获] 视频: {}", url);
                        add_captured_item(url.clone(), "video".to_string(), None);
                    }
                    // 捕获图片
                    else if ctype_value.to_lowercase().contains("image/") {
                        println!("[捕获] 图片: {}", url);
                        add_captured_item(url.clone(), "image".to_string(), None);
                    }
                    // 捕获JSON
                    else if ctype_value.to_lowercase().contains("application/json") {
                        println!("[捕获] JSON: {}", url);
                        add_captured_item(url.clone(), "json".to_string(), None);
                    }
                    // 捕获JavaScript
                    else if ctype_value.to_lowercase().contains("javascript")
                        || ctype_value
                            .to_lowercase()
                            .contains("application/x-javascript")
                    {
                        println!("[捕获] JavaScript: {}", url);
                        add_captured_item(url.clone(), "javascript".to_string(), None);
                    }
                }
            }
        }

        if !buf.is_empty() {
            let _ = client_w.write_all(&buf).await;
        }
        let _ = tokio::io::copy(&mut up_r, &mut client_w).await;
    });

    let _ = client_to_up.await;
    let _ = up_to_client.await;

    Ok(())
}
