extends SceneTree
## The key that signs releases, and the signing itself. A client only installs an update whose manifest is
## signed by a key it already trusts (engine/client/updater.gd RELEASE_KEYS), so taking over the website or
## its DNS is not enough to push a build to anyone.
##
##   godot --headless --path . -s tools/release_key.gd -- new [--out=~/.config/quarrowen/release_key.pem]
##       makes a key, writes the private half (keep it safe and off this repository) and prints the public
##       half to paste into Updater.RELEASE_KEYS.
##
##   godot --headless --path . -s tools/release_key.gd -- sign --file=build/release/update.json
##       writes build/release/update.json.sig next to it. tools/make_release.sh does this for you when
##       QUARROWEN_RELEASE_KEY points at the private key.
##
## Rotating: generate a new key, add its public half to RELEASE_KEYS *alongside* the old one, ship that
## build, and only then start signing with the new key. Drop the old entry a release or two later.

const KEY_BITS := 3072


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var command := args[0] if args.size() > 0 else ""
	var options := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			options[kv[0]] = kv[1] if kv.size() > 1 else "true"
	match command:
		"new":
			_new(str(options.get("out", "~/.config/quarrowen/release_key.pem")))
		"sign":
			_sign(str(options.get("file", "build/release/update.json")), str(options.get("key", _key_path())))
		_:
			print("usage: release_key.gd -- new [--out=<path>] | sign --file=<manifest> [--key=<path>]")
			quit(1)
	quit()


func _new(out_path: String) -> void:
	var path := _expand(out_path)
	if FileAccess.file_exists(path):
		print("[release_key] %s already exists - move it aside first, or you will invalidate the old key" % path)
		quit(1)
		return
	var key := Crypto.new().generate_rsa(KEY_BITS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("[release_key] could not write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(key.save_to_string(false))
	file.close()
	print("[release_key] private key written to %s - back it up somewhere safe and never commit it" % path)
	print("[release_key] paste this into RELEASE_KEYS in engine/client/updater.gd:\n")
	print('\t"%s",' % key.save_to_string(true).replace("\n", "\\n"))


func _sign(manifest_path: String, key_path: String) -> void:
	var path := _expand(key_path)
	var key := CryptoKey.new()
	if not FileAccess.file_exists(path) or key.load(path, false) != OK:
		print("[release_key] no private key at %s (make one with 'new', or set QUARROWEN_RELEASE_KEY)" % path)
		quit(1)
		return
	if not FileAccess.file_exists(manifest_path):
		print("[release_key] no manifest at %s" % manifest_path)
		quit(1)
		return
	var text := FileAccess.get_file_as_string(manifest_path)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(text.to_utf8_buffer())
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, digest.finish(), key)
	var out := FileAccess.open(manifest_path + ".sig", FileAccess.WRITE)
	out.store_string(Marshalls.raw_to_base64(signature))
	out.close()
	print("[release_key] signed %s -> %s.sig" % [manifest_path, manifest_path])


func _key_path() -> String:
	var configured := OS.get_environment("QUARROWEN_RELEASE_KEY")
	return configured if not configured.is_empty() else "~/.config/quarrowen/release_key.pem"


static func _expand(path: String) -> String:
	return OS.get_environment("HOME").path_join(path.substr(2)) if path.begins_with("~/") else path
