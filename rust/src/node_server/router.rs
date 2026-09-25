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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    /// 构造不依赖外部状态的测试节点配置
    fn test_config() -> Arc<NodeServerConfig> {
        Arc::new(NodeServerConfig {
            host: "127.0.0.1".to_string(),
            port: 19998,
            name: "路由单元测试节点".to_string(),
            auth_code_hash: None,
        })
    }

    /// 直构 hyper Request 走完整 route_request，返回 (状态码, Content-Type, JSON 体)；
    /// 根 crate 的 tokio 无 macros feature，用 node_server 的全局共享 runtime 驱动
    fn drive(method: Method, uri: &str, body: Body) -> (StatusCode, String, Value) {
        super::super::shared_runtime().block_on(async move {
            let req = Request::builder()
                .method(method)
                .uri(uri)
                .body(body)
                .expect("构造测试 Request 应成功");
            let resp = route_request(req, test_config())
                .await
                .expect("route_request 签名为 Infallible");
            let status = resp.status();
            let ctype = resp
                .headers()
                .get("Content-Type")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("")
                .to_string();
            let bytes = hyper::body::to_bytes(resp.into_body()).await.unwrap();
            let json: Value = serde_json::from_slice(&bytes).unwrap_or_else(|e| {
                panic!(
                    "响应体应为 JSON: {e}, raw={}",
                    String::from_utf8_lossy(&bytes)
                )
            });
            (status, ctype, json)
        })
    }

    /// GET /health：200 + success 包装 + 配置回显
    #[test]
    fn health_returns_200_with_config_echo() {
        let (status, ctype, body) = drive(Method::GET, "/health", Body::empty());
        assert_eq!(status, StatusCode::OK);
        assert!(ctype.starts_with("application/json"), "ctype = {ctype}");
        assert_eq!(body["success"], json!(true));
        assert_eq!(body["data"]["name"], json!("路由单元测试节点"));
        assert_eq!(body["data"]["port"], json!(19998));
    }

    /// 未知路径：404 + error "Not Found"
    #[test]
    fn unknown_path_returns_404_not_found() {
        for uri in ["/", "/nope", "/node", "/node/callx", "/HEALTH", "/health/extra"] {
            let (status, ctype, body) = drive(Method::GET, uri, Body::empty());
            assert_eq!(status, StatusCode::NOT_FOUND, "路径 {uri} 应 404");
            assert!(ctype.starts_with("application/json"));
            assert_eq!(body["success"], json!(false));
            assert_eq!(body["error"], json!("Not Found"));
        }
    }

    /// 方法不匹配一律落到 404 兜底分支（路由按 (method, path) 精确匹配）
    #[test]
    fn wrong_method_falls_through_to_404() {
        // /health 只接受 GET
        let (status, _, body) = drive(Method::POST, "/health", Body::from("{}"));
        assert_eq!(status, StatusCode::NOT_FOUND);
        assert_eq!(body["error"], json!("Not Found"));
        // /node/call 与 /node/upload 只接受 POST（不触达 media/upload 处理器的 GET 分支）
        for (method, uri) in [
            (Method::GET, "/node/call"),
            (Method::PUT, "/node/call"),
            (Method::DELETE, "/node/call"),
            (Method::GET, "/node/upload"),
            (Method::PUT, "/node/upload"),
            (Method::DELETE, "/node/media"),
            (Method::POST, "/node/media"),
        ] {
            let (status, _, body) = drive(method, uri, Body::from("{}"));
            assert_eq!(status, StatusCode::NOT_FOUND, "{uri} 非约定方法应 404");
            assert_eq!(body["success"], json!(false));
        }
    }

    /// POST /node/call 坏 JSON：HTTP 200 但 success=false，错误文案含「解析请求失败」
    #[test]
    fn node_call_malformed_json_body_returns_parse_error() {
        for raw in [
            "", // 空 body
            "{", // 截断 JSON
            r#"{"action": "#,
            "not json at all",
            r#"{"action": 123}"#, // action 类型错误（应为字符串）
            r#"[1,2,3]"#,         // 顶层不是对象
        ] {
            let (status, _, body) = drive(Method::POST, "/node/call", Body::from(raw));
            assert_eq!(status, StatusCode::OK, "解析错误应以 200 + success:false 返回");
            assert_eq!(body["success"], json!(false), "raw = {raw}");
            let err = body["error"].as_str().unwrap_or_default();
            assert!(err.contains("解析请求失败"), "raw = {raw}, err = {err}");
        }
    }

    /// POST /node/call 缺 action 字段：serde 反序列化失败同样走解析错误分支
    #[test]
    fn node_call_missing_action_field_is_parse_error() {
        let (_, _, body) = drive(Method::POST, "/node/call", Body::from(r#"{"params":{}}"#));
        assert_eq!(body["success"], json!(false));
        assert!(body["error"].as_str().unwrap().contains("解析请求失败"));
    }

    /// POST /node/call 合法 JSON + 未知 action：分发层兜底错误（不触 DB）
    #[test]
    fn node_call_unknown_action_returns_unsupported_error() {
        let (status, _, body) = drive(
            Method::POST,
            "/node/call",
            Body::from(r#"{"action":"no_such_action_xyz","params":{"a":1}}"#),
        );
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["success"], json!(false));
        let err = body["error"].as_str().unwrap();
        assert!(err.contains("不支持的动作"), "err = {err}");
        assert!(err.contains("no_such_action_xyz"));
    }

    /// POST /node/call 纯内存动作 ping：success=true 且 data.pong=true
    #[test]
    fn node_call_ping_action_returns_pong() {
        let (status, ctype, body) = drive(Method::POST, "/node/call", Body::from(r#"{"action":"ping"}"#));
        assert_eq!(status, StatusCode::OK);
        assert!(ctype.starts_with("application/json"));
        assert_eq!(body["success"], json!(true));
        assert_eq!(body["data"], json!({"pong": true}));
        // params 缺省（#[serde(default)]）应补 Null 而不报错
        let (_, _, body2) = drive(Method::POST, "/node/call", Body::from(r#"{"action":"get_status"}"#));
        assert_eq!(body2["data"]["name"], json!("路由单元测试节点"));
    }
}
