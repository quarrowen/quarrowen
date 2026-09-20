extends RefCounted
## Named numbers a player owns: coins, reputation, contribution, experience, a guild's standing.
##
## **This is one capability where the roadmap listed two.** "Balances" and "experience" turned out to
## be the same storage asked a different question: a balance is a number you care about the *value* of,
## and experience is a number you care about the *level* of. Building both would have been building one
## thing twice, so a ledger may be given a table of thresholds and then answers about levels as well.
##
##     api.register_ledger("coins", {"display_name": "Coins"})
##     api.register_ledger("delving", {"display_name": "Delving", "levels": [0, 50, 150, 400]})
##
## The engine stores a number against a player and a name, and **never learns that one of them is
## money**. Whether coins can go negative, what a level unlocks, whether anything unlocks at all: all
## the mod's, and none of it here.
##
## Kept in the player's own saved data, so it travels with them and needs no new file.

const KEY := "_ledgers"
## A number a mod can set. Wide enough for anything a game means and narrow enough that it cannot be
## used to store something that is not a number.
const LIMIT := 1e12

var server

## Name -> {name, display_name, levels, min, max, owner}
var kinds := {}


func _init(game_server) -> void:
	server = game_server


## def: display_name, levels (thresholds, lowest first - the value at which each level begins),
## min and max (what the number may not go past; a balance that may not go negative sets min 0).
func register(ledger_name: String, def: Dictionary, owner := "engine") -> bool:
	if ledger_name.is_empty() or kinds.has(ledger_name):
		push_error("Invalid or duplicate ledger '%s'" % ledger_name)
		return false
	var levels := []
	for entry in (def.get("levels", []) if def.get("levels") is Array else []):
		levels.append(float(entry))
	levels.sort()
	kinds[ledger_name] = {
		"name": ledger_name,
		"display_name": String(def.get("display_name", ledger_name.capitalize())),
		"levels": levels,
		"min": float(def.get("min", -LIMIT)),
		"max": float(def.get("max", LIMIT)),
		"owner": owner,
	}
	return true


func value_of(player, ledger_name: String) -> float:
	if player == null:
		return 0.0
	return float((player.data.get(KEY, {}) as Dictionary).get(ledger_name, 0.0))


## Sets it outright. Returns what it ended up as, which is not always what was asked for - a ledger
## may have a floor or a ceiling, and saying so is more use than refusing.
func set_value(player, ledger_name: String, value: float) -> float:
	var kind: Dictionary = kinds.get(ledger_name, {})
	if player == null or kind.is_empty():
		return 0.0
	var was := value_of(player, ledger_name)
	var now := clampf(value, float(kind.min), float(kind.max))
	if is_equal_approx(was, now):
		return now
	if not (player.data.get(KEY) is Dictionary):
		player.data[KEY] = {}
	player.data[KEY][ledger_name] = now
	var was_level := level_for(ledger_name, was)
	var now_level := level_for(ledger_name, now)
	server.emit("ledger_changed", {"player": player, "ledger": ledger_name, "was": was, "value": now,
		"level": now_level, "levelled": now_level != was_level})
	return now


## Adds to it (a negative amount spends). Returns what it ended up as.
func add(player, ledger_name: String, amount: float) -> float:
	return set_value(player, ledger_name, value_of(player, ledger_name) + amount)


## Takes `amount` only if there is that much, so a shop can be written without a check and a race
## between the check and the spend. Returns false and changes nothing when there is not enough.
func spend(player, ledger_name: String, amount: float) -> bool:
	if amount <= 0.0 or value_of(player, ledger_name) < amount:
		return false
	add(player, ledger_name, -amount)
	return true


## What level a value is at: 0 below the first threshold, 1 at it, and so on.
func level_for(ledger_name: String, value: float) -> int:
	var levels: Array = kinds.get(ledger_name, {}).get("levels", [])
	var level := 0
	for threshold in levels:
		if value >= float(threshold):
			level += 1
		else:
			break
	return level


func level_of(player, ledger_name: String) -> int:
	return level_for(ledger_name, value_of(player, ledger_name))


## How far through the current level, 0 to 1, and what is left to the next. {level, value, into, needed,
## next}, with `next` -1 at the top. For a bar on the screen, which is the usual reason to ask.
func progress_of(player, ledger_name: String) -> Dictionary:
	var levels: Array = kinds.get(ledger_name, {}).get("levels", [])
	var value := value_of(player, ledger_name)
	var level := level_for(ledger_name, value)
	if levels.is_empty():
		return {"level": 0, "value": value, "into": 0.0, "needed": 0.0, "next": -1.0}
	var floor_at := float(levels[level - 1]) if level > 0 else 0.0
	if level >= levels.size():
		return {"level": level, "value": value, "into": 1.0, "needed": 0.0, "next": -1.0}
	var next := float(levels[level])
	var span := maxf(next - floor_at, 0.0001)
	return {"level": level, "value": value, "into": clampf((value - floor_at) / span, 0.0, 1.0),
		"needed": maxf(next - value, 0.0), "next": next}


## Everything a player has, for a scoreboard or a screen: [{name, display_name, value, level}].
func all_of(player) -> Array:
	var out := []
	for ledger_name: String in kinds:
		var value := value_of(player, ledger_name)
		if is_zero_approx(value):
			continue
		out.append({"name": ledger_name, "display_name": String(kinds[ledger_name].display_name),
			"value": value, "level": level_for(ledger_name, value)})
	return out
