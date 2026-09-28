extends RefCounted
## The board beside each door: what the game is called, and the best anybody has managed at it.
##
## **A board is an entity wearing a label and nothing else.** The world has no text in it - there is no
## way to write on a block - and the one thing the engine can already put words at a position in the
## world is a nameplate, which rides on an entity. So a board is an `object` entity, hidden entirely
## (`hide: ["*"]`), standing still beside a doorway with up to four lines over its head.
##
## Three capabilities already existed and this needed no new ones: `kind: "object"` (a declared entity
## kind that, before this, nothing in the engine or any mod had ever used - it gets no AI, which is the
## whole point), `set_look`'s `hide`, and `set_nameplate`. The only engine change was that `hide: ["*"]`
## meant "all of it" for a player avatar and nothing at all for a creature, so a board came with a
## creature standing inside it. (2026-09-28)
##
## **`float_text` was the obvious wrong answer.** It puts a word at a position, which is what this wants,
## and it is transient by design - it drifts upwards and goes. A scoreboard that has to be redrawn every
## few seconds for the life of the server is a timer nobody needed and a flicker everybody sees.
##
## The bests live in `api.storage`, the mod's own dictionary saved with the world, so the fairground
## remembers across restarts. Nothing here is per-player: one number per game, and the name of whoever
## set it.

## Where the board sits relative to its door: just in front and a little to the side, so walking into the
## light does not walk you through the label.
const OFFSET := Vector3(0.0, 1.4, 0.0)
const SIDE := 1.6

var api
## slot -> the entity standing there
var signs := {}

var _type := -1


func setup(mod_api) -> void:
	api = mod_api
	# No AI block at all: `object` never reaches the brain. Gravity off so it holds its height whatever
	# is or is not under it, and persistent so it is not swept away for standing in an empty hub - the
	# doors are built before anybody has joined, which is exactly the case that removes a creature the
	# same tick it appears.
	_type = api.register_entity("board", {"kind": "object", "display_name": "Board",
		"width": 0.2, "height": 0.2, "health": 1, "gravity": 0.0, "persistent": true,
		"nameplate": {"show_health": false, "range": 30.0}})


## The bests, as {game id: {score, name}}. Read through here rather than reached into, so the shape is
## in one place.
func bests() -> Dictionary:
	if not (api.storage.get("bests") is Dictionary):
		api.storage["bests"] = {}
	return api.storage["bests"]


## Stands a board beside a door. `facing` is the angle the door sits at round the ring, which is also
## the direction "outwards" - so the board goes to one side of it rather than in the doorway.
func raise(slot: int, game: Dictionary, at: Vector3i, angle: float) -> void:
	if _type < 0:
		return
	var sideways := Vector3(-sin(angle), 0.0, cos(angle)) * SIDE
	var where := Vector3(at) + Vector3(0.5, 0.0, 0.5) + OFFSET + sideways
	# **Spawned into open air and then moved**, because `spawn` refuses a position with no room to stand
	# and returns null, and a board's place is chosen from the door rather than from the floor.
	var sign_entity = api.spawn_entity("fairground:board", where)
	if sign_entity == null:
		api.warn("no room for the board beside door %d" % slot)
		return
	sign_entity.position = where
	sign_entity.set_look({"hide": ["*"]})
	signs[slot] = {"entity": sign_entity, "game": String(game.id), "title": String(game.display_name)}
	_write(slot)


## Offers a score to a game's board. Returns true when it was a new best, so the round can say so.
func offer(game_id: String, score: float, who: String) -> bool:
	var table := bests()
	var standing: Dictionary = table.get(game_id, {})
	if not standing.is_empty() and float(standing.get("score", 0.0)) >= score:
		return false
	table[game_id] = {"score": score, "name": who}
	for slot in signs:
		if String(signs[slot].game) == game_id:
			_write(slot)
	return true


## Puts the current words on one board.
func _write(slot: int) -> void:
	var board: Dictionary = signs.get(slot, {})
	if board.is_empty() or board.entity == null or not is_instance_valid(board.entity):
		return
	var standing: Dictionary = bests().get(String(board.game), {})
	var line := "Nobody has played this yet"
	if not standing.is_empty():
		# The score is stored as a float because a game may keep fractions of one; shown as a whole
		# number, because every game written so far counts things.
		line = "Best  %d  -  %s" % [int(round(float(standing.get("score", 0.0)))), String(standing.get("name", "?"))]
	# **Both in `lines`, with no `name`.** A plate stacks upwards from the head - bar, then name, then the
	# mod's lines *above* it - which is right for a creature, where the extra line is an aside over a
	# thing that already has a name in front of you. On a board it put "Nobody has played this yet" above
	# the name of the game, so the sign read bottom-up. The lines label is one multi-line label and reads
	# top-down, so saying both there puts the title where a sign's title goes. Seen in a photograph; the
	# tests had no opinion about it. (2026-09-28)
	# The empty `name` is not redundant: a plate with no name falls back to the entity's display name, so
	# every board in the fairground carried the word "Board" under its title. Also only visible in a
	# photograph.
	api.set_nameplate(board.entity, {"name": "", "lines": [String(board.title), line], "show_health": false})
