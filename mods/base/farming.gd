extends RefCounted
## Plants and farming, built on engine block ticks, light levels and support rules:
##   hoes till grass or dirt into farmland; seeds (from tall grass) plant wheat on farmland
##   wheat grows through four stages with light, twice as fast on farmland near water
##   farmland dries back to dirt when it has no water nearby and nothing planted
##   saplings (from leaves) grow into trees; tall grass and flowers decorate generated terrain

const WHEAT_STAGES := 4
const WHEAT_INTERVAL := 50.0  # seconds per growth attempt; ~3.5 minutes seed to harvest when watered
const MIN_GROW_LIGHT := 9
const WATER_RANGE := 4
const SEED_CHANCE := 0.15
const SAPLING_CHANCE := 0.06
const BREAD_HEAL := 5.0

var api
var ids := {}


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	var soil := ["base:grass", "base:dirt"]
	ids.farmland = api.register_block("farmland", {"display_name": "Farmland", "drops": "base:dirt", "sounds": sounds.dirt,
		"textures": {"top": "textures/farmland_top.png", "side": "textures/dirt.png", "bottom": "textures/dirt.png"},
		"hardness": 0.6, "tool": "shovel", "placeable": false})
	var wheat := []
	for stage in WHEAT_STAGES:
		wheat.append(api.register_block("wheat_%d" % stage, {"display_name": "Wheat", "textures": "textures/wheat_%d.png" % stage,
			"render": "plant", "sway": true, "hardness": 0.0, "placeable": false, "support": ["base:farmland"],
			"drops": "", "sounds": sounds.grass}))
	ids.wheat_stages = wheat
	ids.tall_grass = api.register_block("tall_grass", {"display_name": "Tall Grass", "textures": "textures/tall_grass.png",
		"render": "plant", "sway": true, "hardness": 0.0, "support": soil, "drops": "", "replaceable": true, "sounds": sounds.grass})
	for flower in ["poppy", "dandelion"]:
		ids[flower] = api.register_block(flower, {"textures": "textures/%s.png" % flower, "render": "plant", "sway": true,
			"hardness": 0.0, "support": soil, "sounds": sounds.grass})
	ids.sapling = api.register_block("sapling", {"display_name": "Sapling", "textures": "textures/sapling.png", "render": "plant",
		"hardness": 0.0, "support": soil, "sounds": sounds.grass})

	ids.seeds = api.register_item("wheat_seeds", {"display_name": "Wheat Seeds", "icon": "textures/wheat_seeds.png", "usable": true})
	ids.wheat = api.register_item("wheat", {"display_name": "Wheat", "icon": "textures/wheat.png"})
	ids.bread = api.register_item("bread", {"display_name": "Bread", "icon": "textures/bread.png", "usable": true})
	api.register_recipe({"base:wheat": 3}, "base:bread", 1, {"category": "food"})

	# Found by experimenting: arranged in the crafting grid (see the recipe patterns).
	api.register_block("torch", {"display_name": "Torch", "textures": "textures/torch.png", "render": "plant", "light": 14,
		"hardness": 0.0, "support": "solid", "sounds": sounds.grass})
	api.register_block("hay_bale", {"display_name": "Hay Bale", "sounds": sounds.grass, "hardness": 0.5,
		"textures": {"top": "textures/hay_bale_top.png", "bottom": "textures/hay_bale_top.png", "side": "textures/hay_bale_side.png"}})
	api.register_recipe({}, "base:hay_bale", 1, {"pattern": ["WWW", "WWW", "WWW"], "key": {"W": "base:wheat"}, "unlock": "experiment",
		"category": "blocks", "hint": "A whole grid of the harvest, bundled."})
	api.register_recipe({"base:hay_bale": 1}, "base:wheat", 9, {"id": "wheat_from_hay"})
	ids.hoes = {}
	for m in [{"name": "wooden", "input": "base:planks", "tier": 1, "durability": 60},
			{"name": "stone", "input": "base:cobblestone", "tier": 2, "durability": 130},
			{"name": "iron", "input": "base:iron_ingot", "tier": 3, "durability": 250}]:
		var hoe: int = api.register_item("%s_hoe" % m.name, {"display_name": "%s Hoe" % m.name.capitalize(),
			"icon": "textures/%s_hoe.png" % m.name, "durability": m.durability, "usable": true,
			"tool": {"type": "hoe", "tier": m.tier, "speed": 1.0 + m.tier}, "weapon": {"damage": 1.0, "cooldown": 0.4}})
		ids.hoes[hoe] = true
		api.register_recipe({m.input: 2, "base:stick": 2}, "base:%s_hoe" % m.name, 1,
			{"station": "crafting_table", "needs": ["metalwork"]} if m.name == "iron" else {"station": "crafting_table"})

	for stage in WHEAT_STAGES - 1:
		api.register_block_tick("base:wheat_%d" % stage, _grow_wheat, {"interval": WHEAT_INTERVAL})
	api.register_block_tick("base:farmland", _dry_farmland, {"interval": 30.0})
	api.register_block_tick("base:sapling", _grow_sapling, {"interval": 120.0})
	api.on("item_use", _on_item_use)
	api.on("block_break", func(ev): ev.drops = _plant_drops(ev.block, ev.drops))
	api.on("block_destroyed", func(ev): ev.drops = _plant_drops(ev.block, ev.drops))


## What plants and leaves drop: ripe wheat gives wheat and seeds, young wheat its seed back, tall
## grass sometimes a seed, leaves sometimes a sapling.
func _plant_drops(block: int, drops) -> Array:
	var out: Array = drops if drops is Array else []
	var stage: int = ids.wheat_stages.find(block)
	if stage == WHEAT_STAGES - 1:
		out = [[ids.wheat, 1], [ids.seeds, randi_range(1, 3)]]
	elif stage >= 0:
		out = [[ids.seeds, 1]]
	elif block == ids.tall_grass and randf() < SEED_CHANCE:
		out = [[ids.seeds, 1]]
	elif block == api.block("base:leaves") and randf() < SAPLING_CHANCE:
		out.append([ids.sapling, 1])
	return out


func _on_item_use(ev: Dictionary) -> void:
	var player = ev.player
	if ev.item == ids.bread:
		if player.health >= player.max_health:
			player.show_title("", "You are not hungry", 1.0)
		elif player.is_creative() or player.take(ids.bread, 1):
			player.heal(BREAD_HEAL)
			api.play_sound("base:eat", player.get_eye_position())
		return
	if not ev.has_target:
		return
	var pos: Vector3i = ev.position
	if api.get_block(pos) == ids.tall_grass:
		pos += Vector3i.DOWN  # aiming at tall grass means the ground under it
	elif ev.normal != Vector3i.UP:
		return
	var above := pos + Vector3i.UP
	if api.get_block(above) != 0 and api.get_block(above) != ids.tall_grass:
		return
	var block: int = api.get_block(pos)
	if ids.hoes.has(ev.item) and (block == api.block("base:grass") or block == api.block("base:dirt")):
		if api.get_block(above) == ids.tall_grass:
			api.set_block(above, 0)
		api.set_block(pos, ids.farmland, false, 1 if _near_water(pos) else 0)
		api.play_sound("base:dirt", Vector3(pos) + Vector3(0.5, 1.0, 0.5))
		player.damage_item(player.selected_slot, 1, "till")
	elif ev.item == ids.seeds and block == ids.farmland and api.get_block(above) == 0:
		if player.is_creative() or player.take(ids.seeds, 1):
			api.set_block(above, ids.wheat_stages[0])
			api.play_sound("base:grass", Vector3(above) + Vector3(0.5, 0.2, 0.5))


## Each tick has a chance to advance a stage: always on watered farmland, half the time on dry.
func _grow_wheat(ctx: Dictionary) -> void:
	var pos: Vector3i = ctx.position
	var ticks := _lit_ticks(pos, ctx.ticks)
	var watered: bool = api.get_block_state(pos + Vector3i.DOWN) == 1
	var stage: int = ids.wheat_stages.find(ctx.block)
	for i in ticks:
		if watered or randf() < 0.5:
			stage += 1
	stage = mini(stage, WHEAT_STAGES - 1)
	if ids.wheat_stages[stage] != ctx.block:
		api.set_block(pos, ids.wheat_stages[stage])


## Farmland remembers whether it is watered (state 1) and turns back to dirt when dry and bare.
func _dry_farmland(ctx: Dictionary) -> void:
	var pos: Vector3i = ctx.position
	var wet := _near_water(pos)
	var above: int = api.get_block(pos + Vector3i.UP)
	if not wet and above == 0 and randf() < 0.5:
		api.set_block(pos, api.block("base:dirt"))
	elif int(wet) != ctx.state:
		api.set_block(pos, ids.farmland, true, int(wet))


func _near_water(pos: Vector3i) -> bool:
	var water: int = api.block("base:water")
	for dy in range(0, 2):
		for dz in range(-WATER_RANGE, WATER_RANGE + 1):
			for dx in range(-WATER_RANGE, WATER_RANGE + 1):
				if api.get_loaded_block(pos + Vector3i(dx, dy, dz)) == water:
					return true
	return false


func _grow_sapling(ctx: Dictionary) -> void:
	var pos: Vector3i = ctx.position
	if _lit_ticks(pos, ctx.ticks) > 0:
		grow_tree(pos)


## How many of `ticks` count as lit: all of them in light (sun or lamps), none in the dark. Ticks
## caught up after an unload span days and nights, so with only sky light half of them count.
func _lit_ticks(pos: Vector3i, ticks: int) -> int:
	if ticks <= 1:
		return ticks if api.get_light(pos) >= MIN_GROW_LIGHT else 0
	var levels: Dictionary = api.get_light_levels(pos)
	if levels.block >= MIN_GROW_LIGHT:
		return ticks
	return ticks / 2 if levels.sky >= MIN_GROW_LIGHT else 0


## Grows a tree with its trunk starting at `pos` if there is room. Returns whether it grew.
func grow_tree(pos: Vector3i) -> bool:
	var trunk := randi_range(4, 6)
	var log_id: int = api.block("base:log")
	var leaves: int = api.block("base:leaves")
	for dy in range(1, trunk + 2):
		var b: int = api.get_block(pos + Vector3i(0, dy, 0))
		if b != 0 and b != leaves:
			return false
	var top := pos.y + trunk
	for ly in range(top - 2, top + 2):
		var r := 2 if ly < top else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and (ly >= top or randf() < 0.5):
					continue
				var p := Vector3i(pos.x + dx, ly, pos.z + dz)
				var existing: int = api.get_block(p)
				if existing == 0 or existing == ids.tall_grass:
					api.set_block(p, leaves)
	for dy in trunk:
		api.set_block(pos + Vector3i(0, dy, 0), log_id)
	return true
