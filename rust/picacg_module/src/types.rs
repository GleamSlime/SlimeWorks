/// PicACG 模块数据类型
use serde::{Deserialize, Serialize};

/// 代理类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PicAcgProxyType {
    None,
    Http,
    Socks5,
}

/// 代理配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PicAcgProxyConfig {
    pub proxy_type: PicAcgProxyType,
    pub url: String,
}

impl Default for PicAcgProxyConfig {
    fn default() -> Self {
        PicAcgProxyConfig {
            proxy_type: PicAcgProxyType::None,
            url: String::new(),
        }
    }
}
