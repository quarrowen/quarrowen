extends RefCounted
## The dev dashboard: a tiny HTTP server on the game server that serves engine/server/dev_web/index.html
## and a JSON API over the same data as the F8 overlay (logs, errors, event trace, profiler, inspector),
## for a browser next to the game or on a headless server.
##
## Off unless configured: --dev-web=24580 (or on by default with --dev). It binds 127.0.0.1 unless
## --dev-web-host says otherwise, and every request needs the token printed at start (also shown to
## admins by /devweb).
##
## Two transports answer the same routes: with the native extension, NativeHttpServer
## (native/src/http.rs) parses HTTP on its own threads (keep-alive, many clients) and adds
## /api/stream, a Server-Sent Events stream the game pushes the state to every PUSH_INTERVAL seconds,
## so the page need not poll; without it, a small GDScript TCPServer (one request per connection) and
## the page polls /api/state.
##
## API (all GET, ?token=...):
##   /api/state?logs_after=N&events_after=N&events=0|1&filter=...   everything new since the last poll
##   /api/inspect?player=<peer>  |  &look=1 (what that player looks at)  |  entity=<id>  |  x=&y=&z=
##   /api/clear_errors[?source=mod]
##   /api/reload?mod=<id> | mod=all | mod=full
##   /api/ugc?filter=pending|reported|approved|rejected|removed|all&text=   creations for review
##   /api/ugc_action?action=set_status|trust|ban|clear_reports&id=&status=&reason=&player_id=&on=
##   /api/ugc_file?id=   a creation's file (skin PNG, accessory JSON, model GLB)
##   /api/stream   (native only) events: `state` (the /api/state answer with only what is new since the
##                 last push, using the dashboard's last /api/state parameters)
## A dashboard that polls within VIEWER_TIMEOUT seconds counts as a dev tools viewer (so events are traced).

const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const PAGE := "res://engine/server/dev_web/index.html"
const VIEWER_ID := -1000
const VIEWER_TIMEOUT := 5.0
const MAX_REQUEST := 16384
const PUSH_INTERVAL := 0.5
const Native = preload("res://engine/shared/native.gd")

var token := ""
var port := 0
var host := "127.0.0.1"
var _server
var _tcp: TCPServer
var _clients: Array[Dictionary] = []  # {peer: StreamPeerTCP, data: PackedByteArray, since}
var _last_poll := -100.0
var _page := ""
var _native: Object  # NativeHttpServer when the extension is loaded
var _push_timer := 0.0
var _push_logs_after := 0
var _push_events_after := 0


func _init(game_server) -> void:
	_server = game_server


## `keep_token`: reuse a token (a full reload keeps open dashboards working).
func start(listen_port: int, bind_host := "127.0.0.1", keep_token := "") -> Error:
	port = listen_port
	host = bind_host
	token = keep_token if not keep_token.is_empty() else Crypto.new().generate_random_bytes(12).hex_encode()
	_native = Native.create(&"NativeHttpServer")
	if _native != null:
		var problem: String = _native.listen(host, port, token)
		if not problem.is_empty():
			_server.dev_log.add("error", "server", "Dev dashboard could not listen on %s:%d (%s)" % [host, port, problem])
			_native = null
			return ERR_CANT_CREATE
	else:
		_tcp = TCPServer.new()
		var err := _tcp.listen(port, host)
		if err != OK:
			_server.dev_log.add("error", "server", "Dev dashboard could not listen on %s:%d (%s)" % [host, port, error_string(err)])
			_tcp = null
			return err
	_page = FileAccess.get_file_as_string(PAGE)
	# Deliberately without the token. The URL carries a live credential that grants the logs, player
	# positions, reloads and the ban controls, and the log is the one place it must not be: it is read by
	# anyone with `docker logs`, and it used to be copied into every backup archive as well. Admins get
	# the full URL privately with /devweb.
	_server.dev_log.add("info", "server", "Dev dashboard on http://%s:%d/ (use /devweb for the link with its token)"
		% ["127.0.0.1" if host == "0.0.0.0" or host == "*" else host, port])
	return OK


func url() -> String:
	return "http://%s:%d/?token=%s" % ["127.0.0.1" if host == "0.0.0.0" or host == "*" else host, port, token]


func running() -> bool:
	return _tcp != null or _native != null


## True when the native server (with live push) is in use.
func streaming() -> bool:
	return _native != null


func stop() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	if _native != null:
		_native.stop()
		_native = null
	_server.dev_tools.unsubscribe(VIEWER_ID)


func update(delta := 0.0) -> void:
	if _native != null:
		_update_native(delta)
		return
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		_clients.append({"peer": peer, "data": PackedByteArray(), "since": Time.get_ticks_msec()})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		var status := peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - c.since > 5000:
			_clients.erase(c)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			if chunk[0] == OK:
				c.data.append_array(chunk[1])
		var text: String = c.data.get_string_from_utf8()
		if c.data.size() > MAX_REQUEST:
			_respond(peer, 413, "text/plain", "request too large")
			_clients.erase(c)
		elif text.contains("\r\n\r\n"):
			var parts := text.get_slice("\r\n", 0).split(" ")
			var target := parts[1] if parts.size() > 1 else ""
			var answer := _route(parts[0], target.get_slice("?", 0), target.get_slice("?", 1) if target.contains("?") else "")
			_respond_raw(peer, answer[0], answer[1], answer[2])
			_clients.erase(c)
	_expire_viewer()


func _update_native(delta: float) -> void:
	for request in _native.poll():
		var answer := _route(request.method, request.path, request.query)
		_native.respond(request.id, answer[0], answer[1], answer[2])
	_push_timer += delta
	if _push_timer < PUSH_INTERVAL:
		return
	_push_timer = 0.0
	if _native.stream_count() > 0 and _server.dev_tools.viewers.has(VIEWER_ID):
		_last_poll = Time.get_unix_time_from_system()  # an open stream keeps the dashboard a viewer
		var s := _state({"logs_after": str(_push_logs_after), "events_after": str(_push_events_after)}, false)
		_native.push("state", JSON.stringify(s))
	# Advance the push cursors even without streams, so a page that polls once when its stream
	# opens and then follows pushes misses nothing.
	if not _server.dev_log.entries.is_empty():
		_push_logs_after = _server.dev_log.entries[-1].id
	if not _server.dev_tools.trace.is_empty():
		_push_events_after = _server.dev_tools.trace[-1].id
	_expire_viewer()


func _expire_viewer() -> void:
	if _last_poll > 0.0 and Time.get_unix_time_from_system() - _last_poll > VIEWER_TIMEOUT:
		_last_poll = -100.0
		_server.dev_tools.unsubscribe(VIEWER_ID)


## [status, content type, body bytes] for a request, whichever server received it.
func _route(method: String, path: String, query_text: String) -> Array:
	if method != "GET":
		return _text(405, "text/plain", "only GET")
	var query := _query(query_text)
	if path == "/" or path == "/index.html":
		# The page itself asks for the token in the URL; without it, say so.
		if query.get("token", "") != token:
			return _text(403, "text/html", "<h1>Dev dashboard</h1><p>Open the URL with the token printed by the server (or run /devweb in game).</p>")
		return _text(200, "text/html; charset=utf-8", _page)
	if not path.begins_with("/api/"):
		return _text(404, "text/plain", "not found")
	if query.get("token", "") != token:
		return _text(403, "application/json", JSON.stringify({"error": "bad token"}))
	var result
	match path:
		"/api/state": result = _state(query)
		"/api/inspect": result = _inspect(query)
		"/api/reload":
			var what := str(query.get("mod", ""))
			if what == "full":
				_server.request_full_reload.call_deferred()
				result = {"ok": true, "full": true}
			elif what == "all":
				result = {"results": _server.mod_reload.reload_all()}
			else:
				result = {"results": [_server.mod_reload.reload(what)]}
		"/api/ugc":
			result = {"items": _server.ugc.review_list(str(query.get("filter", "pending")), str(query.get("text", ""))).slice(0, 200), "policy": _server.ugc.policy}
		"/api/ugc_action":
			var ugc = _server.ugc
			match str(query.get("action", "")):
				"set_status": ugc.set_status(str(query.get("id", "")), str(query.get("status", "")), str(query.get("reason", "")).left(200), "dashboard")
				"trust": ugc.set_trusted(str(query.get("player_id", "")), query.get("on", "1") == "1")
				"ban": ugc.set_banned(str(query.get("player_id", "")), query.get("on", "1") == "1", str(query.get("reason", "")).left(200), "dashboard")
				"clear_reports": ugc.clear_reports(str(query.get("id", "")))
			result = {"ok": true}
		"/api/ugc_file":
			var id := str(query.get("id", ""))
			var bytes: PackedByteArray = _server.ugc.payload(id)
			if bytes.is_empty():
				return _text(404, "application/json", JSON.stringify({"error": "no such creation"}))
			var kind: String = _server.ugc.store[id].manifest.kind
			return [200, {"skin": "image/png", "accessory": "application/json", "model": "model/gltf-binary"}.get(kind, "application/octet-stream"), bytes]
		"/api/clear_errors":
			_server.dev_log.clear_errors(query.get("source", ""))
			result = {"ok": true}
		_:
			return _text(404, "application/json", JSON.stringify({"error": "unknown endpoint"}))
	return _text(200, "application/json", JSON.stringify(result))


## `configure`: a poll sets the dashboard viewer's channels and filter from its query; a push reuses them.
func _state(query: Dictionary, configure := true) -> Dictionary:
	var tools = _server.dev_tools
	var v: Dictionary = tools.viewers.get(VIEWER_ID, {"channels": {}, "inspect": {}, "log_after": 0, "trace_after": 0, "web": true})
	if configure:
		_last_poll = Time.get_unix_time_from_system()
		# The dashboard is a viewer without a player: tracing follows its filter.
		v.channels = {"perf": true}
		if query.get("events", "0") == "1":
			v.channels["events"] = true
		v.trace_filter = str(query.get("filter", "")).left(200)
		tools.viewers[VIEWER_ID] = v
		tools.set_tracing()
	var channels: Array = v.channels.keys()
	var logs_after := int(query.get("logs_after", "0"))
	var events_after := int(query.get("events_after", "0"))
	var players := []
	for p in _server.players.values():
		players.append({"peer": p.peer_id, "name": p.name, "position": tools.describe(p.state.position), "admin": _server.is_admin(p),
			"creative": p.inventory.creative, "health": snappedf(p.health, 0.1)})
	return {
		"server": {"name": _server.server_info.name, "game": _server.server_info.game, "mods": _server.server_info.mods,
			"tick": _server.tick, "time_of_day": snappedf(_server.get_time_of_day(), 0.001), "entities": _server.entities.entities.size(),
			"chunks": _server.world.chunks.size(), "dev_mode": _server.dev_mode, "watching": _server.mod_reload.watching,
			"stream": _native != null, "ugc_revision": _server.ugc.revision},
		"mods": _server.mod_order.map(func(m): return {"id": m.id, "name": m.name, "version": m.version, "language": "JavaScript" if str(m.main).ends_with(".js") else "GDScript"}),
		"players": players,
		"logs": _server.dev_log.entries.filter(func(e): return e.id > logs_after).slice(-500),
		"errors": _server.dev_log.sorted_errors().slice(0, 100),
		"events": tools.trace.filter(func(t): return t.id > events_after).slice(-200) if channels.has("events") else [],
		"perf": tools.perf().slice(0, 120),
	}


func _inspect(query: Dictionary) -> Dictionary:
	var tools = _server.dev_tools
	if query.has("entity"):
		return tools.inspect({"entity": int(query.entity)})
	if query.has("x") and query.has("y") and query.has("z"):
		return tools.inspect({"pos": Vector3i(int(query.x), int(query.y), int(query.z))})
	if query.has("player"):
		var p = _server.players.get(int(query.player))
		if p == null:
			return {"title": "Player gone"}
		if query.get("look", "0") != "1":
			return tools.inspect({"player": p.peer_id})
		return tools.inspect(_looked_at(p))
	return {"title": "Nothing to inspect"}


## What a player is looking at, up to 64 blocks: the nearest mob or item on the line, else the block.
func _looked_at(p) -> Dictionary:
	var eye: Vector3 = p.get_eye_position()
	var dir := PlayerPhysics.look_direction(p.yaw, p.pitch)
	var ray := VoxelRaycast.cast(_server.realm_of(p).world, _server.registry.solid_lut, eye, dir, 64.0)
	var best: float = eye.distance_to(Vector3(ray.position) + Vector3(0.5, 0.5, 0.5)) if ray.hit else 64.0
	var target := {"pos": ray.position} if ray.hit else {"player": p.peer_id}
	for e in _server.entities.in_radius(eye, best):
		var box: AABB = e.aabb()
		var hit = box.intersects_ray(eye, dir)
		if hit != null and eye.distance_to(hit) < best:
			best = eye.distance_to(hit)
			target = {"entity": e.id}
	return target


static func _query(text: String) -> Dictionary:
	var out := {}
	for pair in text.split("&", false):
		var kv := pair.split("=", true, 1)
		out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out


static func _text(code: int, content_type: String, body: String) -> Array:
	return [code, content_type, body.to_utf8_buffer()]


static func _respond(peer: StreamPeerTCP, code: int, content_type: String, body: String) -> void:
	_respond_raw(peer, code, content_type, body.to_utf8_buffer())


static func _respond_raw(peer: StreamPeerTCP, code: int, content_type: String, bytes: PackedByteArray) -> void:
	var reason: String = {200: "OK", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n" % [
		code, reason, content_type, bytes.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(bytes)
	peer.disconnect_from_host()
