/// PicACG 模块错误类型
use std::fmt;

#[derive(Debug)]
pub enum PicacgError {
    /// 网络请求错误
    Network(String),
    /// JSON 解析错误
    Parse(String),
    /// 服务器返回错误（code != 200）
    Api(u32, String),
    /// 未登录
    Unauthorized,
    /// 其他错误
    Other(String),
}

impl fmt::Display for PicacgError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PicacgError::Network(msg) => write!(f, "网络错误: {}", msg),
            PicacgError::Parse(msg) => write!(f, "解析错误: {}", msg),
            PicacgError::Api(code, msg) => write!(f, "API错误 [{}]: {}", code, msg),
            PicacgError::Unauthorized => write!(f, "未登录或Token已过期"),
            PicacgError::Other(msg) => write!(f, "错误: {}", msg),
        }
    }
}

impl From<reqwest::Error> for PicacgError {
    fn from(e: reqwest::Error) -> Self {
        PicacgError::Network(e.to_string())
    }
}

impl From<serde_json::Error> for PicacgError {
    fn from(e: serde_json::Error) -> Self {
        PicacgError::Parse(e.to_string())
    }
}

impl From<anyhow::Error> for PicacgError {
    fn from(e: anyhow::Error) -> Self {
        PicacgError::Other(e.to_string())
    }
}

pub type PicacgResult<T> = Result<T, PicacgError>;
