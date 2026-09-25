extends Node
## Offline test of encrypted identity export / import:
##   godot --headless --path . res://tests/identity_test.tscn

const Identity = preload("res://engine/shared/identity.gd")

const NAME := "identity_test"
var _failures := 0


func _ready() -> void:
	var key: Dictionary = Identity.load_or_create("identity_source")
	var passphrase := "correct horse battery"
	var text := Identity.export_encrypted(key, passphrase, 20000)
	_check(not text.contains(Marshalls.raw_to_base64(key.private)), "export does not contain the key in plain text")

	var imported := Identity.import_encrypted(text, passphrase)
	_check(imported.has("key") and imported.player_id == Identity.player_id(key), "roundtrip keeps the player id")
	if imported.has("key"):
		var nonce := Identity.new_nonce()
		_check(Identity.verify(key.public, nonce, Identity.sign(imported.key, nonce)), "imported key signs for the original identity")

	_check(Identity.import_encrypted(text, "wrong passphrase").get("error", "").contains("Wrong passphrase"), "wrong passphrase rejected")
	var doc: Dictionary = JSON.parse_string(text)
	var bytes := Marshalls.base64_to_raw(doc.ciphertext)
	bytes[5] ^= 1
	doc.ciphertext = Marshalls.raw_to_base64(bytes)
	_check(Identity.import_encrypted(JSON.stringify(doc), passphrase).has("error"), "modified ciphertext rejected")
	doc = JSON.parse_string(text)
	doc.iterations = 20001
	_check(Identity.import_encrypted(JSON.stringify(doc), passphrase).has("error"), "modified parameters rejected")
	_typed()
	_check(Identity.import_encrypted("{}", passphrase).get("error", "").contains("Not a Quarrowen"), "unrelated file rejected")

	# Installing replaces the named identity and keeps the previous one.
	var path := Identity.path_for(NAME)
	var previous := Identity.load_or_create(NAME)
	_check(Identity.install(imported.key, NAME) == OK, "install succeeds")
	_check(Identity.player_id(Identity.load_or_create(NAME)) == Identity.player_id(key), "installed identity is used")
	var backups := Array(DirAccess.get_files_at(Identity.dir())).filter(func(f): return f.begins_with(NAME + ".key.bak-"))
	_check(backups.size() == 1, "previous identity kept as backup (%s)" % str(backups))
	var kept := Identity.pair_from(FileAccess.get_file_as_bytes(Identity.dir().path_join(backups[0]))) if not backups.is_empty() else {}
	_check(not kept.is_empty() and Identity.player_id(kept) == Identity.player_id(previous), "backup holds the previous key")
	for f in backups:
		DirAccess.remove_absolute(Identity.dir().path_join(f))
	DirAccess.remove_absolute(path)

	print("[identity] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Moving an identity to another device is now typing it in: 44 characters of base64, off one screen and
## into the other. **The untidy path is the one that matters** - a key copied by hand arrives with a line
## break or a stray space in it far more often than not, and refusing those would make a working key look
## like a broken one.
func _typed() -> void:
	var key: Dictionary = Identity.load_or_create("typed_source")
	var text := Identity.private_text(key)
	_check(text.length() == 44, "a key is 44 characters, short enough to type (%d)" % text.length())
	var back := Identity.from_private_text(text)
	_check(not back.is_empty() and Identity.player_id(back) == Identity.player_id(key), "typing it back gives the same identity")
	var untidy := " %s\n  %s \n" % [text.substr(0, 20), text.substr(20)]
	_check(Identity.player_id(Identity.from_private_text(untidy)) == Identity.player_id(key),
		"and so does a copy that arrived wrapped and padded with spaces")
	_check(Identity.from_private_text("").is_empty(), "nothing is not a key")
	_check(Identity.from_private_text("not a key at all").is_empty(), "nor is a sentence")
	# **Any 32 bytes is a valid Ed25519 private key**, so a key typed with one character wrong cannot be
	# detected - it is simply a different person, one nobody has ever been. Pasting the *public* half,
	# which is the same length and alphabet and so the likeliest mistake, is the clearest case of it.
	# Nothing here can refuse that; what makes it survivable is upstream, and both halves are asserted
	# below: `install` keeps the key it replaced, and the menu says which id you have become.
	var mistake := Identity.from_private_text(Identity.public_text(key))
	_check(not mistake.is_empty() and Identity.player_id(mistake) != Identity.player_id(key),
		"a key typed wrong is a different person rather than an error, which is why install keeps a backup")
	_check(Identity.from_private_text("A".repeat(Identity.MAX_KEY_TEXT + 1)).is_empty(), "an oversized string is refused before it is decoded")


func _check(ok: bool, what: String) -> void:
	print("[identity] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
