use flutter_rust_bridge::frb;
use path_provider::path_provider;

use super::module_loader::CaptureProxyModule;

/// 捕获的数据类型
#[derive(Debug, Clone)]
pub enum CaptureType {
    Video,
    Image,
    Json,
    Javascript,
}

/// 捕获统计数据
#[derive(Debug, Clone)]
pub struct CaptureStats {
    pub total: i32,
    pub videos: i32,
    pub images: i32,
    pub json: i32,
    pub javascript: i32,
}

/// 获取应用安装目录
fn get_install_dir() -> Result<String, String> {
    // TODO: 从配置或环境变量获取
    // 临时使用固定路径，实际应该从 path_provider 获取
    #[cfg(target_os = "windows")]
    {
        let appdata = std::env::var("APPDATA").unwrap_or_else(|_| "C:\\ProgramData".to_string());
        Ok(format!("{}\\SlimeWorks", appdata))
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        Ok("/tmp/slimeworks".to_string())
    }
}

/// 启动代理服务器（通过动态模块）
#[frb(sync)]
pub fn start_capture_proxy(port: u16, install_dir: Option<String>) -> Result<String, String> {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::start(port, &dir)
}

/// 停止代理服务器
#[frb(sync)]
pub fn stop_capture_proxy(install_dir: Option<String>) -> Result<String, String> {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::stop(&dir)
}

/// 获取捕获状态
#[frb(sync)]
pub fn is_proxy_running(install_dir: Option<String>) -> bool {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::is_running(&dir).unwrap_or(false)
}

/// 获取所有捕获的视频链接
#[frb(sync)]
pub fn get_captured_videos(install_dir: Option<String>) -> Vec<String> {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::get_videos(&dir).unwrap_or_default()
}

/// 获取所有捕获的图片链接
#[frb(sync)]
pub fn get_captured_images(install_dir: Option<String>) -> Vec<String> {
    // TODO: 需要在 C ABI 中添加对应函数
    Vec::new()
}

/// 获取所有捕获的JSON数据
#[frb(sync)]
pub fn get_captured_json(install_dir: Option<String>) -> Vec<String> {
    // TODO: 需要在 C ABI 中添加对应函数
    Vec::new()
}

/// 获取所有捕获的JavaScript文件
#[frb(sync)]
pub fn get_captured_javascript(install_dir: Option<String>) -> Vec<String> {
    // TODO: 需要在 C ABI 中添加对应函数
    Vec::new()
}

/// 清除所有捕获的数据
#[frb(sync)]
pub fn clear_captured_data(install_dir: Option<String>) -> Result<(), String> {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::clear_data(&dir)
}

/// 获取捕获统计
#[frb(sync)]
pub fn get_capture_stats(install_dir: Option<String>) -> Option<CaptureStats> {
    // TODO: 需要在 C ABI 中添加对应函数
    Some(CaptureStats {
        total: 0,
        videos: 0,
        images: 0,
        json: 0,
        javascript: 0,
    })
}

/// 安装CA证书
#[frb(sync)]
pub fn install_ca_certificate(password: String, install_dir: Option<String>) -> Result<String, String> {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::install_certificate(&password, &dir)?;
    Ok("证书安装成功".to_string())
}

/// 检查CA证书是否已安装
#[frb(sync)]
pub fn is_ca_certificate_installed(install_dir: Option<String>) -> bool {
    let dir = install_dir.unwrap_or_else(|| get_install_dir().unwrap());
    CaptureProxyModule::is_certificate_installed(&dir).unwrap_or(false)
}

/// 检查是否以管理员身份运行（Windows）
#[frb(sync)]
#[cfg(target_os = "windows")]
pub fn is_running_as_administrator() -> bool {
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processthreadsapi::{GetCurrentProcess, OpenProcessToken};
    use winapi::um::securitybaseapi::GetTokenInformation;
    use winapi::um::winnt::{TokenElevation, TOKEN_ELEVATION, TOKEN_QUERY};

    unsafe {
        let mut token_handle = std::ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token_handle) == 0 {
            return false;
        }

        let mut elevation = TOKEN_ELEVATION { TokenIsElevated: 0 };
        let mut return_length = 0;

        let result = GetTokenInformation(
            token_handle,
            TokenElevation,
            &mut elevation as *mut _ as *mut _,
            std::mem::size_of::<TOKEN_ELEVATION>() as u32,
            &mut return_length,
        );

        CloseHandle(token_handle);

        result != 0 && elevation.TokenIsElevated != 0
    }
}

#[cfg(not(target_os = "windows"))]
pub fn is_running_as_administrator() -> bool {
    false
}
