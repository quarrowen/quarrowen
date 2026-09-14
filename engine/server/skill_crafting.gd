extends RefCounted
## Crafting by hand: recipes and assemblies that name a `skill` (a registered minigame) can be crafted
## normally (Standard quality) or through the minigame for Fine, Superior or Masterwork results.
## Ingredients are taken when the game starts, so leaving early still gives at least Standard.
##
## Team minigames: the starter can wait for a partner at the same station (others there see an
## invitation in the co-op panel); the starter takes the hammer and the partner the bellows. Without a
## partner in time the game starts solo.
##
## The server scores inputs itself (engine/shared/minigame.gd). Clients send the game time of each
## input; it is clamped to what the connection's latency allows, so a modified client can only shift
## inputs within that small window.

const Minigame = preload("res://engine/shared/minigame.gd")
const COUNTDOWN := 2.0
const INVITE_SECONDS := 8.0
const MIN_LAG := 0.25
const MAX_LAG := 0.6

var defs := {}  # minigame name -> clean def
## Tests set this to control the clock (seconds); < 0 uses real time.
var time_override := -1.0

var _server
var _games := {}  # game id -> game
var _by_peer := {}  # peer id -> game id
var _next_id := 1


func _init(game_server) -> void:
	_server = game_server


func register(minigame_name: String, def: Dictionary) -> void:
	defs[minigame_name] = Minigame.clean_def(minigame_name, def)


func to_network() -> Dictionary:
	return defs


func now() -> float:
	return time_override if time_override >= 0.0 else Time.get_ticks_msec() / 1000.0


func game_of(p) -> Dictionary:
	return _games.get(_by_peer.get(p.peer_id, -1), {})


## Starts crafting by hand. product: {recipe: index} or {assembly: name, slots: [backpack slot per
## assembly slot]}. Returns the game id, or 0 if it could not start.
func start(p, product: Dictionary, assist := false, with_partner := false) -> int:
	if p.dead or _by_peer.has(p.peer_id):
		return 0
	var skill := ""
	if product.has("recipe"):
		var index := int(product.recipe)
		if index < 0 or index >= _server.recipes.recipes.size():
			return 0
		skill = str(_server.recipes.recipes[index].get("skill", ""))
	elif product.has("assembly"):
		skill = str(_server.assembly.assemblies.get(str(product.assembly), {}).get("skill", ""))
	if not defs.has(skill):
		return 0
	var output: Dictionary = _server.take_recipe_inputs(p, int(product.recipe)) if product.has("recipe") \
		else _server.take_assembly_parts(p, str(product.assembly), PackedInt32Array(product.get("slots", [])))
	if output.is_empty():
		return 0
	var def: Dictionary = defs[skill]
	var at_station: bool = _server._station_valid(p)
	var bonus := float(p.crafting_station.get("quality", 0.0)) if at_station else 0.0
	var g := Minigame.new_game(def, randi(), assist and bool(_server.gameplay.get("minigame_assist", true)), bonus, with_partner and at_station)
	g.merge({"id": _next_id, "owner": p.peer_id, "partner": 0, "output": output, "product": product, "started": -1.0,
		"station": p.crafting_station.position if at_station else null, "names": [p.name], "invite_until": 0.0, "done": false})
	_next_id += 1
	_games[g.id] = g
	_by_peer[p.peer_id] = g.id
	if g.team:
		g.invite_until = now() + INVITE_SECONDS
		_send(g)
		_server.sessions.mark(g.station)
	else:
		_begin(g)
	return g.id


## Invitations waiting at a station: [{id, by_name, title}].
func invites_at(pos: Vector3i) -> Array:
	var out := []
	for g in _games.values():
		if g.team and g.started < 0.0 and g.station == pos:
			out.append({"id": g.id, "by_name": g.names[0], "title": g.def.title})
	return out


## Joins a waiting team game as the bellows.
func join(p, game_id: int) -> bool:
	var g: Dictionary = _games.get(game_id, {})
	if g.is_empty() or not g.team or g.started >= 0.0 or g.owner == p.peer_id or _by_peer.has(p.peer_id) or p.dead:
		return false
	if not _server._station_valid(p) or p.crafting_station.position != g.station:
		return false
	g.partner = p.peer_id
	g.names.append(p.name)
	_by_peer[p.peer_id] = g.id
	_begin(g)
	return true


## Starts a waiting team game without a partner.
func start_alone(p) -> void:
	var g := game_of(p)
	if not g.is_empty() and g.owner == p.peer_id and g.started < 0.0:
		g.team = false
		_begin(g)


func _begin(g: Dictionary) -> void:
	g.started = now() + COUNTDOWN
	if g.station != null:
		_server.sessions.mark(g.station)
	_send(g)


## An input from a player: "strike", "hold" (arg 1 pressed / 0 released), "key" (arg = direction
## index) or "quit". `t` is the game time the client saw.
func input(p, action: String, t: float, arg := 0) -> void:
	var g := game_of(p)
	if g.is_empty() or g.done:
		return
	if action == "quit":
		if g.owner == p.peer_id:
			finish(g)
		else:
			_leave_partner(g)
		return
	if g.started < 0.0:
		return
	var game_t: float = now() - g.started
	var lag := clampf(MIN_LAG + _server.peer_rtt(p) * 1.5, MIN_LAG, MAX_LAG)
	t = clampf(t, maxf(game_t - lag, 0.0), game_t + 0.05)
	var role := role_of(g, p)
	match action:
		"strike":
			if g.def.type != "timing" or role == "bellows" or g.strikes.size() >= g.def.rounds:
				return
			t = maxf(t, float(g.strikes.back()) if not g.strikes.is_empty() else 0.0)
			g.strikes.append(t)
		"hold":
			var hold_role: bool = role == "bellows" or (not g.team and g.def.type == "hold")
			var down := arg != 0
			if not hold_role or (not g.holds.is_empty() and bool(g.holds.back()[1]) == down) or (g.holds.is_empty() and not down):
				return
			t = maxf(t, float(g.holds.back()[0]) if not g.holds.is_empty() else 0.0)
			g.holds.append([t, down])
		"key":
			if g.def.type != "sequence" or arg < 0 or arg >= Minigame.KEYS.size():
				return
			t = maxf(t, float(g.keys.back()[0]) if not g.keys.is_empty() else 0.0)
			g.keys.append([t, Minigame.KEYS[arg]])
		_:
			return
	var other: int = g.partner if p.peer_id == g.owner else g.owner
	if other > 0 and _server.players.has(other) and _server.players[other]._online():
		Net.s_minigame_event.rpc_id(other, action, t, arg)
	if Minigame.complete(g, game_t):
		finish(g)


func role_of(g: Dictionary, p) -> String:
	if not g.team:
		return ""
	return "hammer" if p.peer_id == g.owner else "bellows"


func update() -> void:
	var t := now()
	for g in _games.values().duplicate():
		if g.started < 0.0:
			if t >= g.invite_until:
				g.team = false
				_begin(g)
		elif t - g.started > Minigame.time_limit(g) + MAX_LAG:
			finish(g)


## Ends the game: scores it, gives the item with its quality and tells the players.
func finish(g: Dictionary) -> void:
	if g.done:
		return
	g.done = true
	var game_t: float = clampf(now() - g.started, 0.0, Minigame.time_limit(g)) if g.started >= 0.0 else 0.0
	var value := Minigame.score(g, game_t) if g.started >= 0.0 else 0.0
	var quality := Minigame.quality_for(value)
	var owner = _server.players.get(g.owner)
	var out: Dictionary = g.output
	var data := apply_quality(int(out.item), out.data.duplicate(true), quality, g.names)
	var ev: Dictionary = _server.emit("skill_crafted", {"player": owner, "item": out.item, "count": out.count, "quality": quality.tier,
		"score": value, "names": g.names.duplicate(), "data": data, "product": g.product})
	if owner != null:
		_server.give_crafted(owner, int(out.item), int(out.count), ev.data, g.product.has("assembly"))
		if out.has("recipe"):
			_server.emit("item_crafted", {"player": owner, "item": out.item, "count": out.count, "recipe": out.recipe})
	var result := {"quality": quality.tier, "name": quality.name, "color": quality.color, "score": snappedf(value, 0.01), "item": out.item, "data": ev.data}
	for peer in [g.owner, g.partner]:
		_by_peer.erase(peer)
		var pl = _server.players.get(peer)
		if pl != null and pl._online():
			Net.s_minigame.rpc_id(peer, {"id": g.id, "phase": "done", "result": result})
	_games.erase(g.id)
	if g.station != null:
		_server.sessions.mark(g.station)


func player_left(p) -> void:
	var g := game_of(p)
	if g.is_empty():
		return
	if g.owner == p.peer_id:
		finish(g)
	else:
		_leave_partner(g)


func _leave_partner(g: Dictionary) -> void:
	_by_peer.erase(g.partner)
	g.partner = 0  # the heat just cools from here


## Quality raises durability, tool speed, weapon damage and armor, renames the item and credits the
## makers. Standard leaves the item unchanged.
func apply_quality(item: int, data: Dictionary, quality: Dictionary, names: Array) -> Dictionary:
	if int(quality.tier) <= 0:
		return data
	var items = _server.items
	var mult := 1.0 + float(quality.bonus)
	var durability: int = items.max_durability(item, data)
	if durability > 0:
		data.durability = roundi(durability * mult)
	var tool: Dictionary = items.tool_of(item, data)
	if not tool.is_empty() and not str(tool.get("type", "")).is_empty():
		tool = tool.duplicate()
		tool.speed = snappedf(float(tool.speed) * mult, 0.1)
		data.tool = tool
	var weapon: Dictionary = items.weapon_of(item, data)
	if not weapon.is_empty():
		weapon = weapon.duplicate()
		weapon.damage = snappedf(float(weapon.damage) * mult, 0.1)
		data.weapon = weapon
	var armor: Dictionary = items.get_def(item).get("armor", {})
	if float(armor.get("armor", 0.0)) > 0.0:
		var modifiers: Array = data.get("modifiers", []).duplicate() if data.get("modifiers") is Array else []
		modifiers.append({"stat": "armor", "amount": snappedf(float(armor.armor) * float(quality.bonus), 0.1)})
		data.modifiers = modifiers
	data.name = "%s %s" % [quality.name, str(data.get("name", items.display_name(item)))]
	data.quality = int(quality.tier)
	var lore: Array = data.get("lore", []).duplicate() if data.get("lore") is Array else []
	var stars := "★".repeat(int(quality.tier))
	lore.push_front("%s %s (+%d%%)" % [stars, quality.name, roundi(float(quality.bonus) * 100)])
	if int(quality.tier) >= 3:
		lore.append("Crafted by %s" % " & ".join(PackedStringArray(names)))
		if not data.has("glow"):
			data.glow = {"color": quality.color, "energy": 0.35}
	data.lore = lore
	return data


func _send(g: Dictionary) -> void:
	var t := now()
	for peer in [g.owner, g.partner]:
		var pl = _server.players.get(peer)
		if pl == null or not pl._online():
			continue
		Net.s_minigame.rpc_id(peer, {"id": g.id, "phase": "waiting" if g.started < 0.0 else "playing", "def": g.def, "seed": g.seed,
			"assist": g.assist, "bonus": g.bonus, "team": g.team, "role": role_of(g, pl), "names": g.names,
			"countdown": maxf(g.started - t, 0.0), "wait": maxf(g.invite_until - t, 0.0), "item": g.output.item})
