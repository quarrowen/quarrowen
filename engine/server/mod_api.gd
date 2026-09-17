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
##   block_destroyed {position, block, drops}                broken without a player (support lost, break_block)
##   container_open {player, position, container, cancelled} container_close {player, position}
##   container_changed {player, position, container, slot}  a player moved items in or out
##   station_upgraded {player, position, station, tier}      a kit upgraded a station
##   craft_job_started {player, position, recipe, times}     a timed recipe joined a station's queue
##   craft_job_finished {player_id, position, recipe, times, helpers}
##   project_contributed {player, position, recipe, item, count}
##   project_completed {position, recipe, item, contributors: {player id: {name, items}}}   reward them here
##   recipe_learned {player, recipe, source ("pickup" | "blueprint" | "experiment" | "mod")}
##   tool_assembled {player, assembly, parts: {slot: material}, data}   data (the tool's item data) may be changed
##   recipe_experimented {player, recipe}                    discovered at the experimentation grid
##   item_crafted also carries {recipe, helpers}; its player is null when a job finished for someone offline
##   block_place    {player, position, block, cancelled}
##   block_placed   {player, position, block}
##   chat           {player, text, cancelled}
##   ui_action      {player, ui_id, action}
##   block_interact {player, position, block, cancelled}   right-click on an "interactive" block (cancel stops containers and stations opening)
##   item_use       {player, item, has_target, position, normal, direction}   right-click holding a usable item
##   player_eat     {player, item, hunger, saturation, heal, effects, cancelled}   a meal is finished; values may be changed
##   player_sleep   {player, position, cancelled}             lying down in a bed (position: the bed's foot)
##   player_wake    {player, reason ("moved" | "left bed" | "hurt" | "bed" | "day" | "morning" | "left")}
##   guide_page_unlocked {player, page}                      a guidebook page unlocked for a player
##   guide_page_read {player, page}                          a page read for the first time
##   tutorial_started {player, tutorial}   tutorial_step {player, tutorial, step, index, skipped}
##   tutorial_completed {player, tutorial}   tip_shown {player, tip}
##   milestone_reached {player, milestone, title}
##   ugc_uploaded {player, creation, cancelled, reason}   a player creation arrived; cancel to refuse it
##   ugc_status {id, status, reason, by}   ugc_reported {player, id, reason, details, reports, cancelled}
##   role_changed {player_id, role, added, by}              a role given or taken
##   cheat_detected {player, check, score, detail, cancelled}   an anti-cheat warning or kick (cancel to keep them)
##   player_transfer {player, server, arrival, data, cancelled, reason}   leaving for another server (data may be changed)
##   player_arrived {player, from, arrival, data}           arrived through a transfer ticket from a trusted server
##   night_skipped  {sleepers}                                enough players slept; it is morning now
##   skill_crafted  {player, item, count, quality, score, names, data, product}   crafted by hand; data may be changed
##   item_crafted   {player, item, count}
##   item_durability {player, slot, item, data, amount, reason ("mine" | "attack" | "armor" | ...), cancelled}
##   item_break     {player, slot, item, data}                an item wore out
##   equipment_changed {player, slot, old_item, item}
##   player_appearance {player, appearance}                    what others see; may be changed
##   avatar_change  {player, avatar}                          the player's look was recomputed; avatar may be changed
##   player_stats   {player, stats}                           stats may be changed (see ItemRegistry.BASE_STATS)
##   block_break / block_broken also carry {item, slot} (the held tool) and block_broken {harvested}
##   item_drop      {player, item, count, cancelled}          Q key
##   item_pickup    {player, entity, item, count, cancelled}
##   player_attack  {player, target, target_kind ("entity" | "player"), item, damage, cancelled}   damage may be changed
##   player_damage  {player, amount, cause, attacker, cancelled}   amount may be changed; cause: attack, mob,
##                  projectile, fall, void, starvation, magic, ...
##   player_death   {player, cause, attacker, keep_inventory, message}   keep_inventory and message may be changed
##   player_respawn {player, position}                        position may be changed
##   entity_spawned {entity}          entity_removed {entity}
##   entity_damage  {entity, amount, cause, attacker, cancelled}
##   entity_death   {entity, cause, attacker, drops: [[id, count, data]...]}   drops may be changed
##   loot_generated {position, table, player}                a chest rolled its loot
##   loot_first_time {player, table, source}                 this player met that table for the first time
##   rare_loot      {player, item, count, table, position, announce}   an unlikely drop; set announce false to stay quiet
##   entity_interact {player, entity, item, cancelled}        right-click on an entity (cancel stops feeding it)
##   entity_fed     {player, entity, item, cancelled}         breeding food given (see engine/server/breeding.gd)
##   entity_bred    {parents, baby, player}   entity_grew {entity}
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
const BiomeGenerator = preload("res://engine/server/worldgen/biome_generator.gd")
const CaveCarver = preload("res://engine/server/worldgen/cave_carver.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")

var mod_id: String
var mod_dir: String
var manifest: Dictionary
## True while the mod's setup re-runs for a quick reload (see engine/server/mod_reload.gd): blocks,
## items and entities that exist update in place; things that cannot change live are skipped and noted.
var reloading := false
var reload_notes: Array[String] = []

var _server


func _init(server, mod_manifest: Dictionary) -> void:
	_server = server
	manifest = mod_manifest
	mod_id = mod_manifest.id
	mod_dir = mod_manifest.dir


# --- General ------------------------------------------------------------------------------------

## Logs a line from this mod (console, <world>/logs/latest.log and the dev tools).
func info(message) -> void:
	_server.dev_log.add("info", mod_id, str(message))


## Debug drawing for developers (shown to admins with the dev overlay's Draw toggle on; cheap when
## nobody watches). Shapes expire after `seconds`. Colors are "#rrggbb" or "#rrggbbaa".
func debug_box(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0, label := "") -> void:
	_server.dev_tools.draw(mod_id, {"type": "box", "min": from, "max": to, "color": color, "seconds": seconds})
	if not label.is_empty():
		debug_text((from + to) * 0.5 + Vector3(0, absf(to.y - from.y) * 0.5 + 0.3, 0), label, color, seconds)


## A debug line between two points (see debug_box).
func debug_line(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0) -> void:
	_server.dev_tools.draw(mod_id, {"type": "line", "from": from, "to": to, "color": color, "seconds": seconds})


## A debug label floating at a position, always facing the camera (see debug_box).
func debug_text(position: Vector3, text: String, color := "#ffffff", seconds := 2.0) -> void:
	_server.dev_tools.draw(mod_id, {"type": "text", "position": position, "text": text, "color": color, "seconds": seconds})


## A debug path through a list of points (Vector3 or [x, y, z]), with a dot at each (see debug_box).
func debug_path(points: Array, color := "#60ff90", seconds := 2.0) -> void:
	_server.dev_tools.draw(mod_id, {"type": "path", "points": points, "color": color, "seconds": seconds})


## A debug wire sphere (see debug_box).
func debug_sphere(center: Vector3, radius := 0.5, color := "#6090ff", seconds := 2.0) -> void:
	_server.dev_tools.draw(mod_id, {"type": "sphere", "center": center, "radius": radius, "color": color, "seconds": seconds})


## Log levels for authors: debug lines only appear with `/log level <mod> debug` (or --log-level).
## Messages go to the server console, <world>/logs/latest.log and the dev tools.
func debug(message) -> void:
	_server.dev_log.add("debug", mod_id, str(message))


## Logs a warning from this mod (shown in yellow in the dev tools).
func warn(message) -> void:
	_server.dev_log.add("warn", mod_id, str(message))


## Logs an error from the mod (grouped like script errors and shown to admins).
func error(message) -> void:
	var stack := []
	var file := ""
	var line := 0
	for bt in Engine.capture_script_backtraces():
		for i in bt.get_frame_count():
			if bt.get_frame_file(i).ends_with("engine/server/mod_api.gd"):
				continue
			if file.is_empty():
				file = bt.get_frame_file(i)
				line = bt.get_frame_line(i)
			stack.append("%s:%d in %s()" % [bt.get_frame_file(i), bt.get_frame_line(i), bt.get_frame_function(i)])
		break
	_server.dev_log.report_error(mod_id, str(message), file, line, stack)


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
## Beds: `bed: true` (right-click sets the respawn point and sleeps at night). Two-block pieces:
## `pair: {block, direction: "back" | "front" | "up" | "down"}` places `block` next to it (relative to
## the facing of an `orientation: "horizontal"` block) and removes both together; give the second half
## the opposite direction and `placeable: false`.
## `contact_damage: {amount, interval, cause}` hurts players and mobs whose body is inside the block
## (lava).
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
	if def.has("container"):
		d.container = _qualify_ref(String(def.container))
		d.interactive = true
	if def.has("station") or bool(def.get("bed", false)):
		d.interactive = true
	if def.get("pair") is Dictionary:
		d.pair = {"block": _qualify_ref(str(def.pair.get("block", ""))), "direction": str(def.pair.get("direction", "back"))}
	if reloading:
		if _server.registry.id_of(d.name) < 0:
			reload_notes.append("new block %s needs a full reload (/reload full)" % d.name)
			return -1
		return _server.registry.register(d, true)
	return _server.registry.register(d)


## Registers a non-block item. `icon` is a texture path; `usable` makes right-click fire item_use.
## Returns the item id (>= 256), or -1.
func register_item(item_name: String, def: Dictionary) -> int:
	var d := def.duplicate(true)
	d.name = _qualify(item_name)
	for key in ["icon", "model", "armor_texture"]:
		if not String(def.get(key, "")).is_empty():
			d[key] = register_asset(def[key])
	if def.get("effects") is Dictionary:
		for hook in def.effects:
			d.effects[hook] = _qualify_ref(String(def.effects[hook]))
	if reloading:
		if _server.items.id_of(d.name) < 0:
			reload_notes.append("new item %s needs a full reload (/reload full)" % d.name)
			return -1
		return _server.items.register(d, true)
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
	if reloading:
		if _server.entities.registry.id_of(d.name) < 0:
			reload_notes.append("new entity %s needs a full reload (/reload full)" % d.name)
			return -1
		return _server.entities.registry.register(d, true)
	return _server.entities.registry.register(d)


## Registers a sound from one or more audio files in the mod folder (.ogg or .wav; a random one plays
## each time). options: volume (0-2), pitch, pitch_variance, range (blocks). Returns the sound id.
func register_sound(sound_name: String, files, options := {}) -> int:
	if reloading and _server.sounds.id_of(_qualify(sound_name)) >= 0:
		return _server.sounds.id_of(_qualify(sound_name))
	if _static_during_reload("sound", _qualify(sound_name)):
		return -1
	var d := options.duplicate()
	d.name = _qualify(sound_name)
	var assets := []
	for f in (files if files is Array else [files]):
		assets.append(register_asset(String(f)))
	d.files = assets
	return _server.sounds.register(d)


## Registers a visual effect: particle emitters, light flash, camera shake and sound (see
## engine/shared/effect_registry.gd). Emitter textures are paths in this mod or "soft", "spark",
## "star", "square". Returns the effect id, or -1.
func register_effect(effect_name: String, def: Dictionary) -> int:
	if reloading and _server.effects.id_of(_qualify(effect_name)) >= 0:
		return _server.effects.id_of(_qualify(effect_name))
	if _static_during_reload("effect", _qualify(effect_name)):
		return -1
	var d := def.duplicate(true)
	d.name = _qualify(effect_name)
	if def.get("sound") is String:
		d.sound = _qualify_ref(def.sound)
	if def.get("emitters") is Array:
		for e in d.emitters:
			if e is Dictionary and e.get("texture") is String and not e.texture in ["soft", "spark", "star", "square"]:
				e.texture = register_asset(e.texture)
	return _server.effects.register(d)


## Sets off an explosion (see engine/server/explosions.gd): power ~3 is a mob blast. options: source,
## break_blocks, drop_chance, damage (multiplier), effect, sound. Returns the explosion event.
func explode(position: Vector3, power: float, options := {}) -> Dictionary:
	return _server.explosions.explode(position, power, options)


## Plays an effect for everyone in range. options: color ("#rrggbb", tints it), scale, direction
## (Vector3), duration (seconds for continuous emitters), follow (an entity or player it moves with).
## Built in: engine:hit, engine:crit, engine:smoke, engine:sparkle, engine:magic, engine:heal,
## engine:dust, engine:explosion.
func play_effect(effect_name: String, position: Vector3, options := {}) -> void:
	_server.play_effect(_qualify_ref(effect_name), position, options)


## Makes blocks of a type change over time. `handler(ctx)` gets {position, block, state, ticks, reason,
## payload}: "random" ticks come about every options.interval seconds (default 30) per block, and a
## chunk that was unloaded hands each block the ticks it missed at once (`ticks` > 1) unless
## options.catch_up is false; "scheduled" ticks come from schedule_block_tick.
func register_block_tick(block_name: String, handler: Callable, options := {}) -> void:
	var id := block(block_name)
	if id <= 0:
		push_error("[%s] register_block_tick: unknown block '%s'" % [mod_id, block_name])
		return
	_server.block_ticks.register(id, handler, options, mod_id)


## Calls the tick handler of the block at `position` after `seconds`, with `payload` (saved with the world).
func schedule_block_tick(position: Vector3i, seconds: float, payload := {}) -> void:
	_server.block_ticks.schedule(position, seconds, payload)


## Light level 0-15 at a position right now: block light or sky light scaled by daylight, whichever is
## brighter. An estimate (no occlusion) meant for growth and spawning rules.
func get_light(position: Vector3i) -> int:
	return _server.block_ticks.light_at(position, get_daylight())


## {sky, block} light levels 0-15 (sky not scaled by the time of day).
func get_light_levels(position: Vector3i) -> Dictionary:
	return _server.block_ticks.light_levels(position)


## Seconds of world time that have passed (keeps counting across restarts, not while stopped).
func get_world_clock() -> float:
	return _server.block_ticks.clock


## Breaks a block as if mined without a player: drops its items (when `drop`) and plays its sound.
## Fires block_destroyed {position, block, drops} (drops may be changed).
func break_block(position: Vector3i, drop := true) -> void:
	_server.break_block(position, drop)


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


## The entity with this id, or null if it is gone.
func get_entity(entity_id: int):
	return _server.entities.entities.get(entity_id)


## Replaces the player character rig for this server (see engine/shared/player_rig.gd).
func set_player_rig(def: Dictionary) -> void:
	if _static_during_reload("player rig", "", true):
		return
	_server.set_player_rig(def)


## Registers a server cosmetic players can wear on this server (see engine/shared/cosmetics.gd for
## the def: category, paint, pixels, boxes, texture, model, color, covers, unlocked...). `texture` and
## `model` are paths in this mod. `unlocked: false` makes it wearable only after player.grant_cosmetic.
## Returns the cosmetic's full name ("mod:name"), or "" when invalid.
func register_cosmetic(cosmetic_name: String, def: Dictionary) -> String:
	if _static_during_reload("cosmetic", _qualify(cosmetic_name), true):
		return _qualify(cosmetic_name)
	var d := def.duplicate(true)
	d.name = _qualify(cosmetic_name)
	for key in ["texture", "model"]:
		if not String(def.get(key, "")).is_empty():
			d[key] = register_asset(def[key])
	return _server.cosmetics.register(d)


## Adds a cosmetic category. def: display_name, attach (rig attachment point for boxes and models),
## covers (armor slots its cosmetics replace by default).
func register_cosmetic_category(category_name: String, def := {}) -> bool:
	if reloading:
		return false
	var d := def.duplicate()
	d.name = category_name
	return _server.cosmetics.register_category(d)


## Sets how cosmetics work on this server. values (any subset):
##   allow_builtin: players may wear built-in cosmetics (their own look from other servers)
##   allow_colors:  players may recolor cosmetics and choose skin colors
##   armor: "player" (each player chooses per slot), "armor" (armor always shows), "cosmetics"
##   blocked: [cosmetic names or categories]
##   uniform: avatar data laid over every player, e.g. {wear: {shirt: {id: "builtin:tshirt", color: "#d94c4c"}}}
## For per-player looks (teams, disguises) use player.set_avatar_override or the avatar_change event.
func set_cosmetics_policy(values: Dictionary) -> void:
	_server.set_cosmetics_policy(values)


## Adds an equipment slot (after head, chest, legs, feet, offhand). Items with a matching
## `equip_slot` go in it; its modifiers apply while worn. def: display_name.
func register_equipment_slot(slot_name: String, def := {}) -> void:
	if reloading:
		return
	var d := def.duplicate()
	d.name = slot_name
	_server.items.register_slot(d)


## Adds a player stat with a base value. Items and effects change it with modifiers; read it with
## player.get_stat(name). Engine stats: see ItemRegistry.BASE_STATS.
func register_stat(stat_name: String, base: float) -> void:
	if reloading:
		return
	_server.items.register_stat(stat_name, base)


## Registers a mob behaviour that mobs listing it in ai.behaviors can choose. `def`:
##   score:  Callable(brain) -> float   utility each think; the highest scoring behaviour runs.
##           Engine scores: idle 0.05, wander 0.1, investigate 0.4, search <= 0.65, engage 0.7-0.9,
##           return_home 0.95+, flee 1.05, scripted 1.2
##   update: Callable(brain, delta)     called each think while it runs; use brain.move_to / stop /
##           look_at, brain.target, brain.entity, brain.can_see_target(), brain.health_fraction()
##   stop:   Callable(brain)            optional, when another behaviour takes over
func register_mob_behavior(behavior_name: String, def: Dictionary) -> void:
	_server.entities.ai.custom_behaviors[_qualify_ref(behavior_name) if behavior_name.contains(":") else _qualify(behavior_name)] = {
		"score": def.get("score", Callable()), "update": def.get("update", Callable()), "stop": def.get("stop", Callable()), "owner": mod_id}


## Lets mobs hear something at `position` (they come to investigate). `source` may be a player.
func make_noise(position: Vector3, radius: float, source = null) -> void:
	_server.entities.ai.make_noise(position, radius, source)


## Natural spawning. def: entity (name), category ("monster" | "animal" | "ambient" | "misc"; default
## from the mob's AI), light [min, max] (0-15; monsters default to [0, 7] so torches keep them away,
## animals to [9, 15]), place ("any" | "surface" | "underground"), time ("night" | "day" | "any"), on
## (block names the mob may stand on; default any), group [min, max] (pack size), max_nearby (per
## player), max_total, chance (per player per second), min_distance, max_distance. See
## engine/server/spawning.gd for caps and despawning.
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
	rule.owner = mod_id
	_server.entities.add_spawn_rule(rule)


## How many mobs of each category may be around each player: {monster, animal, ambient, misc}.
func set_spawn_caps(caps: Dictionary) -> void:
	_server.entities.spawning.set_caps(caps)


## Game-wide rules: item_drops ("entity" | "inventory"), keep_inventory, pvp, fall_damage,
## natural_regeneration, mob_spawning.
func set_gameplay(values: Dictionary) -> void:
	_server.set_gameplay(values)


## A gameplay rule's current value (see set_gameplay), or null.
func get_gameplay(rule: String):
	return _server.gameplay.get(rule)


## Looks up any block or item id by name ("base:coal", or a local name). -1 if unknown.
func item(item_name: String) -> int:
	return _server.items.id_of(item_name if item_name.contains(":") else _qualify(item_name))


## The full name ("mod:name") of a block or item id, or "".
func item_name(id: int) -> String:
	return _server.items.name_of(id)


## How many of this item fit in one slot.
func item_max_stack(id: int) -> int:
	return _server.items.max_stack(id)


## The name players see for a block or item id.
func item_display_name(id: int) -> String:
	return _server.items.display_name(id)


## Shapeless recipe: `inputs` maps item names to counts. Appears in the engine crafting menu (C key).
## options: pattern (["C", "S"]) with key ({"C": "base:coal", "S": "base:stick"}) makes the recipe shaped for
## the experimentation grid (its inputs are counted from the pattern; pass {} as inputs), unlock ("known" | "pickup" (default) | "blueprint" | "experiment" | "secret") and hint (text
## shown while undiscovered) for recipe discovery, time (seconds in the station's queue; more players there craft faster), project (built
## together: players contribute ingredients over time, see project_completed), tier (minimum station
## tier), needs ([station features]), station (name of the crafting station block needed, e.g. "crafting_table"; blocks declare
## `station: "<name>"`; without one it is crafted anywhere), category (recipe book tab: tools, weapons,
## armor, blocks, food, materials, misc or one from register_recipe_category), id (defaults to
## "<mod>:<output name>").
func register_recipe(inputs: Dictionary, output: String, count := 1, options := {}) -> void:
	var resolved := {}
	var pattern := []
	if options.get("pattern") is Array and options.get("key") is Dictionary:
		# Shaped: rows of characters, the key maps characters to items; inputs are counted from it.
		inputs = {}
		for row in (options.pattern as Array).slice(0, 3):
			var ids := []
			for ch in str(row).left(3):
				var id := item(str(options.key.get(ch, ""))) if ch != " " else 0
				if ch != " " and id <= 0:
					push_error("[%s] Recipe pattern key '%s' is unknown" % [mod_id, ch])
					return
				ids.append(id)
				if id > 0:
					var named := item_name(id)
					inputs[named] = int(inputs.get(named, 0)) + 1
			pattern.append(ids)
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
	var recipe_id := str(options.get("id", output.get_slice(":", 1) if output.contains(":") else output))
	_server.add_recipe(resolved, out, count, String(options.get("station", "")),
		{"category": str(options.get("category", "")), "id": recipe_id if recipe_id.contains(":") else _qualify(recipe_id),
			"tier": int(options.get("tier", 0)), "needs": options.get("needs", []), "time": float(options.get("time", 0.0)),
			"project": bool(options.get("project", false)), "unlock": str(options.get("unlock", "pickup")), "hint": str(options.get("hint", "")),
			"pattern": pattern, "owner": mod_id, "skill": _qualify_ref(str(options.get("skill", ""))) if not str(options.get("skill", "")).is_empty() else ""})


## A material parts can be made of: {display_name, item (raw material item name), color, tier, speed,
## durability, damage, handle (durability multiplier as a handle), trait: {name, description, modifiers,
## durability_mult, speed_mult, damage_add, glow}}. Every part type gets a recipe for it.
func register_material(material_name: String, def: Dictionary) -> void:
	var d := def.duplicate(true)
	d.item = item(str(def.get("item", "")))
	_server.assembly.add_material(_qualify_ref(material_name) if material_name.contains(":") else _qualify(material_name), d)


## A kind of part (registers the part item): {display_name, sprite (grayscale 16x16 image tinted by the
## material), cost (material per part), station (where parts are made)}.
func register_part_type(part_name: String, def: Dictionary) -> int:
	var sprite := register_asset(str(def.get("sprite", "")))
	var id := register_item(part_name, {"display_name": def.get("display_name", part_name.capitalize()), "icon": def.get("sprite", "")})
	var d := def.duplicate(true)
	d.sprite = sprite
	d.item = id
	_server.assembly.add_part_type(_qualify(part_name), d)
	return id


## A tool or weapon built from parts (registers its item): {display_name, icon (shown for plain
## stacks), slots: [{name, part, label}], tool_type, damage, cooldown, reach, sweep, station}. The
## first slot is the head. Part names without ":" are this mod's.
func register_assembly(assembly_name: String, def: Dictionary) -> int:
	var id := register_item(assembly_name, {"display_name": def.get("display_name", assembly_name.capitalize()), "icon": def.get("icon", ""),
		"durability": 1, "weapon": {"damage": float(def.get("damage", 1.0)), "cooldown": float(def.get("cooldown", 0.5))},
		"tool": {"type": str(def.get("tool_type", "")), "tier": 0, "speed": 1.0} if not str(def.get("tool_type", "")).is_empty() else {}})
	var d := def.duplicate(true)
	d.item = id
	var slots := []
	for s in (def.get("slots") if def.get("slots") is Array else []):
		var slot: Dictionary = s.duplicate()
		slot.part = _qualify_ref(str(s.get("part", "")))
		slots.append(slot)
	d.slots = slots
	d.skill = _qualify_ref(str(def.get("skill", "")))
	_server.assembly.add_assembly(_qualify(assembly_name), d)
	return id


## A crafting minigame recipes and assemblies can name as their `skill` (crafting by hand for better
## quality; see engine/shared/minigame.gd): {title, type: "timing" | "hold" | "sequence", verb, rounds,
## speed, zone, cool, team (bellows + hammer), duration, window}.
func register_minigame(minigame_name: String, def: Dictionary) -> void:
	_server.skill.register(_qualify(minigame_name), def)


## Makes a station upgradable (see engine/server/stations.gd): tiers [{block, title, kit, grants}],
## workshop {radius, upgrades: [{block, title, max, grants}]}, multiblock {core, pattern, legend,
## title}. grants: {features, tier, speed, quality, pull_radius, hints}. Blocks involved still declare
## `station: "<name>"`. Recipes then ask for `tier` and `needs` (features).
func register_station(station_name: String, def: Dictionary) -> void:
	_server.stations.register(station_name, def)


## The station at a position: {name, title, tier, tier_title, features, speed, quality, pull_radius,
## hints, detected, available, next, structure}, or {}.
func get_station(position: Vector3i) -> Dictionary:
	return _server.stations.evaluate(position)


## Adds a recipe book tab. def: display_name, icon (item name shown on the tab).
func register_recipe_category(category_name: String, def := {}) -> bool:
	var d := def.duplicate()
	d.name = category_name
	if def.get("icon") is String:
		d.icon = item(def.icon)
	return _server.recipes.register_category(d)


## Puts a marker on a player's map and compass (it stays until removed).
## `marker` = {label, position, color, dimension}. Markers are per player, so a home or a grave only shows
## to whoever it belongs to. `dimension` ("" = the ordinary world) hides it while they are somewhere else.
func set_map_marker(player, marker_id: String, marker: Dictionary) -> void:
	if player == null or String(player.player_id).is_empty():
		return
	var id := _qualify(marker_id)
	if not _server.map_markers.has(player.player_id):
		_server.map_markers[player.player_id] = {}
	_server.map_markers[player.player_id][id] = {"label": String(marker.get("label", marker_id)).left(32),
		"position": marker.get("position", Vector3.ZERO), "color": String(marker.get("color", "#ffd166")).left(9),
		"dimension": String(marker.get("dimension", _server.dimension_of(player)))}


## Takes a marker off a player's map.
func clear_map_marker(player, marker_id: String) -> void:
	if player != null and _server.map_markers.has(player.player_id):
		_server.map_markers[player.player_id].erase(_qualify(marker_id))


## Puts a marker on everyone's map and compass (a village, a shared base, an event). Saved with the world.
## `marker` = {label, position, color, dimension} ("" = the ordinary world).
func set_world_marker(marker_id: String, marker: Dictionary) -> void:
	var id := _qualify(marker_id)
	var at = marker.get("position", Vector3.ZERO)
	_server.world_markers[id] = {"label": String(marker.get("label", marker_id)).left(32),
		"position": [snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1)],
		"color": String(marker.get("color", "#ffd166")).left(9), "dimension": String(marker.get("dimension", ""))}


## Takes a marker off everyone's map.
func clear_world_marker(marker_id: String) -> void:
	_server.world_markers.erase(_qualify(marker_id))


## Registers a container type (see engine/server/containers.gd): {title, groups: [{name, count,
## columns, label, take_only, accepts}], progress: [{name, label, color}]}. Blocks use it with
## `container: "<name>"` and open it on right-click. Names without ":" are this mod's.
func register_container(container_name: String, def: Dictionary) -> bool:
	var d := def.duplicate(true)
	for g in (d.get("groups") if d.get("groups") is Array else []):
		if g is Dictionary and g.get("accepts") is Array:
			g.accepts = (g.accepts as Array).map(func(n): return _qualify_ref(String(n)))
	return _server.containers.register(_qualify(container_name), d)


## The container at a position (engine/server/container.gd), or null.
func get_container(position: Vector3i):
	return _server.containers.get_container(position)


## Opens a container's screen for a player (as if they right-clicked it).
func open_container(player, position: Vector3i) -> bool:
	return _server.containers.open(player, position)


## Makes an item burn in fuel slots for `seconds`.
func set_fuel(item_name: String, seconds: float) -> void:
	var id := item(item_name)
	if id > 0:
		_server.set_fuel(id, seconds)


## How many seconds an item burns in a furnace (0 = not fuel).
func get_fuel(item_id: int) -> float:
	return _server.get_fuel(item_id)


## A processing recipe machines look up by kind: register_process("smelting", "base:iron_ore",
## "base:iron_ingot", 1, 10.0).
func register_process(kind: String, input: String, output: String, count := 1, seconds := 10.0) -> void:
	var input_id := item(input)
	var output_id := item(output)
	if input_id <= 0 or output_id <= 0:
		push_error("[%s] Process '%s': unknown item '%s' or '%s'" % [mod_id, kind, input, output])
		return
	_server.add_process(kind, input_id, output_id, count, seconds)


## {output, count, seconds} for an input, or {} when that kind of machine cannot process it.
func get_process(kind: String, item_id: int) -> Dictionary:
	return _server.get_process(kind, item_id)


## Makes a file from this mod's folder downloadable by clients. Returns its asset name.
func register_asset(relative_path: String) -> String:
	if reloading and not relative_path.contains(":") and not _server._assets.has("%s:%s" % [mod_id, relative_path]):
		reload_notes.append("new file %s needs a full reload (/reload full)" % relative_path)
	if relative_path.contains(":"):
		return relative_path  # already an asset name from another mod
	var asset_name := "%s:%s" % [mod_id, relative_path]
	_server.add_asset(asset_name, mod_dir.path_join(relative_path))
	return asset_name


## Looks up a block id by name ("base:stone", or "stone" for this mod's own). -1 if unknown.
## The texture names a block uses, so a slab or stairs can be made of the same material.
func block_textures(block_name: String) -> Array:
	var id := block(block_name)
	return (_server.registry.defs[id].textures as Array).duplicate() if _server.registry.is_valid(id) else []


func block(block_name: String) -> int:
	return _server.registry.id_of(block_name if block_name.contains(":") else _qualify(block_name))


## The full name ("mod:name") of a block id, or "".
func block_name(id: int) -> String:
	return _server.registry.defs[id].name if _server.registry.is_valid(id) else ""


## The name players see for a block id.
func block_display_name(id: int) -> String:
	return _server.registry.display_name(id)


# --- World --------------------------------------------------------------------------------------

## `generator` must implement `generate(chunk)`; write into a local copy of `chunk.blocks`
## (index with Chunk.index(x, y, z)) and assign it back for speed.
func set_world_generator(generator: Object) -> void:
	if _static_during_reload("world generator", "", true):
		return
	_server.generator = generator


## Turns on the engine biome generator (engine/server/worldgen/biome_generator.gd) for this world.
## options: sea_level, snow_level. Register biomes and features before or after; returns the generator.
func use_biome_generator(options := {}) -> Object:
	if reloading and _server.biome_generator != null:
		return _server.biome_generator
	var gen = biome_generator()
	gen.sea_level = int(options.get("sea_level", gen.sea_level))
	gen.snow_level = int(options.get("snow_level", gen.snow_level))
	_server.generator = gen
	return gen


## The shared biome generator (created on first use, even if the game uses its own generator).
func biome_generator() -> Object:
	if _server.biome_generator == null:
		_server.biome_generator = BiomeGenerator.new(_server.world_seed, func(n: String) -> int: return block(n) if n.contains(":") else block(n), _server.registry)
	return _server.biome_generator


## A biome for the biome generator: {climate, ocean, height, surface, features, plants}. See BiomeGenerator.
func register_biome(biome_name: String, def: Dictionary) -> void:
	if reloading:
		return  # world generation is fixed once the world runs (a full reload applies changes)
	var d := def.duplicate(true)
	d.features = (def.get("features", []) as Array).map(func(f): return f.merged({"feature": _qualify_ref(str(f.get("feature", "")))}, true) if f is Dictionary else f) \
		if def.get("features") is Array else []
	biome_generator().add_biome(_qualify(biome_name), d)


## Carves caves, caverns and ravines into the biome generator's terrain (see worldgen/cave_carver.gd).
## options: tunnels, caverns, ravines (bools), lava (block name), lava_level, water_level, min_y,
## entrance_chance.
func add_cave_carver(options := {}) -> void:
	if reloading:
		return
	biome_generator().carvers.append(CaveCarver.new(_server.world_seed, func(n: String) -> int: return block(n), _server.registry, options))


## A structure template: a JSON file in this mod (e.g. "structures/tower.json", saved with /struct save)
## or a template dictionary. Names without ":" are this mod's.
func register_structure_template(template_name: String, source) -> bool:
	if reloading:
		return true
	var doc = source
	if source is String:
		var path := mod_dir.path_join(source)
		doc = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (doc is Dictionary) or not biome_generator().structures.add_template(_qualify(template_name), doc):
		push_error("[%s] register_structure_template: invalid template %s" % [mod_id, template_name])
		return false
	return true


## Generated structures (see worldgen/structures.gd): {templates: [{template, weight}] or generator
## (GDScript Callable), spacing, separation, biomes, place, y, sink, foundation, swaps, reach, chance}.
## Stamps a template into the world now, rotated a quarter turn at a time (0-3). What `/struct place`
## does, for a mod that wants to build something itself rather than leave it to world generation: a
## story's outpost, a rescue site, a prize somebody hid.
func place_structure(template_name: String, at: Vector3i, rotation := 0) -> bool:
	return _server.structure_tools.place(_qualify_ref(template_name), at, rotation)


func register_structure(structure_name: String, def: Dictionary) -> void:
	if reloading:
		return  # world generation is fixed once the world runs (a full reload applies changes)
	var d := def.duplicate(true)
	if def.get("templates") is Array:
		d.templates = (def.templates as Array).map(func(t): return t.merged({"template": _qualify_ref(str(t.get("template", "")))}, true) if t is Dictionary else t)
	biome_generator().structures.add_set(_qualify(structure_name), d)


## Declares what something gives: a mob that dies, a block that breaks, a chest, a reward (docs/loot.md).
##
##   api.register_loot("zombie", {"pools": [
##       {"rolls": [0, 2], "entries": [{"item": "base:rotten_flesh", "count": [1, 2], "weight": 3},
##                                     {"empty": true, "weight": 1}]},
##       {"rolls": 1, "when": {"killed_by": "player"}, "entries": [{"item": "base:iron_ingot", "weight": 1},
##                                                                 {"empty": true, "weight": 20}]},
##   ]})
##
## Pools roll on their own, so each is one idea ("some flesh" / "rarely, iron"). An entry names an `item`,
## another `table` to roll instead, or `empty: true` for the miss; `weight` is relative within its pool,
## `count` is a number or [min, max], `data` is the item data the stack carries. `when` on a pool or an
## entry takes killed_by, tool, biome, depth, time, chance and first_time. An entity or block can name its
## table with `loot: "<name>"`; without one, its `drops` list is read as a table.
## Tables can also be JSON files: every loot/*.json in the mod folder registers as "<mod>:<file name>".
func register_loot(table_name: String, def: Dictionary) -> void:
	_server.loot.register(_qualify_ref(table_name), def)


## Same as register_loot (the name it had before tables were used for everything).
func register_loot_table(table_name: String, def: Dictionary) -> void:
	register_loot(table_name, def)


## Adds pools to a table another mod owns, without forking it: an extra drop on their mob, a bonus in
## their dungeon chests.
func extend_loot(table_name: String, def: Dictionary) -> void:
	_server.loot.extend(_qualify_ref(table_name), def, mod_id)


## Rolls a table and returns [[item id, count, data], …], for anything the engine does not roll itself
## (fishing, a quest reward, a prize crate). `context` may carry player, cause, tool, position and seed.
func roll_loot(table_name: String, context := {}) -> Array:
	return _server.loot.roll(_qualify_ref(table_name), context)


## What a mob, block or table gives, without rolling: everything it could drop, as
## [{item, chance, count, table}]. This is what the guide's "what drops this?" is built from.
func loot_sources(item_name: String) -> Array:
	return _server.loot.sources_of(_server.items.id_of(_qualify_ref(item_name)))


## How much everything drops, as a multiplier (1.0 is normal). A host's "how much loot" setting.
func set_loot_rate(multiplier: float) -> void:
	_server.loot.rate = clampf(multiplier, 0.0, 10.0)


func get_loot_rate() -> float:
	return _server.loot.rate


## Turns one thing up (or down) for a while, for an event: `target` is a table or an item name, `factor`
## how much more often it comes up, `seconds` how long (0: until it is changed back).
##
##   api.set_loot_boost("base:coal", 3.0, 3600.0)     # coal everywhere, for an hour
##   api.set_loot_boost("vanilla:dungeon", 2.0)       # richer dungeon chests until further notice
func set_loot_boost(target: String, factor: float, seconds := 0.0) -> void:
	_server.loot.set_boost(_qualify_ref(target), factor, seconds)


## A guidebook chapter: {title, icon (item name), order, description}. Names without ":" are this mod's.
func register_guide_chapter(chapter_name: String, def := {}) -> bool:
	var d := def.duplicate(true)
	d.id = _qualify_ref(chapter_name)
	d.owner = mod_id
	if def.get("icon") is String and not def.icon.is_empty():
		d.icon = _qualify_ref(def.icon)
	return _server.guide.registry.add_chapter(d)


## A guidebook page (see engine/shared/guide_registry.gd): {chapter, title, icon, order, unlock: {item (a
## name or a list of names, any of which opens it) |
## recipe | entity | flag | page}, hint, keywords, blocks: [{type: text | heading | items | recipe |
## entity | image | tip | link | keys, ...}]}. Item, entity, page and flag names without ":" are this
## mod's; image blocks take a texture path in this mod.
func register_guide_page(page_name: String, def: Dictionary) -> bool:
	var d := def.duplicate(true)
	d.id = _qualify_ref(page_name)
	d.owner = mod_id
	d.chapter = _qualify_ref(str(def.get("chapter", "")))
	if def.get("icon") is String and not def.icon.is_empty():
		d.icon = _qualify_ref(def.icon)
	if def.get("unlock") is Dictionary:
		var u := {}
		for key in def.unlock:
			# An unlock may name one thing or several, any of which opens the page.
			var value = def.unlock[key]
			u[key] = (value as Array).map(func(v): return _qualify_ref(str(v))) if value is Array else _qualify_ref(str(value))
		d.unlock = u
	var blocks := []
	for b in (def.get("blocks") if def.get("blocks") is Array else []):
		if not (b is Dictionary):
			continue
		var c: Dictionary = b.duplicate(true)
		if c.get("items") is Array:
			c.items = (c.items as Array).map(func(n): return _qualify_ref(str(n)))
		for key in ["output", "entity", "page"]:
			if c.has(key):
				c[key] = _qualify_ref(str(c[key]))
		if str(c.get("type", "")) == "image" and c.get("asset") is String:
			c.asset = register_asset(c.asset)
		blocks.append(c)
	d.blocks = blocks
	return _server.guide.registry.add_page(d)


## Opens the guidebook for a player at a page ("" = where they left off).
func open_guide(player, page := "") -> void:
	_server.guide.open(player, _qualify_ref(page))


## Guide flags unlock pages with `unlock: {flag}` (names without ":" are this mod's). Saved per player.
func set_guide_flag(player, flag: String, on := true) -> void:
	_server.guide.set_flag(player, _qualify_ref(flag), on)


## Whether a player has a guide flag (see set_guide_flag).
func has_guide_flag(player, flag: String) -> bool:
	return _server.guide.has_flag(player, _qualify_ref(flag))


## Unlocks a guide page for a player whatever its condition. Returns true if it was locked.
func unlock_guide_page(player, page: String, notify := true) -> bool:
	return _server.guide.unlock(player, _qualify_ref(page), notify)


## Whether a guide page is open to a player.
func is_guide_page_unlocked(player, page: String) -> bool:
	return _server.guide.is_unlocked(player, _qualify_ref(page))


## A tutorial: guided goals completed by real actions (see engine/server/tutorials.gd for goal types):
## {title, description, order, auto_start, reward: [[item, count]], steps: [{title, text, icon, goal: {type,
## target, count, ...}, hint: {block | entity | position} or false, page, reward}]}. Names without ":" are
## this mod's.
func register_tutorial(tutorial_name: String, def: Dictionary) -> bool:
	return _server.tutorials.register_tutorial(_qualify_ref(tutorial_name), def.merged({"owner": mod_id}), _qualify_ref)


## A milestone: something a player has done, remembered for the life of the world and paid out once
## (see engine/server/milestones.gd). Goals are written exactly as tutorial goals are - {type, target,
## count}, type being an event goal (break, place, craft, kill, ...) or "event" - but the count is a
## lifetime total. No target means anything of that kind counts.
## {title, description, goal, icon, order, secret (hidden until reached), announce (tell everyone),
## reward: {items: [[item, count]], cosmetic}}. The usual reward is a cosmetic, because a cosmetic is
## something other players can see. Names without ":" are this mod's.
func register_milestone(milestone_name: String, def: Dictionary) -> bool:
	return _server.milestones.register(_qualify_ref(milestone_name), def, _qualify_ref)


## Whether a player has reached a milestone, for gating something behind it.
func milestone_reached(player, milestone_name: String) -> bool:
	return _server.milestones.reached(player, _qualify_ref(milestone_name))


## A one-time contextual tip: {text, icon, page (guide page to read more), trigger: a goal}.
func register_tip(tip_name: String, def: Dictionary) -> bool:
	return _server.tutorials.register_tip(_qualify_ref(tip_name), def.merged({"owner": mod_id}), _qualify_ref)


## Starts (or restarts) a tutorial for a player. Returns false if it does not exist.
func start_tutorial(player, tutorial_name: String) -> bool:
	return _server.tutorials.start(player, _qualify_ref(tutorial_name))


## Stops the player's running tutorial; it will not start by itself again.
func stop_tutorial(player) -> void:
	_server.tutorials.stop(player)


## Completes the player's current tutorial step (for "manual" goals).
func advance_tutorial(player) -> void:
	_server.tutorials.advance(player)


## {active, step, progress, done: [ids]} for a player.
func get_tutorial_state(player) -> Dictionary:
	var s: Dictionary = _server.tutorials.state_of(player)
	return {"active": s.active, "step": s.step, "progress": s.progress, "done": s.done.keys()}


## Shows a registered tip now (even if seen before).
func show_tip(player, tip_name: String) -> bool:
	return _server.tutorials.show_tip(player, _qualify_ref(tip_name))


## How this server treats player creations (engine/server/ugc.gd): {enabled, accept: "auto" | "trusted" |
## "approval" | "off", kinds: ["skin", "accessory", "model"], library (others may wear approved ones),
## max_per_player, max_bytes_per_player}. Saved with the world.
func set_ugc_policy(values: Dictionary) -> void:
	_server.ugc.set_policy(values)


## Player creations for review or rewards: filter pending | reported | approved | rejected | removed | all.
## Each: {id, manifest {kind, category, name, author, author_name}, status, reason, reports, uploaded_by, size}.
func ugc_list(filter := "approved") -> Array:
	return _server.ugc.review_list(filter)


## One creation's record, or {}.
func ugc_get(id: String) -> Dictionary:
	return _server.ugc.store.get(id, {}).duplicate(true)


## Approves, rejects (hidden; the author may upload a fixed version) or removes (blocked for good) a creation.
func ugc_set_status(id: String, status: String, reason := "") -> bool:
	return _server.ugc.set_status(id, {"approve": "approved", "reject": "rejected", "remove": "removed"}.get(status, status), reason, mod_id)


## Files a report as a player (e.g. from a mod's own report button).
func ugc_report(player, id: String, reason := "other", details := "") -> String:
	return _server.ugc.report(player, id, reason, details)


## Trusted creators' uploads skip the approval queue when the policy accepts "trusted".
func ugc_trust(player_id: String, on := true) -> void:
	_server.ugc.set_trusted(player_id, on)


## Stops (or allows again) a player uploading creations; banning also hides their creations.
func ugc_ban(player_id: String, on := true, reason := "") -> void:
	_server.ugc.set_banned(player_id, on, reason, mod_id)


## Describes a permission a mod checks with player.has_permission, and which built-in roles get it by
## default (e.g. ["moderator"]; admins and owners have every permission anyway).
func register_permission(permission: String, description: String, roles := []) -> void:
	_server.roles.descriptions[permission] = description
	for r in roles:
		if _server.roles.BUILTIN.has(str(r)) and not _server.roles._meta().roles.get(str(r), {}).has("permissions"):
			var def: Dictionary = _server.roles.role(str(r))
			if not def.permissions.has(permission):
				def.permissions.append(permission)
				_server.roles._save_role(str(r), {"permissions": def.permissions})


## A player's roles by player id (the default role included).
func player_roles(player_id: String) -> Array:
	return _server.roles.roles_of(player_id)


## Gives (or takes) a role. Returns whether anything changed.
func set_player_role(player_id: String, role: String, on := true) -> bool:
	var changed: bool = _server.roles.give(player_id, role) if on else _server.roles.take(player_id, role)
	if changed:
		_server.emit("role_changed", {"player_id": player_id, "role": role, "added": on, "by": mod_id})
	return changed


## The servers players can travel to from here (network.json): [{key, name, address, port, hop, inventory}].
func network_servers() -> Array:
	return _server.transfers.servers.values().filter(func(e): return e.send).map(func(e):
		return {"key": e.key, "name": e.name, "address": e.address, "port": e.port, "hop": e.hop, "inventory": e.inventory})


## Names a spot where players arriving from other servers can appear (tickets name it as their arrival).
func set_arrival_point(id: String, position: Vector3) -> void:
	_server.transfers.set_arrival(id, position)


## A world feature (tree, cactus, boulder, spike, huge mushroom, patch) as data {type, ...} or, from
## GDScript, a Callable(writer, origin: Vector3i, rng) run on worker threads. See worldgen/features.gd.
func register_feature(feature_name: String, def) -> void:
	if reloading:
		return  # world generation is fixed once the world runs (a full reload applies changes)
	biome_generator().add_feature(_qualify(feature_name), def)


## Name of the biome at a column ("" without the biome generator).
func get_biome(position: Vector3) -> String:
	return _server.biome_generator.biome_at(floori(position.x), floori(position.z)) if _server.biome_generator != null else ""


## `handler(player) -> Vector3` picks the spawn position for players without a saved position.
func set_spawn_handler(handler: Callable) -> void:
	_server.spawn_handler = handler


## Adds a pass run after the world generator for every new chunk, on worker threads:
## `pass_object.decorate(chunk, world_seed)`. Lets add-on mods put ores or structures in any game.
func add_generation_pass(pass_object: Object) -> void:
	if reloading:
		return
	_server.generation_passes.append(pass_object)


## Scatters veins of `ore` inside `replace` in every new chunk. def: ore, replace (block names),
## veins (per chunk), size (blocks per vein), min_y, max_y, chance (per vein, 0-1).
func add_ore_pass(def: Dictionary) -> void:
	if reloading:
		return
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


## Whether a block id collides (unloaded space counts as solid).
func is_solid(block: int) -> bool:
	return block == BlockRegistry.UNLOADED or (_server.registry.is_valid(block) and _server.registry.solid_lut[block] == 1)


## Whether players can break a block id.
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


## Opens the crafting screen for a player, crafting by hand.
func show_crafting(player) -> void:
	_server.show_crafting(player)


## Block data ("block entities"): a Dictionary of JSON-compatible values stored with the world and
## removed automatically when the block is broken or replaced.
func get_block_data(pos: Vector3i) -> Dictionary:
	return _server.get_block_data(pos)


## Replaces the data dictionary stored with the block at a position (saved with the world).
func set_block_data(pos: Vector3i, data: Dictionary) -> void:
	_server.set_block_data(pos, data)


## Removes the data stored with the block at a position.
func clear_block_data(pos: Vector3i) -> void:
	_server.clear_block_data(pos)


## Loaded positions that carry block data, optionally filtered to one block id.
func find_block_data(block := -1) -> Array[Vector3i]:
	return _server.find_block_data(block)


## time_of_day: 0 = midnight, 0.25 = sunrise, 0.5 = noon. day_length in seconds (0 freezes time).
func set_world_time(time_of_day: float, day_length := -1.0) -> void:
	_server.set_world_time(time_of_day, _server.get_day_length() if day_length < 0.0 else day_length)


## The time of day from 0 to 1 (0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset).
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


## Sets every block in the box between two corners (inclusive) to a block id.
func fill(from: Vector3i, to: Vector3i, id: int) -> void:
	for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
		for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
			for z in range(mini(from.z, to.z), maxi(from.z, to.z) + 1):
				_server.set_block_authoritative(Vector3i(x, y, z), id)


## Y of the highest non-air block in the column, or -1.
func surface_y(x: int, z: int) -> int:
	return _server.surface_height(x, z)


# --- Players ------------------------------------------------------------------------------------

## Everyone online (player objects).
func get_players() -> Array:
	return _server.players.values()


## The online player with this name (any case), or null.
func find_player(player_name: String):
	for p in _server.players.values():
		if p.name.to_lower() == player_name.to_lower():
			return p
	return null


## Sends a chat message to everyone.
func broadcast(text: String) -> void:
	_server.broadcast_chat(text)


## More ways of saying that somebody died, so a mod’s own mobs get their own send-off rather than the
## engine’s general one. `key` is a cause ("lava", "fall", "magic") or the name of an entity; the first
## "%s" is the player and a second one is whatever did it. One is picked at random, never the same twice
## running, alongside the lines already there.
##
##   api.add_death_messages("mymod:dragon", ["%s was toasted by %s", "%s argued with %s and lost"])
##
## Keep them kind: say what happened, never what anyone is like. Children read these about themselves.
func add_death_messages(key: String, lines: Array) -> void:
	_server.add_death_messages(_qualify_ref(key), lines)


# --- Settings -----------------------------------------------------------------------------------

## Declares the settings a host may change without editing this mod, as {key: definition}. Each
## definition takes a `type` ("bool", "int", "float", "choice" or "text"), a `label` players see, an
## optional `help` line, a `default`, `min`/`max`/`step` for numbers and `choices` ([[value, label]])
## for a choice. Call it while the mod loads; declaring the same key again updates its definition.
##
##   api.register_settings({
##       "monster_rate": {"label": "How many monsters", "type": "float", "default": 1.0, "min": 0.0, "max": 3.0,
##                        "help": "Multiplies how often monsters appear."},
##       "difficulty":   {"label": "Difficulty", "type": "choice", "default": "normal",
##                        "choices": [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]},
##   })
##
## The server owns the values, so all three ways in agree: mod_settings.json in the server's data
## folder, the /modsettings command, and the admin settings screen. They live in the world, so a world
## carries its own settings and a backup restores them.
func register_settings(schema: Dictionary) -> void:
	_server.mod_settings.register(mod_id, schema)


## This mod's setting, as the host left it (its default until someone changes it). null if not declared.
func setting(key: String):
	return _server.mod_settings.get_value(mod_id, key)


## Every setting of this mod as {key: value}, for passing to something that wants a config dictionary.
func settings() -> Dictionary:
	var out := {}
	for entry in _server.mod_settings.list(mod_id):
		out[entry.key] = entry.value
	return out


## Changes one of this mod's settings from code (the same path the admin screen uses, so handlers of
## `settings_changed` run). Returns "" or why it was refused.
func set_setting(key: String, value) -> String:
	return _server.mod_settings.set_value(mod_id, key, value)


# --- Events, commands, scheduling ---------------------------------------------------------------

## Higher priority runs first.
func on(event: String, handler: Callable, priority := 0) -> void:
	_server.add_handler(event, handler, priority, mod_id)


## `handler(player, args: PackedStringArray)` runs for "/name args...". permission "admin" restricts
## it to server admins (VOXEL_ADMINS, /op, or the local host).
func register_command(command: String, description: String, handler: Callable, permission := "") -> void:
	_server.add_command(command, description, handler, mod_id, permission)


## Runs `callback` once after `seconds`. Returns a task id for `cancel`.
func after(seconds: float, callback: Callable) -> int:
	return _server.schedule(seconds, callback, 0.0, mod_id)


## Runs `callback` every `seconds`. Returns a task id for `cancel`.
func every(seconds: float, callback: Callable) -> int:
	return _server.schedule(seconds, callback, seconds, mod_id)


## Stops a timer started with after or every.
func cancel(task_id: int) -> void:
	_server.cancel_task(task_id)


## During a quick reload: true (skip the call) for registrations that cannot change live; new names
## are noted so the author knows to do a full reload.
func _static_during_reload(kind: String, full_name: String, quiet := false) -> bool:
	if not reloading:
		return false
	if not quiet:
		reload_notes.append("new %s %s needs a full reload (/reload full)" % [kind, full_name])
	return true


func _qualify(local_name: String) -> String:
	return "%s:%s" % [mod_id, local_name]


## Names that already have a namespace ("base:stone", "engine:hurt") are kept as they are.
func _qualify_ref(ref: String) -> String:
	return ref if ref.contains(":") or ref.is_empty() else _qualify(ref)
