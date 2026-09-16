extends "res://engine/server/mod.gd"
## One Block: everyone stands over the void on a single block. Break it and it comes back as something
## else - dirt, then stone and ores, then stranger things - and now and then a creature or a crate of
## treasure instead. Build outwards from whatever you collect.
##
## Every player gets their own block far from the others (like Skyblock's islands). What the block turns
## into comes from the phase table below: a list of [block name, weight] plus the odd surprise.

const BLOCK_SPACING := 512
const BLOCK_Y := 64
const VOID_Y := -12.0
## Blocks to break before the next phase.
const PHASE_LENGTH := 60

## Each phase: what the block turns into (block name, weight), and the surprises it can roll instead.
## Names that this world does not have are skipped, so the mod works with or without the vanilla add-ons.
const PHASES := [
	{"name": "Meadow", "blocks": [["base:dirt", 5], ["base:grass", 4], ["base:log", 2], ["base:leaves", 2], ["base:sand", 1]],
		"mobs": [["vanilla:chicken", 1], ["vanilla:pig", 1]], "mob_chance": 0.06, "crate_chance": 0.04,
		"crate": [["base:apple", 3], ["base:wheat_seeds", 2], ["base:stick", 4]]},
	{"name": "Caves", "blocks": [["base:stone", 6], ["base:cobblestone", 4], ["base:coal_ore", 2], ["base:iron_ore", 1], ["base:gravel", 2]],
		"mobs": [["vanilla:zombie", 1], ["vanilla:spider", 1]], "mob_chance": 0.08, "crate_chance": 0.05,
		"crate": [["base:torch", 4], ["base:coal", 3], ["base:iron_ingot", 1]]},
	{"name": "Depths", "blocks": [["base:stone", 5], ["base:iron_ore", 2], ["base:cobalt_ore", 1], ["base:clay", 2], ["base:gravel", 1]],
		"mobs": [["vanilla:skeleton", 1], ["vanilla:night_stalker", 1]], "mob_chance": 0.09, "crate_chance": 0.06,
		"crate": [["base:iron_ingot", 2], ["base:glass", 4], ["vanilla:bone", 2]]},
	{"name": "Overgrown", "blocks": [["base:grass", 4], ["base:log", 3], ["base:leaves", 4], ["vanilla:mycelium", 2], ["base:sand", 1]],
		"mobs": [["vanilla:wolf", 1], ["vanilla:boomshroom", 1], ["vanilla:cow", 2]], "mob_chance": 0.1, "crate_chance": 0.06,
		"crate": [["base:sapling", 2], ["base:apple", 4], ["vanilla:string", 2]]},
]

var api
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	api.set_server_info({"name": "One Block", "motd": "Break the block. See what comes back. /oneblock goes home."})
	api.set_physics({"void_below": true})
	# Nothing to catch a dropped item out here, so what you mine goes straight into the backpack.
	api.set_gameplay({"item_drops": "inventory", "keep_inventory": true, "mob_spawning": false})
	api.set_world_generator(VoidGenerator.new())
	api.set_spawn_handler(func(player): return _spawn_for(player))
	api.on("player_join", _on_join)
	api.on("block_broken", _on_block_broken)
	api.every(0.25, _check_void)
	api.register_command("oneblock", "Go back to your block ('/oneblock reset' starts over)", _cmd_oneblock)


class VoidGenerator:
	func generate(_chunk) -> void:
		pass  # empty sky; each player's block is placed for them


# --- The block ------------------------------------------------------------------------------------

func _data(player) -> Dictionary:
	if not player.data.has("oneblock"):
		player.data.oneblock = {}
	return player.data.oneblock


func _origin(index: int) -> Vector3i:
	return Vector3i(index * BLOCK_SPACING + 8, BLOCK_Y, 8)


func _spawn_for(player) -> Vector3:
	var data := _data(player)
	if not data.has("index"):
		_assign(player)
	var o := _origin(int(data.index))
	return Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)


func _assign(player) -> void:
	var index := int(api.storage.get("next_block", 0))
	api.storage.next_block = index + 1
	var data := _data(player)
	data.index = index
	data.broken = 0
	data.phase = 0
	var o := _origin(index)
	api.set_block(o, api.block("base:grass"))
	api.set_block(o + Vector3i(0, 1, 0), 0)
	api.info("One Block #%d is %s's" % [index, player.name])


func _cmd_oneblock(player, args: PackedStringArray) -> void:
	if args.size() > 0 and args[0] == "reset":
		player.clear_inventory()
		_assign(player)
		player.show_title("A fresh block", "Good luck!", 3.0)
	var data := _data(player)
	var o := _origin(int(data.get("index", 0)))
	if api.get_loaded_block(o) == 0:
		api.set_block(o, api.block("base:grass"))  # never leave someone standing over nothing
	player.teleport(_spawn_for(player))
	_show_progress(player)


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	if ev.first_time:
		player.give(api.item("base:wooden_pickaxe"))
		player.give(api.item("base:wooden_axe"))
		player.show_title("One Block", "Break it. Something else takes its place.", 5.0)
	_show_progress(player)


func _on_block_broken(ev: Dictionary) -> void:
	var player = ev.player
	if player == null:
		return
	var data := _data(player)
	if not data.has("index") or Vector3i(ev.position) != _origin(int(data.index)):
		return
	data.broken = int(data.get("broken", 0)) + 1
	var phase_index: int = mini(int(data.broken) / PHASE_LENGTH, PHASES.size() - 1)
	if phase_index != int(data.get("phase", 0)):
		data.phase = phase_index
		player.show_title(String(PHASES[phase_index].name), "The block has changed", 4.0)
		api.play_sound("engine:level_up", player.position)
	_replace(player, _origin(int(data.index)), PHASES[phase_index])
	_show_progress(player)


## Puts something new where the block was: usually a block, now and then a creature or a crate of goods.
func _replace(player, position: Vector3i, phase: Dictionary) -> void:
	api.set_block(position, _pick_block(phase))
	if randf() < float(phase.get("mob_chance", 0.0)):
		var mob: String = _pick(phase.get("mobs", []), func(n): return api.entity_type(n) >= 0)
		if not mob.is_empty():
			api.spawn_entity(mob, Vector3(position) + Vector3(0.5, 1.2, 0.5))
			return
	if randf() < float(phase.get("crate_chance", 0.0)):
		var given := []
		for entry in phase.get("crate", []):
			var item: int = api.item(String(entry[0]))
			if item > 0:
				player.give(item, int(entry[1]))
				given.append("%d %s" % [int(entry[1]), String(entry[0]).get_slice(":", 1).replace("_", " ")])
		if not given.is_empty():
			player.show_title("", "A crate! " + ", ".join(given), 2.5)


func _pick_block(phase: Dictionary) -> int:
	var name: String = _pick(phase.get("blocks", []), func(n): return api.block(n) > 0)
	return api.block(name) if not name.is_empty() else api.block("base:dirt")


## One weighted entry ([name, weight]) whose name this world actually has, or "".
func _pick(entries: Array, exists: Callable) -> String:
	var usable := []
	var total := 0
	for entry in entries:
		if entry is Array and entry.size() == 2 and exists.call(String(entry[0])):
			usable.append(entry)
			total += int(entry[1])
	if total <= 0:
		return ""
	var roll := randi() % total
	for entry in usable:
		roll -= int(entry[1])
		if roll < 0:
			return String(entry[0])
	return String(usable[0][0])


# --- Falling out of the world ---------------------------------------------------------------------

func _check_void() -> void:
	for player in api.get_players():
		if player.position.y < VOID_Y:
			player.teleport(_spawn_for(player))
			player.show_title("", "The void spat you back out", 2.0)


func _show_progress(player) -> void:
	var data := _data(player)
	var broken := int(data.get("broken", 0))
	var phase: Dictionary = PHASES[mini(int(data.get("phase", 0)), PHASES.size() - 1)]
	var next: int = PHASE_LENGTH - (broken % PHASE_LENGTH)
	player.show_ui("oneblock:progress", {
		"anchor": "top_right",
		"children": [
			{"type": "label", "text": "One Block", "size": 18, "color": "#ffd166"},
			{"type": "label", "text": "%s  -  %d broken" % [phase.name, broken]},
			{"type": "label", "text": "%d more to the next phase" % next if int(data.get("phase", 0)) < PHASES.size() - 1 else "the last phase", "size": 12},
		],
	})
