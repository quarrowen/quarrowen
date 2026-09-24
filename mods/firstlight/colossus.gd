extends RefCounted
## The ending: the altar you build deep underground, and what happens when you light it.
##
## **The Colossus is not killed.** It is put back to sleep, which is the whole point of the story and
## the reason there is no boss fight at the end of a game for children. Wick has known where it is
## for a very long time and has never once gone down to look; what the player brings is not a sword,
## it is the nerve to go with him. (2026-09-24)
##
## **Two multiblocks, not one.** `altar` is the ring of sunstone on deepstone - building it is act 11.
## `altar_lit` is the same ring with the last light set in its middle, which is act 12 and the ending.
## Splitting them means the last act is one deliberate placement rather than a puzzle, and a child who
## has carried the lantern this far knows exactly what to do with it without being told.
##
## The reward is the one thing this game can give that means anything: **the nights get quieter, for
## good.** Monster caps drop and stay dropped, in the save, so the world the children go back to
## afterwards is visibly the world they changed. Not a trophy - a different place.

## How far the quiet reaches. The whole world, because a fix that only works near the altar is a fix
## the children have to stand next to.
const CALMED := {"monster": 1}

var api
var _lit := {}  # realm -> true, so the ending happens once per world and not once per rebuild


func setup(mod_api) -> void:
	api = mod_api
	_recipe(api)
	_patterns(api)
	api.on("multiblock_formed", func(ev):
		if String(ev.get("name", "")) == "firstlight:altar_lit":
			_wake(ev))


## How sunstone becomes a block you can build with. **The recipe is here and the block is in `base`**,
## which is the line this project holds: `base` says a Sunstone Block exists, a game says what it
## costs. A creative game takes the block and ships no recipe at all, and nothing breaks.
func _recipe(api) -> void:
	api.register_recipe({"base:sunstone": 9}, "base:sunstone_block", 1,
		{"station": "crafting_table"})


## Four corners of sunstone standing on deepstone, and in act 12 a lantern between them.
##
## Drawn bottom layer first, the way anybody would draw it on paper. The floor must be deepstone,
## which is what makes this a thing you build *down there* rather than in the garden - the story has
## spent four acts getting the player underground and the ending should need that to have happened.
func _patterns(api) -> void:
	api.register_multiblock("altar", {
		"layers": [["DDD", "DDD", "DDD"],
				   ["S S", "   ", "S S"]],
		"key": {"D": "base:deepstone", "S": "base:sunstone_block"},
		"controller": "D"})
	api.register_multiblock("altar_lit", {
		"layers": [["DDD", "DDD", "DDD"],
				   ["S S", " T ", "S S"]],
		"key": {"D": "base:deepstone", "S": "base:sunstone_block", "T": "base:torch"},
		"controller": "T"})


## The ending. Said rather than shown, because this game has no cutscenes and a paragraph read at
## bedtime is worth more than a camera move nobody wrote.
func _wake(ev: Dictionary) -> void:
	var realm := String(ev.get("realm", ""))
	if _lit.has(realm):
		return
	_lit[realm] = true
	api.set_spawn_caps(CALMED)
	api.broadcast("The light catches. Somewhere a long way down, something enormous turns over and settles.")
	api.broadcast("[Wick] That's it. That's all it wanted. Someone to put the light back.")
	api.broadcast("The nights will be quieter now. You did that.")
	for p in api.players():
		# The story is over and the world is not. Everything stays exactly where it is; what changed
		# is the dark, which is the only thing that was ever the problem.
		api.advance_objective(p, "act_firstlight")
