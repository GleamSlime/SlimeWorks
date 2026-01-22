/// 证书管理模块 - 处理CA证书生成、安装和动态证书解析
use rcgen::{Certificate as RcgenCert, CertificateParams, KeyPair};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::{server::ClientHello, server::ResolvesServerCert, sign::CertifiedKey};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, RwLock};

/// 证书解析器 - 动态生成和缓存服务器证书
pub struct CertResolver {
    ca_rcgen: RcgenCert,
    ca_cert_der: Vec<u8>, // 保存实际的CA证书DER格式
    cache: RwLock<HashMap<String, Arc<CertifiedKey>>>,
}

impl std::fmt::Debug for CertResolver {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CertResolver")
            .field("ca_cert_der", &"<certificate>")
            .field("cache", &"<cache>")
            .finish()
    }
}

impl CertResolver {
    pub fn new() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        // 确保证书存在
        ensure_ca_certificate_exists().map_err(|e| {
            Box::new(std::io::Error::new(std::io::ErrorKind::Other, e))
                as Box<dyn std::error::Error + Send + Sync>
        })?;

        println!("[证书] 加载CA证书用于MITM...");

        // 从文件加载CA证书和私钥
        let cert_path = get_ca_cert_path();
        let key_path = get_ca_key_path();

        let cert_pem =
            std::fs::read_to_string(&cert_path).map_err(|e| format!("读取CA证书失败: {}", e))?;
        let key_pem =
            std::fs::read_to_string(&key_path).map_err(|e| format!("读取CA私钥失败: {}", e))?;

        // 解析CA证书DER格式（用于证书链）
        use rustls_pemfile::Item;
        let mut cert_reader = std::io::BufReader::new(cert_pem.as_bytes());
        let ca_cert_der = match rustls_pemfile::read_one(&mut cert_reader)
            .map_err(|e| format!("解析CA证书失败: {}", e))?
        {
            Some(Item::X509Certificate(cert)) => cert,
            _ => return Err("无效的CA证书格式".into()),
        };

        // 调试：输出CA证书指纹
        let ca_der_hash = {
            let mut hasher = std::collections::hash_map::DefaultHasher::new();
            std::hash::Hash::hash_slice(&ca_cert_der, &mut hasher);
            std::hash::Hasher::finish(&hasher)
        };
        println!(
            "[证书] 加载的CA证书DER大小: {} 字节, 哈希: {:x}",
            ca_cert_der.len(),
            ca_der_hash
        );

        // 使用保存的私钥重建CA证书（仅用于签名）
        let key_pair = KeyPair::from_pem(&key_pem)?;
        let mut params = get_ca_cert_config()?;

        // 设置固定的序列号（与磁盘CA证书保持一致）
        // 从磁盘CA证书中提取序列号
        use x509_parser::prelude::*;
        let (_rem, x509) = X509Certificate::from_der(&ca_cert_der)
            .map_err(|e| format!("解析CA证书失败: {}", e))?;
        // rcgen 0.13的serial_number是SerialNumber类型，转换序列号
        let serial_u64 = {
            let serial_bytes = x509.serial.to_bytes_be();
            // 取最后8个字节转换为u64（如果序列号超过8字节，只取低位）
            let len = serial_bytes.len();
            let start = if len > 8 { len - 8 } else { 0 };
            let mut bytes = [0u8; 8];
            bytes[8 - (len - start)..].copy_from_slice(&serial_bytes[start..]);
            u64::from_be_bytes(bytes)
        };
        params.serial_number = Some(rcgen::SerialNumber::from(serial_u64));

        // 使用加载的密钥对而不是生成新的
        params.key_pair = Some(key_pair);
        let ca_rcgen = RcgenCert::from_params(params)?;

        println!("[证书] CA证书加载成功");

        Ok(Self {
            ca_rcgen,
            ca_cert_der: ca_cert_der.to_vec(), // 保存实际的CA证书DER
            cache: RwLock::new(HashMap::new()),
        })
    }

    fn generate_cert(&self, name: &str) -> Option<Arc<CertifiedKey>> {
        // Subject Alternative Name是必须的，传入构造函数
        let mut params = CertificateParams::new(vec![name.to_string()]);

        // 叶子证书配置 - 用于服务器认证
        params.key_usages = vec![
            rcgen::KeyUsagePurpose::DigitalSignature,
            rcgen::KeyUsagePurpose::KeyEncipherment,
        ];
        params.extended_key_usages = vec![rcgen::ExtendedKeyUsagePurpose::ServerAuth];

        // 设置叶子证书有效期（2年）
        use rcgen::date_time_ymd;
        params.not_before = date_time_ymd(2024, 1, 1);
        params.not_after = date_time_ymd(2026, 12, 31);

        let key_pair = KeyPair::generate(&rcgen::PKCS_ECDSA_P256_SHA256).ok()?;
        params.key_pair = Some(key_pair);
        let leaf = RcgenCert::from_params(params).ok()?;
        let leaf_der = leaf.serialize_der_with_signer(&self.ca_rcgen).ok()?;
        let leaf_priv = leaf.serialize_private_key_der();

        let private_key = PrivateKeyDer::try_from(leaf_priv).ok()?;
        let signing_key = rustls::crypto::ring::sign::any_supported_type(&private_key).ok()?;

        // 构建证书链：叶子证书 + CA证书
        let chain = vec![
            CertificateDer::from(leaf_der),
            CertificateDer::from(self.ca_cert_der.clone()),
        ];

        let ck = CertifiedKey::new(chain, signing_key);
        Some(Arc::new(ck))
    }
}

impl ResolvesServerCert for CertResolver {
    fn resolve(&self, client_hello: ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        let sni = client_hello.server_name()?;
        let name = sni.to_string();
        println!("[证书] 为域名生成证书: {}", name);
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

pub fn get_ca_cert_config() -> Result<CertificateParams, rcgen::Error> {
    use rcgen::{
        BasicConstraints as RcgenBasicConstraints, DistinguishedName, DnType, IsCa, KeyUsagePurpose,
    };

    let mut params = CertificateParams::new(vec!["GleamSlime Capture Client Root CA".to_string()]);

    let mut dn = DistinguishedName::new();
    dn.push(DnType::CountryName, "CN");
    dn.push(DnType::StateOrProvinceName, "Zhejiang");
    dn.push(DnType::LocalityName, "Hangzhou");
    dn.push(DnType::OrganizationName, "gleamslime.com");
    dn.push(DnType::OrganizationalUnitName, "GleamSlime Client");
    dn.push(DnType::CommonName, "GleamSlime Capture Client Root CA");
    params.distinguished_name = dn;

    params.is_ca = IsCa::Ca(RcgenBasicConstraints::Constrained(0));
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

    // 设置有效期（10年）
    use rcgen::date_time_ymd;
    params.not_before = date_time_ymd(2024, 1, 1);
    params.not_after = date_time_ymd(2034, 12, 31);

    Ok(params)
}

/// 获取CA证书路径（使用绝对路径）
pub fn get_ca_cert_path() -> PathBuf {
    // 使用用户主目录下的固定位置
    let home_dir = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home_dir)
        .join(".slime_works")
        .join("key")
        .join("generated_ca.crt")
}

/// 获取CA私钥路径
pub fn get_ca_key_path() -> PathBuf {
    let home_dir = std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .unwrap_or_else(|_| ".".to_string());

    PathBuf::from(home_dir)
        .join(".slime_works")
        .join("key")
        .join("generated_ca.key")
}

/// 生成CA证书（如果不存在）
pub fn ensure_ca_certificate_exists() -> Result<PathBuf, String> {
    let cert_path = get_ca_cert_path();
    let key_path = get_ca_key_path();

    // 如果证书和私钥都已存在，直接返回
    if cert_path.exists() && key_path.exists() {
        println!("[证书] 使用已存在的CA证书: {}", cert_path.display());
        return Ok(cert_path);
    }

    println!("[证书] 生成新的CA证书...");

    let mut params = get_ca_cert_config().map_err(|e| format!("配置证书参数失败: {}", e))?;

    let key_pair = KeyPair::generate(&rcgen::PKCS_ECDSA_P256_SHA256)
        .map_err(|e| format!("生成密钥对失败: {}", e))?;
    params.key_pair = Some(key_pair);

    let ca_rcgen = RcgenCert::from_params(params).map_err(|e| format!("生成证书失败: {}", e))?;
    let ca_cert_pem = ca_rcgen
        .serialize_pem()
        .map_err(|e| format!("序列化证书失败: {}", e))?;
    let ca_key_pem = ca_rcgen.serialize_private_key_pem();

    // 创建目录并保存证书和私钥
    if let Some(parent) = cert_path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| format!("创建目录失败: {}", e))?;
    }

    std::fs::write(&cert_path, &ca_cert_pem).map_err(|e| format!("写入证书失败: {}", e))?;
    std::fs::write(&key_path, &ca_key_pem).map_err(|e| format!("写入私钥失败: {}", e))?;

    println!("[证书] CA证书已生成并保存到: {}", cert_path.display());
    println!("[证书] CA私钥已保存到: {}", key_path.display());
    Ok(cert_path)
}

/// 安装CA证书到系统信任存储（需要管理员密码）
pub fn install_ca_certificate_with_password(_password: &str) -> Result<String, String> {
    // 先确保证书存在
    let cert_path = ensure_ca_certificate_exists()?;
    let cert_path_str = cert_path.to_string_lossy().to_string();

    #[cfg(target_os = "windows")]
    {
        // Windows: 先尝试当前用户存储（不需要管理员权限），失败则提示使用企业存储
        use std::process::Command;

        println!("[证书] 尝试安装CA证书到Windows当前用户的根证书存储...");

        // 首先尝试添加到当前用户存储（不需要管理员权限）
        let output = Command::new("certutil")
            .args(&["-addstore", "-user", "Root", &cert_path_str])
            .output()
            .map_err(|e| format!("执行certutil失败: {}", e))?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            println!("[证书] 证书已安装到当前用户的根证书存储");
            return Ok(format!("CA证书安装成功（当前用户）\n{}", stdout));
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        eprintln!("[证书] 用户级安装失败: {}", stderr);

        // 如果用户级失败，提示安装方法
        Err(format!(
            "证书安装失败。请选择以下方式之一手动安装:\n\n\
            1. 双击打开证书文件: {}\n\
               选择\"安装证书\" -> \"当前用户\" -> \"将所有的证书放入下列存储\" -> 浏览选择\"受信任的根证书颁发机构\"\n\n\
            2. 或以管理员身份在PowerShell中运行:\n\
               certutil -addstore -enterprise -f Root \"{}\"\n\n\
            错误详情: {}",
            cert_path_str, cert_path_str, stderr
        ))
    }

    #[cfg(target_os = "macos")]
    {
        use std::io::{BufRead, BufReader};
        use std::process::{Command, Stdio};
        use std::thread;

        println!("[证书] 正在安装CA证书到macOS钥匙串...");

        // 先尝试删除旧证书（如果存在）
        // println!("[证书] 检查并删除旧证书...");
        // let delete_command = format!(
        //     "echo '{}' | /usr/bin/sudo -S /usr/bin/security delete-certificate -c 'Skill Capture Client Root CA' /Library/Keychains/System.keychain 2>/dev/null || true",
        //     password
        // );
        // let _ = Command::new("/bin/sh")
        //     .arg("-c")
        //     .arg(&delete_command)
        //     .output();

        // 使用完整路径避免 PATH 问题，并使用 sh 而不是 bash（更通用）
        let command = format!(
            "echo '{}' | /usr/bin/sudo -S /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain '{}'",
            _password, cert_path_str
        );

        // 使用 sh -c 执行命令
        let mut child = Command::new("/bin/sh")
            .arg("-c")
            .arg(&command)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("执行命令失败: {}", e))?;

        // 捕获输出
        let stdout = child.stdout.take().ok_or("Failed to capture stdout")?;
        let stderr = child.stderr.take().ok_or("Failed to capture stderr")?;

        let stdout_reader = BufReader::new(stdout);
        let stderr_reader = BufReader::new(stderr);

        // 读取 stdout
        let stdout_thread = thread::spawn(move || {
            let mut stdout_accum = String::new();
            stdout_reader
                .lines()
                .filter_map(Result::ok)
                .for_each(|line| {
                    stdout_accum.push_str(&line);
                    stdout_accum.push('\n');
                    println!("[证书输出] {}", line);
                });
            stdout_accum
        });

        // 读取 stderr
        let stderr_thread = thread::spawn(move || {
            let mut stderr_accum = String::new();
            stderr_reader
                .lines()
                .filter_map(Result::ok)
                .for_each(|line| {
                    stderr_accum.push_str(&line);
                    stderr_accum.push('\n');
                    eprintln!("[证书错误] {}", line);
                });
            stderr_accum
        });

        // 等待子进程完成
        let status = child.wait().map_err(|e| format!("命令执行失败: {}", e))?;

        // 获取输出
        let stdout_result = stdout_thread.join().unwrap();
        let stderr_result = stderr_thread.join().unwrap();

        if status.success() {
            Ok("CA证书安装成功".to_string())
        } else {
            let stderr = stderr_result.trim();
            if stderr.contains("Sorry, try again") || stderr.contains("incorrect password") {
                Err("管理员密码错误".to_string())
            } else if stderr.contains("already exists") {
                Ok("证书已经安装（已存在）".to_string())
            } else if stderr.is_empty() && !stdout_result.is_empty() {
                // 某些情况下成功信息在 stdout
                Ok("CA证书安装成功".to_string())
            } else {
                Err(format!("证书安装失败: {}", stderr))
            }
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

/// 检查CA证书是否已安装到系统
pub fn is_ca_certificate_installed() -> Result<bool, String> {
    let cert_name = "Skill Capture Client Root CA";

    #[cfg(target_os = "macos")]
    {
        // 执行命令检查证书是否存在
        match Command::new("security")
            .args(&[
                "find-certificate",
                "-c",
                cert_name,
                "/Library/Keychains/System.keychain",
            ])
            .output()
        {
            Ok(output) => {
                // 如果命令成功执行且stdout不为空，说明证书已安装
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    // 检查输出中是否包含证书名称
                    Ok(stdout.contains(cert_name))
                } else {
                    Ok(false)
                }
            }
            Err(err) => Err(format!("检查证书失败: {}", err)),
        }
    }

    #[cfg(target_os = "windows")]
    {
        // Windows: 使用 certutil 命令查询证书
        match Command::new("certutil")
            .args(&["-verifystore", "Root", cert_name])
            .output()
        {
            Ok(output) => {
                if output.status.success() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    Ok(stdout.contains(cert_name))
                } else {
                    Ok(false)
                }
            }
            Err(err) => Err(format!("检查证书失败: {}", err)),
        }
    }

    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    {
        Ok(false)
    }
}
