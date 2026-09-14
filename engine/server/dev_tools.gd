extends RefCounted
## Developer tools behind the dev overlay (and the web dashboard): a per-mod profiler, a live event
## tracer, an inspector for blocks, entities and players, and debug drawing. Available to admins, or to
## everyone when the server runs with --dev.
##
## - Profiler: event handlers, scheduled tasks, commands, block ticks and mob behaviours are timed per
##   owner (mod id or "engine") and category ("event:block_broken", "task", "command:/x", ...). Totals
##   roll into one-second windows; `perf()` reports the last WINDOWS seconds.
## - Tracer: while someone traces, each emitted event is recorded with its payload (players, entities,
##   blocks and items shown by name), each handler's owner and time, and which handler cancelled it.
## - Inspector: `inspect(player, target)` describes a block {pos}, an entity {entity} or a player {player}.
## - Debug draw: `draw(owner, shape)` queues boxes, lines, labels and paths that expire; watchers get them
##   each tick. `ai_debug` draws mob paths, targets and homes near watchers.
## Viewers subscribe with a set of channels: logs, errors, perf, events, draw, ai, inspect.

const WINDOWS := 10
const MAX_TRACE := 300
const MAX_SHAPES := 2000
const SHAPES := ["box", "line", "text", "path", "sphere"]

var _server
## peer id -> {channels: {name: true}, inspect: {...target}, trace_filter: String, log_after: int}
var viewers := {}
var tracing := false
var trace: Array[Dictionary] = []
var _trace_seq := 0
var _window := {}  # owner -> category -> [calls, usec, max]
var _history: Array[Dictionary] = []  # finished windows
var _window_started := 0.0
var _shapes: Array[Dictionary] = []  # queued since the last flush
var _send_timer := 0.0
var _perf_timer := 0.0
var _ai_timer := 0.0


func _init(game_server) -> void:
	_server = game_server


func allowed(p) -> bool:
	return p != null and (_server.dev_mode or _server.is_admin(p))


# --- Profiler ---------------------------------------------------------------------------------------

func record(owner: String, category: String, usec: int) -> void:
	var by_owner: Dictionary = _window.get(owner, {})
	if by_owner.is_empty():
		_window[owner] = by_owner
	var c: Array = by_owner.get(category, [])
	if c.is_empty():
		c = [0, 0, 0]
		by_owner[category] = c
	c[0] += 1
	c[1] += usec
	if usec > c[2]:
		c[2] = usec


## Calls `callable` with `args`, timing it for `owner`.
func timed(owner: String, category: String, callable: Callable, args := []):
	var t := Time.get_ticks_usec()
	var result = callable.callv(args)
	record(owner, category, Time.get_ticks_usec() - t)
	return result


func _roll_window() -> void:
	_history.append(_window)
	if _history.size() > WINDOWS:
		_history.pop_front()
	_window = {}


## [{owner, category, calls, ms_per_s, avg_ms, max_ms}] over the last WINDOWS seconds, slowest first,
## plus owner totals ({owner, category: "total"}).
func perf() -> Array:
	var sums := {}
	for w in _history:
		for owner in w:
			for category in w[owner]:
				var key := "%s|%s" % [owner, category]
				var c: Array = w[owner][category]
				var s: Array = sums.get(key, [owner, category, 0, 0, 0])
				s[2] += c[0]
				s[3] += c[1]
				s[4] = maxi(s[4], c[2])
				sums[key] = s
	var seconds := maxf(1.0, _history.size())
	var rows := []
	var totals := {}
	for s in sums.values():
		rows.append({"owner": s[0], "category": s[1], "calls": s[2], "ms_per_s": s[3] / 1000.0 / seconds,
			"avg_ms": s[3] / 1000.0 / maxf(1.0, s[2]), "max_ms": s[4] / 1000.0})
		var t: Dictionary = totals.get(s[0], {"owner": s[0], "category": "total", "calls": 0, "ms_per_s": 0.0, "avg_ms": 0.0, "max_ms": 0.0})
		t.calls += s[2]
		t.ms_per_s += s[3] / 1000.0 / seconds
		t.max_ms = maxf(t.max_ms, s[4] / 1000.0)
		totals[s[0]] = t
	rows.append_array(totals.values())
	rows.sort_custom(func(a, b): return a.ms_per_s > b.ms_per_s)
	return rows


# --- Event tracer -----------------------------------------------------------------------------------

## Emits `payload` to `handlers` ([priority, callable, owner]), timing each handler and recording the
## event when tracing. Returns the payload.
func dispatch(event: String, handlers: Array, payload: Dictionary) -> Dictionary:
	if not tracing or not _trace_wanted(event):
		for entry in handlers:
			var handler: Callable = entry[1]
			if handler.is_valid():
				var t := Time.get_ticks_usec()
				handler.call(payload)
				record(entry[2], "event:" + event, Time.get_ticks_usec() - t)
		return payload
	var before: Dictionary = describe(payload)
	var ran := []
	var total := 0
	for entry in handlers:
		var handler: Callable = entry[1]
		if not handler.is_valid():
			continue
		var was_cancelled = payload.get("cancelled")
		var t := Time.get_ticks_usec()
		handler.call(payload)
		var usec := Time.get_ticks_usec() - t
		total += usec
		record(entry[2], "event:" + event, usec)
		var step := {"owner": entry[2], "ms": usec / 1000.0}
		if payload.get("cancelled") != was_cancelled:
			step.cancelled = payload.get("cancelled")
		ran.append(step)
	_trace_seq += 1
	var rec := {"id": _trace_seq, "time": Time.get_unix_time_from_system(), "event": event, "payload": before, "handlers": ran,
		"ms": total / 1000.0}
	if payload.has("cancelled"):
		rec.cancelled = bool(payload.cancelled)
	var after: Dictionary = describe(payload)
	if after != before:
		rec.changed = after
	trace.append(rec)
	if trace.size() > MAX_TRACE:
		trace.pop_front()
	return payload


func set_tracing() -> void:
	tracing = viewers.values().any(func(v): return v.channels.has("events"))


## Tracing viewers' filters: event names with "*" wildcards, comma separated ("" = everything but tick).
func _trace_wanted(event: String) -> bool:
	for v in viewers.values():
		if not v.channels.has("events"):
			continue
		var filter: String = v.get("trace_filter", "")
		if filter.is_empty():
			if event != "tick":
				return true
			continue
		for f in filter.split(",", false):
			if event.match(f.strip_edges()):
				return true
	return false


func set_trace_filter(p, filter: String) -> void:
	if viewers.has(p.peer_id):
		viewers[p.peer_id].trace_filter = filter.left(200)


## A JSON-friendly copy of a value: players, entities, vectors and block/item ids become readable.
func describe(value, key := "", depth := 0):
	if depth > 4:
		return "…"
	if value is Dictionary:
		var out := {}
		var n := 0
		for k in value:
			n += 1
			if n > 40:
				out["…"] = "%d more" % (value.size() - 40)
				break
			out[str(k)] = describe(value[k], str(k), depth + 1)
		return out
	if value is Array or value is PackedStringArray or value is PackedInt32Array:
		var out := []
		for i in mini(value.size(), 40):
			out.append(describe(value[i], key, depth + 1))
		if value.size() > 40:
			out.append("… %d more" % (value.size() - 40))
		return out
	if value is Vector3 or value is Vector3i:
		return "(%s, %s, %s)" % [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]
	if value is Object:
		if value.get("peer_id") != null and value.get("name") != null:
			return "player %s" % value.name
		if value.get("def") is Dictionary and value.get("id") != null:
			return "%s #%d" % [value.def.name, value.id]
		return str(value)
	if value is int and key in ["block"] and _server.registry.is_valid(value):
		return "%s (%d)" % [_server.registry.defs[value].name, value]
	if value is int and key in ["item", "old_item"] and value > 0:
		return "%s (%d)" % [_server.items.name_of(value), value]
	if value is float:
		return snappedf(value, 0.001)
	return value


# --- Inspector --------------------------------------------------------------------------------------

## target: {pos: Vector3i} | {entity: id} | {player: peer id}
func inspect(target: Dictionary) -> Dictionary:
	if target.has("pos"):
		return _inspect_block(target.pos)
	if target.has("entity"):
		var e = _server.entities.entities.get(int(target.entity))
		return _inspect_entity(e) if e != null else {"title": "Entity gone"}
	if target.has("player"):
		var p = _server.players.get(int(target.player))
		return _inspect_player(p) if p != null else {"title": "Player gone"}
	return {"title": "Nothing to inspect"}


func _inspect_block(pos: Vector3i) -> Dictionary:
	var id: int = _server.world.get_block_v(pos)
	if not _server.registry.is_valid(id):
		return {"title": "Unloaded (%d, %d, %d)" % [pos.x, pos.y, pos.z]}
	var def: Dictionary = _server.registry.defs[id]
	var fields := {"name": def.name, "id": id, "position": describe(pos), "state": _server.get_block_state(pos),
		"light": _server.block_ticks.light_at(pos + Vector3i.UP, 1.0), "data": describe(_server.get_block_data(pos))}
	if _server.biome_generator != null:
		fields.biome = _server.biome_generator.biome_at(pos.x, pos.z)
	if _server.block_ticks.handlers.has(id):
		fields.ticks = "every ~%ds" % int(_server.block_ticks.handlers[id].interval)
	var server_def := {}
	for k in def:
		if not k in ["name", "id"] and not (def[k] is Array and def[k].is_empty()):
			server_def[k] = def[k]
	fields.definition = describe(server_def)
	if not str(def.get("station", "")).is_empty():
		fields.station = describe(_server.stations.evaluate(pos))
	return {"title": str(def.get("display_name", def.name)), "kind": "block", "fields": fields}


func _inspect_entity(e) -> Dictionary:
	var fields := {"type": e.def.name, "id": e.id, "position": describe(e.body.position), "health": "%s / %s" % [snappedf(e.health, 0.1), e.max_health],
		"velocity": describe(e.body.velocity), "on_ground": e.body.on_ground, "age": snappedf(e.age, 0.1), "data": describe(e.data)}
	if e.def.kind == "item":
		fields.item = "%s × %d" % [_server.items.name_of(e.item_id), e.item_count]
	if e.brain != null:
		var b = e.brain
		fields.ai = {"behavior": b.behavior, "target": describe(b.target), "threat": describe(b.threat.duplicate()),
			"memory": b.memory.size(), "home": describe(b.home) if b.home != Vector3.INF else "none",
			"path": "%d nodes (%d left)" % [b.path.size(), maxi(0, b.path.size() - b.path_index)],
			"goal": describe(b.move_goal) if b.move_goal != Vector3.INF else "none", "attack": str(b.attack.get("name", "")),
			"preset": str(b.config.get("preset", "")), "aggression": b.config.get("aggression"), "intelligence": b.config.get("intelligence")}
	return {"title": str(e.def.get("display_name", e.def.name)), "kind": "entity", "fields": fields}


func _inspect_player(p) -> Dictionary:
	var fields := {"name": p.name, "player_id": p.player_id, "position": describe(p.state.position), "health": "%s / %s" % [snappedf(p.health, 0.1), p.max_health],
		"hunger": "%s (saturation %s)" % [snappedf(p.hunger, 0.1), snappedf(p.saturation, 0.1)], "creative": p.inventory.creative,
		"admin": _server.is_admin(p), "team": p.team, "held": _server.items.name_of(p.inventory.selected_item()) if p.inventory.selected_item() > 0 else "nothing",
		"stats": describe(p.get_stats()), "modifiers": describe(p.modifiers), "data": describe(p.data),
		"tutorial": describe(_server.tutorials.view(p)), "known_recipes": p.known_recipes.size()}
	return {"title": p.name, "kind": "player", "fields": fields}


# --- Debug drawing ----------------------------------------------------------------------------------

## shape: {type: box | line | text | path | sphere, color, seconds, ...}; box {min, max} or {center, size},
## line {from, to}, text {position, text}, path {points}, sphere {center, radius}.
func draw(owner: String, shape: Dictionary) -> void:
	if not SHAPES.has(str(shape.get("type", ""))) or not viewers.values().any(func(v): return v.channels.has("draw")):
		return
	if _shapes.size() >= MAX_SHAPES:
		return
	var s := {"owner": owner, "type": shape.type, "color": str(shape.get("color", "#ffcc00")), "seconds": clampf(float(shape.get("seconds", 2.0)), 0.05, 120.0)}
	for key in ["min", "max", "center", "size", "from", "to", "position"]:
		if shape.has(key):
			s[key] = _vec(shape[key])
	if shape.has("points") and shape.points is Array:
		s.points = (shape.points as Array).slice(0, 256).map(func(v): return _vec(v))
	if shape.has("radius"):
		s.radius = float(shape.radius)
	if shape.has("text"):
		s.text = str(shape.text).left(200)
	_shapes.append(s)


static func _vec(v) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector3i:
		return Vector3(v)
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is Dictionary:
		return Vector3(float(v.get("x", 0)), float(v.get("y", 0)), float(v.get("z", 0)))
	return Vector3.ZERO


func _draw_ai(p) -> void:
	for e in _server.entities.in_radius(p.state.position, 32.0):
		if e.brain == null or not e.is_alive():
			continue
		var b = e.brain
		var head: Vector3 = e.body.position + Vector3(0, e.def.height + 0.3, 0)
		_shapes.append({"owner": "engine:ai", "type": "text", "position": head, "text": "%s%s" % [b.behavior, " → %s" % describe(b.target) if b.target != null else ""],
			"color": "#ff6060" if b.target != null else "#a0e0ff", "seconds": 0.6, "to_peer": p.peer_id})
		if b.path.size() > b.path_index:
			var pts := [e.body.position + Vector3(0, 0.2, 0)]
			for i in range(b.path_index, b.path.size()):
				pts.append(Vector3(b.path[i]) + Vector3(0.5, 0.2, 0.5))
			_shapes.append({"owner": "engine:ai", "type": "path", "points": pts, "color": "#60ff90", "seconds": 0.6, "to_peer": p.peer_id})
		if b.target != null:
			var at: Vector3 = b.target.state.position if b.target.get("state") != null else b.target.body.position
			_shapes.append({"owner": "engine:ai", "type": "line", "from": head, "to": at + Vector3(0, 1, 0), "color": "#ff4040", "seconds": 0.6, "to_peer": p.peer_id})
		if b.home != Vector3.INF:
			_shapes.append({"owner": "engine:ai", "type": "sphere", "center": b.home, "radius": 0.4, "color": "#6090ff", "seconds": 0.6, "to_peer": p.peer_id})


# --- Viewers ----------------------------------------------------------------------------------------

func subscribe(p, channels: Array) -> void:
	if not allowed(p):
		return
	var v: Dictionary = viewers.get(p.peer_id, {"channels": {}, "inspect": {}, "log_after": 0, "trace_after": _trace_seq})
	v.channels = {}
	for c in channels:
		v.channels[str(c)] = true
	viewers[p.peer_id] = v
	set_tracing()
	if v.channels.has("errors"):
		_send(p, "errors", _server.dev_log.sorted_errors().slice(0, 100))
	if v.channels.has("logs"):
		v.log_after = 0


func unsubscribe(peer_id: int) -> void:
	viewers.erase(peer_id)
	set_tracing()


func set_inspect(p, target: Dictionary) -> void:
	if not viewers.has(p.peer_id) or not allowed(p):
		return
	viewers[p.peer_id].inspect = target
	_send(p, "inspect", inspect(target))


func _send(p, kind: String, data) -> void:
	if p._online():
		Net.s_dev.rpc_id(p.peer_id, kind, data)


func update(delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if now - _window_started >= 1.0:
		_window_started = now
		_roll_window()
	if viewers.is_empty():
		_shapes.clear()
		return
	_send_timer += delta
	_perf_timer += delta
	_ai_timer += delta
	var ai_round := _ai_timer >= 0.5
	if ai_round:
		_ai_timer = 0.0
	for peer_id in viewers.keys():
		var p = _server.players.get(peer_id)
		if p == null or not allowed(p):
			viewers.erase(peer_id)
			set_tracing()
			continue
		if ai_round and viewers[peer_id].channels.has("ai"):
			_draw_ai(p)
	if not _shapes.is_empty():
		for peer_id in viewers:
			var v: Dictionary = viewers[peer_id]
			var mine := _shapes.filter(func(s): return s.get("to_peer", peer_id) == peer_id and (v.channels.has("draw") or s.owner == "engine:ai"))
			if not mine.is_empty():
				_send(_server.players[peer_id], "draw", mine)
		_shapes.clear()
	if _send_timer < 0.25:
		return
	_send_timer = 0.0
	var perf_round := _perf_timer >= 1.0
	if perf_round:
		_perf_timer = 0.0
	var rows := perf() if perf_round else []
	for peer_id in viewers:
		var v: Dictionary = viewers[peer_id]
		var p = _server.players[peer_id]
		if v.channels.has("logs"):
			var fresh: Array = _server.dev_log.entries.filter(func(e): return e.id > v.log_after)
			if not fresh.is_empty():
				v.log_after = fresh.back().id
				_send(p, "logs", fresh.slice(-300))
		if v.channels.has("events"):
			var events: Array = trace.filter(func(t): return t.id > v.trace_after)
			if not events.is_empty():
				v.trace_after = events.back().id
				_send(p, "events", events.slice(-100))
		if perf_round and v.channels.has("perf"):
			_send(p, "perf", rows.slice(0, 80))
		if perf_round and v.channels.has("inspect") and not v.inspect.is_empty():
			_send(p, "inspect", inspect(v.inspect))


func on_error(e: Dictionary) -> void:
	for peer_id in viewers:
		if viewers[peer_id].channels.has("errors"):
			_send(_server.players[peer_id], "error", e)
