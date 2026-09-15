extends RefCounted
## Transfer tickets: how a player moves from one server to another that trusts it, carrying where they
## should arrive and (when both servers agree) what they carry.
##
## The source server writes the ticket as JSON and signs it with its identity key (the same key as its
## DTLS certificate). The client passes it to the destination right after saying hello; the destination
## accepts it only when the signing key is on its trusted list (engine/server/transfers.gd), the ticket
## names this destination and the player who logged in, it has not expired, and its nonce is new.
##
## {v, player_id, player_name, from: {id, name, key}, to: {name, address, port}, arrival, issued, expires,
##  nonce, carry: {inventory?, health?, hunger?, data?}}

const VERSION := 1
const LIFETIME := 120  # seconds a ticket stays valid
const MAX_SIZE := 64 * 1024


## The id servers use for each other: the first 32 hex characters of SHA-256 over the public key PEM.
static func key_id(key: CryptoKey) -> String:
	return pem_id(key.save_to_string(true))


static func pem_id(pem: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(pem.to_utf8_buffer())
	return ctx.finish().hex_encode().left(32)


## {ticket: JSON text, signature: base64}
static func make(source_key: CryptoKey, fields: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var data := fields.duplicate(true)
	data.v = VERSION
	data.issued = now
	data.expires = now + LIFETIME
	data.nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	var from: Dictionary = data.get("from", {})
	from.key = source_key.save_to_string(true)
	from.id = key_id(source_key)
	data.from = from
	var text := JSON.stringify(data)
	return {"ticket": text, "signature": Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, _digest(text), source_key))}


## Checks a ticket's signature and shape. `trusted`: source id -> anything truthy.
## Returns {ok: true, data} or {ok: false, error}. Expiry, destination and replay are the caller's checks
## too (see `check`), since they need the destination's own details.
static func verify(ticket: String, signature: String, trusted: Dictionary) -> Dictionary:
	if ticket.length() > MAX_SIZE or signature.length() > 2048:
		return {"ok": false, "error": "the transfer ticket is too large"}
	var parsed = JSON.parse_string(ticket) if not ticket.is_empty() else null
	if not (parsed is Dictionary) or int(parsed.get("v", 0)) != VERSION or not (parsed.get("from") is Dictionary):
		return {"ok": false, "error": "the transfer ticket is not valid"}
	var pem := str(parsed.from.get("key", ""))
	var source_id := pem_id(pem)
	if source_id != str(parsed.from.get("id", "")) or not trusted.has(source_id):
		return {"ok": false, "error": "this server does not accept travellers from %s" % str(parsed.from.get("name", "that server"))}
	var key := CryptoKey.new()
	if key.load_from_string(pem, true) != OK:
		return {"ok": false, "error": "the transfer ticket is not valid"}
	var raw := Marshalls.base64_to_raw(signature)
	if raw.is_empty() or not Crypto.new().verify(HashingContext.HASH_SHA256, _digest(ticket), raw, key):
		return {"ok": false, "error": "the transfer ticket's signature is wrong"}
	return {"ok": true, "data": parsed, "source_id": source_id}


## The destination's checks after `verify`: the logged-in player, this server, time.
static func check(data: Dictionary, player_id: String, own_id: String, now: int) -> String:
	if str(data.get("player_id", "")) != player_id:
		return "the transfer ticket belongs to another player"
	var to = data.get("to")
	if not (to is Dictionary) or str(to.get("id", "")) != own_id:
		return "the transfer ticket is for another server"
	if now > int(data.get("expires", 0)) or now < int(data.get("issued", 0)) - 60:
		return "the transfer ticket has expired"
	return ""


static func _digest(text: String) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish()
