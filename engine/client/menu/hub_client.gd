extends Node
## Talks to a hub (services/hub) for the menu: the server list, invite codes and news. The hub's
## address is the "network/hub_url" setting (or QW_HUB). Each call emits its signal once, with
## `error` set ("" on success).

signal servers_received(servers: Array, total: int, error: String)
signal code_resolved(entry: Dictionary, error: String)
signal news_received(items: Array, error: String)

const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const NetAccess = preload("res://engine/shared/net_access.gd")

const MAX_RESPONSE := 512 * 1024


static func hub_url() -> String:
	var override := OS.get_environment("QW_HUB")
	var url: String = override if not override.is_empty() else str(ClientSettings.shared().get_value("network/hub_url"))
	return url.strip_edges().trim_suffix("/")


static func configured() -> bool:
	return hub_url().begins_with("http://") or hub_url().begins_with("https://")


func list_servers(query := "", game := "") -> void:
	var params := PackedStringArray(["limit=200"])
	if not query.is_empty():
		params.append("q=" + query.uri_encode())
	if not game.is_empty():
		params.append("game=" + game.uri_encode())
	_request_json("/v1/servers?" + "&".join(params), func(data, error):
		if not error.is_empty() or not (data is Dictionary) or not (data.get("servers") is Array):
			servers_received.emit([], 0, error if not error.is_empty() else "the hub sent an unexpected answer")
			return
		servers_received.emit(data.servers.filter(func(s): return s is Dictionary).map(_clean_server), int(data.get("total", 0)), ""))


func resolve_code(code: String) -> void:
	var clean := code.to_upper().replace("QW-", "").replace("-", "").replace(" ", "")
	_request_json("/v1/codes/" + clean.uri_encode(), func(data, error):
		if not error.is_empty() or not (data is Dictionary) or not data.has("address"):
			code_resolved.emit({}, error if not error.is_empty() else "the hub sent an unexpected answer")
			return
		code_resolved.emit({"address": str(data.address).left(253), "port": clampi(int(data.get("port", 0)), 1, 65535),
			"name": str(data.get("name", "")).left(64), "online": bool(data.get("online", false))}, ""))


func fetch_news() -> void:
	_request_json("/v1/news", func(data, error):
		if not error.is_empty() or not (data is Array):
			news_received.emit([], error if not error.is_empty() else "no news")
			return
		news_received.emit(data.filter(func(n): return n is Dictionary).slice(0, 8).map(func(n):
			return {"title": str(n.get("title", "")).left(80), "body": str(n.get("body", "")).left(400), "url": str(n.get("url", "")).left(300)}), ""))


static func _clean_server(s: Dictionary) -> Dictionary:
	return {"name": str(s.get("name", "")).left(64), "motd": str(s.get("motd", "")).left(256), "address": str(s.get("address", "")).left(253),
		"port": clampi(int(s.get("port", 0)), 1, 65535), "game": str(s.get("game", "")).left(64), "game_name": str(s.get("game_name", "")).left(64),
		"players": clampi(int(s.get("players", 0)), 0, 100000), "max_players": clampi(int(s.get("max_players", 0)), 0, 100000),
		"protocol": int(s.get("protocol", 0)), "version": str(s.get("version", "")).left(32), "code": str(s.get("code", "")).left(16),
		"tags": (s.get("tags", []) as Array).slice(0, 8).map(func(t): return str(t).left(24)) if s.get("tags") is Array else [],
		"compatible": int(s.get("protocol", 0)) == Protocol.VERSION}


func _request_json(path: String, done: Callable) -> void:
	if not configured():
		done.call(null, "no hub is set (Settings → Network)")
		return
	if not NetAccess.allowed(hub_url()):
		done.call(null, "cannot reach the hub")
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	http.body_size_limit = MAX_RESPONSE
	add_child(http)
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			done.call(null, "cannot reach the hub")
			return
		var json := JSON.new()
		var parsed = json.data if json.parse(body.get_string_from_utf8()) == OK else null
		if status != 200:
			done.call(null, str(parsed.get("error", "hub error %d" % status)) if parsed is Dictionary else "hub error %d" % status)
			return
		done.call(parsed, ""))
	if http.request(hub_url() + path, PackedStringArray(["User-Agent: Quarrowen/%s" % Protocol.GAME_VERSION])) != OK:
		http.queue_free()
		done.call(null, "cannot reach the hub")
