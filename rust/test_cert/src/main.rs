fn main() {
    // 加载CA证书
    let home_dir = std::env::var("HOME").unwrap();
    let cert_path = std::path::PathBuf::from(&home_dir)
        .join(".slime_works")
        .join("key")
        .join("generated_ca.crt");

    let cert_pem = std::fs::read_to_string(&cert_path).expect("读取CA证书失败");

    // 解析为DER
    use rustls_pemfile::Item;
    let mut cert_reader = std::io::BufReader::new(cert_pem.as_bytes());
    let ca_cert_der = match rustls_pemfile::read_one(&mut cert_reader).expect("解析失败") {
        Some(Item::X509Certificate(cert)) => cert,
        _ => panic!("无效的CA证书格式"),
    };

    // 使用x509-parser解析
    use x509_parser::prelude::*;
    let (_rem, x509) = X509Certificate::from_der(&ca_cert_der).expect("解析CA证书失败");

    println!("CA证书信息:");
    println!("  Subject: {:?}", x509.subject());
    println!("  Issuer: {:?}", x509.issuer());
    println!("  Serial: {:?}", x509.serial);
    println!("  Serial (hex): {:02x?}", x509.serial.to_bytes_be());

    // 使用rcgen重建CA证书
    let key_path = std::path::PathBuf::from(&home_dir)
        .join(".slime_works")
        .join("key")
        .join("generated_ca.key");
    let key_pem = std::fs::read_to_string(&key_path).expect("读取CA私钥失败");
    let key_pair = rcgen::KeyPair::from_pem(&key_pem).expect("解析私钥失败");

    use rcgen::{BasicConstraints as RcgenBC, *};
    let mut params = CertificateParams::new(vec!["Skill Capture Client Root CA".to_string()]);

    let mut dn = DistinguishedName::new();
    dn.push(DnType::CountryName, "CN");
    dn.push(DnType::StateOrProvinceName, "Zhejiang");
    dn.push(DnType::LocalityName, "Hangzhou");
    dn.push(DnType::OrganizationName, "www.everyselect.com");
    dn.push(DnType::OrganizationalUnitName, "Skill Client");
    dn.push(DnType::CommonName, "Skill Capture Client Root CA");
    params.distinguished_name = dn;

    params.is_ca = IsCa::Ca(RcgenBC::Constrained(0));
    params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyEncipherment,
        KeyUsagePurpose::KeyCertSign,
        KeyUsagePurpose::CrlSign,
    ];
    params.extended_key_usages = vec![
        ExtendedKeyUsagePurpose::ServerAuth,
        ExtendedKeyUsagePurpose::ClientAuth,
    ];

    // 设置序列号
    let serial_u64 = {
        let serial_bytes = x509.serial.to_bytes_be();
        let len = serial_bytes.len();
        let start = if len > 8 { len - 8 } else { 0 };
        let mut bytes = [0u8; 8];
        bytes[8 - (len - start)..].copy_from_slice(&serial_bytes[start..]);
        u64::from_be_bytes(bytes)
    };
    params.serial_number = Some(serial_u64);
    params.key_pair = Some(key_pair);

    let ca_rcgen = Certificate::from_params(params).expect("生成CA失败");

    // 生成rcgen CA证书的DER
    let ca_rcgen_der = ca_rcgen.serialize_der().expect("序列化失败");

    // 解析rcgen生成的证书
    let (_rem2, x509_rcgen) =
        X509Certificate::from_der(&ca_rcgen_der).expect("解析rcgen CA证书失败");

    println!("\nrcgen生成的CA证书信息:");
    println!("  Subject: {:?}", x509_rcgen.subject());
    println!("  Issuer: {:?}", x509_rcgen.issuer());
    println!("  Serial: {:?}", x509_rcgen.serial);
    println!("  Serial (hex): {:02x?}", x509_rcgen.serial.to_bytes_be());

    // 比较两个证书是否一致
    println!("\n证书比较:");
    println!("  序列号是否一致: {}", x509.serial == x509_rcgen.serial);
    println!(
        "  Subject是否一致: {}",
        x509.subject() == x509_rcgen.subject()
    );

    // 生成一个叶子证书测试
    let mut leaf_params = CertificateParams::new(vec!["example.com".to_string()]);
    let mut leaf_dn = DistinguishedName::new();
    leaf_dn.push(DnType::CommonName, "example.com");
    leaf_params.distinguished_name = leaf_dn;
    leaf_params.key_usages = vec![
        KeyUsagePurpose::DigitalSignature,
        KeyUsagePurpose::KeyEncipherment,
    ];
    leaf_params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];

    let leaf = Certificate::from_params(leaf_params).expect("生成叶子证书失败");
    let leaf_der = leaf.serialize_der_with_signer(&ca_rcgen).expect("签名失败");

    // 解析叶子证书
    let (_rem3, x509_leaf) = X509Certificate::from_der(&leaf_der).expect("解析叶子证书失败");

    println!("\n叶子证书信息:");
    println!("  Subject: {:?}", x509_leaf.subject());
    println!("  Issuer: {:?}", x509_leaf.issuer());

    // 检查叶子证书的Issuer是否与CA证书的Subject一致
    println!("\n验证证书链:");
    println!(
        "  叶子证书Issuer == CA证书Subject: {}",
        x509_leaf.issuer() == x509_rcgen.subject()
    );
    println!(
        "  叶子证书Issuer == 磁盘CA Subject: {}",
        x509_leaf.issuer() == x509.subject()
    );
}
