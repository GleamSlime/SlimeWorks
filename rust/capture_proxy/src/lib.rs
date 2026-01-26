/// Capture Proxy 库 - HTTP/HTTPS 代理服务器，支持流量捕获和MITM拦截
mod capture;
mod cert;
pub mod ffi;
mod mitm;
mod server;
pub mod system_proxy; // C ABI 导出接口

// 重新导出公共API
pub use capture::{
    add_captured_item, clear_captured_items, get_captured_items, init_capture_storage, CapturedItem,
};
pub use cert::{
    ensure_ca_certificate_exists, get_ca_cert_path, install_ca_certificate_with_password,
    is_ca_certificate_installed, CertResolver,
};

use hyper::Server;
use rustls::Certificate as RustlsCert;
use std::convert::Infallible;
use std::net::SocketAddr;
use std::sync::Arc;
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
                .with_safe_defaults()
                .with_no_client_auth()
                .with_cert_resolver(Arc::new(resolver));
            let acceptor = TlsAcceptor::from(Arc::new(server_config));
            tls_acceptor_opt = Some(Arc::new(acceptor));

            let mut root_store = rustls::RootCertStore::empty();
            if let Ok(store) = rustls_native_certs::load_native_certs() {
                for cert in store {
                    root_store.add(&RustlsCert(cert.0)).ok();
                }
            }
            let client_config = rustls::ClientConfig::builder()
                .with_safe_defaults()
                .with_root_certificates(root_store)
                .with_no_client_auth();
            let connector = TlsConnector::from(Arc::new(client_config));
            tls_connector_opt = Some(Arc::new(connector));
        }
        Err(e) => {
            eprintln!("CA证书生成失败: {}", e);
        }
    }

    let make_service = {
        let tls_acceptor_opt = tls_acceptor_opt.clone();
        let tls_connector_opt = tls_connector_opt.clone();
        hyper::service::make_service_fn(move |_conn| {
            let tls_acceptor_opt = tls_acceptor_opt.clone();
            let tls_connector_opt = tls_connector_opt.clone();
            async move {
                Ok::<_, Infallible>(hyper::service::service_fn(move |req| {
                    server::proxy_handler(req, tls_acceptor_opt.clone(), tls_connector_opt.clone())
                }))
            }
        })
    };

    println!("代理服务运行在端口 {}...", port);

    // 设置系统代理
    if let Err(e) = system_proxy::set_proxy("127.0.0.1", port, None).await {
        eprintln!("设置系统代理错误: {}", e);
    } else {
        println!("系统代理已设置为 127.0.0.1:{}", port);
    }

    let server = Server::bind(&addr).serve(make_service);
    server.await?;
    Ok(())
}
