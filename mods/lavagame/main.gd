extends "res://engine/server/mod.gd"
## The Floor is Lava, for the Fairground: the lava rises a block at a time and you climb away from it,
## with a pocketful of blocks to build something to stand on when the pillars run out.
##
## **Written to be worth playing alone**, which is the rule the whole Fairground runs on (the user,
## 28 September 2026: "usually solo, sometimes together"). So it scores rather than eliminates: the
## round ends when the lava reaches the roof or everybody is in it, and what you get is **how long you
## lasted**. A rival makes that better and is not required, which is the difference between a game
## these children can play on a Tuesday and one they can play twice a year.
##
## **It is a separate mod, which is the point.** The Fairground knows nothing about lava; it asked
## `fairground:games` who had a game, and this answered. Everything below is content - a room, a
## kit, and a rule about height - over capabilities the engine already had.

const Arena = preload("res://mods/lavagame/arena.gd")

## Seconds between the lava coming up one block. **Eight**, which is slow enough to think and fast
## enough that a four-minute round ends in lava rather than in boredom: thirty layers over four
## minutes, and the arena is twenty-two tall.
const RISE_EVERY := 8.0

var arena := Arena.new()
## instance id -> {level, next_rise, safe}
var runs := {}

var _ids := {}


func setup(api) -> void:
	_ids.lava = api.require_block("base:lava")
	_ids.platform = api.require_block("base:stone")
	_ids.kit = api.require_block("base:planks")
	arena.setup(api, _ids)

	# Answering the Fairground's roll call. `mod` is how it knows who wrote this, since `emit` hands
	# every listener the same payload and there is no way to tell from outside who appended what.
	api.on("fairground:games", func(ev): ev.games.append({
		"mod": "lavagame",
		"id": "lava",
		"display_name": "The Floor is Lava",
		"blurb": "Climb. Don't touch the floor.",
		"min_players": 1,
		"max_players": 8,
		"seconds": 240,
		"ends": "score",
		# The island in the middle of the pit, not the Fairground's default: this game's floor is
		# twenty blocks lower than a hub's.
		"spawn": Vector3(0.5, Arena.FLOOR_Y + 2, 0.5),
	}))

	api.on("fairground:round_start", func(ev):
		if not _mine(ev):
			return
		arena.build(String(ev.instance))
		runs[String(ev.instance)] = {"level": Arena.FLOOR_Y, "next_rise": RISE_EVERY}
		for p in ev.players:
			# A kit rather than their own things: the Fairground put those in the cloakroom, and a game
			# where the child with the best pickaxe wins is not a game anybody else wants to play.
			p.set_hotbar([_ids.kit], 32)
			p.send_message("The lava is coming. Climb.")
		api.after(1.0, func(): arena.flood(String(ev.instance), Arena.FLOOR_Y)))

	api.on("fairground:round_tick", func(ev):
		if not _mine(ev):
			return
		_rise(api, ev))

	api.on("fairground:round_end", func(ev):
		if _mine(ev):
			runs.erase(String(ev.instance)))


## Whether this event is about our game. Every mod's handler sees every round, because the Fairground
## raises one event and everybody listening gets it - so the first line of each handler is this.
func _mine(ev) -> bool:
	return String(ev.game).ends_with(":lava")


## One second of a round: bring the lava up when it is due, and score everybody who is still above it.
func _rise(api, ev) -> void:
	var run: Dictionary = runs.get(String(ev.instance), {})
	if run.is_empty():
		return
	run.next_rise = float(run.next_rise) - 1.0
	if float(run.next_rise) <= 0.0:
		run.next_rise = RISE_EVERY
		run.level = int(run.level) + 1
		if int(run.level) >= Arena.ROOF_Y:
			# Nowhere left to climb: the room is full and the round is over however many are still up.
			ev.finished = true
			return
		arena.flood(String(ev.instance), int(run.level))
		for p in ev.players:
			p.show_title("", "The lava is rising", 1.2)
	# **Scored on the clock, not on height.** Height rewards whoever started on the tallest pillar; a
	# second survived is a second survived wherever you are standing.
	for p in ev.players:
		if p == null:
			continue
		if p.position.y < float(run.level) + 0.5:
			# In it. Out of the round, and the Fairground does the rest - a player who is out watches.
			ev.out.append(p)
		else:
			ev.scores[p.player_id] = int(ev.scores.get(p.player_id, 0)) + 1
	if ev.out.size() >= (ev.players as Array).size():
		ev.finished = true
