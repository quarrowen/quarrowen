extends RefCounted
## Firstlight's own guidebook chapter: the four subjects the book could not cover.
##
## **Why these are here and not in `guidebook`.** That mod is a library, and its pages are all about
## `base`, `simple_machines` and `simple_gear` - nouns any game might have. Wick, the ruin and the thing
## under the world are *this story's*, and a library that knew about them could not be used by a game
## that does not have them. The line the project draws for blocks draws itself the same way for pages:
## `base` owns nouns, a game owns its own. (2026-09-27)
##
## **Everything here is locked until the story reaches it, and that is the whole design.** A guidebook
## that tells a child how the story ends before they get there has done the opposite of helping. Three
## of the four unlock on something the player has actually done - met him, found sunstone - and the last
## two on flags the story sets as it hands the act over, so a page arrives in the same breath as the man
## asking for it.
##
## The voice follows Wick's: plain, kind, and never grand about it. A page is read at bedtime by
## somebody who has forgotten what they were doing since Tuesday, so each one opens by saying where you
## are before it says anything else.

const CHAPTER := "lights"


func setup(api) -> void:
	api.register_guide_chapter(CHAPTER, {"title": "The Lights", "icon": "base:sunstone",
		# After the base chapters (0, 5, 10, 15): this is the story's own shelf and it reads oddly above
		# "how do I make a pickaxe".
		"order": 20,
		"description": "Wick, the old lights, and what put them out."})
	_wick(api)
	_old_lights(api)
	_ruin(api)
	_colossus(api)


## He is the first thing in this game a child meets and nothing anywhere explained him - not that he
## cannot be hurt, which is the fact that stops a child panicking the first time something swings at
## him, and not that he teleports, which is why walking off is allowed.
func _wick(api) -> void:
	api.register_guide_page("wick", {"chapter": CHAPTER, "title": "Wick", "order": 0,
		"icon": "base:torch",
		"unlock": {"entity": "firstlight:wick"},
		"keywords": "wick lamplighter guide companion follow hat coat man",
		"blocks": [
			# **The portrait is second, not first.** It is nearly the height of the page, so opening on it
			# meant every word was below the fold and a page about a person said nothing about him until
			# you scrolled. Photographed on 2026-09-27; the same trap as the task panel, one day and one
			# panel apart. An `entity` block is a picture, and a picture goes under the sentence it
			# illustrates.
			{"type": "text", "text": "Wick keeps the lights. He has been keeping them alone for a long time, and lately he has been losing."},
			{"type": "entity", "entity": "firstlight:wick"},
			{"type": "heading", "text": "He cannot be hurt"},
			{"type": "text", "text": "Nothing can hurt him - not monsters, not falling, not lava. If something swings at him it simply does not land. You do not have to protect him, and you never have to go back for him."},
			{"type": "heading", "text": "He keeps up"},
			{"type": "text", "text": "He follows you. If you get far enough ahead, or put a ravine between you, he turns up beside you again. So go where you like."},
			{"type": "text", "text": "[b]Right-click him[/b] to talk. He will tell you what you are doing, and where to read about it."},
			{"type": "tip", "text": "He cannot fight at all, and he says so. That is why the story needs you and not him."},
		]})


## Sunstone, and the block the story's recipe makes from it. **The recipe belongs to this game and the
## stone belongs to `base`**, which is the line holding correctly - and it is also why the page has to
## be here: in the library it would show a recipe card for something only Firstlight registers.
func _old_lights(api) -> void:
	api.register_guide_page("old_lights", {"chapter": CHAPTER, "title": "The Old Lights", "order": 1,
		"icon": "base:sunstone_block",
		"unlock": {"item": ["base:sunstone_ore", "base:sunstone"]},
		"hint": "Find sunstone, and this page fills itself in.",
		"keywords": "sunstone old lights altar block glow deep rare",
		"blocks": [
			{"type": "text", "text": "The lights that kept the dark thin were not torches. They were made of [b]sunstone[/b], which holds a little of the sun in it and gives it back slowly, for a very long time."},
			{"type": "items", "items": ["base:sunstone_ore", "base:sunstone", "base:sunstone_block"]},
			{"type": "text", "text": "Sunstone is the rarest thing in the ground and it is only found under everything else. Four pieces make one block of it."},
			{"type": "recipe", "output": "base:sunstone_block"},
			{"type": "tip", "text": "Sunstone blocks give off light on their own. They make a good roof over a place you want to find again."},
			{"type": "link", "page": "ruin"},
		]})


## Unlocked by a flag the story sets when act 13 is handed over, so it arrives with Wick's line about it
## and not before. The page's job is the one thing the act cannot say in a sentence: what "two corners
## short" actually looks like when you are standing in front of it in the dark.
func _ruin(api) -> void:
	api.register_guide_page("ruin", {"chapter": CHAPTER, "title": "The Ruin", "order": 2,
		"icon": "base:sunstone_block",
		"unlock": {"flag": "seeking_ruin"},
		"hint": "Wick will tell you when this matters.",
		"keywords": "ruin altar broken corners repair build deep chamber",
		"blocks": [
			{"type": "text", "text": "Somebody built a light down here long before either of you. Most of it is still standing. Two of its four corners are not."},
			{"type": "text", "text": "It sits in an open chamber in the deep, on dark stone, and it is easy to walk past - look for two blocks that glow where nothing else does."},
			{"type": "heading", "text": "Putting it back"},
			{"type": "text", "text": "Set a [b]sunstone block[/b] on each of the two empty corners. Eight sunstone ore makes exactly the two you need, with none left over."},
			{"type": "items", "items": ["base:sunstone_block"]},
			{"type": "tip", "text": "You are repairing it, not building it. If a corner will not take a block, you are looking at the wrong square - the ones that are missing are the ones with nothing on them."},
			{"type": "link", "page": "colossus"},
		]})


## The last page in the book, and the one most worth getting right: a child reads this at the point
## where a story of this shape usually produces a monster to kill. This one does not, and saying so
## plainly is the kind thing to do at bedtime.
func _colossus(api) -> void:
	api.register_guide_page("colossus", {"chapter": CHAPTER, "title": "What Is Under The World", "order": 3,
		"icon": "base:sunstone",
		"unlock": {"flag": "woke_it"},
		"hint": "Wick will tell you when this matters.",
		"keywords": "colossus ending sleep wake boss last act firstlight",
		"blocks": [
			{"type": "text", "text": "Something very old sleeps under everything. While it is awake the nights are full, and it has been awake for a long time - which is why the lights have been going out faster than one man can light them."},
			{"type": "heading", "text": "It is not killed"},
			{"type": "text", "text": "You do not have to fight it and you cannot beat it. Lighting the old altar puts it back to sleep, which is what it wants and what Wick has wanted for years and never been brave enough to do by himself."},
			{"type": "text", "text": "Stand at the altar when you light it. It takes a few moments, and it is worth watching."},
			{"type": "tip", "text": "Nothing here can be failed and nothing runs out of time. If it goes wrong you can simply do it again."},
			{"type": "text", "text": "Afterwards the world is still yours. The nights get quieter, and Wick stays."},
		]})
