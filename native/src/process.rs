//! Process-level helpers Godot does not provide, currently graceful shutdown on SIGTERM/SIGINT so a
//! containerised server can save its world when `docker stop` is issued.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};

use godot::prelude::*;

static SHUTDOWN: OnceLock<Arc<AtomicBool>> = OnceLock::new();

#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct NativeProcess {}

#[godot_api]
impl NativeProcess {
    /// Installs SIGTERM/SIGINT handlers that set a flag instead of killing the process. A second
    /// SIGINT exits immediately, so a stuck server can still be stopped from a terminal.
    /// Returns false where signals are not supported.
    #[func]
    fn install_shutdown_handlers() -> bool {
        let flag = SHUTDOWN.get_or_init(|| Arc::new(AtomicBool::new(false))).clone();
        install(flag)
    }

    #[func]
    fn is_shutdown_requested() -> bool {
        SHUTDOWN.get().is_some_and(|flag| flag.load(Ordering::Relaxed))
    }
}

#[cfg(unix)]
fn install(flag: Arc<AtomicBool>) -> bool {
    use signal_hook::consts::{SIGINT, SIGTERM};
    use signal_hook::flag;
    // Order matters: the conditional shutdown must be registered before the flag setter.
    flag::register_conditional_shutdown(SIGINT, 130, flag.clone()).is_ok()
        && flag::register(SIGINT, flag.clone()).is_ok()
        && flag::register(SIGTERM, flag).is_ok()
}

#[cfg(not(unix))]
fn install(_flag: Arc<AtomicBool>) -> bool {
    false
}
