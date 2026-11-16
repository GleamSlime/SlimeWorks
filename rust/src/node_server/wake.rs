//! 局域网唤醒（Wake-on-LAN）
//!
//! 魔术包是二层广播，只能由与目标主机同网段的设备发出。客户端在外网时，
//! 调用节点 `wake_host` 动作，让局域网内的节点代发。

use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::thread;
use std::time::Duration;

/// 6 字节同步头 + 16 次 MAC 重复
const MAGIC_PACKET_LEN: usize = 102;
const DEFAULT_PORT: u16 = 9;
const DEFAULT_COUNT: u8 = 3;
const MAX_COUNT: u8 = 5;
const SEND_INTERVAL: Duration = Duration::from_millis(80);

/// 解析 MAC 地址，支持冒号、横线、点分隔与纯十六进制
pub fn parse_mac(input: &str) -> Result<[u8; 6], String> {
    let cleaned: String = input
        .chars()
        .filter(|c| !matches!(c, ':' | '-' | '.' | ' '))
        .collect();
    if cleaned.len() != 12 || !cleaned.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!("MAC 地址格式不正确: {}", input));
    }

    let mut mac = [0u8; 6];
    for (index, slot) in mac.iter_mut().enumerate() {
        *slot = u8::from_str_radix(&cleaned[index * 2..index * 2 + 2], 16)
            .map_err(|_| format!("MAC 地址格式不正确: {}", input))?;
    }
    Ok(mac)
}

/// 构造魔术包
pub fn build_magic_packet(mac: [u8; 6]) -> Vec<u8> {
    let mut packet = Vec::with_capacity(MAGIC_PACKET_LEN);
    packet.extend_from_slice(&[0xFF; 6]);
    for _ in 0..16 {
        packet.extend_from_slice(&mac);
    }
    packet
}

/// 发送魔术包，返回实际目标地址与发送次数
///
/// `target` 留空时走全网广播 `255.255.255.255`；同一子网也可直接填
/// `192.168.x.255` 减少对路由器广播转发的依赖。
pub fn send_magic_packet(
    mac: &str,
    target: &str,
    port: u16,
    count: u8,
) -> Result<(String, u8), String> {
    let mac = parse_mac(mac)?;
    let dest = if target.trim().is_empty() {
        IpAddr::V4(Ipv4Addr::BROADCAST)
    } else {
        match target.trim().parse::<IpAddr>() {
            Ok(IpAddr::V4(ip)) => IpAddr::V4(ip),
            Ok(IpAddr::V6(_)) => return Err("暂不支持 IPv6 唤醒地址".to_string()),
            Err(_) => return Err(format!("唤醒地址格式不正确: {}", target)),
        }
    };

    let port = if port == 0 { DEFAULT_PORT } else { port };
    let count = if count == 0 {
        DEFAULT_COUNT
    } else {
        count.clamp(1, MAX_COUNT)
    };

    // 绑到 0.0.0.0 而不是回环地址，广播包才能从物理网卡发出
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0))
        .map_err(|e| format!("创建 UDP 套接字失败: {}", e))?;
    socket
        .set_broadcast(true)
        .map_err(|e| format!("开启广播失败: {}", e))?;

    let packet = build_magic_packet(mac);
    for index in 0..count {
        socket
            .send_to(&packet, SocketAddr::new(dest, port))
            .map_err(|e| format!("发送唤醒包失败: {}", e))?;
        if index + 1 < count {
            thread::sleep(SEND_INTERVAL);
        }
    }

    Ok((dest.to_string(), count))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_mac_accepts_common_formats() {
        let expected = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF];
        for raw in [
            "AA:BB:CC:DD:EE:FF",
            "aa-bb-cc-dd-ee-ff",
            "AABB.CCDD.EEFF",
            "AABBCCDDEEFF",
            "aa bb cc dd ee ff",
        ] {
            assert_eq!(parse_mac(raw), Ok(expected), "raw = {raw}");
        }
    }

    #[test]
    fn parse_mac_rejects_invalid_input() {
        for raw in ["", "AA:BB:CC:DD:EE", "GG:BB:CC:DD:EE:FF", "AA:BB:CC:DD:EE:FFZZ"] {
            assert!(parse_mac(raw).is_err(), "raw = {raw}");
        }
    }

    #[test]
    fn magic_packet_has_sync_header_and_mac_repeats() {
        let mac = [1, 2, 3, 4, 5, 6];
        let packet = build_magic_packet(mac);
        assert_eq!(packet.len(), MAGIC_PACKET_LEN);
        assert_eq!(&packet[..6], &[0xFF; 6]);
        for index in 0..16 {
            let start = 6 + index * 6;
            assert_eq!(&packet[start..start + 6], &mac, "第 {} 段 MAC 不匹配", index + 1);
        }
    }

    #[test]
    fn send_rejects_invalid_address_before_io() {
        assert!(send_magic_packet("AA:BB:CC:DD:EE:FF", "not-an-ip", 9, 3).is_err());
        assert!(send_magic_packet("AA:BB:CC:DD:EE:FF", "fe80::1", 9, 3).is_err());
    }
}
