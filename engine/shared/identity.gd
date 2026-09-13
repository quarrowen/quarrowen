extends RefCounted
## Player identity: an RSA key pair per client. The public key's hash is the player's permanent id on
## every server; logging in means signing a server-chosen random challenge. Names are display names,
## bound to the first identity that claims them on each server.

const DIR := "user://identity"
const DEFAULT_BITS := 2048
const MIN_BITS_PEM_LENGTH := 200
const MAX_PEM_LENGTH := 4096
const NONCE_BYTES := 32


## Loads the named identity from user://identity, creating it on first use.
static func load_or_create(identity_name := "default", bits := DEFAULT_BITS) -> CryptoKey:
	var path := DIR.path_join(identity_name.validate_filename() + ".pem")
	var key := CryptoKey.new()
	if FileAccess.file_exists(path) and key.load(path) == OK:
		return key
	key = Crypto.new().generate_rsa(bits)
	DirAccess.make_dir_recursive_absolute(DIR)
	key.save(path)
	return key


static func public_pem(key: CryptoKey) -> String:
	return key.save_to_string(true)


static func sign(key: CryptoKey, nonce: PackedByteArray) -> PackedByteArray:
	return Crypto.new().sign(HashingContext.HASH_SHA256, _digest(nonce), key)


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


static func verify(key: CryptoKey, nonce: PackedByteArray, signature: PackedByteArray) -> bool:
	if signature.is_empty() or signature.size() > 1024:
		return false
	return Crypto.new().verify(HashingContext.HASH_SHA256, _digest(nonce), signature, key)


static func new_nonce() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(NONCE_BYTES)


static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()
