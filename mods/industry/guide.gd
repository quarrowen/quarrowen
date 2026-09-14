extends RefCounted
## Industry's guidebook chapter: power, machines and cables.


func setup(api) -> void:
	api.register_guide_chapter("industry", {"title": "Industry", "icon": "industry:coal_generator", "order": 45,
		"description": "Generators, cables, batteries and machines."})
	api.register_guide_page("power", {"chapter": "industry", "title": "Power", "icon": "industry:cable", "order": 0,
		"keywords": "energy fe power network cable generator battery", "blocks": [
			{"type": "text", "text": "Machines run on energy (FE). Everything touching a [b]cable[/b], or another machine, joins one network: generators feed the machines on it and batteries store what is left over."},
			{"type": "recipe", "output": "industry:cable"},
			{"type": "text", "text": "Right-click any machine for a live panel with its energy, fuel and contents."},
			{"type": "link", "page": "generators"},
		]})
	api.register_guide_page("generators", {"chapter": "industry", "title": "Generators and Batteries", "icon": "industry:coal_generator", "order": 1,
		"unlock": {"item": "base:iron_ore"}, "keywords": "coal generator solar panel battery fuel sun", "blocks": [
			{"type": "text", "text": "• [b]Coal Generator[/b]: makes 40 FE a second while it burns fuel: coal lasts longest, then logs, then planks.\n• [b]Solar Panel[/b]: up to 15 FE a second in daylight; it needs open sky.\n• [b]Battery[/b]: stores 20 000 FE for the night."},
			{"type": "recipe", "output": "industry:coal_generator"},
			{"type": "recipe", "output": "industry:solar_panel"},
			{"type": "recipe", "output": "industry:battery"},
		]})
	api.register_guide_page("machines", {"chapter": "industry", "title": "Lamps and the Auto Miner", "icon": "industry:miner", "order": 2,
		"unlock": {"item": "base:iron_ore"}, "keywords": "lamp light miner auto dig", "blocks": [
			{"type": "text", "text": "[b]Electric Lamps[/b] light up while powered (4 FE a second each)."},
			{"type": "recipe", "output": "industry:lamp"},
			{"type": "text", "text": "The [b]Auto Miner[/b] digs straight down, 120 FE per block, and keeps what it mines. Open its panel to collect."},
			{"type": "recipe", "output": "industry:miner"},
			{"type": "tip", "text": "A solar panel and a battery make a lamp that turns on by itself at night."},
		]})
