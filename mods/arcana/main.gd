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
const POTION_MANA := 60.0
const BLINK_COST := 20.0
const BLINK_RANGE := 8.0
const LIGHT_COST := 10.0
const LIGHT_SECONDS := 30.0
const HUD_ID := "arcana:mana"
const SPARK_COST := 8.0
const SPARK_SPEED := 26.0
## Soul Blade: souls needed for each level; each level adds damage and eventually crit chance.
const SOUL_LEVELS := [3, 8, 16, 30, 50]

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
	# A potion is swigged like any drink (the engine's food system) and restores mana in player_eat below.
	ids.potion = api.register_item("mana_potion", {"display_name": "Mana Potion", "icon": "textures/mana_potion.png", "max_stack": 16,
		"food": {"hunger": 0, "saturation": 0, "eat_time": 0.9, "always": true, "style": "drink", "color": "#b070ff", "remainder": "base:glass_bottle"}})
	api.register_recipe({"arcana:mana_shard": 2, "base:glass_bottle": 1}, "arcana:mana_potion", 1, {"category": "food"})
	api.register_material("mana", {"display_name": "Mana Crystal", "item": "arcana:mana_shard", "color": "#b98cff", "tier": 3, "speed": 7.0,
		"durability": 180, "damage": 2.5, "handle": 1.0,
		"trait": {"name": "Arcane", "description": "glows and hits harder", "damage_add": 1.0,
			"glow": {"color": "#b070ff", "energy": 0.6}}})
	ids.blink = api.register_item("wand_of_blink", {"display_name": "Wand of Blink", "icon": "textures/wand_of_blink.png", "usable": true, "max_stack": 1})
	ids.light = api.register_item("wand_of_light", {"display_name": "Wand of Light", "icon": "textures/wand_of_light.png", "usable": true, "max_stack": 1})
	ids.sparks = api.register_item("wand_of_sparks", {"display_name": "Wand of Sparks", "icon": "textures/wand_of_sparks.png", "usable": true, "max_stack": 1,
		"glow": {"color": "#ff9040", "energy": 0.6}, "effects": {"use": "cast"}})
	api.register_sound("spark_cast", "sounds/spark_cast.wav", {"pitch_variance": 0.15})
	api.register_sound("spark_hit", "sounds/spark_hit.wav")
	ids.spark = api.register_entity("spark", {"kind": "projectile", "sprite": "textures/spark.png", "glow": true,
		"width": 0.3, "height": 0.3, "damage": 6, "gravity": 1.5, "lifetime": 3.0})
	# Effects are data: the client draws them, the mod only says when and where.
	api.register_effect("soul_hit", {"emitters": [
		{"amount": 16, "lifetime": 0.5, "speed": [2.0, 4.5], "spread": 180, "gravity": -1.0, "drag": 3.0, "size": [0.14, 0.02],
			"colors": ["#f0d8ff", "#b060ff", "#4010a000"], "texture": "spark"},
		{"amount": 6, "lifetime": 0.9, "speed": [0.3, 0.8], "direction": [0, 1, 0], "spread": 40, "gravity": -1.5, "size": [0.25, 0.05],
			"colors": ["#8040ffa0", "#2000a000"]}],
		"light": {"color": "#a060ff", "energy": 1.5, "range": 4.0, "seconds": 0.25}})
	api.register_effect("soul_level", {"emitters": [
		{"amount": 60, "lifetime": 1.2, "speed": [1.5, 4.0], "spread": 180, "gravity": -2.0, "drag": 1.5, "size": [0.18, 0.0],
			"colors": ["#ffffff", "#c080ff", "#6020c000"], "texture": "star", "shape": "sphere", "radius": 0.6}],
		"light": {"color": "#b070ff", "energy": 5.0, "range": 10.0, "seconds": 0.8},
		"shake": {"strength": 0.35, "seconds": 0.4, "radius": 10.0}, "sound": "arcana:spark_cast"})
	api.register_effect("soul_aura", {"duration": -1, "emitters": [
		{"amount": 10, "burst": false, "lifetime": 0.8, "speed": [0.05, 0.3], "direction": [0, 1, 0], "spread": 60, "gravity": -0.6,
			"size": [0.07, 0.0], "colors": ["#e0c0ff", "#9050ff", "#4010a000"], "shape": "sphere", "radius": 0.12}]})
	api.register_effect("blink", {"emitters": [
		{"amount": 30, "lifetime": 0.6, "speed": [0.5, 2.5], "spread": 180, "gravity": -2.0, "drag": 2.0, "size": [0.15, 0.0],
			"colors": ["#d0f8ff", "#40c0ff", "#0060c000"], "shape": "box", "extents": [0.3, 0.9, 0.3]}],
		"light": {"color": "#60d0ff", "energy": 2.5, "range": 6.0, "seconds": 0.3}})
	api.register_effect("cast", {"emitters": [
		{"amount": 12, "lifetime": 0.35, "speed": [1.0, 3.0], "direction": [0, 1, 0], "spread": 35, "drag": 4.0, "size": [0.1, 0.0],
			"colors": ["#fff0c0", "#ff9040", "#ff402000"], "texture": "spark"}]})
	api.register_effect("spark_burst", {"emitters": [
		{"amount": 24, "lifetime": 0.45, "speed": [2.0, 6.0], "spread": 180, "gravity": 6.0, "drag": 2.0, "size": [0.12, 0.02],
			"colors": ["#ffffff", "#ffc040", "#ff602000"], "texture": "spark"}],
		"light": {"color": "#ffa040", "energy": 3.0, "range": 6.0, "seconds": 0.3}})
	ids.soul_blade = api.register_item("soul_blade", {"display_name": "Soul Blade", "icon": "textures/soul_blade.png",
		"durability": 400, "weapon": {"damage": 5.0, "cooldown": 0.6, "sweep": 0.25},
		"trail": {"color": "#a060ff90", "width": 0.5, "seconds": 0.2}, "effects": {"hit": "soul_hit"},
		"lore": ["Grows stronger with every soul it takes."]})
	# A helmet whose crystals glow when worn (armor glow lights up the armor texture).
	ids.crystal_helmet = api.register_item("crystal_helmet", {"display_name": "Crystal Helmet", "icon": "base:textures/iron_helmet.png",
		"equip_slot": "head", "durability": 300, "armor": {"armor": 3.0, "toughness": 1.0}, "armor_texture": "base:textures/iron_armor.png",
		"glow": {"color": "#60e0ff", "energy": 0.8},
		"lore": ["Mana crystals set in iron."]})
	ids.crystal = api.register_block("mana_crystal_ore", {"display_name": "Mana Crystal Ore", "textures": "textures/mana_crystal_ore.png",
		"light": 7, "drops": [[ids.shard, 2]]})
	ids.pylon = api.register_block("mana_pylon", {"display_name": "Mana Pylon", "model": "models/mana_pylon.glb",
		"textures": "textures/mana_pylon_icon.png", "light": 10})
	ids.orb = api.register_block("light_orb", {"display_name": "Light Orb", "textures": "textures/light_orb.png", "render": "cutout",
		"light": 15, "solid": false, "drops": "", "placeable": false})

	# Cosmetics: robes anyone can wear here, and a hat earned by levelling a Soul Blade.
	api.register_cosmetic("mage_robe", {"category": "jacket", "display_name": "Mage robe", "color": "#4a3a8a",
		"description": "Arcana: worn by those who study the crystals.", "paint": [
			{"region": "torso_overlay", "rows": [0, 12]},
			{"region": "arm_r_overlay", "rows": [0, 12]}, {"region": "arm_l_overlay", "rows": [0, 12]},
			{"region": "leg_r_overlay", "rows": [0, 10]}, {"region": "leg_l_overlay", "rows": [0, 10]},
			{"region": "torso_overlay", "rows": [9, 10], "sides": ["front", "back", "left", "right"], "color": "#e8c040"},
			{"region": "arm_r_overlay", "rows": [10, 12], "sides": ["front", "back", "left", "right"], "color": "#e8c040"},
			{"region": "arm_l_overlay", "rows": [10, 12], "sides": ["front", "back", "left", "right"], "color": "#e8c040"}]})
	ids.archmage_hat = api.register_cosmetic("archmage_hat", {"category": "hat", "display_name": "Archmage hat", "color": "#2a3a8a",
		"unlocked": false, "description": "Arcana: awarded for a Soul Blade of level 3.", "boxes": [
			{"from": [-6, 0, -6], "size": [12, 1, 12]}, {"from": [-4, 1, -4], "size": [8, 3, 8]},
			{"from": [-3, 4, -2.5], "size": [6, 3, 6]}, {"from": [-2, 7, -1], "size": [4, 3, 4]},
			{"from": [-1, 10, 0.5], "size": [2, 2, 2]}, {"from": [-0.5, 12, 1.5], "size": [1, 1.5, 1]},
			{"from": [-4.1, 1, -4.1], "size": [8.2, 1, 8.2], "color": "#e8c040"},
			{"from": [-1, 2, -4.4], "size": [2, 2, 0.5], "color": "#9ff0ff"}]})

	api.add_generation_pass(CrystalPass.new(api.block("base:stone"), ids.crystal))
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 3}, "arcana:wand_of_blink")
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 2, "base:glass": 1}, "arcana:wand_of_light")
	api.register_recipe({"arcana:mana_shard": 6, "base:cobblestone": 2}, "arcana:mana_pylon")
	api.register_recipe({"base:log": 1, "arcana:mana_shard": 4}, "arcana:wand_of_sparks")
	# Channeling mana by hand: hold to raise the flow and keep it inside the drifting band.
	api.register_minigame("channeling", {"title": "Channel by hand", "type": "hold", "verb": "Channel", "duration": 7.0, "zone": 0.24})
	api.register_recipe({"base:iron_sword": 1, "arcana:mana_shard": 8}, "arcana:soul_blade", 1, {"skill": "arcana:channeling"})
	api.register_recipe({"base:iron_helmet": 1, "arcana:mana_shard": 5}, "arcana:crystal_helmet", 1, {"skill": "arcana:channeling"})
	api.on("entity_death", _on_soul_harvest)
	api.on("projectile_hit", func(ev):
		if ev.entity.type == ids.spark:
			api.play_sound("spark_hit", ev.position)
			api.play_effect("spark_burst", ev.position))

	api.on("player_join", _on_join)
	api.on("player_leave", func(ev): _hud_shown.erase(ev.player.peer_id))
	api.on("item_use", _on_item_use)
	api.on("player_eat", func(ev):
		if ev.item == ids.potion:
			_set_mana(ev.player, _mana(ev.player) + POTION_MANA)
			api.play_effect("engine:magic", ev.player.get_eye_position(), {"scale": 0.6}))
	api.on("block_placed", func(ev):
		if ev.block == ids.pylon:
			api.set_block_data(ev.position, {}))
	api.every(TICK, _tick)
	api.register_command("arcana", "kit - shards, wands and a pylon | blade <level> (admins)", _cmd_arcana)


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
		api.play_effect("blink", player.position + Vector3(0, 0.9, 0))
		player.teleport(destination)
		api.play_effect("blink", destination + Vector3(0, 0.9, 0))


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


## Soul Blade progression, built from engine pieces only: the kill event, item data (souls, level,
## name, lore, per-item modifiers) and item stats. Nothing about levelling is in the engine.
func _on_soul_harvest(ev: Dictionary) -> void:
	var player = ev.attacker
	if player == null or player.get("peer_id") == null or ev.entity.def.kind != "mob":
		return
	var slot: int = player.selected_slot
	var stack: Dictionary = player.get_item(slot)
	if stack.item != ids.soul_blade:
		return
	var data: Dictionary = stack.data.duplicate(true)
	data.souls = int(data.get("souls", 0)) + 1
	var level := 0
	for threshold in SOUL_LEVELS:
		if data.souls >= threshold:
			level += 1
	if level > int(data.get("level", 0)):
		player.show_title("", "Soul Blade reached level %d" % level, 2.0)
		api.play_effect("soul_level", player.position + Vector3(0, 1.0, 0), {"follow": player})
		if level >= 3 and not player.has_cosmetic(ids.archmage_hat):
			player.grant_cosmetic(ids.archmage_hat)
			player.send_message("You earned the Archmage hat! Wear it from Esc > Customize avatar.")
	player.set_item_data(slot, _soul_data(data.souls, data))


## Item data for a Soul Blade holding `souls` souls: level, name, lore, stat modifiers and its look.
func _soul_data(souls: int, data := {}) -> Dictionary:
	data = data.duplicate(true)
	data.souls = souls
	var level := 0
	for threshold in SOUL_LEVELS:
		if souls >= threshold:
			level += 1
	data.level = level
	data.name = "Soul Blade" + (" +%d" % level if level > 0 else "")
	data.modifiers = [{"stat": "attack_damage", "amount": level * 1.5}]
	if level >= 3:
		data.modifiers.append({"stat": "crit_chance", "amount": 0.05 * (level - 2)})
	var next := "max level" if level >= SOUL_LEVELS.size() else "%d / %d souls to level %d" % [souls, SOUL_LEVELS[level], level + 1]
	data.lore = ["Souls: %d (%s)" % [souls, next]]
	# The blade glows brighter with each level, lights its surroundings from level 3 and trails wisps at 4.
	if level > 0:
		data.glow = {"color": "#b070ff", "energy": 0.35 * level, "light": 3.0 if level >= 3 else 0.0}
		data.trail = {"color": "#b070ffa0", "width": 0.5 + 0.06 * level, "seconds": 0.2 + 0.03 * level}
	if level >= 4:
		data.effects = {"held": "soul_aura"}
	return data


func _cmd_arcana(player, args: PackedStringArray) -> void:
	if not (player.is_creative() or player.is_admin()):
		player.send_message("Only admins can hand out Arcana kits in survival.")
		return
	if args.size() >= 1 and args[0] == "blade":
		var level := clampi(int(args[1]) if args.size() > 1 else SOUL_LEVELS.size(), 0, SOUL_LEVELS.size())
		player.give(ids.soul_blade, 1, _soul_data(SOUL_LEVELS[level - 1] if level > 0 else 0))
		player.send_message("A level %d Soul Blade." % level)
		return
	if player.is_creative():
		player.set_hotbar([ids.shard, ids.blink, ids.light, ids.pylon, api.block("base:stone"), ids.sparks, ids.soul_blade])
		player.send_message("Arcana kit in your hotbar: shard, Wand of Blink, Wand of Light, Mana Pylon, Wand of Sparks, Soul Blade.")
		return
	player.give(ids.shard, 16)
	player.give(ids.blink, 1)
	player.give(ids.light, 1)
	player.give(ids.pylon, 1)
	player.give(ids.sparks, 1)
	player.give(ids.soul_blade, 1)
	player.send_message("Arcana kit: shards (right-click to restore mana), Wand of Blink, Wand of Light and a Mana Pylon.")
