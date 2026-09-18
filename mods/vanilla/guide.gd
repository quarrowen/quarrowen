extends RefCounted
## Vanilla guidebook chapters: animals, monsters and the world (biomes, caves, structures). Creature
## pages unlock when you first see each one, biome pages when you first visit.


func setup(api) -> void:
	_animals(api)
	_monsters(api)
	_world(api)


func _page(api, id: String, chapter: String, order: int, title: String, icon: String, unlock: Dictionary, keywords: String, blocks: Array, hint := "") -> void:
	var def := {"chapter": chapter, "title": title, "icon": icon, "order": order, "keywords": keywords, "blocks": blocks}
	if not unlock.is_empty():
		def.unlock = unlock
	if not hint.is_empty():
		def.hint = hint
	api.register_guide_page(id, def)


func _animals(api) -> void:
	api.register_guide_chapter("animals", {"title": "Animals", "icon": "vanilla:raw_beef", "order": 20,
		"description": "Farm animals, breeding and a loyal wolf."})
	_page(api, "breeding", "animals", 0, "Breeding Animals", "base:wheat", {}, "breed baby love feed farm animal tempt", [
		{"type": "text", "text": "Animals follow anyone holding their favourite food. Feed two of the same kind and they fall in love (hearts), find each other and have a baby."},
		{"type": "text", "text": "• [b]Cows[/b] and [b]sheep[/b]: wheat\n• [b]Chickens[/b]: wheat seeds\n• [b]Pigs[/b]: apples\n• [b]Wolves[/b]: meat"},
		{"type": "text", "text": "Babies are small, drop nothing and grow up in about ten minutes; feeding them speeds that up. Parents need a few minutes' rest before breeding again."},
		{"type": "tip", "text": "Animals stay put when you leave, so a fenced field keeps a farm for good."},
	])
	_page(api, "cow", "animals", 1, "Cows", "vanilla:raw_beef", {"entity": "vanilla:cow"}, "cow beef leather milk bucket steak", [
		{"type": "entity", "entity": "vanilla:cow", "text": "Calm grassland animals that follow anyone holding wheat."},
		{"type": "text", "text": "Cows drop [b]raw beef[/b] and [b]leather[/b]. Right-click one with a bucket for [b]milk[/b], which also cures food poisoning."},
		{"type": "items", "items": ["vanilla:raw_beef", "vanilla:steak", "vanilla:leather", "vanilla:milk_bucket"]},
		{"type": "recipe", "output": "vanilla:steak"},
		{"type": "recipe", "output": "vanilla:bucket"},
	])
	_page(api, "sheep", "animals", 2, "Sheep and Wool", "vanilla:wool_white", {"entity": "vanilla:sheep"}, "sheep wool shears dye color bed", [
		{"type": "entity", "entity": "vanilla:sheep", "text": "Woolly and mostly white; now and then gray, black or brown."},
		{"type": "text", "text": "Right-click a sheep with [b]shears[/b] to take its wool without hurting it; the wool grows back. Dye a sheep to change the color of its wool, and lambs take after their parents."},
		{"type": "recipe", "output": "vanilla:shears"},
		{"type": "heading", "text": "Dyes"},
		{"type": "text", "text": "White from bone, black from coal, red from poppies, yellow from dandelions, green from saplings. Mix them for orange, pink and gray."},
		{"type": "items", "items": ["vanilla:dye_white", "vanilla:dye_black", "vanilla:dye_red", "vanilla:dye_yellow", "vanilla:dye_green"]},
		{"type": "recipe", "output": "vanilla:bed_red"},
	])
	_page(api, "chicken", "animals", 3, "Chickens", "vanilla:egg", {"entity": "vanilla:chicken"}, "chicken egg feather", [
		{"type": "entity", "entity": "vanilla:chicken", "text": "They flutter down gently instead of falling, and lay an egg every few minutes."},
		{"type": "items", "items": ["vanilla:raw_chicken", "vanilla:cooked_chicken", "vanilla:feather", "vanilla:egg"]},
		{"type": "tip", "text": "Raw chicken can give you food poisoning. Cook it first."},
	])
	_page(api, "pig", "animals", 4, "Pigs", "vanilla:porkchop", {"entity": "vanilla:pig"}, "pig pork porkchop leather herd", [
		{"type": "entity", "entity": "vanilla:pig", "text": "Pigs graze in herds and scatter together when one is hurt."},
		{"type": "items", "items": ["vanilla:porkchop", "vanilla:cooked_porkchop", "vanilla:leather"]},
		{"type": "recipe", "output": "vanilla:leather_chestplate"},
	])
	_page(api, "wolf", "animals", 5, "Wolves", "vanilla:bone", {"entity": "vanilla:wolf"}, "wolf tame dog pet bone sit follow", [
		{"type": "entity", "entity": "vanilla:wolf", "text": "Wolves roam in packs and leave you alone, unless you hurt one."},
		{"type": "heading", "text": "Taming"},
		{"type": "text", "text": "Right-click a wolf with a [b]bone[/b]; it may take a few tries. A tamed wolf wears a red collar, follows you (and catches up if you get too far away), and attacks whatever hurts you or whatever you hit."},
		{"type": "text", "text": "Right-click your wolf to make it [b]sit[/b] and stay, and again to make it follow."},
		{"type": "tip", "text": "Skeletons drop bones. Feed tamed wolves meat to breed them."},
	])


func _monsters(api) -> void:
	api.register_guide_chapter("monsters", {"title": "Monsters", "icon": "vanilla:rotten_flesh", "order": 25,
		"description": "What comes out at night, and how to deal with it."})
	_page(api, "zombie", "monsters", 0, "Zombies", "vanilla:rotten_flesh", {"entity": "vanilla:zombie"}, "zombie night undead pack", [
		{"type": "entity", "entity": "vanilla:zombie", "text": "Shambling packs that come out at night and burn in the morning sun."},
		{"type": "text", "text": "Zombies claw and lunge, and call nearby zombies in when they spot you. Fight them one at a time: back through a doorway so they cannot surround you."},
		{"type": "items", "items": ["vanilla:rotten_flesh", "base:coal", "base:workbench_plans"]},
		{"type": "tip", "text": "Rotten flesh fills you up, but it often gives you food poisoning."},
	])
	_page(api, "skeleton", "monsters", 1, "Skeletons", "vanilla:bone", {"entity": "vanilla:skeleton"}, "skeleton archer arrow bow bone plans", [
		{"type": "entity", "entity": "vanilla:skeleton", "text": "Archers that keep their distance, strafe and dodge."},
		{"type": "text", "text": "Skeletons lead their shots, so change direction as you close in, or break their line of sight and make them come to you."},
		{"type": "items", "items": ["vanilla:bone", "base:forge_plans"]},
		{"type": "tip", "text": "Skeletons sometimes carry Forge Plans."},
	])
	_page(api, "spider", "monsters", 2, "Spiders", "vanilla:string", {"entity": "vanilla:spider"}, "spider climb wall string pounce", [
		{"type": "entity", "entity": "vanilla:spider", "text": "Spiders climb walls and pounce from a distance."},
		{"type": "text", "text": "In bright daylight spiders leave you alone unless you attack them. Walls do not stop them, so light up the ground around your home instead."},
		{"type": "items", "items": ["vanilla:string"]},
	])
	_page(api, "slime", "monsters", 3, "Slimes", "vanilla:slimeball", {"entity": "vanilla:slime"}, "slime split hop cave slimeball", [
		{"type": "entity", "entity": "vanilla:slime", "text": "Big green cubes that hop around caves."},
		{"type": "text", "text": "A large slime splits into medium slimes when it dies, and each of those into small ones. Only the small ones are harmless, and they drop slimeballs."},
		{"type": "items", "items": ["vanilla:slimeball"]},
	])
	_page(api, "boomshroom", "monsters", 4, "Boomshrooms", "vanilla:boom_spores", {"entity": "vanilla:boomshroom"}, "boomshroom explode explosion blast mushroom fungus", [
		{"type": "entity", "entity": "vanilla:boomshroom", "text": "A walking mushroom that sneaks up on you, hisses, and explodes."},
		{"type": "text", "text": "When you hear the hiss, [b]run[/b]: get a few blocks away and it fizzles out. The blast breaks blocks and hurts; armor helps."},
		{"type": "items", "items": ["vanilla:boom_spores"]},
		{"type": "tip", "text": "They live in the glowing mushroom fields and also roam at night."},
	])
	_page(api, "night_stalker", "monsters", 5, "Night Stalkers", "vanilla:shadow_essence", {"entity": "vanilla:night_stalker"}, "night stalker shadow dark light torch essence", [
		{"type": "entity", "entity": "vanilla:night_stalker", "text": "Fast, clever hunters of the darkest nights and deepest caves."},
		{"type": "text", "text": "Night stalkers are rare and dangerous, but they hate light: they flee from lit places and from anyone holding a torch."},
		{"type": "items", "items": ["vanilla:shadow_essence", "base:torch"]},
		{"type": "tip", "text": "In shadowwood forests they come out at dusk."},
	])
	_page(api, "colossus", "monsters", 6, "The Ancient Colossus", "base:cobalt_ingot", {"entity": "vanilla:colossus"}, "colossus boss arena altar", [
		{"type": "entity", "entity": "vanilla:colossus", "text": "A giant of stone that sleeps beneath ancient arenas."},
		{"type": "text", "text": "The Colossus wakes when you step into its arena. It stomps the ground around it, punches hard and, once badly hurt, charges across the arena in a fury."},
		{"type": "text", "text": "• Stay out of reach while it winds up a stomp.\n• Sidestep the charge; it cannot turn quickly.\n• Bring friends, food and your best armor."},
		{"type": "tip", "text": "The arena's chests hold cobalt, iron and shadow essence."},
	], "Ancient arenas hide in plains, savannas and deserts.")


func _world(api) -> void:
	api.register_guide_chapter("world", {"title": "The World", "icon": "base:grass", "order": 30,
		"description": "Biomes, caves and what lies buried in them."})
	_page(api, "biomes", "world", 0, "Biomes", "base:grass", {}, "biome plains forest desert taiga tundra swamp savanna mountains ocean", [
		{"type": "text", "text": "The world is made of biomes with their own ground, trees and plants:"},
		{"type": "text", "text": "• [b]Plains[/b] and [b]savanna[/b]: open grassland, good for a first home\n• [b]Forests[/b]: oak, and birch with flowers\n• [b]Taiga[/b] and [b]snowy tundra[/b]: spruce and snow\n• [b]Desert[/b]: sand, sandstone, cacti and dead bushes\n• [b]Swamp[/b], [b]mountains[/b] and the [b]ocean[/b]"},
		{"type": "items", "items": ["base:log", "base:birch_log", "base:spruce_log", "base:acacia_log", "base:cactus", "base:sandstone"]},
		{"type": "tip", "text": "Every kind of log makes the same planks."},
	])
	_page(api, "mushroom_fields", "world", 1, "Glowing Mushroom Fields", "vanilla:glow_mushroom", {"biome": "vanilla:mushroom_fields"}, "mushroom glow rare biome mycelium", [
		{"type": "text", "text": "A rare biome of mycelium and huge red and glowing mushrooms, with pools of glowing water that light up the night."},
		{"type": "items", "items": ["vanilla:mycelium", "vanilla:glow_mushroom", "vanilla:red_mushroom", "vanilla:glowing_water"]},
		{"type": "tip", "text": "Watch out: boomshrooms wander here."},
	])
	_page(api, "shadowwood", "world", 2, "Shadowwood", "vanilla:shadow_log", {"biome": "vanilla:shadowwood"}, "shadow dark forest gloom nightbloom pod rare biome", [
		{"type": "text", "text": "A rare, gloomy forest of towering dark trees hung with glowing pods, over gloomgrass and murky water. Nightblooms open here."},
		{"type": "items", "items": ["vanilla:shadow_log", "vanilla:shadow_pod", "vanilla:nightbloom", "vanilla:gloomgrass"]},
		{"type": "tip", "text": "Night stalkers hunt shadowwood from dusk. Bring torches."},
	])
	_page(api, "fishing", "world", 4, "Fishing", "vanilla:fishing_rod", {"item": "vanilla:string"},
		"fish fishing rod water lake river sea bait catch wait", [
		{"type": "text", "text": "Sticks and string make a [b]fishing rod[/b]. Stand at the edge of any water, look at it and use the rod to cast."},
		{"type": "text", "text": "Then wait. It takes a few seconds, and the float will not move until it does. When something tugs, use the rod again straight away - you have a moment, not an instant."},
		{"type": "items", "items": ["vanilla:fishing_rod", "vanilla:raw_fish", "vanilla:cooked_fish"]},
		{"type": "recipe", "output": "vanilla:cooked_fish"},
		{"type": "tip", "text": "Missing a bite costs nothing. Cast again."},
	])
	_page(api, "caves", "world", 3, "Caves and Lava", "base:lava", {"item": "base:coal"}, "cave cavern ravine lava underground ore depth cobalt", [
		{"type": "text", "text": "Winding tunnels, huge caverns and deep ravines run under the world. Ores are placed by depth: coal high up, iron in the middle, and cobalt deep down near the lava."},
		{"type": "text", "text": "Low caverns flood with water; the deepest ones hold [b]lava[/b], which burns anything that touches it."},
		{"type": "items", "items": ["base:coal_ore", "base:iron_ore", "base:cobalt_ore", "base:lava"]},
		{"type": "recipe", "output": "base:cobalt_ingot"},
		{"type": "tip", "text": "Caves are dark, and dark means monsters. Place torches as you go so you can find your way back."},
	])
	_page(api, "structures", "world", 4, "Ruins and Dungeons", "base:chest", {"page": "vanilla:caves"}, "structure dungeon ruin watchtower mineshaft loot chest spawner cobweb", [
		{"type": "text", "text": "Explorers find old buildings full of loot:"},
		{"type": "text", "text": "• [b]Ruins[/b] and [b]watchtowers[/b] on the surface, built from whatever the land around them offers\n• [b]Dungeons[/b] underground: a monster spawner, cobwebs and two chests\n• [b]Mineshafts[/b]: long branching tunnels with chests\n• [b]Ancient arenas[/b]: guarded by something enormous"},
		{"type": "items", "items": ["base:spawner", "vanilla:cobweb", "base:chest"]},
		{"type": "tip", "text": "Break a spawner, or light it up, to stop it spawning. Chests are filled the first time someone opens them."},
	])
