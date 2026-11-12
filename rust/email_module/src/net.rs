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
        let addrs = resolve_host(&cfg.host, cfg.port)?;
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
    ///
    /// 已扫描水位：每轮 fill 后只从上次扫到的地方继续找 \n。
    /// 从 start 重扫的话，一条 8MB 长行在几十次 fill 下要扫几亿字节（O(n²)）。
    /// 水位是绝对下标，fill 会 drain 掉 start 之前的前缀，所以 drain 后要同步前移。
    pub fn read_line_bytes(&mut self) -> Result<Vec<u8>, String> {
        let mut scanned = self.start;
        loop {
            if let Some(rel) = self.buf[scanned..].iter().position(|b| *b == b'\n') {
                let end = scanned + rel + 1;
                let bytes = self.buf[self.start..end].to_vec();
                self.start = end;
                return Ok(bytes);
            }
            scanned = self.buf.len();
            if self.buf.len() - self.start > MAX_LINE {
                return Err("单行超过 8MB，协议响应异常".to_string());
            }
            let before = self.start;
            self.fill()?;
            // fill 可能把已消费前缀丢掉，水位跟随后移
            let dropped = before - self.start;
            scanned = scanned.saturating_sub(dropped);
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

/// DNS 解析超时：真正的上限。
///
/// `to_socket_addrs` 是同步阻塞的，域名服务器不回包时会一直挂着；
/// 而它挂在**收信线程**上，整个自动记账就静默停摆。所以把解析放进子线程，
/// 这里只带超时等待结果，超时就放弃这轮（调度器下一节拍会重试）。
const DNS_TIMEOUT: Duration = Duration::from_secs(5);

fn resolve_host(host: &str, port: u16) -> Result<Vec<std::net::SocketAddr>, String> {
    let (tx, rx) = std::sync::mpsc::channel();
    let owned_host = host.to_string();
    // 解析线程是 detached 的：即使卡死也不拖住收信线程；
    // 它之后 send 失败是预期的（接收端已超时返回）
    std::thread::spawn(move || {
        let result = (owned_host.as_str(), port)
            .to_socket_addrs()
            .map(|it| it.collect::<Vec<_>>());
        let _ = tx.send(result);
    });
    match rx.recv_timeout(DNS_TIMEOUT) {
        Ok(Ok(addrs)) => Ok(addrs),
        Ok(Err(e)) => Err(format!("解析 {} 失败: {}", host, e)),
        Err(_) => Err(format!(
            "解析 {} 超时（{} 秒）：域名服务器无响应",
            host,
            DNS_TIMEOUT.as_secs()
        )),
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::net::TcpListener;

    /// 起一对回环 TCP，返回 (客户端读端, 服务器写端)。
    /// 用真 socket 而不是内存替身：行读的填充边界（16KB）就是真实读缓冲的粒度。
    fn loopback_pair() -> (TcpStream, TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let client = TcpStream::connect(addr).unwrap();
        let (server, _) = listener.accept().unwrap();
        (client, server)
    }

    fn conn_of(stream: TcpStream) -> Conn {
        Conn {
            stream: Stream::Plain(stream),
            buf: Vec::with_capacity(8 * 1024),
            start: 0,
            timeout: Duration::from_secs(5),
            accept_invalid_certs: false,
            host: "127.0.0.1".to_string(),
        }
    }

    /// P3-16（性能）：一条跨多次 fill 的长行必须完整读回。
    /// 水位优化最典型的回归就是「fill 之后漏扫上一轮尾部」，表现为行被截断或卡死。
    #[test]
    fn long_line_spanning_many_fills_is_read_intact() {
        let (client, mut server) = loopback_pair();
        let mut conn = conn_of(client);

        // 64KB + 少量：必然跨越多个 16KB 填充窗口
        let payload: String = (0..65536 / 4).map(|i| format!("{:04}", i % 10000)).collect();
        let payload_clone = payload.clone();
        let writer = std::thread::spawn(move || {
            // 分几次写，故意让填充边界落在行中间
            for chunk in payload_clone.as_bytes().chunks(7000) {
                server.write_all(chunk).unwrap();
                server.flush().unwrap();
            }
            server.write_all(b"\n").unwrap();
            server.flush().unwrap();
        });

        let line = conn.read_line_bytes().unwrap();
        writer.join().unwrap();

        assert_eq!(line.len(), payload.len() + 1);
        assert_eq!(&line[..line.len() - 1], payload.as_bytes());
        assert_eq!(*line.last().unwrap(), b'\n');
    }

    /// 连续两行：第二行不能因为水位没有重置而丢开头
    #[test]
    fn consecutive_lines_each_start_after_previous_newline() {
        let (client, mut server) = loopback_pair();
        let mut conn = conn_of(client);
        std::thread::spawn(move || {
            server.write_all(b"first line\r\nsecond line\r\nthird").unwrap();
            server.flush().unwrap();
            std::thread::sleep(Duration::from_millis(50));
            server.write_all(b" line\r\n").unwrap();
            server.flush().unwrap();
        });

        assert_eq!(conn.read_line().unwrap(), "first line\r\n");
        assert_eq!(conn.read_line().unwrap(), "second line\r\n");
        // 跨两次填充才凑齐的一行（水位必须跟着上一步的 start 走）
        assert_eq!(conn.read_line().unwrap(), "third line\r\n");
    }

    /// 单行超上限要报错而不是一直吃内存：上限判定用「未消费长度」，不能因为水位算法失效
    #[test]
    fn oversized_line_is_rejected() {
        let (client, mut server) = loopback_pair();
        let mut conn = conn_of(client);
        std::thread::spawn(move || {
            // 持续写不带换行的数据，直到客户端报错断开
            let block = vec![b'A'; 64 * 1024];
            for _ in 0..200 {
                if server.write_all(&block).is_err() {
                    break;
                }
            }
        });

        let err = conn.read_line_bytes().unwrap_err();
        assert!(err.contains("8MB"), "err = {err}");
    }

    /// P2-24：DNS 解析必须有时间上限。
    ///
    /// 不能断言「.invalid 一定失败」：本机装有 DNS 代理时它会回一个假 IP（198.18.x.x），
    /// 这属于环境差异，不是代码问题。这里锁的是**时长**——正是修复的目标：
    /// 旧实现直接阻塞在 to_socket_addrs 上，域名服务器不回包就永远挂着。
    #[test]
    fn dns_lookup_never_blocks_beyond_the_timeout() {
        let started = std::time::Instant::now();
        let _ = resolve_host("no-such-host.invalid", 993);
        let elapsed = started.elapsed();
        assert!(
            elapsed < DNS_TIMEOUT * 3,
            "解析耗时 {:?} 超出上限（应收敛到 {:?} 附近）",
            elapsed,
            DNS_TIMEOUT
        );
    }

    /// 本机回环名要走通正常分支（证明超时包装没有把成功路径也弄坏）
    #[test]
    fn dns_success_path_still_resolves() {
        let addrs = resolve_host("localhost", 80).expect("localhost 必须能解析");
        assert!(!addrs.is_empty());
        assert!(addrs.iter().all(|a| a.port() == 80));
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
