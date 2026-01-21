/// 证书管理模块 - 处理CA证书生成、安装和动态证书解析
use rcgen::{
    BasicConstraints, Certificate as RcgenCert, CertificateParams, DistinguishedName, DnType, IsCa,
    KeyUsagePurpose,
};
use rustls::{
    server::ClientHello, server::ResolvesServerCert, sign::CertifiedKey, Certificate as RustlsCert,
    PrivateKey,
};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};

/// 证书解析器 - 动态生成和缓存服务器证书
pub struct CertResolver {
    ca_rcgen: RcgenCert,
    cache: RwLock<HashMap<String, Arc<CertifiedKey>>>,
}

impl CertResolver {
    pub fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        println!("[证书] 生成新的CA证书...");

        let mut params = CertificateParams::new(vec!["Skill Capture Client Root CA".to_string()]);

        let mut dn = DistinguishedName::new();
        dn.push(DnType::CountryName, "CN");
        dn.push(DnType::StateOrProvinceName, "Zhejiang");
        dn.push(DnType::LocalityName, "Hangzhou");
        dn.push(DnType::OrganizationName, "www.everyselect.com");
        dn.push(DnType::OrganizationalUnitName, "Skill Client");
        dn.push(DnType::CommonName, "Skill Capture Client Root CA");
        params.distinguished_name = dn;

        params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
        ];
        params.extended_key_usages = vec![
            rcgen::ExtendedKeyUsagePurpose::ServerAuth,
            rcgen::ExtendedKeyUsagePurpose::ClientAuth,
        ];

        let ca_rcgen = RcgenCert::from_params(params)?;
        println!("[证书] CA证书生成成功");

        // 保存CA证书
        let key_dir = PathBuf::from("key");
        std::fs::create_dir_all(&key_dir).ok();
        let ca_cert_path = key_dir.join("generated_ca.crt");
        let ca_cert_pem = ca_rcgen.serialize_pem()?;

        if let Err(e) = std::fs::write(&ca_cert_path, &ca_cert_pem) {
            eprintln!("[警告] 无法保存CA证书: {}", e);
        } else {
            println!("[证书] CA证书已保存到: {}", ca_cert_path.display());

            // 尝试自动安装CA证书
            match install_ca_certificate(&ca_cert_path) {
                Ok(msg) => println!("[证书] {}", msg),
                Err(e) => eprintln!("[证书] 自动安装失败: {}，请手动安装", e),
            }
        }

        Ok(Self {
            ca_rcgen,
            cache: RwLock::new(HashMap::new()),
        })
    }

    fn generate_cert(&self, name: &str) -> Option<Arc<CertifiedKey>> {
        let mut params = CertificateParams::new(vec![name.to_string()]);
        let leaf = RcgenCert::from_params(params).ok()?;
        let leaf_der = leaf.serialize_der_with_signer(&self.ca_rcgen).ok()?;
        let leaf_priv = leaf.serialize_private_key_der();
        let signing_key = rustls::sign::any_supported_type(&PrivateKey(leaf_priv)).ok()?;
        let signing_key = Arc::from(signing_key);

        let ca_cert_der = self.ca_rcgen.serialize_der().ok()?;
        let mut chain = vec![RustlsCert(leaf_der)];
        chain.push(RustlsCert(ca_cert_der));

        let ck = CertifiedKey::new(chain, signing_key);
        Some(Arc::new(ck))
    }
}

impl ResolvesServerCert for CertResolver {
    fn resolve(&self, client_hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        let sni = client_hello.server_name()?;
        let name = sni.to_string();
        if let Some(c) = self.cache.read().unwrap().get(&name) {
            return Some(c.clone());
        }
        if let Some(ck) = self.generate_cert(&name) {
            self.cache.write().unwrap().insert(name.clone(), ck.clone());
            return Some(ck);
        }
        None
    }
}

/// 安装CA证书到系统信任存储
fn install_ca_certificate(cert_path: &PathBuf) -> Result<String, String> {
    let cert_path_str = cert_path.to_string_lossy().to_string();

    #[cfg(target_os = "windows")]
    {
        // Windows: 使用 certutil 命令（需要管理员权限）
        use std::process::Command;

        println!("[证书] 尝试安装CA证书到Windows系统（需要管理员权限）...");
        let output = Command::new("certutil")
            .args(&["-enterprise", "-f", "-AddStore", "Root", &cert_path_str])
            .output()
            .map_err(|e| format!("执行certutil失败: {}", e))?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            Ok(format!("CA证书安装成功\n{}", stdout))
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            // 检查是否是权限问题
            if stderr.contains("需要管理员权限")
                || stderr.contains("拒绝访问")
                || stderr.contains("ERROR_ACCESS_DENIED")
            {
                Err(format!(
                    "需要管理员权限。请以管理员身份运行以下命令安装CA证书:\ncertutil -enterprise -f -AddStore Root \"{}\"\n\n或者手动双击证书文件安装到\"受信任的根证书颁发机构\"",
                    cert_path_str
                ))
            } else {
                Err(format!("certutil执行失败: {}", stderr))
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        // macOS: 使用 security 命令
        use std::process::Command;

        println!("[证书] 正在安装CA证书到macOS钥匙串...");
        println!("[证书] 提示：可能需要输入管理员密码");

        let output = Command::new("security")
            .args(&[
                "add-trusted-cert",
                "-d",
                "-r",
                "trustRoot",
                "-k",
                "/Library/Keychains/System.keychain",
                &cert_path_str,
            ])
            .output()
            .map_err(|e| format!("执行security命令失败: {}", e))?;

        if output.status.success() {
            Ok("CA证书安装成功".to_string())
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(format!("security命令执行失败: {}\n\n请手动运行:\nsudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \"{}\"", stderr, cert_path_str))
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Err(format!(
            "当前平台不支持自动安装，请手动安装证书: {}",
            cert_path_str
        ))
    }
}
