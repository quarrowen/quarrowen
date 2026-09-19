extends RefCounted
## Blocks that change over time, and an approximate server-side light level.
##
## Random ticks: mods register a handler per block type with an average interval; each block of that
## type *close enough to a player to be simulated* is called at random about that often. The engine
## indexes tickable blocks per chunk, so only they are visited.
## Scheduled ticks: `schedule(pos, seconds, payload)` calls the block's handler once at that time (also
## after unloads and restarts, since they are saved with the chunk).
## Handler: Callable(ctx) with ctx = {position, block, state, ticks, reason: "random" | "scheduled",
## payload, elapsed}.
##
## **Chunks that are not being run keep time rather than losing it.** A chunk goes to sleep when it is
## unloaded, and now also when the last player walks out of simulation range of it; the clock carries
## on, and when it wakes each block is given the ticks it missed in one call (`ticks` > 1, and
## `elapsed` seconds), so crops keep growing while nobody is near. The number of ticks is capped at
## MAX_CATCH_UP on purpose: returning to a world after a week must not simulate a week in one frame.
## A mod that wants the true figure reads `elapsed`, which is not capped.
##
## Light (0-15) is estimated from column heights (sky) and nearby light-emitting blocks (block light)
## without occlusion, which is close enough for growth and spawning rules. Clients compute real light.

const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

const STEP := 0.5  # seconds between random tick rounds
const MAX_CATCH_UP := 64  # ticks handed to one block after an unload
const SKY_SEARCH := 6  # columns searched sideways for open sky
const LIGHT_RANGE := 15

var server
## The world these blocks are in. Everything here is indexed by chunk coordinate, and every realm has
## a chunk (0, 0), so the table has to belong to one world rather than to the server.
var realm
## Seconds of simulated world time (persists across restarts).
var clock := 0.0
## Block id -> {handler, interval, catch_up}.
var handlers := {}

var _positions := {}  # Vector2i chunk -> {local index: block id} for tickable blocks
var _lights := {}  # Vector2i chunk -> {local index: light level}
var _scheduled := {}  # Vector2i chunk -> {local index: [due clock, payload]}
const UNKNOWN_HEIGHT := -2
var _heights := {}  # Vector2i chunk -> PackedInt32Array(256) highest opaque y per column (-1 open)
var _pending: Array = []  # [position, ticks, elapsed] catch-up calls to make on the next round
## Chunks that are loaded but not being run, and the clock reading from when they stopped. A chunk is
## in exactly one of this and `_awake`.
var _asleep_since := {}  # Vector2i chunk -> clock
var _awake := {}  # Vector2i chunk -> true
var _timer := 0.0


func _init(game_server, in_realm) -> void:
	server = game_server
	realm = in_realm


func register(block: int, handler: Callable, options := {}, owner := "engine") -> void:
	handlers[block] = {"handler": handler, "owner": owner, "interval": clampf(float(options.get("interval", 30.0)), STEP, 86400.0),
		"catch_up": bool(options.get("catch_up", true))}


## Calls the handler of the block at `pos` after `seconds` (reason "scheduled"). One per position; a
## new schedule replaces the old one.
func schedule(pos: Vector3i, seconds: float, payload := {}) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	if pos.y < 0 or pos.y >= Chunk.SIZE_Y or not realm.world.chunks.has(coord):
		return
	if not _scheduled.has(coord):
		_scheduled[coord] = {}
	_scheduled[coord][Chunk.index(pos.x & 15, pos.y, pos.z & 15)] = [clock + maxf(seconds, 0.0), payload]


## Worker thread: local indices of the given block ids in a chunk's block array.
static func scan(blocks: PackedByteArray, ids: PackedInt32Array) -> Dictionary:
	var out := {}
	for id in ids:
		var low := id & 255
		var from := 0
		while true:
			var at := blocks.find(low, from)
			if at < 0:
				break
			from = at + 1
			if at % 2 == 0 and blocks.decode_u16(at) == id:
				out[at >> 1] = id
	return out


## Block ids the chunk jobs should index: [tickable ids, light-emitting ids].
func scan_ids() -> Array:
	var lights := PackedInt32Array()
	for d in server.registry.defs:
		if d.light > 0:
			lights.append(d.id)
	return [PackedInt32Array(handlers.keys()), lights]


func load_chunk(coord: Vector2i, tickable: Dictionary, lights: Dictionary, saved) -> void:
	if not tickable.is_empty():
		_positions[coord] = tickable
	if not lights.is_empty():
		var levels := {}
		for index in lights:
			levels[index] = server.registry.defs[lights[index]].light
		_lights[coord] = levels
	# A chunk arrives asleep and is caught up when a player comes near enough to run it - not here.
	# Loading used to do the catching up itself, which meant a chunk streamed to somebody standing at
	# the far edge of their view did a whole night of growth for nobody.
	_asleep_since[coord] = clock
	if not (saved is Dictionary):
		return
	var scheduled := {}
	var entries = saved.get("scheduled", {})
	if entries is Dictionary:
		for key in entries:
			if entries[key] is Array and entries[key].size() == 2:
				scheduled[int(key)] = [float(entries[key][0]), entries[key][1] if entries[key][1] is Dictionary else {}]
	if not scheduled.is_empty():
		_scheduled[coord] = scheduled
	_asleep_since[coord] = float(saved.get("at", clock))


## What to save with a chunk (null when nothing).
func save_chunk(coord: Vector2i):
	if not _positions.has(coord) and not _scheduled.has(coord):
		return null
	var scheduled := {}
	for index: int in _scheduled.get(coord, {}):
		scheduled[str(index)] = _scheduled[coord][index]
	return {"at": clock, "scheduled": scheduled}


## Chunks whose tick state must be saved.
func ticking_chunks() -> Array:
	var out := _positions.keys()
	for coord in _scheduled:
		if not _positions.has(coord):
			out.append(coord)
	return out


func unload_chunk(coord: Vector2i) -> void:
	_positions.erase(coord)
	_lights.erase(coord)
	_scheduled.erase(coord)
	_heights.erase(coord)
	_asleep_since.erase(coord)
	_awake.erase(coord)


func block_changed(pos: Vector3i, old: int, block: int) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var index := Chunk.index(pos.x & 15, pos.y, pos.z & 15)
	var heights: PackedInt32Array = _heights.get(coord, PackedInt32Array())
	if not heights.is_empty():
		# Keep the column's height current instead of rescanning the chunk.
		var column := (pos.x & 15) + (pos.z & 15) * 16
		if server.registry.opaque_lut[block] == 1:
			if heights[column] != UNKNOWN_HEIGHT and pos.y > heights[column]:
				heights[column] = pos.y
		elif pos.y >= heights[column]:
			heights[column] = UNKNOWN_HEIGHT
		_heights[coord] = heights
	if handlers.has(old):
		_positions.get(coord, {}).erase(index)
	if handlers.has(block):
		if not _positions.has(coord):
			_positions[coord] = {}
		_positions[coord][index] = block
	if old != block:
		_scheduled.get(coord, {}).erase(index)
	var level: int = server.registry.defs[block].light if server.registry.is_valid(block) else 0
	if level > 0:
		if not _lights.has(coord):
			_lights[coord] = {}
		_lights[coord][index] = level
	elif _lights.has(coord):
		_lights[coord].erase(index)


## `simulated` is the set of chunk coordinates close enough to somebody to be run; everything else
## that is loaded is left alone. The clock advances either way, so a chunk that comes back is told how
## long it was asleep rather than losing the time.
func update(delta: float, simulated: Dictionary) -> void:
	clock += delta
	_timer += delta
	if _timer < STEP:
		return
	var step := _timer
	_timer = 0.0
	_follow_simulation(simulated)
	var pending := _pending
	_pending = []
	for entry in pending:
		_call(entry[0], entry[1], "random", {}, entry[2])
	for coord: Vector2i in _positions.keys():
		if not simulated.has(coord):
			continue
		var entries: Dictionary = _positions.get(coord, {})
		var origin := Vector3i(coord.x * 16, 0, coord.y * 16)
		for index: int in entries.keys():
			var h: Dictionary = handlers.get(entries.get(index, -1), {})
			if not h.is_empty() and randf() < step / h.interval:
				_call(origin + _local(index), 1, "random", {})
	for coord: Vector2i in _scheduled.keys():
		# A scheduled tick in a sleeping chunk is not lost, only late: the clock is past its due time
		# already, so it fires on the round after somebody comes back.
		if not simulated.has(coord):
			continue
		var entries: Dictionary = _scheduled.get(coord, {})
		var origin := Vector3i(coord.x * 16, 0, coord.y * 16)
		for index: int in entries.keys():
			var entry: Array = entries[index]
			if clock >= float(entry[0]):
				entries.erase(index)
				_call(origin + _local(index), 1, "scheduled", entry[1])


## Moves chunks between awake and asleep, and hands the ones that just woke the time they missed.
func _follow_simulation(simulated: Dictionary) -> void:
	for coord: Vector2i in _awake.keys():
		if not simulated.has(coord):
			_awake.erase(coord)
			_asleep_since[coord] = clock
	for coord: Vector2i in simulated:
		if _awake.has(coord) or not _asleep_since.has(coord):
			continue
		_awake[coord] = true
		_catch_up(coord, clock - float(_asleep_since[coord]))
		_asleep_since.erase(coord)


## Tells every catching-up block in a chunk how long it has been standing still. The number of ticks
## is capped, deliberately: coming back to a world after a week must not run a week of growth in one
## frame. `elapsed` is uncapped alongside it, so a mod that wants to work out the real answer can.
func _catch_up(coord: Vector2i, elapsed: float) -> void:
	if elapsed <= STEP or not _positions.has(coord):
		return
	var origin := Vector3i(coord.x * 16, 0, coord.y * 16)
	for index: int in _positions[coord]:
		var h: Dictionary = handlers.get(_positions[coord][index], {})
		if h.is_empty() or not h.catch_up:
			continue
		var ticks := mini(floori(elapsed / h.interval + randf()), MAX_CATCH_UP)
		if ticks > 0:
			_pending.append([origin + _local(index), ticks, elapsed])


func _call(pos: Vector3i, ticks: int, reason: String, payload: Dictionary, elapsed := 0.0) -> void:
	var block: int = realm.world.get_block_v(pos)
	var h: Dictionary = handlers.get(block, {})
	if h.is_empty() or not h.handler.is_valid():
		return
	var t := Time.get_ticks_usec()
	h.handler.call({"position": pos, "block": block, "state": realm.block_state(pos), "ticks": ticks,
		"reason": reason, "payload": payload, "elapsed": elapsed})
	server.dev_tools.record(h.owner, "block_tick:" + server.registry.defs[block].name, Time.get_ticks_usec() - t)


# --- Light --------------------------------------------------------------------------------------

## {sky, block} light levels (0-15) at a position; sky is not scaled by the time of day.
func light_levels(pos: Vector3i) -> Dictionary:
	return {"sky": sky_light(pos), "block": block_light(pos)}


## Light plants and mobs care about: block light or daylight-scaled sky light, whichever is brighter.
func light_at(pos: Vector3i, daylight: float) -> int:
	return maxi(block_light(pos), roundi(sky_light(pos) * daylight))


func sky_light(pos: Vector3i) -> int:
	if pos.y >= Chunk.SIZE_Y:
		return 15
	if _column_height(pos.x, pos.z) < pos.y:
		return 15
	# Light spills sideways from nearby open columns (cave mouths, overhangs), one level per block.
	for r in range(1, SKY_SEARCH + 1):
		for dx in range(-r, r + 1):
			var dz := r - absi(dx)
			for sz in ([dz, -dz] if dz != 0 else [0]):
				if _column_height(pos.x + dx, pos.z + sz) < pos.y:
					return 15 - r
	return 0


func block_light(pos: Vector3i) -> int:
	var best := 0
	var center := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	for cx in range(-1, 2):
		for cz in range(-1, 2):
			var coord := center + Vector2i(cx, cz)
			var levels: Dictionary = _lights.get(coord, {})
			if levels.is_empty():
				continue
			var origin := Vector3i(coord.x * 16, 0, coord.y * 16)
			for index: int in levels:
				var d := origin + _local(index) - pos
				best = maxi(best, int(levels[index]) - (absi(d.x) + absi(d.y) + absi(d.z)))
	return clampi(best, 0, 15)


func _column_height(x: int, z: int) -> int:
	var coord := VoxelWorld.chunk_coord_at(x, z)
	var chunk = realm.world.chunks.get(coord)
	if chunk == null:
		return -1  # unloaded: treat as open sky
	var heights: PackedInt32Array = _heights.get(coord, PackedInt32Array())
	if heights.is_empty():
		heights.resize(256)
		heights.fill(UNKNOWN_HEIGHT)
	var column := (x & 15) + (z & 15) * 16
	if heights[column] != UNKNOWN_HEIGHT:
		return heights[column]
	# Columns are measured when first asked about (a whole chunk at once is too slow for one tick).
	var blocks: PackedByteArray = chunk.blocks
	var opaque: PackedByteArray = server.registry.opaque_lut
	var h := -1
	for y in range(Chunk.SIZE_Y - 1, -1, -1):
		if opaque[blocks.decode_u16(Chunk.index(x & 15, y, z & 15) << 1)] == 1:
			h = y
			break
	heights[column] = h
	_heights[coord] = heights
	return h


static func _local(index: int) -> Vector3i:
	return Vector3i(index & 15, index >> 8, (index >> 4) & 15)
