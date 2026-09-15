extends RefCounted
## The server status query: a small UDP exchange the menu uses to show a server's name, message,
## game, players and ping before joining (and, later, LAN discovery). Servers answer on their game
## port + 1 unless configured otherwise (engine/server/status_query.gd).
##
##   request   "VXQ1" + 8 byte nonce + flags byte (1 = include a proof), zero-padded to REQUEST_SIZE
##             bytes (so answers are never much bigger than the questions: no useful amplification)
##   response  "VXR1" + the same nonce + UTF-8 JSON {name, motd, game, game_name, players, max_players,
##             protocol, version, port (the game port), code (hub invite code, if listed),
##             proof (when asked: base64 signature of PROOF_PREFIX + nonce hex with the server key)},
##             at most RESPONSE_MAX bytes
## The hub (services/hub) asks for the proof to check that an announced address belongs to the key.

const Protocol = preload("res://engine/shared/protocol.gd")

const REQUEST_MAGIC := "VXQ1"
const RESPONSE_MAGIC := "VXR1"
const REQUEST_SIZE := 512
const RESPONSE_MAX := 1024
const NONCE_SIZE := 8
const FLAG_PROOF := 1
const PROOF_PREFIX := "voxelcraft-status-proof:"


static func query_port(game_port: int) -> int:
	return game_port + 1


static func make_request(nonce: PackedByteArray, flags := 0) -> PackedByteArray:
	var out := REQUEST_MAGIC.to_ascii_buffer()
	out.append_array(nonce)
	out.append(flags)
	out.resize(REQUEST_SIZE)
	return out


## {nonce, proof} of a valid request, or {}.
static func parse_request(packet: PackedByteArray) -> Dictionary:
	if packet.size() != REQUEST_SIZE or packet.slice(0, 4).get_string_from_ascii() != REQUEST_MAGIC:
		return {}
	return {"nonce": packet.slice(4, 4 + NONCE_SIZE), "proof": packet[4 + NONCE_SIZE] & FLAG_PROOF != 0}


## The bytes a server signs to prove it holds its key.
static func proof_message(nonce: PackedByteArray) -> PackedByteArray:
	return (PROOF_PREFIX + nonce.hex_encode()).to_utf8_buffer()


static func make_response(nonce: PackedByteArray, info: Dictionary) -> PackedByteArray:
	var out := RESPONSE_MAGIC.to_ascii_buffer()
	out.append_array(nonce)
	var body := JSON.stringify(info).to_utf8_buffer()
	if out.size() + body.size() > RESPONSE_MAX:
		info = info.duplicate()
		info.motd = ""
		body = JSON.stringify(info).to_utf8_buffer().slice(0, RESPONSE_MAX - out.size())
	out.append_array(body)
	return out


## {nonce, info} from a response, or {} when it is not one. Every field is checked and clamped.
static func parse_response(packet: PackedByteArray) -> Dictionary:
	if packet.size() < 4 + NONCE_SIZE or packet.size() > RESPONSE_MAX or packet.slice(0, 4).get_string_from_ascii() != RESPONSE_MAGIC:
		return {}
	var parsed = JSON.parse_string(packet.slice(4 + NONCE_SIZE).get_string_from_utf8())
	if not (parsed is Dictionary):
		return {}
	var info := {
		"name": str(parsed.get("name", "")).left(64),
		"motd": str(parsed.get("motd", "")).left(256),
		"game": str(parsed.get("game", "")).left(64),
		"game_name": str(parsed.get("game_name", "")).left(64),
		"players": clampi(int(parsed.get("players", 0)), 0, 100000),
		"max_players": clampi(int(parsed.get("max_players", 0)), 0, 100000),
		"protocol": int(parsed.get("protocol", 0)),
		"version": str(parsed.get("version", "")).left(32),
		"port": clampi(int(parsed.get("port", 0)), 0, 65535),
		"code": str(parsed.get("code", "")).left(16),
	}
	info.compatible = info.protocol == Protocol.VERSION
	return {"nonce": packet.slice(4, 4 + NONCE_SIZE), "info": info}
