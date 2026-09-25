extends RefCounted
## Player identity: an RSA key pair per client. The public key's hash is the player's permanent id on
## every server; logging in means signing a server-chosen random challenge. Names are display names,
## bound to the first identity that claims them on each server.

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
const DEFAULT_BITS := 2048
const MIN_BITS_PEM_LENGTH := 200
const MAX_PEM_LENGTH := 4096
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
	return dir().path_join(identity_name.validate_filename() + ".pem")


## Loads the named identity from user://identity, creating it on first use.
static func load_or_create(identity_name := "default", bits := DEFAULT_BITS) -> CryptoKey:
	var path := path_for(identity_name)
	var key := CryptoKey.new()
	if FileAccess.file_exists(path) and key.load(path) == OK:
		return key
	key = Crypto.new().generate_rsa(bits)
	DirAccess.make_dir_recursive_absolute(dir())
	key.save(path)
	return key


static func public_pem(key: CryptoKey) -> String:
	return key.save_to_string(true)


## Signs the challenge. **`audience` is who the signature is *for*, and leaving it out is the bug this
## parameter exists to fix.**
##
## Signing a bare nonce proves you hold the key and nothing else - so a hostile server could take the
## nonce a real server handed it, pass it to you as its own challenge, and replay your answer to log
## in as you. Binding the server's id into what is signed makes the answer worthless anywhere else:
## the real server hashes its own id and the signature no longer matches. The hub has always done it
## this way; the game handshake did not. (2026-09-24)
static func sign(key: CryptoKey, nonce: PackedByteArray, audience := "") -> PackedByteArray:
	return Crypto.new().sign(HashingContext.HASH_SHA256, _digest(_bind(nonce, audience)), key)


## Server side: parses a public key PEM; returns null if it is not a usable key.
static func parse_public_key(pem: String) -> CryptoKey:
	if pem.length() < MIN_BITS_PEM_LENGTH or pem.length() > MAX_PEM_LENGTH:
		return null
	var key := CryptoKey.new()
	return key if key.load_from_string(pem, true) == OK else null


## Stable id derived from the public key (32 hex characters).
static func player_id(key: CryptoKey) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(key.save_to_string(true).to_utf8_buffer())
	return ctx.finish().hex_encode().left(32)


static func verify(key: CryptoKey, nonce: PackedByteArray, signature: PackedByteArray, audience := "") -> bool:
	if signature.is_empty() or signature.size() > 1024:
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, _digest(_bind(nonce, audience)), signature, key)


## What is actually signed: a purpose, who it is for, and the nonce. The purpose is there so a
## signature made for this handshake can never be mistaken for one made for anything else we sign
## later - the mistake this whole change is about, one layer up.
static func _bind(nonce: PackedByteArray, audience: String) -> PackedByteArray:
	if audience.is_empty():
		return nonce
	var bound := "quarrowen-join:%s:" % audience
	return bound.to_utf8_buffer() + nonce


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

## Returns the JSON text of an encrypted identity file.
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
static func export_for_transfer(key: CryptoKey, code: String) -> String:
	return export_encrypted(key, tidy_transfer_code(code))


static func import_from_transfer(blob: String, code: String) -> Dictionary:
	return import_encrypted(blob, tidy_transfer_code(code))


static func export_encrypted(key: CryptoKey, passphrase: String, iterations := EXPORT_ITERATIONS) -> String:
	var crypto := Crypto.new()
	var salt := crypto.generate_random_bytes(16)
	var iv := crypto.generate_random_bytes(16)
	var keys := _derive_keys(passphrase, salt, iterations)
	var plaintext := key.save_to_string(false).to_utf8_buffer()
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


## Decrypts an exported identity. Returns {key: CryptoKey, player_id} or {error: String}.
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
	var key := CryptoKey.new()
	if key.load_from_string(plaintext.slice(0, plaintext.size() - padding).get_string_from_utf8()) != OK:
		return {"error": "Identity file does not contain a valid key"}
	return {"key": key, "player_id": player_id(key)}


## Saves `key` as the named identity. An existing different identity is kept as a .bak file.
static func install(key: CryptoKey, identity_name := "default") -> Error:
	DirAccess.make_dir_recursive_absolute(dir())
	var path := path_for(identity_name)
	if FileAccess.file_exists(path):
		var current := CryptoKey.new()
		if current.load(path) == OK and player_id(current) == player_id(key):
			return OK
		var backup := "%s.bak-%d" % [path, int(Time.get_unix_time_from_system())]
		var err := DirAccess.rename_absolute(path, backup)
		if err != OK:
			return err
	return key.save(path)


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
