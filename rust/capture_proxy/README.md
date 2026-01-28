# Capture Proxy - 代码结构说明

## 概述

Capture Proxy 是一个支持 MITM（中间人）拦截的 HTTP/HTTPS 代理服务器，能够捕获和分析网络流量。

## 模块结构

代码已按功能拆分为多个独立模块，便于维护和扩展：

### 核心模块

#### `lib.rs` - 主入口

- **职责**：库的主入口文件，协调各模块协同工作
- **公共API**：
  - `start_proxy_server(port)` - 启动代理服务器
  - `CapturedItem` - 捕获的数据项结构
  - 数据操作函数（通过重新导出）
- **功能**：
  - 初始化TLS配置
  - 创建HTTP服务器
  - 设置系统代理

#### `capture.rs` - 数据捕获

- **职责**：管理捕获的数据存储
- **公共API**：
  - `init_capture_storage()` - 初始化存储
  - `add_captured_item(url, type, content)` - 添加捕获项
  - `get_captured_items()` - 获取所有捕获项
  - `clear_captured_items()` - 清空捕获数据
- **数据结构**：
  - `CapturedItem` - 存储URL、内容类型和内容

#### `cert.rs` - 证书管理

- **职责**：CA证书生成、安装和动态证书解析
- **核心组件**：
  - `CertResolver` - 实现 `ResolvesServerCert` trait
  - 动态为每个SNI域名生成证书
  - 证书缓存机制
- **功能**：
  - 生成自签名CA证书
  - 保存证书到 `key/generated_ca.crt`
  - 自动安装到系统（Windows/macOS）
  - 运行时动态生成域名证书

#### `mitm.rs` - MITM拦截

- **职责**：拦截和分析HTTPS流量
- **公共API**：
  - `handle_connect_mitm()` - 处理CONNECT请求
- **功能**：
  - 与客户端建立TLS连接
  - 与上游服务器建立TLS连接
  - 双向转发流量
  - 解析HTTP请求/响应头
  - 根据Content-Type识别资源类型
- **支持的资源类型**：
  - 视频（video/\*）
  - 图片（image/\*）
  - JSON（application/json）
  - JavaScript（_javascript_）

#### `server.rs` - HTTP代理处理

- **职责**：处理HTTP代理请求和CONNECT隧道
- **公共API**：
  - `proxy_handler()` - 主请求处理器
- **功能**：
  - 处理CONNECT请求
  - 支持普通隧道模式（无MITM）
  - 支持MITM拦截模式
  - 处理普通HTTP请求

#### `system_proxy2.rs` - 系统代理

- **职责**：设置和清除系统代理配置
- **功能**：
  - Windows注册表操作
  - macOS/Linux环境变量设置

#### `main.rs` - 独立可执行

- **职责**：提供独立运行的命令行工具
- **功能**：
  - 解析命令行参数
  - 启动代理服务
  - 处理Ctrl+C退出

## 数据流

```
1. 客户端请求 → server.rs::proxy_handler()
   ├─ CONNECT请求 → mitm.rs::handle_connect_mitm()
   │  ├─ 使用 cert.rs::CertResolver 动态生成证书
   │  ├─ 建立TLS连接（客户端和上游）
   │  ├─ 解析HTTP头
   │  └─ capture.rs::add_captured_item() 存储数据
   └─ 普通HTTP请求 → 直接处理

2. 捕获的数据存储在 capture.rs::CAPTURED_ITEMS
3. Flutter通过FRB调用获取数据
```

## 编译和使用

### 作为库使用（Flutter集成）

```rust
use capture_proxy::{start_proxy_server, get_captured_items, CapturedItem};

// 在异步环境中启动
tokio::spawn(async {
    start_proxy_server(8433).await.unwrap();
});

// 获取捕获的数据
let items = get_captured_items();
```

### 作为独立工具运行

```bash
# 编译
cargo build --release
cargo build --release --lib

# 运行（默认端口8433）
cargo run

# 或直接运行可执行文件
./target/release/capture_proxy
```

## 扩展指南

### 添加新的资源类型检测

在 [`mitm.rs`](mitm.rs) 的 `up_to_client` 任务中添加检测逻辑：

```rust
else if ctype_value.to_lowercase().contains("application/xml") {
    println!("[捕获] XML: {}", url);
    add_captured_item(url.clone(), "xml".to_string(), None);
}
```

### 添加内容过滤

在 [`capture.rs`](capture.rs) 的 `add_captured_item` 函数中添加过滤逻辑：

```rust
pub fn add_captured_item(url: String, content_type: String, content: Option<String>) {
    // 过滤规则
    if url.contains("advertisement") {
        return; // 跳过广告
    }

    if let Some(ref mut items) = *CAPTURED_ITEMS.lock().unwrap() {
        items.push(CapturedItem { url, content_type, content });
    }
}
```

### 自定义证书配置

修改 [`cert.rs`](cert.rs) 中的 `CertResolver::new()`：

```rust
let mut dn = DistinguishedName::new();
dn.push(DnType::CountryName, "US");  // 修改国家
dn.push(DnType::OrganizationName, "Your Company");  // 修改组织
```

## 依赖关系

```
lib.rs
├── capture.rs (独立)
├── cert.rs (依赖: rcgen, rustls)
├── mitm.rs (依赖: capture.rs)
├── server.rs (依赖: cert.rs, mitm.rs)
└── system_proxy2.rs (独立)
```

## 注意事项

1. **证书安装**：首次运行需要管理员权限安装CA证书
2. **系统代理**：程序会自动设置系统代理，退出时需清除
3. **线程安全**：使用 `Mutex` 和 `RwLock` 保证多线程安全
4. **内存管理**：捕获数据存储在内存中，大量数据可能占用较多内存

## 性能优化建议

1. **证书缓存**：`CertResolver` 使用 `RwLock<HashMap>` 缓存生成的证书
2. **异步处理**：使用 `tokio::spawn` 异步处理每个连接
3. **定期清理**：建议定期调用 `clear_captured_items()` 清理旧数据
