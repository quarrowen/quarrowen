extends RefCounted
## The vanilla tutorials: a short one that teaches the controls in creative (where new players land), and
## the survival one from punching a tree to sleeping through the first night.


func setup(api) -> void:
	# New players start in creative, so this is the first thing anyone sees. Nothing else in the game tells
	# a child which keys to press; before this, the survival tutorial below never ran for them at all.
	api.register_tutorial("first_steps", {"title": "Finding your feet", "order": -1, "auto_start": true,
		"modes": ["creative"],
		"description": "The keys you need: look, build, and where everything lives.",
		"reward": [],
		"steps": [
			{"title": "Build something", "text": "Move with [b]W A S D[/b] and look with the mouse. Pick a block from the hotbar with [b]1-9[/b], then [b]right click[/b] the ground to place it.",
				"icon": "base:planks", "goal": {"type": "place"}, "hint": false},
			{"title": "Take it back", "text": "Hold [b]left click[/b] on a block to break it. In creative you have as many as you like.",
				"icon": "base:cobblestone", "goal": {"type": "break"}, "hint": false},
			{"title": "Read the guide", "text": "Press [b]G[/b] for the guide - it explains everything and fills up as you play. [b]E[/b] opens your things, [b]C[/b] the recipe book, [b]M[/b] the map, [b]T[/b] to chat.",
				"goal": {"type": "read", "target": "base:welcome"}, "page": "base:welcome", "hint": false},
		]})

	api.register_tutorial("survival", {"title": "Survival Basics", "order": 0, "auto_start": true,
		"description": "From your first log to your first night in a bed.",
		"reward": [["base:bread", 3]],
		"steps": [
			{"title": "Chop some wood", "text": "Hold [b]left click[/b] on a tree trunk.", "icon": "base:log",
				"goal": {"type": "break", "target": "base:*log", "count": 3}, "page": "base:wood"},
			{"title": "Make planks", "text": "Press [b]C[/b] to open the recipe book and turn logs into planks.", "icon": "base:planks",
				"goal": {"type": "craft", "target": "base:planks", "count": 8}, "page": "base:wood"},
			{"title": "Build a crafting table", "text": "Craft one from 4 planks.", "icon": "base:crafting_table",
				"goal": {"type": "craft", "target": "base:crafting_table"}},
			{"title": "Place the table", "text": "Select it on your hotbar and [b]right click[/b] the ground.", "icon": "base:crafting_table",
				"goal": {"type": "place", "target": "base:crafting_table"}, "page": "base:crafting_table"},
			{"title": "Make a wooden pickaxe", "text": "Right-click the table, then craft sticks and a pickaxe.", "icon": "base:wooden_pickaxe",
				"goal": {"type": "craft", "target": "base:wooden_pickaxe"}, "hint": {"block": "base:crafting_table"}, "page": "base:crafting_table"},
			{"title": "Mine stone", "text": "Dig into a hillside or straight down (never right under your feet!).", "icon": "base:cobblestone",
				"goal": {"type": "break", "target": "base:stone", "count": 5}, "page": "base:stone_tools"},
			{"title": "Upgrade to stone", "text": "A stone pickaxe mines faster and can dig iron ore.", "icon": "base:stone_pickaxe",
				"goal": {"type": "craft", "target": "base:stone_pickaxe"}, "hint": {"block": "base:crafting_table"}, "page": "base:stone_tools"},
			{"title": "Discover something", "text": "Not every recipe is written down. Open the recipe book's [b]Experiment[/b] tab and try something that burns, held up by something to hold it.",
				"icon": "base:torch", "goal": {"type": "learn", "target": "base:torch"}, "page": "base:experiment", "hint": false},
			{"title": "Eat something", "text": "Apples fall from leaves; animals and wheat give more. Hold [b]right click[/b] with food.", "icon": "base:apple",
				"goal": {"type": "eat"}, "page": "base:food"},
			{"title": "Make a bed", "text": "Beds need wool from sheep or a hay bale. Place it somewhere safe.", "icon": "base:bed",
				"goal": {"type": "place", "target": ["base:bed", "vanilla:bed_*"]}, "hint": {"entity": "vanilla:sheep"}, "page": "base:beds"},
			{"title": "Sleep through the night", "text": "When it gets dark, right-click your bed. Morning comes when everyone sleeps.", "icon": "base:bed",
				"goal": {"type": "sleep"}, "page": "base:beds"},
		]})

	api.register_tip("home", {"text": "Somewhere to come back to. Type [b]/sethome[/b] here, and [b]/home[/b] brings you back from anywhere.",
		"icon": "base:crafting_table", "trigger": {"type": "place", "target": "base:crafting_table"}})
	api.register_tip("cooking", {"text": "Two mushrooms and a bowl make a stew. Build a [b]Cooking Pot[/b] - cooked meals give you something extra for a while.",
		"icon": "base:cooking_pot", "page": "base:cooking", "trigger": {"type": "pickup", "target": ["vanilla:red_mushroom", "vanilla:glow_mushroom", "vanilla:raw_beef"]}})
	api.register_tip("first_night", {"text": "Night is falling. Monsters spawn in the dark: stay near light, build walls or sleep in a bed.",
		"icon": "base:bed", "page": "base:beds", "trigger": {"type": "night"}})
	api.register_tip("hungry", {"text": "You're getting hungry. Below 3 drumsticks you can't sprint, and your health stops coming back.",
		"icon": "base:apple", "page": "base:food", "trigger": {"type": "hunger_below", "value": 8}})
	api.register_tip("hurt", {"text": "You're badly hurt. Back off, eat to heal, and come back with armor.",
		"icon": "base:bread", "trigger": {"type": "health_below", "value": 6}})
	api.register_tip("caves", {"text": "Deep underground ores get richer, but so does the danger. Bring torches and watch out for lava.",
		"icon": "base:iron_ore", "page": "base:stone_tools", "trigger": {"type": "depth", "below": 30}})
	api.register_tip("first_iron", {"text": "Iron ore! Smelt it in a furnace with coal to get ingots.",
		"icon": "base:iron_ore", "trigger": {"type": "pickup", "target": "base:iron_ore"}})
	api.register_tip("plans", {"text": "Plans teach you recipes. Right-click them to learn how to build a Forge.",
		"icon": "base:forge_plans", "page": "base:forge", "trigger": {"type": "pickup", "target": "base:forge_plans"}})
	api.register_tip("bones", {"text": "Wolves love bones. Right-click one with a bone to tame it.",
		"icon": "vanilla:bone", "page": "vanilla:wolf", "trigger": {"type": "pickup", "target": "vanilla:bone"}})
	api.register_tip("blast", {"text": "That was a boomshroom! When you hear the hiss, get a few blocks away and it fizzles out.",
		"icon": "vanilla:boom_spores", "page": "vanilla:boomshroom", "trigger": {"type": "damage", "target": "explosion"}})
	api.register_tip("died", {"text": "You died. Sleep in a bed (or just right-click one) to respawn next to it.",
		"icon": "base:bed", "page": "base:beds", "trigger": {"type": "respawn"}})
	# Points at the route that is actually open. Iron tools by recipe need an anvil, and an anvil needs
	# plans that drop from skeletons - a wall a child can sit behind for hours. The Tool Forge needs no
	# plans at all, and it is where the parts, traits and quality stars live.
	api.register_tip("iron_tools", {"text": "Iron! Build a [b]Tool Forge[/b] (cobblestone, iron and planks) and put your own pickaxe together from parts - each material gives it a different knack.",
		"icon": "base:tool_forge", "page": "base:tool_forge", "trigger": {"type": "pickup", "target": "base:iron_ingot"}})
	api.register_tip("first_parts", {"text": "Parts made. Stand at the Tool Forge and open [b]Assemble[/b] to put them together - and hammer it by hand for a chance at [b]Masterwork[/b].",
		"icon": "base:tool_forge", "page": "base:by_hand", "trigger": {"type": "craft", "target": "base:*_head"}})
