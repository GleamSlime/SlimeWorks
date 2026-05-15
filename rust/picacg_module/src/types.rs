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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proxy_type_serde_round_trip() {
        let types = [PicAcgProxyType::None, PicAcgProxyType::Http, PicAcgProxyType::Socks5];
        for t in &types {
            let json = serde_json::to_string(t).expect("serialize");
            let restored: PicAcgProxyType = serde_json::from_str(&json).expect("deserialize");
            assert_eq!(&restored, t);
        }
    }

    #[test]
    fn proxy_config_default() {
        let config = PicAcgProxyConfig::default();
        assert_eq!(config.proxy_type, PicAcgProxyType::None);
        assert_eq!(config.url, "");
    }

    #[test]
    fn proxy_config_serde_round_trip() {
        let config = PicAcgProxyConfig {
            proxy_type: PicAcgProxyType::Socks5,
            url: "socks5://127.0.0.1:1080".to_string(),
        };
        let json = serde_json::to_string(&config).expect("serialize");
        let restored: PicAcgProxyConfig = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(restored.proxy_type, config.proxy_type);
        assert_eq!(restored.url, config.url);
    }
}
