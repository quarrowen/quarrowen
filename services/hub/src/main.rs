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
//!   HUB_PUBLIC_URL=            the hub's public address (https://hub.example.org): sign-ins must name it,
//!                              so a login made for another hub cannot be replayed here
//!
//! API (JSON):
//!   POST /v1/servers/announce  body {key, time, port, query_port, address?, name, motd, game, game_name,
//!                              players, max_players, protocol, version, tags}, header X-Voxel-Signature
//!                              (base64 signature of the body) -> {id, code, heartbeat}
//!   POST /v1/servers/leave     body {key, time}, signed -> {ok}
//!   GET  /v1/servers?game=&q=&limit=&offset=   -> {servers: [...], total}
//!   GET  /v1/codes/{code}      -> {code, address, port, name, online}
//!   GET  /v1/news              -> [{title, body, url?, date?}] from HUB_DATA/news.json
//!   Players (see social.rs); every call but the first two needs "Authorization: Bearer <token>":
//!   POST /v1/auth/challenge    -> {nonce}
//!   POST /v1/auth/login        {key, nonce, hub, name, signature} -> {token, id, name, friend_code}
//!   GET  /v1/social            -> {me, friends, incoming, outgoing, party, party_invites}
//!   POST /v1/presence          {server: {name, address, port, code} | null, share_server} -> the social state
//!   POST /v1/friends/request   {code (friend code or player id)} -> {result: requested | friends}
//!   POST /v1/friends/respond   {id, accept}      POST /v1/friends/cancel {id}     POST /v1/friends/remove {id}
//!   POST /v1/party/invite      {id} (creates a party when needed)     POST /v1/party/respond {party_id, accept}
//!   POST /v1/party/leave       POST /v1/party/kick {id}     POST /v1/party/promote {id}
//!   (every POST under /v1/friends and /v1/party answers with the social state)
//!   GET  /healthz

mod keys;
mod limits;
mod social;
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
    public_url: String,
}

struct Hub {
    config: Config,
    store: store::Store,
    servers: Mutex<HashMap<String, Entry>>,
    limiter: limits::Limiter,
    social: Mutex<social::Social>,
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

// --- Players, friends and parties ---------------------------------------------------------------

#[derive(Deserialize)]
struct Login {
    key: String,
    nonce: String,
    #[serde(default)]
    hub: String,
    #[serde(default)]
    name: String,
    signature: String,
}

async fn challenge(State(hub): State<Arc<Hub>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap) -> Response {
    if !hub.limiter.allow(client_ip(&hub, &headers, peer), "login", 20, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many sign-ins");
    }
    Json(json!({"nonce": hub.social.lock().unwrap().new_nonce(), "hub": hub.config.public_url})).into_response()
}

async fn login(State(hub): State<Arc<Hub>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, headers: HeaderMap, body: Bytes) -> Response {
    if !hub.limiter.allow(client_ip(&hub, &headers, peer), "login", 20, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many sign-ins");
    }
    if body.len() > MAX_BODY {
        return error(StatusCode::PAYLOAD_TOO_LARGE, "request too large");
    }
    let Ok(l) = serde_json::from_slice::<Login>(&body) else { return error(StatusCode::BAD_REQUEST, "invalid sign-in") };
    if !hub.config.public_url.is_empty() && l.hub.trim_end_matches('/') != hub.config.public_url.trim_end_matches('/') {
        return error(StatusCode::UNAUTHORIZED, "this sign-in was made for another hub");
    }
    let key = match keys::PublicKey::from_pem(&l.key) {
        Ok(key) => key,
        Err(e) => return error(StatusCode::BAD_REQUEST, e),
    };
    if !hub.social.lock().unwrap().take_nonce(&l.nonce) {
        return error(StatusCode::UNAUTHORIZED, "the sign-in challenge expired; try again");
    }
    if !key.verify(&social::login_message(&l.hub, &l.nonce), &l.signature) {
        return error(StatusCode::UNAUTHORIZED, "bad signature");
    }
    let name = clip(l.name.trim(), 16);
    let name = if name.is_empty() { "Player".to_string() } else { name };
    let code = match hub.store.upsert_player(&key.id, &name, now_unix()) {
        Ok(code) => code,
        Err(e) => return error(StatusCode::INTERNAL_SERVER_ERROR, format!("storage error: {e}")),
    };
    let token = hub.social.lock().unwrap().start_session(&key.id);
    Json(json!({"token": token, "id": key.id, "name": name, "friend_code": code})).into_response()
}

fn session(hub: &Hub, headers: &HeaderMap) -> Result<String, Response> {
    let token = headers.get("authorization").and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")).unwrap_or("");
    hub.social.lock().unwrap().player_for(token.trim()).ok_or_else(|| error(StatusCode::UNAUTHORIZED, "not signed in"))
}

fn social_error(e: social::Error) -> Response {
    error(StatusCode::from_u16(e.0).unwrap_or(StatusCode::BAD_REQUEST), e.1)
}

fn state_response(hub: &Hub, player: &str) -> Response {
    match hub.social.lock().unwrap().state(&hub.store, player) {
        Ok(state) => Json(state).into_response(),
        Err(e) => social_error(e),
    }
}

async fn social_state(State(hub): State<Arc<Hub>>, headers: HeaderMap) -> Response {
    match session(&hub, &headers) {
        Ok(player) => state_response(&hub, &player),
        Err(response) => response,
    }
}

#[derive(Deserialize)]
struct PresenceBody {
    #[serde(default)]
    server: Option<social::ServerRef>,
    #[serde(default = "yes")]
    share_server: bool,
}

fn yes() -> bool {
    true
}

async fn presence(State(hub): State<Arc<Hub>>, headers: HeaderMap, body: Bytes) -> Response {
    let player = match session(&hub, &headers) {
        Ok(player) => player,
        Err(response) => return response,
    };
    if !hub.limiter.allow_key(&player, "presence", 30, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many updates");
    }
    let Ok(p) = serde_json::from_slice::<PresenceBody>(&body) else { return error(StatusCode::BAD_REQUEST, "invalid presence") };
    let server = p.server.map(|s| social::ServerRef { name: clip(&s.name, 64), address: clip(&s.address, 253), port: s.port, code: clip(&s.code, 16) });
    hub.social.lock().unwrap().set_presence(&player, server, p.share_server);
    state_response(&hub, &player)
}

#[derive(Deserialize)]
struct Target {
    #[serde(default)]
    id: String,
    #[serde(default)]
    code: String,
    #[serde(default)]
    party_id: String,
    #[serde(default)]
    accept: bool,
}

/// Every friends and party action: `action` from the path, body {id | code | party_id, accept}.
async fn social_action(State(hub): State<Arc<Hub>>, Path((group, action)): Path<(String, String)>, headers: HeaderMap, body: Bytes) -> Response {
    let player = match session(&hub, &headers) {
        Ok(player) => player,
        Err(response) => return response,
    };
    if !hub.limiter.allow_key(&player, "social", 60, Duration::from_secs(60)) {
        return error(StatusCode::TOO_MANY_REQUESTS, "too many requests");
    }
    let t: Target = if body.is_empty() { serde_json::from_str("{}").unwrap() } else {
        match serde_json::from_slice(&body) {
            Ok(t) => t,
            Err(_) => return error(StatusCode::BAD_REQUEST, "invalid request"),
        }
    };
    let now = now_unix();
    let result: Result<Value, social::Error> = match (group.as_str(), action.as_str()) {
        ("friends", "request") => match hub.store.find_player(&t.code) {
            Ok(Some(to)) => hub.store.request_friend(&player, &to, now).map(|r| json!({"result": r})),
            Ok(None) => Err((404, "no player has that friend code".into())),
            Err(e) => Err((500, e.to_string())),
        },
        ("friends", "respond") => hub.store.respond_friend(&player, &t.id, t.accept, now).map(|_| json!({})),
        ("friends", "cancel") => hub.store.cancel_request(&player, &t.id).map(|_| json!({})).map_err(|e| (500, e.to_string())),
        ("friends", "remove") => hub.store.remove_friend(&player, &t.id).map(|_| json!({})).map_err(|e| (500, e.to_string())),
        ("party", "invite") => hub.social.lock().unwrap().invite_to_party(&hub.store, &player, &t.id).map(|_| json!({})),
        ("party", "respond") => hub.social.lock().unwrap().respond_party(&player, &t.party_id, t.accept).map(|_| json!({})),
        ("party", "leave") => {
            hub.social.lock().unwrap().leave_party(&player);
            Ok(json!({}))
        }
        ("party", "kick") => hub.social.lock().unwrap().kick(&player, &t.id).map(|_| json!({})),
        ("party", "promote") => hub.social.lock().unwrap().promote(&player, &t.id).map(|_| json!({})),
        _ => Err((404, "unknown action".into())),
    };
    match result {
        Ok(extra) => {
            let mut state = match hub.social.lock().unwrap().state(&hub.store, &player) {
                Ok(state) => state,
                Err(e) => return social_error(e),
            };
            if let (Some(obj), Some(extra)) = (state.as_object_mut(), extra.as_object()) {
                for (k, v) in extra {
                    obj.insert(k.clone(), v.clone());
                }
            }
            Json(state).into_response()
        }
        Err(e) => social_error(e),
    }
}

fn app(hub: Arc<Hub>) -> Router {
    Router::new()
        .route("/v1/auth/challenge", post(challenge))
        .route("/v1/auth/login", post(login))
        .route("/v1/social", get(social_state))
        .route("/v1/presence", post(presence))
        .route("/v1/{group}/{action}", post(social_action))
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
        public_url: env("HUB_PUBLIC_URL", ""),
    };
    let bind: SocketAddr = env("HUB_BIND", "0.0.0.0:24600").parse().expect("HUB_BIND must be host:port");
    let store = store::Store::open(&config.data).expect("cannot open the hub database");
    let hub = Arc::new(Hub { config: config.clone(), store, servers: Mutex::new(HashMap::new()), limiter: limits::Limiter::default(), social: Mutex::new(social::Social::default()) });
    // Forget silent servers and old rate-limit windows now and then.
    {
        let hub = hub.clone();
        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(30)).await;
                hub.servers.lock().unwrap().retain(|_, e| e.last_seen.elapsed() < EXPIRE);
                hub.limiter.prune();
                hub.social.lock().unwrap().prune();
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
