//! Ed25519 signing for player identities.
//!
//! **Godot only gives us RSA**, and an RSA-2048 private key is 1,675 characters of PEM. That one
//! number decided a great deal: an identity that size cannot be typed, cannot fit a QR code anybody
//! can reliably scan, and therefore has to be *moved over a network* - which meant either both
//! devices on one LAN or a server holding it for a moment, and a server holding player keys is the
//! wrong shape for identities that are meant to be local.
//!
//! An Ed25519 private key is **32 bytes**. Fifty-two characters of base64, read off one screen and
//! typed into the other, or written on paper and put in a drawer. No network, no discovery, no
//! relay, and a backup that survives the house burning down. (the user, 2026-09-25)
//!
//! Signatures are 64 bytes and verification is far faster than RSA, which matters at the door of a
//! busy server. The cost was one dependency and changing every player id, which is free before 1.0
//! and expensive after it - so it was done now.

use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use rand_core::RngCore;
use godot::prelude::*;

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeIdentity {}

#[godot_api]
impl NativeIdentity {
    /// A new private key: 32 random bytes from the OS.
    #[func]
    fn generate() -> PackedByteArray {
        // Filled from the OS rather than `SigningKey::generate`, which wants a feature flag to pull
        // in its own RNG - the bytes are the key, so there is nothing else to get right here.
        let mut bytes = [0u8; 32];
        rand_core::OsRng.fill_bytes(&mut bytes);
        PackedByteArray::from(SigningKey::from_bytes(&bytes).to_bytes().as_slice())
    }

    /// The public key for a private one, or empty when the private key is not 32 bytes.
    #[func]
    fn public_key(private: PackedByteArray) -> PackedByteArray {
        match to_array(&private) {
            Some(bytes) => {
                let key = SigningKey::from_bytes(&bytes);
                PackedByteArray::from(key.verifying_key().to_bytes().as_slice())
            }
            None => PackedByteArray::new(),
        }
    }

    /// Signs a message. Empty when the private key is the wrong size.
    #[func]
    fn sign(private: PackedByteArray, message: PackedByteArray) -> PackedByteArray {
        match to_array(&private) {
            Some(bytes) => {
                let key = SigningKey::from_bytes(&bytes);
                PackedByteArray::from(key.sign(message.as_slice()).to_bytes().as_slice())
            }
            None => PackedByteArray::new(),
        }
    }

    /// Whether `signature` is this public key's signature over `message`.
    ///
    /// **Every bad input is false, never a panic.** This runs on whatever a stranger sent to the
    /// join handler, so a wrong-length key, a wrong-length signature and a forged one all have to
    /// end the same way.
    #[func]
    fn verify(public: PackedByteArray, message: PackedByteArray, signature: PackedByteArray) -> bool {
        let (Some(public), Some(sig)) = (to_array(&public), to_sig(&signature)) else {
            return false;
        };
        let Ok(key) = VerifyingKey::from_bytes(&public) else {
            return false;
        };
        key.verify(message.as_slice(), &Signature::from_bytes(&sig)).is_ok()
    }
}

fn to_array(bytes: &PackedByteArray) -> Option<[u8; 32]> {
    bytes.as_slice().try_into().ok()
}

fn to_sig(bytes: &PackedByteArray) -> Option<[u8; 64]> {
    bytes.as_slice().try_into().ok()
}
