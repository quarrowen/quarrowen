extends RefCounted
## Whether this process may reach out to the internet, and how a test run is kept off it.
##
## The suite launches the real client, and the real client's menu fetches: `hub_client.gd` asks for
## news and a server list, `downloads.gd` checks `https://quarrowen.com/update.json`. So a network
## hiccup on whoever's machine is running the tests could fail a test about joining a *local* server -
## which is exactly what happened on 2026-09-22, as two `TLS handshake error: -27648` lines above a
## failed `host client joined its own server`. It passed alone and passed on a re-run, and a flake that
## points at the wrong thing costs more than a flake that fails honestly.
##
## This is the same rule as `user_paths.gd` and for the same reason: **the suite must not touch the real
## world.** Fixing it one call site at a time is what let the `user://` problem come back three times,
## so this is the one place to ask, and `tools/run_tests.sh` sets it.
##
## **Loopback is still allowed.** The point is not "no sockets" - the hub tests run a real hub on
## localhost and should keep working. The point is that nothing reaches a machine somebody else owns.

const ENV := "QW_OFFLINE"

## Hosts that are this machine. A test that wants a server can have one; it just cannot have ours.
const LOCAL_HOSTS := ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]


## Whether this process may fetch `url`. True for everything unless `QW_OFFLINE` is set, and then only
## for loopback.
static func allowed(url: String) -> bool:
	if OS.get_environment(ENV).is_empty():
		return true
	return host_allowed(_host_of(url))


## The same question when the host is already in hand, as `hub_announcer.leave()` has it.
static func host_allowed(host: String) -> bool:
	if OS.get_environment(ENV).is_empty():
		return true
	return host.to_lower() in LOCAL_HOSTS


## Whether this process has been kept off the network. Tests assert on it, because the whole point is
## that it is true while they run and false while somebody is playing.
static func restricted() -> bool:
	return not OS.get_environment(ENV).is_empty()


static func _host_of(url: String) -> String:
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	return rest.get_slice("/", 0).get_slice(":", 0)
