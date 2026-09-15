extends RefCounted
## Answers status queries (engine/shared/server_status.gd) so menus can show this server's name,
## message, game, player count and ping. Off with --query-port=0. Rate limited per address.

const ServerStatus = preload("res://engine/shared/server_status.gd")
const Protocol = preload("res://engine/shared/protocol.gd")

const PER_ADDRESS_PER_SECOND := 8
const MAX_PACKETS_PER_UPDATE := 64

var port := 0
## The server's identity key (signs proofs for the hub); set by the server when it starts listening.
var key: CryptoKey
var _server
var _udp: PacketPeerUDP
var _counts := {}  # ip -> answers this second
var _window := 0


func _init(game_server) -> void:
	_server = game_server


func start(listen_port: int) -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	var err := _udp.bind(listen_port)
	if err != OK:
		_server.dev_log.add("warn", "server", "Status queries could not listen on UDP port %d (%s)" % [listen_port, error_string(err)])
		_udp = null
		return err
	port = listen_port
	return OK


func stop() -> void:
	if _udp != null:
		_udp.close()
		_udp = null
	port = 0


func running() -> bool:
	return _udp != null


func info() -> Dictionary:
	return {"name": _server.server_info.name, "motd": _server.server_info.motd, "game": _server.server_info.get("game_id", ""),
		"game_name": _server.server_info.game, "players": _server.players.size(), "max_players": _server.max_players,
		"protocol": Protocol.VERSION, "version": Protocol.GAME_VERSION, "port": _server.port, "code": _server.hub.code if _server.hub != null else ""}


func update() -> void:
	if _udp == null:
		return
	var second := int(Time.get_ticks_msec() / 1000.0)
	if second != _window:
		_window = second
		_counts.clear()
	var handled := 0
	while _udp.get_available_packet_count() > 0 and handled < MAX_PACKETS_PER_UPDATE:
		handled += 1
		var packet := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var from_port := _udp.get_packet_port()
		var request := ServerStatus.parse_request(packet)
		if request.is_empty():
			continue
		var count := int(_counts.get(ip, 0))
		if count >= PER_ADDRESS_PER_SECOND:
			continue
		_counts[ip] = count + 1
		_udp.set_dest_address(ip, from_port)
		var answer := info()
		if request.proof and key != null:
			answer.proof = Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256,
				_sha256(ServerStatus.proof_message(request.nonce)), key))
		_udp.put_packet(ServerStatus.make_response(request.nonce, answer))


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish()
