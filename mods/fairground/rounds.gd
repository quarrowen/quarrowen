extends RefCounted
## Running a round: open an arena, put people in it, ask the game how everybody is doing, and put them
## back where they came from.
##
## **The Fairground drives and the game answers.** Every tick this raises `fairground:round_tick` with
## the scores so far, and whichever mod owns the game writes into it - a score per player, a player who
## is out, or `finished` when the whole thing is over. The Fairground never learns what the game is; it
## knows a timer, a list of people, and who is still in.
##
## **An arena is an instance**, which is the engine's word for a realm with a lifetime: made on demand,
## never written to disk, everybody returned to where they entered, and thrown away when it empties.
## That is also the whole of "reset between rounds" - there is no reset, because round two opens a new
## one and the wrecked one evaporates.

const Protocol = preload("res://mods/fairground/protocol.gd")

## A round ends this long after it is decided, so the last thing that happened is still on the screen
## when the scores appear rather than being replaced by the hub mid-cheer.
const LINGER := 4.0
## The countdown before a round starts, which is also how long somebody has to realise they are in it.
const COUNTDOWN := 5.0
## How often a round is asked how it is going. One second: a game that needs finer timing than that
## keeps its own `api.every`, and asking every frame would put a mod's handler in the physics loop.
const TICK := 1.0

var api
## game id -> definition (see protocol.gd)
var games := {}
## instance id -> {game, instance, realm, started, seconds, players, scores, out, state}
var live := {}

var _hub
## Seconds since this mod started, counted here. **The mod API exposes the time *of day***, which runs
## on the world clock and restarts with the server, so it cannot answer "how long has this round been
## going". `wick.gd` keeps its own for the same reason.
var _elapsed := 0.0


func setup(mod_api, hub) -> void:
	api = mod_api
	_hub = hub
	# **Asked for once, at setup, and not again.** A game that appears later would need the doors
	# rebuilt and the hub re-laid-out; games are declared by mods and mods are all loaded by now.
	var answer: Dictionary = api.emit("games", {"games": []})
	for entry in answer.games:
		var read := Protocol.clean(entry, _owner_of(entry))
		if read.has("error"):
			api.warn("a game was refused: %s" % read.error)
			continue
		games[read.game.id] = read.game
	api.info("%d game%s at the fairground" % [games.size(), "" if games.size() == 1 else "s"])
	api.every(TICK, func():
		_elapsed += TICK
		_tick())


## Which mod appended a game. **Taken from the entry rather than guessed**, because `emit` hands every
## handler the same payload and there is no way to tell from the outside who wrote into it. A mod that
## does not say is called "somebody", which is wrong in the logs and harmless everywhere else.
func _owner_of(entry) -> String:
	if entry is Dictionary and not String(entry.get("mod", "")).is_empty():
		return String(entry.mod)
	return "somebody"


## Opens an arena and puts these players into it. Returns the round id, or "" with a reason sent to
## whoever asked.
func begin(game_id: String, starters: Array) -> String:
	var game: Dictionary = games.get(game_id, {})
	if game.is_empty():
		return ""
	if starters.size() < int(game.min_players):
		for p in starters:
			p.send_message("%s needs %d." % [String(game.display_name), int(game.min_players)])
		return ""
	var instance: String = api.open_instance("arena", {"data": {"game": game_id}})
	if instance.is_empty():
		for p in starters:
			p.send_message("No room for another game just now.")
		return ""
	# **The arena's own rules, which is what per-realm gameplay was built for.** Nothing spawns, nobody
	# starves, and falling is the game's business rather than the engine's - a round that killed you
	# for landing badly would be a different game every time somebody built a ledge.
	#
	# Set on **the instance's own id, not the kind's**: each run is its own realm ("fairground:arena#3"), so
	# the rules are set on the realm that was just opened rather than on the name it was opened from -
	# which would have set them on a realm that does not exist and silently done nothing.
	api.set_gameplay({"mob_spawning": false, "hunger": false, "fall_damage": false,
		"keep_inventory": true, "pvp": false}, instance)
	var round_id := instance
	live[round_id] = {"game": game_id, "instance": instance, "started": _elapsed,
		"seconds": float(game.seconds) + COUNTDOWN, "players": starters.duplicate(),
		"scores": {}, "out": {}, "state": {}}
	for p in starters:
		# Their own things go in the cloakroom and come back at the end, whatever the round does to
		# them. `save_items` / `clear_inventory` / `load_items` is the round trip an arena needs.
		live[round_id].state[p.player_id] = {"kept": p.save_items()}
		p.clear_inventory()
		api.enter_instance(p, instance, Vector3(0.5, 65.0, 0.5))
		p.show_title(String(game.display_name), String(game.blurb), 3.0)
	api.emit("round_start", {"round": round_id, "game": game_id, "instance": instance,
		"players": starters.duplicate(), "state": live[round_id].state})
	return round_id


## One second of every live round.
func _tick() -> void:
	for round_id in live.keys():
		var run: Dictionary = live[round_id]
		var game: Dictionary = games.get(String(run.game), {})
		if game.is_empty():
			_finish(round_id)
			continue
		var elapsed: float = _elapsed - float(run.started)
		if elapsed < COUNTDOWN:
			continue
		var left: float = float(run.seconds) - elapsed
		var ev: Dictionary = api.emit("round_tick", {"round": round_id, "game": String(run.game),
			"instance": String(run.instance), "seconds_left": left,
			"players": _still_in(run), "scores": run.scores, "out": [], "state": run.state,
			"finished": false})
		for p in ev.out:
			if p != null and not (run.out as Dictionary).has(p.player_id):
				(run.out as Dictionary)[p.player_id] = true
				_watch(p)
		var alone: bool = String(game.ends) == "elimination" and _still_in(run).size() <= 1
		if bool(ev.finished) or left <= 0.0 or alone:
			_finish(round_id)


## Knocked out, and watching the rest. **Not sent home**: a child who is out and immediately standing
## in the hub has been told the game is over for everybody, which it is not.
func _watch(p) -> void:
	p.set_phasing(true)
	p.set_look({"hide": ["*"]})
	p.show_title("Out", "Watch the rest", 2.0)


func _still_in(run: Dictionary) -> Array:
	return (run.players as Array).filter(func(p): return p != null and not (run.out as Dictionary).has(p.player_id))


## Scores up, things back, everybody home, arena thrown away.
func _finish(round_id: String) -> void:
	var run: Dictionary = live.get(round_id, {})
	if run.is_empty():
		return
	live.erase(round_id)
	api.emit("round_end", {"round": round_id, "game": String(run.game),
		"instance": String(run.instance), "scores": run.scores, "state": run.state})
	var board := _scoreboard(run)
	for p in run.players:
		if p == null:
			continue
		p.set_phasing(false)
		p.set_look({})
		p.clear_inventory()
		p.load_items((run.state as Dictionary).get(p.player_id, {}).get("kept", {}))
		p.show_title("", board, 5.0)
		api.leave_instance(p)
	# Closed after they are out rather than left to empty on its own, because "the arena is still
	# standing behind you" is a thing nobody wants and `empty_seconds` would take half a minute over it.
	api.after(LINGER, func(): api.close_instance(String(run.instance)))


## The line everybody sees at the end. One line, because five names down the middle of the screen is
## a wall of text to a seven-year-old and the board in the hub is where the detail belongs.
func _scoreboard(run: Dictionary) -> String:
	var best := ""
	var best_score := -INF
	for player_id in run.scores:
		if float(run.scores[player_id]) > best_score:
			best_score = float(run.scores[player_id])
			best = player_id
	if best.is_empty():
		return "Good game"
	for p in run.players:
		if p != null and p.player_id == best:
			return "%s - %d" % [p.name, int(best_score)]
	return "Good game"
