extends RefCounted
## The guidebook on the server: registered chapters and pages (see engine/shared/guide_registry.gd)
## and what each player has unlocked and read. Unlocks only ever grow and are saved with the world.
## Checked about once a second per player: held items (`seen_items`), known recipes, mobs seen within
## SEE_RADIUS blocks, flags set by mods, and pages read.
## Event: guide_page_unlocked {player, page}

const GuideRegistry = preload("res://engine/shared/guide_registry.gd")

const SEE_RADIUS := 12.0
const CHECK_INTERVAL := 1.0

var registry := GuideRegistry.new()
var _server
var _timer := 0.0


func _init(game_server) -> void:
	_server = game_server


## Per-player guide state: {flags, entities, read, unlocked (page id -> true), last}.
static func state_of(p) -> Dictionary:
	if p.guide.is_empty():
		p.guide = {"flags": {}, "entities": {}, "read": {}, "unlocked": {}, "last": ""}
	return p.guide


func load_player(p, saved) -> void:
	var s := state_of(p)
	if not (saved is Dictionary):
		return
	for key in ["flags", "entities", "read", "unlocked"]:
		for id in (saved.get(key) if saved.get(key) is Array else []):
			s[key][str(id)] = true
	s.last = str(saved.get("last", ""))


func save_player(p) -> Dictionary:
	var s := state_of(p)
	return {"flags": s.flags.keys(), "entities": s.entities.keys(), "read": s.read.keys(), "unlocked": s.unlocked.keys(), "last": s.last}


## Whether a page's unlock condition holds right now (ignores pages unlocked before).
func condition_met(p, page: Dictionary) -> bool:
	var s := state_of(p)
	var unlock: Dictionary = page.unlock
	if unlock.is_empty():
		return true
	if unlock.has("item"):
		return p.seen_items.has(unlock.item)
	if unlock.has("recipe"):
		return _server.knows_recipe(p, unlock.recipe)
	if unlock.has("entity"):
		return s.entities.has(unlock.entity)
	if unlock.has("flag"):
		return s.flags.has(unlock.flag)
	if unlock.has("page"):
		return s.read.has(unlock.page)
	return false


func is_unlocked(p, page_id: String) -> bool:
	return state_of(p).unlocked.has(page_id)


## Unlocks pages whose conditions now hold; tells the client (with a popup when `notify`).
func refresh(p, notify := true) -> void:
	var s := state_of(p)
	var fresh := PackedStringArray()
	# Pages can unlock others ("page" conditions need reading, so one pass is enough).
	for page in registry.pages:
		if not s.unlocked.has(page.id) and condition_met(p, page):
			s.unlocked[page.id] = true
			fresh.append(page.id)
	if fresh.is_empty():
		return
	if p._online():
		Net.s_guide_unlocked.rpc_id(p.peer_id, fresh, notify)
	for page_id in fresh:
		_server.emit("guide_page_unlocked", {"player": p, "page": page_id})


## Sends the full guide state after joining.
func sync(p) -> void:
	refresh(p, false)
	var s := state_of(p)
	if p._online():
		Net.s_guide_state.rpc_id(p.peer_id, PackedStringArray(s.unlocked.keys()), PackedStringArray(s.read.keys()), s.last)


func set_flag(p, flag: String, on := true) -> void:
	var s := state_of(p)
	if on:
		s.flags[flag] = true
		refresh(p)
	else:
		s.flags.erase(flag)


func has_flag(p, flag: String) -> bool:
	return state_of(p).flags.has(flag)


## Unlocks a page right away, whatever its condition.
func unlock(p, page_id: String, notify := true) -> bool:
	var s := state_of(p)
	if registry.get_page(page_id).is_empty() or s.unlocked.has(page_id):
		return false
	s.unlocked[page_id] = true
	if p._online():
		Net.s_guide_unlocked.rpc_id(p.peer_id, PackedStringArray([page_id]), notify)
	_server.emit("guide_page_unlocked", {"player": p, "page": page_id})
	return true


## Opens the book for a player, at a page ("" = where they left off).
func open(p, page_id := "") -> void:
	if p._online():
		Net.s_guide_open.rpc_id(p.peer_id, page_id)


## The client shows a page: it counts as read (if unlocked) and is remembered as the last page.
func on_read(p, page_id: String) -> void:
	var s := state_of(p)
	if registry.get_page(page_id).is_empty() or not s.unlocked.has(page_id):
		return
	s.last = page_id
	if not s.read.has(page_id):
		s.read[page_id] = true
		refresh(p)


func update(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL or registry.pages.is_empty():
		return
	_timer = 0.0
	for p in _server.players.values():
		if p.dead:
			continue
		var s := state_of(p)
		for e in _server.entities.in_radius(p.state.position, SEE_RADIUS):
			if e.def.kind == "mob" and e.is_alive():
				s.entities[e.def.name] = true
		refresh(p)
