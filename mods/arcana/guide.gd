extends RefCounted
## Arcana's guidebook chapter: mana, wands, pylons, channeled gear and the crystal highlands.


func setup(api) -> void:
	api.register_guide_chapter("arcana", {"title": "Arcana", "icon": "arcana:mana_shard", "order": 40,
		"description": "Mana, wands and crystal magic."})
	api.register_guide_page("mana", {"chapter": "arcana", "title": "Mana", "icon": "arcana:mana_shard", "order": 0,
		"keywords": "mana crystal shard ore potion magic", "blocks": [
			{"type": "text", "text": "Glowing [b]mana crystal ore[/b] hides in stone underground. Mine it for [b]mana shards[/b], the heart of every spell."},
			{"type": "items", "items": ["arcana:mana_crystal_ore", "arcana:mana_shard", "arcana:mana_potion"]},
			{"type": "text", "text": "Your mana pool (100) is shown in the corner and refills slowly on its own. Right-click a shard to drink in 25 mana at once, or brew a potion for 60."},
			{"type": "recipe", "output": "arcana:mana_potion"},
			{"type": "link", "page": "wands"},
		]})
	api.register_guide_page("wands", {"chapter": "arcana", "title": "Wands", "icon": "arcana:wand_of_sparks", "order": 1,
		"unlock": {"item": "arcana:mana_shard"}, "keywords": "wand blink teleport light orb sparks projectile spell", "blocks": [
			{"type": "text", "text": "Right-click with a wand to cast:"},
			{"type": "text", "text": "• [b]Wand of Blink[/b] (20 mana): teleports you up to 8 blocks where you look.\n• [b]Wand of Light[/b] (10 mana): conjures an orb of light for 30 seconds.\n• [b]Wand of Sparks[/b] (8 mana): fires a spark that hurts monsters."},
			{"type": "recipe", "output": "arcana:wand_of_blink"},
			{"type": "recipe", "output": "arcana:wand_of_light"},
			{"type": "recipe", "output": "arcana:wand_of_sparks"},
		]})
	api.register_guide_page("pylon", {"chapter": "arcana", "title": "Mana Pylons", "icon": "arcana:mana_pylon", "order": 2,
		"unlock": {"item": "arcana:mana_shard"}, "keywords": "pylon regenerate mana base", "blocks": [
			{"type": "text", "text": "A glowing pylon refills the mana of everyone within 6 blocks five times as fast. Put one in your base."},
			{"type": "recipe", "output": "arcana:mana_pylon"},
		]})
	api.register_guide_page("channeling", {"chapter": "arcana", "title": "Channeled Gear", "icon": "arcana:soul_blade", "order": 3,
		"unlock": {"item": "base:iron_sword"}, "keywords": "soul blade crystal helmet channel hold quality level souls", "blocks": [
			{"type": "text", "text": "Mana can be channeled into iron gear by hand: keep the gauge inside the drifting band to reach a better quality (see Crafting by Hand)."},
			{"type": "text", "text": "The [b]Soul Blade[/b] grows stronger with every monster it slays, levelling up at 3, 8, 16, 30 and 50 souls. The [b]Crystal Helmet[/b] glows with a cool light."},
			{"type": "recipe", "output": "arcana:soul_blade"},
			{"type": "recipe", "output": "arcana:crystal_helmet"},
			{"type": "link", "page": "base:by_hand"},
		]})
	api.register_guide_page("crystal_highlands", {"chapter": "arcana", "title": "Crystal Highlands", "icon": "arcana:crystal_block", "order": 4,
		"unlock": {"biome": "arcana:crystal_highlands"}, "keywords": "crystal highlands biome spire spring", "blocks": [
			{"type": "text", "text": "A rare land of pale crystal stone and tall glowing spires, with mana springs that shine through the night."},
			{"type": "items", "items": ["arcana:crystal_stone", "arcana:crystal_block", "arcana:mana_spring"]},
		]})
