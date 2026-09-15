//! The game's UDP status query (engine/shared/server_status.gd), used to check that an announced
//! address really is the announcing server: the hub asks for a proof, a signature over the nonce with
//! the server's key, which only the owner of the key can make.

use std::net::SocketAddr;
use std::time::Duration;

use rand::RngCore;
use tokio::net::UdpSocket;

use crate::keys::PublicKey;

const REQUEST_SIZE: usize = 512;
const RESPONSE_MAX: usize = 1024;
const FLAG_PROOF: u8 = 1;

/// The message a server signs to prove it holds its key, for a given nonce.
pub fn proof_message(nonce: &[u8]) -> Vec<u8> {
    format!("voxelcraft-status-proof:{}", hex::encode(nonce)).into_bytes()
}

/// Queries `addr` and checks the reply carries a valid proof for `key`.
pub async fn verify_owner(addr: SocketAddr, key: &PublicKey, timeout: Duration) -> Result<(), String> {
    let bind: SocketAddr = if addr.is_ipv4() { "0.0.0.0:0".parse().unwrap() } else { "[::]:0".parse().unwrap() };
    let socket = UdpSocket::bind(bind).await.map_err(|e| format!("cannot open a socket: {e}"))?;
    let mut nonce = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut nonce);
    let mut request = Vec::with_capacity(REQUEST_SIZE);
    request.extend_from_slice(b"VXQ1");
    request.extend_from_slice(&nonce);
    request.push(FLAG_PROOF);
    request.resize(REQUEST_SIZE, 0);
    let mut buffer = [0u8; RESPONSE_MAX + 1];
    // A few tries: UDP may drop a packet.
    for _ in 0..3 {
        socket.send_to(&request, addr).await.map_err(|e| format!("cannot reach the server: {e}"))?;
        let wait = tokio::time::timeout(timeout / 3, async {
            loop {
                let (n, from) = socket.recv_from(&mut buffer).await?;
                if from.ip() == addr.ip() && n >= 12 && n <= RESPONSE_MAX && &buffer[..4] == b"VXR1" && buffer[4..12] == nonce {
                    return Ok::<usize, std::io::Error>(n);
                }
            }
        })
        .await;
        let Ok(Ok(n)) = wait else { continue };
        let info: serde_json::Value = serde_json::from_slice(&buffer[12..n]).map_err(|_| "the status reply is not valid".to_string())?;
        let proof = info.get("proof").and_then(|p| p.as_str()).unwrap_or("");
        if !key.verify(&proof_message(&nonce), proof) {
            return Err("the server at that address did not prove it holds the announcing key".into());
        }
        return Ok(());
    }
    Err(format!("no status reply from {addr} (is the query port open and forwarded?)"))
}
