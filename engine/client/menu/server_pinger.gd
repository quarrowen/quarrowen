extends RefCounted
## Asks several servers for their status at once (engine/shared/server_status.gd). Call `update()` every
## frame; `result` carries {address, port, online, ping_ms, info} or {address, port, online: false, error}.
## Addresses may be host names (resolved when pinged).

signal result(key: String, entry: Dictionary)
## A server answered a LAN discovery broadcast: {address, port, online, ping_ms, info}.
signal lan_found(key: String, entry: Dictionary)

const ServerStatus = preload("res://engine/shared/server_status.gd")
const TIMEOUT := 2.0
## LAN discovery asks the status ports of the usual game ports (24565 and the next ones).
const LAN_GAME_PORTS := [24565, 24566, 24567, 24568, 24569, 24570, 24571, 24572, 24573, 24574]

var _udp := PacketPeerUDP.new()
var _pending := {}  # nonce hex -> {key, address, port, sent}
var _lan := {}  # nonce hex -> sent (a broadcast gets any number of answers)
var _lan_seen := {}  # key -> address reported
var _local_addresses := IP.get_local_addresses()


func _init() -> void:
	_udp.bind(0)
	_udp.set_broadcast_enabled(true)


## Finds servers on the local network (a broadcast) and on this computer. `extra_ports`: more game
## ports to try (e.g. the one this player hosts on).
func discover_lan(extra_ports := []) -> void:
	var nonce := Crypto.new().generate_random_bytes(ServerStatus.NONCE_SIZE)
	_lan = {nonce.hex_encode(): Time.get_ticks_msec()}
	_lan_seen.clear()
	var ports := LAN_GAME_PORTS.duplicate()
	for p in extra_ports:
		if not ports.has(int(p)):
			ports.append(int(p))
	for game_port in ports:
		for target in ["255.255.255.255", "127.0.0.1"]:
			_udp.set_dest_address(target, ServerStatus.query_port(game_port))
			_udp.put_packet(ServerStatus.make_request(nonce))


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
		var packet := _udp.get_packet()
		var from := _udp.get_packet_ip()
		var parsed: Dictionary = ServerStatus.parse_response(packet)
		if parsed.is_empty():
			continue
		if _lan.has(parsed.nonce.hex_encode()) and parsed.info.port > 0:
			# A server on this computer answers both on loopback and on its network address: report it once,
			# with the network address when there is one (friends can use that).
			var local := from.begins_with("127.") or from == "::1" or _local_addresses.has(from)
			var key := ("this:%d" if local else from + ":%d") % parsed.info.port
			var address: String = from if not (from.begins_with("127.") or from == "::1") else _lan_seen.get(key, "127.0.0.1")
			_lan_seen[key] = address
			lan_found.emit(key, {"address": address, "port": parsed.info.port, "online": true,
				"ping_ms": Time.get_ticks_msec() - int(_lan[parsed.nonce.hex_encode()]), "info": parsed.info})
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
