extends "res://engine/server/mod.gd"
## Skyblock: each player gets a small island floating over the void, a cobblestone generator block,
## a survival inventory, and a list of challenges that hand out rewards.

const ISLAND_SPACING := 512
const ISLAND_Y := 64
const VOID_Y := -12.0
const GENERATOR_DELAY := 1.0

const CHALLENGES := [
	{"id": "cobble", "text": "Mine 16 cobblestone", "stat": "cobble", "goal": 16, "reward": ["base:sand", 8]},
	{"id": "builder", "text": "Place 48 blocks", "stat": "placed", "goal": 48, "reward": ["base:dirt", 16]},
	{"id": "tower", "text": "Build up to height 80", "stat": "height", "goal": 80, "reward": ["base:glass", 8]},
]

var api
var generator := -1
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	for block_name in ["grass", "dirt", "log", "leaves", "cobblestone", "sand"]:
		ids[block_name] = api.block("base:" + block_name)
	generator = api.register_block("generator", {
		"display_name": "Cobblestone Generator",
		"textures": "textures/generator.png",
		"drops": "",
	})
	api.set_server_info({"name": "Skyblock", "motd": "Your island awaits. /island to go home, /island reset to start over."})
	api.set_physics({"void_below": true})
	api.set_world_generator(VoidGenerator.new())
	api.set_spawn_handler(func(player): return _island_spawn(player))

	api.on("player_join", _on_join)
	api.on("block_break", _on_block_break)
	api.on("block_broken", _on_block_broken)
	api.on("block_placed", _on_block_placed)
	api.on("ui_action", _on_ui_action)
	api.every(0.25, _check_void)
	api.register_command("island", "Go home, or '/island reset' for a fresh island", _cmd_island)


class VoidGenerator:
	func generate(_chunk) -> void:
		pass  # Chunks start as air; islands are built per player.


# --- Islands ------------------------------------------------------------------------------------

func _data(player) -> Dictionary:
	if not player.data.has("skyblock"):
		player.data.skyblock = {}
	return player.data.skyblock


func _island_origin(index: int) -> Vector3i:
	return Vector3i(index * ISLAND_SPACING + 8, ISLAND_Y, 8)


func _island_spawn(player) -> Vector3:
	var data := _data(player)
	if not data.has("island"):
		_assign_island(player)
	var o := _island_origin(int(data.island))
	return Vector3(o.x + 0.5, o.y + 1, o.z + 0.5)


func _assign_island(player) -> void:
	var index := int(api.storage.get("next_island", 0))
	api.storage.next_island = index + 1
	var data := _data(player)
	data.island = index
	data.stats = {"cobble": 0, "placed": 0, "height": 0}
	data.done = {}
	_build_island(_island_origin(index))
	api.info("Built island #%d for %s" % [index, player.name])


## An L-shaped island of dirt and grass with a tree and a cobblestone generator.
func _build_island(o: Vector3i) -> void:
	for x in range(-2, 4):
		for z in range(-2, 4):
			if x > 0 and z > 0:
				continue  # cut out a corner to make the L
			for y in range(-2, 1):
				api.set_block(o + Vector3i(x, y, z), ids.grass if y == 0 else ids.dirt)
	var tree := o + Vector3i(-1, 1, 3)
	for dy in 4:
		api.set_block(tree + Vector3i(0, dy, 0), ids.log)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(3, 5):
				var p := tree + Vector3i(dx, dy, dz)
				if api.get_block(p) == 0:
					api.set_block(p, ids.leaves)
	api.set_block(tree + Vector3i(0, 5, 0), ids.leaves)
	api.set_block(o + Vector3i(3, 0, -2), generator)
	api.set_block(o + Vector3i(3, 1, -2), ids.cobblestone)


func _cmd_island(player, args: PackedStringArray) -> void:
	if args.size() > 0 and args[0] == "reset":
		player.clear_inventory()
		_assign_island(player)
		_give_starter_items(player)
		player.show_title("New island", "Good luck!", 3.0)
		_refresh_challenges(player)
	player.teleport(_island_spawn(player))


func _give_starter_items(player) -> void:
	player.give(ids.dirt, 8)


# --- Events -------------------------------------------------------------------------------------

func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	player.set_creative(false)
	if ev.first_time:
		_give_starter_items(player)
		player.show_ui("skyblock:welcome", {
			"anchor": "center",
			"modal": true,
			"children": [
				{"type": "label", "text": "Welcome to Skyblock", "size": 28, "color": "#8ecae6"},
				{"type": "label", "text": "You have a tiny island and nothing else.\nMine the cobblestone above the generator - it grows back.\nDon't fall off."},
				{"type": "spacer", "size": 6},
				{"type": "button", "text": "Let's go", "action": "close"},
			],
		})
	_refresh_challenges(player)


func _on_ui_action(ev: Dictionary) -> void:
	if ev.ui_id == "skyblock:welcome" and ev.action == "close":
		ev.player.hide_ui("skyblock:welcome")


## Generators can't be broken in survival; that would soft-lock the island.
func _on_block_break(ev: Dictionary) -> void:
	if ev.block == generator and not ev.player.is_creative():
		ev.cancelled = true
		ev.player.send_message("The generator is bolted down.")


func _on_block_broken(ev: Dictionary) -> void:
	var pos: Vector3i = ev.position
	if api.get_block(pos + Vector3i.DOWN) == generator:
		api.after(GENERATOR_DELAY, func():
			if api.get_block(pos) == 0 and api.get_block(pos + Vector3i.DOWN) == generator:
				api.set_block(pos, ids.cobblestone))
	if ev.block == ids.cobblestone:
		_bump_stat(ev.player, "cobble", 1)


func _on_block_placed(ev: Dictionary) -> void:
	_bump_stat(ev.player, "placed", 1)
	var data := _data(ev.player)
	var height: int = ev.position.y
	if height > int(data.stats.get("height", 0)):
		data.stats.height = height
		_check_challenges(ev.player)
	if ev.block == generator:
		var above: Vector3i = ev.position + Vector3i.UP
		api.after(GENERATOR_DELAY, func():
			if api.get_block(above) == 0:
				api.set_block(above, ids.cobblestone))


func _check_void() -> void:
	for player in api.get_players():
		if player.position.y < VOID_Y:
			player.teleport(_island_spawn(player))
			player.show_title("You fell into the void", "Back to your island", 2.5)


# --- Challenges ---------------------------------------------------------------------------------

func _bump_stat(player, stat: String, amount: int) -> void:
	var stats: Dictionary = _data(player).get("stats", {})
	stats[stat] = int(stats.get(stat, 0)) + amount
	_data(player).stats = stats
	_check_challenges(player)


func _check_challenges(player) -> void:
	var data := _data(player)
	var done: Dictionary = data.get("done", {})
	for c in CHALLENGES:
		if done.has(c.id) or int(data.stats.get(c.stat, 0)) < c.goal:
			continue
		done[c.id] = true
		var reward_block: int = api.block(c.reward[0])
		player.give(reward_block, c.reward[1])
		player.show_title("Challenge complete!", "%s  (+%d %s)" % [c.text, c.reward[1], api.block_display_name(reward_block)], 3.0)
		api.broadcast("%s completed '%s'" % [player.name, c.text])
	data.done = done
	_refresh_challenges(player)


func _refresh_challenges(player) -> void:
	var data := _data(player)
	var done: Dictionary = data.get("done", {})
	var children := [{"type": "label", "text": "Island #%d challenges" % (int(data.get("island", 0)) + 1), "size": 18, "color": "#8ecae6"}]
	for c in CHALLENGES:
		var value := mini(int(data.stats.get(c.stat, 0)), c.goal)
		var complete := done.has(c.id)
		children.append({"type": "label", "text": ("[done] " if complete else "") + "%s  (%d/%d)" % [c.text, value, c.goal],
			"color": "#90be6d" if complete else "#ffffff"})
		children.append({"type": "progress", "value": value, "max": c.goal})
	player.show_ui("skyblock:challenges", {"anchor": "top_right", "children": children})
