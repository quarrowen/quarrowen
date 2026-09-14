extends RefCounted
## Farm animals, built on the engine's breeding, entity looks and spawn rules:
## - cows: beef and leather; right-click with a bucket for milk (a drink that also cures food poisoning)
## - sheep: shear with shears for wool in the sheep's color (it regrows); dye a sheep to change its
##   color; wool comes in nine colors and makes matching beds
## - chickens: chicken meat and feathers; hens lay an egg every few minutes
## - wolves: wild ones hunt in packs only when provoked; tame one with bones and it follows you, fights
##   for you and sits when you right-click it (a red collar shows it is yours)
## All breed when fed (wheat for cows and sheep, seeds for chickens, meat for wolves) and babies grow up.

const COLORS := {"white": "#f2f2f0", "gray": "#8a8a8c", "black": "#2a2a2c", "brown": "#7a5230", "red": "#b83030",
	"orange": "#e8862a", "yellow": "#f0cc40", "green": "#5c9a2c", "pink": "#f09ab0"}
## Dyes from plants and materials; the rest are mixed.
const DYE_SOURCES := {"white": "vanilla:bone", "black": "base:coal", "red": "base:poppy", "yellow": "base:dandelion", "green": "base:sapling"}
const DYE_MIXES := {"orange": ["red", "yellow"], "pink": ["red", "white"], "gray": ["black", "white"]}
const NATURAL_COLORS := [["white", 0.82], ["gray", 0.06], ["black", 0.06], ["brown", 0.06]]
const REGROW_SECONDS := [60.0, 150.0]
const EGG_SECONDS := [150.0, 300.0]

var api
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	api.register_sound("cow_ambient", "sounds/cow_ambient.wav", {"pitch_variance": 0.08})
	api.register_sound("cow_hurt", "sounds/cow_hurt.wav", {"pitch_variance": 0.08})
	api.register_sound("sheep_ambient", "sounds/sheep_ambient.wav", {"pitch_variance": 0.1})
	api.register_sound("sheep_hurt", "sounds/sheep_hurt.wav", {"pitch_variance": 0.1})
	api.register_sound("chicken_ambient", "sounds/chicken_ambient.wav", {"pitch_variance": 0.12})
	api.register_sound("chicken_hurt", "sounds/chicken_hurt.wav", {"pitch_variance": 0.1})
	api.register_sound("shear", "sounds/shear.wav")
	api.register_sound("wolf_ambient", "sounds/wolf_ambient.wav", {"pitch_variance": 0.1})
	api.register_sound("wolf_hurt", "sounds/wolf_hurt.wav", {"pitch_variance": 0.1})
	api.register_sound("wolf_growl", "sounds/wolf_growl.wav", {"pitch_variance": 0.1})
	api.register_sound("milk", "sounds/milk.wav")
	_register_items()
	_register_wool()
	_register_entities()
	api.on("entity_spawned", _on_spawned)
	api.on("entity_interact", _on_interact)
	api.on("entity_bred", _on_bred)
	api.on("entity_tamed", func(ev):
		if ev.entity.type == ids.wolf:
			ev.entity.set_look({"hide": []})  # the collar appears
			ev.player.send_message("The wolf is yours! Right-click it to make it sit or stand.")
			api.play_sound("wolf_ambient", ev.entity.position))
	api.on("entity_sit", func(ev):
		if ev.player != null and ev.entity.type == ids.wolf:
			ev.player.show_title("", "Sit" if ev.sitting else "Follow", 1.0))
	api.on("entity_death", _on_death)
	api.on("player_eat", func(ev):
		if ev.item == ids.milk:
			for id in ev.player.modifiers.keys():
				if String(id).begins_with("food:"):
					ev.player.remove_modifier(id)
			ev.player.show_title("", "Refreshing", 1.0))
	api.every(5.0, _tick)


func _register_items() -> void:
	ids.beef = api.register_item("raw_beef", {"display_name": "Raw Beef", "icon": "textures/raw_beef.png", "food": {"hunger": 3, "saturation": 1.8, "color": "#c04040"}})
	ids.steak = api.register_item("steak", {"display_name": "Steak", "icon": "textures/steak.png", "food": {"hunger": 8, "saturation": 12.8, "color": "#80502c"}})
	ids.raw_chicken = api.register_item("raw_chicken", {"display_name": "Raw Chicken", "icon": "textures/raw_chicken.png",
		"food": {"hunger": 2, "saturation": 1.2, "color": "#f0b8a0",
			"effects": [{"stat": "hunger_drain", "amount": 0.5, "seconds": 30, "chance": 0.3, "message": "Food poisoning!"}]}})
	ids.cooked_chicken = api.register_item("cooked_chicken", {"display_name": "Cooked Chicken", "icon": "textures/cooked_chicken.png",
		"food": {"hunger": 6, "saturation": 7.2, "color": "#d09050"}})
	api.register_process("smelting", "vanilla:raw_beef", "vanilla:steak", 1, 8.0)
	api.register_process("smelting", "vanilla:raw_chicken", "vanilla:cooked_chicken", 1, 8.0)
	ids.feather = api.register_item("feather", {"display_name": "Feather", "icon": "textures/feather.png"})
	ids.egg = api.register_item("egg", {"display_name": "Egg", "icon": "textures/egg.png", "max_stack": 16})
	ids.bucket = api.register_item("bucket", {"display_name": "Bucket", "icon": "textures/bucket.png", "max_stack": 16})
	api.register_recipe({"base:iron_ingot": 3}, "vanilla:bucket", 1, {"station": "crafting_table", "category": "tools"})
	ids.milk = api.register_item("milk_bucket", {"display_name": "Milk Bucket", "icon": "textures/milk_bucket.png", "max_stack": 1,
		"food": {"hunger": 1, "saturation": 1.0, "always": true, "eat_time": 1.6, "style": "drink", "color": "#f8f8f4", "remainder": "vanilla:bucket"},
		"lore": ["Cures food poisoning"]})
	ids.shears = api.register_item("shears", {"display_name": "Shears", "icon": "textures/shears.png", "durability": 238})
	api.register_recipe({"base:iron_ingot": 2}, "vanilla:shears", 1, {"station": "crafting_table", "category": "tools"})


func _register_wool() -> void:
	var soft := {"break": "base:grass", "place": "base:grass", "step": "base:soft_step"}
	for color in COLORS:
		ids["wool_" + color] = api.register_block("wool_" + color, {"display_name": "%s Wool" % String(color).capitalize(),
			"textures": "textures/wool_%s.png" % color, "sounds": soft, "hardness": 0.8})
		# Colored beds: three wool of a color and three planks.
		var common := {"orientation": "horizontal", "bed": true, "hardness": 0.6, "tool": "axe", "drops": "vanilla:bed_" + color,
			"textures": "textures/bed_%s_icon.png" % color, "sounds": {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"}}
		var foot := common.duplicate()
		foot.merge({"display_name": "%s Bed" % String(color).capitalize(), "model": "models/bed_%s_foot.glb" % color,
			"pair": {"block": "vanilla:bed_%s_head" % color, "direction": "back"}})
		api.register_block("bed_" + color, foot)
		var head := common.duplicate()
		head.merge({"display_name": "%s Bed" % String(color).capitalize(), "model": "models/bed_%s_head.glb" % color, "placeable": false,
			"pair": {"block": "vanilla:bed_" + color, "direction": "front"}})
		api.register_block("bed_%s_head" % color, head)
		api.register_recipe({"vanilla:wool_" + color: 3, "base:planks": 3}, "vanilla:bed_" + color, 1, {"station": "crafting_table", "category": "blocks"})
	for color in COLORS:
		if color == "brown":
			continue  # brown wool only comes from brown sheep
		ids["dye_" + color] = api.register_item("dye_" + color, {"display_name": "%s Dye" % String(color).capitalize(), "icon": "textures/dye_%s.png" % color})
	for color in DYE_SOURCES:
		api.register_recipe({DYE_SOURCES[color]: 1}, "vanilla:dye_" + color, 2, {"category": "materials"})
	for color in DYE_MIXES:
		api.register_recipe({"vanilla:dye_" + DYE_MIXES[color][0]: 1, "vanilla:dye_" + DYE_MIXES[color][1]: 1}, "vanilla:dye_" + color, 2, {"category": "materials"})
	for color in COLORS:
		if color != "white" and color != "brown":
			api.register_recipe({"vanilla:wool_white": 1, "vanilla:dye_" + color: 1}, "vanilla:wool_" + color, 1, {"category": "blocks"})


func _register_entities() -> void:
	ids.cow = api.register_entity("cow", {"kind": "mob", "model": "models/cow.glb", "width": 0.9, "height": 1.4, "health": 10, "speed": 2.0,
		"persistent": true, "category": "animal", "drops": [["vanilla:raw_beef", 1], ["vanilla:raw_beef", 2, 0.5], ["vanilla:leather", 1, 0.7], ["vanilla:leather", 1, 0.3]],
		"sounds": {"hurt": "cow_hurt", "death": "cow_hurt", "ambient": "cow_ambient"},
		"ai": {"preset": "passive", "group": "cows", "alert_radius": 10, "wander_radius": 8},
		"breeding": {"food": ["base:wheat"], "cooldown": 300, "grow_seconds": 600}})
	ids.sheep = api.register_entity("sheep", {"kind": "mob", "model": "models/sheep.glb", "width": 0.9, "height": 1.3, "health": 8, "speed": 2.0,
		"persistent": true, "category": "animal", "drops": [],
		"sounds": {"hurt": "sheep_hurt", "death": "sheep_hurt", "ambient": "sheep_ambient"},
		"ai": {"preset": "passive", "group": "sheep", "alert_radius": 10, "wander_radius": 8},
		"breeding": {"food": ["base:wheat"], "cooldown": 300, "grow_seconds": 600}})
	ids.chicken = api.register_entity("chicken", {"kind": "mob", "model": "models/chicken.glb", "width": 0.4, "height": 0.7, "health": 4, "speed": 2.2,
		"gravity": 14.0, "persistent": true, "category": "animal", "drops": [["vanilla:raw_chicken", 1], ["vanilla:feather", 1, 0.6], ["vanilla:feather", 1, 0.3]],
		"sounds": {"hurt": "chicken_hurt", "death": "chicken_hurt", "ambient": "chicken_ambient"},
		"ai": {"preset": "passive", "group": "chickens", "alert_radius": 8, "wander_radius": 6},
		"breeding": {"food": ["base:wheat_seeds"], "cooldown": 300, "grow_seconds": 600}})
	# Wolves: neutral pack hunters, tamed with bones.
	ids.wolf = api.register_entity("wolf", {"kind": "mob", "model": "models/wolf.glb", "width": 0.6, "height": 0.85, "health": 12, "speed": 3.2,
		"persistent": true, "category": "animal", "drops": [["vanilla:bone", 1, 0.4]],
		"sounds": {"hurt": "wolf_hurt", "death": "wolf_hurt", "ambient": "wolf_ambient", "attack": "wolf_growl"},
		"ai": {"preset": "neutral", "group": "wolves", "aggression": 0.75, "courage": 0.8, "intelligence": 0.6, "alert_radius": 16,
			"chase_speed": 1.4, "wander_radius": 10, "attacks": [{"name": "bite", "type": "melee", "damage": 3.0, "windup": 0.25, "cooldown": 0.8}]},
		"breeding": {"food": ["vanilla:raw_beef", "vanilla:steak", "vanilla:raw_chicken", "vanilla:cooked_chicken", "vanilla:porkchop", "vanilla:cooked_porkchop"],
			"cooldown": 300, "grow_seconds": 600, "tempt": false},
		"taming": {"items": ["vanilla:bone"], "chance": 0.33, "follow_distance": 3.0, "teleport_distance": 16.0}})
	api.add_spawn_rule({"entity": "wolf", "category": "animal", "light": [9, 15], "place": "surface", "on": ["base:grass", "base:snow"],
		"max_nearby": 3, "max_total": 8, "chance": 0.015, "group": [2, 4]})
	for animal in ["cow", "sheep", "chicken"]:
		api.add_spawn_rule({"entity": animal, "category": "animal", "light": [9, 15], "place": "surface", "on": ["base:grass"],
			"max_nearby": 4, "max_total": 24, "chance": 0.06, "group": [2, 4]})


func _wool_color(sheep) -> String:
	return String(sheep.data.get("color", "white"))


func _set_color(sheep, color: String) -> void:
	sheep.data.color = color
	sheep.set_look({"tint": {"wool": COLORS[color]}})


func _on_spawned(ev: Dictionary) -> void:
	var e = ev.entity
	if e.type == ids.sheep and not e.data.has("color"):
		var roll := randf()
		var color := "white"
		for entry in NATURAL_COLORS:
			roll -= float(entry[1])
			if roll <= 0.0:
				color = entry[0]
				break
		_set_color(e, color)
	elif e.type == ids.wolf and not e.data.has("owner"):
		e.set_look({"hide": ["collar"]})
	elif e.type == ids.chicken and not e.data.has("next_egg"):
		e.data.next_egg = randf_range(EGG_SECONDS[0], EGG_SECONDS[1])


func _on_interact(ev: Dictionary) -> void:
	var e = ev.entity
	var player = ev.player
	var baby: bool = e.data.get("baby", false)
	if e.type == ids.cow and ev.item == ids.bucket and not baby:
		ev.cancelled = true
		if player.is_creative() or player.take(ids.bucket, 1):
			player.give(ids.milk, 1)
			api.play_sound("milk", e.position)
	elif e.type == ids.sheep and ev.item == ids.shears and not baby and not e.data.get("sheared", false):
		ev.cancelled = true
		e.data.sheared = true
		e.data.regrow_left = randf_range(REGROW_SECONDS[0], REGROW_SECONDS[1])
		e.set_look({"hide": ["wool"]})
		api.drop_item(ids["wool_" + _wool_color(e)], randi_range(1, 3), e.position + Vector3(0, 1.0, 0))
		api.play_sound("shear", e.position)
		if not player.is_creative():
			player.damage_item(player.inventory.selected, 1, "shear")
	elif e.type == ids.sheep and not baby:
		for color in COLORS:
			if ids.has("dye_" + color) and ev.item == ids["dye_" + color] and _wool_color(e) != color:
				ev.cancelled = true
				if player.is_creative() or player.take(ev.item, 1):
					_set_color(e, color)
				return


## Lambs take a color from one of their parents (or a mix of two dye colors).
func _on_bred(ev: Dictionary) -> void:
	var baby = ev.baby
	if baby.type != ids.sheep:
		return
	var a := _wool_color(ev.parents[0])
	var b := _wool_color(ev.parents[1])
	var color := a if randf() < 0.5 else b
	for mixed in DYE_MIXES:
		if DYE_MIXES[mixed].has(a) and DYE_MIXES[mixed].has(b) and a != b:
			color = mixed
	_set_color(baby, color)


func _on_death(ev: Dictionary) -> void:
	var e = ev.entity
	if e.type == ids.sheep and not e.data.get("sheared", false) and not e.data.get("baby", false):
		ev.drops.append([ids["wool_" + _wool_color(e)], 1])


## Every few seconds: sheared sheep regrow wool, hens lay eggs.
func _tick() -> void:
	for e in api.get_entities(Vector3.ZERO, 1.0e9, "vanilla:sheep"):
		if e.data.get("sheared", false):
			e.data.regrow_left = float(e.data.get("regrow_left", 0.0)) - 5.0
			if e.data.regrow_left <= 0.0:
				e.data.erase("sheared")
				e.data.erase("regrow_left")
				e.set_look({"hide": []})
	for e in api.get_entities(Vector3.ZERO, 1.0e9, "vanilla:chicken"):
		if e.data.get("baby", false):
			continue
		e.data.next_egg = float(e.data.get("next_egg", EGG_SECONDS[1])) - 5.0
		if e.data.next_egg <= 0.0:
			e.data.next_egg = randf_range(EGG_SECONDS[0], EGG_SECONDS[1])
			api.drop_item(ids.egg, 1, e.position + Vector3(0, 0.2, 0))
			api.play_sound("chicken_ambient", e.position)
