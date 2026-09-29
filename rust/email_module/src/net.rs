//! TCP + TLS 的最小连接体：行读、定长读、读写超时、明文升 TLS。
//!
//! 不用 BufReader/split 的组合是因为协议读要"行"和"字面量字节块"交替：
//! IMAP 的 `{1234}` 之后必须精确读 1234 字节，缓冲层自己做最直接。

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use crate::types::EmailAccountConfig;

/// 单行上限：邮件头偶尔很长，但超过这个量就是跑偏了
const MAX_LINE: usize = 8 * 1024 * 1024;

pub enum Stream {
    Plain(TcpStream),
    Tls(native_tls::TlsStream<TcpStream>),
}

impl Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.read(buf),
            Stream::Tls(s) => s.read(buf),
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.write(buf),
            Stream::Tls(s) => s.write(buf),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Stream::Plain(s) => s.flush(),
            Stream::Tls(s) => s.flush(),
        }
    }
}

pub struct Conn {
    stream: Stream,
    buf: Vec<u8>,
    start: usize,
    timeout: Duration,
    accept_invalid_certs: bool,
    host: String,
}

impl Conn {
    /// 建立连接；use_ssl 时直接套 TLS（IMAP 993 / POP3 995 / SMTP 465）
    pub fn connect(cfg: &EmailAccountConfig) -> Result<Conn, String> {
        let timeout = Duration::from_secs(cfg.timeout_secs.max(1));
        let addrs = (cfg.host.as_str(), cfg.port)
            .to_socket_addrs()
            .map_err(|e| format!("解析 {} 失败: {}", cfg.host, e))?;
        let mut tcp: Option<TcpStream> = None;
        let mut last_err = String::new();
        for addr in addrs {
            match TcpStream::connect_timeout(&addr, timeout) {
                Ok(s) => {
                    tcp = Some(s);
                    break;
                }
                Err(e) => last_err = format!("{} ({})", e, addr),
            }
        }
        let tcp = tcp.ok_or_else(|| format!("连接 {}:{} 失败: {}", cfg.host, cfg.port, last_err))?;
        tcp.set_read_timeout(Some(timeout))
            .map_err(|e| format!("设置读超时失败: {}", e))?;
        tcp.set_write_timeout(Some(timeout))
            .map_err(|e| format!("设置写超时失败: {}", e))?;
        tcp.set_nodelay(true).ok();

        let accept_invalid = cfg.accept_invalid_certs;
        let stream = if cfg.use_ssl {
            wrap_tls(&tcp, &cfg.host, accept_invalid)?
        } else {
            Stream::Plain(tcp)
        };
        Ok(Conn {
            stream,
            buf: Vec::with_capacity(8 * 1024),
            start: 0,
            timeout,
            accept_invalid_certs: accept_invalid,
            host: cfg.host.clone(),
        })
    }

    /// 明文连接升到 TLS（SMTP 的 STARTTLS）
    pub fn upgrade_tls(&mut self) -> Result<(), String> {
        let tcp = match &self.stream {
            Stream::Plain(s) => s.try_clone().map_err(|e| format!("克隆连接失败: {}", e))?,
            Stream::Tls(_) => return Err("连接已经是 TLS".to_string()),
        };
        let tls = wrap_tls(&tcp, &self.host, self.accept_invalid_certs)?;
        self.stream = tls;
        // 升级前缓冲里可能已经躺着明文尾巴，TLS 之后必须作废
        self.buf.clear();
        self.start = 0;
        Ok(())
    }

    pub fn has_tls(&self) -> bool {
        matches!(self.stream, Stream::Tls(_))
    }

    /// 读一行（含结尾的 \n）；超时/EOF 都当错误，让调用方不必区分
    pub fn read_line(&mut self) -> Result<String, String> {
        Ok(String::from_utf8_lossy(&self.read_line_bytes()?).into_owned())
    }

    /// 按字节读一行：正文里的 GBK/Big5 字节必须先原样保住，
    /// 过早 lossy 转换会把正文变成一串 U+FFFD。
    pub fn read_line_bytes(&mut self) -> Result<Vec<u8>, String> {
        loop {
            if let Some(rel) = self.buf[self.start..].iter().position(|b| *b == b'\n') {
                let end = self.start + rel + 1;
                let bytes = self.buf[self.start..end].to_vec();
                self.start = end;
                return Ok(bytes);
            }
            if self.buf.len() - self.start > MAX_LINE {
                return Err("单行超过 8MB，协议响应异常".to_string());
            }
            self.fill()?;
        }
    }

    /// 精确读 n 字节（IMAP literal）
    pub fn read_exact_bytes(&mut self, n: usize) -> Result<Vec<u8>, String> {
        while self.buf.len() - self.start < n {
            self.fill()?;
        }
        let out = self.buf[self.start..self.start + n].to_vec();
        self.start += n;
        Ok(out)
    }

    fn fill(&mut self) -> Result<(), String> {
        if self.start > 0 {
            // 把已消费的前缀丢掉，避免缓冲无限增长
            self.buf.drain(..self.start);
            self.start = 0;
        }
        let mut tmp = [0u8; 16 * 1024];
        match self.stream.read(&mut tmp) {
            Ok(0) => Err("连接被服务器关闭（读超时或未收到预期响应）".to_string()),
            Ok(n) => {
                self.buf.extend_from_slice(&tmp[..n]);
                Ok(())
            }
            Err(e) => {
                if e.kind() == std::io::ErrorKind::WouldBlock || e.kind() == std::io::ErrorKind::TimedOut {
                    Err(format!("等待响应超时（{} 秒）", self.timeout.as_secs()))
                } else {
                    Err(format!("读取失败: {}", e))
                }
            }
        }
    }

    pub fn write_all(&mut self, data: &[u8]) -> Result<(), String> {
        self.stream
            .write_all(data)
            .map_err(|e| format!("发送失败: {}", e))?;
        self.stream.flush().map_err(|e| format!("刷新失败: {}", e))
    }

    pub fn write_line(&mut self, line: &str) -> Result<(), String> {
        let mut bytes = line.as_bytes().to_vec();
        bytes.extend_from_slice(b"\r\n");
        self.write_all(&bytes)
    }

    pub fn quit(&mut self) {
        let _ = self.write_all(b"QUIT\r\n");
    }
}

fn wrap_tls(tcp: &TcpStream, host: &str, accept_invalid_certs: bool) -> Result<Stream, String> {
    let connector = native_tls::TlsConnector::builder()
        .danger_accept_invalid_certs(accept_invalid_certs)
        .danger_accept_invalid_hostnames(accept_invalid_certs)
        .build()
        .map_err(|e| format!("初始化 TLS 失败: {}", e))?;
    // connect 会吃掉 socket，先克隆一份：握手失败时调用方的明文连接还在
    let owned = tcp.try_clone().map_err(|e| format!("克隆连接失败: {}", e))?;
    match connector.connect(host, owned) {
        Ok(tls) => Ok(Stream::Tls(tls)),
        Err(e) => Err(format!(
            "TLS 握手失败: {}（host={}）；自签证书请在规则里勾选\"接受不受信任的证书\"",
            e, host
        )),
    }
}
