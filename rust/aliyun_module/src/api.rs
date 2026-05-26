use crate::client::{get_public_ip, AliyunDnsClient};
use crate::types::*;
use slime_logger::{sw_error, sw_info, sw_warn};
use std::sync::{Arc, RwLock};

static DDNS_INSTANCE: RwLock<Option<Arc<DdnsManager>>> = RwLock::new(None);

struct DdnsManager {
    config: RwLock<DdnsConfig>,
    logs: RwLock<Vec<DdnsLogEntry>>,
    status: RwLock<DdnsStatus>,
}

fn get_manager() -> Result<Arc<DdnsManager>, String> {
    DDNS_INSTANCE
        .read()
        .map_err(|e| format!("{}", e))?
        .clone()
        .ok_or("DDNS模块未初始化".to_string())
}

pub fn aliyun_ddns_init(config_json: String) -> Result<String, String> {
    let config: DdnsConfig =
        serde_json::from_str(&config_json).map_err(|e| format!("解析DDNS配置失败: {}", e))?;

    let status = DdnsStatus {
        enabled: config.enabled,
        current_ip: String::new(),
        interval_secs: config.interval_secs,
        last_update: String::new(),
        last_result: String::new(),
        domain_statuses: Vec::new(),
    };
    let manager = Arc::new(DdnsManager {
        config: RwLock::new(config),
        logs: RwLock::new(Vec::new()),
        status: RwLock::new(status),
    });

    {
        let mut instance = DDNS_INSTANCE.write().map_err(|e| format!("{}", e))?;
        *instance = Some(manager);
    }

    sw_info!("[aliyun] DDNS模块初始化完成");
    Ok("阿里云DDNS模块初始化完成".to_string())
}

pub fn aliyun_ddns_update_config(config_json: String) -> Result<(), String> {
    let manager = get_manager()?;

    let config: DdnsConfig =
        serde_json::from_str(&config_json).map_err(|e| format!("解析DDNS配置失败: {}", e))?;

    {
        let mut cfg = manager.config.write().map_err(|e| format!("{}", e))?;
        *cfg = config.clone();
    }

    {
        let mut status = manager.status.write().map_err(|e| format!("{}", e))?;
        status.enabled = config.enabled;
        status.interval_secs = config.interval_secs;
    }

    sw_info!("[aliyun] DDNS配置已更新");
    Ok(())
}

pub fn aliyun_ddns_get_config() -> Result<String, String> {
    let manager = get_manager()?;

    let config = manager.config.read().map_err(|e| format!("{}", e))?.clone();
    serde_json::to_string(&config).map_err(|e| format!("序列化配置失败: {}", e))
}

pub fn aliyun_ddns_set_enabled(enabled: bool) -> Result<(), String> {
    let manager = get_manager()?;

    manager
        .config
        .write()
        .map_err(|e| format!("{}", e))?
        .enabled = enabled;
    manager
        .status
        .write()
        .map_err(|e| format!("{}", e))?
        .enabled = enabled;

    sw_info!("[aliyun] DDNS开关: {}", enabled);
    Ok(())
}

pub async fn aliyun_ddns_check_and_update() -> Result<String, String> {
    let manager = get_manager()?;

    let config = manager.config.read().map_err(|e| format!("{}", e))?.clone();
    if !config.enabled {
        return Ok("DDNS未启用".to_string());
    }

    if config.access_key_id.is_empty() || config.access_key_secret.is_empty() {
        return Err("AccessKey未配置".to_string());
    }

    if config.watch_domains.is_empty() {
        return Err("未配置监控域名".to_string());
    }

    let current_ip = get_public_ip()
        .await
        .map_err(|e| format!("获取公网IP失败: {}", e))?;

    {
        let mut status = manager.status.write().map_err(|e| format!("{}", e))?;
        status.current_ip = current_ip.clone();
    }

    let client = AliyunDnsClient::new(
        config.access_key_id.clone(),
        config.access_key_secret.clone(),
    );

    let mut domain_statuses = Vec::new();
    let mut any_updated = false;
    let mut results = Vec::new();

    for watch in &config.watch_domains {
        sw_info!(
            "[aliyun] 检查域名: {}.{} (type={})",
            watch.rr,
            watch.domain_name,
            watch.record_type
        );

        match client
            .find_sub_domain_record(&watch.domain_name, &watch.rr)
            .await
        {
            Ok(Some(record)) => {
                sw_info!(
                    "[aliyun] 找到记录: {}.{} -> {} (record_id={}, line={})",
                    record.rr,
                    watch.domain_name,
                    record.value,
                    record.record_id,
                    record.line
                );

                let resolved_ip = record.value.clone();
                if resolved_ip == current_ip {
                    domain_statuses.push(DomainStatus {
                        domain_name: watch.domain_name.clone(),
                        rr: watch.rr.clone(),
                        record_type: watch.record_type.clone(),
                        resolved_ip: resolved_ip.clone(),
                        updated: false,
                    });
                    results.push(format!(
                        "{}.{} IP未变化({})",
                        watch.rr, watch.domain_name, current_ip
                    ));
                    continue;
                }

                sw_info!(
                    "[aliyun] IP变化: {}.{} {} -> {}",
                    watch.rr,
                    watch.domain_name,
                    resolved_ip,
                    current_ip
                );

                match client
                    .update_domain_record(
                        &record.record_id,
                        &watch.rr,
                        &watch.record_type,
                        &current_ip,
                        &record.line,
                    )
                    .await
                {
                    Ok(_) => {
                        let log = DdnsLogEntry {
                            timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                            domain: watch.domain_name.clone(),
                            rr: watch.rr.clone(),
                            old_ip: resolved_ip.clone(),
                            new_ip: current_ip.clone(),
                            success: true,
                            message: "更新成功".to_string(),
                        };
                        let log_ts = log.timestamp.clone();
                        manager
                            .logs
                            .write()
                            .map_err(|e| format!("{}", e))?
                            .push(log);

                        domain_statuses.push(DomainStatus {
                            domain_name: watch.domain_name.clone(),
                            rr: watch.rr.clone(),
                            record_type: watch.record_type.clone(),
                            resolved_ip: current_ip.clone(),
                            updated: true,
                        });
                        any_updated = true;
                        results.push(format!(
                            "{}.{} 已更新: {} -> {}",
                            watch.rr, watch.domain_name, resolved_ip, current_ip
                        ));

                        {
                            let mut status =
                                manager.status.write().map_err(|e| format!("{}", e))?;
                            status.last_update = log_ts;
                            status.last_result = format!(
                                "{}.{}: {} -> {}",
                                watch.rr, watch.domain_name, resolved_ip, current_ip
                            );
                        }
                    }
                    Err(e) => {
                        let log = DdnsLogEntry {
                            timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                            domain: watch.domain_name.clone(),
                            rr: watch.rr.clone(),
                            old_ip: resolved_ip.clone(),
                            new_ip: current_ip.clone(),
                            success: false,
                            message: format!("更新失败: {}", e),
                        };
                        let log_ts = log.timestamp.clone();
                        let log_msg = log.message.clone();
                        manager
                            .logs
                            .write()
                            .map_err(|e| format!("{}", e))?
                            .push(log);

                        domain_statuses.push(DomainStatus {
                            domain_name: watch.domain_name.clone(),
                            rr: watch.rr.clone(),
                            record_type: watch.record_type.clone(),
                            resolved_ip: resolved_ip.clone(),
                            updated: false,
                        });
                        results.push(format!(
                            "{}.{} 更新失败: {}",
                            watch.rr, watch.domain_name, e
                        ));

                        sw_error!("[aliyun] DDNS更新失败: {}", e);

                        {
                            let mut status =
                                manager.status.write().map_err(|e| format!("{}", e))?;
                            status.last_update = log_ts;
                            status.last_result = log_msg;
                        }
                    }
                }
            }
            Ok(None) => {
                sw_warn!(
                    "[aliyun] 未找到解析记录: {}.{}",
                    watch.rr,
                    watch.domain_name
                );

                let log = DdnsLogEntry {
                    timestamp: chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
                    domain: watch.domain_name.clone(),
                    rr: watch.rr.clone(),
                    old_ip: String::new(),
                    new_ip: current_ip.clone(),
                    success: false,
                    message: format!("未找到子域名 {}.{} 的解析记录", watch.rr, watch.domain_name),
                };
                manager
                    .logs
                    .write()
                    .map_err(|e| format!("{}", e))?
                    .push(log);

                domain_statuses.push(DomainStatus {
                    domain_name: watch.domain_name.clone(),
                    rr: watch.rr.clone(),
                    record_type: watch.record_type.clone(),
                    resolved_ip: String::new(),
                    updated: false,
                });
                results.push(format!("{}.{} 未找到解析记录", watch.rr, watch.domain_name));
            }
            Err(e) => {
                sw_warn!(
                    "[aliyun] 查找记录失败: {}.{} - {}",
                    watch.rr,
                    watch.domain_name,
                    e
                );
                domain_statuses.push(DomainStatus {
                    domain_name: watch.domain_name.clone(),
                    rr: watch.rr.clone(),
                    record_type: watch.record_type.clone(),
                    resolved_ip: String::new(),
                    updated: false,
                });
                results.push(format!(
                    "{}.{} 查找失败: {}",
                    watch.rr, watch.domain_name, e
                ));
            }
        }
    }

    {
        let mut status = manager.status.write().map_err(|e| format!("{}", e))?;
        status.domain_statuses = domain_statuses;
    }

    if any_updated {
        Ok(format!("检查完成(有更新): {}", results.join("; ")))
    } else {
        Ok(format!("检查完成(无变化): {}", results.join("; ")))
    }
}

pub fn aliyun_ddns_get_status() -> Result<String, String> {
    let manager = get_manager()?;

    let status = manager.status.read().map_err(|e| format!("{}", e))?.clone();
    serde_json::to_string(&status).map_err(|e| format!("序列化状态失败: {}", e))
}

pub fn aliyun_ddns_get_logs() -> Result<String, String> {
    let manager = get_manager()?;

    let logs = manager.logs.read().map_err(|e| format!("{}", e))?.clone();
    serde_json::to_string(&logs).map_err(|e| format!("序列化日志失败: {}", e))
}

pub fn aliyun_ddns_clear_logs() -> Result<(), String> {
    let manager = get_manager()?;

    manager.logs.write().map_err(|e| format!("{}", e))?.clear();
    Ok(())
}

pub async fn aliyun_ddns_describe_domains(
    access_key_id: String,
    access_key_secret: String,
) -> Result<String, String> {
    let client = AliyunDnsClient::new(access_key_id, access_key_secret);
    let domains = client
        .describe_domains()
        .await
        .map_err(|e| format!("获取域名列表失败: {}", e))?;
    serde_json::to_string(&domains).map_err(|e| format!("序列化域名列表失败: {}", e))
}

pub async fn aliyun_ddns_describe_domain_records(
    access_key_id: String,
    access_key_secret: String,
    domain_name: String,
) -> Result<String, String> {
    let client = AliyunDnsClient::new(access_key_id, access_key_secret);
    let records = client
        .describe_domain_records(&domain_name)
        .await
        .map_err(|e| format!("获取解析记录失败: {}", e))?;
    serde_json::to_string(&records).map_err(|e| format!("序列化解析记录失败: {}", e))
}
