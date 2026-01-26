/// 测试动态库加载
use libloading::{Library, Symbol};
use std::os::raw::{c_char, c_int};

#[repr(C)]
struct ModuleInfo {
    name: *const c_char,
    version: *const c_char,
    api_version: u32,
}

fn main() {
    println!("开始测试 capture_proxy.dll 加载...\n");
    
    unsafe {
        let lib_path = r"H:\SlimeWorks\rust\target\release\capture_proxy.dll";
        println!("加载库: {}", lib_path);
        
        let lib = match Library::new(lib_path) {
            Ok(lib) => {
                println!("✅ 成功加载库\n");
                lib
            }
            Err(e) => {
                eprintln!("❌ 加载库失败: {}", e);
                return;
            }
        };
        
        // 测试 module_init
        println!("测试 module_init():");
        let module_init: Symbol<unsafe extern "C" fn() -> *const ModuleInfo> = 
            match lib.get(b"module_init") {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("❌ 找不到 module_init 函数: {}", e);
                    return;
                }
            };
        
        let info = module_init();
        if !info.is_null() {
            let name = std::ffi::CStr::from_ptr((*info).name).to_str().unwrap();
            let version = std::ffi::CStr::from_ptr((*info).version).to_str().unwrap();
            println!("  模块名称: {}", name);
            println!("  模块版本: {}", version);
            println!("  API 版本: {}", (*info).api_version);
            println!("✅ module_init 测试通过\n");
        } else {
            eprintln!("❌ module_init 返回 null");
            return;
        }
        
        // 测试其他函数
        let test_functions = [
            "proxy_start",
            "proxy_stop",
            "proxy_is_running",
            "proxy_get_video_count",
            "proxy_get_videos_json",
            "proxy_get_all_items_json",
            "proxy_clear_items",
            "proxy_free_string",
            "proxy_install_certificate",
            "proxy_is_certificate_installed",
        ];
        
        println!("检查导出的函数:");
        for func_name in &test_functions {
            match lib.get::<Symbol<unsafe extern "C" fn()>>(func_name.as_bytes()) {
                Ok(_) => println!("  ✅ {}", func_name),
                Err(_) => println!("  ❌ {} (未找到)", func_name),
            }
        }
        
        println!("\n✅ 所有测试完成！");
    }
}
