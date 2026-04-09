/// PicACG 模块错误类型
use std::fmt;

#[derive(Debug)]
pub enum PicAcgError {
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

impl fmt::Display for PicAcgError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PicAcgError::Network(msg) => write!(f, "网络错误: {}", msg),
            PicAcgError::Parse(msg) => write!(f, "解析错误: {}", msg),
            PicAcgError::Api(code, msg) => write!(f, "API错误 [{}]: {}", code, msg),
            PicAcgError::Unauthorized => write!(f, "未登录或Token已过期"),
            PicAcgError::Other(msg) => write!(f, "错误: {}", msg),
        }
    }
}

impl From<reqwest::Error> for PicAcgError {
    fn from(e: reqwest::Error) -> Self {
        PicAcgError::Network(e.to_string())
    }
}

impl From<serde_json::Error> for PicAcgError {
    fn from(e: serde_json::Error) -> Self {
        PicAcgError::Parse(e.to_string())
    }
}

impl From<anyhow::Error> for PicAcgError {
    fn from(e: anyhow::Error) -> Self {
        PicAcgError::Other(e.to_string())
    }
}

pub type PicAcgResult<T> = Result<T, PicAcgError>;
