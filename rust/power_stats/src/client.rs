use regex::Regex;
use slime_logger::{sw_error, sw_info};

use crate::types::MeterReading;

const USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36";

/// 请求 cnyiot 接口并解析电表读数
pub async fn fetch_meter_reading(meter_id: &str) -> Result<MeterReading, String> {
    if meter_id.trim().is_empty() {
        return Err("表号为空".to_string());
    }

    let url = format!("http://www.wap.cnyiot.com/nat/pay.aspx?mid={}", meter_id);
    sw_info!("[power_stats] 请求电表数据: {}", url);

    let client = reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .redirect(reqwest::redirect::Policy::limited(5))
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(|e| format!("创建HTTP客户端失败: {}", e))?;

    let resp = client
        .get(&url)
        .header("User-Agent", USER_AGENT)
        .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        .header("Accept-Language", "zh-CN,zh;q=0.9")
        .header("Cache-Control", "no-cache")
        .header("Referer", &url)
        .send()
        .await
        .map_err(|e| format!("请求电表数据失败: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("接口返回异常状态码: {}", resp.status()));
    }

    let html = resp.text().await.map_err(|e| format!("读取响应体失败: {}", e))?;
    parse_html(&html, meter_id)
}

/// 从HTML中提取剩余电量、剩余金额、表名称、综合费用
fn parse_html(html: &str, meter_id: &str) -> Result<MeterReading, String> {
    let kwh_re = Regex::new(r"剩余电量[:：]\s*</span>\s*<label[^>]*>\s*([\d.]+)\s*</label>").unwrap();
    let yuan_re = Regex::new(r"剩余金额[:：]\s*</span>\s*<label[^>]*>\s*([\d.]+)\s*</label>").unwrap();
    let name_re = Regex::new(r"表.*?名.*?称[:：]\s*</span>\s*<label[^>]*>\s*([^<]+?)\s*</label>").unwrap();
    let price_re = Regex::new(r"综合费用[:：]\s*</span>\s*<label[^>]*>\s*([\d.]+)\s*</label>").unwrap();

    let remaining_kwh = kwh_re
        .captures(html)
        .and_then(|c| c.get(1))
        .and_then(|m| m.as_str().trim().parse::<f64>().ok())
        .ok_or_else(|| {
            sw_error!("[power_stats] 未匹配到剩余电量");
            "未找到剩余电量".to_string()
        })?;

    let remaining_yuan = yuan_re
        .captures(html)
        .and_then(|c| c.get(1))
        .and_then(|m| m.as_str().trim().parse::<f64>().ok())
        .ok_or_else(|| {
            sw_error!("[power_stats] 未匹配到剩余金额");
            "未找到剩余金额".to_string()
        })?;

    let meter_name = name_re
        .captures(html)
        .and_then(|c| c.get(1))
        .map(|m| m.as_str().trim().to_string())
        .unwrap_or_default();

    let price = price_re
        .captures(html)
        .and_then(|c| c.get(1))
        .and_then(|m| m.as_str().trim().parse::<f64>().ok())
        .filter(|p| *p > 0.0)
        .unwrap_or(1.0);

    sw_info!(
        "[power_stats] 解析成功: 表号={} 名称={} 电量={} 金额={} 单价={}",
        meter_id, meter_name, remaining_kwh, remaining_yuan, price
    );

    Ok(MeterReading {
        meter_id: meter_id.to_string(),
        meter_name,
        remaining_kwh,
        remaining_yuan,
        price,
        fetched_at: chrono::Local::now().timestamp(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_HTML: &str = r#"
    <div style="margin:5px 0">
        <span>表&ensp;名&ensp;称:</span>
        <label style="margin-left:5px;font-weight:bold;color: #0063F7;">佳丰南苑5-1-501-1</label>
    </div>
    <div style="margin:5px 0">
        <span>表&ensp;&ensp;&ensp;&ensp;号:</span>
        <label id="metid" style="margin-left:5px;">19501609994</label>
    </div>
    <div style="margin:5px 0">
        <span>剩余电量:</span>
        <label style="min-width:75px;margin-left:5px;display:inline-block;">213.15</label>  <span>kWh</span>
    </div>
    <div style="margin:5px 0">
        <span>剩余金额:</span>
        <label style="min-width:75px;margin-left:5px;display:inline-block;color: #3293C6;font-weight:bold;">213.15</label>  <span>元 </span>
    </div>
    <div>
        <span>综合费用:</span>
        <label style="min-width:75px;margin-left:5px;display:inline-block;">1</label>  <span>元/kWh</span>
    </div>
    "#;

    #[test]
    fn test_parse_html() {
        let reading = parse_html(SAMPLE_HTML, "19501609994").unwrap();
        assert_eq!(reading.meter_id, "19501609994");
        assert_eq!(reading.meter_name, "佳丰南苑5-1-501-1");
        assert!((reading.remaining_kwh - 213.15).abs() < 0.001);
        assert!((reading.remaining_yuan - 213.15).abs() < 0.001);
        assert!((reading.price - 1.0).abs() < 0.001);
    }
}
