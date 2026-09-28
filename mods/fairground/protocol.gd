extends RefCounted
## **How a game mod plugs into the Fairground.** This file registers nothing; it is the contract, kept
## in one place because it is the thing other people's mods depend on and the thing that is expensive
## to change later.
##
## Five events, all raised by `fairground` and answered **in the payload**. There is no call back the
## other way, and that is a consequence of how `api.emit` works rather than a preference: a mod may
## only raise events in its *own* namespace, so a game mod saying `emit("score", ...)` raises
## `yourgame:score`, which the Fairground has never heard of and cannot subscribe to. Answering in the
## payload avoids the whole problem, works identically from JavaScript, and is the shape the engine's
## own events already use - `cancelled`, `amount` and `message` are all written back. (2026-09-28)
##
##     # in a game mod
##     api.on("fairground:games", func(ev): ev.games.append({
##         "id": "lava", "display_name": "The Floor is Lava",
##         "blurb": "Climb. Don't touch the floor.",
##         "min_players": 1, "max_players": 8, "seconds": 240,
##         "ends": "score",
##     }))
##
##     api.on("fairground:round_start", func(ev):
##         if ev.game != "lava": return
##         ...)                      # build the arena, hand out kits
##
##     api.on("fairground:round_tick", func(ev):
##         if ev.game != "lava": return
##         ev.scores[player.player_id] = ...   # say how everybody is doing
##         ev.out.append(player)               # or that somebody is finished
##         ev.finished = true)                 # or that the whole round is
##
## **`id` is the game's own short name and the Fairground qualifies it** with the mod that answered,
## so two mods may both offer a "lava" without meeting. The qualified name is what `ev.game` carries.

## What a game must say about itself. Everything else has a default, because a game that only wants to
## say "I am called this and I last four minutes" should be able to.
const REQUIRED := ["id", "display_name"]

## How a round can finish, which the user settled on 28 September: **each game chooses**, because some
## want a score at the end of a timer and some want a last one standing.
##
## - `score` - nobody is ever out; the timer ends it and the best score wins.
## - `elimination` - players are put out as they fail, and it ends when one (or none) is left.
##
## **`score` is the default and that is deliberate.** The user plays mostly alone ("usually solo,
## sometimes together"), and a game that ends the moment one person is out is a game with nothing in it
## for somebody on their own. A solo round of a scoring game is a personal best.
const ENDINGS := ["score", "elimination"]

## Defaults for everything a game did not say.
const DEFAULTS := {
	"blurb": "",
	"min_players": 1,
	"max_players": 8,
	## Long enough to get somewhere, short enough that being out is not a sentence. Four minutes is a
	## starting guess and every game may say otherwise.
	"seconds": 240.0,
	"ends": "score",
	## Where the door to this game stands in the hub, as a slot number. Unset means "wherever there is
	## room", which is what a mod that does not care should get.
	"door": -1,
}


## Reads what a mod appended and returns {game} or {error}. **Validated here rather than trusted**,
## because the failure of a bad definition is otherwise a round that opens and does nothing, which
## reads as a broken engine rather than a mod that forgot a field.
static func clean(entry, owner: String) -> Dictionary:
	if not (entry is Dictionary):
		return {"error": "a game must be a dictionary"}
	for key in REQUIRED:
		if String(entry.get(key, "")).strip_edges().is_empty():
			return {"error": "a game needs %s" % key}
	var game := DEFAULTS.duplicate()
	for key in entry:
		if game.has(key) or key in REQUIRED:
			game[key] = entry[key]
	game.id = "%s:%s" % [owner, String(entry.id)]
	game.owner = owner
	game.display_name = String(entry.display_name).left(48)
	game.blurb = String(game.blurb).left(140)
	game.min_players = clampi(int(game.min_players), 1, 64)
	game.max_players = clampi(int(game.max_players), int(game.min_players), 64)
	game.seconds = clampf(float(game.seconds), 10.0, 3600.0)
	if not String(game.ends) in ENDINGS:
		return {"error": "'%s' is not a way for a round to end" % String(game.ends)}
	return {"game": game}
