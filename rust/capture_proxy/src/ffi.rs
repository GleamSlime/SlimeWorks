/// C ABI 导出接口
///
/// 这些函数通过 C ABI 导出，供主应用动态加载调用
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::sync::Mutex;

lazy_static::lazy_static! {
    static ref PROXY_RUNTIME: Mutex<Option<tokio::runtime::Runtime>> = Mutex::new(None);
}

/// 模块信息结构
#[repr(C)]
pub struct ModuleInfo {
    pub name: *const c_char,
    pub version: *const c_char,
    pub api_version: u32,
}

/// 初始化模块，返回模块信息
#[no_mangle]
pub extern "C" fn module_init() -> *const ModuleInfo {
    let name = CString::new("capture_proxy").unwrap();
    let version = CString::new("0.1.0").unwrap();

    let info = Box::new(ModuleInfo {
        name: name.into_raw(),
        version: version.into_raw(),
        api_version: 1,
    });

    Box::into_raw(info)
}

/// 启动代理服务器
///
/// # 参数
/// * `port` - 代理端口
///
/// # 返回值
/// * 0: 成功
/// * -1: 失败（已在运行）
/// * -2: 其他错误
#[no_mangle]
pub extern "C" fn proxy_start(port: u16) -> c_int {
    let mut runtime_guard = PROXY_RUNTIME.lock().unwrap();

    if runtime_guard.is_some() {
        eprintln!("代理已经在运行");
        return -1;
    }

    // 创建运行时
    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(e) => {
            eprintln!("创建运行时失败: {}", e);
            return -2;
        }
    };

    // 启动代理服务器
    rt.spawn(async move {
        if let Err(e) = crate::start_proxy_server(port).await {
            eprintln!("代理服务器错误: {}", e);
        }
    });

    *runtime_guard = Some(rt);
    0
}

/// 停止代理服务器
///
/// # 返回值
/// * 0: 成功
/// * -1: 代理未运行
#[no_mangle]
pub extern "C" fn proxy_stop() -> c_int {
    let mut runtime_guard = PROXY_RUNTIME.lock().unwrap();

    if runtime_guard.is_none() {
        eprintln!("代理未运行");
        return -1;
    }

    // 清除系统代理
    if let Some(rt) = runtime_guard.as_ref() {
        rt.block_on(async {
            let _ = crate::system_proxy::close_proxy().await;
        });
    }

    *runtime_guard = None;
    0
}

/// 检查代理是否正在运行
#[no_mangle]
pub extern "C" fn proxy_is_running() -> c_int {
    let runtime_guard = PROXY_RUNTIME.lock().unwrap();
    if runtime_guard.is_some() {
        1
    } else {
        0
    }
}

/// 获取捕获的视频数量
#[no_mangle]
pub extern "C" fn proxy_get_video_count() -> c_int {
    let items = crate::get_captured_items();
    items
        .iter()
        .filter(|item| item.content_type.starts_with("video/"))
        .count() as c_int
}

/// 获取捕获的视频 URL（JSON 格式）
///
/// 调用者需要调用 proxy_free_string() 释放内存
#[no_mangle]
pub extern "C" fn proxy_get_videos_json() -> *mut c_char {
    let items = crate::get_captured_items();
    let videos: Vec<&str> = items
        .iter()
        .filter(|item| item.content_type.starts_with("video/"))
        .map(|item| item.url.as_str())
        .collect();

    match serde_json::to_string(&videos) {
        Ok(json) => match CString::new(json) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// 获取所有捕获数据（JSON 格式）
#[no_mangle]
pub extern "C" fn proxy_get_all_items_json() -> *mut c_char {
    let items = crate::get_captured_items();

    match serde_json::to_string(&items) {
        Ok(json) => match CString::new(json) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// 清除所有捕获的数据
#[no_mangle]
pub extern "C" fn proxy_clear_items() {
    crate::clear_captured_items();
}

/// 释放由模块分配的字符串内存
#[no_mangle]
pub extern "C" fn proxy_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// 获取模块版本信息
#[no_mangle]
pub extern "C" fn proxy_get_version() -> *const c_char {
    b"0.1.0\0".as_ptr() as *const c_char
}

/// 安装 CA 证书（带密码，用于 macOS）
///
/// # 参数
/// * `password` - 系统密码（macOS 需要）
///
/// # 返回值
/// * 0: 成功
/// * -1: 失败
#[no_mangle]
pub extern "C" fn proxy_install_certificate(password: *const c_char) -> c_int {
    let password_str = if password.is_null() {
        String::new()
    } else {
        unsafe {
            match CStr::from_ptr(password).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return -1,
            }
        }
    };

    match crate::install_ca_certificate_with_password(&password_str) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// 检查 CA 证书是否已安装
#[no_mangle]
pub extern "C" fn proxy_is_certificate_installed() -> c_int {
    if crate::is_ca_certificate_installed().unwrap_or(false) {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_module_init() {
        let info = module_init();
        assert!(!info.is_null());
        unsafe {
            assert_eq!((*info).api_version, 1);
        }
    }

    #[test]
    fn test_proxy_lifecycle() {
        // 初始状态
        assert_eq!(proxy_is_running(), 0);

        // 启动
        let result = proxy_start(18433);
        assert_eq!(result, 0);
        assert_eq!(proxy_is_running(), 1);

        // 重复启动应该失败
        let result = proxy_start(18433);
        assert_eq!(result, -1);

        // 停止
        let result = proxy_stop();
        assert_eq!(result, 0);
        assert_eq!(proxy_is_running(), 0);
    }
}
