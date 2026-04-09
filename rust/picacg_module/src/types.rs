/// PicACG 模块数据类型
use serde::{Deserialize, Serialize};

/// 代理类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum PicacgProxyType {
    None,
    Http,
    Socks5,
}

/// 代理配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PicacgProxyConfig {
    pub proxy_type: PicacgProxyType,
    pub url: String,
}

impl Default for PicacgProxyConfig {
    fn default() -> Self {
        PicacgProxyConfig {
            proxy_type: PicacgProxyType::None,
            url: String::new(),
        }
    }
}
