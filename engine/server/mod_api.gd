extends RefCounted
## The interface a mod uses to realize a game on top of the engine. Each mod gets its own instance
## so names and assets are namespaced to that mod ("mod_id:name").
##
## Events (handler receives one Dictionary; set `cancelled = true` where noted to veto):
##   player_join    {player, first_time}
##   player_leave   {player}
##   tick           {delta, tick}
##   block_break    {player, position, block, drops: [[id, count]...], cancelled}
##   block_broken   {player, position, block}
##   block_place    {player, position, block, cancelled}
##   block_placed   {player, position, block}
##   chat           {player, text, cancelled}
##   ui_action      {player, ui_id, action}
##   block_interact {player, position, block}   right-click on a block registered "interactive"
##   item_use       {player, item, has_target, position, normal, direction}   right-click holding a usable item
##   item_crafted   {player, item, count}
##   item_drop      {player, item, count, cancelled}          Q key
##   item_pickup    {player, entity, item, count, cancelled}
##   player_attack  {player, target, target_kind ("entity" | "player"), item, damage, cancelled}   damage may be changed
##   player_damage  {player, amount, cause, attacker, cancelled}   amount may be changed; cause: attack, mob,
##                  projectile, fall, void, magic, ...
##   player_death   {player, cause, attacker, keep_inventory, message}   keep_inventory and message may be changed
##   player_respawn {player, position}                        position may be changed
##   entity_spawned {entity}          entity_removed {entity}
##   entity_damage  {entity, amount, cause, attacker, cancelled}
##   entity_death   {entity, cause, attacker, drops: [[id, count]...]}   drops may be changed
##   entity_interact {player, entity, item}                   right-click on an entity
##   entity_natural_spawn {type, position, cancelled}         from spawn rules
##   mob_target     {entity, target, previous, reason, cancelled}   a mob picks a new enemy
##   mob_attack     {entity, attack: {name, type, damage}, target, cancelled}   an attack lands (custom attacks act here)
##   mob_phase      {entity, phase, message}                  a boss crosses a phase threshold; message may be changed
##   projectile_hit {entity, owner, hit ("block" | "entity" | "player"), target, position, block, damage,
##                  cancelled (no damage), keep (do not remove the projectile)}

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const OrePass = preload("res://engine/server/ore_pass.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")

var mod_id: String
var mod_dir: String
var manifest: Dictionary

var _server


func _init(server, mod_manifest: Dictionary) -> void:
	_server = server
	manifest = mod_manifest
	mod_id = mod_manifest.id
	mod_dir = mod_manifest.dir


# --- General ------------------------------------------------------------------------------------

func info(message: String) -> void:
	print("[%s] %s" % [mod_id, message])


var world_seed: int:
	get:
		return _server.world_seed


## Persistent Dictionary owned by this mod, saved with the world.
var storage: Dictionary:
	get:
		return _server.mod_storage(mod_id)


## Sets the server name/description shown to connecting clients.
func set_server_info(values: Dictionary) -> void:
	for key in ["name", "description", "motd"]:
		if values.has(key):
			_server.server_info[key] = String(values[key])


# --- Content ------------------------------------------------------------------------------------

## Registers a block. `name` is namespaced to this mod. Texture and model paths are relative to the
## mod folder. See BlockRegistry.register for keys (render, light, interactive, model, ...). Extra keys
## (e.g. `drops`: "base:cobblestone" or "") are kept server-side.
## Returns the runtime block id, or -1 on error.
func register_block(block_name: String, def: Dictionary) -> int:
	var d := def.duplicate(true)
	d.name = _qualify(block_name)
	var faces := BlockRegistry.expand_textures(def.get("textures", ""))
	for i in faces.size():
		faces[i] = register_asset(faces[i]) if not faces[i].is_empty() else ""
	d.textures = faces
	if not String(def.get("model", "")).is_empty():
		d.model = register_asset(def.model)
		d.render = "model"
	if not String(def.get("model_arm", "")).is_empty():
		d.model_arm = register_asset(def.model_arm)
	if def.get("sounds") is Dictionary:
		d.sounds = {}
		for action in def.sounds:
			d.sounds[action] = _qualify_ref(String(def.sounds[action]))
	return _server.registry.register(d)


## Registers a non-block item. `icon` is a texture path; `usable` makes right-click fire item_use.
## Returns the item id (>= 256), or -1.
func register_item(item_name: String, def: Dictionary) -> int:
	var d := def.duplicate(true)
	d.name = _qualify(item_name)
	if not String(def.get("icon", "")).is_empty():
		d.icon = register_asset(def.icon)
	return _server.items.register(d)


## Registers an entity type (mob, projectile, object). See EntityRegistry.register for keys. Model and
## sprite paths are relative to the mod folder; sound names without a ":" are this mod's.
## Returns the type id, or -1.
func register_entity(entity_name: String, def: Dictionary) -> int:
	var d := def.duplicate(true)
	d.name = _qualify(entity_name)
	for key in ["model", "sprite"]:
		if not String(def.get(key, "")).is_empty():
			d[key] = register_asset(def[key])
	if def.get("sounds") is Dictionary:
		d.sounds = {}
		for action in def.sounds:
			d.sounds[action] = _qualify_ref(String(def.sounds[action]))
	return _server.entities.registry.register(d)


## Registers a sound from one or more audio files in the mod folder (.ogg or .wav; a random one plays
## each time). options: volume (0-2), pitch, pitch_variance, range (blocks). Returns the sound id.
func register_sound(sound_name: String, files, options := {}) -> int:
	var d := options.duplicate()
	d.name = _qualify(sound_name)
	var assets := []
	for f in (files if files is Array else [files]):
		assets.append(register_asset(String(f)))
	d.files = assets
	return _server.sounds.register(d)


## Plays a sound at a world position for everyone in range.
func play_sound(sound_name: String, position: Vector3, volume := 1.0, pitch := 1.0) -> void:
	_server.play_sound_at(_qualify_ref(sound_name), position, volume, pitch)


## Entity type id by name ("vanilla:zombie", or a local name). -1 if unknown.
func entity_type(entity_name: String) -> int:
	return _server.entities.registry.id_of(_qualify_ref(entity_name))


## Spawns an entity. options: yaw, velocity (Vector3), data (Dictionary), owner (player or entity,
## for projectiles). Returns the entity or null.
func spawn_entity(entity_name: String, position: Vector3, options := {}):
	return _server.entities.spawn(entity_type(entity_name), position, options)


## Fires a projectile entity from `from` with `velocity`, credited to `owner` (player or entity).
func spawn_projectile(entity_name: String, from: Vector3, velocity: Vector3, owner = null):
	return _server.entities.spawn(entity_type(entity_name), from, {"velocity": velocity, "owner": owner, "yaw": atan2(-velocity.x, -velocity.z)})


## Drops an item stack entity (players walk over it to pick it up).
func drop_item(item_id: int, count: int, position: Vector3):
	return _server.entities.drop_item(item_id, count, position)


## Living entities within `radius` of `center`, optionally only of one type.
func get_entities(center: Vector3, radius: float, entity_name := "") -> Array:
	return _server.entities.in_radius(center, radius, entity_type(entity_name) if not entity_name.is_empty() else -1)


func get_entity(entity_id: int):
	return _server.entities.entities.get(entity_id)


## Registers a mob behaviour that mobs listing it in ai.behaviors can choose. `def`:
##   score:  Callable(brain) -> float   utility each think; the highest scoring behaviour runs.
##           Engine scores: idle 0.05, wander 0.1, investigate 0.4, search <= 0.65, engage 0.7-0.9,
##           return_home 0.95+, flee 1.05, scripted 1.2
##   update: Callable(brain, delta)     called each think while it runs; use brain.move_to / stop /
##           look_at, brain.target, brain.entity, brain.can_see_target(), brain.health_fraction()
##   stop:   Callable(brain)            optional, when another behaviour takes over
func register_mob_behavior(behavior_name: String, def: Dictionary) -> void:
	_server.entities.ai.custom_behaviors[_qualify_ref(behavior_name) if behavior_name.contains(":") else _qualify(behavior_name)] = {
		"score": def.get("score", Callable()), "update": def.get("update", Callable()), "stop": def.get("stop", Callable())}


## Lets mobs hear something at `position` (they come to investigate). `source` may be a player.
func make_noise(position: Vector3, radius: float, source = null) -> void:
	_server.entities.ai.make_noise(position, radius, source)


## Natural spawning. def: entity (name), time ("night" | "day" | "any"), on (block names the mob may
## stand on; default any), max_nearby (per player), max_total, chance (per player per second),
## min_distance, max_distance.
func add_spawn_rule(def: Dictionary) -> void:
	var type_id := entity_type(String(def.get("entity", "")))
	if type_id < 0:
		push_error("[%s] add_spawn_rule: unknown entity %s" % [mod_id, def.get("entity")])
		return
	var rule := def.duplicate()
	rule.entity = type_id
	var on := []
	for block_ref in def.get("on", []):
		var id := block(String(block_ref))
		if id > 0:
			on.append(id)
	rule.on = on
	_server.entities.add_spawn_rule(rule)


## Game-wide rules: item_drops ("entity" | "inventory"), keep_inventory, pvp, fall_damage,
## natural_regeneration, mob_spawning.
func set_gameplay(values: Dictionary) -> void:
	_server.set_gameplay(values)


func get_gameplay(rule: String):
	return _server.gameplay.get(rule)


## Looks up any block or item id by name ("base:coal", or a local name). -1 if unknown.
func item(item_name: String) -> int:
	return _server.items.id_of(item_name if item_name.contains(":") else _qualify(item_name))


func item_name(id: int) -> String:
	return _server.items.name_of(id)


func item_display_name(id: int) -> String:
	return _server.items.display_name(id)


## Shapeless recipe: `inputs` maps item names to counts. Appears in the engine crafting menu (C key).
func register_recipe(inputs: Dictionary, output: String, count := 1) -> void:
	var resolved := {}
	for input_name: String in inputs:
		var id := item(input_name)
		if id <= 0:
			push_error("[%s] Recipe input '%s' is unknown" % [mod_id, input_name])
			return
		resolved[id] = int(inputs[input_name])
	var out := item(output)
	if out <= 0:
		push_error("[%s] Recipe output '%s' is unknown" % [mod_id, output])
		return
	_server.add_recipe(resolved, out, count)


## Makes a file from this mod's folder downloadable by clients. Returns its asset name.
func register_asset(relative_path: String) -> String:
	if relative_path.contains(":"):
		return relative_path  # already an asset name from another mod
	var asset_name := "%s:%s" % [mod_id, relative_path]
	_server.add_asset(asset_name, mod_dir.path_join(relative_path))
	return asset_name


## Looks up a block id by name ("base:stone", or "stone" for this mod's own). -1 if unknown.
func block(block_name: String) -> int:
	return _server.registry.id_of(block_name if block_name.contains(":") else _qualify(block_name))


func block_name(id: int) -> String:
	return _server.registry.defs[id].name if _server.registry.is_valid(id) else ""


func block_display_name(id: int) -> String:
	return _server.registry.display_name(id)


# --- World --------------------------------------------------------------------------------------

## `generator` must implement `generate(chunk)`; write into a local copy of `chunk.blocks`
## (index with Chunk.index(x, y, z)) and assign it back for speed.
func set_world_generator(generator: Object) -> void:
	_server.generator = generator


## `handler(player) -> Vector3` picks the spawn position for players without a saved position.
func set_spawn_handler(handler: Callable) -> void:
	_server.spawn_handler = handler


## Adds a pass run after the world generator for every new chunk, on worker threads:
## `pass_object.decorate(chunk, world_seed)`. Lets add-on mods put ores or structures in any game.
func add_generation_pass(pass_object: Object) -> void:
	_server.generation_passes.append(pass_object)


## Scatters veins of `ore` inside `replace` in every new chunk. def: ore, replace (block names),
## veins (per chunk), size (blocks per vein), min_y, max_y, chance (per vein, 0-1).
func add_ore_pass(def: Dictionary) -> void:
	var ore := block(String(def.get("ore", "")))
	var replace := block(String(def.get("replace", "base:stone")))
	if ore <= 0 or replace <= 0:
		push_error("[%s] add_ore_pass: unknown block in %s" % [mod_id, def])
		return
	var resolved := def.duplicate()
	resolved.ore = ore
	resolved.replace = replace
	resolved.salt = "%s:%s" % [mod_id, def.get("ore")]
	add_generation_pass(OrePass.new(resolved))


## Movement tunables (walk_speed, sprint_speed, gravity, jump_velocity, ...) and `void_below`.
func set_physics(values: Dictionary) -> void:
	_server.set_rules(values)


## Loads the chunk if needed. Use get_loaded_block when scanning large areas.
func get_block(pos: Vector3i) -> int:
	return _server.get_block_loaded(pos)


## Block id without loading anything; BlockRegistry.UNLOADED (255) if the chunk is not in memory.
func get_loaded_block(pos: Vector3i) -> int:
	return _server.world.get_block_v(pos)


func is_solid(block: int) -> bool:
	return block == BlockRegistry.UNLOADED or (_server.registry.is_valid(block) and _server.registry.solid_lut[block] == 1)


func is_breakable(block: int) -> bool:
	return _server.registry.is_valid(block) and _server.registry.breakable_lut[block] == 1


## What breaking this block yields by default: [[item id, count], ...].
func get_drops(block: int) -> Array:
	return _server._default_drops(block) if _server.registry.is_valid(block) else []


## Sets a block authoritatively (loading its chunk if needed) and replicates it to players. Block
## data at the position is cleared when the block type changes unless `keep_data` is true.
func set_block(pos: Vector3i, id: int, keep_data := false, state := 0) -> void:
	_server.set_block_authoritative(pos, id, keep_data, state)


## Per-block state byte (e.g. facing 0-3 for "orientation": "horizontal" blocks).
func get_block_state(pos: Vector3i) -> int:
	return _server.get_block_state(pos)


## Facing (0-3) an oriented block gets when placed by someone looking along `yaw`.
func facing_from_yaw(yaw: float) -> int:
	return BlockRegistry.facing_from_yaw(yaw)


## Front direction of an oriented block (+Z/+X/-Z/-X for facing 0-3).
func facing_direction(state: int) -> Vector3i:
	return BlockRegistry.facing_direction(state)


func show_crafting(player) -> void:
	_server.show_crafting(player)


## Block data ("block entities"): a Dictionary of JSON-compatible values stored with the world and
## removed automatically when the block is broken or replaced.
func get_block_data(pos: Vector3i) -> Dictionary:
	return _server.get_block_data(pos)


func set_block_data(pos: Vector3i, data: Dictionary) -> void:
	_server.set_block_data(pos, data)


func clear_block_data(pos: Vector3i) -> void:
	_server.clear_block_data(pos)


## Loaded positions that carry block data, optionally filtered to one block id.
func find_block_data(block := -1) -> Array[Vector3i]:
	return _server.find_block_data(block)


## time_of_day: 0 = midnight, 0.25 = sunrise, 0.5 = noon. day_length in seconds (0 freezes time).
func set_world_time(time_of_day: float, day_length := -1.0) -> void:
	_server.set_world_time(time_of_day, _server.get_day_length() if day_length < 0.0 else day_length)


func get_time_of_day() -> float:
	return _server.get_time_of_day()


## Sky brightness in [0.12, 1] for the current time of day.
func get_daylight() -> float:
	return WorldTime.daylight(_server.get_time_of_day())


## True if nothing opaque or solid is above the block (it can see the sky).
func sees_sky(pos: Vector3i) -> bool:
	for y in range(pos.y + 1, Chunk.SIZE_Y):
		var id := get_block(Vector3i(pos.x, y, pos.z))
		if _server.registry.opaque_lut[id] == 1 or _server.registry.solid_lut[id] == 1:
			return false
	return true


func fill(from: Vector3i, to: Vector3i, id: int) -> void:
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			for z in range(mini(from.z, to.z), maxi(from.z, to.z) + 1):
				_server.set_block_authoritative(Vector3i(x, y, z), id)


## Y of the highest non-air block in the column, or -1.
func surface_y(x: int, z: int) -> int:
	for y in range(Chunk.SIZE_Y - 1, -1, -1):
		if get_block(Vector3i(x, y, z)) != BlockRegistry.AIR:
			return y
	return -1


# --- Players ------------------------------------------------------------------------------------

func get_players() -> Array:
	return _server.players.values()


func find_player(player_name: String):
	for p in _server.players.values():
		if p.name.to_lower() == player_name.to_lower():
			return p
	return null


func broadcast(text: String) -> void:
	_server.broadcast_chat(text)


# --- Events, commands, scheduling ---------------------------------------------------------------

## Higher priority runs first.
func on(event: String, handler: Callable, priority := 0) -> void:
	_server.add_handler(event, handler, priority)


## `handler(player, args: PackedStringArray)` runs for "/name args...". permission "admin" restricts
## it to server admins (VOXEL_ADMINS, /op, or the local host).
func register_command(command: String, description: String, handler: Callable, permission := "") -> void:
	_server.add_command(command, description, handler, mod_id, permission)


## Runs `callback` once after `seconds`. Returns a task id for `cancel`.
func after(seconds: float, callback: Callable) -> int:
	return _server.schedule(seconds, callback, 0.0)


## Runs `callback` every `seconds`. Returns a task id for `cancel`.
func every(seconds: float, callback: Callable) -> int:
	return _server.schedule(seconds, callback, seconds)


func cancel(task_id: int) -> void:
	_server.cancel_task(task_id)


func _qualify(local_name: String) -> String:
	return "%s:%s" % [mod_id, local_name]


## Names that already have a namespace ("base:stone", "engine:hurt") are kept as they are.
func _qualify_ref(ref: String) -> String:
	return ref if ref.contains(":") or ref.is_empty() else _qualify(ref)
