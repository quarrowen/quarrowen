extends RefCounted
## A level that spreads from block to block and fades with distance, and blocks that are told when the
## level reaching them changes.
##
## **That is the whole capability, and it is deliberately less than it looks.** Gates, delays,
## inverters, latches and counters are *blocks a mod writes*: each one is told the level arriving at
## it, decides what that means, and emits accordingly with `set_source`. An engine that shipped an AND
## gate would have decided what logic looks like here, which is not its business - a mod building a
## puzzle game and a mod building a factory want very different answers.
##
## What the engine knows:
##
## - **Sources** emit a level. A block type can always emit one (`signal: 15` in its definition), or a
##   mod can set one on a particular block (`set_source`) when a lever is flipped or a plate stepped on.
## - **Carriers** pass it on, one level weaker each block (`signal_carry: true`). Fifteen blocks and it
##   is gone, so a long run needs something to repeat it - which is a block a mod writes.
## - **Receivers** are told when the level arriving changes (`register`). A door opens, a lamp lights,
##   a piston shoves.
##
## In the bundled game the carrier is **quickdust** and the stone it comes from is **quickstone**; a
## block with a level reaching it is *quickened*. Those are the mod's words. Another mod's wiring can
## look nothing like it, which is the test this capability has to pass.
##
## **Nothing here is saved.** A level is not a fact about the world, it is what follows from where the
## sources are - and the sources *are* saved, as blocks and their data. So the whole network is worked
## out again when chunks come back, and there is no new shape on disk to get wrong later.

const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

const MAX_LEVEL := 15
## Cells recomputed in one go. A network larger than this is somebody's mistake or somebody's art
## project; either way the server must not stop for it.
const MAX_COMPONENT := 4096
## How far one change may cascade through gates that set off other gates. A mod may build a clock; it
## may not stop the server with one.
const MAX_CASCADE := 32
const NEIGHBOURS := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]

var server
var realm

## Where a level is, and how strong. Only cells above zero are kept, so an unpowered world costs nothing.
var levels := {}  # Vector3i -> int
## Levels a mod has put on particular blocks (a lever that is on). Block types that always emit are
## read from the registry instead, so a thousand torches cost no memory.
var sources := {}  # Vector3i -> int
## Which source each powered cell's level came from. A gate must not hear its own voice come back to it
## through the wire it is driving - which is not the same as not hearing its own cell, and cost an
## afternoon to tell apart. (2026-09-19)
var origins := {}  # Vector3i -> Vector3i
## Block id -> {handler, owner}: told when the level arriving at one of these changes.
var handlers := {}
## How deep a change is cascading. Two gates can feed each other for ever - a mod is allowed to build a
## clock - so the chain is cut rather than the server stopped, and the mod is told once.
var _depth := 0
var _warned := false


func _init(game_server, in_realm) -> void:
	server = game_server
	realm = in_realm


## Tells `handler(ctx)` when the level reaching a block of this type changes.
## ctx = {position, block, level, previous, realm}.
func register(block: int, handler: Callable, owner := "engine") -> void:
	handlers[block] = {"handler": handler, "owner": owner}


## Makes the block at `pos` emit `level` (0 stops it). This is how a lever, a plate or a mod's own
## gate speaks: the engine never learns what any of them are.
func set_source(pos: Vector3i, level: int) -> void:
	level = clampi(level, 0, MAX_LEVEL)
	if level == int(sources.get(pos, 0)):
		return
	# Snapshot who is listening and what they hear *before* changing anything: the point of the change
	# is usually that a source stopped, and asking afterwards compares silence with silence.
	var watchers := _watchers(pos)
	if level > 0:
		sources[pos] = level
	else:
		sources.erase(pos)
	_recompute(pos, watchers)


## The level in a cell: what a carrier there is carrying.
func level_at(pos: Vector3i) -> int:
	return int(levels.get(pos, 0))


## The strongest level arriving at a block **from elsewhere** - what a receiver acts on.
##
## Deliberately not counting what the block itself emits. A gate that heard its own output would
## oscillate for ever the moment a mod wrote the most obvious thing there is - "emit when nothing
## reaches me" - and the first version of this did exactly that, with a stack overflow to show for it.
## A thing does not hear itself speak.
func reaching(pos: Vector3i) -> int:
	var best := 0
	if _carries(pos) and origins.get(pos) != pos:
		best = int(levels.get(pos, 0))
	for step in NEIGHBOURS:
		var at: Vector3i = pos + step
		if origins.get(at) == pos:
			continue  # this is our own output, come back around
		best = maxi(best, int(levels.get(at, 0)))
	return best


## What a cell emits on its own account: a mod's source, or a block type that always emits.
func _emitted(pos: Vector3i) -> int:
	var own := int(sources.get(pos, 0))
	var block: int = realm.world.get_block_v(pos)
	if server.registry.is_valid(block):
		own = maxi(own, int(server.registry.defs[block].get("signal", 0)))
	return own


func _carries(pos: Vector3i) -> bool:
	var block: int = realm.world.get_block_v(pos)
	return server.registry.is_valid(block) and bool(server.registry.defs[block].get("signal_carry", false))


## A block was placed or broken: the network around it may be a different shape now.
func block_changed(pos: Vector3i, old: int, block: int) -> void:
	if old == block:
		return
	var watchers := _watchers(pos)
	sources.erase(pos)  # whatever was emitting here is gone; the new block speaks for itself
	_recompute(pos, watchers)


## Forgets a chunk's levels. Nothing is written: a level follows from the sources, and they are saved
## with the blocks, so it is worked out again when somebody comes back.
func unload_chunk(coord: Vector2i) -> void:
	for pos: Vector3i in levels.keys():
		if VoxelWorld.chunk_coord_at(pos.x, pos.z) == coord:
			levels.erase(pos)
			origins.erase(pos)
	for pos: Vector3i in sources.keys():
		if VoxelWorld.chunk_coord_at(pos.x, pos.z) == coord:
			sources.erase(pos)


## Works out the network again around `seed_pos` and tells whatever the change reached.
##
## Only the piece that is connected to the change is touched, not the whole world: a lever in one base
## must not cost anything to somebody's machine a thousand blocks away.
## Who is listening around here, and what each of them hears at this moment. A receiver need not carry
## or emit anything - a door is just a door - so it is never part of the network itself, and what it
## was hearing has to be written down before the network moves underneath it. (2026-09-19)
func _watchers(seed_pos: Vector3i) -> Dictionary:
	var watchers := {}
	var cells := [seed_pos] + NEIGHBOURS.map(func(s: Vector3i) -> Vector3i: return seed_pos + s)
	for cell: Vector3i in _component(seed_pos):
		for step in ([Vector3i.ZERO] + NEIGHBOURS):
			cells.append(cell + step)
	for cell: Vector3i in cells:
		if not watchers.has(cell) and handlers.has(realm.world.get_block_v(cell)):
			watchers[cell] = reaching(cell)
	return watchers


func _recompute(seed_pos: Vector3i, watchers: Dictionary) -> void:
	var component := _component(seed_pos)
	# A cell that is no longer part of any network keeps no level. Switching off the last source in a
	# run can leave nothing there to recompute - the run stops being a network at all - so the level it
	# was carrying would otherwise sit there for ever, quietly powering its neighbours. (2026-09-19)
	for cell: Vector3i in ([seed_pos] + NEIGHBOURS.map(func(s: Vector3i) -> Vector3i: return seed_pos + s)):
		if not component.has(cell):
			levels.erase(cell)
			origins.erase(cell)
	if component.is_empty():
		_notify(watchers)
		return

	# Every source in the piece pushes its level outwards, weakening by one a block, and the strongest
	# wins wherever two meet. Done widest-first so a cell is never visited with a weaker level later.
	var after := {}
	var came_from := {}
	var queue := []
	for cell: Vector3i in component:
		var own := _emitted(cell)
		if own > 0:
			after[cell] = own
			came_from[cell] = cell
			queue.append(cell)
	queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return int(after[a]) > int(after[b]))
	var head := 0
	while head < queue.size():
		var cell: Vector3i = queue[head]
		head += 1
		var next := int(after[cell]) - 1
		if next <= 0:
			continue
		for step in NEIGHBOURS:
			var to: Vector3i = cell + step
			if not component.has(to) or next <= int(after.get(to, 0)):
				continue
			after[to] = next
			came_from[to] = came_from[cell]
			queue.append(to)

	for cell: Vector3i in component:
		var now := int(after.get(cell, 0))
		if now > 0:
			levels[cell] = now
			origins[cell] = came_from[cell]
		else:
			levels.erase(cell)
			origins.erase(cell)
	_notify(watchers)


## The connected run of carriers and sources reached from `pos`, as a set. Bounded: past MAX_COMPONENT
## it stops, which leaves a very large network partly stale rather than stalling the tick for everybody.
func _component(pos: Vector3i) -> Dictionary:
	var seen := {}
	var stack := []
	for start in ([pos] + NEIGHBOURS.map(func(step: Vector3i) -> Vector3i: return pos + step)):
		if _carries(start) or _emitted(start) > 0:
			stack.append(start)
			seen[start] = true
	while not stack.is_empty() and seen.size() < MAX_COMPONENT:
		var cell: Vector3i = stack.pop_back()
		for step in NEIGHBOURS:
			var to: Vector3i = cell + step
			if seen.has(to) or to.y < 0 or to.y >= Chunk.SIZE_Y:
				continue
			if _carries(to) or _emitted(to) > 0:
				seen[to] = true
				stack.append(to)
	return seen


## Tells each watcher what is arriving now, if it is different from what was arriving before.
func _notify(watchers: Dictionary) -> void:
	if _depth >= MAX_CASCADE:
		if not _warned:
			_warned = true
			server.dev_log.add("warn", "engine", "A signal network is feeding itself; stopped after %d steps" % MAX_CASCADE)
		return
	_depth += 1
	for at: Vector3i in watchers:
		var block: int = realm.world.get_block_v(at)
		var h: Dictionary = handlers.get(block, {})
		if h.is_empty() or not h.handler.is_valid():
			continue
		var now := reaching(at)
		var was := int(watchers[at])
		if now == was:
			continue
		var t := Time.get_ticks_usec()
		h.handler.call({"position": at, "block": block, "level": now, "previous": was, "realm": realm.id})
		server.dev_tools.record(h.owner, "signal:" + server.registry.defs[block].name, Time.get_ticks_usec() - t)
	_depth -= 1
	if _depth == 0:
		_warned = false
