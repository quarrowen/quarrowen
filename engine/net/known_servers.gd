extends RefCounted
## Trust-on-first-use pinning of server certificates, like SSH known_hosts. The first connection to an
## address stores the server's certificate; later connections verify it during the DTLS handshake.
## QW_KNOWN_SERVERS_DIR overrides the folder (tests use a throwaway one), and failing that it follows
## QW_USER_DIR like every other client path.
##
## **This used to be a bare `user://`**, which is the mistake CLAUDE.md says had already bitten three
## times: `project.godot` sets `use_custom_user_dir`, so `user://` from this checkout *is* the installed
## app's folder. `tools/run_tests.sh` happened to set QW_KNOWN_SERVERS_DIR, so the suite was clean - but
## `tools/look_shots.sh` sets only QW_USER_DIR, so every render pinned throwaway localhost servers into
## the player's real folder. Fourteen of them were sitting there. Routing through `UserPaths` means one
## override covers it, which is the whole point of that file. (2026-09-22)

const UserPaths = preload("res://engine/shared/user_paths.gd")


static func dir() -> String:
	var override := OS.get_environment("QW_KNOWN_SERVERS_DIR")
	return override if not override.is_empty() else UserPaths.path("known_servers")


static func path_for(endpoint: String) -> String:
	return dir().path_join(endpoint.replace(":", "_").validate_filename() + ".crt")


static func load_certificate(endpoint: String) -> X509Certificate:
	var path := path_for(endpoint)
	if not FileAccess.file_exists(path):
		return null
	var cert := X509Certificate.new()
	return cert if cert.load(path) == OK else null


## Pins `certificate_pem` for `endpoint` if nothing is pinned yet. Returns "" when the certificate
## matches (or was just pinned), otherwise a message explaining the mismatch.
## PEM text is compared directly (X509Certificate.save_to_string() adds a NUL character).
static func check_and_pin(endpoint: String, certificate_pem: String) -> String:
	var presented := X509Certificate.new()
	if certificate_pem.is_empty() or presented.load_from_string(certificate_pem) != OK:
		return "The server did not present a valid identity certificate."
	var path := path_for(endpoint)
	if not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(certificate_pem)
		return ""
	if FileAccess.get_file_as_string(path).strip_edges() != certificate_pem.strip_edges():
		return "The server at %s has a different identity than the last time you connected. If it was reinstalled, remove %s to trust it again; otherwise someone may be impersonating it." % [
			endpoint, ProjectSettings.globalize_path(path)]
	return ""


static func forget(endpoint: String) -> void:
	DirAccess.remove_absolute(path_for(endpoint))
