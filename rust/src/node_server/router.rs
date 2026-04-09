use super::types::*;
use super::NodeServerConfig;
use hyper::{Body, Method, Request, Response, StatusCode};
use std::convert::Infallible;
use std::sync::Arc;

/// 路由请求到对应的处理器
pub async fn route_request(
    req: Request<Body>,
    config: Arc<NodeServerConfig>,
) -> Result<Response<Body>, Infallible> {
    let method = req.method().clone();
    let path = req.uri().path().to_string();

    match (method, path.as_str()) {
        // 健康检查
        (Method::GET, "/health") => {
            let response = NodeResponse::success(serde_json::json!({
                "name": config.name,
                "port": config.port,
            }));
            Ok(json_response(response))
        }

        // 动作分发
        (Method::POST, "/node/call") => handle_node_call(req, config).await,

        // 媒体文件服务
        (Method::GET, "/node/media") => super::media_handler::handle_media_request(req).await,

        // 文件上传
        (Method::POST, "/node/upload") => super::handlers::handle_upload(req).await,

        // 404
        _ => {
            let response = NodeResponse::error("Not Found".to_string());
            let mut resp = json_response(response);
            *resp.status_mut() = StatusCode::NOT_FOUND;
            Ok(resp)
        }
    }
}

/// 处理 /node/call 请求
async fn handle_node_call(
    req: Request<Body>,
    config: Arc<NodeServerConfig>,
) -> Result<Response<Body>, Infallible> {
    // 读取请求体
    let whole_body = match hyper::body::to_bytes(req.into_body()).await {
        Ok(bytes) => bytes,
        Err(e) => {
            return Ok(json_response(NodeResponse::error(format!(
                "读取请求体失败: {}",
                e
            ))));
        }
    };

    // 解析请求
    let node_req: NodeRequest = match serde_json::from_slice(&whole_body) {
        Ok(req) => req,
        Err(e) => {
            return Ok(json_response(NodeResponse::error(format!(
                "解析请求失败: {}",
                e
            ))));
        }
    };

    // 分发动作
    match super::handlers::dispatch_action(&node_req.action, node_req.params, &config).await {
        Ok(data) => Ok(json_response(NodeResponse::success(data))),
        Err(e) => Ok(json_response(NodeResponse::error(e))),
    }
}

/// 创建 JSON 响应
fn json_response(resp: NodeResponse) -> Response<Body> {
    let body = serde_json::to_string(&resp)
        .unwrap_or_else(|_| r#"{"success":false,"error":"JSON 序列化失败"}"#.to_string());

    Response::builder()
        .header("Content-Type", "application/json; charset=utf-8")
        .body(Body::from(body))
        .unwrap()
}
