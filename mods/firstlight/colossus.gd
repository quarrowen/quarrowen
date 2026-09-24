extends RefCounted
## The ending: a ruined altar you find deep underground, what it takes to repair it, and what happens
## when you light it.
##
## **The Colossus is not killed.** It is put back to sleep, which is the whole point of the story and
## the reason there is no boss fight at the end of a game for children. Wick has known where it is for
## a very long time and has never once gone down to look; what the player brings is not a sword, it is
## the nerve to go with him. (2026-09-24)
##
## **It is found, not invented** (the user, 2026-09-24). The first version had the player build the
## altar anywhere on any deepstone floor, which made the ending a recipe rather than a place. Now a
## broken one generates in the deep - two of its four sunstone corners still standing, two fallen - so
## arriving teaches you the shape without a word, and the last act is repairing somebody else's work
## rather than assembling a kit. Wick marks it on your compass once you are carrying sunstone,
## because a ruin nobody can find is the same as no ruin at all.
##
## **Two multiblocks, not one.** `altar` is the ring of sunstone on deepstone - repairing it is act 13.
## `altar_lit` is the same ring with a light set in its middle, which is act 14 and the ending. That
## split is what makes the last act one deliberate placement: a child who has carried a lantern since
## act 6 knows exactly what to do without being told.
##
## The reward is the one thing this game can give that means anything: **the nights get quieter, for
## good.** Monster caps drop and stay dropped, in the save, so the world they go back to afterwards is
## visibly the world they changed. Not a trophy - a different place.

## How far the quiet reaches. The whole world, because a fix that only works near the altar is a fix
## the children have to stand next to.
const CALMED := {"monster": 1}

## Deep enough to be past the deepstone line (main.gd DEEP_FROM is 30) and above the lava, and the
## same band the sunstone it is made of generates in - so the stone you need is near the thing that
## needs it.
const DEPTH := [6, 20]

var api
var _lit := {}     # realm -> true, so the ending happens once per world and not once per rebuild
var _found := {}   # player id -> the ruin we pointed them at


func setup(mod_api) -> void:
	api = mod_api
	_recipe(api)
	_template(api)
	_patterns(api)
	api.on("multiblock_formed", func(ev):
		if String(ev.get("name", "")) == "firstlight:altar_lit":
			_wake(ev))
	# Wick points the way once the sunstone is in hand. Not before: a marker on the compass from the
	# first morning is a spoiler and a chore, and this way finding it is the reward for act 12.
	api.on("objective_done", func(ev):
		if String(ev.get("objective", "")) == "firstlight:act_sunstone":
			_point_the_way(ev.player))


## How sunstone becomes a block you can build with. **The recipe is here and the block is in `base`**,
## which is the line this project holds: `base` says a Sunstone Block exists, a game says what it
## costs. A creative game takes the block and ships no recipe at all, and nothing breaks.
##
## Four, not nine. Nine is the convention for turning gems into a block and it is wrong here: sunstone
## ore generates at 0.35 veins per chunk between y3 and y16, so nine-to-one would have made the two
## blocks the ruin needs cost thirty-six of the rarest ore in the game. Four-to-one makes act 12's
## eight ore into exactly the two blocks the altar is missing, with nothing left over - which is also
## the easiest kind of sum for a child to hold in their head.
func _recipe(api) -> void:
	api.register_recipe({"base:sunstone": 4}, "base:sunstone_block", 1, {"station": "crafting_table"})


## The ruin, as a template: a sunken chamber with a deepstone floor, two sunstone corners still
## standing and two fallen, and the stumps of what used to hold a roof up.
##
## Built here in GDScript rather than saved as a JSON blob with `/struct save`, because this shape is
## *argued for* - the two missing corners are the puzzle and the two standing ones are the lesson -
## and a hand-edited array of coordinates is the only version of it anybody can read and change. The
## blocks are [x, y, z, palette index].
func _template(api) -> void:
	var blocks := []
	# Floor: 5x5 of deepstone, with the middle 3x3 being the altar's own base.
	for x in 5:
		for z in 5:
			blocks.append([x, 0, z, 0])
	# The four corners of the altar sit on the middle 3x3, at (1,1) (3,1) (1,3) (3,3). Two still
	# stand; the other two are rubble on the floor beside where they were, which is what tells the
	# player what is missing without anybody having to say it.
	blocks.append([1, 1, 1, 1])  # sunstone, standing
	blocks.append([3, 1, 3, 1])  # sunstone, standing
	blocks.append([3, 1, 0, 2])  # fallen: cobblestone rubble where a corner was
	blocks.append([0, 1, 3, 2])
	# Four stumps of pillar around the outside, broken off at different heights. Uneven on purpose:
	# a ruin with symmetrical damage reads as a design, not as something that fell down.
	for pillar in [[0, 0, 1], [4, 0, 2], [0, 4, 1], [4, 4, 3]]:
		for y in int(pillar[2]):
			blocks.append([int(pillar[0]), 1 + y, int(pillar[1]), 2])
	api.register_structure_template("altar_ruin", {"size": [5, 5, 5],
		"palette": ["base:deepstone", "base:sunstone_block", "base:cobblestone"],
		"blocks": blocks})
	# **`spacing` is in chunks, not blocks** - which cost an afternoon. 160 meant one ruin every 2,560
	# blocks, and since Wick marks its position the player would have been sent on a walk measured in
	# kilometres. 24 chunks is about 380 blocks: rare enough that finding one is an event, near enough
	# that the marker is a destination rather than an expedition. `chance` under one means some regions
	# hold nothing at all, so the spacing is a floor on how far apart they are and not a grid anybody
	# could learn. (2026-09-24)
	api.register_structure("altar_site", {"templates": [{"template": "firstlight:altar_ruin"}],
		"place": "underground", "y": DEPTH, "spacing": 24, "separation": 8, "chance": 0.75})


## The ring of sunstone on its deepstone floor, and then the same ring with a light in the middle.
##
## Drawn bottom layer first, the way anybody would draw it on paper. The floor must be deepstone,
## which is what keeps this a thing you finish *down there*: the story spends five acts getting the
## player under the world and the ending should need that to have happened.
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


## Wick tells you where to look: the nearest ruin world generation actually placed, asked of the same
## seeded computation that puts it there, so it works for one nobody has been near yet.
func _point_the_way(player) -> void:
	if player == null or _found.has(str(player.player_id)):
		return
	# The real one. This used to invent a spot near the player and hope, which is how the spacing bug
	# above stayed hidden: a marker that points somewhere plausible looks exactly like a marker that
	# points somewhere true.
	var at: Vector3 = api.find_structure("altar_site", player.position)
	if at == Vector3.INF:
		player.send_message("[Wick] There's one down there somewhere. I've never been able to say where.")
		return
	_found[str(player.player_id)] = at
	api.set_map_marker(player, "altar", {"label": "The old light", "position": at, "color": "#ffc65a"})
	player.send_message("[Wick] There's one down there. I've known for years and never once gone to look.")
	player.send_message("[Wick] I've put it on your compass. You'll have to dig for it, mind.")


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
		api.clear_map_marker(p, "altar")
