extends RefCounted
## Keeps the game up to date with the project's own releases.
##
## Where updates come from is built into the client (MANIFEST_URL below) and never taken from a server:
## a server can say which version it wants, but it can never point the client at a download. The steps are
##
##   1. fetch the manifest (a small JSON file published with each release) and its signature
##   2. check the signature against the release keys built into this build - a manifest that is not signed
##      by the project is refused, so taking over the website or its DNS is not enough to push a build
##   3. compare its version with this build's (engine/shared/protocol.gd GAME_VERSION)
##   4. download the zip for this platform and check it against the checksum in the signed manifest
##   5. unpack it beside the installed app, then hand over to a small script that swaps the two once this
##      process has quit, and starts the new one
##
## Everything except the two network calls is plain data in and out, so the logic is tested offline
## (tests/gameplay_test.gd, "updates").
##
## Public halves of the keys that may sign a release ("update.json.sig" next to the manifest). More than
## one so a key can be rotated: ship a build that trusts both, then start signing with the new one.
## The private halves live outside the repository (see tools/sign_manifest.gd and docs/distribution.md).
const RELEASE_KEYS := [
	"-----BEGIN PUBLIC KEY-----\nMIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEArxszSL0cIfm6bPDINbwN\nS/sWLu4jcye0HCcRZ866hBYQq57xOjWRZYs3XqvCS1SzdFMQY2hys/E2n3TS1REg\nOMNCkLjvrEYM8qyAiL411sgGg2DBiNT42ariYhwfv9Uu9aKhPttcFSmRSZBf3jNT\nzNzxpvzG8xRT4+rh2B0XmKoR7cCzuR2aVIU8ze9egTrdaeJoIcBTQnnTcaGADY+P\n9FWyuoZcTNy5wzfyS55v05/pzk7xzquVUv+vRbKgRs6s/WfajN9QhS1++PcG+VWB\ni1Iq3cvX30DCo11eujNWZvJNI/3iKDjP5WVF1IVa+apC70oQFecdcJdx7+sluPef\ni8lZddJI9S2YZrJtWgrr3tWLuSGzjpB3/r+vyvr+DQwCHIjgdsX2VQxNPAkHLIA5\ndEtcLddblyMF0eymZydQIHtNEecrC5vvgVN9uTce3FD0qlvXNV4VRsMutI26oFjJ\nW73zONMcw4zmaUaAYCCfXVhLn3M9ygxcI8ljdw8QfIbpAgMBAAE=\n-----END PUBLIC KEY-----\n"
]

## The manifest (an asset of every release, and what MANIFEST_URL points at):
##   {"version": "0.38.0",
##    "notes": "What changed, one line.",
##    "builds": {"macos": {"url": "https://github.com/.../Quarrowen-macos-0.38.0.zip",
##                         "sha256": "…", "size": 123456}}}

const Protocol = preload("res://engine/shared/protocol.gd")
const Semver = preload("res://engine/shared/semver.gd")

## Where updates are fetched from. The release host has to be publicly readable (a private repository's
## release assets need a token, which a game cannot carry), so this points at the project's public
## distribution: override it in project.godot ("quarrowen/update_manifest_url") for a fork or a test.
const DEFAULT_MANIFEST_URL := "https://quarrowen.com/update.json"
const DOWNLOAD_DIR := "user://updates"
## Downloads must come from the project's own release host, whatever the manifest says.
const ALLOWED_HOSTS := ["quarrowen.com", "www.quarrowen.com", "quarrowen.github.io",
	"github.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"]
const MAX_DOWNLOAD_BYTES := 512 * 1024 * 1024


## Where to ask about new versions (the project setting wins, so a fork can point somewhere else).
static func manifest_url() -> String:
	var configured := str(ProjectSettings.get_setting("quarrowen/update_manifest_url", ""))
	return configured if configured.begins_with("https://") else DEFAULT_MANIFEST_URL


## This platform's key in the manifest, or "" where updating is not supported (a server, or a build
## installed by something else).
static func platform() -> String:
	if OS.has_feature("macos"):
		return "macos"
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("linux"):
		return "linux"
	# iOS and iPadOS deliberately return "": a build there comes from TestFlight or the App Store and
	# cannot replace itself, which is a fact the refusal message needs rather than a gap to fall
	# through. (2026-09-22)
	return ""


## Whether this manifest was signed by one of the project's release keys. A build with no keys refuses
## everything rather than accepting everything: this used to return true so that builds made before
## signing existed could still update themselves, which meant that a build shipped with its keys somehow
## empty would take an update from anyone who could answer for the address.
static func signature_ok(manifest_text: String, signature: String, keys := RELEASE_KEYS) -> bool:
	var trusted := keys.filter(func(pem): return not str(pem).strip_edges().is_empty())
	if trusted.is_empty():
		return false
	var raw := Marshalls.base64_to_raw(signature)
	if raw.is_empty():
		return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(manifest_text.to_utf8_buffer())
	var hash := digest.finish()
	var crypto := Crypto.new()
	for pem: String in trusted:
		var key := CryptoKey.new()
		if key.load_from_string(pem, true) == OK and crypto.verify(HashingContext.HASH_SHA256, hash, raw, key):
			return true
	return false


## Reads a manifest. Returns {available, version, notes, url, sha256, size, reason}: `available` is true
## only when the manifest is signed by the project, sound, names this platform, and is newer than `current`.
static func check(manifest_text: String, current := Protocol.GAME_VERSION, for_platform := "", signature := "",
		keys := RELEASE_KEYS) -> Dictionary:
	var out := {"available": false, "version": "", "notes": "", "url": "", "sha256": "", "size": 0, "reason": ""}
	if not signature_ok(manifest_text, signature, keys):
		out.reason = "the update information is not signed by the project, so it was ignored"
		return out
	var parsed = JSON.new()
	if parsed.parse(manifest_text) != OK or not (parsed.data is Dictionary):
		out.reason = "the update information could not be read"
		return out
	var manifest: Dictionary = parsed.data
	var version := str(manifest.get("version", ""))
	if not Semver.is_valid(version):
		out.reason = "the update information has no version"
		return out
	out.version = version
	out.notes = str(manifest.get("notes", "")).left(200)
	var key := for_platform if not for_platform.is_empty() else platform()
	var builds = manifest.get("builds")
	var build = builds.get(key) if builds is Dictionary else null
	if not (build is Dictionary):
		out.reason = "there is no build for this computer in that release"
		return out
	out.url = str(build.get("url", ""))
	out.sha256 = str(build.get("sha256", "")).to_lower()
	out.size = int(build.get("size", 0))
	if not url_allowed(out.url):
		out.reason = "the download is not on the project's own release page"
		out.url = ""
		return out
	if out.sha256.length() != 64 or not out.sha256.is_valid_hex_number():
		out.reason = "the download has no checksum"
		return out
	if Semver.compare(version, current) <= 0:
		out.reason = "this is already the newest version"
		return out
	out.available = true
	return out


## Only the project's own release hosts (or whatever host the built-in manifest address uses), over https.
## The mod list checks every download address the same way (engine/client/mod_catalog.gd).
static func url_allowed(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host := _host_of(url)
	return not host.is_empty() and (ALLOWED_HOSTS.has(host) or host == _host_of(manifest_url()))


static func _host_of(url: String) -> String:
	return url.substr(8).get_slice("/", 0).get_slice(":", 0).to_lower() if url.begins_with("https://") else ""


## Whether a downloaded file is exactly what the manifest described.
static func verify(bytes: PackedByteArray, sha256: String, size := 0) -> bool:
	if bytes.is_empty() or bytes.size() > MAX_DOWNLOAD_BYTES or (size > 0 and bytes.size() != size):
		return false
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode() == sha256.to_lower()


## Where this build is installed: the .app bundle on macOS, otherwise the folder holding the executable.
## "" when the game runs from source (the editor), where there is nothing to replace.
static func installed_path() -> String:
	if not OS.has_feature("template"):
		return ""
	var executable := OS.get_executable_path()
	if OS.has_feature("macos"):
		var app := executable.get_base_dir().get_base_dir().get_base_dir()  # …/X.app/Contents/MacOS/exe
		return app if app.ends_with(".app") else ""
	return executable.get_base_dir()


## The installer for this platform: what file to write, what runs it, and what goes inside.
## `force` ("macos", "linux", "windows") is for the tests, which have to be able to read the Windows
## installer from a Mac - there is no Windows machine in this project and there may never be one.
static func installer(zip_path: String, work_dir: String, installed: String, pid: int, force := "") -> Dictionary:
	var platform := force
	if platform.is_empty():
		platform = "windows" if OS.has_feature("windows") else ("macos" if OS.has_feature("macos") else "linux")
	if platform == "windows":
		return {"file": "install.cmd", "program": "cmd.exe", "args": ["/c"],
			"text": windows_install_script(zip_path, work_dir, installed, pid)}
	return {"file": "install.sh", "program": "/bin/sh", "args": [],
		"text": install_script(zip_path, work_dir, installed, pid)}


## The Windows twin of install_script, as a batch file.
##
## Windows will not let you delete a running .exe, so everything waits for the game to go first - the
## same shape as the shell one, in a language that cannot do most of it. `tasklist` is the wait,
## PowerShell is borrowed for the unzip because batch has no such thing, and the swap is a rename so
## that a failure halfway leaves the old build where it was rather than nothing at all.
##
## **Not tested on Windows by anyone yet.** It is deliberately not reachable: Windows is a download link
## and is not in update.json, so no client will run this until somebody has tried it by hand and the
## manifest is changed to offer it. An untested script that replaces a folder is not something to arm.
static func windows_install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String:
	var unpacked := work_dir.path_join("unpacked").replace("/", "\\")
	var zip := zip_path.replace("/", "\\")
	var target := installed.replace("/", "\\")
	return "\r\n".join([
		"@echo off",
		"rem Written by Quarrowen's updater: waits for the game to quit, unpacks the update, puts it in",
		"rem place and starts it again. Safe to delete.",
		"setlocal",
		"set \"TARGET=%s\"" % target,
		"set \"UNPACKED=%s\"" % unpacked,
		"set \"ZIP=%s\"" % zip,
		"",
		"rem Windows keeps a running executable locked, so wait for it to go before touching anything.",
		"set TRIES=0",
		":wait",
		"tasklist /fi \"PID eq %d\" 2>nul | find \"%d\" >nul" % [pid, pid],
		"if errorlevel 1 goto gone",
		"set /a TRIES+=1",
		"if %TRIES% GEQ 60 goto gone",
		"timeout /t 1 /nobreak >nul",
		"goto wait",
		":gone",
		"",
		"if exist \"%UNPACKED%\" rmdir /s /q \"%UNPACKED%\"",
		"mkdir \"%UNPACKED%\"",
		"rem Batch cannot unzip; PowerShell can, and is on every Windows that can run this game.",
		"powershell -NoProfile -NonInteractive -Command \"Expand-Archive -LiteralPath '%ZIP%' -DestinationPath '%UNPACKED%' -Force\"",
		"if errorlevel 1 exit /b 1",
		"",
		"rem The zip holds one folder; find whichever one has the game in it.",
		"set \"NEW=\"",
		"if exist \"%UNPACKED%\\Quarrowen.exe\" set \"NEW=%UNPACKED%\"",
		"if not defined NEW for /d %%D in (\"%UNPACKED%\\*\") do if exist \"%%~fD\\Quarrowen.exe\" set \"NEW=%%~fD\"",
		"if not defined NEW exit /b 1",
		"",
		"rem Rename rather than delete, so a failure below still has something to put back.",
		"if exist \"%TARGET%.old\" rmdir /s /q \"%TARGET%.old\"",
		"move \"%TARGET%\" \"%TARGET%.old\" >nul 2>&1",
		"rem If that did not work - locked, or no permission to write here - stop while the old build is",
		"rem still whole. Moving onto a folder that still exists puts the new one *inside* it.",
		"if exist \"%TARGET%\" exit /b 1",
		"move \"%NEW%\" \"%TARGET%\" >nul 2>&1",
		"if errorlevel 1 (",
		"  if exist \"%TARGET%\" rmdir /s /q \"%TARGET%\"",
		"  move \"%TARGET%.old\" \"%TARGET%\" >nul 2>&1",
		"  exit /b 1",
		")",
		"",
		"if exist \"%TARGET%.old\" rmdir /s /q \"%TARGET%.old\"",
		"if exist \"%UNPACKED%\" rmdir /s /q \"%UNPACKED%\"",
		"del /q \"%ZIP%\" >nul 2>&1",
		"start \"\" \"%TARGET%\\Quarrowen.exe\"",
		"",
	])


## The script that installs a downloaded update once this process has gone: it unpacks the zip itself
## (so the executable bits inside a .app survive), swaps it with the installed build, clears the download
## flag macOS puts on it and starts the new one. Kept as a string so a test can read it without installing.
static func install_script(zip_path: String, work_dir: String, installed: String, pid: int) -> String:
	var mac := OS.has_feature("macos") or installed.ends_with(".app")
	var name := installed.get_file()
	var unpacked := work_dir.path_join("unpacked")
	var lines := [
		"#!/bin/sh",
		"# Written by Quarrowen's updater: waits for the running game to quit, unpacks the update, puts it",
		"# in place and starts it again. Safe to delete.",
		"set -e",
		"for i in $(seq 1 150); do",
		"  kill -0 %d 2>/dev/null || break" % pid,
		"  sleep 0.2",
		"done",
		"rm -rf \"%s\"" % unpacked,
		"mkdir -p \"%s\"" % unpacked,
	]
	if mac:
		lines.append("ditto -x -k \"%s\" \"%s\"" % [zip_path, unpacked])
	else:
		lines.append("unzip -oq \"%s\" -d \"%s\"" % [zip_path, unpacked])
	lines.append_array([
		"new=\"%s\"" % unpacked.path_join(name),
		"if [ ! -e \"$new\" ]; then new=$(find \"%s\" -maxdepth 2 -name \"%s\" | head -1); fi" % [unpacked, name],
		"if [ -z \"$new\" ] || [ ! -e \"$new\" ]; then exit 1; fi",
		"rm -rf \"%s.old\"" % installed,
		"mv \"%s\" \"%s.old\" 2>/dev/null || true" % [installed, installed],
		"if ! cp -R \"$new\" \"%s\"; then" % installed,
		"  rm -rf \"%s\"" % installed,
		"  mv \"%s.old\" \"%s\"" % [installed, installed],
		"  exit 1",
		"fi",
		"rm -rf \"%s.old\" \"%s\" \"%s\"" % [installed, unpacked, zip_path],
	])
	if mac:
		# Downloads carry the quarantine flag; without clearing it the new build is refused for being
		# unsigned, exactly the dance the playtest guide describes for the first install.
		lines.append("xattr -dr com.apple.quarantine \"%s\" 2>/dev/null || true" % installed)
		lines.append("open \"%s\"" % installed)
	else:
		lines.append("\"%s\" &" % installed)
	return "\n".join(lines) + "\n"
