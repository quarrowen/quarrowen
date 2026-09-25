extends RefCounted
## Player identity: an Ed25519 key pair per client. The public key's hash is the player's permanent id
## on every server; logging in means signing a server-chosen random challenge. Names are display names,
## bound to the first identity that claims them on each server.
##
## A **server** has one of these too, since 2026-09-25 (`Net.load_or_create_server_key`), so that one
## kind of key and one kind of id run through the whole project rather than two that look alike.
##
## **Ed25519 rather than RSA, and the reason is a number.** Godot's `Crypto` offers only RSA, and an
## RSA-2048 private key is 1,675 characters of PEM. That size decided the whole design of moving an
## identity between devices: too big to type, too big for a QR anybody can scan, so it had to travel
## over a network - either both devices on one LAN, or a server holding it in the middle. A server
## holding player keys is the wrong shape for identities that are meant to be local, and the user said
## so. An Ed25519 private key is **32 bytes**: 44 characters of base64, read off one screen and typed
## into the other, or written on paper. (2026-09-25)
##
## Signing lives in the Rust extension (`native/src/identity.rs`) because Godot cannot do it. The
## extension is required anyway.
##
## **A key here is a Dictionary of both halves**, `{private, public}`, and that is deliberate: both are
## 32 bytes, so a function taking a bare array could be handed the wrong one and would quietly compute
## a different player id. There is no shape of mistake this design allows.

const UserPaths = preload("res://engine/shared/user_paths.gd")


## Where identities live. QW_IDENTITY_DIR moves them, which is how the tests keep their bot keys out of
## the player's own folder: a test run used to overwrite default.pem and take the player's account with
## it. (2026-09-18)
static func dir() -> String:
	var override := OS.get_environment("QW_IDENTITY_DIR")
	# Falls back to QW_USER_DIR rather than a bare `user://`. The named override is what the suite sets;
	# the tools set only QW_USER_DIR, and `tools/look_shots.sh` was therefore signing in to its throwaway
	# servers as the player. (2026-09-22)
	return override if not override.is_empty() else UserPaths.path("identity")


const KEY_BYTES := 32
const SIGNATURE_BYTES := 64
## A public key as text: base64 of 32 bytes. Kept as a bound rather than an equality so a future
## format has somewhere to go, and so a stranger's oversized string is refused before it is decoded.
const MAX_PUBLIC_TEXT := 128
const NONCE_BYTES := 32


const EXPORT_FORMAT := "quarrowen-identity"
const EXPORT_ITERATIONS := 210000
const MIN_PASSPHRASE_LENGTH := 8

## Moving an identity to another device: the shape of the one-time code, and how it is split.
##
## **The code is read aloud and typed, so the alphabet avoids every pair that looks alike** - no O or
## 0, no I or 1, no S or 5. Five groups of four is a hundred bits, which is far more than is needed to
## stop somebody guessing it within the ten minutes it lives, and is chosen for the *other* threat: the
## server holds the ciphertext, so the code must resist an offline attack by whoever runs it. It is
## their own identity, so this is belt and braces - but the cost of the braces is four more characters.
const TRANSFER_ALPHABET := "ABCDEFGHJKLMNPQRTUVWXYZ2346789"
const TRANSFER_GROUPS := 5
const TRANSFER_GROUP_SIZE := 4


static func path_for(identity_name := "default") -> String:
	return dir().path_join(identity_name.validate_filename() + ".key")


## A key pair from 32 private bytes: `{private, public}`, or `{}` when the bytes are the wrong size.
static func pair_from(private: PackedByteArray) -> Dictionary:
	if private.size() != KEY_BYTES:
		return {}
	var public: PackedByteArray = ClassDB.class_call_static(&"NativeIdentity", &"public_key", private)
	return {} if public.size() != KEY_BYTES else {"private": private, "public": public}


## Loads the named identity, creating it on first use. Returns `{private, public}`.
static func load_or_create(identity_name := "default") -> Dictionary:
	return load_or_create_at(path_for(identity_name))


## The same, at an exact path rather than a name under `dir()`. A server's own identity lives beside its
## world rather than in the player's identity folder, because it belongs to the world: copy the save and
## the server is still the same server to everybody who trusts it.
static func load_or_create_at(path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		var pair := pair_from(FileAccess.get_file_as_bytes(path))
		if not pair.is_empty():
			return pair
	var made := pair_from(ClassDB.class_call_static(&"NativeIdentity", &"generate"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(made.private)
		file.close()
	return made


## The public half as text, which is what crosses the wire.
static func public_text(key: Dictionary) -> String:
	return Marshalls.raw_to_base64(key.get("public", PackedByteArray()))


## Signs the challenge. **`audience` is who the signature is *for*, and leaving it out is the bug this
## parameter exists to fix.**
##
## Signing a bare nonce proves you hold the key and nothing else - so a hostile server could take the
## nonce a real server handed it, pass it to you as its own challenge, and replay your answer to log
## in as you. Binding the server's id into what is signed makes the answer worthless anywhere else:
## the real server hashes its own id and the signature no longer matches. The hub has always done it
## this way; the game handshake did not. (2026-09-24)
##
## With no `audience` this signs `message` exactly as given, which is how everything that is not a login
## challenge uses it: a transfer ticket, a hub announce, a status proof. Ed25519 signs the whole message,
## so there is no digest to agree on separately.
static func sign(key: Dictionary, message: PackedByteArray, audience := "") -> PackedByteArray:
	return ClassDB.class_call_static(&"NativeIdentity", &"sign", key.get("private", PackedByteArray()),
		_bind(message, audience))


## Server side: the 32 public bytes a client sent, or an empty array when it is not a usable key.
## Checked for length *before* decoding, so an oversized string from a stranger costs nothing.
static func parse_public_key(text: String) -> PackedByteArray:
	if text.length() > MAX_PUBLIC_TEXT:
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(text)
	return bytes if bytes.size() == KEY_BYTES else PackedByteArray()


## Stable id derived from the public key (32 hex characters). Takes a `{private, public}` pair or the
## public bytes on their own - which is what a server has.
static func player_id(key) -> String:
	var public: PackedByteArray = key.get("public", PackedByteArray()) if key is Dictionary else key
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(public)
	return ctx.finish().hex_encode().left(32)


## Whether this public key signed the challenge. Takes the public bytes, since that is all a server
## ever has of somebody.
static func verify(public: PackedByteArray, message: PackedByteArray, signature: PackedByteArray, audience := "") -> bool:
	if signature.size() != SIGNATURE_BYTES or public.size() != KEY_BYTES:
		return false
	return ClassDB.class_call_static(&"NativeIdentity", &"verify", public, _bind(message, audience), signature)


## What is actually signed: a purpose, who it is for, and the nonce. The purpose is there so a
## signature made for this handshake can never be mistaken for one made for anything else we sign
## later - the mistake this whole change is about, one layer up.
static func _bind(message: PackedByteArray, audience: String) -> PackedByteArray:
	if audience.is_empty():
		return message
	var bound := "quarrowen-join:%s:" % audience
	return bound.to_utf8_buffer() + message


static func new_nonce() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(NONCE_BYTES)


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()


# --- Export / import ------------------------------------------------------------------------------
# The identity *is* the account, so it is exported encrypted: PBKDF2-HMAC-SHA256 stretches the
# passphrase, AES-256-CBC encrypts the private key and HMAC-SHA256 authenticates the ciphertext
# (encrypt-then-MAC, separate keys), so a wrong passphrase or a modified file is detected.

## A fresh transfer code, in groups for reading out: "ABCD-EFGH-IJKL-MNOP-QRST".
static func new_transfer_code() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(TRANSFER_GROUPS * TRANSFER_GROUP_SIZE)
	var groups := []
	for g in TRANSFER_GROUPS:
		var chunk := ""
		for i in TRANSFER_GROUP_SIZE:
			chunk += TRANSFER_ALPHABET[bytes[g * TRANSFER_GROUP_SIZE + i] % TRANSFER_ALPHABET.length()]
		groups.append(chunk)
	return "-".join(groups)


## What the code looks like once dashes, spaces and case are forgiven. Typing it back is the one part a
## person does by hand, so every way of getting it slightly wrong that still means the same thing is
## accepted.
static func tidy_transfer_code(typed: String) -> String:
	var out := ""
	for c in typed.to_upper():
		if TRANSFER_ALPHABET.contains(c):
			out += c
	return out


## **The half of the code the server is allowed to see.** A transfer is stored under this, and it is a
## hash - so a server holding the ciphertext holds nothing that decrypts it. Splitting the code this
## way is the whole reason the server can be handed an encrypted private key at all: store it under
## the code itself and "encrypted" would mean nothing, because the key would have arrived with it.
static func transfer_handle(code: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("quarrowen-transfer-handle:" + tidy_transfer_code(code)).to_utf8_buffer())
	return ctx.finish().hex_encode().left(32)


## Encrypting and decrypting *for a transfer*, as a pair, so the two ends cannot disagree about what
## the passphrase was. **Both tidy the code first**: the person reading it out says the letters and the
## person typing it may or may not put the dashes in, and a key derived from the difference is a
## transfer that fails with "wrong code" when the code was right. Found by testing the untidy path
## rather than the neat one. (2026-09-25)
static func export_for_transfer(key: Dictionary, code: String) -> String:
	return export_encrypted(key, tidy_transfer_code(code))


static func import_from_transfer(blob: String, code: String) -> Dictionary:
	return import_encrypted(blob, tidy_transfer_code(code))


## Returns the JSON text of an encrypted identity file.
static func export_encrypted(key: Dictionary, passphrase: String, iterations := EXPORT_ITERATIONS) -> String:
	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(16)
	var iv := crypto.generate_random_bytes(16)
	var keys := _derive_keys(passphrase, salt, iterations)
	var plaintext: PackedByteArray = key.get("private", PackedByteArray()).duplicate()
	var padding := 16 - plaintext.size() % 16
	for i in padding:
		plaintext.append(padding)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, keys[0], iv)
	var ciphertext := aes.update(plaintext)
	aes.finish()
	var doc := {"format": EXPORT_FORMAT, "version": 1, "player_id": player_id(key), "kdf": "pbkdf2-hmac-sha256",
		"iterations": iterations, "salt": Marshalls.raw_to_base64(salt), "iv": Marshalls.raw_to_base64(iv),
		"cipher": "aes-256-cbc", "ciphertext": Marshalls.raw_to_base64(ciphertext)}
	doc.mac = Marshalls.raw_to_base64(crypto.hmac_digest(HashingContext.HASH_SHA256, keys[1], _mac_input(doc)))
	return JSON.stringify(doc, "\t")


## Decrypts an exported identity. Returns {key: {private, public}, player_id} or {error: String}.
static func import_encrypted(text: String, passphrase: String) -> Dictionary:
	var doc = JSON.parse_string(text) if text.length() < 16384 else null
	if not (doc is Dictionary) or doc.get("format") != EXPORT_FORMAT or int(doc.get("version", 0)) != 1:
		return {"error": "Not a Quarrowen identity file"}
	var iterations := int(doc.get("iterations", 0))
	if iterations < 10000 or iterations > 10000000:
		return {"error": "Unsupported identity file parameters"}
	var salt := Marshalls.base64_to_raw(String(doc.get("salt", "")))
	var iv := Marshalls.base64_to_raw(String(doc.get("iv", "")))
	var ciphertext := Marshalls.base64_to_raw(String(doc.get("ciphertext", "")))
	if salt.size() != 16 or iv.size() != 16 or ciphertext.is_empty() or ciphertext.size() % 16 != 0:
		return {"error": "Identity file is damaged"}
	var keys := _derive_keys(passphrase, salt, iterations)
	var crypto := Crypto.new()
	var expected := crypto.hmac_digest(HashingContext.HASH_SHA256, keys[1], _mac_input(doc))
	if not crypto.constant_time_compare(expected, Marshalls.base64_to_raw(String(doc.get("mac", "")))):
		return {"error": "Wrong passphrase, or the file was modified"}
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, keys[0], iv)
	var plaintext := aes.update(ciphertext)
	aes.finish()
	var padding := plaintext[plaintext.size() - 1]
	if padding < 1 or padding > 16:
		return {"error": "Identity file is damaged"}
	var pair := pair_from(plaintext.slice(0, plaintext.size() - padding))
	if pair.is_empty():
		return {"error": "Identity file does not contain a valid key"}
	return {"key": pair, "player_id": player_id(pair)}


## Saves `key` as the named identity. An existing different identity is kept as a .bak file.
static func install(key: Dictionary, identity_name := "default") -> Error:
	if key.get("private", PackedByteArray()).size() != KEY_BYTES:
		return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(dir())
	var path := path_for(identity_name)
	if FileAccess.file_exists(path):
		var current := pair_from(FileAccess.get_file_as_bytes(path))
		if not current.is_empty() and player_id(current) == player_id(key):
			return OK
		# **The one you are replacing is kept.** Installing the wrong identity over the right one is
		# otherwise unrecoverable, and the whole reason this exists is that a lost key is a lost person.
		var backup := "%s.bak-%d" % [path, int(Time.get_unix_time_from_system())]
		var err := DirAccess.rename_absolute(path, backup)
		if err != OK:
			return err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(key.private)
	file.close()
	return OK


static func _mac_input(doc: Dictionary) -> PackedByteArray:
	return ("%s|%d|%s|%d|%s|%s|%s" % [doc.format, int(doc.version), doc.get("player_id", ""), int(doc.iterations), doc.salt, doc.iv, doc.ciphertext]).to_utf8_buffer()


## [encryption key, MAC key], both 32 bytes, from one PBKDF2 output.
static func _derive_keys(passphrase: String, salt: PackedByteArray, iterations: int) -> Array:
	var master := pbkdf2_sha256(passphrase.to_utf8_buffer(), salt, iterations)
	var crypto := Crypto.new()
	return [crypto.hmac_digest(HashingContext.HASH_SHA256, master, "encrypt".to_utf8_buffer()),
		crypto.hmac_digest(HashingContext.HASH_SHA256, master, "authenticate".to_utf8_buffer())]


## PBKDF2-HMAC-SHA256 with a single 32-byte output block.
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray, iterations: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, block)
	# XOR the running result as four 64-bit words; much faster than per-byte loops in GDScript.
	var a := u.decode_u64(0)
	var b := u.decode_u64(8)
	var c := u.decode_u64(16)
	var d := u.decode_u64(24)
	for i in range(1, iterations):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		a ^= u.decode_u64(0)
		b ^= u.decode_u64(8)
		c ^= u.decode_u64(16)
		d ^= u.decode_u64(24)
	var out := PackedByteArray()
	out.resize(32)
	out.encode_u64(0, a)
	out.encode_u64(8, b)
	out.encode_u64(16, c)
	out.encode_u64(24, d)
	return out
