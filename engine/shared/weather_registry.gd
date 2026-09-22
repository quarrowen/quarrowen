extends RefCounted
## Weather: rain, snow, a storm, whatever a mod decides weather is.
##
## The engine knows that *some* weather is happening and how hard, and how to draw and sync it. It does
## not know what rain is. A mod registers what its weather looks like, using the same emitter vocabulary
## as effects, and decides when it happens:
##
##     api.register_weather("rain", {
##         "emitter": {"amount": 220, "lifetime": 1.1, "speed": [16, 20], "direction": [0, -1, 0],
##             "spread": 3, "size": [0.05, 0.05], "colors": ["#9fc4e8aa"], "shape": "box",
##             "extents": [18, 1, 18]},
##         "sound": "rain", "sky_tint": "#6a7686", "light_scale": 0.72})
##
##     api.set_weather("rain", {"intensity": 0.8, "seconds": 300})
##
## Why the engine at all, when a mod could spawn particles itself: weather is *world state*. Everybody
## standing in the same place sees the same storm, somebody joining halfway through arrives in it, and a
## block or a creature can ask what the weather is. Particles a mod fired at each player would be none of
## those things - and every mod that wanted weather would invent its own answer to all of them.
##
## Deliberately not here: when it rains. A mod decides that, and different games want wildly different
## answers - a survival world on a random timer, a story where the storm arrives when the story says so.

const EffectRegistry = preload("res://engine/shared/effect_registry.gd")

const MAX_WEATHERS := 64
const NETWORK_FIELDS := ["name", "emitter", "sound", "sky_tint", "light_scale", "fog"]

var defs: Array[Dictionary] = []
var ids := {}  # name -> id


## def: name, emitter (as an effect emitter), sound (looped while it falls), sky_tint ("#rrggbb"),
## light_scale (0-1, how far it darkens the world), fog (0-1). Returns the id, or -1.
func register(def: Dictionary) -> int:
	var weather_name := String(def.get("name", ""))
	if weather_name.is_empty() or ids.has(weather_name) or defs.size() >= MAX_WEATHERS:
		push_error("Invalid or duplicate weather '%s'" % weather_name)
		return -1
	var d := {
		"name": weather_name,
		# Read through the effect registry's own reader, so an emitter written for weather is subject to
		# exactly the same defaults and limits as one written for an effect. Weather filled the dictionary
		# itself at first and the client then asked it for a key it did not have. (2026-09-19)
		"emitter": EffectRegistry.emitter(def.emitter) if def.get("emitter") is Dictionary else {},
		"sound": String(def.get("sound", "")),
		"sky_tint": String(def.get("sky_tint", "")),
		# Clamped rather than trusted: a mod that darkens the world to nothing has made the game
		# unplayable for everybody on the server, and it is the sort of thing that gets typed by
		# accident.
		"light_scale": clampf(float(def.get("light_scale", 1.0)), 0.25, 1.0),
		"fog": clampf(float(def.get("fog", 0.0)), 0.0, 1.0),
	}
	ids[weather_name] = defs.size()
	defs.append(d)
	return defs.size() - 1


## The id registered under this name, or **-1 if nothing is**.
##
## -1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
## and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
## reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
## only after checking it, or use the `require_*` form at the API boundary.
func id_of(weather_name: String) -> int:
	return int(ids.get(weather_name, -1))


## Whether anything is registered under this id.
func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


## The weather table as the client receives it.
func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


## Rebuilds the table on the client. False when the data is malformed.
func load_network(list) -> bool:
	defs.clear()
	ids.clear()
	if not (list is Array):
		return true  # a server with no weather is not an error
	for entry in (list as Array).slice(0, MAX_WEATHERS):
		if not (entry is Dictionary):
			return false
		if register(entry) < 0:
			return false
	return true
