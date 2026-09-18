extends RefCounted
## The opening, as guided steps.
##
## Hearthhold had no tutorial of its own, so vanilla's generic one started instead and a new player spent
## their first session chopping wood while the charter board stood unread in the yard. The story was there
## to be noticed rather than to be led into, and the first person to play it did not notice. (2026-09-18)
##
## Three steps, and no more: read the board, light the hearth, make a light of your own. That is chapter
## one's shape, it ends with the player holding a torch on the night it matters, and it hands over to
## vanilla's survival tutorial afterwards rather than trying to teach the whole game itself.
##
## `order` is below vanilla's -1 so this is the one that starts (engine/server/tutorials.gd on_join takes
## the first auto-start tutorial in order).

var api


func setup(mod_api) -> void:
	api = mod_api
	api.register_tutorial("arriving", {"title": "The Cold Hearth", "order": -2, "auto_start": true,
		"description": "What the valley needs first.",
		"steps": [
			{"title": "Read the board", "icon": "hearthhold:charter_board",
				"text": "Somebody kept this place, and left a note about what it needed. It is still in the yard.",
				"goal": {"type": "use_block", "target": "hearthhold:charter_board"},
				"page": "hearthhold:arriving"},
			{"title": "Light the hearth", "icon": "hearthhold:cold_hearth",
				"text": "Three logs will do it, and you are carrying them. Right-click the hearth at the middle of the yard.",
				"goal": {"type": "use_block", "target": "hearthhold:cold_hearth"},
				"page": "hearthhold:arriving"},
			{"title": "Make a light you can carry", "icon": "base:torch",
				"text": "The hearth lights the yard, not the valley. Open a crafting table's Experiment tab and put something that burns on top of a stick.",
				"goal": {"type": "learn", "target": "base:torch"},
				"page": "base:experiment", "hint": false, "reward": [["base:stick", 4]]},
		],
		"reward": [["base:torch", 2]]})
