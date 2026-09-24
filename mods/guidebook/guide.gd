extends RefCounted
## The Survival Guide item (right-click to open the guidebook, same as the G key) and the base
## chapters every game built on base shares: first steps, survival, crafting and smithing.


func setup(api) -> void:
	api.register_item("guide_book", {"display_name": "Survival Guide", "icon": "textures/guide_book.png", "usable": true, "max_stack": 1,
		"lore": ["Right-click to read."]})
	api.register_recipe({"base:planks": 1, "base:stick": 1}, "guidebook:guide_book", 1, {"unlock": "known", "category": "misc"})
	api.on("item_use", func(ev):
		if ev.item == api.item("guide_book"):
			api.open_guide(ev.player))
	_first_steps(api)
	_survival(api)
	_crafting(api)
	_smithing(api)


func _first_steps(api) -> void:
	api.register_guide_chapter("basics", {"title": "First Steps", "icon": "guidebook:guide_book", "order": 0,
		"description": "Surviving your first day."})
	api.register_guide_page("welcome", {"chapter": "basics", "title": "Welcome", "icon": "guidebook:guide_book", "order": 0,
		"keywords": "start help controls keys",
		"blocks": [
			{"type": "text", "text": "This book fills itself in as you explore. New pages appear when you find new things, and a note pops up when they do. Pages still marked [b]???[/b] tell you what reveals them."},
			{"type": "heading", "text": "Controls"},
			{"type": "keys", "action": "guide", "text": "opens this guide at any time."},
			{"type": "keys", "action": "inventory", "text": "opens your inventory and equipment."},
			{"type": "keys", "action": "crafting", "text": "opens the recipe book."},
			{"type": "keys", "action": "break", "text": "(hold) mines blocks and attacks."},
			{"type": "keys", "action": "place", "text": "places blocks, uses items and opens chests and stations; hold it to eat."},
			{"type": "keys", "action": "drop", "text": "drops the item in your hand."},
			{"type": "keys", "action": "sprint", "text": "sprints while moving."},
			{"type": "tip", "text": "Click any item shown in this book to see how it is made."},
			{"type": "link", "page": "wood"},
		]})
	api.register_guide_page("wood", {"chapter": "basics", "title": "Wood and Planks", "icon": "base:planks", "order": 1,
		"keywords": "tree log chop punch sticks",
		"blocks": [
			{"type": "text", "text": "Everything starts with wood. Hold [b]left click[/b] on a tree trunk to break a log; it takes a while by hand and goes faster with an axe. Every kind of log makes planks, and planks make sticks."},
			{"type": "items", "items": ["base:log", "base:planks", "base:stick"]},
			{"type": "recipe", "output": "base:planks"},
			{"type": "recipe", "output": "base:stick"},
			{"type": "tip", "text": "Leaves sometimes drop saplings. Plant them to grow more trees."},
			{"type": "link", "page": "crafting_table"},
		]})
	api.register_guide_page("crafting_table", {"chapter": "basics", "title": "The Crafting Table", "icon": "simple_machines:crafting_table", "order": 2,
		"unlock": {"item": "base:planks"}, "keywords": "workbench station tools",
		"blocks": [
			{"type": "text", "text": "Most tools, chests and furnaces need a [b]Crafting Table[/b]. Place it and right-click it: the recipe book then shows what you can make there."},
			{"type": "recipe", "output": "simple_machines:crafting_table"},
			{"type": "heading", "text": "Your first tools"},
			{"type": "text", "text": "A pickaxe mines stone and ores, an axe chops wood, a shovel digs dirt and sand, a sword fights. Wooden tools mine stone; stone tools mine iron ore. Better tools dig faster and last longer, and every tool wears out with use."},
			{"type": "recipe", "output": "simple_gear:wooden_pickaxe"},
			{"type": "link", "page": "stone_tools"},
		]})
	api.register_guide_page("stone_tools", {"chapter": "basics", "title": "Stone and Ores", "icon": "simple_gear:stone_pickaxe", "order": 3,
		"unlock": {"item": "base:cobblestone"}, "keywords": "mine mining ore coal iron pickaxe tier",
		"blocks": [
			{"type": "text", "text": "Stone drops cobblestone. Keep digging to find ores: [b]coal[/b] near the surface, [b]iron[/b] deeper down and [b]cobalt[/b] far below, near the lava."},
			{"type": "items", "items": ["base:cobblestone", "base:coal", "base:iron_ore", "base:cobalt_ore"]},
			{"type": "recipe", "output": "simple_gear:stone_pickaxe"},
			{"type": "tip", "text": "A tool that is too weak mines slowly and gets nothing. Iron ore needs a stone pickaxe or better; cobalt needs iron."},
			{"type": "link", "page": "furnace"},
		]})
	# The ores the book never covered. Copper and gold are sidegrades rather than rungs and want saying
	# so; sunstone is what the deep is *for*, and a child who finds a vein of it should be able to look
	# it up rather than guess. (2026-09-24)
	api.register_guide_page("deep_ores", {"chapter": "basics", "title": "The Deeper Ores", "icon": "base:sunstone", "order": 4,
		# **Any of the four opens it, not the deepest one.** It was gated on cobalt ore, which meant you
		# could not read about *copper* until you had *cobalt* - backwards, since copper is the early
		# material and the reason the page exists is to say so. (found in play, 2026-09-24)
		"unlock": {"item": ["base:copper_ore", "base:gold_ore", "base:cobalt_ore", "base:sunstone_ore", "base:deepstone"]},
		"keywords": "copper gold sunstone deepstone ore deep mine rare",
		"blocks": [
			{"type": "text", "text": "Below the ordinary stone the world turns to [b]deepstone[/b]: darker, harder, and only a cobalt pickaxe will lift it. What lives down there is worth the walk."},
			{"type": "items", "items": ["base:copper_ore", "base:gold_ore", "base:sunstone_ore", "base:deepstone"]},
			{"type": "text", "text": "[b]Copper[/b] sits between stone and iron and is easy to find, so it shortens the dull stretch before iron. [b]Gold[/b] is quicker to dig with than anything until cobalt, and it wears out while you watch - a trade, not a mistake."},
			{"type": "text", "text": "[b]Sunstone[/b] keeps a little of the sun in it. It is the rarest thing in the ground and the old lights were made of it."},
			{"type": "tip", "text": "Neither copper nor gold is a step on the way to cobalt. You can go straight from iron, and many do."},
		]})
	api.register_guide_page("food", {"chapter": "basics", "title": "Hunger and Food", "icon": "base:apple", "order": 4,
		"unlock": {"page": "guidebook:wood"}, "keywords": "eat hunger starve health regenerate saturation drumstick",
		"blocks": [
			{"type": "text", "text": "Running, jumping, mining and fighting make you hungry. The drumsticks next to your hearts show how full you are."},
			{"type": "text", "text": "• With [b]9 or more[/b] drumsticks your health comes back on its own.\n• With [b]3 or fewer[/b] you cannot sprint.\n• At [b]zero[/b] you starve and lose health."},
			{"type": "keys", "action": "place", "text": "hold with food in hand to eat it."},
			{"type": "items", "items": ["base:apple", "base:bread", "base:apple_juice"]},
			{"type": "recipe", "output": "base:bread"},
			{"type": "tip", "text": "Some food keeps you full for longer than its drumsticks show. Cooked meat is far better than raw."},
		]})
	api.register_guide_page("cooking", {"chapter": "basics", "title": "Cooking", "icon": "simple_machines:cooking_pot", "order": 5,
		"unlock": {"item": ["simple_machines:bowl", "simple_machines:cooking_pot"]},
		"hint": "Make a bowl, or pick up something worth cooking.",
		"keywords": "cook pot stew soup cake pie meal bowl feast buff masterwork stir",
		"blocks": [
			{"type": "text", "text": "A furnace melts one thing at a time. A [b]Cooking Pot[/b] takes several and makes a meal of them - and a meal does more than fill you up."},
			{"type": "recipe", "output": "simple_machines:cooking_pot"},
			{"type": "text", "text": "Every dish gives you something for a while: quicker feet, a longer reach, harder to knock over, more hearts than you started with. The message when you finish eating tells you what you got."},
			{"type": "items", "items": ["simple_machines:bowl", "simple_machines:apple_pie"]},
			{"type": "tip", "text": "Press [b]Stir the pot[/b] instead of Craft and keep the spoon moving steadily. A Masterwork meal glows, carries your name, and fills you more."},
			{"type": "text", "text": "Not every recipe is written down. The pot is a good place to try two things that seem like they belong together."},
			{"type": "link", "page": "experiment"},
		]})
	api.register_guide_page("beds", {"chapter": "basics", "title": "Beds", "icon": "base:bed", "order": 5,
		"unlock": {"item": "base:wheat"}, "hint": "Grow or find some wheat to fill in this page.", "keywords": "sleep night respawn spawn",
		"blocks": [
			{"type": "text", "text": "Right-click a bed to make it your [b]respawn point[/b]. At night, lie down in it to sleep until morning; on a server, enough players have to be in bed at once."},
			{"type": "recipe", "output": "base:bed"},
			{"type": "recipe", "output": "base:hay_bale"},
			{"type": "tip", "text": "You cannot sleep with monsters nearby. If your bed is broken or blocked you respawn at the world spawn."},
		]})


func _survival(api) -> void:
	api.register_guide_chapter("survival", {"title": "Survival", "icon": "base:torch", "order": 5,
		"description": "Staying alive: health, light, farming and storage."})
	api.register_guide_page("health", {"chapter": "survival", "title": "Health and Armor", "icon": "simple_gear:iron_chestplate", "order": 0,
		"keywords": "hearts damage fall death respawn armor heal",
		"blocks": [
			{"type": "text", "text": "You have 10 hearts. Monsters, falls, lava and starving all hurt. Health comes back slowly while you are well fed."},
			{"type": "text", "text": "Armor goes in the equipment slots beside your inventory ([b]shift-click[/b] or [b]right-click[/b] to wear it) and takes the edge off every hit. It wears out as it protects you."},
			{"type": "items", "items": ["simple_gear:iron_helmet", "simple_gear:iron_chestplate", "simple_gear:iron_leggings", "simple_gear:iron_boots"]},
			{"type": "heading", "text": "Fighting"},
			{"type": "text", "text": "Swords hit hardest. Wait for your weapon to recharge between swings; hitting while falling from a jump lands a [b]critical hit[/b], and sword swings also catch mobs around your target."},
			{"type": "tip", "text": "When you die you come back at your bed. Depending on the server, your items may stay where you fell."},
		]})
	api.register_guide_page("light", {"chapter": "survival", "title": "Light and Torches", "icon": "base:torch", "order": 1,
		"unlock": {"item": ["base:coal", "simple_machines:charcoal", "simple_machines:furnace"]}, "keywords": "torch dark night monsters spawn safe",
		"blocks": [
			{"type": "text", "text": "Monsters appear in the dark: at night, in caves and in unlit rooms. Light keeps them away, so a well-lit base is a safe base."},
			{"type": "recipe", "output": "base:torch"},
			{"type": "tip", "text": "There is no torch recipe in the book at first. Try arranging fuel and a stick in the Experiment grid (see Discovering Recipes)."},
			{"type": "link", "page": "discovery"},
		]})
	api.register_guide_page("farming", {"chapter": "survival", "title": "Farming", "icon": "base:wheat", "order": 2,
		"unlock": {"item": "base:wheat_seeds"}, "keywords": "seeds wheat hoe farmland water crops grow sapling",
		"blocks": [
			{"type": "text", "text": "Breaking tall grass sometimes drops [b]wheat seeds[/b]. Till grass or dirt with a hoe, then right-click the farmland with seeds."},
			{"type": "recipe", "output": "simple_gear:wooden_hoe"},
			{"type": "text", "text": "Wheat grows in four stages and needs light. It grows twice as fast on farmland near water. Bare farmland dries back into dirt."},
			{"type": "items", "items": ["base:wheat_seeds", "base:wheat", "base:bread", "base:hay_bale"]},
			{"type": "tip", "text": "Crops keep growing while you are away; come back to a ripe field."},
		]})
	# A child who sees "A Wisp is drifting somewhere out in the dark" in chat needs somewhere to find
	# out what that means, what the countdown on the compass is counting down to, and - the part that
	# matters at bedtime - that one of the four will not hurt them.
	api.register_guide_page("night_visitors", {"chapter": "survival", "title": "Night Visitors",
		"icon": "base:moonpearl", "order": 4, "keywords": "rare wisp piper warden palemoth night hunt marker compass",
		"blocks": [
			{"type": "text", "text": "Now and then at night the server says that something rare has turned up. A mark appears on your [b]compass[/b] and on your [b]map[/b], and it moves as the creature moves, so you can follow it."},
			{"type": "text", "text": "The mark counts down. When the time runs out the creature goes, and you have to wait for the next one - so when you see the message, go."},
			{"type": "heading", "text": "What you might meet"},
			{"type": "text", "text": "The [b]Palemoth[/b] is harmless. It only wants to get away from you, and it is worth more than most things that bite."},
			{"type": "text", "text": "The [b]Wisp[/b] is a light that will not be caught easily. The [b]Barrow Warden[/b] is slow, very tough, and comes up out of stony ground. The [b]Hollow Piper[/b] is tall and never hurries, and walking away from it works."},
			{"type": "items", "items": ["base:moonpearl", "base:emberheart", "base:warden_core", "base:hollow_reed"]},
			{"type": "tip", "text": "Take a friend, and take a torch. Whatever they leave behind, nobody else can get any other way."},
		]})
	api.register_guide_page("storage", {"chapter": "survival", "title": "Chests", "icon": "simple_machines:chest", "order": 3,
		"unlock": {"item": "base:planks"}, "keywords": "chest storage container inventory",
		"blocks": [
			{"type": "text", "text": "A chest holds 27 stacks. Right-click to open it; [b]shift-click[/b] moves whole stacks between the chest and your inventory. Breaking a chest spills what is inside."},
			{"type": "recipe", "output": "simple_machines:chest"},
			{"type": "tip", "text": "Crafting at a station also uses ingredients from chests close to it."},
		]})


func _crafting(api) -> void:
	api.register_guide_chapter("crafting", {"title": "Crafting", "icon": "simple_machines:crafting_table", "order": 10,
		"description": "The recipe book, discovery, furnaces, workshops and crafting with friends."})
	api.register_guide_page("recipe_book", {"chapter": "crafting", "title": "The Recipe Book", "icon": "simple_machines:crafting_table", "order": 0,
		"keywords": "recipe search pin craft all lookup",
		"blocks": [
			{"type": "keys", "action": "crafting", "text": "opens the recipe book (right-clicking a station opens it too)."},
			{"type": "text", "text": "Search or pick a tab, click a recipe to see what you have and what is missing, then [b]Craft[/b] or [b]Craft all[/b]."},
			{"type": "text", "text": "• [b]Pin[/b] a recipe to keep its shopping list on your screen while you gather.\n• Hover any item and press [b]R[/b] to see how it is made or [b]U[/b] to see what it is used in.\n• The stats of tools and armor are compared with what you hold and wear."},
			{"type": "link", "page": "discovery"},
		]})
	api.register_guide_page("discovery", {"chapter": "crafting", "title": "Discovering Recipes", "icon": "simple_machines:bookshelf", "order": 1,
		"keywords": "discover learn unknown silhouette blueprint plans hint bookshelf",
		"blocks": [
			{"type": "text", "text": "You do not know every recipe from the start. Unknown recipes show as dark silhouettes with a hint of how to find them."},
			{"type": "text", "text": "• [b]Pick up[/b] an ingredient and recipes that use it are often learned.\n• [b]Plans[/b] and blueprints teach recipes when you use them.\n• The [b]Experiment[/b] tab finds recipes by arranging items.\n• [b]Bookshelves[/b] around a crafting table reveal more of each hidden recipe."},
			{"type": "items", "items": ["simple_machines:forge_plans", "simple_machines:workbench_plans", "simple_machines:bookshelf"]},
			{"type": "link", "page": "experiment"},
		]})
	api.register_guide_page("experiment", {"chapter": "crafting", "title": "Experimenting", "icon": "base:torch", "order": 2,
		"unlock": {"page": "guidebook:discovery"}, "keywords": "experiment grid arrange pattern try",
		"blocks": [
			{"type": "text", "text": "Open the recipe book's [b]Experiment[/b] tab and arrange items you are holding in the 3 × 3 grid, then press [b]Try[/b]. Nothing is used up."},
			{"type": "text", "text": "If the arrangement is a recipe you learn it. Near misses get a hint: the right items in the wrong shape, amounts that are off, something missing or something extra."},
			{"type": "tip", "text": "Things worth trying: something that burns on top of a stick, and a full grid of one crop."},
		]})
	api.register_guide_page("furnace", {"chapter": "crafting", "title": "Furnaces and Smelting", "icon": "simple_machines:furnace", "order": 3,
		"unlock": {"item": "base:cobblestone"}, "keywords": "furnace smelt fuel coal charcoal ingot glass cook",
		"blocks": [
			{"type": "text", "text": "A furnace smelts and cooks. Put something in the top slot and fuel below; it keeps working while you are away."},
			{"type": "recipe", "output": "simple_machines:furnace"},
			{"type": "recipe", "output": "base:iron_ingot"},
			{"type": "recipe", "output": "base:glass"},
			{"type": "recipe", "output": "simple_machines:charcoal"},
			{"type": "text", "text": "[b]Fuel:[/b] coal and charcoal burn longest; logs, planks, sticks and old wooden tools work too."},
			{"type": "link", "page": "workshop"},
		]})
	api.register_guide_page("workshop", {"chapter": "crafting", "title": "Workshop Upgrades", "icon": "simple_machines:anvil", "order": 4,
		"unlock": {"item": "base:iron_ingot"}, "keywords": "anvil tool rack bookshelf metalwork upgrade station tier sturdy workbench",
		"blocks": [
			{"type": "text", "text": "Blocks placed within 4 blocks of a crafting table upgrade it. Right-click the table to see what it has found and what is still missing."},
			{"type": "text", "text": "• [b]Anvil[/b]: metalwork, needed for iron tools and weapons, and better crafting by hand.\n• [b]Tool Rack[/b]: faster crafting and ingredients from chests further away.\n• [b]Bookshelves[/b] (up to 3): reveal hidden recipes."},
			{"type": "recipe", "output": "simple_machines:tool_rack"},
			{"type": "recipe", "output": "simple_machines:bookshelf"},
			{"type": "heading", "text": "Sturdy Workbench"},
			{"type": "text", "text": "Use a [b]Reinforced Frame[/b] on a crafting table to turn it into a Sturdy Workbench. Iron armor needs one (and an anvil)."},
			{"type": "items", "items": ["simple_machines:reinforced_frame", "simple_machines:anvil"]},
			{"type": "link", "page": "forge"},
		]})
	api.register_guide_page("forge", {"chapter": "crafting", "title": "The Forge", "icon": "simple_machines:forge", "order": 5,
		"unlock": {"recipe": "simple_machines:forge"}, "hint": "Skeletons carry Forge Plans, and traders sell them.", "keywords": "forge brick structure multiblock anvil frame plans",
		"blocks": [
			{"type": "text", "text": "The Forge is a structure: a forge core with bricks around it. Build it like this, seen from above ([b]C[/b] is the core, [b]B[/b] a brick):"},
			{"type": "text", "text": "[code] B C B\n B B B\n   B[/code]"},
			{"type": "text", "text": "Right-click the core and press [b]Show build guide[/b] to see ghost bricks where the missing ones go. A finished Forge casts anvils and reinforced frames."},
			{"type": "recipe", "output": "simple_machines:forge"},
			{"type": "recipe", "output": "base:brick"},
			{"type": "recipe", "output": "simple_machines:anvil"},
			{"type": "recipe", "output": "simple_machines:reinforced_frame"},
		]})
	api.register_guide_page("coop", {"chapter": "crafting", "title": "Crafting Together", "icon": "simple_machines:crafting_table", "order": 6,
		"keywords": "co-op multiplayer team tray queue project friends",
		"blocks": [
			{"type": "text", "text": "Everyone at the same station shares it: you see who is there and what they are looking at."},
			{"type": "text", "text": "• The [b]shared tray[/b] holds 9 stacks anyone at the station can craft from. You can take back what you put in.\n• Slow recipes go into a [b]queue[/b] and finish faster with more players nearby, up to 2.5 times as fast.\n• [b]Projects[/b] are big builds everyone adds ingredients to over time."},
			{"type": "tip", "text": "Some items can be crafted by hand with a partner: one hammers while the other works the bellows."},
		]})


func _smithing(api) -> void:
	api.register_guide_chapter("smithing", {"title": "Smithing", "icon": "simple_gear:iron_pickaxe", "order": 15,
		"description": "Tools from parts, and crafting by hand for better quality."})
	# Leather stitching is the first minigame anyone meets, long before iron, so this has to be readable by
	# then - otherwise the only explanation of quality is a hover tooltip on a button.
	api.register_guide_page("by_hand", {"chapter": "smithing", "title": "Crafting by Hand", "icon": "simple_gear:iron_sword", "order": 0,
		"unlock": {"item": ["base:iron_ingot", "simple_gear:tool_forge"]}, "keywords": "quality masterwork superior fine minigame hammer skill forging timing relaxed",
		"blocks": [
			{"type": "text", "text": "Some recipes have a [b]by hand[/b] button next to Craft. It starts a short minigame, and how well you do sets the result's quality:"},
			{"type": "text", "text": "• [b]Standard[/b]: the same as crafting normally (also what you get for stopping early)\n• [b]Fine[/b]: +10%\n• [b]Superior[/b]: +20%\n• [b]Masterwork[/b]: +30%, glows and carries its makers' names"},
			{"type": "text", "text": "Quality raises durability, mining speed, damage and armor. Forging iron gear is a timing game: strike while the marker is inside the zone, which shrinks as the metal cools."},
			{"type": "tip", "text": "Tick [b]Relaxed timing[/b] in the recipe book for a slower marker and wider zones. An anvil nearby widens them too."},
			{"type": "heading", "text": "With a partner"},
			{"type": "text", "text": "Press [b]With a partner[/b] to invite players at the station. They work the bellows: keep the heat in the green band and pump just before your strikes for a bonus."},
		]})
	api.register_guide_page("tool_forge", {"chapter": "smithing", "title": "Tools from Parts", "icon": "simple_gear:tool_forge", "order": 1,
		"unlock": {"item": "base:iron_ingot"}, "keywords": "tool forge parts head handle binding material trait assemble",
		"blocks": [
			{"type": "text", "text": "A [b]Toolsmith’s Bench[/b] makes tool parts from any material: heads, blades, handles, grips, bindings and guards. Put them together in the recipe book's [b]Assemble[/b] tab."},
			{"type": "recipe", "output": "simple_gear:tool_forge"},
			{"type": "text", "text": "• The [b]head[/b] (or blade) sets the tier, speed and damage.\n• The [b]handle[/b]'s material changes durability.\n• Every material adds its own [b]trait[/b], shown on the part."},
			{"type": "items", "items": ["simple_gear:pickaxe_head", "simple_gear:axe_head", "simple_gear:sword_blade", "simple_gear:tool_handle", "simple_gear:binding"]},
			{"type": "tip", "text": "Mix materials: a strong head on a light handle, or a glowing binding for caves."},
		]})
