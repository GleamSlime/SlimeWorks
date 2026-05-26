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
        "https://api.ipify.org",
        "https://icanhazip.com",
        "https://4.ident.me",
        "https://api.ipsimple.org/ipv4",
        "https://checkip.amazonaws.com",
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

    Err(anyhow!("所有公网IP获取方式均失败，请检查网络连接"))
}
