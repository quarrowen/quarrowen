extends SceneTree
## Paints the placeholder 16x16 block textures used by the bundled mods and writes them as PNGs.
##   godot --headless --path . -s tools/generate_textures.gd
##
## **118 of these currently print FAILED, and that is expected.** They write into `mods/vanilla` (82),
## `arcana` (13), `industry` (8), `guild` (8), `hearthhold` (6) and `skyblock` (1), all deleted on
## 21 September 2026; the directories are gone, so `save_png` refuses. 173 still write, `base` among
## them, and `base`'s come out byte-identical every run - this generator is deterministic.
##
## They are not simply deleted, for two reasons. The first is mechanical: one RNG seeded once drives
## every texture in order, so removing a call re-rolls every texture after it - the note on
## `_float_bob` records that silently changing three already-shipped textures. The second matters
## more: **most of these are not dead, they are unplaced.** Under the architecture settled the same
## day, `base` owns nouns - so porkchop, feather, wool, leather, egg and mushroom are base textures
## that happen to be written to a vanilla path, while bucket and shears belong to `simple_gear` and
## the machine icons to `simple_machines`. Only the arcana wands and guild coins are genuinely gone.
##
## Sorting that out *is* Phase 4's re-scope of `base`, and it is the one moment the re-roll is free,
## because every texture gets regenerated together anyway. Until then the FAILED lines are an accurate
## report of an unanswered question, which is better than a tidy file that has quietly picked answers.

const TILE := 16

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1337
	var stone := Color(0.49, 0.49, 0.51)
	var dirt := Color(0.47, 0.32, 0.2)
	var grass := Color(0.38, 0.64, 0.25)
	var snow := Color(0.95, 0.97, 1.0)
	var base := "res://mods/base/textures/"
	var machines := "res://mods/simple_machines/textures/"
	var gear := "res://mods/simple_gear/textures/"
	var book := "res://mods/guidebook/textures/"

	_save(_noise(stone, 0.07), base + "stone.png")
	_save(_noise(dirt, 0.07), base + "dirt.png")
	_save(_noise(grass, 0.09), base + "grass_top.png")
	_save(_cap(_noise(dirt, 0.07), grass, 3), base + "grass_side.png")
	_save(_noise(Color(0.87, 0.82, 0.58), 0.04), base + "sand.png")
	_save(_log_side(), base + "log_side.png")
	_save(_log_top(), base + "log_top.png")
	_save(_leaves(), base + "leaves.png")
	_save(_planks(), base + "planks.png")
	_save(_cobblestone(), gear + "cobblestone.png")
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
	_save(_item(Color(0.62, 0.45, 0.25), "sword"), gear + "wooden_sword.png")
	_save(_item(Color(0.6, 0.6, 0.63), "sword"), gear + "stone_sword.png")
	_save(_item(Color(0.85, 0.15, 0.15), "apple"), base + "apple.png")
	var vanilla := "res://mods/vanilla/textures/"
	# The `make_dir_recursive_absolute` that stood here is gone. With the mod deleted it was *creating*
	# `mods/vanilla/textures/` and filling it with sixty-odd PNGs for a mod that does not exist - a
	# stray folder that looks like somebody's work in progress. Without it these writes fail loudly,
	# the same as the other five dead mods below, which is what we want until Phase 4 says where each
	# of these textures actually belongs. (2026-09-21)
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
			_save(_item(materials[material], tool), gear + "%s_%s.png" % [material, tool])
	_save(_item(Color(0.85, 0.85, 0.88), "sword"), gear + "iron_sword.png")
	_save(_item(Color(0.55, 0.4, 0.22), "stick"), base + "stick.png")
	_save(_item(Color(0.85, 0.85, 0.88), "ingot"), base + "iron_ingot.png")
	_save(_item(Color(0.55, 0.35, 0.2), "hide"), vanilla + "leather.png")
	var armors := {"leather": Color(0.55, 0.35, 0.2), "iron": Color(0.82, 0.83, 0.86)}
	for material in armors:
		for piece in ["helmet", "chestplate", "leggings", "boots"]:
			_save(_item(armors[material], piece), (vanilla if material == "leather" else gear) + "%s_%s.png" % [material, piece])
	_save(_item(Color(0.62, 0.35, 0.95), "sword"), arcana + "soul_blade.png")
	_save(_item(Color(1.0, 0.8, 0.25), "pickaxe"), guild + "prospector_pick.png")
	# Worn armor in the 64x64 skin layout; each armor slot only uses the regions it covers.
	_save(_armor_layer(Color(0.78, 0.8, 0.84), Color(0.5, 0.52, 0.58)), gear + "iron_armor.png")
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
		_save(_hoe(materials[material]), gear + "%s_hoe.png" % material)

	# Stations and containers (appended last so earlier textures keep their random sequence).
	_save(_crafting_table_top(), machines + "crafting_table_top.png")
	_save(_crafting_table_side(), machines + "crafting_table_side.png")
	_save(_chest(false), machines + "chest_side.png")
	_save(_chest(true), machines + "chest_top.png")
	_save(_furnace(0), machines + "furnace_side.png")
	_save(_furnace(1), machines + "furnace_front.png")
	_save(_furnace(2), machines + "furnace_front_lit.png")
	_save(_item(Color(0.2, 0.17, 0.15), "lump"), machines + "charcoal.png")
	_save(_item(Color(0.72, 0.42, 0.25), "meat"), vanilla + "cooked_porkchop.png")

	# Station upgrades (appended last so earlier textures keep their random sequence).
	_save(_anvil(true), gear + "anvil_top.png")
	_save(_anvil(false), machines + "anvil_side.png")
	_save(_tool_rack(), gear + "tool_rack.png")
	_save(_bookshelf(), machines + "bookshelf.png")
	_save(_sturdy_top(), machines + "sturdy_workbench_top.png")
	_save(_sturdy_side(), machines + "sturdy_workbench_side.png")
	_save(_forge_front(), machines + "forge_front.png")
	_save(_reinforced_frame(), machines + "reinforced_frame.png")
	_save(_banner(), guild + "guild_banner.png")
	_save(_blueprint(), machines + "blueprint.png")
	_save(_torch(), base + "torch.png")
	_save(_hay(true), base + "hay_bale_top.png")
	_save(_hay(false), base + "hay_bale_side.png")
	# Part sprites: light grayscale shapes the client tints with each material's color.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(gear + "parts"))
	for part in ["pickaxe_head", "axe_head", "shovel_head", "sword_blade", "tool_handle", "binding", "sword_grip", "guard"]:
		_save(_part(part), gear + "parts/%s.png" % part)

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
	_save(_web(), vanilla + "cobweb.png")
	_save(_altar(), vanilla + "ancient_altar.png")
	_save(_guide_book(), book + "guide_book.png")



	# Graves (appended last so earlier textures keep their random sequence).
	_save(_grave(false), base + "grave_side.png")
	_save(_grave(true), base + "grave_top.png")
	# Cooking (appended last so earlier textures keep their random sequence).
	_save(_pot_side(), machines + "cooking_pot_side.png")
	_save(_pot_top(), machines + "cooking_pot_top.png")
	_save(_bowl(Color(0, 0, 0, 0)), machines + "bowl.png")
	_save(_pie(Color(0.9, 0.45, 0.3)), machines + "apple_pie.png")
	_save(_bowl(Color(0.55, 0.32, 0.18)), vanilla + "beef_stew.png")
	_save(_bowl(Color(0.78, 0.6, 0.35)), vanilla + "mushroom_stew.png")
	_save(_bowl(Color(0.45, 0.75, 0.55)), vanilla + "glowcap_soup.png")
	_save(_pie(Color(0.95, 0.82, 0.45)), vanilla + "honey_cake.png")
	_save(_bowl(Color(0.85, 0.75, 0.55)), vanilla + "hearty_feast.png")

	# Doors and windows (appended last so earlier textures keep their random sequence).
	_save(_door(false), base + "door_lower.png")
	_save(_door(true), base + "door_upper.png")
	_save(_bars(), base + "iron_bars.png")

	# Hearthhold (appended last so earlier textures keep their random sequence).
	var hearth := "res://mods/hearthhold/textures/"
	_save(_hearth(false), hearth + "hearth_cold.png")
	_save(_hearth(true), hearth + "hearth_lit.png")
	_save(_hearth_side(), hearth + "hearth_side.png")
	_save(_hearthstone(true), hearth + "hearthstone_top.png")
	_save(_hearthstone(false), hearth + "hearthstone_side.png")
	_save(_charter_board(), hearth + "charter_board.png")

	# Cobalt gear, deepstone and the charms (appended last so earlier textures keep their random sequence).
	var cobalt := Color(0.32, 0.5, 0.72)
	for tool in ["pickaxe", "axe", "shovel"]:
		_save(_item(cobalt, tool), gear + "cobalt_%s.png" % tool)
	_save(_item(cobalt, "sword"), gear + "cobalt_sword.png")
	for piece in ["helmet", "chestplate", "leggings", "boots"]:
		_save(_item(cobalt, piece), base + "cobalt_%s.png" % piece)
	_save(_armor_layer(cobalt, cobalt.darkened(0.35)), gear + "cobalt_armor.png")
	_save(_noise(Color(0.17, 0.17, 0.21), 0.05), base + "deepstone.png")
	_save(_charm(Color(0.35, 0.35, 0.4), Color(0.2, 0.2, 0.22)), gear + "miners_charm.png")
	_save(_charm(Color(0.6, 0.72, 0.5), Color(0.35, 0.28, 0.18)), gear + "wayfarers_charm.png")
	_save(_charm(cobalt, Color(0.3, 0.3, 0.34)), gear + "stoneheart_charm.png")
	_save(_colossus_heart(), vanilla + "colossus_heart.png")
	_save(_bow(), vanilla + "bow.png")
	_save(_arrow_item(), vanilla + "arrow_item.png")

	# Fishing (appended last so earlier textures keep their random sequence).
	_save(_fishing_rod(), vanilla + "fishing_rod.png")
	_save(_fish(Color(0.56, 0.66, 0.74), Color(0.85, 0.88, 0.9)), vanilla + "raw_fish.png")
	_save(_fish(Color(0.78, 0.56, 0.34), Color(0.92, 0.78, 0.56)), vanilla + "cooked_fish.png")

	# The float on the water. Appended after the fish, not beside the rod, because inserting a _save
	# anywhere but the end re-rolls every texture after it - which is what happened the first time this
	# line was written, and it silently changed three textures that had already shipped. (2026-09-18)
	_save(_float_bob(), vanilla + "float.png")

	# Signals: quickstone in the rock, the quickdust it grinds into, the lever that wakes it and the
	# lamp it lights. Appended at the end, like everything else, for the reason written above.
	_save(_quickstone(), machines + "quickstone.png")
	_save(_quickdust(false), machines + "quickdust.png")
	_save(_quickdust(true), machines + "quickdust_lit.png")
	_save(_quickdust_item(), machines + "quickdust_item.png")
	_save(_lever(), machines + "lever.png")
	_save(_quicklamp(false), machines + "quicklamp.png")
	_save(_quicklamp(true), machines + "quicklamp_lit.png")

	# The cable spool and the pole it is strung between (appended at the end, as everything is).
	var industry_late := "res://mods/industry/textures/"
	_save(_pole(), industry_late + "pole.png")
	_save(_spool(), industry_late + "cable_spool.png")

	_save(_blackglass(), base + "blackglass.png")
	_save(_full_bucket(Color(0.25, 0.48, 0.80), Color(0.42, 0.66, 0.92)), vanilla + "water_bucket.png")
	_save(_full_bucket(Color(0.86, 0.32, 0.08), Color(1.0, 0.68, 0.18)), vanilla + "lava_bucket.png")

	# Copper, gold and sunstone (appended last so earlier textures keep their random sequence).
	# Three ores and two metals was not a survival game: every tool tree ended in the same place.
	var copper := Color(0.76, 0.44, 0.24)
	var gold := Color(0.95, 0.76, 0.26)
	var sunstone := Color(1.0, 0.6, 0.2)
	_save(_ore(stone, copper.lightened(0.1)), base + "copper_ore.png")
	_save(_ore(stone, gold), base + "gold_ore.png")
	_save(_ore(stone, sunstone), base + "sunstone_ore.png")
	_save(_item(copper, "ingot"), base + "copper_ingot.png")
	_save(_item(gold, "ingot"), base + "gold_ingot.png")
	_save(_item(sunstone, "shard"), base + "sunstone.png")
	for metal in [[copper, "copper"], [gold, "gold"], [sunstone, "sunstone"]]:
		for tool in ["pickaxe", "axe", "shovel", "sword", "helmet", "chestplate", "leggings", "boots"]:
			_save(_item(metal[0], tool), gear + "%s_%s.png" % [metal[1], tool])
		_save(_armor_layer(metal[0], (metal[0] as Color).darkened(0.35)), gear + "%s_armor.png" % metal[1])

	# Deep variants (appended last so earlier textures keep their random sequence). The same metal in
	# deepstone rather than stone, so the wall tells you how far down you are without a coordinate.
	var deepstone := Color(0.17, 0.17, 0.21)
	_save(_ore(deepstone, Color(0.1, 0.1, 0.1)), base + "deep_coal_ore.png")
	_save(_ore(deepstone, Color(0.85, 0.68, 0.52)), base + "deep_iron_ore.png")
	_save(_ore(deepstone, copper.lightened(0.1)), base + "deep_copper_ore.png")
	_save(_ore(deepstone, gold), base + "deep_gold_ore.png")

	# **The colour sets, appended at the end** - as this file's own rule says, because one RNG seeded
	# once drives every texture in order and inserting a call anywhere above re-rolls everything after
	# it. The table lives in the mod (mods/base/colours.gd) rather than here, so the hue in a block's
	# name and the hue on its face cannot drift apart. (2026-09-23)
	var Colours = preload("res://mods/base/colours.gd")
	for entry in Colours.COLOURS:
		_save(_wool(entry[1]), base + "cloth_%s.png" % entry[0])
		_save(_plaster(entry[1]), base + "plaster_%s.png" % entry[0])

	# **Four textures written twice, on purpose.** An asset path is relative to the mod that names it,
	# and `simple_machines` names planks and brick for its benches and its forge. Copying them is
	# cheaper than it looks: assets travel to clients by content hash, so two identical files are one
	# transfer. The alternative is for the pack to reach into `base`'s folder, which is the kind of
	# thing that works until somebody moves a file. (2026-09-23)
	for shared_name in ["brick", "planks", "anvil_top", "tool_rack", "cobblestone"]:
		var from_base: String = base + shared_name + ".png"
		if ResourceLoader.exists(from_base):
			var copy := Image.load_from_file(ProjectSettings.globalize_path(from_base))
			_save(copy, String(machines) + shared_name + ".png")
			if shared_name in ["cobblestone", "anvil_top", "tool_rack"]:
				_save(copy, String(gear) + shared_name + ".png")

	# A SceneTree script runs until it is told not to. Without this the tool wrote every texture
	# correctly and then sat there for ever; three of them were found still running an hour later,
	# looking like a hung build rather than a finished one. (2026-09-19)
	quit()


## The heads a Tool Forge assembles from, cut from the same silhouettes the finished tools use.
##
## They were drawn a second time here, by hand, and so a forged pickaxe head and a basic pickaxe were
## different shapes - two descriptions of one thing, which is the arrangement that always drifts.
const HEAD_OF := {"pickaxe_head": "pickaxe", "axe_head": "axe", "shovel_head": "shovel"}


func _part(part: String) -> Image:
	var img := _blank()
	if HEAD_OF.has(part):
		var rows := _tool_rows(String(HEAD_OF[part]))
		for y in TILE:
			for x in TILE:
				var ch := rows[y][x]
				if ch != "#" and ch != "=":
					continue  # the head alone: a part is not a finished tool
				var lit := 0.95 - 0.05 * ((x + y) % 3) + (0.05 if ch == "=" else 0.0)
				img.set_pixel(x, y, Color(lit, lit, lit))
		return img
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
	return _lit(img)


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
	return _lit(img)


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
	return _lit(img)


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


## A scatter of seeds with a lit top and a body, rather than nine random two-pixel ticks. Placed
## rather than rolled: a handful of seeds wants to look scattered, and random placement at this size
## gives clumps and gaps that read as dirt.
func _seeds() -> Image:
	var img := _blank()
	var body := Color(0.47, 0.62, 0.24)
	var lit := Color(0.63, 0.77, 0.36)
	for spot in [Vector2i(5, 6), Vector2i(9, 5), Vector2i(7, 9), Vector2i(11, 9), Vector2i(4, 11), Vector2i(9, 12)]:
		img.set_pixel(spot.x, spot.y, _vary(lit, 0.04))
		img.set_pixel(spot.x, spot.y + 1, _vary(body, 0.04))
		img.set_pixel(spot.x + 1, spot.y + 1, _vary(body, 0.04))
	return _lit(img)


## A stalk with ears up it, rather than a diagonal smear. What says "wheat" is the pairs of grains
## angling up and away from a straight stem; the old one had the stem and nothing else. (2026-09-23)
func _wheat_item() -> Image:
	var img := _blank()
	var stem := Color(0.59, 0.49, 0.20)
	var grain := Color(0.89, 0.77, 0.38)
	var lit := Color(0.96, 0.87, 0.55)
	for y in range(4, 15):
		img.set_pixel(8, y, _vary(stem, 0.05))
	var tier := 0
	for y in range(3, 11, 2):
		var reach := 3 - tier / 2
		for k in range(1, reach + 1):
			var c := lit if k == reach else grain
			img.set_pixel(8 - k, y + k - 1, _vary(c, 0.05))
			img.set_pixel(8 + k, y + k - 1, _vary(c, 0.05))
		tier += 1
	img.set_pixel(8, 2, lit)
	img.set_pixel(8, 3, grain)
	for k in range(1, 4):
		img.set_pixel(8 + k, 12 + k / 3, _vary(stem, 0.05))  # a leaf low on the stem
	return _lit(img)


func _bread() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2((x - 7.5) / 6.5, (y - 8.5) / 3.5).length()
			if d < 1.0:
				var crust := Color(0.72, 0.45, 0.2) if y > 7 or d > 0.8 else Color(0.85, 0.6, 0.3)
				img.set_pixel(x, y, _vary(crust, 0.05))
	return _lit(img)


## A hoe: a blade set square across the end of the haft, hanging down on one side.
##
## It had the same fault the pickaxe had - a flat bar laid across the top of a stick - and the fix is
## the same one: the shape that says *hoe* is the right angle between haft and blade, and the blade
## hanging below the joint rather than balancing on top of it. (2026-09-23)
func _hoe(head: Color) -> Image:
	var img := _blank()
	var g := []
	for y in TILE:
		var row := []
		for x in TILE:
			row.append(".")
		g.append(row)
	_shaft(g, 9, 4, 2, 13)
	# The neck turns out of the haft, then the blade drops from it: an L, which is the whole silhouette.
	for x in range(10, 14):
		_mark(g, x, 3, "=")
	for y in range(4, 8):
		for x in range(12, 14):
			_mark(g, x, y, "#")
	_mark(g, 11, 4, "#")
	_mark(g, 14, 4, "=")
	_mark(g, 14, 5, "=")
	for y in TILE:
		for x in TILE:
			var ch: String = g[y][x]
			if ch == ".":
				continue
			var tone := head
			if ch == "=":
				tone = head.lightened(0.2)
			elif ch == "|":
				tone = HAFT
			elif ch == "+":
				tone = HAFT.lightened(0.18)
			img.set_pixel(x, y, _vary(tone, 0.05))
	return _lit(img)


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
	# The four tools are drawn from real silhouettes (see `_tool_rows`); everything else is still a
	# condition per glyph, which is fine for a lump or a coin and was never fine for a pickaxe.
	if glyph in ["pickaxe", "axe", "shovel", "sword", "helmet", "chestplate", "leggings", "boots", "ingot"]:
		var rows := _tool_rows(glyph) if glyph in ["pickaxe", "axe", "shovel", "sword"] \
			else _armour_rows(glyph)
		for y in TILE:
			for x in TILE:
				var ch := rows[y][x]
				if ch == ".":
					continue
				var tone := color
				if ch == "=":
					tone = color.lightened(0.22)
				elif ch == "-":
					tone = color.darkened(0.28)
				elif ch == "|":
					tone = HAFT
				elif ch == "+":
					tone = HAFT.lightened(0.18)
				img.set_pixel(x, y, _vary(tone, 0.05))
		return img
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
	return _lit(img)


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


## A leather-bound book with gold corners and a green bookmark ribbon.
func _guide_book() -> Image:
	var img := _blank()
	var leather := Color(0.52, 0.28, 0.14)
	for y in range(2, 15):
		for x in range(3, 13):
			var edge := x == 3 or x == 12 or y == 2 or y == 14
			img.set_pixel(x, y, leather.darkened(0.35) if edge else _vary(leather, 0.04))
	for y in range(3, 14):
		img.set_pixel(12, y, Color(0.95, 0.9, 0.75))  # page edges
		img.set_pixel(4, y, leather.darkened(0.2))  # spine line
	for c in [Vector2i(3, 2), Vector2i(11, 2), Vector2i(3, 14), Vector2i(11, 14)]:
		img.set_pixel(c.x, c.y, Color(0.95, 0.78, 0.25))
	for y in range(5, 9):
		for x in range(6, 11):
			if y == 5 or y == 8 or x == 6 or x == 10:
				img.set_pixel(x, y, Color(0.95, 0.78, 0.25))  # title plate
	img.set_pixel(8, 11, Color(0.95, 0.78, 0.25))
	for y in range(13, 16):
		img.set_pixel(9, y, Color(0.3, 0.65, 0.3))  # ribbon
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


func _web() -> Image:
	var img := _blank()
	var silk := Color(0.92, 0.92, 0.95, 0.9)
	for i in TILE:
		img.set_pixel(i, i, silk)
		img.set_pixel(TILE - 1 - i, i, silk)
		img.set_pixel(7, i, silk)
		img.set_pixel(i, 7, silk)
	for r in [3, 6]:
		for a in 24:
			var x: float = 7.5 + cos(a * TAU / 24.0) * r
			var y: float = 7.5 + sin(a * TAU / 24.0) * r
			img.set_pixel(clampi(int(x), 0, TILE - 1), clampi(int(y), 0, TILE - 1), silk)
	return img


func _altar() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var rune := (x == 7 or x == 8) and y > 2 and y < 13 or (y == 7 or y == 8) and x > 2 and x < 13
			img.set_pixel(x, y, Color(1.0, 0.7, 0.3) if rune else _vary(Color(0.35, 0.33, 0.36), 0.05))
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


## A mossy headstone: the side carries the stone slab, the top is bare earth and grass.
func _grave(top: bool) -> Image:
	var img := _noise(Color(0.42, 0.42, 0.45) if not top else Color(0.35, 0.28, 0.2), 0.08)
	if top:
		for y in TILE:
			for x in TILE:
				if (x + y) % 5 == 0:
					img.set_pixel(x, y, _vary(Color(0.3, 0.45, 0.24), 0.08))  # grass tufts on the mound
		return img
	for y in TILE:
		for x in TILE:
			if x >= 4 and x <= 11 and y >= 2:
				img.set_pixel(x, y, _vary(Color(0.58, 0.58, 0.6), 0.05))  # the stone itself
			if x >= 5 and x <= 10 and y >= 3 and y <= 4 and (x == 5 or x == 10 or y == 3):
				img.set_pixel(x, y, Color(0.3, 0.3, 0.32))  # a carved arch
	for x in range(6, 10):
		img.set_pixel(x, 7, Color(0.32, 0.32, 0.34))
	for y in range(6, 10):
		img.set_pixel(7, y, Color(0.32, 0.32, 0.34))
	return img

## A black iron pot: a fat belly with a rim, seen from the side.
func _pot_side() -> Image:
	var img := _noise(Color(0.2, 0.2, 0.22), 0.05)
	for y in TILE:
		for x in TILE:
			var outside := Vector2((x - 7.5) * 0.85, (y - 9.5) * 0.95).length() > 6.2
			if y <= 3 and outside:
				img.set_pixel(x, y, Color(0.35, 0.33, 0.3))  # the stone it stands on shows past the rim
			elif y >= 3 and y <= 4:
				img.set_pixel(x, y, Color(0.3, 0.3, 0.33))  # rim
			elif outside and y > 4:
				img.set_pixel(x, y, Color(0.35, 0.33, 0.3))
	for x in range(4, 12):
		img.set_pixel(x, 12, Color(0.14, 0.14, 0.16))  # a shadow where the fire licks it
	return img


## Looking down into the pot: stew, with a lazy bubble or two.
func _pot_top() -> Image:
	var img := _noise(Color(0.2, 0.2, 0.22), 0.05)
	for y in TILE:
		for x in TILE:
			var r := Vector2(x - 7.5, y - 7.5).length()
			if r < 5.6:
				img.set_pixel(x, y, _vary(Color(0.62, 0.38, 0.2), 0.06))
			elif r < 6.4:
				img.set_pixel(x, y, Color(0.3, 0.3, 0.33))
	for spot in [Vector2(6, 6), Vector2(9, 8), Vector2(7, 10)]:
		img.set_pixel(int(spot.x), int(spot.y), Color(0.78, 0.55, 0.3))
	return img


## A wooden bowl, filled when the meal has a colour.
func _bowl(filling: Color) -> Image:
	var img := _blank()
	var wood := Color(0.55, 0.38, 0.22)
	# **A rim, and a hollow under it.** Empty, this used to be one flat ellipse of wood - a brown
	# pebble. A bowl reads as a bowl because you can see into it, so the rim is lighter than the body
	# and what is inside is darker than both, whether that is stew or shadow. (2026-09-23)
	for y in TILE:
		for x in TILE:
			var dx := (x - 7.5) / 6.3
			var dy := (y - 9.2) / 4.2
			if dx * dx + dy * dy > 1.0 or y < 6:
				continue
			if y <= 7:
				img.set_pixel(x, y, _vary(wood.lightened(0.18), 0.05))
			elif y <= 8 and absf(x - 7.5) < 4.6:
				img.set_pixel(x, y, _vary(filling if filling.a > 0.0 else wood.darkened(0.35), 0.05))
			else:
				img.set_pixel(x, y, _vary(wood.darkened(0.3 if y > 11 else 0.0), 0.05))
	return _lit(img)


## A round pie or cake with a lattice top.
func _pie(crust: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			if Vector2(x - 7.5, y - 8.0).length() > 6.0:
				continue
			var edge := Vector2(x - 7.5, y - 8.0).length() > 4.6
			img.set_pixel(x, y, _vary(Color(0.78, 0.6, 0.35) if edge else crust, 0.06))
	for i in range(3, 13):
		img.set_pixel(i, 8, Color(0.85, 0.7, 0.45))
		img.set_pixel(8, i, Color(0.85, 0.7, 0.45))
	return img


## The outpost hearth seen from above: a ring of stones round ash, or round a fire once it is lit.
func _hearth(lit: bool) -> Image:
	var img := _noise(Color(0.34, 0.33, 0.32), 0.07)
	for y in TILE:
		for x in TILE:
			var r := Vector2(x - 7.5, y - 7.5).length()
			if r > 6.6:
				continue
			if r > 5.0:
				img.set_pixel(x, y, _vary(Color(0.52, 0.51, 0.5), 0.08))  # the ring of stones
			elif lit:
				var heat := 1.0 - r / 5.0
				img.set_pixel(x, y, _vary(Color(0.95, 0.55 + 0.35 * heat, 0.18).lerp(Color(1, 0.95, 0.6), heat * heat), 0.06))
			else:
				img.set_pixel(x, y, _vary(Color(0.22, 0.21, 0.2), 0.09))  # cold ash
	if lit:
		for spot in [Vector2(6, 5), Vector2(9, 7), Vector2(7, 9)]:
			img.set_pixel(int(spot.x), int(spot.y), Color(1.0, 0.98, 0.82))
	return img


func _hearth_side() -> Image:
	var img := _noise(Color(0.4, 0.39, 0.38), 0.08)
	for y in TILE:
		for x in TILE:
			if y < 3:
				img.set_pixel(x, y, _vary(Color(0.52, 0.51, 0.5), 0.07))  # the rim, seen edge on
			elif (x + y * 3) % 7 == 0:
				img.set_pixel(x, y, _vary(Color(0.33, 0.32, 0.31), 0.05))  # mortar between the stones
	return img


## The hearthstone: a slab with a carved mark, lit from within by a small ember.
func _hearthstone(top: bool) -> Image:
	var img := _noise(Color(0.46, 0.45, 0.47), 0.06)
	if not top:
		for x in TILE:
			img.set_pixel(x, 3, _vary(Color(0.36, 0.35, 0.37), 0.04))
			img.set_pixel(x, 12, _vary(Color(0.36, 0.35, 0.37), 0.04))
		return img
	# A simple house shape scratched into the top: a roof over a square.
	for x in range(4, 12):
		img.set_pixel(x, 11, Color(0.88, 0.62, 0.3))
	for y in range(7, 12):
		img.set_pixel(4, y, Color(0.88, 0.62, 0.3))
		img.set_pixel(11, y, Color(0.88, 0.62, 0.3))
	for i in 4:
		img.set_pixel(4 + i, 7 - i + 3, Color(0.95, 0.72, 0.38))
		img.set_pixel(11 - i, 7 - i + 3, Color(0.95, 0.72, 0.38))
	img.set_pixel(7, 9, Color(1.0, 0.85, 0.5))
	img.set_pixel(8, 9, Color(1.0, 0.85, 0.5))
	return img


## A plank door. The upper half carries a small window; the lower half a handle, on the side it opens.
func _door(upper: bool) -> Image:
	var img := _planks()
	for y in TILE:
		for x in TILE:
			if x <= 1 or x >= 14:
				img.set_pixel(x, y, _vary(Color(0.32, 0.22, 0.13), 0.05))  # the stiles down each edge
	if upper:
		for y in range(3, 8):
			for x in range(5, 11):
				var edge: bool = x == 5 or x == 10 or y == 3 or y == 7
				img.set_pixel(x, y, Color(0.3, 0.2, 0.12) if edge else Color(0.55, 0.78, 0.86, 0.85))
	else:
		for y in range(6, 9):
			img.set_pixel(12, y, Color(0.75, 0.64, 0.3))  # the handle
		img.set_pixel(11, 7, Color(0.82, 0.72, 0.36))
	return img


## Iron bars: uprights with a band across, so a window reads as barred rather than merely dark.
func _bars() -> Image:
	var img := _blank()
	var iron := Color(0.62, 0.63, 0.66)
	for y in TILE:
		for x in [2, 7, 13]:
			img.set_pixel(x, y, _vary(iron.darkened(0.1 if x == 7 else 0.0), 0.06))
	for x in TILE:
		img.set_pixel(x, 1, _vary(iron, 0.05))
		img.set_pixel(x, 14, _vary(iron, 0.05))
	return img


## The charter board: planks with a nailed-on notice, and handwriting too small to read as anything but
## handwriting - which is the point, since what it says is on the panel, not the block.
## A bow: the stave curved back, the string straight across it. Drawn at rest rather than fully bent, so
## it reads as a bow in the hotbar rather than as a letter D.
func _bow() -> Image:
	var img := _blank()
	var wood := Color(0.55, 0.38, 0.2)
	for y in range(2, 14):
		var t := (y - 8.0) / 6.0
		var x := int(round(10.5 - 3.5 * (1.0 - t * t)))
		img.set_pixel(x, y, _vary(wood, 0.06))
		img.set_pixel(clampi(x + 1, 0, 15), y, _vary(wood.darkened(0.2), 0.06))
	for y in range(2, 14):
		img.set_pixel(10, y, Color(0.88, 0.86, 0.8))  # the string
	for tip in [2, 13]:
		img.set_pixel(10, tip, wood.darkened(0.35))
	return img


## A loose arrow, lying corner to corner: flint head one end, fletching the other.
func _arrow_item() -> Image:
	var img := _blank()
	for i in range(3, 14):
		img.set_pixel(i, 16 - i, Color(0.55, 0.4, 0.25))
	for d in [Vector2i(12, 3), Vector2i(13, 2), Vector2i(12, 2), Vector2i(13, 3), Vector2i(11, 4)]:
		img.set_pixel(d.x, d.y, Color(0.72, 0.72, 0.76))  # the head
	for d in [Vector2i(3, 12), Vector2i(3, 13), Vector2i(4, 13), Vector2i(2, 12), Vector2i(5, 12)]:
		img.set_pixel(d.x, d.y, Color(0.93, 0.93, 0.95))  # the fletching
	return img


## The Colossus heart: a lump of dark stone with something lit inside it, brightest at the middle. It has
## to read as alive at 16x16, so the glow is a gradient rather than a shape.
func _colossus_heart() -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2(x - 7.5, (y - 8.0) * 1.1).length()
			if d > 6.0:
				continue
			if d < 3.0:
				img.set_pixel(x, y, _vary(Color(1.0, 0.72, 0.35).lerp(Color(1.0, 0.95, 0.7), 1.0 - d / 3.0), 0.05))
			else:
				img.set_pixel(x, y, _vary(Color(0.32, 0.22, 0.2).lerp(Color(0.85, 0.4, 0.2), (6.0 - d) / 3.0), 0.06))
	return img


## A charm: a stone on a cord. The stone is what differs between them, so the three read as a set at a
## glance in the hotbar and as three different things once you look.
func _charm(stone: Color, cord: Color) -> Image:
	var img := _blank()
	for y in range(1, 7):
		img.set_pixel(7 - (y / 3), y, cord)
		img.set_pixel(8 + (y / 3), y, cord)
	for y in range(6, 14):
		for x in range(4, 12):
			if Vector2(x - 7.5, y - 9.5).length() < 3.6:
				img.set_pixel(x, y, _vary(stone, 0.07))
	for x in range(6, 10):
		img.set_pixel(x, 7, stone.lightened(0.25))  # a highlight so it reads as round
	return img


func _charter_board() -> Image:
	var img := _planks()
	for y in range(2, 14):
		for x in range(3, 13):
			var edge: bool = x == 3 or x == 12 or y == 2 or y == 13
			img.set_pixel(x, y, Color(0.72, 0.66, 0.52) if not edge else Color(0.55, 0.45, 0.3))
	for row in range(4, 12, 2):
		# A line of writing, ragged at the end the way handwriting is.
		var width: int = 7 if row % 4 == 0 else 5
		for x in range(5, 5 + width):
			img.set_pixel(x, row, Color(0.32, 0.27, 0.22))
	for corner in [Vector2(4, 3), Vector2(11, 3), Vector2(4, 12), Vector2(11, 12)]:
		img.set_pixel(int(corner.x), int(corner.y), Color(0.45, 0.45, 0.48))  # the nails
	return img


## A rod held corner to corner with a line hanging off the tip. The line is drawn a pixel at a time
## rather than as a straight run so it reads as string rather than as a crack in the icon.
func _fishing_rod() -> Image:
	var img := _blank()
	var wood := Color(0.52, 0.36, 0.2)
	for y in range(3, 16):
		var x := 15 - y
		img.set_pixel(x, y, _vary(wood, 0.06))
		if y > 10:
			img.set_pixel(x - 1, y, _vary(wood.darkened(0.2), 0.05))  # the grip is thicker
	var line := Color(0.86, 0.86, 0.8)
	for y in range(3, 11):
		img.set_pixel(12 if y < 7 else 13, y, line)
	img.set_pixel(13, 11, Color(0.8, 0.25, 0.2))  # the float, the one spot of colour
	img.set_pixel(13, 12, Color(0.9, 0.9, 0.9))
	return img


## A fish in profile: body, tail, and an eye, which is what makes it read as a fish at 16 pixels.
func _fish(body: Color, belly: Color) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			var d := Vector2((x - 8.0) / 5.5, (y - 8.0) / 2.8).length()
			if d < 1.0:
				img.set_pixel(x, y, _vary(belly if y > 8 else body, 0.05))
	for y in range(5, 12):
		for x in range(2, 5):
			if absi(y - 8) >= x - 1:  # a notched tail
				img.set_pixel(x, y, _vary(body.darkened(0.15), 0.05))
	img.set_pixel(11, 7, Color(0.1, 0.1, 0.12))
	return img


## The float that sits on the water: a red top, a white bottom and a waterline between them, which is
## what makes it read as floating rather than as a ball. Drawn small in the middle of the tile so it
## stays a dot at a distance instead of a smear.
func _float_bob() -> Image:
	var img := _blank()
	var red := Color(0.86, 0.20, 0.16)
	# Not white below the line: a white float on bright water disappears, and this is a thing a child has
	# to be able to see at fifteen paces. A dark slate reads against water and against sky both.
	var below := Color(0.28, 0.30, 0.34)
	for y in range(3, 13):
		for x in range(3, 13):
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d < 4.2:
				img.set_pixel(x, y, _vary(red if y < 8 else below, 0.04))
			elif d < 4.9:
				img.set_pixel(x, y, Color(0.12, 0.10, 0.10, 0.85))  # an outline, so it never merges with the water
	for x in range(4, 12):
		if absf(x - 7.5) < 3.6:
			img.set_pixel(x, 8, Color(0.97, 0.96, 0.92))  # the waterline band
	for spot in [Vector2i(6, 5), Vector2i(7, 4)]:
		img.set_pixel(spot.x, spot.y, red.lightened(0.4))  # a highlight, so it is not a flat disc
	return img


## Quickstone in the rock: not scattered specks like the other ores, but **crystal veins with a glow
## around them**. The halo is the whole trick - a bright pixel on dark stone reads as a fleck of paint,
## and the same pixel with two dimmer rings around it reads as something giving off light. Finding one
## in a dark cave should feel like a find. (the user, 2026-09-19: "really nice glowy sparkly")
func _quickstone() -> Image:
	var img := _noise(Color(0.30, 0.29, 0.34), 0.06)
	var core := Color(1.0, 0.86, 0.42)
	var glow := Color(0.98, 0.62, 0.16)
	var veins := []
	for i in 3:
		var x := rng.randi_range(3, 12)
		var y := rng.randi_range(3, 12)
		for n in rng.randi_range(3, 5):  # a short crooked run, like a crystal seam
			veins.append(Vector2i(x, y))
			x = clampi(x + rng.randi_range(-1, 1), 1, 14)
			y = clampi(y + rng.randi_range(-1, 1), 1, 14)
	# Two rings of halo first, then the bright cores on top, so the glow never paints over a core.
	for cell: Vector2i in veins:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var d := Vector2(dx, dy).length()
				if d < 0.5 or d > 2.4:
					continue
				var at := Vector2i(clampi(cell.x + dx, 0, 15), clampi(cell.y + dy, 0, 15))
				var here := img.get_pixelv(at)
				img.set_pixelv(at, here.lerp(glow, 0.55 if d < 1.5 else 0.22))
	for cell: Vector2i in veins:
		img.set_pixelv(cell, _vary(core, 0.05))
	for n in 5:  # a few sparks off the seams, so it glitters rather than sits there
		img.set_pixel(rng.randi_range(0, 15), rng.randi_range(0, 15), core.lightened(0.3))
	return img


## Quickdust laid on the ground: a bright line with a warm glow either side of it, drawn as a cross so
## a run reads as joined up whichever way it turns. `lit` is the same dust carrying a level - brighter,
## whiter at the core and sparkier - so a powered wire is plainly the *same thing* doing something,
## rather than a different block.
func _quickdust(lit: bool) -> Image:
	var img := _blank()
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, Color(0.16, 0.13, 0.11, 0.0))
	var core := Color(1.0, 0.94, 0.66) if lit else Color(0.96, 0.68, 0.24)
	var glow := Color(1.0, 0.72, 0.24) if lit else Color(0.72, 0.42, 0.12)
	# The halo lines beside the run: this is what makes it glow instead of being a stripe.
	for i in TILE:
		for pair in [[5, 0.30 if lit else 0.16], [6, 0.75 if lit else 0.45], [9, 0.75 if lit else 0.45], [10, 0.30 if lit else 0.16]]:
			var t: int = int(pair[0])
			var a: float = float(pair[1])
			img.set_pixel(i, t, Color(glow.r, glow.g, glow.b, a))
			img.set_pixel(t, i, Color(glow.r, glow.g, glow.b, a))
	for i in TILE:
		for t in [7, 8]:
			img.set_pixel(i, t, _vary(core, 0.06))
			img.set_pixel(t, i, _vary(core, 0.06))
	for n in (22 if lit else 14):  # grains, so it is dust and not paint
		img.set_pixel(rng.randi_range(0, 15), rng.randi_range(6, 10), _vary(core.lightened(0.35), 0.08))
	if lit:
		for spot in [Vector2i(3, 7), Vector2i(11, 8), Vector2i(7, 12)]:
			img.set_pixelv(spot, Color(1.0, 1.0, 0.92))  # bright sparks along the run
	return img


## The same dust in the hand: a small heap rather than a line, so the item and the block are plainly
## the same stuff without the item looking like a length of wire.
func _quickdust_item() -> Image:
	var img := _blank()
	var warm := Color(0.95, 0.66, 0.22)
	# **A heap, which is wide at the bottom.** This was the other way up - widest at the top row and
	# narrowing downward - so a pile of dust drew as a funnel and read as a bowl. (2026-09-23)
	for y in range(8, 14):
		var half := 1 + (y - 8)
		for x in range(8 - half, 8 + half + 1):
			img.set_pixel(x, y, _vary(warm.darkened(0.25) if y > 12 else warm, 0.07))
	for n in 9:
		var x := rng.randi_range(5, 11)
		var y := rng.randi_range(9, 12)
		if img.get_pixel(x, y).a > 0.0:
			img.set_pixel(x, y, _vary(warm.lightened(0.3), 0.1))
	return _lit(img)


## A lever: a pale base plate with a dark handle leaning out of it.
func _lever() -> Image:
	var img := _blank()
	var stone := Color(0.52, 0.52, 0.55)
	for y in range(9, 14):
		for x in range(5, 11):
			img.set_pixel(x, y, _vary(stone, 0.05))
	var wood := Color(0.46, 0.32, 0.20)
	for n in 7:
		img.set_pixel(8 - n / 3, 10 - n, _vary(wood, 0.05))
		img.set_pixel(9 - n / 3, 10 - n, _vary(wood.darkened(0.12), 0.05))
	img.set_pixel(6, 3, Color(0.78, 0.62, 0.42))  # the knob on the end
	img.set_pixel(7, 3, Color(0.78, 0.62, 0.42))
	return img


## A lamp, dark and lit. The lit one is the same lamp with the glow turned up rather than a different
## design, so a child can see at a glance that it is one thing in two states.
##
## Lit is drawn as light *coming from the middle* rather than as a filled square: a flat yellow panel
## reads as a yellow block, and the whole point is that it should read as switched on.
func _quicklamp(lit: bool) -> Image:
	var img := _blank()
	var shell := Color(0.34, 0.31, 0.28)
	var core := Color(1.0, 0.95, 0.72)
	var edge_glass := Color(0.86, 0.52, 0.14) if lit else Color(0.26, 0.25, 0.24)
	for y in TILE:
		for x in TILE:
			if x < 2 or x > 13 or y < 2 or y > 13:
				img.set_pixel(x, y, _vary(shell.lightened(0.18 if lit else 0.0), 0.04))
				continue
			if not lit:
				img.set_pixel(x, y, _vary(Color(0.28, 0.27, 0.26), 0.05))
				continue
			# Bright in the middle, falling off to the frame: light with somewhere to come from.
			var d := Vector2(x - 7.5, y - 7.5).length() / 8.0
			img.set_pixel(x, y, _vary(core.lerp(edge_glass, clampf(d * 1.25, 0.0, 1.0)), 0.04))
	if lit:
		for spot in [Vector2i(5, 5), Vector2i(10, 6), Vector2i(6, 10), Vector2i(9, 11)]:
			img.set_pixelv(spot, Color(1.0, 1.0, 0.95))  # sparks in the glass
		for corner in [Vector2i(2, 2), Vector2i(13, 2), Vector2i(2, 13), Vector2i(13, 13)]:
			img.set_pixelv(corner, shell.lightened(0.45))  # the frame catching the light
	return img


## A cable pole: creosoted timber, drawn as a post with its grain running up it. It is a fence shape in
## the world, so only the middle of this tile is ever seen.
func _pole() -> Image:
	var img := _blank()
	var wood := Color(0.34, 0.26, 0.20)
	for y in TILE:
		for x in TILE:
			var post: bool = x >= 5 and x <= 10
			img.set_pixel(x, y, _vary(wood if post else wood.darkened(0.35), 0.05))
	for y in TILE:
		if y % 5 != 2:
			continue
		for x in range(5, 11):  # the bands where the insulators would be
			img.set_pixel(x, y, _vary(Color(0.52, 0.44, 0.34), 0.04))
	return img


## A spool of cable in the hand: a wound drum seen end on, with the copper showing through.
func _spool() -> Image:
	var img := _blank()
	var drum := Color(0.42, 0.34, 0.26)
	var copper := Color(0.80, 0.48, 0.20)
	for y in range(3, 13):
		for x in range(3, 13):
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d > 5.0:
				continue
			# Rings of wound cable, so it reads as wound rather than as a disc.
			var wound: bool = int(d) % 2 == 0
			img.set_pixel(x, y, _vary(copper if wound else copper.darkened(0.3), 0.06))
	for y in range(3, 13):
		for x in [4, 11]:
			if Vector2(x - 7.5, y - 7.5).length() <= 5.4:
				img.set_pixel(x, y, _vary(drum, 0.05))  # the cheeks of the drum
	for spot in [Vector2i(9, 4), Vector2i(10, 5)]:
		img.set_pixelv(spot, copper.lightened(0.35))  # a loose end catching the light
	return img


## Blackglass: what lava leaves behind when water finds it. Near-black with a cold purple sheen and a
## few sharp highlights, so it reads as glassy rather than as another dark stone.
func _blackglass() -> Image:
	var img := _blank()
	var base_colour := Color(0.09, 0.07, 0.13)
	for y in TILE:
		for x in TILE:
			img.set_pixel(x, y, _vary(base_colour, 0.03))
	for n in 14:  # facets catching what little light there is
		var cx := rng.randi_range(0, 15)
		var cy := rng.randi_range(0, 15)
		var shade := Color(0.20, 0.14, 0.30).lerp(Color(0.32, 0.22, 0.44), rng.randf())
		for d in rng.randi_range(2, 4):
			img.set_pixel(clampi(cx + d, 0, 15), clampi(cy + d, 0, 15), _vary(shade, 0.04))
	for n in 5:
		img.set_pixel(rng.randi_range(0, 15), rng.randi_range(0, 15), Color(0.52, 0.42, 0.66))
	return img


## A bucket with something in it: the same pail as the empty one, with a surface near the top and a
## lighter band on it so it reads as full rather than as a painted bucket.
func _full_bucket(liquid: Color, shine: Color) -> Image:
	var img := _blank()
	var tin := Color(0.62, 0.64, 0.68)
	for y in range(5, 14):
		var inset := 0 if y < 12 else 1
		for x in range(3 + inset, 13 - inset):
			var wall: bool = x <= 4 + inset or x >= 11 - inset or y >= 12
			img.set_pixel(x, y, _vary(tin.darkened(0.25) if wall else liquid, 0.05))
	for x in range(5, 11):
		img.set_pixel(x, 6, _vary(shine, 0.05))  # the surface catching the light
	for x in range(3, 13):
		img.set_pixel(x, 5, _vary(tin.lightened(0.15), 0.04))  # the rim
	img.set_pixel(3, 4, tin.darkened(0.1))
	img.set_pixel(12, 4, tin.darkened(0.1))
	for x in range(4, 12):  # the handle, arching over
		if x == 4 or x == 11:
			img.set_pixel(x, 3, tin)
		elif x % 2 == 0:
			img.set_pixel(x, 2, tin)
	return img

## A painted render: flat colour, a fine grain, and a few flecks where the trowel caught.
##
## Deliberately much calmer than `_wool`, which curls. The two sets carry the same sixteen hues, so
## the *texture* is the only thing telling a wall of one from a wall of the other - if both were busy
## they would read as the same block at any distance.
func _plaster(c: Color) -> Image:
	var img := _noise(c, 0.022)
	for n in 7:
		var x := rng.randi_range(0, TILE - 1)
		var y := rng.randi_range(0, TILE - 1)
		img.set_pixel(x, y, _vary(c.darkened(0.10), 0.02))
	return img

## The haft every tool shares. One colour, so a wooden pickaxe and an iron one are plainly the same
## tool in different metal.
const HAFT := Color(0.45, 0.31, 0.16)


## The four tool silhouettes, as 16 rows of characters: `.` nothing, `#` head, `=` its lit edge,
## `|` haft, `+` the haft's lit side.
##
## **Shapes, not one-line conditions.** These were a boolean expression each, and a condition like
## `y >= 2 and y <= 3 and x >= 5 and x <= 14` can only ever say *rectangle* - so the pickaxe came out
## as a flat bar across the top of a slanted stick, which is a sledgehammer. (the user, 2026-09-23:
## "the pickaxe for example looks like a slanted hammer".) What makes each of these read as itself is
## a curve: a pickaxe is an arc tapering to two points, an axe is a wedge with a convex edge and a
## narrowed neck, a spade is a blade with a rounded digging end. Curves have to be drawn as curves.
func _tool_rows(glyph: String) -> PackedStringArray:
	var g := []
	for y in TILE:
		var row := []
		for x in TILE:
			row.append(".")
		g.append(row)
	match glyph:
		"pickaxe": _draw_pickaxe(g)
		"axe": _draw_axe(g)
		"shovel": _draw_shovel(g)
		"sword": _draw_sword(g)
	var out := PackedStringArray()
	for row: Array in g:
		out.append("".join(row))
	return out


func _mark(g: Array, x: int, y: int, ch: String) -> void:
	if x >= 0 and x < TILE and y >= 0 and y < TILE:
		g[y][x] = ch


## A two-pixel haft, so it reads as a shaft rather than as a dotted line of single pixels.
func _shaft(g: Array, x0: int, y0: int, x1: int, y1: int) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := int(round(float(x0) + float(x1 - x0) * t))
		var y := int(round(float(y0) + float(y1 - y0) * t))
		_mark(g, x, y, "|")
		_mark(g, x + 1, y, "+")


## Lights whatever edge faces the sky. Cheap, and it is most of what stops a silhouette reading flat.
func _crown(g: Array) -> void:
	for y in TILE:
		for x in TILE:
			if g[y][x] == "#" and y > 0 and g[y - 1][x] == ".":
				g[y][x] = "="


func _draw_pickaxe(g: Array) -> void:
	var cx := 7.5
	var cy := 10.2
	var r := 7.4
	for y in TILE:
		for x in TILE:
			var dx := float(x) - cx
			var dy := float(y) - cy
			if dy > 0.4:
				continue
			var ang := atan2(-dy, dx)
			if ang <= 0.30 or ang >= PI - 0.30:
				continue
			# Thick at the crown, tapering to a point at each tip. The taper is the whole difference
			# between a pickaxe and a bar lying on a stick.
			var half := 0.45 + 1.25 * pow(sin(ang), 0.7)
			if absf(sqrt(dx * dx + dy * dy) - r) <= half:
				g[y][x] = "#"
	for y in range(4, 7):
		for x in range(6, 10):
			if g[y][x] == ".":
				g[y][x] = "="  # the eye the haft passes through
	_shaft(g, 7, 5, 2, 14)
	_crown(g)


func _draw_axe(g: Array) -> void:
	for y in range(2, 11):
		var t := (float(y) - 6.0) / 4.0
		# The bit pulls away from the shaft at top and bottom, which is the neck; without it the head
		# is a slab bolted to a stick.
		var left := 8.0 + maxf(0.0, absf(float(y) - 6.0) - 2.0) * 1.3
		var right := 14.2 - 2.4 * t * t
		for x in TILE:
			if float(x) >= left and float(x) <= right:
				g[y][x] = "#"
	_shaft(g, 8, 6, 2, 14)
	# On an axe the lit edge is the cutting edge, which is the far side rather than the top.
	for y in TILE:
		for x in TILE:
			if g[y][x] == "#" and x + 1 < TILE and g[y][x + 1] == ".":
				g[y][x] = "="


func _draw_shovel(g: Array) -> void:
	for y in range(1, 9):
		var t := (float(y) - 1.0) / 7.0
		var half := 2.7 - 1.5 * t * t
		if y == 1:
			half -= 1.0  # a rounded digging edge rather than a flat lip, or it reads as a bucket
		for x in TILE:
			if absf(float(x) - 9.0) <= half:
				g[y][x] = "#"
	for y in range(7, 9):
		for x in range(8, 10):
			g[y][x] = "="  # the socket the haft goes into
	_shaft(g, 8, 8, 2, 14)
	_crown(g)


func _draw_sword(g: Array) -> void:
	for i in 11:
		_mark(g, 14 - i, 1 + i, "#")
		_mark(g, 13 - i, 1 + i, "=")
	_mark(g, 15, 0, "=")
	_mark(g, 14, 0, "=")
	# The crossguard runs square to the blade, not along the screen: a guard parallel to the blade is
	# the thing that made the old one read as a bent stick.
	for t in range(-2, 3):
		_mark(g, 4 + t, 11 + t, "=")
	for i in 3:
		_mark(g, 3 - i, 12 + i, "|")
		_mark(g, 4 - i, 12 + i, "+")
	_mark(g, 0, 15, "=")
	_mark(g, 1, 15, "=")

## The four armour pieces, in the same character rows the tools use, plus `-` for a shaded edge.
##
## **Two tones were not enough.** A belt drawn one shade lighter than the leg below it is not a belt
## at 16 pixels, it is a leg; the first attempt came out as an archway. What separates the parts of a
## piece of armour is a *dark* line - a brow under a dome, a seam down a breastplate, a cuff, a sole -
## so these get a third tone and spend it on exactly those. (2026-09-23)
func _armour_rows(piece: String) -> PackedStringArray:
	var g := []
	for y in TILE:
		var row := []
		for x in TILE:
			row.append(".")
		g.append(row)
	match piece:
		"helmet": _draw_helmet(g)
		"chestplate": _draw_chestplate(g)
		"leggings": _draw_leggings(g)
		"boots": _draw_boots(g)
		"ingot": _draw_ingot(g)
	var out := PackedStringArray()
	for row: Array in g:
		out.append("".join(row))
	return out


func _fill(g: Array, x0: int, x1: int, y0: int, y1: int, ch := "#") -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_mark(g, x, y, ch)


func _draw_helmet(g: Array) -> void:
	for y in TILE:
		for x in TILE:
			if y <= 10 and sqrt(pow((float(x) - 7.5) / 6.2, 2.0) + pow((float(y) - 8.0) / 6.6, 2.0)) <= 1.0:
				g[y][x] = "#"
	_fill(g, 4, 11, 7, 7, "-")    # the brow: a shadow line is what turns a dome into a helmet
	_fill(g, 5, 10, 8, 10, ".")   # the sight opening
	_fill(g, 4, 5, 8, 10, "#")    # cheeks either side of it
	_fill(g, 10, 11, 8, 10, "#")
	_fill(g, 4, 11, 11, 11, "-")  # and a chin bar to close it
	_crown(g)


func _draw_chestplate(g: Array) -> void:
	_fill(g, 4, 11, 4, 12)
	_fill(g, 2, 3, 4, 7)          # pauldrons, or it is a shirt
	_fill(g, 12, 13, 4, 7)
	_fill(g, 6, 9, 3, 4, ".")     # neck opening
	_fill(g, 7, 8, 6, 11, "-")    # centre seam
	_fill(g, 4, 11, 12, 12, "-")  # belted hem
	_crown(g)


func _draw_leggings(g: Array) -> void:
	_fill(g, 3, 12, 3, 5)
	_fill(g, 3, 12, 5, 5, "-")    # the belt, dark, or waist and leg read as one slab
	_fill(g, 3, 6, 6, 13)
	_fill(g, 9, 12, 6, 13)
	_fill(g, 3, 6, 13, 13, "-")   # cuffs
	_fill(g, 9, 12, 13, 13, "-")
	_crown(g)


func _draw_boots(g: Array) -> void:
	for x0 in [1, 9]:
		_fill(g, x0, x0 + 4, 3, 9)        # the shaft
		_fill(g, x0, x0 + 6, 10, 12)      # the foot, stepping forward
		_fill(g, x0, x0 + 6, 13, 13, "-")  # and a sole, so it stands on something
	_crown(g)


## An ingot: a flat lit top face, sloping sides, a dark foot.
##
## The old one was a trapezoid drawn in a single tone, and a single-tone trapezoid with noise on it is
## a pebble. What makes a cast bar read is that you are looking at *two* faces of it at once - the top
## you could stamp, and the side that falls away from it. (2026-09-23)
func _draw_ingot(g: Array) -> void:
	_fill(g, 5, 10, 6, 7, "=")    # the top face, square on
	_fill(g, 4, 11, 8, 8)         # the shoulders, falling away
	_fill(g, 3, 12, 9, 10)
	_fill(g, 3, 12, 11, 11, "-")  # and the foot it sits on


## The one light every item here is lit by: from up and to the left.
##
## **Art direction, not an engine feature.** The same pass could run in the client over every mod's
## icons at once, and that would be the engine having an opinion about what content looks like, which
## is the one opinion it is not supposed to have. A mod that wants glossy items draws them glossy.
## (the user, 2026-09-23: "we can't add some kind of gloss or something for items eh")
##
## Edges facing the light lift, edges facing away drop, and the corner square to it gets a little
## more. It is the cheapest thing that turns a cut-out silhouette into something solid - a single tone
## with noise on it reads as a sticker whatever shape it is cut into, which is why the ingots looked
## like pebbles even after they were the right shape.
const LIT_LIFT := 0.36
const LIT_DROP := 0.26
const LIT_SPEC := 0.16


func _lit(img: Image) -> Image:
	# Read from a copy: lighting a pixel and then asking its neighbour about it walks the highlight
	# across the sprite one pixel at a time.
	# `duplicate()` is typed Resource, so this must be annotated or the whole script fails to parse
	# and every texture silently stops being generated (CLAUDE.md).
	var src: Image = img.duplicate()
	for y in TILE:
		for x in TILE:
			var c: Color = src.get_pixel(x, y)
			if c.a < 0.8:
				continue
			var up := _clear(src, x, y - 1)
			var left := _clear(src, x - 1, y)
			var k := 0.0
			if up or left:
				k += LIT_LIFT
			if up and left:
				k += LIT_SPEC
			if _clear(src, x, y + 1) or _clear(src, x + 1, y):
				k -= LIT_DROP
			if k > 0.0:
				img.set_pixel(x, y, c.lerp(Color(1.0, 1.0, 1.0, c.a), k))
			elif k < 0.0:
				img.set_pixel(x, y, c.darkened(-k))
	return img


## Whether nothing is drawn at this pixel. Off the tile counts as nothing, so a sprite that runs to
## the edge is still lit along it.
func _clear(img: Image, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= TILE or y >= TILE:
		return true
	return img.get_pixel(x, y).a < 0.8
