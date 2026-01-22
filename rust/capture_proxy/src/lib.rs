/// Capture Proxy 库 - HTTP/HTTPS 代理服务器，支持流量捕获和MITM拦截
mod capture;
mod cert;
mod mitm;
mod server;
pub mod system_proxy2;

// 重新导出公共API
pub use capture::{
    add_captured_item, clear_captured_items, get_captured_items, init_capture_storage, CapturedItem,
};
pub use cert::{
    ensure_ca_certificate_exists, get_ca_cert_path, install_ca_certificate_with_password,
    is_ca_certificate_installed, CertResolver,
};

use hyper_util::rt::TokioIo;
use hyper_util::server::conn::auto::Builder;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio_rustls::{TlsAcceptor, TlsConnector};

/// 启动代理服务器
pub async fn start_proxy_server(port: u16) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    // 初始化捕获存储
    init_capture_storage();

    // 动态生成CA证书
    let mut tls_acceptor_opt: Option<Arc<TlsAcceptor>> = None;
    let mut tls_connector_opt: Option<Arc<TlsConnector>> = None;

    match CertResolver::new() {
        Ok(resolver) => {
            println!("CA证书生成成功，MITM已启用");
            let server_config = rustls::ServerConfig::builder()
                .with_no_client_auth()
                .with_cert_resolver(Arc::new(resolver));
            let acceptor = TlsAcceptor::from(Arc::new(server_config));
            tls_acceptor_opt = Some(Arc::new(acceptor));

            let mut root_store = rustls::RootCertStore::empty();
            let certs_result = rustls_native_certs::load_native_certs();
            for cert in certs_result.certs {
                root_store.add(cert).ok();
            }
            if let Some(e) = certs_result.errors.first() {
                eprintln!("警告: 加载系统证书时出现错误: {}", e);
            }
            let client_config = rustls::ClientConfig::builder()
                .with_root_certificates(root_store)
                .with_no_client_auth();
            let connector = TlsConnector::from(Arc::new(client_config));
            tls_connector_opt = Some(Arc::new(connector));
        }
        Err(e) => {
            eprintln!("CA证书生成失败: {}", e);
        }
    }

    println!("代理服务运行在端口 {}...", port);

    // 设置系统代理
    if let Err(e) = system_proxy2::set_proxy("127.0.0.1", port, None).await {
        eprintln!("设置系统代理错误: {}", e);
    } else {
        println!("系统代理已设置为 127.0.0.1:{}", port);
    }

    let listener = TcpListener::bind(addr).await?;
    loop {
        let (stream, peer_addr) = listener.accept().await?;
        println!("[代理] 接受新连接来自: {}", peer_addr);
        let io = TokioIo::new(stream);

        let tls_acceptor = tls_acceptor_opt.clone();
        let tls_connector = tls_connector_opt.clone();

        tokio::task::spawn(async move {
            let service = hyper::service::service_fn(move |req| {
                println!("[代理] 收到请求: {} {}", req.method(), req.uri());
                server::proxy_handler(req, tls_acceptor.clone(), tls_connector.clone())
            });

            if let Err(err) = Builder::new(hyper_util::rt::TokioExecutor::new())
                .serve_connection_with_upgrades(io, service)
                .await
            {
                eprintln!("[代理] 连接错误: {:?}", err);
            } else {
                println!("[代理] 连接正常关闭");
            }
        });
    }
}
