//! Identity keys and signatures, matching the game's (Godot `Crypto.sign` with SHA-256: RSA PKCS#1 v1.5).
//! Keys arrive as PEM "PUBLIC KEY" text exactly as Godot writes them; ids hash that text, like
//! `Identity.player_id` in engine/shared/identity.gd.

use base64::Engine;
use rsa::pkcs1v15::{Signature, VerifyingKey};
use rsa::pkcs8::DecodePublicKey;
use rsa::signature::Verifier;
use rsa::traits::PublicKeyParts;
use rsa::RsaPublicKey;
use sha2::{Digest, Sha256};

pub const MIN_BITS: usize = 2048;
pub const MAX_PEM_LENGTH: usize = 4096;

pub struct PublicKey {
    key: VerifyingKey<Sha256>,
    pub id: String,
}

impl PublicKey {
    pub fn from_pem(pem: &str) -> Result<Self, String> {
        if pem.len() > MAX_PEM_LENGTH {
            return Err("key too long".into());
        }
        let rsa = RsaPublicKey::from_public_key_pem(pem.trim()).map_err(|_| "not an RSA public key".to_string())?;
        if rsa.size() * 8 < MIN_BITS {
            return Err(format!("keys must have at least {MIN_BITS} bits"));
        }
        Ok(Self { key: VerifyingKey::<Sha256>::new(rsa), id: id_of(pem) })
    }

    /// Checks a base64 signature over `message`.
    pub fn verify(&self, message: &[u8], signature_b64: &str) -> bool {
        let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(signature_b64.trim()) else { return false };
        let Ok(signature) = Signature::try_from(bytes.as_slice()) else { return false };
        self.key.verify(message, &signature).is_ok()
    }
}

/// The 32 hex character id of a key: SHA-256 of its PEM text.
pub fn id_of(pem: &str) -> String {
    hex::encode(Sha256::digest(pem.as_bytes()))[..32].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rsa::pkcs1v15::SigningKey;
    use rsa::pkcs8::{EncodePublicKey, LineEnding};
    use rsa::signature::{SignatureEncoding, Signer};
    use rsa::RsaPrivateKey;

    #[test]
    fn verifies_signatures_and_rejects_tampering() {
        let private = RsaPrivateKey::new(&mut rand::thread_rng(), 2048).unwrap();
        let pem = private.to_public_key().to_public_key_pem(LineEnding::LF).unwrap();
        let key = PublicKey::from_pem(&pem).unwrap();
        let signer = SigningKey::<Sha256>::new(private);
        let sig = base64::engine::general_purpose::STANDARD.encode(signer.sign(b"hello").to_bytes());
        assert!(key.verify(b"hello", &sig));
        assert!(!key.verify(b"hellO", &sig));
        assert!(!key.verify(b"hello", "not base64!"));
        assert_eq!(key.id.len(), 32);
    }

    #[test]
    fn rejects_small_keys() {
        let private = RsaPrivateKey::new(&mut rand::thread_rng(), 1024).unwrap();
        let pem = private.to_public_key().to_public_key_pem(LineEnding::LF).unwrap();
        assert!(PublicKey::from_pem(&pem).is_err());
        assert!(PublicKey::from_pem("junk").is_err());
    }
}
