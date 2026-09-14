extends RefCounted
## The Survival Guide item (right-click to open the guidebook, same as the G key) and the base
## chapters: the first steps every game built on base shares.


func setup(api) -> void:
	api.register_item("guide_book", {"display_name": "Survival Guide", "icon": "textures/guide_book.png", "usable": true, "max_stack": 1,
		"lore": ["Right-click to read."]})
	api.register_recipe({"base:planks": 1, "base:stick": 1}, "base:guide_book", 1, {"unlock": "known", "category": "misc"})
	api.on("item_use", func(ev):
		if ev.item == api.item("guide_book"):
			api.open_guide(ev.player))

	api.register_guide_chapter("basics", {"title": "First Steps", "icon": "base:guide_book", "order": 0,
		"description": "Surviving your first day."})
	api.register_guide_page("welcome", {"chapter": "basics", "title": "Welcome", "icon": "base:guide_book", "order": 0,
		"keywords": "start help controls",
		"blocks": [
			{"type": "text", "text": "This book fills itself in as you explore. New pages appear when you find new things, and a note pops up when they do."},
			{"type": "keys", "action": "guide", "text": "opens this guide at any time."},
			{"type": "keys", "action": "inventory", "text": "opens your inventory."},
			{"type": "keys", "action": "crafting", "text": "opens the recipe book."},
			{"type": "tip", "text": "Click any item shown in this book to see its recipes."},
			{"type": "link", "page": "wood"},
		]})
	api.register_guide_page("wood", {"chapter": "basics", "title": "Wood and Planks", "icon": "base:planks", "order": 1,
		"keywords": "tree log chop punch",
		"blocks": [
			{"type": "text", "text": "Everything starts with wood. Hold [b]left click[/b] on a tree trunk to break a log, then turn logs into planks and planks into sticks."},
			{"type": "items", "items": ["base:log", "base:planks", "base:stick"]},
			{"type": "recipe", "output": "base:planks"},
			{"type": "recipe", "output": "base:stick"},
			{"type": "link", "page": "crafting_table"},
		]})
	api.register_guide_page("crafting_table", {"chapter": "basics", "title": "The Crafting Table", "icon": "base:crafting_table", "order": 2,
		"unlock": {"item": "base:planks"}, "keywords": "workbench station",
		"blocks": [
			{"type": "text", "text": "Most tools need a [b]Crafting Table[/b]. Place it, right-click it, and the recipe book shows what you can make there."},
			{"type": "recipe", "output": "base:crafting_table"},
			{"type": "heading", "text": "Your first tools"},
			{"type": "text", "text": "A wooden pickaxe mines stone; stone tools mine iron ore. Better tools dig faster and last longer."},
			{"type": "recipe", "output": "base:wooden_pickaxe"},
			{"type": "link", "page": "stone_tools"},
		]})
	api.register_guide_page("stone_tools", {"chapter": "basics", "title": "Stone and Ores", "icon": "base:stone_pickaxe", "order": 3,
		"unlock": {"item": "base:cobblestone"}, "keywords": "mine mining ore coal iron pickaxe",
		"blocks": [
			{"type": "text", "text": "Stone drops cobblestone. Keep digging to find ores: [b]coal[/b] near the surface, [b]iron[/b] a little deeper."},
			{"type": "items", "items": ["base:cobblestone", "base:coal", "base:iron_ore"]},
			{"type": "recipe", "output": "base:stone_pickaxe"},
			{"type": "tip", "text": "Iron ore needs a stone pickaxe or better, and must be smelted into ingots."},
		]})
	api.register_guide_page("food", {"chapter": "basics", "title": "Hunger and Food", "icon": "base:apple", "order": 4,
		"unlock": {"page": "base:wood"}, "keywords": "eat hunger starve health regenerate",
		"blocks": [
			{"type": "text", "text": "Running, jumping and fighting make you hungry. With a full belly your health comes back on its own; when the drumsticks run low you cannot sprint, and at zero you start to starve."},
			{"type": "keys", "action": "place", "text": "hold with food in hand to eat it."},
			{"type": "items", "items": ["base:apple", "base:bread"]},
			{"type": "tip", "text": "Cooked food fills you up far more than raw food."},
		]})
	api.register_guide_page("beds", {"chapter": "basics", "title": "Beds", "icon": "base:bed", "order": 5,
		"unlock": {"recipe": "base:bed"}, "hint": "Survive until you can make a bed.", "keywords": "sleep night respawn spawn",
		"blocks": [
			{"type": "text", "text": "Right-click a bed to make it your respawn point. At night, lie down to sleep until morning; everyone (or the share the server sets) has to be in bed."},
			{"type": "recipe", "output": "base:bed"},
			{"type": "tip", "text": "You cannot sleep with monsters nearby."},
		]})
