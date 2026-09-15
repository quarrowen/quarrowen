extends RefCounted
## Asks several servers for their status at once (engine/shared/server_status.gd). Call `update()` every
## frame; `result` carries {address, port, online, ping_ms, info} or {address, port, online: false, error}.
## Addresses may be host names (resolved when pinged).

signal result(key: String, entry: Dictionary)

const ServerStatus = preload("res://engine/shared/server_status.gd")
const TIMEOUT := 2.0

var _udp := PacketPeerUDP.new()
var _pending := {}  # nonce hex -> {key, address, port, sent}


func _init() -> void:
	_udp.bind(0)


## `key` identifies the answer (e.g. "host:port").
func ping(key: String, address: String, game_port: int) -> void:
	var ip := address if address.is_valid_ip_address() else IP.resolve_hostname(address, IP.TYPE_IPV4)
	if ip.is_empty():
		result.emit(key, {"address": address, "port": game_port, "online": false, "error": "unknown host"})
		return
	var nonce := Crypto.new().generate_random_bytes(ServerStatus.NONCE_SIZE)
	_udp.set_dest_address(ip, ServerStatus.query_port(game_port))
	_udp.put_packet(ServerStatus.make_request(nonce))
	_pending[nonce.hex_encode()] = {"key": key, "address": address, "port": game_port, "sent": Time.get_ticks_msec()}


func update() -> void:
	while _udp.get_available_packet_count() > 0:
		var parsed: Dictionary = ServerStatus.parse_response(_udp.get_packet())
		if parsed.is_empty():
			continue
		var waiting: Dictionary = _pending.get(parsed.nonce.hex_encode(), {})
		if waiting.is_empty():
			continue
		_pending.erase(parsed.nonce.hex_encode())
		result.emit(waiting.key, {"address": waiting.address, "port": waiting.port, "online": true,
			"ping_ms": Time.get_ticks_msec() - int(waiting.sent), "info": parsed.info})
	var now := Time.get_ticks_msec()
	for nonce: String in _pending.keys():
		var waiting: Dictionary = _pending[nonce]
		if now - int(waiting.sent) > TIMEOUT * 1000:
			_pending.erase(nonce)
			result.emit(waiting.key, {"address": waiting.address, "port": waiting.port, "online": false, "error": "no answer"})


func busy() -> bool:
	return not _pending.is_empty()


func close() -> void:
	_udp.close()
	_pending.clear()
