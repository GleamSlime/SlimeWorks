fn main() {
    // build script 里的 cfg! 判的是宿主平台，在 macOS 上交叉编译 Android 时
    // target_os="macos" 依然为真，会把 framework 链接参数带给非 Apple 目标
    // （rustc 报 "library kind `framework` is only supported on Apple targets"）。
    // 因此必须读环境变量来判定真正的目标平台。
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "macos" || target_os == "ios" {
        println!("cargo:rustc-link-lib=framework=SystemConfiguration");
    }
    println!("cargo:rerun-if-changed=build.rs");
}
