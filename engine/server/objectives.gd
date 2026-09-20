extends RefCounted
## Something a player has been asked to do, and how far along they are: a story, a daily errand, a
## contract, a delivery.
##
## **Why this is not tutorials and not milestones**, both of which already exist. A tutorial *teaches*
## - it starts itself, it is about the game rather than the world, and everybody gets the same one. A
## milestone *commemorates* - it notices something that already happened. An objective is neither: it
## is given, it can be refused, several can be running at once, it has steps in an order, and it can
## be abandoned or fail. Bending either of the others into that shape would have spoiled both.
##
##     api.register_objective("deliver_the_post", {
##         "display_name": "The Post",
##         "steps": [{"text": "Take the letter to Bramble", "count": 1},
##                   {"text": "Bring her answer back", "count": 1}]})
##
##     api.give_objective(player, "deliver_the_post")
##     api.advance_objective(player, "deliver_the_post")   # when the mod decides a step is done
##
## **The engine never works out whether a step is done.** It counts, remembers and tells you; the mod
## watches whatever event means "they did it". Anything else would mean the engine learning what
## delivering a letter is.

const KEY := "_objectives"
## How many one player may have going at once. Enough for a story and a handful of errands; few enough
## that a mod cannot quietly fill a save file.
const MAX_ACTIVE := 32

var server

## Name -> {name, display_name, description, steps: [{text, count}], repeatable, owner}
var kinds := {}


func _init(game_server) -> void:
	server = game_server


func register(objective_name: String, def: Dictionary, owner := "engine") -> bool:
	if objective_name.is_empty() or kinds.has(objective_name):
		push_error("Invalid or duplicate objective '%s'" % objective_name)
		return false
	var steps := []
	for entry in (def.get("steps", []) if def.get("steps") is Array else []):
		if entry is Dictionary:
			steps.append({"text": String(entry.get("text", "")), "count": maxi(int(entry.get("count", 1)), 1)})
	if steps.is_empty():
		push_error("Objective '%s' has no steps" % objective_name)
		return false
	kinds[objective_name] = {
		"name": objective_name,
		"display_name": String(def.get("display_name", objective_name.capitalize())),
		"description": String(def.get("description", "")),
		"steps": steps,
		# Whether it can be given again once it is done - a daily errand can, a story cannot.
		"repeatable": bool(def.get("repeatable", false)),
		"owner": owner,
	}
	return true


func _book(player) -> Dictionary:
	if not (player.data.get(KEY) is Dictionary):
		player.data[KEY] = {"active": {}, "done": {}}
	var book: Dictionary = player.data[KEY]
	if not (book.get("active") is Dictionary):
		book.active = {}
	if not (book.get("done") is Dictionary):
		book.done = {}
	return book


## Gives it to a player. Returns false if they already have it, have finished one that cannot be
## repeated, or are carrying as many as they may.
func give(player, objective_name: String) -> bool:
	var kind: Dictionary = kinds.get(objective_name, {})
	if player == null or kind.is_empty():
		return false
	var book := _book(player)
	if book.active.has(objective_name):
		return false
	if book.done.has(objective_name) and not bool(kind.repeatable):
		return false
	if book.active.size() >= MAX_ACTIVE:
		return false
	book.active[objective_name] = {"step": 0, "progress": 0}
	server.emit("objective_given", {"player": player, "objective": objective_name})
	return true


## Counts `amount` towards the step they are on. When the step is filled it moves on, and when the
## last one is filled the whole thing is done - which is `objective_done`, where a mod hands out
## whatever it thinks the reward is. The engine has no idea what a reward would be.
func advance(player, objective_name: String, amount := 1) -> bool:
	var kind: Dictionary = kinds.get(objective_name, {})
	if player == null or kind.is_empty():
		return false
	var book := _book(player)
	var state = book.active.get(objective_name)
	if not (state is Dictionary):
		return false
	var steps: Array = kind.steps
	state.progress = int(state.progress) + maxi(amount, 1)
	while int(state.step) < steps.size() and int(state.progress) >= int(steps[int(state.step)].count):
		state.progress = int(state.progress) - int(steps[int(state.step)].count)
		state.step = int(state.step) + 1
		if int(state.step) < steps.size():
			server.emit("objective_step", {"player": player, "objective": objective_name,
				"step": int(state.step), "text": String(steps[int(state.step)].text)})
	if int(state.step) >= steps.size():
		book.active.erase(objective_name)
		book.done[objective_name] = int(book.done.get(objective_name, 0)) + 1
		server.emit("objective_done", {"player": player, "objective": objective_name,
			"times": int(book.done[objective_name])})
	return true


## Gives up on one. Kept separate from finishing it, because "I am not doing this" and "I did this"
## are different things and a mod may want to say so.
func abandon(player, objective_name: String) -> bool:
	if player == null:
		return false
	var book := _book(player)
	if not book.active.erase(objective_name):
		return false
	server.emit("objective_abandoned", {"player": player, "objective": objective_name})
	return true


## What they are doing now: [{name, display_name, step, of, text, progress, needed}].
func active_for(player) -> Array:
	if player == null:
		return []
	var out := []
	var book := _book(player)
	for objective_name: String in book.active:
		var kind: Dictionary = kinds.get(objective_name, {})
		if kind.is_empty():
			continue  # a mod that is no longer here; shown as nothing rather than as broken
		var state: Dictionary = book.active[objective_name]
		var step := clampi(int(state.step), 0, (kind.steps as Array).size() - 1)
		out.append({"name": objective_name, "display_name": String(kind.display_name),
			"step": step, "of": (kind.steps as Array).size(), "text": String(kind.steps[step].text),
			"progress": int(state.progress), "needed": int(kind.steps[step].count)})
	return out


func has(player, objective_name: String) -> bool:
	return player != null and _book(player).active.has(objective_name)


## How many times they have finished it (0 if never).
func finished(player, objective_name: String) -> int:
	return int(_book(player).done.get(objective_name, 0)) if player != null else 0
