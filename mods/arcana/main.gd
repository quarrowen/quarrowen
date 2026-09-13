extends "res://engine/server/mod.gd"
## Arcana: a mana system built from the same engine primitives as Industry.
##
## - A generation pass seeds glowing mana crystal ore into any world's stone.
## - Mining crystals yields mana shards; eating a shard restores mana.
## - Every player has a mana pool shown in a HUD panel; it regenerates slowly, and quickly near a
##   mana pylon (a model block that emits light).
## - Wands are usable items: Wand of Blink teleports you forward, Wand of Light conjures a
##   temporary light orb, Wand of Sparks fires a magic projectile that hurts mobs. Craft them with C.
##   /arcana kit gives a starter set.

const MAX_MANA := 100.0
const REGEN := 2.0  # mana per second
const PYLON_REGEN := 10.0
const PYLON_RANGE := 6.0
const TICK := 0.5
const SHARD_MANA := 25.0
const BLINK_COST := 20.0
const BLINK_RANGE := 8.0
const LIGHT_COST := 10.0
const LIGHT_SECONDS := 30.0
const HUD_ID := "arcana:mana"
const SPARK_COST := 8.0
const SPARK_SPEED := 26.0

var api
var ids := {}
var _hud_shown := {}  # peer_id -> last displayed whole mana


class CrystalPass:
	var stone: int
	var crystal: int

	func _init(stone_id: int, crystal_id: int) -> void:
		stone = stone_id
		crystal = crystal_id

	## Worker thread: small crystal clusters in stone, deterministic per chunk.
	func decorate(chunk, world_seed: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([world_seed, "arcana", chunk.coord.x, chunk.coord.y])
		var blocks: PackedByteArray = chunk.blocks
		for attempt in 3:
			if rng.randf() > 0.6:
				continue
			var x := rng.randi_range(1, 14)
			var y := rng.randi_range(6, 44)
			var z := rng.randi_range(1, 14)
			for n in rng.randi_range(1, 4):
				var i: int = x + rng.randi_range(-1, 1) + ((z + rng.randi_range(-1, 1)) << 4) + ((y + rng.randi_range(-1, 1)) << 8)
				if i >= 0 and i < blocks.size() / 2 and blocks.decode_u16(i << 1) == stone:
					blocks.encode_u16(i << 1, crystal)
		chunk.blocks = blocks


func setup(mod_api) -> void:
	api = mod_api
	ids.shard = api.register_item("mana_shard", {"display_name": "Mana Shard", "icon": "textures/mana_shard.png", "usable": true})
	ids.blink = api.register_item("wand_of_blink", {"display_name": "Wand of Blink", "icon": "textures/wand_of_blink.png", "usable": true, "max_stack": 1})
	ids.light = api.register_item("wand_of_light", {"display_name": "Wand of Light", "icon": "textures/wand_of_light.png", "usable": true, "max_stack": 1})
	ids.sparks = api.register_item("wand_of_sparks", {"display_name": "Wand of Sparks", "icon": "textures/wand_of_sparks.png", "usable": true, "max_stack": 1})
	api.register_sound("spark_cast", "sounds/spark_cast.wav", {"pitch_variance": 0.15})
	api.register_sound("spark_hit", "sounds/spark_hit.wav")
	ids.spark = api.register_entity("spark", {"kind": "projectile", "sprite": "textures/spark.png", "glow": true,
		"width": 0.3, "height": 0.3, "damage": 6, "gravity": 1.5, "lifetime": 3.0})
	ids.crystal = api.register_block("mana_crystal_ore", {"display_name": "Mana Crystal Ore", "textures": "textures/mana_crystal_ore.png",
		"light": 7, "drops": [[ids.shard, 2]]})
	ids.pylon = api.register_block("mana_pylon", {"display_name": "Mana Pylon", "model": "models/mana_pylon.glb",
		"textures": "textures/mana_pylon_icon.png", "light": 10})
	ids.orb = api.register_block("light_orb", {"display_name": "Light Orb", "textures": "textures/light_orb.png", "render": "cutout",
		"light": 15, "solid": false, "drops": "", "placeable": false})

	api.add_generation_pass(CrystalPass.new(api.block("base:stone"), ids.crystal))
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 3}, "arcana:wand_of_blink")
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 2, "base:glass": 1}, "arcana:wand_of_light")
	api.register_recipe({"arcana:mana_shard": 6, "base:cobblestone": 2}, "arcana:mana_pylon")
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 4}, "arcana:wand_of_sparks")
	api.on("projectile_hit", func(ev):
		if ev.entity.type == ids.spark:
			api.play_sound("spark_hit", ev.position))

	api.on("player_join", _on_join)
	api.on("player_leave", func(ev): _hud_shown.erase(ev.player.peer_id))
	api.on("item_use", _on_item_use)
	api.on("block_placed", func(ev):
		if ev.block == ids.pylon:
			api.set_block_data(ev.position, {}))
	api.every(TICK, _tick)
	api.register_command("arcana", "kit - shards, wands and a pylon", _cmd_arcana)


func _mana(player) -> float:
	if not (player.data.get("arcana") is Dictionary):
		player.data.arcana = {"mana": MAX_MANA}
	return float(player.data.arcana.get("mana", MAX_MANA))


func _set_mana(player, value: float) -> void:
	_mana(player)
	player.data.arcana.mana = clampf(value, 0.0, MAX_MANA)
	_refresh_hud(player)


func _on_join(ev: Dictionary) -> void:
	_hud_shown.erase(ev.player.peer_id)
	_refresh_hud(ev.player)
	if ev.first_time:
		ev.player.send_message("Arcana is installed: find glowing mana crystals underground, craft wands with C, or /arcana kit.")


func _tick() -> void:
	var pylons: Array[Vector3i] = api.find_block_data(ids.pylon)
	for player in api.get_players():
		var rate := REGEN
		for pylon in pylons:
			if player.position.distance_to(Vector3(pylon) + Vector3(0.5, 0.5, 0.5)) <= PYLON_RANGE:
				rate = PYLON_REGEN
				break
		var mana := _mana(player)
		if mana < MAX_MANA:
			_set_mana(player, mana + rate * TICK)


func _refresh_hud(player) -> void:
	var mana := _mana(player)
	var whole := floori(mana)
	if _hud_shown.get(player.peer_id, -1) == whole:
		return
	_hud_shown[player.peer_id] = whole
	player.show_ui(HUD_ID, {
		"anchor": "bottom_right",
		"children": [
			{"type": "label", "text": "Mana  %d / %d" % [whole, MAX_MANA], "color": "#c792ff"},
			{"type": "progress", "value": mana, "max": MAX_MANA, "color": "#b18cff"},
		],
	})


func _spend(player, cost: float) -> bool:
	var mana := _mana(player)
	if mana < cost:
		player.show_title("", "Not enough mana (%d / %d)" % [floori(mana), cost], 1.5)
		return false
	_set_mana(player, mana - cost)
	return true


func _on_item_use(ev: Dictionary) -> void:
	var player = ev.player
	match ev.item:
		ids.shard:
			if _mana(player) >= MAX_MANA:
				player.show_title("", "Mana is already full", 1.2)
			elif player.is_creative() or player.take(ids.shard, 1):
				_set_mana(player, _mana(player) + SHARD_MANA)
		ids.blink:
			_blink(player, ev.direction)
		ids.light:
			_conjure_light(player, ev)
		ids.sparks:
			if _spend(player, SPARK_COST):
				var eye: Vector3 = player.get_eye_position()
				api.spawn_projectile("spark", eye + ev.direction * 0.6 - Vector3(0, 0.15, 0), ev.direction * SPARK_SPEED, player)
				api.play_sound("spark_cast", eye)


## Teleports up to BLINK_RANGE blocks along the view direction to the furthest spot with room to stand.
func _blink(player, direction: Vector3) -> void:
	var eye: Vector3 = player.get_eye_position()
	var destination := Vector3.INF
	var t := BLINK_RANGE
	while t >= 1.0:
		var feet := eye + direction * t - Vector3(0, 1.62, 0)
		var cell := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
		if _free(cell) and _free(cell + Vector3i.UP):
			destination = Vector3(cell.x + 0.5, cell.y, cell.z + 0.5)
			break
		t -= 0.5
	if destination == Vector3.INF:
		player.show_title("", "No room to blink there", 1.2)
		return
	if _spend(player, BLINK_COST):
		player.teleport(destination)


func _free(cell: Vector3i) -> bool:
	var block: int = api.get_loaded_block(cell)
	return not api.is_solid(block)


func _conjure_light(player, ev: Dictionary) -> void:
	if not ev.has_target:
		player.show_title("", "Aim at a block to conjure light", 1.2)
		return
	var pos: Vector3i = ev.position + ev.normal
	if api.get_block(pos) != 0:
		return
	if _spend(player, LIGHT_COST):
		api.set_block(pos, ids.orb)
		api.after(LIGHT_SECONDS, func():
			if api.get_loaded_block(pos) == ids.orb:
				api.set_block(pos, 0))


func _cmd_arcana(player, _args: PackedStringArray) -> void:
	if not (player.is_creative() or player.is_admin()):
		player.send_message("Only admins can hand out Arcana kits in survival.")
		return
	if player.is_creative():
		player.set_hotbar([ids.shard, ids.blink, ids.light, ids.pylon, api.block("base:stone"), ids.sparks])
		player.send_message("Arcana kit in your hotbar: shard, Wand of Blink, Wand of Light, Mana Pylon, Wand of Sparks.")
		return
	player.give(ids.shard, 16)
	player.give(ids.blink, 1)
	player.give(ids.light, 1)
	player.give(ids.pylon, 1)
	player.give(ids.sparks, 1)
	player.send_message("Arcana kit: shards (right-click to restore mana), Wand of Blink, Wand of Light and a Mana Pylon.")
