extends RefCounted
## The vanilla survival tutorial: from punching a tree to sleeping through the first night. Starts for
## new survival players (and sandbox players who switch to survival).


func setup(api) -> void:
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
			{"title": "Eat something", "text": "Apples fall from leaves; animals and wheat give more. Hold [b]right click[/b] with food.", "icon": "base:apple",
				"goal": {"type": "eat"}, "page": "base:food"},
			{"title": "Make a bed", "text": "Beds need wool from sheep or a hay bale. Place it somewhere safe.", "icon": "base:bed",
				"goal": {"type": "place", "target": ["base:bed", "vanilla:bed_*"]}, "hint": {"entity": "vanilla:sheep"}, "page": "base:beds"},
			{"title": "Sleep through the night", "text": "When it gets dark, right-click your bed. Morning comes when everyone sleeps.", "icon": "base:bed",
				"goal": {"type": "sleep"}, "page": "base:beds"},
		]})

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
