use crate::types::{BridgeRequest, BridgeResponse};
use anyhow::Result;
use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Method, Request, Response, Server, StatusCode};
use std::convert::Infallible;
use std::net::SocketAddr;
use tokio::sync::oneshot;

/// HTTP桥接服务器
pub struct HttpBridgeServer {
    host: String,
    port: u16,
    shutdown_tx: Option<oneshot::Sender<()>>,
}

impl HttpBridgeServer {
    pub fn new(host: String, port: u16) -> Result<Self> {
        Ok(Self {
            host,
            port,
            shutdown_tx: None,
        })
    }

    pub async fn start(&mut self) -> Result<()> {
        let addr: SocketAddr = format!("{}:{}", self.host, self.port).parse()?;

        let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
        self.shutdown_tx = Some(shutdown_tx);

        let make_svc =
            make_service_fn(|_conn| async { Ok::<_, Infallible>(service_fn(handle_request)) });

        let server = Server::bind(&addr).serve(make_svc);

        println!("HTTP Bridge Server listening on http://{}", addr);

        tokio::spawn(async move {
            let graceful = server.with_graceful_shutdown(async {
                shutdown_rx.await.ok();
            });

            if let Err(e) = graceful.await {
                println!("Server error: {}", e);
            }
        });

        Ok(())
    }

    pub async fn stop(mut self) -> Result<()> {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
        Ok(())
    }
}

/// 处理HTTP请求
async fn handle_request(_req: Request<Body>) -> Result<Response<Body>, Infallible> {
    match (_req.method(), _req.uri().path()) {
        (&Method::POST, "/bridge") => handle_bridge_request(_req).await,
        (&Method::GET, "/health") => Ok(Response::new(Body::from("OK"))),
        _ => {
            let mut response = Response::new(Body::from("Not Found"));
            *response.status_mut() = StatusCode::NOT_FOUND;
            Ok(response)
        }
    }
}

/// 处理桥接请求
async fn handle_bridge_request(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    // 读取请求体
    let whole_body = match hyper::body::to_bytes(req.into_body()).await {
        Ok(bytes) => bytes,
        Err(e) => {
            let error_response = BridgeResponse::error(format!("Failed to read body: {}", e));
            return Ok(Response::new(Body::from(
                serde_json::to_string(&error_response).unwrap(),
            )));
        }
    };

    // 解析请求
    let bridge_req: BridgeRequest = match serde_json::from_slice(&whole_body) {
        Ok(req) => req,
        Err(e) => {
            let error_response = BridgeResponse::error(format!("Invalid request: {}", e));
            return Ok(Response::new(Body::from(
                serde_json::to_string(&error_response).unwrap(),
            )));
        }
    };

    // 根据模块和函数调用相应的处理器
    let response = match process_bridge_request(bridge_req).await {
        Ok(resp) => resp,
        Err(e) => BridgeResponse::error(format!("Processing error: {}", e)),
    };

    Ok(Response::new(Body::from(
        serde_json::to_string(&response).unwrap(),
    )))
}

/// 处理桥接请求的核心逻辑
async fn process_bridge_request(req: BridgeRequest) -> Result<BridgeResponse> {
    // 使用注册的处理器
    match crate::call_handler(req.module.clone(), req.function.clone(), req.params).await {
        Ok(result) => Ok(BridgeResponse::success(result)),
        Err(e) => Ok(BridgeResponse::error(e)),
    }
}
