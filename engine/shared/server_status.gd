extends RefCounted
## The server status query: a small UDP exchange the menu uses to show a server's name, message,
## game, players and ping before joining (and, later, LAN discovery). Servers answer on their game
## port + 1 unless configured otherwise (engine/server/status_query.gd).
##
##   request   "VXQ1" + 8 byte nonce, zero-padded to REQUEST_SIZE bytes (so answers are never much
##             bigger than the questions: no useful traffic amplification)
##   response  "VXR1" + the same nonce + UTF-8 JSON {name, motd, game, game_name, players, max_players,
##             protocol, version}, at most RESPONSE_MAX bytes

const Protocol = preload("res://engine/shared/protocol.gd")

const REQUEST_MAGIC := "VXQ1"
const RESPONSE_MAGIC := "VXR1"
const REQUEST_SIZE := 512
const RESPONSE_MAX := 1024
const NONCE_SIZE := 8


static func query_port(game_port: int) -> int:
	return game_port + 1


static func make_request(nonce: PackedByteArray) -> PackedByteArray:
	var out := REQUEST_MAGIC.to_ascii_buffer()
	out.append_array(nonce)
	out.resize(REQUEST_SIZE)
	return out


## The nonce of a valid request, or an empty array.
static func parse_request(packet: PackedByteArray) -> PackedByteArray:
	if packet.size() != REQUEST_SIZE or packet.slice(0, 4).get_string_from_ascii() != REQUEST_MAGIC:
		return PackedByteArray()
	return packet.slice(4, 4 + NONCE_SIZE)


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
	}
	info.compatible = info.protocol == Protocol.VERSION
	return {"nonce": packet.slice(4, 4 + NONCE_SIZE), "info": info}
