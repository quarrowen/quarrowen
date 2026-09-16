extends Node
## Offline test of encrypted identity export / import:
##   godot --headless --path . res://tests/identity_test.tscn

const Identity = preload("res://engine/shared/identity.gd")

const NAME := "identity_test"
var _failures := 0


func _ready() -> void:
	var key := Crypto.new().generate_rsa(1024)
	var passphrase := "correct horse battery"
	var text := Identity.export_encrypted(key, passphrase, 20000)
	_check(not text.contains("PRIVATE KEY"), "export does not contain the key in plain text")

	var imported := Identity.import_encrypted(text, passphrase)
	_check(imported.has("key") and imported.player_id == Identity.player_id(key), "roundtrip keeps the player id")
	if imported.has("key"):
		var nonce := Identity.new_nonce()
		_check(Identity.verify(key, nonce, Identity.sign(imported.key, nonce)), "imported key signs for the original identity")

	_check(Identity.import_encrypted(text, "wrong passphrase").get("error", "").contains("Wrong passphrase"), "wrong passphrase rejected")
	var doc: Dictionary = JSON.parse_string(text)
	var bytes := Marshalls.base64_to_raw(doc.ciphertext)
	bytes[5] ^= 1
	doc.ciphertext = Marshalls.raw_to_base64(bytes)
	_check(Identity.import_encrypted(JSON.stringify(doc), passphrase).has("error"), "modified ciphertext rejected")
	doc = JSON.parse_string(text)
	doc.iterations = 20001
	_check(Identity.import_encrypted(JSON.stringify(doc), passphrase).has("error"), "modified parameters rejected")
	_check(Identity.import_encrypted("{}", passphrase).get("error", "").contains("Not a Quarrowen"), "unrelated file rejected")

	# Installing replaces the named identity and keeps the previous one.
	var path := Identity.path_for(NAME)
	var previous := Identity.load_or_create(NAME, 1024)
	_check(Identity.install(imported.key, NAME) == OK, "install succeeds")
	_check(Identity.player_id(Identity.load_or_create(NAME)) == Identity.player_id(key), "installed identity is used")
	var backups := Array(DirAccess.get_files_at(Identity.DIR)).filter(func(f): return f.begins_with(NAME + ".pem.bak-"))
	_check(backups.size() == 1, "previous identity kept as backup (%s)" % str(backups))
	var kept := CryptoKey.new()
	_check(not backups.is_empty() and kept.load(Identity.DIR.path_join(backups[0])) == OK and Identity.player_id(kept) == Identity.player_id(previous), "backup holds the previous key")
	for f in backups:
		DirAccess.remove_absolute(Identity.DIR.path_join(f))
	DirAccess.remove_absolute(path)

	print("[identity] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[identity] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
