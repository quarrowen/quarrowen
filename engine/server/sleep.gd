extends RefCounted
## Beds, sleeping and respawn points. Blocks with `bed: true` (usually a two-block `pair`) can be
## right-clicked:
## - it becomes the player's respawn point (checked on respawn: a missing or blocked bed falls back to
##   the world spawn);
## - at night, with no hostile mobs close by and the bed free, the player lies down. When enough
##   players are asleep (the `sleep_percentage` rule, default 100% of online players) for SLEEP_SECONDS,
##   the night is skipped to morning and everyone wakes up.
## Sleepers wake when they move, press Leave bed, take damage, the bed breaks or day comes.

const WorldTime = preload("res://engine/shared/world_time.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")

const SLEEP_SECONDS := 5.0
const NIGHT_DAYLIGHT := 0.4  # daylight below this counts as night
const MORNING := 0.26  # time of day after a skipped night
const MONSTER_RANGE := Vector3(8.0, 5.0, 8.0)

var _server
var _status_timer := 0.0


func _init(game_server) -> void:
	_server = game_server


func is_bed(block: int) -> bool:
	return block > 0 and _server.registry.is_valid(block) and bool(_server.registry.defs[block].get("bed", false))


func is_night() -> bool:
	return WorldTime.daylight(_server.get_time_of_day()) < NIGHT_DAYLIGHT


## Both cells of a bed (the clicked one first), and the direction from foot to head.
func bed_cells(pos: Vector3i) -> Dictionary:
	var block: int = _server.world.get_block_v(pos)
	if not is_bed(block):
		return {}
	var partner: Vector3i = _server.pair_position(pos)
	var cells := [pos]
	if partner != pos:
		cells.append(partner)
	var head_dir := Vector3i.ZERO
	if cells.size() == 2:
		# The foot is the piece players place; its pair points to the head.
		var foot: bool = str(_server.registry.defs[block].get("pair", {}).get("direction", "")) == "back"
		head_dir = (cells[1] - cells[0]) if foot else (cells[0] - cells[1])
	else:
		head_dir = -BlockRegistry.facing_direction(_server.get_block_state(pos))
	return {"cells": cells, "head_dir": head_dir}


## Right-click on a bed: set the respawn point, then try to sleep.
func use_bed(p, pos: Vector3i) -> void:
	var bed := bed_cells(pos)
	if bed.is_empty() or p.dead:
		return
	var anchor := _foot_of(bed)
	if p.spawn_bed != anchor:
		p.spawn_bed = anchor
		p.spawn_point = Vector3.INF
		p.send_message("Respawn point set")
	if not p.sleeping.is_empty():
		return
	if not bool(_server.gameplay.get("sleeping", true)):
		return
	if not is_night():
		p.show_title("", "You can only sleep at night", 1.5)
		return
	for other in _server.players.values():
		if other != p and not other.sleeping.is_empty() and Vector3i(other.sleeping.bed) == anchor:
			p.show_title("", "This bed is occupied", 1.5)
			return
	if _monsters_near(bed):
		p.show_title("", "You may not rest now; there are monsters nearby", 2.0)
		return
	if _server.emit("player_sleep", {"player": p, "position": anchor, "cancelled": false}).cancelled:
		return
	var center := Vector3.ZERO
	for cell: Vector3i in bed.cells:
		center += Vector3(cell) + Vector3(0.5, 1.0, 0.5)
	center /= bed.cells.size()
	p.sleeping = {"bed": anchor, "since": _server._time, "head_dir": bed.head_dir, "return": p.state.position}
	p.teleport(center)
	p.mining = {}
	_server.hunger.stop_eating(p)
	_server.refresh_appearance(p)
	_send_status()


func wake(p, reason := "moved") -> void:
	if p.sleeping.is_empty():
		return
	var bed: Dictionary = p.sleeping
	p.sleeping = {}
	var spot := stand_spot(Vector3i(bed.bed))
	p.teleport(spot if spot != Vector3.INF else Vector3(bed["return"]))
	_server.refresh_appearance(p)
	_server.emit("player_wake", {"player": p, "reason": reason})
	if p._online():
		Net.s_sleep.rpc_id(p.peer_id, {"sleeping": false})
	_send_status()


func update(delta: float) -> void:
	var sleepers := []
	for p in _server.players.values():
		if p.sleeping.is_empty():
			continue
		if p.dead or not is_bed(_server.realm_of(p).world.get_block_v(Vector3i(p.sleeping.bed))):
			wake(p, "bed")
		elif not is_night():
			wake(p, "day")
		else:
			sleepers.append(p)
	if sleepers.is_empty():
		return
	_status_timer += delta
	if _status_timer >= 0.5:
		_status_timer = 0.0
		_send_status()
	var needed := needed_sleepers()
	var rested := sleepers.filter(func(p): return _server._time - float(p.sleeping.since) >= SLEEP_SECONDS)
	if rested.size() >= needed:
		skip_night(rested)


## How many players must be asleep to skip the night.
func needed_sleepers() -> int:
	var online := 0
	for p in _server.players.values():
		if not p.dead or not p.sleeping.is_empty():
			online += 1
	var percent := clampf(float(_server.gameplay.get("sleep_percentage", 100)), 0.0, 100.0)
	return maxi(1, ceili(online * percent / 100.0))


func skip_night(sleepers: Array) -> void:
	_server.set_world_time(MORNING, _server.get_day_length())
	_server.emit("night_skipped", {"sleepers": sleepers.duplicate()})
	for p in sleepers.duplicate():
		wake(p, "morning")
		p.show_title("Good morning", "", 2.0)


## Hostile mobs within a few blocks of the bed keep players awake.
func _monsters_near(bed: Dictionary) -> bool:
	var center := Vector3(bed.cells[0]) + Vector3(0.5, 0.5, 0.5)
	for e in _server.entities.entities.values():
		if e.brain == null or not e.is_alive() or str(e.brain.config.get("temperament", "")) != "hostile":
			continue
		var d: Vector3 = (e.position - center).abs()
		if d.x <= MONSTER_RANGE.x and d.y <= MONSTER_RANGE.y and d.z <= MONSTER_RANGE.z:
			return true
	return false


## Where to stand next to a bed (respawning or getting up), or Vector3.INF if it is gone or boxed in.
func stand_spot(anchor: Vector3i) -> Vector3:
	var bed := bed_cells(anchor)
	if bed.is_empty():
		return Vector3.INF
	var world = _server.world
	var registry = _server.registry
	for cell: Vector3i in bed.cells:
		for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
				Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, -1)]:
			for dy in [0, 1, -1]:
				var feet: Vector3i = cell + offset + Vector3i(0, dy, 0)
				var below: int = world.get_block_v(feet + Vector3i.DOWN)
				if below == BlockRegistry.UNLOADED or registry.solid_lut[below] == 0 or registry.liquid_lut[below] == 1:
					continue
				if registry.solid_lut[world.get_block_v(feet)] == 1 or registry.solid_lut[world.get_block_v(feet + Vector3i.UP)] == 1:
					continue
				if registry.liquid_lut[world.get_block_v(feet)] == 1 or _server.registry.defs[world.get_block_v(feet)].get("hazard", false):
					continue
				return Vector3(feet) + Vector3(0.5, 0.0, 0.5)
	return Vector3.INF


## The respawn position from a player's bed, or Vector3.INF (and a message) when it can't be used.
func respawn_position(p) -> Vector3:
	if p.spawn_bed == null:
		return Vector3.INF
	_server.ensure_area_loaded(Vector3(p.spawn_bed), _server.realm_of(p))
	var spot := stand_spot(Vector3i(p.spawn_bed))
	if spot == Vector3.INF:
		p.spawn_bed = null
		p.send_message("You have no home bed, or it was missing or obstructed")
	return spot


func _foot_of(bed: Dictionary) -> Vector3i:
	if bed.cells.size() < 2:
		return bed.cells[0]
	return bed.cells[0] if bed.cells[1] - bed.cells[0] == bed.head_dir else bed.cells[1]


func _send_status() -> void:
	var asleep := 0
	for p in _server.players.values():
		if not p.sleeping.is_empty():
			asleep += 1
	var needed := needed_sleepers()
	for p in _server.players.values():
		if not p.sleeping.is_empty() and p._online():
			Net.s_sleep.rpc_id(p.peer_id, {"sleeping": true, "since": _server._time - float(p.sleeping.since), "asleep": asleep,
				"needed": needed, "seconds": SLEEP_SECONDS, "head_dir": p.sleeping.head_dir})
