# 节点服务（Node Server）安全加固方案

> 状态：**设计文档，未实施**。本文只给出方案与落地顺序，不含代码改动。
> 前提：SlimeWorks 当前只在个人/局域网环境使用、不分发公网，因此本节所有条目均为
> 「需要知道 + 择机加固」，而不是「立即修复」。请不要把本文中的条目当作已实现能力。

---

## 1. 现状事实（已核对代码）

| 项 | 现状 | 位置 |
|----|------|------|
| 监听地址 | 硬编码 `0.0.0.0`（IPv4 全网卡），端口用户可配 | `lib/core/services/node/node_settings_service.dart:277` |
| 服务端实现 | 手写 raw TCP HTTP/1.1 服务器，线程模型为「一连接一线程」，上限 30 | `rust/src/node_server/mod.rs:83`、`:660`、`:680` |
| 鉴权 | **完全没有**：无 token、无配对、无来源校验 | `rust/src/node_server/mod.rs:163-560` 路由表 |
| CORS | 所有响应固定 `Access-Control-Allow-Origin: *`，OPTIONS 预检允许 GET/POST/DELETE | `mod.rs:220`、`:564`、`:577` |
| 本地文件读取 | `GET /node/media?path=...` 直接对参数路径 `File::open`，无根目录白名单 | `rust/src/node_server/media_handler.rs:79`、`serve_media_file_with_range()` |
| 凭据回显 | `GET /manga/token` 无鉴权返回 PC 侧 Manga 登录态 | `rust/src/node_server/mod.rs:274` |
| 写操作 | `POST /node/call` 按 `action` 分发到各模块（含删除、导入、重命名等写路径） | `rust/src/node_server/mod.rs:171` → `handlers::dispatch_action` |
| 日志面 | `/sentry/events/delete_batch`、`/sentry/projects/rename`、`/sentry/export` 均无鉴权 | `rust/src/node_server/mod.rs:455/473/495` |
| 请求体读取 | 有 10 秒读超时，但 **没有 Content-Length 上限**：`vec![0u8; content_length]` 直接按客户端声明的头部值分配 | `mod.rs:106`、`:135-156` |
| 上传 | `POST /node/upload` 是**未实现的桩**，固定返回错误（因此当前不构成写盘面） | `rust/src/node_server/handlers.rs:1074` |
| TLS | 明文 HTTP；移动端通过 HTTP 中转 PC 节点 | 同上 |
| 证书校验关闭 | `danger_accept_invalid_certs(true)` | `rust/manga_module/src/client.rs:973`、`rust/power_stats/src/client.rs:18`（`rust/game_library/src/api.rs:1408` 已显式为 `false`） |
| iOS ATS | `NSAllowsArbitraryLoads` 开启，允许任意 http 明文 | `ios/Runner/Info.plist:87` |
| 根证书安装 | capture_proxy 用 `echo '<pwd>' \| /usr/bin/sudo -S security add-trusted-cert ...` 拼 shell 串 | `rust/capture_proxy/src/cert.rs:283` |
| `.env` | 被列进 `pubspec.yaml` assets 随包分发；**内容仅含窗口尺寸与 ffmpeg 下载 URL，无凭据**，且已 gitignore | `pubspec.yaml:139`、`.gitignore:50` |
| CI 密钥 | PGYER key 走 `${{ secrets.* }}`（正确），但以 `-F "_api_key=..."` 形式出现在命令行，构建机上 `ps` 可见 | `.github/workflows/release.yml:415-427` |

> 说明：`.env` 与 PGYER 两项经复核**不构成凭据泄露**，属于低优先级的打包/进程可见性卫生问题，
> 之前审计中的「密钥泄露」表述需要按本表修正。

---

## 2. 风险与影响（局域网内、无鉴权的前提下）

1. **同网段任意设备可读取本机任意文件**：`/node/media?path=/Users/x/.ssh/id_rsa` 只要路径可猜/可遍历即可读取，
   不受媒体库范围限制。这是本项目最实质的一条。
2. **任意模块写操作**：`/node/call` 可调用注册过的 action，包含删除集合/删除事件/导入等，等价于
   「局域网内任何人拿到你媒体库的读写权」。
3. **凭据外带**：`/manga/token` 让任意局域网设备取走 Manga 登录态并冒用账号。
4. **浏览器侧间接利用**：所有响应带 `Access-Control-Allow-Origin: *`，浏览器里的任意网页既能**发出**这些请求，
   也能**读到响应内容**（不限于「简单请求」，预检也被允许）。用户访问恶意网页时，§2 的 1/2/3 可被远程网页驱动完成。
5. **无界内存分配**：`Content-Length` 由客户端声明且无上限，服务端先 `vec![0u8; content_length]` 再读体，
   一个声明超大长度的 POST 就能把 PC 端连接线程打到 OOM（10 秒读超时救不了已经完成的分配）。
   属于可用性风险；吞吐/并发侧的性能问题已单独处理（见 §5）。

---

## 3. 加固方案（分四层，可独立启用）

### L1 收敛监听面（改动最小，收益最大）

- 默认 `127.0.0.1`；对外服务改为显式开关，且开关只提供两种模式：
  「仅指定网段」或「需要配对」。UI 上不允许「全网卡 + 无鉴权」这一组合。
- 端口配置项增加校验：禁止 80/443/53 等；启动前打印实际 `host:port` 与暴露级别。
- 验收：`lsof -nP -iTCP -sTCP:LISTEN` 在默认配置下只出现 `127.0.0.1`；
  开启「仅 192.168.1.0/24」后外部网段连接被拒。

### L2 配对 + 请求签名（跨端协议变更，需要移动端与 PC 端同时升级）

- **配对**：PC 端「添加设备」生成一次性配对码（8 位、60 秒有效、只能成功兑换一次），
  移动端输入后换发长期 `device_token`（随机 32 字节）与设备名，PC 端保存 token 哈希（不落明文）。
- **签名**：每个请求带 `X-SW-Device`、`X-SW-Timestamp`、`X-SW-Nonce`、`X-SW-Signature`，
  签名 = `HMAC-SHA256(device_token, METHOD \n PATH \n QUERY \n SHA256(BODY) \n TIMESTAMP \n NONCE)`。
  服务端校验时间窗 ±120s，nonce 在窗口内去重（有界 LRU，避免重放）。
- **降级路径**：仅对 `/health`、`/manga/ping` 保留免鉴权（探活用），其余一律 401。
- **撤权**：PC 端设备列表支持吊销，吊销即从 redb 删除 token 哈希；移动端下次请求失败并提示重新配对。
- 验收：新增集成测试覆盖 缺头/错签/过期时间戳/重放 nonce/已吊销设备 五种用例，全部 401。

### L3 资源范围最小化（防「任意文件」与「凭据外带」）

- **路径白名单**：`/node/media`、缩略图批处理、`/node/call` 中所有带 `path` 的 action，
  统一经过一个 `resolve_within_allowed_roots(path)`：
  `canonicalize()` 解析符号链接 → 必须 `starts_with` 于「已注册媒体根目录 + 应用数据目录 + 缩略图 tmp 目录」
  三者之一，否则拒绝。禁止把用户传入的绝对路径直接 `File::open`。
- **禁止目录穿越**：拒绝含 `..` 分段与 NUL；对 URL 解码后再判断（当前解码点见 `mod.rs:200`、`:320`、`:615`）。
- **`/manga/token` 重做**：改为 `POST /manga/relay` 内部使用，节点服务永不明文回吐 token；
  移动端只发业务请求，PC 侧代签代发（该能力现已存在：`/manga/api`、`/manga/img`）。
- **能力开关**：`/sentry/*`、`/aliyun/*`、`/node/call` 的写类 action 各自受节点设置里的独立开关控制，
  默认只开「读媒体」。
- **请求体上限**：解析头部后先判断 `content_length > MAX_BODY` 就直接回 413，再分配缓冲；
  上限按 action 区分（JSON 调用 1-4MB，未来的上传另行放大），并把 `unwrap_or(0)` 的静默降级改成显式 400。
- **收紧 CORS**：`Access-Control-Allow-Origin` 从 `*` 改为按已配对设备/显式白名单回源，缺省不回 CORS 头。
- 验收：`/node/media?path=/etc/passwd`、`?path=../../..%2fetc/passwd`、含 NUL 的参数均 403；
  媒体库内的合法路径与缩略图路径行为不变。

### L4 传输与依赖卫生（可选，成本较高）

- **TLS**：内网自签 + 客户端 pin（移动端保存 PC 指纹）比「随便找个 CA」更安全，但会带来证书轮换与
  配对流程复杂化。建议仅在跨不可信网络（异地/组网工具）时启用；纯家庭内网可停留在 L1-L3。
- **ATS 收紧**：完成 TLS 后把 `ios/Runner/Info.plist:87` 的 `NSAllowsArbitraryLoads` 改为按域名例外
  （`NSAppTransportSecurity` → `NSExceptionDomains` 仅允许局域网节点），而不是全局放开。
- **`danger_accept_invalid_certs(true)`**：`manga_module`（自签/中转链路）与 `power_stats`（cnyiot 证书链不完整）
  改为「内置根证书/中间证书 + 正常校验」，或至少按域名精确例外，避免全局关闭校验。
- **sudo 安装根证书**：`capture_proxy/src/cert.rs:283` 改为 `Command::new(sudo).args([...])` 传参、
  密码走 `sudo -S` 的 stdin 而非拼进 shell 字符串，消除引号注入面；或改用 macOS `security` 的用户级钥匙串
  避免提权。
- **CI**：`_api_key` 改用 `curl --form _api_key="<${PGYER_API_KEY}"`（`<` 读文件）或临时 netrc，避免 `ps` 可见；
  `.env` 从 `pubspec.yaml` assets 中移除（当前无凭据，属卫生项）。

---

## 4. 建议落地顺序

1. L1（半天，无协议变更）→ 立刻消除「默认全网卡」暴露。
2. L3 的路径白名单与 `/manga/token` 重做（1 天，无协议变更）→ 消除 §2 中最实的 1、3 两条。
3. L2 配对 + 签名（2-3 天，含移动端改造与兼容窗口）→ 之后才谈「可以给同事/另一台设备开外网访问」。
4. L3 能力开关（0.5 天）。
5. L4 按需排期，不与前三项绑定。

兼容窗口建议：L2 上线后保留 1 个大版本的「免鉴权局域网模式」开关，并在 UI 上标红提示风险，
避免移动端旧版本直接不可用；到期后移除。

---

## 5. 与性能改动的边界（本分支已完成，避免混淆）

以下属于本轮**性能**修复，不代表安全问题已解决：

- `node_server` runtime 由 `worker_threads(2)` 提升到按 CPU 自适应并解除与 30 连接上限的冲突；
  ffmpeg/文件读/`Condvar::wait` 等阻塞工作移入 `spawn_blocking`。
- Range 解析的 u64 下溢修复 + 正则预编译（`media_handler.rs`）。
- redb 批量单事务导入、缩略图并发生成与常见位图跳过 ffmpeg、音乐扫描目录索引、
  game_library N+1 与 WAL、`reqwest::Client` 复用。

安全侧仍待处理的本质问题只有一句话：**任何能连到该端口的人 = 你的媒体库读 + 大部分模块写**。
唯一已经落地的是授权码校验（见 §6），它把「能连就能读」改成了「没有授权码就读不到」。

---

## 6. 已落地：节点授权码（L2 的简化版）

L2 的完整配对/签名尚未实现，先落了成本最低的一档：**共享授权码**。

- **生成/存储**：`NodeSettingsService` 在首次加载时用 `Random.secure()` 生成 16 位十六进制授权码
  （形如 `ABCD-1234-...`，分 4 段），存 SharedPreferences 键 `node_local_auth_code`；
  设置页开启本机节点后展示该码，复制按钮写入剪切板，重置按钮换发新码并重建监听。
- **传输形态**：明文只在生成/复制时出现。运行时发送与存储的都是它的 sha256 摘要：
  Rust `NodeServerConfig` 只保留 `auth_code_hash`（`rust/src/node_server/mod.rs`），
  启动日志只打印"是否启用校验"，不落摘要。摘要必须与 Dart 侧 `NodeSettingsService.authCodeDigest`
  一致，`test/node_auth_code_test.dart` 用 sha256 标准向量钉住这一点。
- **请求头**：`X-SW-Auth: <sha256(授权码)>`，由 Dio 拦截器 `_NodeAuthInterceptor` 按请求 URL 匹配节点后注入，
  覆盖 `/node/call`、`/node/upload` 与连通性探测。
- **媒体 URL 例外**：图片/视频 URL 会直接交给 `Image.network` 与播放器，拿不到自定义请求头，
  因此 `/node/media` 额外接受同一份摘要以 `?sw_auth=<hex>` 提供（`AUTH_QUERY_PARAM`）。
  摘要出现在 URL 里意味着它会进入访问日志/代理日志，属已知取舍；
  若要收紧，需要把媒体取回改走带请求头的 Dio 缓存层。
- **放行面**：`/health` 与 `OPTIONS` 预检保持免鉴权——客户端要靠 `/health` 区分"节点不在线"和
  "授权码不对"，否则只能报"不可达"。
- **校验位置**：401 在读取请求体之前返回，未授权请求的 body 不进内存，顺带堵掉
  超大 `Content-Length` 打爆节点内存这条最省事的打法（对应 L3 的请求体上限项，仍未做）。
- **兼容**：授权码为空 = 不校验，旧部署与未配置的节点行为不变；401 在 UI 上显示为
  「授权码错误，请核对节点授权码」，且不触发熔断（节点是在线的）。

仍不解决的问题：摘要即凭据（拿到码即等同拿到库），无设备维度、无重放保护、无 TLS，
明文 HTTP 下抓取包仍可复用该摘要。要按 §3 L2 升级为配对 + HMAC 签名。

---

## 7. 已落地：归档上传端点 `POST /node/upload/archive`

给「在远程文件夹内拖入本地目录」用的传输通道（`rust/src/node_server/upload_handler.rs`）。

- **协议**：请求体是 zip 的**原始字节流**（非 multipart），`?dest=<绝对路径>`；
  节点用 `io::copy` 流式写入 `std::env::temp_dir()/sw_upload_<millis>.zip`，收满后调
  `extract_module::extractor::extract_archive` 解压到 `dest`，最后无论成败删除临时 zip。
  这样大目录不会像通用 body 路径那样 `vec![0u8; content_length]` 全量进内存。
- **配额**：`MAX_UPLOAD_BYTES = 8 GiB`，超出返回 413；实收字节与 `Content-Length` 不符按 400 处理并清理。
- **鉴权**：与普通路由同一道门——401 在读体之前返回，没有授权码连不上上传。
- **落点校验**：`validate_dest` 只接受非空、无 NUL、**绝对路径**且**当前已存在**的目录，
  节点不会因为一个请求就在磁盘上凭空建目录树。正常客户端的 `dest` 来自节点自己回传的
  `resolve_folder_upload_target`（库内集合的磁盘父目录）或节点目录浏览器，路径不出节点。
- **解压穿越**：zip 条目走 `enclosed_name()`，`../` 与绝对路径条目被丢弃；
  客户端打包侧 `zip_directory_to_tmp` 也拒绝含分隔符/`..` 的 `entry_root`（有测试钉住）。

残留风险（本轮按约定只记录不改码）：

1. `dest` 仍是**调用方给的绝对路径**：拿到授权码 = 能往节点机器上任意已存在目录写文件，
   没有"只能写进媒体库根目录之下"的白名单（对应 §3 L3）。
2. 落点存在性检查与写入之间有 TOCTOU 窗口；解压本身也会覆盖同名文件。
3. 只有单次体积上限，没有按节点/按天的存储配额，也没有速率限制。
4. 请求体按嗅探出的格式分派（zip/7z/tar…），非 zip 格式的穿越防护依赖各 crate 的默认行为。

