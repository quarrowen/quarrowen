extends Node
## Lists this server on a hub (services/hub): every HEARTBEAT seconds it posts the server's name,
## message, game and player count, signed with the server's identity key; the hub checks the address
## with a status query and answers with a short invite code (`code`), which status replies and the
## in-game invite dialog then show. On shutdown it asks the hub to drop the listing.
##
## Off unless configured: --hub=https://hub.example.org [--public-address=play.example.org] [--tags=pvp,modded]

const Protocol = preload("res://engine/shared/protocol.gd")

const HEARTBEAT := 30.0
const RETRY := 60.0

var url := ""
var public_address := ""
var tags: PackedStringArray = []
## The hub's invite code for this server ("VC-ABC-123"), once listed.
var code := ""
## "" while fine, else why the last announce failed (shown to admins and in the log once per change).
var problem := ""

var _server
var _key: CryptoKey
var _http: HTTPRequest
var _timer := 0.0
var _busy := false


func _init(game_server) -> void:
	_server = game_server
	name = "HubAnnouncer"


func start(hub_url: String, key: CryptoKey, address := "", server_tags := PackedStringArray()) -> void:
	url = hub_url.strip_edges().trim_suffix("/")
	public_address = address
	tags = server_tags
	_key = key
	if url.is_empty() or key == null:
		return
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_announced)
	add_child(_http)
	_timer = HEARTBEAT  # announce on the first update


func running() -> bool:
	return _http != null


func _process(delta: float) -> void:
	if _http == null or _busy:
		return
	_timer += delta
	if _timer >= (HEARTBEAT if problem.is_empty() else RETRY):
		_timer = 0.0
		announce()


func announce() -> void:
	var info: Dictionary = _server.status_query.info()
	var body := {"key": _key.save_to_string(true), "time": int(Time.get_unix_time_from_system()), "port": _server.port,
		"query_port": _server.status_query.port, "address": public_address, "name": info.name, "motd": info.motd, "game": info.game,
		"game_name": info.game_name, "players": info.players, "max_players": info.max_players, "protocol": info.protocol,
		"version": info.version, "tags": Array(tags)}
	_send("/v1/servers/announce", body)


## Asks the hub to drop the listing (best effort, on shutdown: a blocking request with a short timeout).
func leave() -> void:
	if _http == null:
		return
	var body := JSON.stringify({"key": _key.save_to_string(true), "time": int(Time.get_unix_time_from_system())})
	var client := HTTPClient.new()
	var parts := _split_url(url)
	if client.connect_to_host(parts.host, parts.port, TLSOptions.client() if parts.tls else null) != OK:
		return
	var deadline := Time.get_ticks_msec() + 2000
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return
	client.request(HTTPClient.METHOD_POST, parts.path + "/v1/servers/leave", _headers(body), body)
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(10)
	client.close()


func _send(path: String, data: Dictionary) -> void:
	var body := JSON.stringify(data)
	_busy = true
	if _http.request(url + path, _headers(body), HTTPClient.METHOD_POST, body) != OK:
		_busy = false
		_set_problem("cannot reach the hub at %s" % url)


func _headers(body: String) -> PackedStringArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body.to_utf8_buffer())
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), _key)
	return PackedStringArray(["Content-Type: application/json", "X-Voxel-Signature: " + Marshalls.raw_to_base64(signature),
		"User-Agent: VoxelCraft/%s" % Protocol.GAME_VERSION])


func _on_announced(result: int, status: int, _headers_in: PackedStringArray, response: PackedByteArray) -> void:
	_busy = false
	var parsed = JSON.parse_string(response.get_string_from_utf8()) if response.size() < 65536 else null
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_problem("cannot reach the hub at %s" % url)
	elif status != 200 or not (parsed is Dictionary):
		_set_problem(str(parsed.get("error", "hub error %d" % status)) if parsed is Dictionary else "hub error %d" % status)
	else:
		var was_listed := not code.is_empty()
		code = str(parsed.get("code", "")).left(16)
		_set_problem("")
		if not was_listed:
			_server.dev_log.add("info", "server", "Listed on the hub %s as %s" % [url, code])


func _set_problem(text: String) -> void:
	if text != problem and not text.is_empty():
		_server.dev_log.add("warn", "server", "Hub listing: %s" % text)
	problem = text


static func _split_url(address: String) -> Dictionary:
	var tls := address.begins_with("https://")
	var rest := address.trim_prefix("https://").trim_prefix("http://")
	var host_port := rest.get_slice("/", 0)
	var path := rest.substr(host_port.length()).trim_suffix("/")
	var host := host_port.get_slice(":", 0)
	var port := int(host_port.get_slice(":", 1)) if host_port.contains(":") else (443 if tls else 80)
	return {"tls": tls, "host": host, "port": port, "path": path}
