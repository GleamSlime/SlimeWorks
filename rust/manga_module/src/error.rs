/// Manga 模块错误类型
use std::fmt;

#[derive(Debug)]
pub enum MangaError {
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

impl fmt::Display for MangaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            MangaError::Network(msg) => write!(f, "网络错误: {}", msg),
            MangaError::Parse(msg) => write!(f, "解析错误: {}", msg),
            MangaError::Api(code, msg) => write!(f, "API错误 [{}]: {}", code, msg),
            MangaError::Unauthorized => write!(f, "未登录或Token已过期"),
            MangaError::Other(msg) => write!(f, "错误: {}", msg),
        }
    }
}

impl From<reqwest::Error> for MangaError {
    fn from(e: reqwest::Error) -> Self {
        MangaError::Network(e.to_string())
    }
}

impl From<serde_json::Error> for MangaError {
    fn from(e: serde_json::Error) -> Self {
        MangaError::Parse(e.to_string())
    }
}

impl From<anyhow::Error> for MangaError {
    fn from(e: anyhow::Error) -> Self {
        MangaError::Other(e.to_string())
    }
}

pub type MangaResult<T> = Result<T, MangaError>;
