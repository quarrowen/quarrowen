extends RefCounted
## Atmosphere: the occasional sound that tells you where you are. Wind above ground, water lapping near
## a lake, a drip somewhere in the dark.
##
## This is in the engine and not in a mod for the same reason charging is. A mod *could* do it with a
## timer and a list of players, and every mod that wanted weather or caves would then write its own
## version of the same four decisions - how often is too often, how far away can it be, does a second
## player hear it, what happens when somebody is asleep - and none of them would agree. What a mod
## actually wants to say is "wind, out in the open, every half minute or so", and that is what this
## takes.
##
## A mod registers conditions and the engine picks the moments:
##
##     api.register_ambience("wind", {"sound": "wind", "sky": true, "every": [20.0, 45.0]})
##     api.register_ambience("drip", {"sound": "drip", "sky": false, "depth": [0, 45],
##         "every": [8.0, 25.0], "volume": 0.7})
##     api.register_ambience("lapping", {"sound": "water", "near": ["base:water"], "radius": 6,
##         "every": [10.0, 20.0]})
##
## Each entry keeps its own clock **per player**, so two people in different places hear their own
## surroundings rather than each other's, and the sound is sent only to the player it is for: this is
## atmosphere, not an event in the world that others should hear.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")

## What a mod may ask for. An unknown key is a mistake worth reporting rather than ignoring, the same
## way an unknown loot condition is.
const KNOWN := ["sound", "every", "volume", "pitch", "biome", "depth", "sky", "near", "radius", "chance"]

var entries: Array[Dictionary] = []

var _server
var _next := {}  # peer_id -> {entry index -> seconds until the next roll}


func _init(game_server) -> void:
	_server = game_server


## Returns "" or why it was refused.
func register(def: Dictionary) -> String:
	for key in def:
		if not (key in KNOWN):
			return "unknown ambience setting '%s' (known: %s)" % [key, ", ".join(KNOWN)]
	var sound := String(def.get("sound", ""))
	if sound.is_empty():
		return "an ambience needs a sound"
	var every = def.get("every", [15.0, 40.0])
	if not (every is Array and every.size() == 2):
		return "'every' is [minimum seconds, maximum seconds]"
	var entry := {
		"sound": sound,
		"every": [maxf(float(every[0]), 1.0), maxf(float(every[1]), 1.0)],
		"volume": clampf(float(def.get("volume", 1.0)), 0.0, 2.0),
		"pitch": clampf(float(def.get("pitch", 1.0)), 0.25, 4.0),
		"biome": def.get("biome", null),
		"depth": def.get("depth", null),
		"sky": def.get("sky", null),
		"near": def.get("near", null),
		"radius": clampi(int(def.get("radius", 8)), 1, 32),
		"chance": clampf(float(def.get("chance", 1.0)), 0.0, 1.0),
	}
	entries.append(entry)
	return ""


func player_left(peer_id: int) -> void:
	_next.erase(peer_id)


func update(delta: float) -> void:
	if entries.is_empty():
		return
	for p in _server.players.values():
		# Dead players get silence; offline ones still keep their clocks ticking, because whether the
		# socket is up is _play's business and not a reason to lose where somebody was.
		if p == null or p.dead:
			continue
		var clocks: Dictionary = _next.get(p.peer_id, {})
		if clocks.is_empty():
			_next[p.peer_id] = clocks
		for i in entries.size():
			var entry: Dictionary = entries[i]
			if not clocks.has(i):
				clocks[i] = _reset(entry)  # stagger the first one, so a join is not a chorus
				continue
			clocks[i] = float(clocks[i]) - delta
			if clocks[i] > 0.0:
				continue
			clocks[i] = _reset(entry)
			if randf() > float(entry.chance):
				continue
			var at := _where(p, entry)
			if at != Vector3.INF:
				_play(p, entry, at)


func _reset(entry: Dictionary) -> float:
	var every: Array = entry.every
	return randf_range(float(every[0]), float(every[1]))


## Where this ambience should come from for this player, or Vector3.INF if its conditions do not hold.
func _where(p, entry: Dictionary) -> Vector3:
	var into = _server.realm_of(p)  # what they can hear is what is around them, in their own world
	var feet: Vector3 = p.state.position
	var cell := Vector3i(feet.floor())
	if entry.depth is Array and (entry.depth as Array).size() == 2:
		if cell.y < int(entry.depth[0]) or cell.y > int(entry.depth[1]):
			return Vector3.INF
	if entry.sky != null and bool(entry.sky) != _sees_sky(cell, into):
		return Vector3.INF
	if entry.biome != null and _server.biome_generator != null:
		var here: String = _server.biome_generator.biome_at(cell.x, cell.z)
		var want = entry.biome
		var ok: bool = (want is Array and (want as Array).map(func(b): return str(b)).has(here)) or str(want) == here
		if not ok:
			return Vector3.INF
	# `near` means "and it comes from over there": find the block it is about, so water laps from the
	# water rather than from inside the listener's head.
	if entry.near != null:
		return _find_near(cell, entry, into)
	# Otherwise somewhere close by, off to one side, so it is not dead centre every time.
	var angle := randf() * TAU
	var distance := randf_range(2.0, float(entry.radius))
	return feet + Vector3(cos(angle) * distance, randf_range(0.0, 2.0), sin(angle) * distance)


## Whether there is open air above: nothing solid between here and the top of the world. Cheap, and it
## is the honest answer to "am I outside", which is what a mod means by `sky`.
func _sees_sky(cell: Vector3i, into = null) -> bool:
	var registry = _server.registry
	for y in range(cell.y + 2, mini(cell.y + 40, 255)):
		var block: int = (into if into != null else _server.realm).world.get_block(cell.x, y, cell.z)
		if block == BlockRegistry.UNLOADED:
			return true
		if registry.is_valid(block) and registry.solid_lut[block] == 1:
			return false
	return true


## A block of the wanted kind within `radius`, or Vector3.INF, picked uniformly among all of them.
##
## A full sweep rather than a handful of random probes. Probing was the first attempt and it was wrong:
## a small pond is a few dozen cells in a box of well over a thousand, so two dozen guesses found it
## less than half the time and the water beside you was silent for no reason you could see. The sweep
## costs about fifteen hundred array lookups, and it runs once per ambience per player per interval -
## which is once every ten or twenty seconds, not once a frame.
func _find_near(cell: Vector3i, entry: Dictionary, into = null) -> Vector3:
	var in_world = (into if into != null else _server.realm).world
	var wanted := {}
	for name in (entry.near if entry.near is Array else [entry.near]):
		var id: int = _server.registry.id_of(str(name))
		if id > 0:
			wanted[id] = true
	if wanted.is_empty():
		return Vector3.INF
	var radius: int = entry.radius
	var vertical: int = maxi(radius / 2, 2)
	# Reservoir sampling: one pass, one candidate kept, every match equally likely, no list to build.
	var found := Vector3i.ZERO
	var seen := 0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			for dy in range(-vertical, vertical + 1):
				var at := cell + Vector3i(dx, dy, dz)
				if wanted.has(in_world.get_block_v(at)):
					seen += 1
					if randi() % seen == 0:
						found = at
	return Vector3(found) + Vector3(0.5, 0.5, 0.5) if seen > 0 else Vector3.INF


## To this player only. Ambience is where *you* are; somebody across the valley has their own.
func _play(p, entry: Dictionary, at: Vector3) -> void:
	var id: int = _server.sounds.id_of(String(entry.sound))
	if id < 0 or not p._online():
		return
	Net.s_sound.rpc_id(p.peer_id, id, at, float(entry.volume), float(entry.pitch), true)
