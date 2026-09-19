extends RefCounted
## Mob spawner blocks: any block with `spawner: true`. Its block data `spawner: {entity (name or list:
## one is picked per spawner), count [min, max], range, max_nearby, player_range, max_light}` decides
## what appears. Every few seconds, while a player is within `player_range`, it spawns a few mobs on
## dark free ground around it, up to `max_nearby` of that kind.

const DEFAULTS := {"entity": "", "count": [1, 3], "range": 4, "max_nearby": 6, "player_range": 16.0, "max_light": 11}

var _server


func _init(game_server) -> void:
	_server = game_server


## Hooks every spawner block up to block ticks (after all mods registered their blocks).
func setup() -> void:
	for i in _server.registry.defs.size():
		if bool(_server.registry.defs[i].get("spawner", false)):
			_server.block_ticks.register(i, _tick, {"interval": 6.0, "catch_up": false})


## KNOWN LIMIT: overworld only. Spawner blocks are found and ticked through the server's default
## realm, so a spawner placed in another world does nothing. It needs the same treatment as block
## ticks - registered per realm rather than per server - and is left until a mod can actually make a
## second realm. (2026-09-19)
func settings(pos: Vector3i) -> Dictionary:
	var data: Dictionary = _server.get_block_data(pos)
	var s: Dictionary = DEFAULTS.duplicate(true)
	if data.get("spawner") is Dictionary:
		s.merge(data.spawner, true)
	if s.entity is Array and not s.entity.is_empty():
		# A structure lists a few options: settle on one for this spawner.
		var choice: String = str(s.entity[int(data.get("structure_seed", 0)) % s.entity.size()])
		s.entity = choice
		if not data.is_empty():
			data.spawner.entity = choice
	return s


func _tick(ctx: Dictionary) -> void:
	var pos: Vector3i = ctx.position
	var s := settings(pos)
	var type_id: int = _server.entities.registry.id_of(str(s.entity))
	if type_id < 0:
		return
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	var near := false
	for p in _server.players.values():
		if not p.dead and p.state.position.distance_to(center) <= float(s.player_range):
			near = true
	if not near or _server.entities.in_radius(center, 8.0, type_id).size() >= int(s.max_nearby):
		return
	var solid: PackedByteArray = _server.registry.solid_lut
	var world = _server.world
	var count: Array = s.count if s.count is Array and s.count.size() == 2 else [1, 3]
	var spawned := 0
	for attempt in 12:
		if spawned >= randi_range(int(count[0]), int(count[1])):
			break
		var r := int(s.range)
		var spot := pos + Vector3i(randi_range(-r, r), randi_range(-1, 1), randi_range(-r, r))
		if solid[world.get_block_v(spot)] == 1 or solid[world.get_block_v(spot + Vector3i.UP)] == 1 or solid[world.get_block_v(spot + Vector3i.DOWN)] == 0:
			continue
		if _server.block_ticks.light_at(spot, 0.0) > int(s.max_light):
			continue
		var e = _server.entities.spawn(type_id, Vector3(spot) + Vector3(0.5, 0.0, 0.5))
		if e != null:
			spawned += 1
			_server.play_effect("engine:smoke", Vector3(spot) + Vector3(0.5, 0.5, 0.5), {"scale": 0.6})
