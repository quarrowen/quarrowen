//! What the hub keeps on disk (SQLite in the data directory): each server's short invite code and last
//! known address, so a code keeps working across restarts and while a server is briefly offline.

use std::path::Path;
use std::sync::Mutex;

use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};

/// Crockford base32, as the game's invite codes.
pub const ALPHABET: &[u8; 32] = b"0123456789ABCDEFGHJKMNPQRSTVWXYZ";
pub const CODE_LENGTH: usize = 6;

pub struct Store {
    pub(crate) db: Mutex<Connection>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CodeEntry {
    pub code: String,
    pub server_id: String,
    pub address: String,
    pub port: u16,
    pub name: String,
    pub updated: i64,
}

impl Store {
    pub fn open(dir: &Path) -> rusqlite::Result<Self> {
        std::fs::create_dir_all(dir).ok();
        Self::with(Connection::open(dir.join("hub.sqlite"))?)
    }

    #[cfg(test)]
    pub fn in_memory() -> rusqlite::Result<Self> {
        Self::with(Connection::open_in_memory()?)
    }

    fn with(db: Connection) -> rusqlite::Result<Self> {
        db.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS codes (
                code TEXT PRIMARY KEY,
                server_id TEXT NOT NULL UNIQUE,
                address TEXT NOT NULL,
                port INTEGER NOT NULL,
                name TEXT NOT NULL,
                updated INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS players (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                friend_code TEXT NOT NULL UNIQUE,
                created INTEGER NOT NULL,
                last_seen INTEGER NOT NULL
             );
             CREATE TABLE IF NOT EXISTS friends (
                a TEXT NOT NULL,
                b TEXT NOT NULL,
                since INTEGER NOT NULL,
                PRIMARY KEY (a, b)
             );
             CREATE TABLE IF NOT EXISTS friend_requests (
                from_id TEXT NOT NULL,
                to_id TEXT NOT NULL,
                created INTEGER NOT NULL,
                PRIMARY KEY (from_id, to_id)
             );",
        )?;
        Ok(Self { db: Mutex::new(db) })
    }

    /// The server's code (made on first use, stable afterwards), updating its last known address.
    pub fn code_for(&self, server_id: &str, address: &str, port: u16, name: &str, now: i64) -> rusqlite::Result<String> {
        let db = self.db.lock().unwrap();
        let existing: Option<String> =
            db.query_row("SELECT code FROM codes WHERE server_id = ?1", params![server_id], |r| r.get(0)).optional()?;
        if let Some(code) = existing {
            db.execute("UPDATE codes SET address = ?1, port = ?2, name = ?3, updated = ?4 WHERE code = ?5", params![address, port, name, now, code])?;
            return Ok(code);
        }
        for attempt in 0u32.. {
            let code = derive_code(server_id, attempt);
            let taken: Option<String> = db.query_row("SELECT server_id FROM codes WHERE code = ?1", params![code], |r| r.get(0)).optional()?;
            if taken.is_none() {
                db.execute(
                    "INSERT INTO codes (code, server_id, address, port, name, updated) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![code, server_id, address, port, name, now],
                )?;
                return Ok(code);
            }
        }
        unreachable!()
    }

    pub fn resolve(&self, code: &str) -> rusqlite::Result<Option<CodeEntry>> {
        let db = self.db.lock().unwrap();
        db.query_row("SELECT code, server_id, address, port, name, updated FROM codes WHERE code = ?1", params![normalize(code)], |r| {
            Ok(CodeEntry { code: r.get(0)?, server_id: r.get(1)?, address: r.get(2)?, port: r.get(3)?, name: r.get(4)?, updated: r.get(5)? })
        })
        .optional()
    }
}

/// A code from a server id: base32 of a hash (with an attempt counter for the rare collision).
pub fn derive_code(server_id: &str, attempt: u32) -> String {
    let digest = Sha256::digest(format!("{server_id}:{attempt}").as_bytes());
    let mut value = u64::from_be_bytes(digest[..8].try_into().unwrap());
    let mut out = String::with_capacity(CODE_LENGTH);
    for _ in 0..CODE_LENGTH {
        out.push(ALPHABET[(value & 31) as usize] as char);
        value >>= 5;
    }
    out
}

/// "vc-abc-123", "ABC123", "abc o12" -> "ABC012" (Crockford look-alikes accepted).
pub fn normalize(code: &str) -> String {
    let upper = code.trim().to_uppercase();
    // "QW" now; "VC" was the prefix before the game was renamed, and codes written down then still work.
    let body = upper
        .strip_prefix("QW")
        .or_else(|| upper.strip_prefix("VC"))
        .unwrap_or(&upper);
    body.chars()
        .filter(|c| !matches!(c, '-' | ' '))
        .map(|c| match c {
            'O' => '0',
            'I' | 'L' => '1',
            other => other,
        })
        .collect()
}

pub fn display(code: &str) -> String {
    format!("QW-{}-{}", &code[..3], &code[3..])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_stable_and_unique() {
        let store = Store::in_memory().unwrap();
        let a = store.code_for("server-a", "1.2.3.4", 24565, "A", 1).unwrap();
        let again = store.code_for("server-a", "5.6.7.8", 24570, "A2", 2).unwrap();
        assert_eq!(a, again);
        assert_eq!(a.len(), CODE_LENGTH);
        let b = store.code_for("server-b", "1.2.3.4", 24565, "B", 1).unwrap();
        assert_ne!(a, b);
        let entry = store.resolve(&display(&a).to_lowercase()).unwrap().unwrap();
        assert_eq!((entry.address.as_str(), entry.port, entry.name.as_str()), ("5.6.7.8", 24570, "A2"));
    }

    #[test]
    fn normalizes_look_alikes() {
        assert_eq!(normalize("qw-abo-il1"), "AB0111");
        assert_eq!(normalize("vc-abo-il1"), "AB0111"); // codes written before the rename still work
        assert_eq!(normalize(" ABC 123 "), "ABC123");
    }
}
