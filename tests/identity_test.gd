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
	_transfer()
	_check(Identity.import_encrypted("{}", passphrase).get("error", "").contains("Not a Quarrowen"), "unrelated file rejected")

	# Installing replaces the named identity and keeps the previous one.
	var path := Identity.path_for(NAME)
	var previous := Identity.load_or_create(NAME, 1024)
	_check(Identity.install(imported.key, NAME) == OK, "install succeeds")
	_check(Identity.player_id(Identity.load_or_create(NAME)) == Identity.player_id(key), "installed identity is used")
	var backups := Array(DirAccess.get_files_at(Identity.dir())).filter(func(f): return f.begins_with(NAME + ".pem.bak-"))
	_check(backups.size() == 1, "previous identity kept as backup (%s)" % str(backups))
	var kept := CryptoKey.new()
	_check(not backups.is_empty() and kept.load(Identity.dir().path_join(backups[0])) == OK and Identity.player_id(kept) == Identity.player_id(previous), "backup holds the previous key")
	for f in backups:
		DirAccess.remove_absolute(Identity.dir().path_join(f))
	DirAccess.remove_absolute(path)

	print("[identity] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Moving an identity to another device, and the one property that makes it safe to leave an encrypted
## private key on a server for ten minutes: **the server is never given the key.**
func _transfer() -> void:
	var key: CryptoKey = Identity.load_or_create("transfer_source")
	var code := Identity.new_transfer_code()
	_check(code.length() == Identity.TRANSFER_GROUPS * (Identity.TRANSFER_GROUP_SIZE + 1) - 1,
		"a transfer code is groups of characters (%s)" % code)
	_check(not code.contains("0") and not code.contains("O") and not code.contains("1"),
		"and avoids characters that look like each other")
	# Typed back with the dashes lost, the case wrong and a stray space: still the same code.
	var sloppy := code.to_lower().replace("-", " ") + " "
	_check(Identity.transfer_handle(sloppy) == Identity.transfer_handle(code),
		"a code typed untidily still finds the same transfer")
	# The handle is what the server sees. It must not be the code.
	var handle := Identity.transfer_handle(code)
	_check(handle.length() == 32 and handle.is_valid_hex_number(), "the handle is a hash")
	_check(not handle.contains(Identity.tidy_transfer_code(code)), "and is not the code itself")
	# **The property that matters**: holding the blob and the handle - everything the server has - must
	# not be enough to read the identity. Only the code does that, and the code never reaches it.
	var blob := Identity.export_for_transfer(key, code)
	_check(Identity.import_from_transfer(blob, handle).has("error"),
		"what the server holds cannot open what the server holds")
	var wrong := Identity.new_transfer_code()
	_check(Identity.import_from_transfer(blob, wrong).has("error"), "and another code does not open it either")
	var got := Identity.import_from_transfer(blob, sloppy)
	_check(got.get("error", "").is_empty() and Identity.player_id(got.key) == Identity.player_id(key),
		"while the right code, typed untidily, gives back the same identity")


func _check(ok: bool, what: String) -> void:
	print("[identity] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
