extends RefCounted
## The guide is the storybook. Pages fill in as a child plays rather than being handed to them at the
## start: a page for arriving, a page once the fire is in, a page when somebody comes home. Read in
## order afterwards they are the story so far, written by what actually happened.
##
## Nothing here is required reading. A child who never opens the book still finishes the chapter, because
## the charter board says what to do and the hearthstone says what is missing. This is for the ones who
## want to know why the valley is empty.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.register_guide_chapter("valley", {"title": "The Valley", "icon": "hearthhold:cold_hearth", "order": -1,
		"description": "What happened here, and what is being put right."})

	api.register_guide_page("arriving", {"chapter": "valley", "title": "Arriving", "order": 0,
		"icon": "hearthhold:cold_hearth", "keywords": "story outpost hearth warden valley light",
		"blocks": [
			{"type": "text", "text": "Quarrowen was a working valley: a quarry, a road, and a light at the heart of it that kept the dark thin."},
			{"type": "text", "text": "One long night the light went out. Nobody agreed on why. People took what they could carry and scattered into the hills, meaning to come back when it was over, and it was never quite over."},
			{"type": "text", "text": "The outpost at the valley mouth still stands. The board in the yard still has the last warden's handwriting on it, asking for firewood."},
			{"type": "tip", "text": "Three logs will light the hearth. Right-click it holding them."},
		]})

	api.register_guide_page("the_fire", {"chapter": "valley", "title": "Keeping the Fire", "order": 1,
		"icon": "base:torch", "unlock": {"item": "base:torch"},
		"keywords": "night dark monsters light fire safe",
		"blocks": [
			{"type": "text", "text": "The dark has had this valley to itself for a long time, and it is not used to being argued with."},
			{"type": "text", "text": "Light is the argument. Torches by the hearth, torches along the wall, torches wherever you mean to stand still. Monsters do not come where they can be seen."},
			{"type": "tip", "text": "Smoke carries a long way. Somebody will see it."},
		]})

	api.register_guide_page("somewhere_to_live", {"chapter": "valley", "title": "Somewhere to Live", "order": 2,
		"icon": "hearthhold:hearthstone", "unlock": {"item": "hearthhold:hearthstone"},
		"keywords": "house home hearthstone bed door roof walls settler",
		"blocks": [
			{"type": "text", "text": "People will not stay in a field. A house is five things, and a [b]Hearthstone[/b] will tell you which of them you are missing:"},
			{"type": "text", "text": "• a bed to sleep in\\n• walls around the bed\\n• a roof over it\\n• a light for the night - the sun does not count\\n• a door to come in by"},
			{"type": "recipe", "output": "hearthhold:hearthstone"},
			{"type": "text", "text": "Place the hearthstone where the house is to be and right-click it. It ticks each thing off as you build. When they all tick, somebody can live there."},
			{"type": "tip", "text": "The house does not have to be beautiful. It has to have the five things. Beautiful is between you and whoever moves in."},
		]})

	api.register_guide_page("bramble", {"chapter": "valley", "title": "Bramble", "order": 3,
		"icon": "base:bowl", "unlock": {"flag": "met_bramble"},
		"keywords": "bramble cook settler stew pot",
		"blocks": [
			{"type": "text", "text": "She saw the fire from the ridge and walked two days towards it, which tells you something about how long she had been on her own."},
			{"type": "text", "text": "She cooks. Give her a roof and the pot goes on, and a cooked meal does more for you than the same food raw ever did."},
			{"type": "tip", "text": "Lost her? Type /bramble and the game will say which way she went."},
		]})
