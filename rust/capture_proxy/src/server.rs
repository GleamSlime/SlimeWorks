/// HTTP代理服务器模块 - 处理HTTP请求和CONNECT隧道
use crate::cert::CertResolver;
use crate::mitm::handle_connect_mitm;
use hyper::{Body, Method, Request, Response, StatusCode};
use std::convert::Infallible;
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio_rustls::{TlsAcceptor, TlsConnector};

/// 处理所有代理请求的主处理器
pub async fn proxy_handler(
    req: Request<Body>,
    tls_acceptor_opt: Option<Arc<TlsAcceptor>>,
    tls_connector_opt: Option<Arc<TlsConnector>>,
) -> Result<Response<Body>, Infallible> {
    // 处理CONNECT请求
    if req.method() == Method::CONNECT {
        // 如果没有TLS配置，使用普通隧道模式
        if tls_acceptor_opt.is_none() || tls_connector_opt.is_none() {
            if let Some(authority) = req.uri().authority() {
                let authority = authority.as_str().to_string();
                tokio::spawn(async move {
                    match hyper::upgrade::on(req).await {
                        Ok(mut upgraded) => {
                            let mut parts = authority.split(':');
                            let host = parts.next().unwrap_or("");
                            let port = parts
                                .next()
                                .and_then(|p| p.parse::<u16>().ok())
                                .unwrap_or(443);
                            if let Ok(mut server) = TcpStream::connect((host, port)).await {
                                let _ =
                                    tokio::io::copy_bidirectional(&mut upgraded, &mut server).await;
                            }
                        }
                        Err(_) => {}
                    }
                });

                return Ok(Response::builder()
                    .status(StatusCode::OK)
                    .body(Body::empty())
                    .unwrap());
            }
        }

        // 使用MITM模式拦截HTTPS流量
        let acceptor = tls_acceptor_opt.unwrap();
        let connector = tls_connector_opt.unwrap();

        if let Some(authority) = req.uri().authority() {
            let authority = authority.as_str().to_string();
            tokio::spawn(async move {
                match hyper::upgrade::on(req).await {
                    Ok(upgraded) => {
                        let _ = handle_connect_mitm(upgraded, authority, acceptor, connector).await;
                    }
                    Err(_) => {}
                }
            });

            return Ok(Response::builder()
                .status(StatusCode::OK)
                .body(Body::empty())
                .unwrap());
        }
    }

    // 处理普通HTTP请求（暂时返回空响应）
    Ok(Response::builder()
        .status(StatusCode::OK)
        .body(Body::empty())
        .unwrap())
}
