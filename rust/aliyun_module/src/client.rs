use anyhow::{anyhow, Result};
use base64::Engine;
use hmac::{Hmac, Mac};
use percent_encoding::utf8_percent_encode;
use reqwest::Client;
use sha2::Sha256;
use slime_logger::{sw_error, sw_info, sw_warn};
use std::collections::BTreeMap;

use crate::types::*;

type HmacSha256 = Hmac<Sha256>;

const ALIYUN_DNS_ENDPOINT: &str = "alidns.cn-hangzhou.aliyuncs.com";
const API_VERSION: &str = "2015-01-09";
const SIGNATURE_METHOD: &str = "HMAC-SHA256";
const SIGNATURE_VERSION: &str = "1.0";
const FORMAT: &str = "JSON";

pub struct AliyunDnsClient {
    access_key_id: String,
    access_key_secret: String,
    http_client: Client,
}

impl AliyunDnsClient {
    pub fn new(access_key_id: String, access_key_secret: String) -> Self {
        let http_client = Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .unwrap_or_default();
        Self {
            access_key_id,
            access_key_secret,
            http_client,
        }
    }

    pub async fn describe_domains(&self) -> Result<Vec<DomainInfo>> {
        let mut params = self.base_params();
        params.insert("Action".to_string(), "DescribeDomains".to_string());

        let resp = self.call_api(&params).await?;
        let domains = resp
            .get("Domains")
            .and_then(|d| d.get("Domain"))
            .and_then(|d| d.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| serde_json::from_value(v.clone()).ok())
                    .collect::<Vec<DomainInfo>>()
            })
            .unwrap_or_default();

        Ok(domains)
    }

    pub async fn describe_domain_records(&self, domain_name: &str) -> Result<Vec<DomainRecord>> {
        let mut params = self.base_params();
        params.insert("Action".to_string(), "DescribeDomainRecords".to_string());
        params.insert("DomainName".to_string(), domain_name.to_string());

        let resp = self.call_api(&params).await?;
        let records = resp
            .get("DomainRecords")
            .and_then(|d| d.get("Record"))
            .and_then(|d| d.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| serde_json::from_value(v.clone()).ok())
                    .collect::<Vec<DomainRecord>>()
            })
            .unwrap_or_default();

        Ok(records)
    }

    pub async fn update_domain_record(
        &self,
        record_id: &str,
        rr: &str,
        record_type: &str,
        value: &str,
        line: &str,
    ) -> Result<()> {
        let mut params = self.base_params();
        params.insert("Action".to_string(), "UpdateDomainRecord".to_string());
        params.insert("RecordId".to_string(), record_id.to_string());
        params.insert("RR".to_string(), rr.to_string());
        params.insert("Type".to_string(), record_type.to_string());
        params.insert("Value".to_string(), value.to_string());
        params.insert("Line".to_string(), line.to_string());

        let resp = self.call_api(&params).await?;
        if let Some(code) = resp.get("Code").and_then(|c| c.as_str()) {
            let message = resp
                .get("Message")
                .and_then(|m| m.as_str())
                .unwrap_or("未知错误");
            return Err(anyhow!("阿里云API错误: {} - {}", code, message));
        }

        Ok(())
    }

    pub async fn find_sub_domain_record(
        &self,
        domain_name: &str,
        rr: &str,
    ) -> Result<Option<DomainRecord>> {
        let mut params = self.base_params();
        params.insert("Action".to_string(), "DescribeDomainRecords".to_string());
        params.insert("DomainName".to_string(), domain_name.to_string());
        params.insert("RRKeyWord".to_string(), rr.to_string());

        sw_info!(
            "[aliyun] 查询解析记录: DomainName={}, RRKeyWord={}",
            domain_name,
            rr
        );

        let resp = self.call_api(&params).await?;

        if let Some(code) = resp.get("Code").and_then(|c| c.as_str()) {
            let message = resp
                .get("Message")
                .and_then(|m| m.as_str())
                .unwrap_or("未知错误");
            sw_error!(
                "[aliyun] DescribeDomainRecords API返回错误: {} - {}",
                code,
                message
            );
            return Err(anyhow!("阿里云API错误: {} - {}", code, message));
        }

        let total_count = resp.get("TotalCount").and_then(|v| v.as_u64()).unwrap_or(0);
        sw_info!(
            "[aliyun] DescribeDomainRecords返回: TotalCount={}",
            total_count
        );

        let records = resp
            .get("DomainRecords")
            .and_then(|d| d.get("Record"))
            .and_then(|d| d.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| serde_json::from_value(v.clone()).ok())
                    .collect::<Vec<DomainRecord>>()
            })
            .unwrap_or_default();

        sw_info!(
            "[aliyun] 解析到{}条记录, 各记录RR: [{}]",
            records.len(),
            records
                .iter()
                .map(|r| format!("{}={}", r.rr, r.value))
                .collect::<Vec<_>>()
                .join(", ")
        );

        let found = records.iter().find(|r| r.rr == rr);
        if let Some(record) = &found {
            sw_info!(
                "[aliyun] 精确匹配成功: RR={}, Value={}, RecordId={}, Type={}, Line={}",
                record.rr,
                record.value,
                record.record_id,
                record.record_type,
                record.line
            );
        } else {
            sw_warn!(
                "[aliyun] 未找到RR='{}'的精确匹配 (共{}条记录)",
                rr,
                records.len()
            );
        }

        Ok(found.cloned())
    }

    fn base_params(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert("Format".to_string(), FORMAT.to_string());
        params.insert("Version".to_string(), API_VERSION.to_string());
        params.insert("AccessKeyId".to_string(), self.access_key_id.clone());
        params.insert("SignatureMethod".to_string(), SIGNATURE_METHOD.to_string());
        params.insert(
            "SignatureVersion".to_string(),
            SIGNATURE_VERSION.to_string(),
        );
        params.insert(
            "SignatureNonce".to_string(),
            uuid::Uuid::new_v4().to_string(),
        );
        params.insert(
            "Timestamp".to_string(),
            chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        );
        params
    }

    async fn call_api(&self, params: &BTreeMap<String, String>) -> Result<serde_json::Value> {
        let signature = self.compute_signature(params)?;
        let mut query_parts: Vec<String> = params
            .iter()
            .map(|(k, v)| {
                format!(
                    "{}={}",
                    percent_encode_rfc3986(k),
                    percent_encode_rfc3986(v)
                )
            })
            .collect();
        query_parts.sort();
        query_parts.push(format!("Signature={}", percent_encode_rfc3986(&signature)));

        let url = format!("https://{}/?{}", ALIYUN_DNS_ENDPOINT, query_parts.join("&"));

        let response = self
            .http_client
            .get(&url)
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| anyhow!("请求阿里云API失败: {}", e))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| anyhow!("读取响应体失败: {}", e))?;

        if !status.is_success() {
            sw_error!("阿里云API请求失败: status={}, body={}", status, body);
            return Err(anyhow!("阿里云API请求失败: HTTP {}", status));
        }

        let json: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| anyhow!("解析响应JSON失败: {}", e))?;

        if json.get("Code").is_some() {
            sw_warn!(
                "[aliyun] API响应含错误: {}",
                serde_json::to_string_pretty(&json).unwrap_or_default()
            );
        }

        Ok(json)
    }

    fn compute_signature(&self, params: &BTreeMap<String, String>) -> Result<String> {
        let mut sorted_params: Vec<(&String, &String)> = params.iter().collect();
        sorted_params.sort_by_key(|(k, _)| *k);

        let canonical_query: Vec<String> = sorted_params
            .iter()
            .map(|(k, v)| {
                format!(
                    "{}={}",
                    percent_encode_rfc3986(k),
                    percent_encode_rfc3986(v)
                )
            })
            .collect();

        let string_to_sign = format!(
            "GET&{}&{}",
            percent_encode_rfc3986("/"),
            percent_encode_rfc3986(&canonical_query.join("&"))
        );

        let key = format!("{}&", self.access_key_secret);
        let mut mac = HmacSha256::new_from_slice(key.as_bytes())
            .map_err(|e| anyhow!("HMAC初始化失败: {}", e))?;
        mac.update(string_to_sign.as_bytes());
        let result = mac.finalize().into_bytes();

        Ok(base64::engine::general_purpose::STANDARD.encode(result))
    }
}

fn percent_encode_rfc3986(input: &str) -> String {
    const RFC3986: &percent_encoding::AsciiSet = &percent_encoding::NON_ALPHANUMERIC
        .remove(b'-')
        .remove(b'_')
        .remove(b'.')
        .remove(b'~');
    utf8_percent_encode(input, RFC3986).to_string()
}

pub async fn get_public_ip() -> Result<String> {
    let client = Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .build()?;

    let urls = [
        "https://icanhazip.com",
        "https://api.ipify.org",
        "https://4.ident.me",
        "https://checkip.amazonaws.com",
        "https://api.ipsimple.org/ipv4",
        "https://ifconfig.me/ip",
    ];

    for url in urls {
        sw_info!("[aliyun] 尝试获取公网IP: {}", url);
        match client.get(url).send().await {
            Ok(resp) => {
                if resp.status().is_success() {
                    if let Ok(text) = resp.text().await {
                        let ip = text.trim().to_string();
                        if !ip.is_empty() && ip.parse::<std::net::IpAddr>().is_ok() {
                            sw_info!("[aliyun] 公网IP获取成功: {} (from {})", ip, url);
                            return Ok(ip);
                        }
                        sw_warn!("[aliyun] 响应不是有效IP: {} -> {}", url, ip);
                    }
                } else {
                    sw_warn!("[aliyun] HTTP非成功状态: {} -> {}", url, resp.status());
                }
            }
            Err(e) => {
                sw_warn!("获取公网IP失败({}): {}", url, e);
            }
        }
    }

    sw_info!("[aliyun] 所有公共API均失败，尝试UDP获取本机出口IP");
    match get_local_outbound_ip() {
        Ok(ip) => {
            sw_info!("[aliyun] 本机出口IP获取成功: {}", ip);
            Ok(ip)
        }
        Err(e) => {
            sw_error!("[aliyun] 本机出口IP获取也失败: {}", e);
            Err(anyhow!("所有公网IP获取方式均失败，请检查网络连接"))
        }
    }
}

fn get_local_outbound_ip() -> Result<String> {
    use std::net::UdpSocket;
    let socket = UdpSocket::bind("0.0.0.0:0")?;
    socket.connect("8.8.8.8:53")?;
    let local_addr = socket.local_addr()?;
    match local_addr {
        std::net::SocketAddr::V4(v4) => {
            let ip = v4.ip().to_string();
            if ip.starts_with("10.") || ip.starts_with("172.") || ip.starts_with("192.168.") {
                sw_warn!("[aliyun] 本机出口IP是内网地址: {}", ip);
            }
            Ok(ip)
        }
        std::net::SocketAddr::V6(v6) => Ok(v6.ip().to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // 说明：以下 AccessKey 全部使用阿里云官方文档示例中的假值（testid / testsecret），
    // 绝不涉及任何真实密钥；call_api 与 get_public_ip 涉及外网，不在测试范围。

    /// 阿里云官方《RPC API 签名机制》文档示例（V2 版）给出的已排序参数集合，
    /// 文档中该示例的 HMAC-SHA1 签名为 `9NaGiOspFP5UPcwX8Iwt2YJXXuk=`
    fn official_docs_params() -> BTreeMap<String, String> {
        let mut p = BTreeMap::new();
        p.insert("AccessKeyId".into(), "testid".into());
        p.insert("Action".into(), "DescribeDedicatedHosts".into());
        p.insert("Format".into(), "JSON".into());
        p.insert("RegionId".into(), "cn-beijing".into());
        p.insert("SignatureMethod".into(), "HMAC-SHA1".into());
        p.insert("SignatureNonce".into(), "edb2b34af0af9a6d14deaf7c1a5315eb".into());
        p.insert("SignatureVersion".into(), "1.0".into());
        p.insert("Timestamp".into(), "2023-03-13T08:34:30Z".into());
        p.insert("Version".into(), "2014-05-26".into());
        p
    }

    /// RFC3986 百分号编码：未保留字符（字母数字与 - _ . ~）保持原样
    #[test]
    fn percent_encode_keeps_unreserved_rfc3986_chars() {
        let raw = "abcXYZ019-_.~";
        assert_eq!(percent_encode_rfc3986(raw), raw);
        assert_eq!(percent_encode_rfc3986(""), "");
    }

    /// RFC3986 百分号编码：保留字符与特殊值必须按文档规则编码（空格是 %20 而非 +）
    #[test]
    fn percent_encode_escapes_reserved_and_special_chars() {
        assert_eq!(percent_encode_rfc3986("/"), "%2F");
        assert_eq!(percent_encode_rfc3986("="), "%3D");
        assert_eq!(percent_encode_rfc3986("&"), "%26");
        assert_eq!(percent_encode_rfc3986(":"), "%3A");
        assert_eq!(percent_encode_rfc3986("+"), "%2B");
        assert_eq!(percent_encode_rfc3986("*"), "%2A");
        assert_eq!(percent_encode_rfc3986(" "), "%20");
        // 官方文档 Timestamp 示例片段的编码结果
        assert_eq!(
            percent_encode_rfc3986("2023-03-13T08:34:30Z"),
            "2023-03-13T08%3A34%3A30Z"
        );
        // UTF-8 多字节：中 → %E4%B8%AD（文档要求按 UTF-8 字节逐字节编码）
        assert_eq!(percent_encode_rfc3986("中"), "%E4%B8%AD");
    }

    /// 已编码字符串再编码（构造 string-to-sign 时对规范化查询串整体二次编码）
    #[test]
    fn percent_encode_is_double_encodable() {
        assert_eq!(
            percent_encode_rfc3986("2023-03-13T08%3A34%3A30Z"),
            "2023-03-13T08%253A34%253A30Z"
        );
    }

    /// base_params：公共参数齐全、取值符合文档约定，且不含 Signature/Action
    #[test]
    fn base_params_contains_required_public_params() {
        let client = AliyunDnsClient::new("testid".into(), "testsecret".into());
        let params = client.base_params();

        assert_eq!(params.get("Format").map(String::as_str), Some("JSON"));
        assert_eq!(params.get("Version").map(String::as_str), Some("2015-01-09"));
        assert_eq!(params.get("AccessKeyId").map(String::as_str), Some("testid"));
        assert_eq!(
            params.get("SignatureMethod").map(String::as_str),
            Some("HMAC-SHA256")
        );
        assert_eq!(
            params.get("SignatureVersion").map(String::as_str),
            Some("1.0")
        );
        assert!(!params.contains_key("Signature"), "签名本身不参与待签串");
        assert!(!params.contains_key("Action"), "Action 是业务参数，不属于 base_params");

        // Nonce 为 UUID v4 文本
        let nonce = params.get("SignatureNonce").expect("应携带 SignatureNonce");
        assert_eq!(nonce.len(), 36, "nonce = {nonce}");
        assert!(uuid::Uuid::parse_str(nonce).is_ok(), "nonce = {nonce}");

        // Timestamp 为 UTC ISO8601：YYYY-MM-DDTHH:MM:SSZ
        let ts = params.get("Timestamp").expect("应携带 Timestamp");
        assert_eq!(ts.len(), 20, "ts = {ts}");
        assert!(ts.ends_with('Z') && ts.matches(':').count() == 2, "ts = {ts}");

        // BTreeMap 保证字典序（签名串要求参数按首字母升序）
        let keys: Vec<&str> = params.keys().map(String::as_str).collect();
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted);
    }

    /// 官方文档示例向量（HMAC-SHA256 版）：文档 string-to-sign 为
    /// GET&%2F&AccessKeyId%3Dtestid%26...%26Version%3D2014-05-26
    /// 同一 string-to-sign 的 HMAC-SHA1 结果与文档一致（9NaGiOspFP5UPcwX8Iwt2YJXXuk=），
    /// 以此证明待签串逐字复刻；期望值为独立实现（Python hmac）对同一串算出的 SHA256 签名
    #[test]
    fn compute_signature_matches_official_docs_vector() {
        let client = AliyunDnsClient::new("testid".into(), "testsecret".into());
        let sig = client
            .compute_signature(&official_docs_params())
            .expect("签名计算不应失败");
        assert_eq!(sig, "VupYLTA1Q8/TdQmnI3sZO0qP4+JtTgQR0z44QP6x70M=");
    }

    /// 微向量：两个最小参数的 string-to-sign 结构为 GET&%2F&k%3Dv%26k%3Dv，
    /// 期望值由独立实现（Python hmac）预算，锁定 GET/%2F/二次编码/HMAC key 拼接等结构细节
    #[test]
    fn compute_signature_matches_minimal_structural_vector() {
        let client = AliyunDnsClient::new("testid".into(), "secret".into());
        let mut params = BTreeMap::new();
        params.insert("a".to_string(), "1".to_string());
        params.insert("b".to_string(), "2".to_string());
        let sig = client.compute_signature(&params).unwrap();
        assert_eq!(sig, "WU62danpqVXT2W3octl1R8WWet4HG+fhvFSFG7HS6HI=");
    }

    /// 签名对参数与密钥敏感：改动任一因子结果必变；重复调用结果稳定
    #[test]
    fn compute_signature_is_deterministic_and_input_sensitive() {
        let client = AliyunDnsClient::new("testid".into(), "testsecret".into());
        let base = official_docs_params();
        let again = client.compute_signature(&base).unwrap();
        assert_eq!(client.compute_signature(&base).unwrap(), again, "同输入必须同输出");

        let mut changed_value = base.clone();
        changed_value.insert("RegionId".into(), "cn-hangzhou".into());
        assert_ne!(client.compute_signature(&changed_value).unwrap(), again);

        let mut added = base.clone();
        added.insert("PageSize".into(), "10".into());
        assert_ne!(client.compute_signature(&added).unwrap(), again);

        // 换一个密钥（仍是假值），签名不同 ⇒ secret 确实进入 HMAC key
        let other = AliyunDnsClient::new("testid".into(), "other-secret".into());
        assert_ne!(other.compute_signature(&base).unwrap(), again);

        // 签名是标准 base64（4 的倍数，SHA256 摘要 ⇒ 44 字符）
        assert_eq!(again.len(), 44);
        assert!(base64::engine::general_purpose::STANDARD
            .decode(&again)
            .map(|d| d.len() == 32)
            .unwrap_or(false));
    }
}
