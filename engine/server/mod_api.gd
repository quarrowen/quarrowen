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
	if def.has("container"):
		d.container = _qualify_ref(String(def.container))
		d.interactive = true
	if def.has("station"):
		d.interactive = true
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


## Registers a visual effect: particle emitters, light flash, camera shake and sound (see
## engine/shared/effect_registry.gd). Emitter textures are paths in this mod or "soft", "spark",
## "star", "square". Returns the effect id, or -1.
func register_effect(effect_name: String, def: Dictionary) -> int:
	var d := def.duplicate(true)
	d.name = _qualify(effect_name)
	if def.get("sound") is String:
		d.sound = _qualify_ref(def.sound)
	if def.get("emitters") is Array:
		for e in d.emitters:
			if e is Dictionary and e.get("texture") is String and not e.texture in ["soft", "spark", "star", "square"]:
				e.texture = register_asset(e.texture)
	return _server.effects.register(d)


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
	_server.block_ticks.register(id, handler, options)


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


func get_entity(entity_id: int):
	return _server.entities.entities.get(entity_id)


## Replaces the player character rig for this server (see engine/shared/player_rig.gd).
func set_player_rig(def: Dictionary) -> void:
	_server.set_player_rig(def)


## Registers a server cosmetic players can wear on this server (see engine/shared/cosmetics.gd for
## the def: category, paint, pixels, boxes, texture, model, color, covers, unlocked...). `texture` and
## `model` are paths in this mod. `unlocked: false` makes it wearable only after player.grant_cosmetic.
## Returns the cosmetic's full name ("mod:name"), or "" when invalid.
func register_cosmetic(cosmetic_name: String, def: Dictionary) -> String:
	var d := def.duplicate(true)
	d.name = _qualify(cosmetic_name)
	for key in ["texture", "model"]:
		if not String(def.get(key, "")).is_empty():
			d[key] = register_asset(def[key])
	return _server.cosmetics.register(d)


## Adds a cosmetic category. def: display_name, attach (rig attachment point for boxes and models),
## covers (armor slots its cosmetics replace by default).
func register_cosmetic_category(category_name: String, def := {}) -> bool:
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
	var d := def.duplicate()
	d.name = slot_name
	_server.items.register_slot(d)


## Adds a player stat with a base value. Items and effects change it with modifiers; read it with
## player.get_stat(name). Engine stats: see ItemRegistry.BASE_STATS.
func register_stat(stat_name: String, base: float) -> void:
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


func items_name(id: int) -> String:
	return _server.items.name_of(id)


func item_max_stack(id: int) -> int:
	return _server.items.max_stack(id)


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
					var item_name := items_name(id)
					inputs[item_name] = int(inputs.get(item_name, 0)) + 1
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
			"pattern": pattern, "skill": _qualify_ref(str(options.get("skill", ""))) if not str(options.get("skill", "")).is_empty() else ""})


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
	return _server.surface_height(x, z)


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
