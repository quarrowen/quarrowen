extends RefCounted
## The label over a thing's head: what it is called, how hurt it is, and anything a mod wants to add.
##
## Players already had one - a name, hardcoded in `remote_player.gd`, with no health and nothing a mod
## could change. Creatures had none at all, and bosses had a `boss` block in their AI config that
## described a bar nobody ever drew.
##
##     api.set_nameplate(mob, {"lines": ["Wants: wheat"], "show_health": true})
##     api.register_entity("cow", {..., "nameplate": {"show_health": true}})
##
## **It rides on `look`.** An entity already has a per-entity, sparse, saved channel for visual state -
## scale, hidden parts, tint - and a nameplate is exactly that kind of fact. Adding a second channel
## would have meant a second thing to sync, save and stream on spawn, all of which `look` does already.
##
## **The client is not told health it cannot see.** A fraction is only sent for something whose plate
## actually shows one, because health changes often and a number nobody draws is a packet nobody needed.
##
## What stays the mod's: whether a creature has a plate at all, what the extra lines say, and when they
## change. The engine knows a name, a fraction and a list of lines.

const ServerPlayer = preload("res://engine/server/server_player.gd")

## Lines a mod may add under the name. Enough for "Wants: wheat" and a mood; few enough that a plate
## cannot become a wall of text over a cow.
const MAX_LINES := 4
const MAX_LINE := 48

var server


func _init(game_server) -> void:
	server = game_server


## The default for an entity type: `nameplate` in its definition, or {} for no plate at all. Creatures
## are quiet by default - a field of forty sheep each wearing a label is worse than no labels.
static func default_for(def: Dictionary) -> Dictionary:
	var n = def.get("nameplate")
	if not (n is Dictionary):
		return {}
	return {"show_health": bool(n.get("show_health", true)),
		"color": String(n.get("color", "#ffffff")),
		"range": clampf(float(n.get("range", 24.0)), 4.0, 96.0)}


## Sets or changes what is over something's head. `spec` merges with whatever is there, so a mod can
## add a line without knowing whether health is being shown.
func set_plate(target, spec := {}) -> bool:
	if target == null:
		return false
	var plate := plate_of(target)
	if spec.get("lines") is Array:
		var lines := []
		for line in (spec.lines as Array).slice(0, MAX_LINES):
			lines.append(String(line).left(MAX_LINE))
		plate["lines"] = lines
	for key in ["show_health", "color", "range", "name"]:
		if spec.has(key):
			plate[key] = spec[key]
	if spec.get("hidden") != null:
		plate["hidden"] = bool(spec.hidden)
	_write(target, plate)
	return true


## What is over its head now, defaults included.
func plate_of(target) -> Dictionary:
	if target == null:
		return {}
	if target.get_script() == ServerPlayer:
		var own = target.data.get("_nameplate")
		return (own as Dictionary).duplicate() if own is Dictionary else {"show_health": false, "name": String(target.name)}
	var look = target.data.get("look")
	var plate = look.get("nameplate") if look is Dictionary else null
	if plate is Dictionary:
		return (plate as Dictionary).duplicate()
	var fallback := default_for(target.def)
	if not fallback.is_empty():
		fallback["name"] = String(target.def.get("display_name", ""))
	return fallback


## Takes it away entirely.
func clear(target) -> bool:
	return set_plate(target, {"hidden": true})


## Called when something's health moves. Only reaches the client for a plate that actually draws it.
func health_changed(target) -> void:
	var plate := plate_of(target)
	if plate.is_empty() or not bool(plate.get("show_health", false)) or bool(plate.get("hidden", false)):
		return
	var maximum := float(target.max_health) if target.get("max_health") != null else 0.0
	var fraction := clampf(float(target.health) / maximum, 0.0, 1.0) if maximum > 0.0 else 1.0
	# Quantised: a health bar is about twenty pixels wide, so sending it to three decimal places is
	# sending a change nobody can see. Every point of damage on a twenty-health mob still moves it.
	var rounded := snappedf(fraction, 0.02)
	if is_equal_approx(float(plate.get("health", -1.0)), rounded):
		return
	plate["health"] = rounded
	_write(target, plate)


func _write(target, plate: Dictionary) -> void:
	if target.get_script() == ServerPlayer:
		target.data["_nameplate"] = plate
		for p: ServerPlayer in server.players.values():
			if p.peer_id != target.peer_id:
				Net.s_player_nameplate.rpc_id(p.peer_id, target.peer_id, plate)
		return
	# Through `look`, which already syncs on change, saves with the entity and is sent on spawn.
	target.set_look({"nameplate": plate})
