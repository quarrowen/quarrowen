extends RefCounted
## Something a player or a creature is temporarily *under*: swiftness, poison, a well-fed glow, the
## shakes after a fright.
##
## **Called conditions rather than effects** because `effect_registry.gd` already means particles here,
## and two things with one name in one engine is how somebody ends up reading the wrong file at
## midnight - the same reason plots are not called claims.
##
##     api.register_condition("swiftness", {"display_name": "Swiftness", "color": "#7fd6ff",
##         "modifiers": [{"stat": "move_speed", "amount": 0.2, "op": "multiply"}], "max_level": 3})
##
##     api.register_condition("poison", {"display_name": "Poison", "color": "#89c24a", "good": false,
##         "tick": {"seconds": 1.5, "damage": 1.0, "cause": "poison"}})
##
##     api.give_condition(player, "swiftness", {"seconds": 30.0, "level": 2})
##
## **The tick is the part food could not express.** A timed stat modifier already existed
## (`player.add_modifier`), and it covers swiftness perfectly well; what it cannot say is "one damage
## every second and a half for twenty seconds", which is what poison, regeneration and burning all are.
## So a condition is a stat change, or a repeating thing, or both.
##
## **Levels multiply, they do not re-describe.** Swiftness II is the same modifiers doubled, because a
## mod that wants two genuinely different things can register two conditions, and a table of per-level
## overrides would be a small language nobody asked for.
##
## What stays the mod's: what conditions exist, what brews or cures them, what a level means in the
## fiction, and whether drinking two makes you ill.

const ServerPlayer = preload("res://engine/server/server_player.gd")

const KEY := "_conditions"
## Per target. Enough for a stacked-up potion cupboard, few enough that the panel is readable.
const MAX_HELD := 16
const MAX_LEVEL := 10
## How a second helping of the same thing is treated.
const STACKS := ["strongest", "refresh", "extend"]

var server

## Name -> {name, display_name, color, good, max_level, modifiers, tick, particle, stacks, owner}
var kinds := {}
## Targets holding at least one condition, so the tick walks those rather than every entity alive.
var _active := []


func _init(game_server) -> void:
	server = game_server


func register(condition_name: String, def: Dictionary, owner := "engine") -> bool:
	if condition_name.is_empty() or kinds.has(condition_name):
		push_error("Invalid or duplicate condition '%s'" % condition_name)
		return false
	var modifiers := []
	for entry in (def.get("modifiers", []) if def.get("modifiers") is Array else []):
		if entry is Dictionary and entry.get("stat") is String:
			modifiers.append({"stat": String(entry.stat), "amount": float(entry.get("amount", 0.0)),
				"op": "multiply" if entry.get("op") == "multiply" else "add"})
	var tick := {}
	var source = def.get("tick")
	if source is Dictionary:
		tick = {"seconds": maxf(float(source.get("seconds", 1.0)), 0.05),
			"damage": maxf(float(source.get("damage", 0.0)), 0.0),
			"heal": maxf(float(source.get("heal", 0.0)), 0.0),
			"cause": String(source.get("cause", condition_name.get_slice(":", 1)))}
	if modifiers.is_empty() and tick.is_empty():
		push_error("Condition '%s' neither changes a stat nor does anything on a timer" % condition_name)
		return false
	var stacks := String(def.get("stacks", "strongest"))
	kinds[condition_name] = {"name": condition_name, "owner": owner,
		"display_name": String(def.get("display_name", condition_name.get_slice(":", 1).capitalize())),
		"color": String(def.get("color", "#ffffff")),
		# Whether this is something to be pleased about, which is all the engine needs to know to let a
		# mod write one cure for everything bad without listing them.
		"good": bool(def.get("good", true)),
		"max_level": clampi(int(def.get("max_level", 1)), 1, MAX_LEVEL),
		"modifiers": modifiers, "tick": tick,
		"particle": String(def.get("particle", "")),
		"stacks": stacks if STACKS.has(stacks) else "strongest"}
	return true


## Everything a target is under. One accessor for players and creatures alike, because both carry a
## `data` dictionary that is saved with them and neither needed anywhere new to put this.
func _book(target) -> Dictionary:
	if not (target.data.get(KEY) is Dictionary):
		target.data[KEY] = {}
	return target.data[KEY]


## Gives one. `seconds` 0 means until it is taken away. Returns false when the target already has
## something stronger and the condition does not stack.
func give(target, condition_name: String, options := {}) -> bool:
	var kind: Dictionary = kinds.get(condition_name, {})
	if target == null or kind.is_empty():
		return false
	var book := _book(target)
	if book.size() >= MAX_HELD and not book.has(condition_name):
		return false
	var level := clampi(int(options.get("level", 1)), 1, int(kind.max_level))
	var seconds := maxf(float(options.get("seconds", 0.0)), 0.0)
	var now: float = server._time
	var held = book.get(condition_name)
	if held is Dictionary:
		match String(kind.stacks):
			"extend":
				# Two short helpings become one long one, which is what a second cup of something ought
				# to feel like.
				var left := maxf(float(held.expires) - now, 0.0) if float(held.expires) > 0.0 else 0.0
				seconds = 0.0 if seconds <= 0.0 or float(held.expires) <= 0.0 else left + seconds
				level = maxi(level, int(held.level))
			"refresh":
				level = maxi(level, int(held.level))
			_:
				# "strongest": a weaker helping never cuts short a stronger one, and at equal strength
				# the longer of the two wins.
				if int(held.level) > level:
					return false
				if int(held.level) == level:
					if float(held.expires) <= 0.0:
						return false  # nothing improves on one that does not run out
					if seconds > 0.0 and now + seconds <= float(held.expires):
						return false
	book[condition_name] = {"level": level, "expires": now + seconds if seconds > 0.0 else 0.0,
		"next_tick": now + float(kind.tick.get("seconds", 0.0)) if not (kind.tick as Dictionary).is_empty() else 0.0}
	_apply_modifiers(target, condition_name, kind, level, seconds)
	if not _active.has(target):
		_active.append(target)
	server.emit("condition_given", {"target": target, "condition": condition_name, "level": level,
		"seconds": seconds, "good": bool(kind.good)})
	return true


## Stat changes go through the modifier machinery that already exists rather than a second one beside
## it. The id is ours so that clearing a condition cannot take away a modifier somebody else added.
func _apply_modifiers(target, condition_name: String, kind: Dictionary, level: int, seconds: float) -> void:
	if not _is_player(target):
		return  # creatures have no stat table yet; their conditions are the ticking sort
	for i in (kind.modifiers as Array).size():
		var m: Dictionary = kind.modifiers[i]
		target.add_modifier("condition:%s:%d" % [condition_name, i], String(m.stat),
			float(m.amount) * level, String(m.op), seconds)


func _remove_modifiers(target, condition_name: String) -> void:
	var kind: Dictionary = kinds.get(condition_name, {})
	if kind.is_empty() or not _is_player(target):
		return
	for i in (kind.modifiers as Array).size():
		target.remove_modifier("condition:%s:%d" % [condition_name, i])


func clear(target, condition_name: String) -> bool:
	if target == null:
		return false
	var book := _book(target)
	if not book.has(condition_name):
		return false
	book.erase(condition_name)
	_remove_modifiers(target, condition_name)
	if book.is_empty():
		_active.erase(target)
	server.emit("condition_cleared", {"target": target, "condition": condition_name})
	return true


## Takes away everything, or with `only_bad` everything unpleasant - which is the whole of what a cure
## is, and means a mod can write one without listing every affliction in the game.
func clear_all(target, only_bad := false) -> int:
	if target == null:
		return 0
	var gone := 0
	for condition_name: String in (_book(target).keys() as Array):
		if only_bad and bool(kinds.get(condition_name, {}).get("good", true)):
			continue
		if clear(target, condition_name):
			gone += 1
	return gone


func has(target, condition_name: String) -> bool:
	return target != null and _book(target).has(condition_name)


func level_of(target, condition_name: String) -> int:
	return int(_book(target).get(condition_name, {}).get("level", 0)) if target != null else 0


## What they are under, for a panel or a command: [{name, display_name, color, level, good, seconds}],
## where `seconds` is -1 for one that does not run out.
func of_target(target) -> Array:
	if target == null:
		return []
	var out := []
	var now: float = server._time
	for condition_name: String in _book(target):
		var kind: Dictionary = kinds.get(condition_name, {})
		if kind.is_empty():
			continue  # a mod that is no longer here: shown as nothing rather than as broken
		var held: Dictionary = _book(target)[condition_name]
		out.append({"name": condition_name, "display_name": String(kind.display_name),
			"color": String(kind.color), "level": int(held.level), "good": bool(kind.good),
			"seconds": maxf(float(held.expires) - now, 0.0) if float(held.expires) > 0.0 else -1.0})
	return out


## Expiry and the repeating half. Walks only what is holding something, so a world of four thousand
## creatures costs nothing until one of them is actually poisoned.
func tick(_delta: float) -> void:
	if _active.is_empty():
		return
	var now: float = server._time
	# Backwards: a target can be removed from the list inside the loop, by its last condition running
	# out or by dying of one.
	for i in range(_active.size() - 1, -1, -1):
		var target = _active[i]
		if not is_instance_valid(target) or not _alive(target):
			_active.remove_at(i)
			continue
		for condition_name: String in (_book(target).keys() as Array):
			var kind: Dictionary = kinds.get(condition_name, {})
			var held = _book(target).get(condition_name)
			if kind.is_empty() or not (held is Dictionary):
				continue
			if float(held.expires) > 0.0 and now >= float(held.expires):
				clear(target, condition_name)
				server.emit("condition_expired", {"target": target, "condition": condition_name})
				continue
			if (kind.tick as Dictionary).is_empty() or now < float(held.next_tick):
				continue
			held.next_tick = now + float(kind.tick.seconds)
			_do_tick(target, kind, int(held.level))


func _do_tick(target, kind: Dictionary, level: int) -> void:
	var tick: Dictionary = kind.tick
	var player := _is_player(target)
	if float(tick.heal) > 0.0:
		target.heal(float(tick.heal) * level)
	if float(tick.damage) > 0.0:
		var amount := float(tick.damage) * level
		# Told apart rather than duck-typed: both have damage(), and they take their arguments in the
		# *opposite* order - ServerPlayer.damage(amount, cause, attacker) against
		# Entity.damage(amount, attacker, cause). Calling the wrong one files the cause as the attacker
		# and loses the death message, silently.
		if player:
			# Through the server so armour, the death message and everything watching player_damaged
			# behave exactly as they do for any other hurt.
			server.damage_player(target, amount, String(tick.cause), null, Vector3.ZERO, true)
		else:
			target.damage(amount, null, String(tick.cause))


static func _is_player(target) -> bool:
	return target != null and target.get_script() == ServerPlayer


static func _alive(target) -> bool:
	return float(target.health) > 0.0 if target.get("health") != null else true


## Puts a target back on the ticking list after a load: conditions live in saved data, so somebody who
## logs out poisoned logs back in poisoned.
func resume(target) -> void:
	if target != null and not _book(target).is_empty() and not _active.has(target):
		_active.append(target)
		for condition_name: String in _book(target):
			var kind: Dictionary = kinds.get(condition_name, {})
			if kind.is_empty():
				continue
			var held: Dictionary = _book(target)[condition_name]
			# Timers are stored as server time, which starts again from zero: a saved expiry would
			# otherwise be in the past and everything would drop off on the first tick.
			if float(held.expires) > 0.0:
				held.expires = server._time + float(held.get("left", 0.0))
			held.next_tick = server._time + float(kind.tick.get("seconds", 0.0)) if not (kind.tick as Dictionary).is_empty() else 0.0
			_apply_modifiers(target, condition_name, kind, int(held.level),
				maxf(float(held.expires) - server._time, 0.0) if float(held.expires) > 0.0 else 0.0)


## Writes how long is *left* rather than when it expires, because server time restarts with the server
## and an absolute expiry means nothing on the other side of a save.
func before_save(target) -> void:
	if target == null:
		return
	for condition_name: String in _book(target):
		var held: Dictionary = _book(target)[condition_name]
		held["left"] = maxf(float(held.expires) - server._time, 0.0) if float(held.expires) > 0.0 else 0.0


func forget(target) -> void:
	_active.erase(target)
