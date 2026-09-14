extends SceneTree
## Paints the placeholder 16x16 block textures used by the bundled mods and writes them as PNGs.
##   godot --headless --path . -s tools/generate_textures.gd

const TILE := 16

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1337
	var stone := Color(0.49, 0.49, 0.51)
	var dirt := Color(0.47, 0.32, 0.2)
	var grass := Color(0.38, 0.64, 0.25)
	var snow := Color(0.95, 0.97, 1.0)
	var base := "res://mods/base/textures/"

	_save(_noise(stone, 0.07), base + "stone.png")
	_save(_noise(dirt, 0.07), base + "dirt.png")
	_save(_noise(grass, 0.09), base + "grass_top.png")
	_save(_cap(_noise(dirt, 0.07), grass, 3), base + "grass_side.png")
	_save(_noise(Color(0.87, 0.82, 0.58), 0.04), base + "sand.png")
	_save(_log_side(), base + "log_side.png")
	_save(_log_top(), base + "log_top.png")
	_save(_leaves(), base + "leaves.png")
	_save(_planks(), base + "planks.png")
	_save(_cobblestone(), base + "cobblestone.png")
	_save(_noise(Color(0.22, 0.42, 0.86, 0.72), 0.03), base + "water.png")
	_save(_noise(Color(0.28, 0.28, 0.28), 0.18), base + "bedrock.png")
	_save(_glass(), base + "glass.png")
	_save(_ore(stone, Color(0.12, 0.12, 0.12)), base + "coal_ore.png")
	_save(_ore(stone, Color(0.85, 0.68, 0.52)), base + "iron_ore.png")
	_save(_noise(snow, 0.03), base + "snow.png")
	_save(_cap(_noise(dirt, 0.07), snow, 4), base + "snow_side.png")
	_save(_brick(), base + "brick.png")
	_save(_noise(Color(0.52, 0.49, 0.47), 0.16), base + "gravel.png")

	_save(_generator(), "res://mods/skyblock/textures/generator.png")

	var industry := "res://mods/industry/textures/"
	_save(_cable(), industry + "cable.png")
	_save(_icon(Color(0.35, 0.35, 0.38), Color(1.0, 0.55, 0.15), "flame"), industry + "coal_generator_icon.png")
	_save(_icon(Color(0.2, 0.25, 0.45), Color(0.45, 0.75, 1.0), "grid"), industry + "solar_panel_icon.png")
	_save(_icon(Color(0.25, 0.28, 0.25), Color(0.4, 0.95, 0.4), "bars"), industry + "battery_icon.png")
	_save(_icon(Color(0.3, 0.3, 0.3), Color(1.0, 0.85, 0.3), "bulb"), industry + "lamp_icon.png")
	_save(_icon(Color(0.45, 0.4, 0.2), Color(0.85, 0.85, 0.9), "drill"), industry + "miner_icon.png")

	_save(_item(Color(0.1, 0.1, 0.12), "lump"), base + "coal.png")
	var arcana := "res://mods/arcana/textures/"
	_save(_ore(stone, Color(0.75, 0.4, 1.0)), arcana + "mana_crystal_ore.png")
	_save(_item(Color(0.72, 0.42, 1.0), "shard"), arcana + "mana_shard.png")
	_save(_item(Color(0.45, 0.8, 1.0), "wand"), arcana + "wand_of_blink.png")
	_save(_item(Color(1.0, 0.85, 0.35), "wand"), arcana + "wand_of_light.png")
	_save(_icon(Color(0.3, 0.3, 0.36), Color(0.75, 0.45, 1.0), "bulb"), arcana + "mana_pylon_icon.png")
	var orb := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, y - 7.5).length()
			orb.set_pixel(x, y, Color(1.0, 0.95, 0.7, 1.0) if d < 3.0 else Color(0, 0, 0, 0))
	_save(orb, arcana + "light_orb.png")

	var guild := "res://mods/guild/textures/"
	_save(_item(Color(1.0, 0.8, 0.25), "coin"), guild + "gold_coin.png")
	_save(_ore(stone, Color(1.0, 0.82, 0.3)), guild + "gold_ore.png")
	_save(_meteorite(true), guild + "meteorite.png")
	_save(_meteorite(false), guild + "meteorite_cooled.png")
	_save(_icon(Color(0.45, 0.32, 0.2), Color(0.95, 0.85, 0.6), "grid"), guild + "quest_board_icon.png")

	# Gameplay items (appended last so the random sequence for earlier textures is unchanged).
	_save(_item(Color(0.62, 0.45, 0.25), "sword"), base + "wooden_sword.png")
	_save(_item(Color(0.6, 0.6, 0.63), "sword"), base + "stone_sword.png")
	_save(_item(Color(0.85, 0.15, 0.15), "apple"), base + "apple.png")
	var vanilla := "res://mods/vanilla/textures/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vanilla))
	_save(_item(Color(0.95, 0.55, 0.55), "meat"), vanilla + "porkchop.png")
	_save(_item(Color(0.35, 0.9, 1.0), "wand"), arcana + "wand_of_sparks.png")
	var spark := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, y - 7.5)
			var star := minf(absf(d.x), absf(d.y)) < 1.0 and d.length() < 7.0
			if d.length() < 3.0 or star:
				spark.set_pixel(x, y, Color(0.75, 0.95, 1.0) if d.length() < 2.0 else Color(0.35, 0.8, 1.0, 0.9))
	_save(spark, arcana + "spark.png")
	var arrow := _blank()
	for i in range(3, 13):
		arrow.set_pixel(i, 15 - i, Color(0.55, 0.4, 0.25))
	for d in [Vector2i(12, 3), Vector2i(13, 2), Vector2i(12, 2), Vector2i(13, 3), Vector2i(11, 3), Vector2i(12, 4)]:
		arrow.set_pixel(d.x, d.y, Color(0.75, 0.75, 0.78))
	for d in [Vector2i(2, 12), Vector2i(3, 13), Vector2i(2, 13), Vector2i(4, 13), Vector2i(2, 11)]:
		arrow.set_pixel(d.x, d.y, Color(0.95, 0.95, 0.95))
	_save(arrow, vanilla + "arrow.png")
	_save(_item(Color(0.9, 0.88, 0.8), "shard"), vanilla + "bone.png")

	# Tools and armor (appended last so earlier textures keep their random sequence).
	var materials := {"wooden": Color(0.62, 0.45, 0.25), "stone": Color(0.6, 0.6, 0.63), "iron": Color(0.85, 0.85, 0.88)}
	for material in materials:
		for tool in ["pickaxe", "axe", "shovel"]:
			_save(_item(materials[material], tool), base + "%s_%s.png" % [material, tool])
	_save(_item(Color(0.85, 0.85, 0.88), "sword"), base + "iron_sword.png")
	_save(_item(Color(0.55, 0.4, 0.22), "stick"), base + "stick.png")
	_save(_item(Color(0.85, 0.85, 0.88), "ingot"), base + "iron_ingot.png")
	_save(_item(Color(0.55, 0.35, 0.2), "hide"), vanilla + "leather.png")
	var armors := {"leather": Color(0.55, 0.35, 0.2), "iron": Color(0.82, 0.83, 0.86)}
	for material in armors:
		for piece in ["helmet", "chestplate", "leggings", "boots"]:
			_save(_item(armors[material], piece), (vanilla if material == "leather" else base) + "%s_%s.png" % [material, piece])
	_save(_item(Color(0.62, 0.35, 0.95), "sword"), arcana + "soul_blade.png")
	_save(_item(Color(1.0, 0.8, 0.25), "pickaxe"), guild + "prospector_pick.png")
	# Worn armor in the 64x64 skin layout; each armor slot only uses the regions it covers.
	_save(_armor_layer(Color(0.78, 0.8, 0.84), Color(0.5, 0.52, 0.58)), base + "iron_armor.png")
	_save(_armor_layer(Color(0.55, 0.35, 0.2), Color(0.38, 0.23, 0.12)), vanilla + "leather_armor.png")

	# Farming and plants (appended last so earlier textures keep their random sequence).
	_save(_farmland(), base + "farmland_top.png")
	for stage in 4:
		_save(_wheat(stage), base + "wheat_%d.png" % stage)
	_save(_tall_grass(), base + "tall_grass.png")
	_save(_sapling(), base + "sapling.png")
	_save(_flower(Color(0.9, 0.15, 0.15), Color(0.2, 0.15, 0.1)), base + "poppy.png")
	_save(_flower(Color(1.0, 0.85, 0.15), Color(0.95, 0.6, 0.1)), base + "dandelion.png")
	_save(_seeds(), base + "wheat_seeds.png")
	_save(_wheat_item(), base + "wheat.png")
	_save(_bread(), base + "bread.png")
	for material in materials:
		_save(_hoe(materials[material]), base + "%s_hoe.png" % material)

	# Stations and containers (appended last so earlier textures keep their random sequence).
	_save(_crafting_table_top(), base + "crafting_table_top.png")
	_save(_crafting_table_side(), base + "crafting_table_side.png")
	_save(_chest(false), base + "chest_side.png")
	_save(_chest(true), base + "chest_top.png")
	_save(_furnace(0), base + "furnace_side.png")
	_save(_furnace(1), base + "furnace_front.png")
	_save(_furnace(2), base + "furnace_front_lit.png")
	_save(_item(Color(0.2, 0.17, 0.15), "lump"), base + "charcoal.png")
	_save(_item(Color(0.72, 0.42, 0.25), "meat"), vanilla + "cooked_porkchop.png")

	# Station upgrades (appended last so earlier textures keep their random sequence).
	_save(_anvil(true), base + "anvil_top.png")
	_save(_anvil(false), base + "anvil_side.png")
	_save(_tool_rack(), base + "tool_rack.png")
	_save(_bookshelf(), base + "bookshelf.png")
	_save(_sturdy_top(), base + "sturdy_workbench_top.png")
	_save(_sturdy_side(), base + "sturdy_workbench_side.png")
	_save(_forge_front(), base + "forge_front.png")
	_save(_reinforced_frame(), base + "reinforced_frame.png")
	_save(_banner(), guild + "guild_banner.png")
	_save(_blueprint(), base + "blueprint.png")
	_save(_torch(), base + "torch.png")
	_save(_hay(true), base + "hay_bale_top.png")
	_save(_hay(false), base + "hay_bale_side.png")
	# Part sprites: light grayscale shapes the client tints with each material's color.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base + "parts"))
	for part in ["pickaxe_head", "axe_head", "shovel_head", "sword_blade", "tool_handle", "binding", "sword_grip", "guard"]:
		_save(_part(part), base + "parts/%s.png" % part)

	# Food (appended last so earlier textures keep their random sequence).
	_save(_item(Color(0.5, 0.58, 0.3), "meat"), vanilla + "rotten_flesh.png")
	_save(_item(Color(0.78, 0.62, 0.4), "lump"), guild + "trail_ration.png")
	_save(_bottle(Color(0, 0, 0, 0)), base + "glass_bottle.png")
	_save(_bottle(Color(0.95, 0.72, 0.25)), base + "apple_juice.png")
	_save(_bottle(Color(0.65, 0.35, 1.0)), arcana + "mana_potion.png")
	_save(_bed_icon(), base + "bed_icon.png")

	# Farm animals (appended last so earlier textures keep their random sequence).
	_save(_item(Color(0.78, 0.25, 0.22), "meat"), vanilla + "raw_beef.png")
	_save(_item(Color(0.5, 0.3, 0.18), "meat"), vanilla + "steak.png")
	_save(_item(Color(0.95, 0.72, 0.62), "meat"), vanilla + "raw_chicken.png")
	_save(_item(Color(0.82, 0.58, 0.32), "meat"), vanilla + "cooked_chicken.png")
	_save(_feather(), vanilla + "feather.png")
	_save(_egg(), vanilla + "egg.png")
	_save(_bucket(Color(0, 0, 0, 0)), vanilla + "bucket.png")
	_save(_bucket(Color(0.97, 0.97, 0.95)), vanilla + "milk_bucket.png")
	_save(_shears(), vanilla + "shears.png")
	for color_name in WOOL_COLORS:
		var c: Color = WOOL_COLORS[color_name]
		_save(_wool(c), vanilla + "wool_%s.png" % color_name)
		_save(_bed_icon(c), vanilla + "bed_%s_icon.png" % color_name)
		if color_name != "brown":
			_save(_item(c, "shard"), vanilla + "dye_%s.png" % color_name)

	# Monsters (appended last so earlier textures keep their random sequence).
	_save(_string_icon(), vanilla + "string.png")
	_save(_item(Color(0.45, 0.8, 0.35), "lump"), vanilla + "slimeball.png")
	_save(_item(Color(0.22, 0.16, 0.32), "shard"), vanilla + "shadow_essence.png")
	_save(_item(Color(0.78, 0.3, 0.25), "lump"), vanilla + "boom_spores.png")

	# Biomes (appended last so earlier textures keep their random sequence).
	var woods := {"birch": [Color(0.9, 0.89, 0.84), Color(0.2, 0.2, 0.2), Color(0.45, 0.62, 0.3), Color(0.82, 0.74, 0.55)],
		"spruce": [Color(0.3, 0.21, 0.12), Color(0.22, 0.15, 0.08), Color(0.16, 0.34, 0.2), Color(0.5, 0.38, 0.24)],
		"acacia": [Color(0.45, 0.42, 0.38), Color(0.32, 0.3, 0.26), Color(0.42, 0.52, 0.18), Color(0.72, 0.42, 0.25)]}
	for wood_name in woods:
		var c: Array = woods[wood_name]
		_save(_bark(c[0], c[1], wood_name == "birch"), base + "%s_log_side.png" % wood_name)
		_save(_rings(c[0], c[3]), base + "%s_log_top.png" % wood_name)
		_save(_foliage(c[2]), base + "%s_leaves.png" % wood_name)
	_save(_cactus(false), base + "cactus_side.png")
	_save(_cactus(true), base + "cactus_top.png")
	_save(_sandstone(false), base + "sandstone_side.png")
	_save(_sandstone(true), base + "sandstone_top.png")
	_save(_dead_bush(), base + "dead_bush.png")
	_save(_fern(), base + "fern.png")

	# Fantasy biomes (appended last so earlier textures keep their random sequence).
	_save(_noise(Color(0.46, 0.4, 0.5), 0.08), vanilla + "mycelium_top.png")
	_save(_cap(_noise(Color(0.47, 0.32, 0.2), 0.07), Color(0.46, 0.4, 0.5), 3), vanilla + "mycelium_side.png")
	_save(_spotted(Color(0.78, 0.18, 0.16), Color(0.95, 0.92, 0.88)), vanilla + "mushroom_cap.png")
	_save(_noise(Color(0.88, 0.85, 0.76), 0.04), vanilla + "mushroom_stem.png")
	_save(_spotted(Color(0.2, 0.62, 0.72), Color(0.6, 0.98, 1.0)), vanilla + "glowcap.png")
	_save(_small_mushroom(Color(0.8, 0.2, 0.18)), vanilla + "red_mushroom.png")
	_save(_small_mushroom(Color(0.35, 0.85, 0.95)), vanilla + "glow_mushroom.png")
	_save(_bark(Color(0.2, 0.15, 0.26), Color(0.12, 0.08, 0.16), false), vanilla + "shadow_log_side.png")
	_save(_rings(Color(0.2, 0.15, 0.26), Color(0.32, 0.26, 0.4)), vanilla + "shadow_log_top.png")
	_save(_foliage(Color(0.22, 0.16, 0.34)), vanilla + "shadow_leaves.png")
	_save(_noise(Color(0.2, 0.3, 0.3), 0.08), vanilla + "gloomgrass_top.png")
	_save(_cap(_noise(Color(0.3, 0.22, 0.16), 0.07), Color(0.2, 0.3, 0.3), 3), vanilla + "gloomgrass_side.png")
	_save(_flower(Color(0.7, 0.5, 1.0), Color(0.95, 0.9, 1.0)), vanilla + "nightbloom.png")
	_save(_crystal(), arcana + "crystal_block.png")
	_save(_noise(Color(0.55, 0.5, 0.62), 0.06), arcana + "crystal_stone.png")

	# Underground and biome liquids (appended last so earlier textures keep their random sequence).
	_save(_lava(), base + "lava.png")
	_save(_ore(stone, Color(0.25, 0.45, 0.95)), base + "cobalt_ore.png")
	_save(_item(Color(0.3, 0.5, 0.95), "ingot"), base + "cobalt_ingot.png")
	_save(_noise(Color(0.35, 0.9, 0.95, 0.7), 0.05), vanilla + "glowing_water.png")
	_save(_noise(Color(0.1, 0.1, 0.18, 0.82), 0.03), vanilla + "gloom_water.png")
	_save(_pod(), vanilla + "shadow_pod.png")
	_save(_noise(Color(0.7, 0.45, 1.0, 0.7), 0.05), arcana + "mana_spring.png")
	_save(_cage(), base + "spawner.png")
	quit()


func _part(part: String) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var on := false
			var diagonal := absi(x - (15 - y)) <= 0
			match part:
				"pickaxe_head": on = (y >= 2 and y <= 3 and x >= 5 and x <= 14) or (y == 4 and (x == 5 or x == 14))
				"axe_head": on = x >= 8 and x <= 13 and y >= 1 and y <= 6 and not (x >= 11 and y >= 4)
				"shovel_head": on = Vector2(x - 11.0, y - 3.5).length() < 2.6
				"tool_handle": on = diagonal and y > 5
				"binding": on = (x >= 9 and x <= 11 and y >= 4 and y <= 6) and not (x == 11 and y == 6)
				"sword_blade": on = absi(x - (15 - y)) <= 1 and y < 10
				"sword_grip": on = (absi(x - (15 - y)) <= 0 and y >= 10) or (x < 2 and y > 13)
				"guard": on = (x - (y - 5)) in [0, 1] and y >= 7 and y <= 13
			if on:
				var shade := 0.95 - 0.05 * ((x + y) % 3) - (0.15 if part in ["binding", "guard"] and (x + y) % 2 == 0 else 0.0)
				img.set_pixel(x, y, Color(shade, shade, shade))
	return img


const WOOL_COLORS := {"white": Color(0.95, 0.95, 0.94), "gray": Color(0.54, 0.54, 0.55), "black": Color(0.15, 0.15, 0.16),
	"brown": Color(0.48, 0.32, 0.19), "red": Color(0.72, 0.19, 0.19), "orange": Color(0.91, 0.52, 0.16),
	"yellow": Color(0.94, 0.8, 0.25), "green": Color(0.36, 0.6, 0.17), "pink": Color(0.94, 0.6, 0.69)}


func _wool(c: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var curl := 0.06 * sin(x * 1.7 + y * 0.9) + 0.05 * cos(y * 2.1 - x * 0.6)
			img.set_pixel(x, y, _vary(c.lightened(curl) if curl > 0 else c.darkened(-curl), 0.03))
	return img


func _string_icon() -> Image:
	var img := _blank()
	for i in range(1, 15):
		var x := 4 + int(round(sin(i * 0.8) * 1.5)) + i / 2
		img.set_pixel(clampi(x, 0, 15), i, Color(0.92, 0.92, 0.9))
		img.set_pixel(clampi(x + 3, 0, 15), 15 - i, Color(0.85, 0.85, 0.83))
	return img


func _feather() -> Image:
	var img := _blank()
	for i in range(2, 14):
		img.set_pixel(i, 15 - i, Color(0.75, 0.72, 0.65))  # quill
	for i in range(4, 13):
		for w in range(1, 3 if i < 11 else 2):
			img.set_pixel(clampi(i - w, 0, 15), 15 - i - w, Color(0.97, 0.97, 0.95))
			img.set_pixel(clampi(i + w, 0, 15), 15 - i + w, Color(0.9, 0.9, 0.88))
	return img


func _egg() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2((x - 7.5) / 4.6, (y - 8.5) / (5.8 if y > 8 else 4.8)).length()
			if d < 1.0:
				img.set_pixel(x, y, Color(0.96, 0.9, 0.78) if not (x < 7 and y < 7) else Color(1.0, 0.97, 0.9))
	return img


func _bucket(fill: Color) -> Image:
	var img := _blank()
	var metal := Color(0.72, 0.73, 0.76)
	for y in range(4, 14):
		var half := 5 - (y - 4) / 3
		for x in range(8 - half - 1, 8 + half + 1):
			var edge: bool = x == 8 - half - 1 or x == 8 + half or y == 13
			img.set_pixel(x, y, metal.darkened(0.25) if edge else (fill if fill.a > 0.0 and y <= 6 else metal))
	for x in range(3, 13):
		img.set_pixel(x, 3, metal.darkened(0.15))
	for i in range(4):
		img.set_pixel(3 + i / 2, 3 - i, metal.darkened(0.3))
		img.set_pixel(12 - i / 2, 3 - i, metal.darkened(0.3))
	for x in range(5, 11):
		img.set_pixel(x, 0, metal.darkened(0.3))
	return img


func _shears() -> Image:
	var img := _blank()
	var blade := Color(0.82, 0.83, 0.86)
	for i in range(1, 9):
		img.set_pixel(6 + i, 9 - i, blade)
		img.set_pixel(6 + i, 8 - i, blade.darkened(0.2))
		img.set_pixel(9 - i, 6 + i, blade.darkened(0.1))
	for y in range(9, 14):
		for x in range(2, 7):
			if Vector2(x - 4, y - 11.5).length() < 2.0 and not Vector2(x - 4, y - 11.5).length() < 1.0:
				img.set_pixel(x, y, Color(0.3, 0.3, 0.32))
	return img


## A bed seen from the side: wooden frame and legs, a blanket (red by default), white pillow and a headboard.
func _bed_icon(blanket := Color(0.75, 0.22, 0.17)) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var c := Color(0, 0, 0, 0)
			if x <= 2 and y >= 4 and y <= 12:
				c = Color(0.54, 0.35, 0.2)  # headboard
			elif y >= 11 and y <= 12 and x >= 1 and x <= 15:
				c = Color(0.54, 0.35, 0.2)  # frame
			elif y >= 13 and y <= 14 and (x in [2, 3, 13, 14]):
				c = Color(0.42, 0.27, 0.14)  # legs
			elif y >= 7 and y <= 10 and x >= 3 and x <= 5:
				c = Color(0.97, 0.96, 0.92)  # pillow
			elif y >= 8 and y <= 10 and x >= 6 and x <= 15:
				c = blanket if y > 8 else blanket.lightened(0.15)  # blanket
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return img


## A glass bottle with a cork, filled with `liquid` (alpha 0 = empty).
func _bottle(liquid: Color) -> Image:
	var img := _blank()
	var glass := Color(0.78, 0.9, 0.95, 0.75)
	for y in TILE:
		for x in TILE:
			var neck := x >= 6 and x <= 9 and y >= 2 and y <= 5
			var body := Vector2((x - 7.5) * 0.9, (y - 10.0) * 1.05).length() < 4.6 and y >= 5
			if y <= 2 and x >= 6 and x <= 9:
				img.set_pixel(x, y, Color(0.6, 0.42, 0.25))  # cork
			elif neck or body:
				var edge := not (Vector2((x - 7.5) * 0.9, (y - 10.0) * 1.05).length() < 3.6 and y >= 6) and not (neck and x >= 7 and x <= 8)
				var fill := liquid.a > 0.0 and y >= 7 and not edge
				var c := liquid.darkened(0.12 * float(y - 7) / 7.0) if fill else glass
				if not fill and not edge:
					c = Color(0.85, 0.95, 1.0, 0.35)
				if x == 5 and y >= 8 and y <= 11:
					c = Color(1, 1, 1, 0.9)  # highlight
				img.set_pixel(x, y, c)
	return img


func _torch() -> Image:
	var img := _blank()
	for y in range(7, 16):
		img.set_pixel(7, y, Color(0.45, 0.3, 0.16))
		img.set_pixel(8, y, Color(0.38, 0.25, 0.13))
	for y in range(3, 7):
		for x in range(6, 10):
			var hot := y >= 5
			img.set_pixel(x, y, Color(1.0, 0.9, 0.45) if hot and (x == 7 or x == 8) else Color(1.0, 0.55 + 0.1 * rng.randf(), 0.12))
	img.set_pixel(7, 2, Color(1.0, 0.75, 0.2))
	return img


func _hay(top: bool) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var straw := Color(0.82, 0.7, 0.3) if (x + (y if top else 0)) % 3 != 0 else Color(0.72, 0.58, 0.22)
			if not top and (y == 3 or y == 12):
				straw = Color(0.5, 0.33, 0.15)  # binding
			img.set_pixel(x, y, _vary(straw, 0.05))
	return img


func _blueprint() -> Image:
	var img := _blank()
	for y in range(2, 14):
		for x in range(2, 14):
			var line := (x == 5 or y == 6 or (x >= 8 and x <= 11 and y == 10) or (x == 11 and y >= 8 and y <= 10))
			img.set_pixel(x, y, Color(0.85, 0.92, 1.0) if line else _vary(Color(0.18, 0.36, 0.72), 0.04))
	for x in range(2, 14):
		img.set_pixel(x, 2, Color(0.12, 0.25, 0.55))
		img.set_pixel(x, 13, Color(0.12, 0.25, 0.55))
	return img


func _banner() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			if y <= 1:
				img.set_pixel(x, y, Color(0.45, 0.3, 0.16))
			elif x >= 2 and x <= 13 and y < 13 + (1 if x % 3 == 0 else 0):
				img.set_pixel(x, y, _vary(Color(0.18, 0.4, 0.2), 0.04))
	for y in range(4, 10):
		for x in range(5, 11):
			if Vector2(x - 7.5, y - 6.5).length() < 3.2:
				img.set_pixel(x, y, Color(1.0, 0.82, 0.25))
	return img


func _anvil(top: bool) -> Image:
	var img := _blank()
	var iron := Color(0.36, 0.37, 0.4)
	for y in TILE:
		for x in TILE:
			var on := true
			if not top:
				# Silhouette: wide face, narrow waist, wide foot.
				var half := 7.5 if y < 5 else (3.5 if y < 11 else 6.5)
				on = absf(x - 7.5) <= half
			if on:
				var c := _vary(iron, 0.05)
				if (top and (x == 0 or x == TILE - 1 or y == 0 or y == TILE - 1)) or (not top and y == 0):
					c = iron.lightened(0.35)
				img.set_pixel(x, y, c)
	return img


func _tool_rack() -> Image:
	var img := _planks()
	for x in TILE:
		img.set_pixel(x, 2, Color(0.35, 0.24, 0.13))
	for tool in [[3, Color(0.75, 0.75, 0.78)], [8, Color(0.6, 0.6, 0.63)], [13, Color(0.62, 0.45, 0.25)]]:
		for y in range(3, 13):
			img.set_pixel(tool[0], y, Color(0.42, 0.29, 0.15))
		for dx in range(-2, 3):
			img.set_pixel(clampi(tool[0] + dx, 0, TILE - 1), 3, tool[1])
			img.set_pixel(clampi(tool[0] + dx, 0, TILE - 1), 4, tool[1].darkened(0.2))
	return img


func _bookshelf() -> Image:
	var img := _planks()
	var colors := [Color(0.6, 0.15, 0.12), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.2), Color(0.55, 0.45, 0.15), Color(0.4, 0.2, 0.45)]
	for shelf in [1, 9]:
		var x := 1
		while x < TILE - 1:
			var w := rng.randi_range(1, 2)
			var h := rng.randi_range(4, 6)
			var c: Color = colors[rng.randi_range(0, colors.size() - 1)]
			for bx in range(x, mini(x + w, TILE - 1)):
				for by in range(shelf + 6 - h, shelf + 6):
					img.set_pixel(bx, by, _vary(c, 0.06))
			x += w + (1 if rng.randf() < 0.3 else 0)
	return img


func _sturdy_top() -> Image:
	var img := _crafting_table_top()
	for i in TILE:
		for band in [0, TILE - 1]:
			img.set_pixel(i, band, Color(0.62, 0.63, 0.66))
			img.set_pixel(band, i, Color(0.62, 0.63, 0.66))
	for corner in [Vector2i(1, 1), Vector2i(14, 1), Vector2i(1, 14), Vector2i(14, 14)]:
		img.set_pixel(corner.x, corner.y, Color(0.85, 0.85, 0.88))
	return img


func _sturdy_side() -> Image:
	var img := _crafting_table_side()
	for x in TILE:
		img.set_pixel(x, 12, Color(0.55, 0.56, 0.6))
		img.set_pixel(x, 13, Color(0.45, 0.46, 0.5))
	for rivet in [2, 7, 12]:
		img.set_pixel(rivet, 12, Color(0.85, 0.85, 0.88))
	return img


func _forge_front() -> Image:
	var img := _brick()
	for y in range(7, 14):
		for x in range(3, 13):
			var heat := float(y - 7) / 6.0
			img.set_pixel(x, y, Color(1.0, 0.35 + 0.45 * heat * rng.randf(), 0.08) if y > 9 else Color(0.1, 0.07, 0.06))
	return img


func _reinforced_frame() -> Image:
	var img := _blank()
	var wood := Color(0.62, 0.45, 0.25)
	var iron := Color(0.8, 0.8, 0.84)
	for y in range(2, 14):
		for x in range(2, 14):
			var edge := x <= 3 or x >= 12 or y <= 3 or y >= 12
			var diagonal := absi(x - y) <= 0
			if edge or diagonal:
				img.set_pixel(x, y, _vary(wood, 0.05))
	for corner in [Vector2i(2, 2), Vector2i(12, 2), Vector2i(2, 12), Vector2i(12, 12)]:
		for dy in 2:
			for dx in 2:
				img.set_pixel(corner.x + dx, corner.y + dy, iron)
	return img


func _crafting_table_top() -> Image:
	var img := _planks()
	for y in TILE:
		for x in TILE:
			if (x == 2 or x == 7 or x == 13 or y == 2 or y == 7 or y == 13) and x >= 2 and x <= 13 and y >= 2 and y <= 13:
				img.set_pixel(x, y, Color(0.36, 0.25, 0.14))
	return img


func _crafting_table_side() -> Image:
	var img := _planks()
	for x in TILE:
		img.set_pixel(x, 0, Color(0.36, 0.25, 0.14))
		img.set_pixel(x, 1, Color(0.45, 0.32, 0.18))
	# A saw and a hammer hanging on the side.
	for x in range(3, 8):
		img.set_pixel(x, 6, Color(0.75, 0.75, 0.78))
		img.set_pixel(x, 7, Color(0.62, 0.62, 0.66))
	img.set_pixel(8, 6, Color(0.4, 0.27, 0.15))
	img.set_pixel(8, 7, Color(0.4, 0.27, 0.15))
	for y in range(5, 12):
		img.set_pixel(11, y, Color(0.4, 0.27, 0.15))
	for x in range(10, 13):
		img.set_pixel(x, 5, Color(0.55, 0.55, 0.58))
	return img


func _chest(top: bool) -> Image:
	var img := _blank()
	var wood := Color(0.62, 0.43, 0.22)
	for y in TILE:
		for x in TILE:
			var rim := x == 0 or x == TILE - 1 or y == 0 or y == TILE - 1 or (not top and y == 6)
			img.set_pixel(x, y, wood.darkened(0.4) if rim else _vary(wood, 0.05))
	if not top:
		for y in range(5, 9):
			for x in range(7, 9):
				img.set_pixel(x, y, Color(0.8, 0.8, 0.82))
	return img


func _furnace(kind: int) -> Image:
	var stone := Color(0.52, 0.52, 0.54)
	var img := _noise(stone, 0.06)
	for x in TILE:
		img.set_pixel(x, 0, stone.darkened(0.3))
		img.set_pixel(x, TILE - 1, stone.darkened(0.3))
	if kind == 0:
		return img
	for y in range(8, 14):
		for x in range(4, 12):
			var fire := Color(1.0, 0.55 + 0.3 * rng.randf(), 0.15) if kind == 2 and y >= 10 else Color(0.08, 0.07, 0.07)
			img.set_pixel(x, y, fire)
	for x in range(3, 13):
		img.set_pixel(x, 7, stone.darkened(0.45))
	return img


func _farmland() -> Image:
	var img := _noise(Color(0.34, 0.22, 0.13), 0.06)
	for y in TILE:
		if y % 4 == 1:
			for x in TILE:
				img.set_pixel(x, y, _vary(Color(0.24, 0.15, 0.09), 0.05))
	return img


## Crop stages: sprouts, leafy shoots, tall green stalks, golden ripe wheat.
func _wheat(stage: int) -> Image:
	var img := _blank()
	var height: int = [4, 8, 12, 14][stage]
	var stalk: Color = [Color(0.35, 0.7, 0.25), Color(0.35, 0.68, 0.22), Color(0.45, 0.65, 0.2), Color(0.78, 0.66, 0.28)][stage]
	for column in [2, 5, 8, 11, 14]:
		var h: int = height - (column % 3)
		for y in range(TILE - 1, TILE - 1 - h, -1):
			var sway := 1 if (TILE - y) > h * 0.6 and column % 2 == 0 else 0
			img.set_pixel(clampi(column + sway, 0, TILE - 1), y, _vary(stalk, 0.08))
		if stage == 3:
			for y in range(TILE - h, TILE - h + 4):
				img.set_pixel(clampi(column - 1, 0, TILE - 1), y, _vary(Color(0.9, 0.78, 0.35), 0.06))
				img.set_pixel(column, y, _vary(Color(0.85, 0.72, 0.3), 0.06))
	return img


func _tall_grass() -> Image:
	var img := _blank()
	for blade in 9:
		var x := rng.randi_range(1, TILE - 2)
		var h := rng.randi_range(6, 13)
		var lean := rng.randi_range(-1, 1)
		for i in h:
			img.set_pixel(clampi(x + (lean * i) / 5, 0, TILE - 1), TILE - 1 - i, _vary(Color(0.36, 0.62, 0.24), 0.1))
	return img


func _sapling() -> Image:
	var img := _blank()
	for y in range(8, TILE):
		img.set_pixel(7, y, _vary(Color(0.42, 0.29, 0.16), 0.05))
	for y in TILE:
		for x in TILE:
			if Vector2(x - 7.5, (y - 5.5) * 1.2).length() < 4.5 and rng.randf() > 0.15:
				img.set_pixel(x, y, _vary(Color(0.25, 0.55, 0.18), 0.12))
	return img


func _flower(petal: Color, center: Color) -> Image:
	var img := _blank()
	for y in range(7, TILE):
		img.set_pixel(7, y, _vary(Color(0.3, 0.58, 0.2), 0.05))
	img.set_pixel(8, 11, Color(0.3, 0.6, 0.2))
	img.set_pixel(9, 10, Color(0.3, 0.6, 0.2))
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.0, y - 4.5).length()
			if d < 1.2:
				img.set_pixel(x, y, center)
			elif d < 3.0:
				img.set_pixel(x, y, _vary(petal, 0.06))
	return img


func _seeds() -> Image:
	var img := _blank()
	for i in 9:
		var p := Vector2i(rng.randi_range(3, 12), rng.randi_range(4, 12))
		img.set_pixel(p.x, p.y, Color(0.45, 0.6, 0.2))
		img.set_pixel(p.x, p.y + 1, Color(0.35, 0.5, 0.15))
	return img


func _wheat_item() -> Image:
	var img := _blank()
	for i in range(2, 14):
		img.set_pixel(15 - i, i, _vary(Color(0.8, 0.68, 0.3), 0.05))
	for i in range(2, 8):
		img.set_pixel(15 - i - 1, i, _vary(Color(0.92, 0.8, 0.38), 0.05))
		img.set_pixel(15 - i + 1, i, _vary(Color(0.88, 0.75, 0.33), 0.05))
	return img


func _bread() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2((x - 7.5) / 6.5, (y - 8.5) / 3.5).length()
			if d < 1.0:
				var crust := Color(0.72, 0.45, 0.2) if y > 7 or d > 0.8 else Color(0.85, 0.6, 0.3)
				img.set_pixel(x, y, _vary(crust, 0.05))
	return img


func _hoe(head: Color) -> Image:
	var img := _blank()
	for y in range(4, 16):
		img.set_pixel(15 - y, y, _vary(Color(0.45, 0.3, 0.16), 0.05))
	for x in range(8, 14):
		img.set_pixel(x, 2, _vary(head, 0.05))
		img.set_pixel(x, 3, _vary(head.darkened(0.15), 0.05))
	img.set_pixel(8, 4, head)
	return img


## Box-unfold rectangles of a skin layout region [u, v, w, h, d]: top, bottom, right, front, left, back.
func _unfold(r: Array) -> Array:
	var u: int = r[0]
	var v: int = r[1]
	var w: int = r[2]
	var h: int = r[3]
	var d: int = r[4]
	return [Rect2i(u + d, v, w, d), Rect2i(u + d + w, v, w, d), Rect2i(u, v + d, d, h), Rect2i(u + d, v + d, w, h),
		Rect2i(u + d + w, v + d, d, h), Rect2i(u + 2 * d + w, v + d, w, h)]


func _armor_layer(plate: Color, trim: Color) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var regions := {"head": [0, 0, 8, 8, 8], "torso": [16, 16, 8, 12, 4], "arm_r": [40, 16, 4, 12, 4], "arm_l": [32, 48, 4, 12, 4],
		"leg_r": [0, 16, 4, 12, 4], "leg_l": [16, 48, 4, 12, 4]}
	for key in regions:
		var rects := _unfold(regions[key])
		for i in rects.size():
			var rect: Rect2i = rects[i]
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var edge := x == rect.position.x or x == rect.end.x - 1 or y == rect.position.y or y == rect.end.y - 1
					var c := trim if edge else _vary(plate, 0.05)
					if key == "head" and i == 3 and y >= rect.position.y + 3 and y <= rect.position.y + 5 and x > rect.position.x and x < rect.end.x - 1:
						c = Color(0, 0, 0, 0)  # visor slit
					if key == "torso" and i == 3 and y == rect.position.y + 5:
						c = trim  # belt line on the chest plate
					img.set_pixel(x, y, c)
	return img


func _meteorite(hot: bool) -> Image:
	var img := _noise(Color(0.2, 0.18, 0.2), 0.06)
	for i in 5:
		var x := rng.randi_range(0, 15)
		var y := rng.randi_range(0, 15)
		for n in 10:
			x = clampi(x + rng.randi_range(-1, 1), 0, 15)
			y = clampi(y + rng.randi_range(-1, 1), 0, 15)
			img.set_pixel(x, y, _vary(Color(1.0, 0.55, 0.15) if hot else Color(0.35, 0.3, 0.32), 0.08))
	return img


## Transparent-background item sprites.
func _item(color: Color, glyph: String) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var on := false
			match glyph:
				"lump": on = Vector2(x - 7.5, (y - 8.0) * 1.2).length() < 5.0 and rng.randf() > 0.08
				"shard": on = absf(x - 7.5) + absf(y - 7.5) * 0.45 < 3.2
				"wand": on = absi(x - (15 - y)) <= 0 and y > 3 or (Vector2(x - 11.5, y - 3.5).length() < 2.0)
				"coin": on = Vector2(x - 7.5, y - 7.5).length() < 5.5 and not (Vector2(x - 7.5, y - 7.5).length() < 3.5 and x == 7)
				"sword": on = (absi(x - (15 - y)) <= 1 and y < 11) or (absi(x - y) <= 0 and y > 8 and y < 13) or (x < 4 and y > 11)
				"apple": on = Vector2(x - 7.5, y - 9.0).length() < 5.0 or (x == 8 and y > 2 and y < 5)
				"meat": on = Vector2((x - 7.0) * 0.8, y - 8.0).length() < 5.0 or (x > 10 and absi(y - 12) <= 1)
				"pickaxe": on = (absi(x - (15 - y)) <= 0 and y > 4) or (y >= 2 and y <= 3 and x >= 5 and x <= 14) or (y == 4 and (x == 5 or x == 14))
				"axe": on = (absi(x - (15 - y)) <= 0 and y > 3) or (x >= 8 and x <= 13 and y >= 1 and y <= 6 and not (x >= 11 and y >= 4))
				"shovel": on = (absi(x - (15 - y)) <= 0 and y > 5) or Vector2(x - 11.0, y - 3.5).length() < 2.6
				"stick": on = absi(x - (15 - y)) <= 0 and y > 2 and y < 14
				"ingot": on = y >= 6 and y <= 10 and x >= 3 + (10 - y) / 2 and x <= 12 - (10 - y) / 2
				"hide": on = x >= 3 and x <= 12 and y >= 3 and y <= 12 and not ((x == 3 or x == 12) and (y == 3 or y == 12))
				"helmet": on = y >= 4 and y <= 9 and x >= 3 and x <= 12 and not (y >= 8 and x >= 5 and x <= 10)
				"chestplate": on = (y >= 3 and y <= 13 and x >= 4 and x <= 11 and not (y <= 5 and x >= 6 and x <= 9)) or (y >= 3 and y <= 6 and (x == 2 or x == 3 or x == 12 or x == 13))
				"leggings": on = (y >= 3 and y <= 5 and x >= 4 and x <= 11) or (y > 5 and y <= 13 and ((x >= 4 and x <= 6) or (x >= 9 and x <= 11)))
				"boots": on = (y >= 7 and y <= 12 and ((x >= 2 and x <= 5) or (x >= 9 and x <= 12))) or (y >= 11 and y <= 12 and ((x >= 2 and x <= 7) or (x >= 9 and x <= 14)))
			if on:
				var c := color if glyph != "wand" or y > 5 else color.lightened(0.4)
				if glyph == "wand" and y > 5:
					c = Color(0.45, 0.3, 0.18)
				if glyph == "sword" and y > 9:
					c = Color(0.4, 0.26, 0.14)  # hilt
				if glyph in ["pickaxe", "axe", "shovel"] and absi(x - (15 - y)) <= 0 and y > 5:
					c = Color(0.45, 0.3, 0.16)  # handle
				if glyph == "apple" and y < 5:
					c = Color(0.4, 0.26, 0.14)
				if glyph == "meat" and x > 10 and absi(y - 12) <= 1:
					c = Color(0.95, 0.92, 0.85)  # bone
				img.set_pixel(x, y, _vary(c, 0.06))
	return img


func _cable() -> Image:
	var img := _noise(Color(0.22, 0.22, 0.24), 0.03)
	for i in TILE:
		for w in range(6, 10):
			img.set_pixel(i, w, _vary(Color(0.78, 0.45, 0.2), 0.05))
			img.set_pixel(w, i, _vary(Color(0.78, 0.45, 0.2), 0.05))
	return img


## Simple item-style icons for model blocks (shown in the hotbar).
func _icon(frame: Color, accent: Color, glyph: String) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x < 2 or y < 2 or x > 13 or y > 13
			img.set_pixel(x, y, frame.darkened(0.3) if edge else _vary(frame, 0.04))
	for y in range(3, 13):
		for x in range(3, 13):
			var on := false
			match glyph:
				"flame": on = absf(x - 7.5) < (y - 3) * 0.45 and y > 4
				"grid": on = x % 3 == 0 or y % 3 == 0
				"bars": on = (x in [4, 5, 7, 8, 10, 11]) and y > 12 - (x / 3) * 2
				"bulb": on = Vector2(x - 7.5, y - 6.5).length() < 3.5 or (x in [7, 8] and y > 9)
				"drill": on = absf(x - 7.5) < (12 - y) * 0.35 or (y < 5 and x > 3 and x < 12)
			if on:
				img.set_pixel(x, y, _vary(accent, 0.06))
	return img


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("%s %s" % ["wrote" if err == OK else "FAILED", path])


func _blank() -> Image:
	return Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)


func _vary(c: Color, amount: float) -> Color:
	var v := rng.randf_range(-amount, amount)
	return Color(clampf(c.r + v, 0, 1), clampf(c.g + v, 0, 1), clampf(c.b + v, 0, 1), c.a)


func _noise(base: Color, amount: float) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _vary(base, amount))
	return img


## Colored top rows with a ragged edge (grass / snow sides).
func _cap(img: Image, color: Color, rows: int) -> Image:
	for x in TILE:
		for y in rows + rng.randi_range(0, 2):
			img.set_pixel(x, y, _vary(color, 0.06))
	return img


func _log_side() -> Image:
	var img := _blank()
	var bark := Color(0.4, 0.29, 0.16)
	for x in TILE:
		for y in TILE:
			img.set_pixel(x, y, _vary(bark.darkened(0.07 if x % 4 == 1 else 0.0), 0.04))
	return img


func _log_top() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var ring := int(Vector2(x - 7.5, y - 7.5).length()) % 2 == 0
			var c := Color(0.4, 0.29, 0.16) if edge else (Color(0.62, 0.48, 0.3) if ring else Color(0.7, 0.56, 0.36))
			img.set_pixel(x, y, _vary(c, 0.03))
	return img


func _bark(c: Color, streak: Color, spotted: bool) -> Image:
	var img := _blank()
	for x in TILE:
		for y in TILE:
			var p := _vary(c.darkened(0.07 if x % 4 == 1 else 0.0), 0.04)
			if spotted and rng.randf() < 0.1:
				p = streak
			img.set_pixel(x, y, p)
	return img


func _rings(edge: Color, wood: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var outer := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var ring := int(Vector2(x - 7.5, y - 7.5).length()) % 2 == 0
			img.set_pixel(x, y, _vary(edge if outer else (wood.darkened(0.12) if ring else wood), 0.03))
	return img


func _foliage(c: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, Color(0, 0, 0, 0) if rng.randf() < 0.18 else _vary(c, 0.1))
	return img


func _cage() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			if x % 5 == 0 or y % 5 == 0 or x == TILE - 1 or y == TILE - 1:
				img.set_pixel(x, y, _vary(Color(0.2, 0.22, 0.26), 0.05))
	return img


func _lava() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var heat := 0.5 + 0.5 * sin(x * 0.9 + y * 0.4) * cos(y * 0.7 - x * 0.3)
			img.set_pixel(x, y, _vary(Color(0.95, 0.35, 0.05).lerp(Color(1.0, 0.85, 0.2), heat), 0.05))
	return img


func _pod() -> Image:
	var img := _blank()
	img.set_pixel(7, 0, Color(0.2, 0.15, 0.26))
	img.set_pixel(7, 1, Color(0.2, 0.15, 0.26))
	for y in range(2, 12):
		for x in range(3, 13):
			var d := Vector2(x - 7.5, (y - 7.0) * 0.9).length()
			if d < 4.2:
				img.set_pixel(x, y, Color(0.85, 0.7, 1.0) if d < 2.0 else _vary(Color(0.6, 0.35, 0.95), 0.06))
	return img


func _spotted(c: Color, spot: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _vary(c, 0.05))
	for i in 5:
		var cx := rng.randi_range(2, 13)
		var cy := rng.randi_range(2, 13)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if absi(dx) + absi(dy) < 2:
					img.set_pixel(cx + dx, cy + dy, spot)
	return img


func _small_mushroom(cap: Color) -> Image:
	var img := _blank()
	for y in range(9, TILE):
		img.set_pixel(7, y, Color(0.9, 0.87, 0.78))
		img.set_pixel(8, y, Color(0.84, 0.8, 0.7))
	for y in range(5, 10):
		for x in range(3, 13):
			if Vector2(x - 7.5, (y - 9.0) * 1.6).length() < 5.0:
				img.set_pixel(x, y, _vary(cap, 0.06))
	return img


func _crystal() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var facet := (x + y) % 6 < 3
			img.set_pixel(x, y, _vary(Color(0.62, 0.36, 0.95) if facet else Color(0.78, 0.58, 1.0), 0.05))
	return img


func _cactus(top: bool) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			if x == 0 or x == TILE - 1 or (top and (y == 0 or y == TILE - 1)):
				continue
			var c := _vary(Color(0.3, 0.55, 0.22), 0.05)
			if not top and x % 3 == 1:
				c = c.darkened(0.2)
			if (x + y * 3) % 7 == 0:
				c = Color(0.85, 0.85, 0.7)  # spines
			img.set_pixel(x, y, c)
	return img


func _sandstone(top: bool) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var c := Color(0.86, 0.8, 0.58)
			if not top and (y == 3 or y == 12):
				c = c.darkened(0.12)
			img.set_pixel(x, y, _vary(c, 0.03))
	return img


func _dead_bush() -> Image:
	var img := _blank()
	var twig := Color(0.5, 0.36, 0.2)
	for i in 8:
		img.set_pixel(7, TILE - 1 - i, twig)
	for branch in [[7, 10, -1], [7, 8, 1], [7, 6, -1], [7, 5, 1]]:
		for i in 4:
			img.set_pixel(clampi(branch[0] + branch[2] * i, 0, TILE - 1), branch[1] - i, twig.darkened(0.1 * i))
	return img


func _fern() -> Image:
	var img := _blank()
	for frond in 5:
		var angle := -1.2 + frond * 0.6
		for i in 9:
			var x := 7.5 + sin(angle) * i
			var y := TILE - 1 - cos(angle) * i
			if x >= 0 and x < TILE and y >= 0:
				img.set_pixel(int(x), int(y), _vary(Color(0.26, 0.5, 0.2), 0.08))
	return img


func _leaves() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, Color(0, 0, 0, 0) if rng.randf() < 0.18 else _vary(Color(0.24, 0.52, 0.18), 0.1))
	return img


func _planks() -> Image:
	var img := _blank()
	var wood := Color(0.68, 0.52, 0.32)
	for y in TILE:
		for x in TILE:
			var seam := y % 4 == 3 or x == (4 if (y / 4) % 2 == 0 else 12)
			img.set_pixel(x, y, wood.darkened(0.35) if seam else _vary(wood, 0.04))
	return img


func _cobblestone() -> Image:
	var img := _blank()
	var points: Array[Vector2] = []
	var shades: Array[float] = []
	for i in 9:
		points.append(Vector2(rng.randf() * TILE, rng.randf() * TILE))
		shades.append(rng.randf_range(0.42, 0.6))
	for y in TILE:
		for x in TILE:
			var best := 1e9
			var second := 1e9
			var shade := 0.5
			for i in points.size():
				# Wrapped distances keep the tile seamless.
				var d := Vector2(x, y) - points[i]
				d = Vector2(minf(absf(d.x), TILE - absf(d.x)), minf(absf(d.y), TILE - absf(d.y)))
				var dist := d.length()
				if dist < best:
					second = best
					best = dist
					shade = shades[i]
				elif dist < second:
					second = dist
			var c := Color(0.3, 0.3, 0.3) if second - best < 1.2 else Color(shade, shade, shade + 0.02)
			img.set_pixel(x, y, _vary(c, 0.03))
	return img


func _glass() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
			var streak := (x == y + 3 or x == y + 4) and x > 3 and x < 9
			img.set_pixel(x, y, Color(0.82, 0.9, 0.95) if edge or streak else Color(0, 0, 0, 0))
	return img


func _ore(stone: Color, ore: Color) -> Image:
	var img := _noise(stone, 0.07)
	for i in 5:
		var cx := rng.randi_range(2, 13)
		var cy := rng.randi_range(2, 13)
		for n in 4:
			img.set_pixel(clampi(cx + rng.randi_range(-1, 1), 0, 15), clampi(cy + rng.randi_range(-1, 1), 0, 15), _vary(ore, 0.06))
	return img


func _brick() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var mortar := y % 4 == 3 or (x + (4 if (y / 4) % 2 == 1 else 0)) % 8 == 7
			img.set_pixel(x, y, Color(0.72, 0.7, 0.66) if mortar else _vary(Color(0.62, 0.27, 0.2), 0.05))
	return img


func _generator() -> Image:
	var img := _noise(Color(0.3, 0.3, 0.33), 0.05)
	for y in TILE:
		for x in TILE:
			if x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1:
				img.set_pixel(x, y, Color(0.15, 0.15, 0.17))
			elif x >= 3 and x <= 12 and y >= 3 and y <= 12:
				var hot := x < 8
				var c := Color(0.95, 0.5, 0.15) if hot else Color(0.25, 0.5, 0.95)
				img.set_pixel(x, y, _vary(c, 0.1))
	return img
