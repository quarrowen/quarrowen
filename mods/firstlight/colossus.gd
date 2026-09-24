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

## The chamber. **A hall, not a room** (the user, 2026-09-24: "chambers should be huge right especially
## for boss fights"). Twenty-one across and eighteen tall against a creature seven blocks high, so the
## Colossus rises with the ceiling still well above it and the space still reads as bigger than
## whatever is standing in it. A cramped boss room makes the boss look small, which is the opposite of
## what the room is for - and this one is the last thing in the game, so it is allowed to be the
## largest. Every cell inside has to be listed as air, because a template leaves untouched anything it
## does not name; twenty-one cubed is a big array and generating it once at load is nothing.
const SPAN := 21
const HEIGHT := 18
## Palette indexes for the template below, named because [0, 1, 2, 3] in a coordinate list is
## unreadable the day after it is written.
const DEEP := 0
const SUN := 1
const COBBLE := 2
const AIR := 3

## How far under the floor it starts. Seven blocks of creature plus a little, so the first thing the
## player sees is the top of its head rather than all of it at once.
const BURIED := 9.0

var api
var _lit := {}     # realm -> true, so the ending happens once per world and not once per rebuild
var _found := {}   # player id -> the ruin we pointed them at
var _waking := 0   # the entity id of the one currently rising, so it can be kept peaceful


func setup(mod_api) -> void:
	api = mod_api
	_recipe(api)
	_template(api)
	_patterns(api)
	api.on("multiblock_formed", func(ev):
		if String(ev.get("name", "")) == "firstlight:altar_lit":
			_wake(ev))
	# **It never fights and it cannot be hurt**, enforced rather than hoped for. Both events are
	# cancellable, so a child who panics and swings at seven metres of waking god achieves nothing at
	# all - which is the right outcome: killing it was never the ending.
	api.on("mob_target", func(ev):
		if ev.entity != null and ev.entity.id == _waking:
			ev.cancelled = true)
	api.on("entity_damage", func(ev):
		if ev.entity != null and ev.entity.id == _waking:
			ev.cancelled = true)
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
	# **A hall, not a slab.** It was a 5x5 floor until the ending needed somewhere for a seven-metre
	# figure to stand up in, and then somewhere that would still feel bigger than it once it had.
	# Air is a palette entry that clears terrain, so the template carves its own room. (2026-09-24)
	for x in SPAN:
		for z in SPAN:
			for y in range(1, HEIGHT):
				blocks.append([x, y, z, AIR])
			blocks.append([x, 0, z, DEEP])       # floor
			blocks.append([x, HEIGHT, z, DEEP])  # roof, so it reads as a room and not as a hole
	# Walls, so a cave breaking in leaves the hall recognisable rather than open on one side.
	for i in SPAN:
		for y in range(1, HEIGHT):
			for wall in [[0, i], [SPAN - 1, i], [i, 0], [i, SPAN - 1]]:
				blocks.append([int(wall[0]), y, int(wall[1]), COBBLE])
	# Eight pillars in two rows down the hall, four still holding the roof up and four broken off at
	# uneven heights. Uneven on purpose: symmetrical damage reads as a design rather than as something
	# that fell down - and the standing ones are what give the space its scale, because a room with
	# nothing in it is just a number.
	var standing := [[4, 4], [SPAN - 5, 4], [4, SPAN - 5], [SPAN - 5, SPAN - 5]]
	for pillar in standing:
		for y in range(1, HEIGHT):
			blocks.append([int(pillar[0]), y, int(pillar[1]), COBBLE])
	for broken in [[4, 10, 11], [SPAN - 5, 10, 4], [10, 4, 7], [10, SPAN - 5, 2]]:
		for y in int(broken[2]):
			blocks.append([int(broken[0]), 1 + y, int(broken[1]), COBBLE])
	# The altar sits on the middle 3x3 of the floor. Its four corners are at the corners of that 3x3;
	# two still stand and two are rubble on the floor beside where they were, which is what tells the
	# player what is missing without anybody having to say it.
	var mid := SPAN / 2
	blocks.append([mid - 1, 1, mid - 1, SUN])  # standing
	blocks.append([mid + 1, 1, mid + 1, SUN])  # standing
	blocks.append([mid + 1, 1, mid - 2, COBBLE])  # fallen, beside where it was
	blocks.append([mid - 2, 1, mid + 1, COBBLE])
	api.register_structure_template("altar_ruin", {"size": [SPAN, HEIGHT + 1, SPAN],
		"palette": ["base:deepstone", "base:sunstone_block", "base:cobblestone", "engine:air"],
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


## The ending. **It is seen, not described.**
##
## The Ancient Colossus has existed in `base` since creatures did - seven blocks tall, its own model,
## a boss preset - and nothing in any game had ever spawned one. The ending was three lines of chat
## about something enormous turning over, which is a sentence where there should be a seven-metre
## figure. Now it rises out of the chamber floor, stands there a moment, and goes back down.
##
## **It never fights and it cannot be hurt**, which is the user's decision from the start and is
## enforced here rather than hoped for: `mob_target` and `entity_damage` are both cancellable, so a
## child who panics and swings at it achieves nothing at all. Killing it was never the ending - it is
## put back to sleep, and that is the whole point of the story.
func _wake(ev: Dictionary) -> void:
	var realm := String(ev.get("realm", ""))
	if _lit.has(realm):
		return
	_lit[realm] = true
	api.set_spawn_caps(CALMED)
	api.broadcast("The light catches, and holds.")
	_rise(Vector3(ev.get("controller", Vector3i.ZERO)))


## Brings it up out of the floor, holds it there, and lets it back down.
##
## Driven by moving the entity rather than by an animation, because there is no animation to play:
## setting `position` zeroes its velocity, so each step overrides gravity and the whole thing is a
## scripted move on a timer. Buried to start with - inside the stone under the chamber, where nobody
## can see it - so what the player watches is a shape coming up through the floor.
func _rise(at: Vector3) -> void:
	var here := Vector3(at.x, at.y, at.z)
	# **Spawned in the open air of the hall, then put underground** - not spawned underground. A spawn
	# into solid rock is refused (there is nowhere to stand), and the refusal is quiet: the ending
	# fired, no creature appeared, and the closing lines ran as though it had. Setting `position`
	# afterwards has no such check, which is what makes the buried start possible at all. Clamped off
	# the bottom of the world too, since the ruin generates as low as y6. (2026-09-24)
	var start := maxf(here.y - BURIED, 2.0)
	var giant = api.spawn_entity("base:colossus", here + Vector3(0.0, 1.0, 0.0))
	if giant != null:
		giant.position = Vector3(here.x, start, here.z)
	if giant == null:
		# Nowhere to put it is not a reason to withhold the ending: say the lines and let it be.
		_closing_words()
		return
	_waking = giant.id
	giant.set_look({"nameplate": {"show_health": false}})
	# **An Array, not an int.** A GDScript lambda captures a local by *value*, so `step += 1` inside one
	# increments a copy that is thrown away: the counter read 1 on every single tick and the Colossus
	# rose four centimetres and stopped for ever. An Array is a reference, so mutating it sticks. There
	# is no warning for this and the symptom is something that moves once. (2026-09-24)
	var step := [0]
	# Roughly twelve seconds all told: up over four, still for four, down over four. Slow on purpose -
	# a seven-metre figure that moves quickly is a jump scare, and this is a goodnight.
	api.every(0.25, func():
		if giant == null or not is_instance_valid(giant) or giant.removed:
			return
		step[0] += 1
		var n: int = step[0]
		if n <= 16:
			giant.position = Vector3(here.x, lerpf(start, here.y, float(n) / 16.0), here.z)
		elif n == 17:
			# It should actually look at them, since the line says so. Nearest player, once, at the top
			# of the rise - it has no AI running to turn it, and a seven-metre figure with its back to
			# you is a different scene from the one the words describe.
			var nearest = null
			for p in api.players():
				if nearest == null or p.position.distance_to(giant.position) < nearest.position.distance_to(giant.position):
					nearest = p
			if nearest != null:
				var to: Vector3 = nearest.position - giant.position
				giant.yaw = atan2(-to.x, -to.z)
			api.broadcast("It stands up out of the floor, and looks at you, and does not do anything else.")
			api.broadcast("[Wick] Oh. Oh, it's just tired. All this time and it was just tired.")
		elif n >= 32 and n <= 48:
			giant.position = Vector3(here.x, lerpf(here.y, start, float(n - 32) / 16.0), here.z)
		elif n == 49:
			api.remove_entity(giant)
			_waking = 0
			_closing_words())


func _closing_words() -> void:
	api.broadcast("Somewhere a long way down, something enormous turns over and settles.")
	api.broadcast("[Wick] That's all it wanted. Someone to put the light back.")
	api.broadcast("The nights will be quieter now. You did that.")
	for p in api.players():
		# The story is over and the world is not. Everything stays exactly where it is; what changed
		# is the dark, which is the only thing that was ever the problem.
		api.advance_objective(p, "act_firstlight")
		api.clear_map_marker(p, "altar")
