extends RefCounted
## Vanilla guidebook chapters: the creatures of the world. Pages unlock when you first see each one.


func setup(api) -> void:
	api.register_guide_chapter("creatures", {"title": "Creatures", "icon": "vanilla:raw_beef", "order": 20,
		"description": "Animals to farm and monsters to fear."})
	api.register_guide_page("cow", {"chapter": "creatures", "title": "Cows", "icon": "vanilla:raw_beef", "order": 0,
		"unlock": {"entity": "vanilla:cow"}, "keywords": "animal farm beef leather milk breed",
		"blocks": [
			{"type": "entity", "entity": "vanilla:cow", "text": "Calm grassland animals. They follow anyone holding wheat."},
			{"type": "text", "text": "Cows drop [b]raw beef[/b] and [b]leather[/b]. Use a bucket on one for milk. Feed two cows wheat and they will have a calf."},
			{"type": "items", "items": ["vanilla:raw_beef", "vanilla:steak", "vanilla:leather", "vanilla:milk_bucket"]},
			{"type": "tip", "text": "Cook beef in a furnace: steak fills you up almost three times as much."},
		]})
