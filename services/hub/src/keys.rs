//! Player identity keys and signatures, matching the game's: **Ed25519**, as
//! `engine/shared/identity.gd` and `native/src/identity.rs`.
//!
//! This was RSA until 2026-09-25, because Godot's `Crypto` offers nothing else. The game moved to
//! Ed25519 so that a private key is 32 bytes rather than 1,675 characters - small enough to type or
//! write down, which is what let identity transfer stop needing a network at all. The hub verifies
//! the same signatures players make, so it had to move with it.
//!
//! Keys arrive as base64 of 32 bytes; ids hash those bytes, like `Identity.player_id`.

use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};

/// A public key as text: base64 of 32 bytes. A bound rather than an equality, so an oversized string
/// is refused before anything decodes it.
pub const MAX_KEY_LENGTH: usize = 128;

pub struct PublicKey {
    key: VerifyingKey,
    pub id: String,
}

impl PublicKey {
    pub fn from_text(text: &str) -> Result<Self, String> {
        let text = text.trim();
        if text.len() > MAX_KEY_LENGTH {
            return Err("key too long".into());
        }
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(text)
            .map_err(|_| "not a key".to_string())?;
        let bytes: [u8; 32] = bytes.as_slice().try_into().map_err(|_| "not a key".to_string())?;
        let key = VerifyingKey::from_bytes(&bytes).map_err(|_| "not a key".to_string())?;
        Ok(Self { key, id: id_of(&bytes) })
    }

    /// Checks a base64 signature over `message`. Every bad input is false rather than an error: this
    /// runs on whatever a stranger posted.
    pub fn verify(&self, message: &[u8], signature_b64: &str) -> bool {
        let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(signature_b64.trim()) else { return false };
        let Ok(bytes) = <[u8; 64]>::try_from(bytes.as_slice()) else { return false };
        self.key.verify(message, &Signature::from_bytes(&bytes)).is_ok()
    }
}

/// The 32 hex character id of a key: SHA-256 of its 32 bytes.
pub fn id_of(public: &[u8]) -> String {
    hex::encode(Sha256::digest(public))[..32].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use ed25519_dalek::{Signer, SigningKey};
    use rand::RngCore;

    fn a_key() -> SigningKey {
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        SigningKey::from_bytes(&bytes)
    }

    fn text_of(private: &SigningKey) -> String {
        base64::engine::general_purpose::STANDARD.encode(private.verifying_key().to_bytes())
    }

    #[test]
    fn verifies_signatures_and_rejects_tampering() {
        let private = a_key();
        let key = PublicKey::from_text(&text_of(&private)).unwrap();
        let sig = base64::engine::general_purpose::STANDARD.encode(private.sign(b"hello").to_bytes());
        assert!(key.verify(b"hello", &sig));
        assert!(!key.verify(b"hellO", &sig));
        assert!(!key.verify(b"hello", "not base64!"));
        assert!(!key.verify(b"hello", ""));
        assert_eq!(key.id.len(), 32);
        // Another key's signature over the same message, which is the forgery that matters.
        let other = base64::engine::general_purpose::STANDARD.encode(a_key().sign(b"hello").to_bytes());
        assert!(!key.verify(b"hello", &other));
    }

    #[test]
    fn rejects_anything_that_is_not_a_key() {
        assert!(PublicKey::from_text("junk").is_err());
        assert!(PublicKey::from_text("").is_err());
        // Right encoding, wrong length: the old RSA keys arrived as PEM and must not be mistaken for
        // an Ed25519 one, and neither must a truncated key.
        assert!(PublicKey::from_text(&base64::engine::general_purpose::STANDARD.encode([7u8; 31])).is_err());
        assert!(PublicKey::from_text("-----BEGIN PUBLIC KEY-----").is_err());
        assert!(PublicKey::from_text(&"A".repeat(MAX_KEY_LENGTH + 1)).is_err());
    }

    /// A key's id must be the one the game computes, or a player signing in to the hub is a different
    /// person from the one who joined a server.
    #[test]
    fn the_id_is_sha256_of_the_key_bytes() {
        assert_eq!(id_of(b""), hex::encode(Sha256::digest(b""))[..32]);
        assert_eq!(id_of(&[0u8; 32]).len(), 32);
    }
}
