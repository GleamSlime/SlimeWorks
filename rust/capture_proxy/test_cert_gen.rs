use capture_proxy::CertResolver;
use std::fs;

fn main() {
    println!("测试证书生成...");

    // 创建CertResolver
    let resolver = match CertResolver::new() {
        Ok(r) => r,
        Err(e) => {
            eprintln!("创建CertResolver失败: {}", e);
            return;
        }
    };

    println!("✅ CertResolver创建成功");

    // 测试生成一个叶子证书
    println!("\n测试为 test.example.com 生成证书...");

    // 由于generate_cert是私有的，我们无法直接测试
    // 但可以通过检查CA证书来验证

    let ca_cert_path = dirs::home_dir()
        .unwrap()
        .join(".slime_works")
        .join("key")
        .join("generated_ca.crt");

    let ca_cert = fs::read_to_string(&ca_cert_path).unwrap();
    println!("\nCA证书内容:");
    println!("{}", ca_cert);
}
