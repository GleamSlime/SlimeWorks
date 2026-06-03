/// Manga 模块数据类型
use serde::{Deserialize, Serialize};

/// 代理类型
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MangaProxyType {
    None,
    Http,
    Socks5,
}

/// 代理配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MangaProxyConfig {
    pub proxy_type: MangaProxyType,
    pub url: String,
}

impl Default for MangaProxyConfig {
    fn default() -> Self {
        MangaProxyConfig {
            proxy_type: MangaProxyType::None,
            url: String::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proxy_type_serde_round_trip() {
        let types = [MangaProxyType::None, MangaProxyType::Http, MangaProxyType::Socks5];
        for t in &types {
            let json = serde_json::to_string(t).expect("serialize");
            let restored: MangaProxyType = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, t);
        }
    }

    #[test]
    fn proxy_config_default() {
        let config = MangaProxyConfig::default();
        assert_eq!(config.proxy_type, MangaProxyType::None);
        assert_eq!(config.url, "");
    }

    #[test]
    fn proxy_config_serde_round_trip() {
        let config = MangaProxyConfig {
            proxy_type: MangaProxyType::Socks5,
            url: "socks5://127.0.0.1:1080".to_string(),
        };
        let json = serde_json::to_string(&config).expect("serialize");
        let restored: MangaProxyConfig = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.proxy_type, config.proxy_type);
        assert_eq!(restored.url, config.url);
    }
}
