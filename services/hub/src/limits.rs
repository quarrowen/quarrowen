//! A small fixed-window rate limiter per client address and action.

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Default)]
pub struct Limiter {
    windows: Mutex<HashMap<(IpAddr, &'static str), (Instant, u32)>>,
    keyed: Mutex<HashMap<(String, &'static str), (Instant, u32)>>,
}

impl Limiter {
    /// True when `ip` may do `action` again: at most `max` times per `window`.
    pub fn allow(&self, ip: IpAddr, action: &'static str, max: u32, window: Duration) -> bool {
        let mut windows = self.windows.lock().unwrap();
        let entry = windows.entry((ip, action)).or_insert((Instant::now(), 0));
        if entry.0.elapsed() >= window {
            *entry = (Instant::now(), 0);
        }
        entry.1 += 1;
        entry.1 <= max
    }

    /// The same, per signed-in player.
    pub fn allow_key(&self, key: &str, action: &'static str, max: u32, window: Duration) -> bool {
        let mut windows = self.keyed.lock().unwrap();
        let entry = windows.entry((key.to_string(), action)).or_insert((Instant::now(), 0));
        if entry.0.elapsed() >= window {
            *entry = (Instant::now(), 0);
        }
        entry.1 += 1;
        entry.1 <= max
    }

    pub fn prune(&self) {
        self.keyed.lock().unwrap().retain(|_, (start, _)| start.elapsed() < Duration::from_secs(300));
        self.windows.lock().unwrap().retain(|_, (start, _)| start.elapsed() < Duration::from_secs(300));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limits_per_address_and_action() {
        let limiter = Limiter::default();
        let a: IpAddr = "1.2.3.4".parse().unwrap();
        let b: IpAddr = "5.6.7.8".parse().unwrap();
        assert!((0..3).all(|_| limiter.allow(a, "x", 3, Duration::from_secs(60))));
        assert!(!limiter.allow(a, "x", 3, Duration::from_secs(60)));
        assert!(limiter.allow(a, "y", 3, Duration::from_secs(60)));
        assert!(limiter.allow(b, "x", 3, Duration::from_secs(60)));
    }
}
