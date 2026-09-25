extends RefCounted
## Transfer tickets: how a player moves from one server to another that trusts it, carrying where they
## should arrive and (when both servers agree) what they carry.
##
## The source server writes the ticket as JSON and signs it with its Ed25519 identity key
## (`Net.load_or_create_server_key`, separate from its DTLS certificate since 2026-09-25). The client
## passes it to the destination right after saying hello; the destination accepts it only when the
## signing key is on its trusted list (engine/server/transfers.gd), the ticket names this destination
## and the player who logged in, it has not expired, and its nonce is new.
##
## {v, player_id, player_name, from: {id, name, key}, to: {name, address, port}, arrival, issued, expires,
##  nonce, carry: {inventory?, health?, hunger?, data?}}

const Identity = preload("res://engine/shared/identity.gd")

const VERSION := 1
const LIFETIME := 120  # seconds a ticket stays valid
const MAX_SIZE := 64 * 1024


## The id servers use for each other: the same id a player has, over the server's own public key, so
## there is one id scheme in the project rather than two that look alike.
static func key_id(key) -> String:
	return Identity.player_id(key)


## {ticket: JSON text, signature: base64}
static func make(source_key: Dictionary, fields: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var data := fields.duplicate(true)
	data.v = VERSION
	data.issued = now
	data.expires = now + LIFETIME
	data.nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	var from: Dictionary = data.get("from", {})
	from.key = Identity.public_text(source_key)
	from.id = key_id(source_key)
	data.from = from
	var text := JSON.stringify(data)
	return {"ticket": text, "signature": Marshalls.raw_to_base64(Identity.sign(source_key, text.to_utf8_buffer()))}


## Checks a ticket's signature and shape. `trusted`: source id -> anything truthy.
## Returns {ok: true, data} or {ok: false, error}. Expiry, destination and replay are the caller's checks
## too (see `check`), since they need the destination's own details.
static func verify(ticket: String, signature: String, trusted: Dictionary) -> Dictionary:
	if ticket.length() > MAX_SIZE or signature.length() > 2048:
		return {"ok": false, "error": "the transfer ticket is too large"}
	var parsed = JSON.parse_string(ticket) if not ticket.is_empty() else null
	if not (parsed is Dictionary) or int(parsed.get("v", 0)) != VERSION or not (parsed.get("from") is Dictionary):
		return {"ok": false, "error": "the transfer ticket is not valid"}
	var public := Identity.parse_public_key(str(parsed.from.get("key", "")))
	if public.is_empty():
		return {"ok": false, "error": "the transfer ticket is not valid"}
	var source_id := key_id(public)
	if source_id != str(parsed.from.get("id", "")) or not trusted.has(source_id):
		return {"ok": false, "error": "this server does not accept travellers from %s" % str(parsed.from.get("name", "that server"))}
	if not Identity.verify(public, ticket.to_utf8_buffer(), Marshalls.base64_to_raw(signature)):
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


