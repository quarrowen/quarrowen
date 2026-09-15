//! VoxelCraft hub: the public server list, short invite codes and news for game menus.
//!
//! Game servers announce themselves every HEARTBEAT seconds with a request signed by their server key;
//! the first announce from an address (and every VERIFY_EVERY after) is checked with a UDP status
//! query that the server must answer with a signature, so nobody can list someone else's address or
//! take over another server's entry. Entries expire after EXPIRE seconds of silence.
//!
//! Configuration (environment):
//!   HUB_BIND=0.0.0.0:24600     address to listen on
//!   HUB_DATA=./hub-data        SQLite database and news.json
//!   HUB_ALLOW_PRIVATE=0        1 lists servers on private/loopback addresses (a LAN or local hub)
//!   HUB_TRUST_PROXY=0          1 takes the client address from X-Forwarded-For (behind a reverse proxy)
//!
//! API (JSON):
//!   POST /v1/servers/announce  body {key, time, port, query_port, address?, name, motd, game, game_name,
//!                              players, max_players, protocol, version, tags}, header X-Voxel-Signature
//!                              (base64 signature of the body) -> {id, code, heartbeat}
//!   POST /v1/servers/leave     body {key, time}, signed -> {ok}
//!   GET  /v1/servers?game=&q=&limit=&offset=   -> {servers: [...], total}
//!   GET  /v1/codes/{code}      -> {code, address, port, name, online}
//!   GET  /v1/news              -> [{title, body, url?, date?}] from HUB_DATA/news.json
//!   GET  /healthz

mod keys;
mod limits;
mod status;
mod store;

use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use axum::body::Bytes;
use axum::extract::{ConnectInfo, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const HEARTBEAT: u64 = 30;
const EXPIRE: Duration = Duration::from_secs(95);
const VERIFY_EVERY: Duration = Duration::from_secs(600);
const MAX_BODY: usize = 16 * 1024;
const CLOCK_SKEW: i64 = 300;
const MAX_SERVERS: usize = 20_000;

#[derive(Clone)]
struct Config {
    allow_private: bool,
    trust_proxy: bool,
    data: PathBuf,
}

struct Hub {
    config: Config,
    store: store::Store,
    servers: Mutex<HashMap<String, Entry>>,
    limiter: limits::Limiter,
}

#[derive(Clone, Serialize)]
struct Listing {
    id: String,
    code: String,
    address: String,
    port: u16,
    name: String,
    motd: String,
    game: String,
    game_name: String,
    players: u32,
    max_players: u32,
    protocol: i64,
    version: String,
    tags: Vec<String>,
}

#[derive(Clone)]
struct Entry {
    listing: Listing,
    query_port: u16,
    last_seen: Instant,
    verified_at: Instant,
}

#[derive(Deserialize)]
struct Announce {
    key: String,
    time: i64,
    port: u16,
    #[serde(default)]
    query_port: u16,
    #[serde(default)]
    address: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    motd: String,
    #[serde(default)]
    game: String,
    #[serde(default)]
    game_name: String,
    #[serde(default)]
    players: u32,
    #[serde(default)]
    max_players: u32,
    #[serde(default)]
    protocol: i64,
    #[serde(default)]
    version: String,
    #[serde(default)]
    tags: Vec<String>,
}

#[derive(Deserialize)]
struct Leave {
    key: String,
    time: i64,
}

#[derive(Deserialize)]
struct ListQuery {
    game: Option<String>,
    q: Option<String>,
    limit: Option<usize>,
    offset: Option<usize>,
}

fn error(status: StatusCode, message: impl Into<String>) -> Response {
    (status, Json(json!({"error": message.into()}))).into_response()
}

fn now_unix() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn clip(text: &str, max_chars: usize) -> String {
    text.chars().filter(|c| !c.is_control()).take(max_chars).collect()
}

fn client_ip(hub: &Hub, headers: &HeaderMap, peer: SocketAddr) -> IpAddr {
    if hub.config.trust_proxy {
        if let Some(ip) = headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()).and_then(|v| v.split(',').next()).and_then(|v| v.trim().parse().ok()) {
            return ip;
        }
    }
    peer.ip()
}

fn is_private(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => v4.is_private() || v4.is_loopback() || v4.is_link_local() || v4.is_unspecified(),
        IpAddr::V6(v6) => v6.is_loopback() || v6.is_unspecified() || (v6.segments()[0] & 0xfe00) == 0xfc00,
    }
}

/// Parses and checks a signed request: body size, signature, clock. Returns the key.
fn signed_key(headers: &HeaderMap, body: &[u8], key_pem: &str, time: i64) -> Result<keys::PublicKey, Response> {
    let key = keys::PublicKey::from_pem(key_pem).map_err(|e| error(StatusCode::BAD_REQUEST, e))?;
    let signature = headers.get("x-voxel-signature").and_then(|v| v.to_str().ok()).unwrap_or("");
    if !key.verify(body, signature) {
        return Err(error(StatusCode::UNAUTHORIZED, "bad signature"));
    }
    if (now_unix() - time).abs() > CLOCK_SKEW {
        return Err(error(StatusCode::BAD_REQUEST, "the server clock is too far off"));
    }
    Ok(key)
}

async fn announce(State(hub): State<Arc<Hub>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, body: Bytes) -> Response {
    let from = client_ip(&hub, &headers, peer);
    if !hub.limiter.allow(from, "announce", 6, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many announces");
    }
    if body.len() > MAX_BODY {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "request too large");
    }
    let Ok(a) = serde_json::from_slice::<Announce>(&body) else { return error(StatusCode::BAD_REQUEST, "invalid announce") };
    let key = match signed_key(&headers, &body, &a.key, a.time) {
        Ok(key) => key,
        Err(response) => return response,
    };
    if a.port == 0 {
        return error(StatusCode::BAD_REQUEST, "missing port");
    }
    // The address: as given (a name or IP, resolved here) or the one the request came from.
    let ip = if a.address.trim().is_empty() {
        from
    } else {
        match tokio::net::lookup_host((a.address.trim(), a.port)).await.ok().and_then(|mut it| it.next()) {
            Some(addr) => addr.ip(),
            None => return error(StatusCode::BAD_REQUEST, "cannot resolve the address"),
        }
    };
    if is_private(ip) && !hub.config.allow_private {
        return error(StatusCode::UNPROCESSABLE_ENTITY, "private addresses are not listed on this hub; use the public address");
    }
    let query_port = if a.query_port == 0 { a.port.saturating_add(1) } else { a.query_port };
    let address = if a.address.trim().is_empty() { ip.to_string() } else { clip(a.address.trim(), 253) };
    let existing = hub.servers.lock().unwrap().get(&key.id).cloned();
    let needs_check = match &existing {
        Some(e) => e.listing.address != address || e.listing.port != a.port || e.query_port != query_port || e.verified_at.elapsed() > VERIFY_EVERY,
        None => true,
    };
    let mut verified_at = existing.as_ref().map(|e| e.verified_at).unwrap_or_else(Instant::now);
    if needs_check {
        if let Err(message) = status::verify_owner(SocketAddr::new(ip, query_port), &key, Duration::from_secs(3)).await {
            return error(StatusCode::UNPROCESSABLE_ENTITY, message);
        }
        verified_at = Instant::now();
    }
    let name = clip(if a.name.trim().is_empty() { "VoxelCraft Server" } else { a.name.trim() }, 64);
    let code = match hub.store.code_for(&key.id, &address, a.port, &name, now_unix()) {
        Ok(code) => code,
        Err(e) => return error(StatusCode::INTERNAL_SERVER_ERROR, format!("storage error: {e}")),
    };
    let listing = Listing {
        id: key.id.clone(),
        code: store::display(&code),
        address,
        port: a.port,
        name,
        motd: clip(&a.motd, 256),
        game: clip(&a.game, 64),
        game_name: clip(&a.game_name, 64),
        players: a.players.min(100_000),
        max_players: a.max_players.min(100_000),
        protocol: a.protocol,
        version: clip(&a.version, 32),
        tags: a.tags.iter().take(8).map(|t| clip(t, 24).to_lowercase()).filter(|t| !t.is_empty()).collect(),
    };
    let mut servers = hub.servers.lock().unwrap();
    if !servers.contains_key(&key.id) && servers.len() >= MAX_SERVERS {
        return error(StatusCode::SERVICE_UNAVAILABLE, "the hub is full");
    }
    servers.insert(key.id.clone(), Entry { listing: listing.clone(), query_port, last_seen: Instant::now(), verified_at });
    Json(json!({"id": key.id, "code": listing.code, "heartbeat": HEARTBEAT, "address": listing.address})).into_response()
}

async fn leave(State(hub): State<Arc<Hub>>, headers: HeaderMap, body: Bytes) -> Response {
    if body.len() > MAX_BODY {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "request too large");
    }
    let Ok(l) = serde_json::from_slice::<Leave>(&body) else { return error(StatusCode::BAD_REQUEST, "invalid request") };
    let key = match signed_key(&headers, &body, &l.key, l.time) {
        Ok(key) => key,
        Err(response) => return response,
    };
    hub.servers.lock().unwrap().remove(&key.id);
    Json(json!({"ok": true})).into_response()
}

async fn list(State(hub): State<Arc<Hub>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Query(q): Query<ListQuery>) -> Response {
    if !hub.limiter.allow(client_ip(&hub, &headers, peer), "list", 60, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many requests");
    }
    let game = q.game.unwrap_or_default().to_lowercase();
    let text = q.q.unwrap_or_default().to_lowercase();
    let mut servers: Vec<Listing> = hub
        .servers
        .lock()
        .unwrap()
        .values()
        .filter(|e| e.last_seen.elapsed() < EXPIRE)
        .map(|e| e.listing.clone())
        .filter(|l| game.is_empty() || l.game.to_lowercase() == game)
        .filter(|l| text.is_empty() || l.name.to_lowercase().contains(&text) || l.motd.to_lowercase().contains(&text) || l.tags.iter().any(|t| t.contains(&text)))
        .collect();
    servers.sort_by(|a, b| b.players.cmp(&a.players).then_with(|| a.name.cmp(&b.name)));
    let total = servers.len();
    let offset = q.offset.unwrap_or(0).min(total);
    let limit = q.limit.unwrap_or(100).clamp(1, 200);
    let page: Vec<Listing> = servers.into_iter().skip(offset).take(limit).collect();
    Json(json!({"servers": page, "total": total})).into_response()
}

async fn resolve_code(State(hub): State<Arc<Hub>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, Path(code): Path<String>) -> Response {
    if !hub.limiter.allow(client_ip(&hub, &headers, peer), "code", 30, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many requests");
    }
    match hub.store.resolve(&code) {
        Ok(Some(entry)) => {
            let online = hub.servers.lock().unwrap().get(&entry.server_id).map(|e| e.last_seen.elapsed() < EXPIRE).unwrap_or(false);
            Json(json!({"code": store::display(&entry.code), "address": entry.address, "port": entry.port, "name": entry.name, "online": online})).into_response()
        }
        Ok(None) => error(StatusCode::NOT_FOUND, "no server has that code"),
        Err(e) => error(StatusCode::INTERNAL_SERVER_ERROR, format!("storage error: {e}")),
    }
}

async fn news(State(hub): State<Arc<Hub>>) -> Response {
    let text = std::fs::read_to_string(hub.config.data.join("news.json")).unwrap_or_else(|_| "[]".into());
    let items: Value = serde_json::from_str(&text).unwrap_or_else(|_| json!([]));
    Json(items).into_response()
}

fn app(hub: Arc<Hub>) -> Router {
    Router::new()
        .route("/v1/servers/announce", post(announce))
        .route("/v1/servers/leave", post(leave))
        .route("/v1/servers", get(list))
        .route("/v1/codes/{code}", get(resolve_code))
        .route("/v1/news", get(news))
        .route("/healthz", get(|| async { "ok" }))
        .with_state(hub)
}

#[tokio::main]
async fn main() {
    let env = |k: &str, d: &str| std::env::var(k).unwrap_or_else(|_| d.to_string());
    let config = Config {
        allow_private: env("HUB_ALLOW_PRIVATE", "0") == "1",
        trust_proxy: env("HUB_TRUST_PROXY", "0") == "1",
        data: PathBuf::from(env("HUB_DATA", "./hub-data")),
    };
    let bind: SocketAddr = env("HUB_BIND", "0.0.0.0:24600").parse().expect("HUB_BIND must be host:port");
    let store = store::Store::open(&config.data).expect("cannot open the hub database");
    let hub = Arc::new(Hub { config: config.clone(), store, servers: Mutex::new(HashMap::new()), limiter: limits::Limiter::default() });
    // Forget silent servers and old rate-limit windows now and then.
    {
        let hub = hub.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(30)).await;
                hub.servers.lock().unwrap().retain(|_, e| e.last_seen.elapsed() < EXPIRE);
                hub.limiter.prune();
            }
        });
    }
    let listener = tokio::net::TcpListener::bind(bind).await.expect("cannot listen");
    println!("[hub] listening on http://{} (data {}, private addresses {})", listener.local_addr().unwrap(), config.data.display(),
        if config.allow_private { "listed" } else { "refused" });
    axum::serve(listener, app(hub).into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await
        .expect("server error");
}
