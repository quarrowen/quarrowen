//! Players, friends and parties.
//!
//! Players sign in with their game identity key: the hub hands out a random nonce and the client signs
//! `voxelcraft-hub-login:<hub url>:<nonce hex>` (a message no game server challenge can produce, bound to
//! the hub it was meant for). The player id is the same as on game servers (SHA-256 of the public key PEM).
//! Friendships and requests are stored in SQLite; sessions, presence (online, which server) and parties
//! live in memory and are rebuilt as clients check in.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use rand::RngCore;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::store::{Store, ALPHABET};

pub const SESSION_TTL: Duration = Duration::from_secs(24 * 3600);
pub const NONCE_TTL: Duration = Duration::from_secs(120);
/// A player counts as online this long after their last check-in.
pub const ONLINE_FOR: Duration = Duration::from_secs(90);
/// Offline party members are dropped after this long.
pub const PARTY_OFFLINE_DROP: Duration = Duration::from_secs(600);
pub const MAX_FRIENDS: usize = 200;
pub const MAX_OUTGOING: usize = 50;
pub const MAX_PARTY: usize = 8;

#[derive(Clone, Serialize, Deserialize, Debug, PartialEq)]
pub struct ServerRef {
    pub name: String,
    pub address: String,
    pub port: u16,
    #[serde(default)]
    pub code: String,
}

#[derive(Clone)]
struct Presence {
    last: Instant,
    server: Option<ServerRef>,
    share_server: bool,
}

#[derive(Clone)]
struct Party {
    leader: String,
    members: Vec<String>,
    invited: Vec<String>,
}

#[derive(Default)]
pub struct Social {
    nonces: HashMap<String, Instant>,
    sessions: HashMap<String, (String, Instant)>,
    presence: HashMap<String, Presence>,
    parties: HashMap<String, Party>,
    party_of: HashMap<String, String>,
}

pub fn login_message(hub: &str, nonce: &str) -> Vec<u8> {
    format!("voxelcraft-hub-login:{hub}:{nonce}").into_bytes()
}

fn random_hex(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    rand::thread_rng().fill_bytes(&mut buf);
    hex::encode(buf)
}

/// "ABCD-EFGH" from a player id.
pub fn friend_code(player_id: &str, attempt: u32) -> String {
    let digest = Sha256::digest(format!("friend:{player_id}:{attempt}").as_bytes());
    let mut value = u64::from_be_bytes(digest[..8].try_into().unwrap());
    let mut out = String::new();
    for i in 0..8 {
        if i == 4 {
            out.push('-');
        }
        out.push(ALPHABET[(value & 31) as usize] as char);
        value >>= 5;
    }
    out
}

fn normalize_friend_code(text: &str) -> String {
    let clean: String = text
        .trim()
        .to_uppercase()
        .chars()
        .filter(|c| !matches!(c, '-' | ' '))
        .map(|c| match c {
            'O' => '0',
            'I' | 'L' => '1',
            other => other,
        })
        .collect();
    if clean.len() == 8 {
        format!("{}-{}", &clean[..4], &clean[4..])
    } else {
        clean
    }
}

pub type Error = (u16, String);

fn err(status: u16, message: &str) -> Error {
    (status, message.to_string())
}

impl Social {
    pub fn new_nonce(&mut self) -> String {
        let now = Instant::now();
        self.nonces.retain(|_, t| now.duration_since(*t) < NONCE_TTL);
        let nonce = random_hex(32);
        self.nonces.insert(nonce.clone(), now);
        nonce
    }

    /// Consumes a nonce (each signs in once).
    pub fn take_nonce(&mut self, nonce: &str) -> bool {
        matches!(self.nonces.remove(nonce), Some(t) if t.elapsed() < NONCE_TTL)
    }

    pub fn start_session(&mut self, player_id: &str) -> String {
        let token = random_hex(32);
        self.sessions.insert(token.clone(), (player_id.to_string(), Instant::now() + SESSION_TTL));
        self.touch(player_id);
        token
    }

    pub fn player_for(&self, token: &str) -> Option<String> {
        self.sessions.get(token).filter(|(_, until)| Instant::now() < *until).map(|(id, _)| id.clone())
    }

    fn touch(&mut self, player_id: &str) {
        let entry = self.presence.entry(player_id.to_string()).or_insert(Presence { last: Instant::now(), server: None, share_server: true });
        entry.last = Instant::now();
    }

    pub fn set_presence(&mut self, player_id: &str, server: Option<ServerRef>, share_server: bool) {
        self.presence.insert(player_id.to_string(), Presence { last: Instant::now(), server, share_server });
    }

    fn online(&self, player_id: &str) -> bool {
        self.presence.get(player_id).map(|p| p.last.elapsed() < ONLINE_FOR).unwrap_or(false)
    }

    /// Where a player is, as seen by someone allowed to see it (friends and party mates).
    fn server_of(&self, player_id: &str) -> Value {
        match self.presence.get(player_id) {
            Some(p) if p.last.elapsed() < ONLINE_FOR && p.share_server => p.server.as_ref().map(|s| json!(s)).unwrap_or(Value::Null),
            _ => Value::Null,
        }
    }

    /// Drops expired sessions and long-offline party members.
    pub fn prune(&mut self) {
        let now = Instant::now();
        self.sessions.retain(|_, (_, until)| now < *until);
        self.nonces.retain(|_, t| now.duration_since(*t) < NONCE_TTL);
        let gone: Vec<String> = self
            .party_of
            .keys()
            .filter(|id| self.presence.get(*id).map(|p| p.last.elapsed() > PARTY_OFFLINE_DROP).unwrap_or(true))
            .cloned()
            .collect();
        for id in gone {
            self.leave_party(&id);
        }
        self.presence.retain(|_, p| p.last.elapsed() < PARTY_OFFLINE_DROP * 6);
    }

    // --- Parties --------------------------------------------------------------------------------

    pub fn create_party(&mut self, player_id: &str) -> Result<(), Error> {
        if self.party_of.contains_key(player_id) {
            return Err(err(409, "you are already in a party"));
        }
        let id = random_hex(8);
        self.parties.insert(id.clone(), Party { leader: player_id.to_string(), members: vec![player_id.to_string()], invited: vec![] });
        self.party_of.insert(player_id.to_string(), id);
        Ok(())
    }

    pub fn invite_to_party(&mut self, store: &Store, player_id: &str, friend_id: &str) -> Result<(), Error> {
        if !store.are_friends(player_id, friend_id).map_err(db)? {
            return Err(err(403, "you can only invite friends"));
        }
        if !self.party_of.contains_key(player_id) {
            self.create_party(player_id)?;
        }
        let party_id = self.party_of[player_id].clone();
        let party = self.parties.get_mut(&party_id).unwrap();
        if party.members.contains(&friend_id.to_string()) {
            return Err(err(409, "they are already in your party"));
        }
        if party.members.len() + party.invited.len() >= MAX_PARTY {
            return Err(err(409, "the party is full"));
        }
        if !party.invited.contains(&friend_id.to_string()) {
            party.invited.push(friend_id.to_string());
        }
        Ok(())
    }

    pub fn respond_party(&mut self, player_id: &str, party_id: &str, accept: bool) -> Result<(), Error> {
        let Some(party) = self.parties.get_mut(party_id) else { return Err(err(404, "that party is gone")) };
        let Some(i) = party.invited.iter().position(|id| id == player_id) else { return Err(err(404, "no invitation")) };
        party.invited.remove(i);
        if !accept {
            return Ok(());
        }
        if party.members.len() >= MAX_PARTY {
            return Err(err(409, "the party is full"));
        }
        self.leave_party(player_id);
        let party = self.parties.get_mut(party_id).ok_or_else(|| err(404, "that party is gone"))?;
        party.members.push(player_id.to_string());
        self.party_of.insert(player_id.to_string(), party_id.to_string());
        Ok(())
    }

    pub fn leave_party(&mut self, player_id: &str) {
        let Some(party_id) = self.party_of.remove(player_id) else { return };
        let Some(party) = self.parties.get_mut(&party_id) else { return };
        party.members.retain(|id| id != player_id);
        if party.members.is_empty() {
            self.parties.remove(&party_id);
        } else if party.leader == player_id {
            party.leader = party.members[0].clone();
        }
    }

    pub fn kick(&mut self, leader_id: &str, member_id: &str) -> Result<(), Error> {
        let party_id = self.party_of.get(leader_id).cloned().ok_or_else(|| err(404, "you are not in a party"))?;
        let party = &self.parties[&party_id];
        if party.leader != leader_id {
            return Err(err(403, "only the party leader can do that"));
        }
        if member_id == leader_id {
            return Err(err(400, "use leave instead"));
        }
        let party = self.parties.get_mut(&party_id).unwrap();
        party.invited.retain(|id| id != member_id);
        if party.members.contains(&member_id.to_string()) {
            self.leave_party(member_id);
        }
        Ok(())
    }

    pub fn promote(&mut self, leader_id: &str, member_id: &str) -> Result<(), Error> {
        let party_id = self.party_of.get(leader_id).cloned().ok_or_else(|| err(404, "you are not in a party"))?;
        let party = self.parties.get_mut(&party_id).unwrap();
        if party.leader != leader_id {
            return Err(err(403, "only the party leader can do that"));
        }
        if !party.members.contains(&member_id.to_string()) {
            return Err(err(404, "they are not in your party"));
        }
        party.leader = member_id.to_string();
        Ok(())
    }

    // --- The state a client sees -----------------------------------------------------------------

    pub fn state(&self, store: &Store, player_id: &str) -> Result<Value, Error> {
        let me = store.player(player_id).map_err(db)?.ok_or_else(|| err(401, "unknown player"))?;
        let friends = store.friends(player_id).map_err(db)?;
        let party_id = self.party_of.get(player_id);
        let friend_list: Vec<Value> = friends
            .iter()
            .map(|(id, name)| {
                json!({"id": id, "name": name, "online": self.online(id), "server": self.server_of(id),
                    "in_my_party": party_id.is_some() && self.party_of.get(id) == party_id})
            })
            .collect();
        let party = party_id.and_then(|pid| self.parties.get(pid).map(|p| (pid, p))).map(|(pid, p)| {
            let describe = |id: &String| {
                let name = store.player(id).ok().flatten().map(|(n, _)| n).unwrap_or_default();
                json!({"id": id, "name": name, "online": self.online(id), "server": self.server_of(id)})
            };
            json!({"id": pid, "leader": p.leader, "members": p.members.iter().map(describe).collect::<Vec<_>>(),
                "invited": p.invited.iter().map(describe).collect::<Vec<_>>()})
        });
        let invites: Vec<Value> = self
            .parties
            .iter()
            .filter(|(_, p)| p.invited.contains(&player_id.to_string()))
            .map(|(pid, p)| {
                let leader_name = store.player(&p.leader).ok().flatten().map(|(n, _)| n).unwrap_or_default();
                json!({"party_id": pid, "leader": p.leader, "leader_name": leader_name, "members": p.members.len()})
            })
            .collect();
        let (incoming, outgoing) = store.requests(player_id).map_err(db)?;
        Ok(json!({
            "me": {"id": player_id, "name": me.0, "friend_code": me.1},
            "friends": friend_list,
            "incoming": incoming.iter().map(|(id, name)| json!({"id": id, "name": name})).collect::<Vec<_>>(),
            "outgoing": outgoing.iter().map(|(id, name)| json!({"id": id, "name": name})).collect::<Vec<_>>(),
            "party": party,
            "party_invites": invites,
        }))
    }
}

fn db(e: rusqlite::Error) -> Error {
    (500, format!("storage error: {e}"))
}

impl Store {
    /// Creates or renames a player; returns their friend code.
    pub fn upsert_player(&self, id: &str, name: &str, now: i64) -> rusqlite::Result<String> {
        let db = self.db.lock().unwrap();
        let existing: Option<String> = db.query_row("SELECT friend_code FROM players WHERE id = ?1", params![id], |r| r.get(0)).optional()?;
        if let Some(code) = existing {
            db.execute("UPDATE players SET name = ?1, last_seen = ?2 WHERE id = ?3", params![name, now, id])?;
            return Ok(code);
        }
        for attempt in 0u32.. {
            let code = friend_code(id, attempt);
            let taken: Option<String> = db.query_row("SELECT id FROM players WHERE friend_code = ?1", params![code], |r| r.get(0)).optional()?;
            if taken.is_none() {
                db.execute("INSERT INTO players (id, name, friend_code, created, last_seen) VALUES (?1, ?2, ?3, ?4, ?4)", params![id, name, code, now])?;
                return Ok(code);
            }
        }
        unreachable!()
    }

    /// (name, friend code)
    pub fn player(&self, id: &str) -> rusqlite::Result<Option<(String, String)>> {
        let db = self.db.lock().unwrap();
        db.query_row("SELECT name, friend_code FROM players WHERE id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?))).optional()
    }

    /// A player id from a friend code or a full id.
    pub fn find_player(&self, text: &str) -> rusqlite::Result<Option<String>> {
        let db = self.db.lock().unwrap();
        let code = normalize_friend_code(text);
        let by_code: Option<String> = db.query_row("SELECT id FROM players WHERE friend_code = ?1", params![code], |r| r.get(0)).optional()?;
        if by_code.is_some() {
            return Ok(by_code);
        }
        db.query_row("SELECT id FROM players WHERE id = ?1", params![text.trim().to_lowercase()], |r| r.get(0)).optional()
    }

    pub fn are_friends(&self, a: &str, b: &str) -> rusqlite::Result<bool> {
        let db = self.db.lock().unwrap();
        Ok(db.query_row("SELECT 1 FROM friends WHERE a = ?1 AND b = ?2", params![a, b], |_| Ok(())).optional()?.is_some())
    }

    /// [(id, name)] sorted by name.
    pub fn friends(&self, id: &str) -> rusqlite::Result<Vec<(String, String)>> {
        let db = self.db.lock().unwrap();
        let mut stmt = db.prepare("SELECT p.id, p.name FROM friends f JOIN players p ON p.id = f.b WHERE f.a = ?1 ORDER BY p.name COLLATE NOCASE")?;
        let rows = stmt.query_map(params![id], |r| Ok((r.get(0)?, r.get(1)?)))?;
        rows.collect()
    }

    /// (incoming, outgoing) requests as [(id, name)].
    pub fn requests(&self, id: &str) -> rusqlite::Result<(Vec<(String, String)>, Vec<(String, String)>)> {
        let db = self.db.lock().unwrap();
        let mut incoming = db.prepare("SELECT p.id, p.name FROM friend_requests r JOIN players p ON p.id = r.from_id WHERE r.to_id = ?1 ORDER BY r.created")?;
        let inc = incoming.query_map(params![id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<Vec<_>>>()?;
        let mut outgoing = db.prepare("SELECT p.id, p.name FROM friend_requests r JOIN players p ON p.id = r.to_id WHERE r.from_id = ?1 ORDER BY r.created")?;
        let out = outgoing.query_map(params![id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<Vec<_>>>()?;
        Ok((inc, out))
    }

    /// Sends a request; if they already asked us, becomes friends at once. Returns "requested" or "friends".
    pub fn request_friend(&self, from: &str, to: &str, now: i64) -> Result<&'static str, Error> {
        if from == to {
            return Err(err(400, "that is your own friend code"));
        }
        if self.are_friends(from, to).map_err(db)? {
            return Err(err(409, "you are already friends"));
        }
        if self.friends(from).map_err(db)?.len() >= MAX_FRIENDS {
            return Err(err(409, "your friends list is full"));
        }
        let db_conn = self.db.lock().unwrap();
        let they_asked: bool = db_conn
            .query_row("SELECT 1 FROM friend_requests WHERE from_id = ?1 AND to_id = ?2", params![to, from], |_| Ok(()))
            .optional()
            .map_err(db)?
            .is_some();
        drop(db_conn);
        if they_asked {
            self.make_friends(from, to, now).map_err(db)?;
            return Ok("friends");
        }
        let db_conn = self.db.lock().unwrap();
        let outgoing: i64 = db_conn.query_row("SELECT COUNT(*) FROM friend_requests WHERE from_id = ?1", params![from], |r| r.get(0)).map_err(db)?;
        if outgoing as usize >= MAX_OUTGOING {
            return Err(err(409, "you have too many open friend requests"));
        }
        db_conn.execute("INSERT OR IGNORE INTO friend_requests (from_id, to_id, created) VALUES (?1, ?2, ?3)", params![from, to, now]).map_err(db)?;
        Ok("requested")
    }

    pub fn respond_friend(&self, me: &str, from: &str, accept: bool, now: i64) -> Result<(), Error> {
        let removed = self.db.lock().unwrap().execute("DELETE FROM friend_requests WHERE from_id = ?1 AND to_id = ?2", params![from, me]).map_err(db)?;
        if removed == 0 {
            return Err(err(404, "no friend request from them"));
        }
        if accept {
            self.make_friends(me, from, now).map_err(db)?;
        }
        Ok(())
    }

    pub fn cancel_request(&self, me: &str, to: &str) -> rusqlite::Result<()> {
        self.db.lock().unwrap().execute("DELETE FROM friend_requests WHERE from_id = ?1 AND to_id = ?2", params![me, to])?;
        Ok(())
    }

    fn make_friends(&self, a: &str, b: &str, now: i64) -> rusqlite::Result<()> {
        let db = self.db.lock().unwrap();
        db.execute("DELETE FROM friend_requests WHERE (from_id = ?1 AND to_id = ?2) OR (from_id = ?2 AND to_id = ?1)", params![a, b])?;
        db.execute("INSERT OR IGNORE INTO friends (a, b, since) VALUES (?1, ?2, ?3), (?2, ?1, ?3)", params![a, b, now])?;
        Ok(())
    }

    pub fn remove_friend(&self, a: &str, b: &str) -> rusqlite::Result<()> {
        self.db.lock().unwrap().execute("DELETE FROM friends WHERE (a = ?1 AND b = ?2) OR (a = ?2 AND b = ?1)", params![a, b])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn players(store: &Store) {
        for (id, name) in [("a", "Alice"), ("b", "Bob"), ("c", "Cara")] {
            store.upsert_player(id, name, 1).unwrap();
        }
    }

    #[test]
    fn friend_requests_and_mutual_requests() {
        let store = Store::in_memory().unwrap();
        players(&store);
        let code_b = store.player("b").unwrap().unwrap().1;
        assert_eq!(store.find_player(&code_b.to_lowercase().replace('-', " ")).unwrap().as_deref(), Some("b"));
        assert_eq!(store.request_friend("a", "b", 2).unwrap(), "requested");
        assert_eq!(store.requests("b").unwrap().0, vec![("a".to_string(), "Alice".to_string())]);
        assert!(store.request_friend("a", "a", 2).is_err());
        store.respond_friend("b", "a", true, 3).unwrap();
        assert!(store.are_friends("a", "b").unwrap() && store.are_friends("b", "a").unwrap());
        assert!(store.request_friend("a", "b", 4).is_err());
        // Both asking each other makes them friends straight away.
        assert_eq!(store.request_friend("c", "a", 5).unwrap(), "requested");
        assert_eq!(store.request_friend("a", "c", 5).unwrap(), "friends");
        assert_eq!(store.friends("a").unwrap().len(), 2);
        store.remove_friend("c", "a").unwrap();
        assert_eq!(store.friends("a").unwrap().len(), 1);
    }

    #[test]
    fn parties_need_friends_and_hand_over_leadership() {
        let store = Store::in_memory().unwrap();
        players(&store);
        let mut social = Social::default();
        for id in ["a", "b", "c"] {
            social.set_presence(id, None, true);
        }
        assert!(social.invite_to_party(&store, "a", "b").is_err());
        store.request_friend("a", "b", 1).unwrap();
        store.respond_friend("b", "a", true, 1).unwrap();
        social.invite_to_party(&store, "a", "b").unwrap();
        assert_eq!(social.state(&store, "b").unwrap()["party_invites"].as_array().unwrap().len(), 1);
        let party_id = social.party_of["a"].clone();
        social.respond_party("b", &party_id, true).unwrap();
        assert_eq!(social.state(&store, "a").unwrap()["party"]["members"].as_array().unwrap().len(), 2);
        assert!(social.kick("b", "a").is_err());
        social.leave_party("a");
        assert_eq!(social.parties[&party_id].leader, "b");
        social.leave_party("b");
        assert!(social.parties.is_empty());
    }

    #[test]
    fn servers_are_shown_only_when_shared() {
        let store = Store::in_memory().unwrap();
        players(&store);
        store.request_friend("a", "b", 1).unwrap();
        store.respond_friend("b", "a", true, 1).unwrap();
        let mut social = Social::default();
        let server = ServerRef { name: "S".into(), address: "1.2.3.4".into(), port: 24565, code: String::new() };
        social.set_presence("b", Some(server.clone()), false);
        assert!(social.state(&store, "a").unwrap()["friends"][0]["server"].is_null());
        assert_eq!(social.state(&store, "a").unwrap()["friends"][0]["online"], true);
        social.set_presence("b", Some(server), true);
        assert_eq!(social.state(&store, "a").unwrap()["friends"][0]["server"]["port"], 24565);
    }
}
