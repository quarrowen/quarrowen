//! HTTP server for the dev dashboard (engine/server/dev_web.gd), on its own threads.
//!
//! tiny_http parses requests (HTTP/1.1, keep-alive, many clients at once) on a background thread and
//! queues them; the game thread takes them with `poll()` and answers with `respond()`, so all game
//! data is still read on the main thread. `/api/stream` is answered here: a Server-Sent Events stream
//! that receives whatever the game pushes with `push()`, instead of the page polling.

use std::collections::HashMap;
use std::io::Write;
use std::net::ToSocketAddrs;
use std::sync::mpsc::{self, Receiver, SyncSender, TryRecvError, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

use godot::prelude::*;
use tiny_http::{Header, Request, Response, Server, StatusCode};

const MAX_URL: usize = 16 * 1024;
/// Messages a slow stream may fall behind by before it misses pushes.
const STREAM_BACKLOG: usize = 64;
const KEEPALIVE: Duration = Duration::from_secs(15);

type Streams = Arc<Mutex<Vec<SyncSender<Arc<Vec<u8>>>>>>;

struct Running {
    server: Arc<Server>,
    accept: Option<JoinHandle<()>>,
    incoming: Receiver<Request>,
    pending: HashMap<i64, Request>,
    streams: Streams,
    next_id: i64,
    port: u16,
}

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeHttpServer {
    running: Option<Running>,
}

#[godot_api]
impl NativeHttpServer {
    /// Listens on `host:port` ("*" or "0.0.0.0" for every interface, port 0 for any free port).
    /// `stream_token`: the token `/api/stream?token=` must carry. Returns "" or why it failed.
    #[func]
    fn listen(&mut self, host: GString, port: i64, stream_token: GString) -> GString {
        self.stop();
        let host = host.to_string();
        let host = if host == "*" { "0.0.0.0".to_string() } else { host };
        let addr = match (host.as_str(), port.clamp(0, 65535) as u16).to_socket_addrs().ok().and_then(|mut a| a.next()) {
            Some(addr) => addr,
            None => return GString::from(format!("cannot resolve {host}").as_str()),
        };
        let server = match Server::http(addr) {
            Ok(server) => Arc::new(server),
            Err(err) => return GString::from(err.to_string().as_str()),
        };
        let port = server.server_addr().to_ip().map(|a| a.port()).unwrap_or(0);
        let (sender, incoming) = mpsc::channel();
        let streams: Streams = Arc::new(Mutex::new(Vec::new()));
        let accept = {
            let server = server.clone();
            let streams = streams.clone();
            let token = stream_token.to_string();
            std::thread::Builder::new()
                .name("dev-web-accept".into())
                .spawn(move || accept_loop(server, sender, streams, token))
                .ok()
        };
        self.running = Some(Running { server, accept, incoming, pending: HashMap::new(), streams, next_id: 0, port });
        GString::new()
    }

    /// The port actually listened on (useful with port 0), or 0 when stopped.
    #[func]
    fn port(&self) -> i64 {
        self.running.as_ref().map_or(0, |r| r.port as i64)
    }

    #[func]
    fn is_listening(&self) -> bool {
        self.running.is_some()
    }

    /// Requests waiting for an answer: [{id, method, path, query}]. Each must get `respond()`.
    #[func]
    fn poll(&mut self) -> VarArray {
        let mut out = VarArray::new();
        let Some(running) = self.running.as_mut() else { return out };
        loop {
            match running.incoming.try_recv() {
                Ok(request) => {
                    running.next_id += 1;
                    let url = request.url().to_string();
                    let (path, query) = url.split_once('?').unwrap_or((url.as_str(), ""));
                    let mut entry = VarDictionary::new();
                    entry.set("id", running.next_id);
                    entry.set("method", &GString::from(request.method().as_str()));
                    entry.set("path", &GString::from(path));
                    entry.set("query", &GString::from(query));
                    out.push(&entry.to_variant());
                    running.pending.insert(running.next_id, request);
                }
                Err(TryRecvError::Empty) | Err(TryRecvError::Disconnected) => break,
            }
        }
        out
    }

    /// Answers request `id`. The response is written on a helper thread so a slow client cannot
    /// stall the game.
    #[func]
    fn respond(&mut self, id: i64, status: i64, content_type: GString, body: PackedByteArray) {
        let Some(request) = self.running.as_mut().and_then(|r| r.pending.remove(&id)) else { return };
        let mut response = Response::from_data(body.to_vec()).with_status_code(StatusCode(status.clamp(100, 599) as u16));
        for (name, value) in [
            ("Content-Type", content_type.to_string()),
            ("Cache-Control", "no-store".to_string()),
            ("X-Content-Type-Options", "nosniff".to_string()),
        ] {
            if let Ok(header) = Header::from_bytes(name.as_bytes(), value.as_bytes()) {
                response.add_header(header);
            }
        }
        let _ = std::thread::Builder::new().name("dev-web-respond".into()).spawn(move || {
            let _ = request.respond(response);
        });
    }

    /// Sends a Server-Sent Event to every open `/api/stream`. Returns how many streams got it.
    #[func]
    fn push(&mut self, event: GString, data: GString) -> i64 {
        let Some(running) = self.running.as_ref() else { return 0 };
        let mut message = format!("event: {event}\n");
        for line in data.to_string().split('\n') {
            message.push_str("data: ");
            message.push_str(line);
            message.push('\n');
        }
        message.push('\n');
        let message = Arc::new(message.into_bytes());
        let mut streams = running.streams.lock().unwrap();
        let mut delivered = 0;
        streams.retain(|s| match s.try_send(message.clone()) {
            Ok(()) => {
                delivered += 1;
                true
            }
            Err(TrySendError::Full(_)) => true,
            Err(TrySendError::Disconnected(_)) => false,
        });
        delivered
    }

    /// Open event streams (closed ones are noticed on the next push).
    #[func]
    fn stream_count(&self) -> i64 {
        self.running.as_ref().map_or(0, |r| r.streams.lock().unwrap().len() as i64)
    }

    #[func]
    fn stop(&mut self) {
        if let Some(mut running) = self.running.take() {
            running.server.unblock();
            running.streams.lock().unwrap().clear();
            running.pending.clear();
            if let Some(accept) = running.accept.take() {
                let _ = accept.join();
            }
        }
    }
}

impl Drop for NativeHttpServer {
    fn drop(&mut self) {
        self.stop();
    }
}

fn accept_loop(server: Arc<Server>, sender: mpsc::Sender<Request>, streams: Streams, token: String) {
    for request in server.incoming_requests() {
        let url = request.url().to_string();
        if url.len() > MAX_URL {
            let _ = request.respond(Response::from_string("request too large").with_status_code(414));
            continue;
        }
        let (path, query) = url.split_once('?').unwrap_or((url.as_str(), ""));
        if path == "/api/stream" {
            if query_value(query, "token").as_deref() != Some(token.as_str()) || token.is_empty() {
                let _ = request.respond(Response::from_string("{\"error\": \"bad token\"}").with_status_code(403));
            } else {
                open_stream(request, &streams);
            }
            continue;
        }
        if sender.send(request).is_err() {
            break;
        }
    }
}

fn open_stream(request: Request, streams: &Streams) {
    let (sender, receiver) = mpsc::sync_channel::<Arc<Vec<u8>>>(STREAM_BACKLOG);
    streams.lock().unwrap().push(sender);
    let _ = std::thread::Builder::new().name("dev-web-stream".into()).spawn(move || {
        let mut writer = request.into_writer();
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nX-Accel-Buffering: no\r\nConnection: close\r\n\r\nretry: 3000\n\n";
        if writer.write_all(head.as_bytes()).and_then(|_| writer.flush()).is_err() {
            return;
        }
        loop {
            let bytes: Arc<Vec<u8>> = match receiver.recv_timeout(KEEPALIVE) {
                Ok(message) => message,
                Err(mpsc::RecvTimeoutError::Timeout) => Arc::new(b": keepalive\n\n".to_vec()),
                Err(mpsc::RecvTimeoutError::Disconnected) => return,
            };
            if writer.write_all(&bytes).and_then(|_| writer.flush()).is_err() {
                return;
            }
        }
    });
}

fn query_value(query: &str, key: &str) -> Option<String> {
    query.split('&').find_map(|pair| {
        let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
        (k == key).then(|| v.to_string())
    })
}
