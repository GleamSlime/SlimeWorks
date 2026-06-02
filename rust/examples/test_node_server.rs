/// 独立验证 node_server 是否能正常绑定并响应 HTTP
///
/// 直接用 hyper 在独立线程启动一个最小 HTTP server，验证机制本身可行。
use hyper::service::{make_service_fn, service_fn};
use hyper::{Body, Request, Response, Server};
use std::convert::Infallible;
use std::sync::Mutex;
use tokio::sync::oneshot;

struct Handle {
    shutdown_tx: oneshot::Sender<()>,
}

static SERVER: Mutex<Option<Handle>> = Mutex::new(None);

fn start(port: u16) -> Result<(), String> {
    let mut guard = SERVER.lock().unwrap();
    if let Some(old) = guard.take() {
        let _ = old.shutdown_tx.send(());
        std::thread::sleep(std::time::Duration::from_millis(200));
    }

    let addr: std::net::SocketAddr = format!("0.0.0.0:{}", port).parse().unwrap();
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<(), String>>();

    std::thread::Builder::new()
        .name("test-server".into())
        .spawn(move || {
            let rt = tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .unwrap();
            rt.block_on(async move {
                let make_svc = make_service_fn(|_| async {
                    Ok::<_, Infallible>(service_fn(|_req: Request<Body>| async {
                        Ok::<_, Infallible>(Response::new(Body::from(r#"{"ok":true}"#)))
                    }))
                });
                let builder = match Server::try_bind(&addr) {
                    Ok(b) => {
                        let _ = ready_tx.send(Ok(()));
                        b
                    }
                    Err(e) => {
                        let _ = ready_tx.send(Err(e.to_string()));
                        return;
                    }
                };
                let graceful = builder.serve(make_svc).with_graceful_shutdown(async {
                    shutdown_rx.await.ok();
                });
                if let Err(e) = graceful.await {
                    eprintln!("server err: {}", e);
                }
            });
        })
        .map_err(|e| e.to_string())?;

    match ready_rx.recv_timeout(std::time::Duration::from_secs(5)) {
        Ok(Ok(())) => {
            *guard = Some(Handle { shutdown_tx });
            Ok(())
        }
        Ok(Err(e)) => Err(e),
        Err(_) => Err("timeout".into()),
    }
}

fn main() {
    println!("==> 启动最小 HTTP server on :17888...");
    match start(17888) {
        Ok(()) => println!("==> bind 成功"),
        Err(e) => {
            eprintln!("==> 失败: {}", e);
            std::process::exit(1);
        }
    }

    std::thread::sleep(std::time::Duration::from_millis(300));

    println!("==> curl http://127.0.0.1:17888/health");
    let out = std::process::Command::new("curl")
        .args(["-sv", "http://127.0.0.1:17888/health"])
        .output()
        .expect("curl failed");
    println!("stdout: {}", String::from_utf8_lossy(&out.stdout));
    println!("stderr: {}", String::from_utf8_lossy(&out.stderr));
    if out.status.success() {
        println!("==> OK - server 响应正常");
    } else {
        eprintln!("==> FAIL - curl exit {}", out.status);
        std::process::exit(1);
    }
}
