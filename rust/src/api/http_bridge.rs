/// HTTP Bridge API接口
use flutter_rust_bridge::frb;

/// 获取已注册的HTTP Bridge处理器列表
#[frb(sync)]
pub fn get_registered_handlers() -> Vec<(String, String)> {
    // 在同步上下文中，我们返回一个已知的列表
    // 实际的注册在init_http_bridge中异步完成
    vec![
        ("novel_reader".to_string(), "get_all_novels".to_string()),
        ("novel_reader".to_string(), "add_novel".to_string()),
        (
            "novel_reader".to_string(),
            "get_chapter_content".to_string(),
        ),
        ("novel_reader".to_string(), "search_in_novel".to_string()),
        (
            "novel_reader".to_string(),
            "update_reading_progress".to_string(),
        ),
    ]
}

/// 调用HTTP Bridge处理器
#[frb(sync)]
pub fn call_handler(module: String, function: String, params: String) -> Result<String, String> {
    // 解析JSON参数
    let params_json: serde_json::Value =
        serde_json::from_str(&params).map_err(|e| format!("Invalid JSON: {}", e))?;

    // 使用tokio runtime调用异步函数
    let runtime =
        tokio::runtime::Runtime::new().map_err(|e| format!("Failed to create runtime: {}", e))?;

    runtime.block_on(async {
        match http_bridge::call_handler(module, function, params_json).await {
            Ok(result) => Ok(serde_json::to_string(&result)
                .map_err(|e| format!("Failed to serialize result: {}", e))?),
            Err(e) => Err(e),
        }
    })
}

/// 初始化HTTP Bridge（注册所有接口）
#[frb(sync)]
pub fn init_http_bridge() -> Result<bool, String> {
    let runtime =
        tokio::runtime::Runtime::new().map_err(|e| format!("Failed to create runtime: {}", e))?;

    runtime.block_on(async {
        novel_reader::http_bridge_register::register_all_handlers()
            .await
            .map_err(|e| format!("Failed to register handlers: {}", e))?;

        Ok(true)
    })
}

// ── 节点服务器 API ─────────────────────────────────────────────────────────

/// 启动本地节点服务器（仅桌面端）
///
/// - host: 监听地址，通常为 "0.0.0.0"
/// - port: 监听端口，默认 17888
/// - name: 节点名称
#[frb(sync)]
pub fn start_node_server(host: String, port: u16, name: String) -> Result<(), String> {
    crate::node_server::start_node_server(host, port, name)
}

/// 停止本地节点服务器
#[frb(sync)]
pub fn stop_node_server() -> Result<(), String> {
    crate::node_server::stop_node_server()
}

/// 检查节点服务器是否在运行
#[frb(sync)]
pub fn is_node_server_running() -> bool {
    crate::node_server::is_node_server_running()
}
