extends RefCounted
## Liquids that go somewhere: water that spreads and falls, lava that creeps, and what happens where
## two of them meet.
##
## **Why this is a capability and not content.** Water and lava already existed as blocks and sat
## exactly where they were put, and the absence was larger than it sounds: a bucket is not worth
## carrying if what comes out of it cannot go anywhere, a cave cannot flood, a moat is a row of still
## squares, and the black glass that forms where lava meets water has no way to exist at all.
##
## The engine knows that *a* liquid spreads, how far, how fast, and that two of them meeting makes
## something. It does not know what water is. A mod says:
##
##     api.register_liquid("water", {"range": 7, "falls": true, "speed": 0.25})
##     api.register_liquid_meeting("water", "lava", "base:blackglass")
##
## **The level lives in the block's state**, which already exists, is already saved with the chunk and
## is already sent to clients. State 0 is a source - it never runs out and never dries up. States 1
## upwards are flow, weakening by one a block, and a flow with nothing feeding it dries up. Nothing new
## had to be put on disk or on the wire for any of this.
##
## **Depth is shown by swapping the block, not by the level alone.** A mod gives a liquid a `shallow`
## twin - an ordinary block with a slab shape - and everything past `shallow_from` blocks of travel is
## placed as that instead. A thin sheet then reads as a thin sheet, and a player wades through it
## rather than swimming, because shapes decide collision as well as drawing.
##
## Done this way on purpose. Rendering an arbitrary height per level would mean sending block states to
## the mesher and re-packing the key its greedy merging uses, in both the GDScript mesher and its Rust
## twin, which must agree exactly - a great deal of risk in the most delicate pair in the codebase, for
## a cosmetic gain. Two depths is most of the look for none of that. (2026-09-20)

const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

const SIDES := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]
## The most cells one flow step may touch. A player emptying a bucket into a cave system should not be
## able to stop the tick while it finds its way down.
const MAX_STEP := 512

var server
var realm

## Block id -> {range, falls, speed, name}
var kinds := {}
## Two block ids meeting -> the block that forms. Keyed "lower:higher" so the pair is order-free.
var meetings := {}


func _init(game_server, in_realm) -> void:
	server = game_server
	realm = in_realm


## `shallow` is the block id to use once it has travelled `shallow_from` blocks (0 for none). Both ids
## are the same liquid as far as flowing, drying and meeting are concerned.
func register(block: int, def: Dictionary) -> void:
	var shallow := int(def.get("shallow", 0))
	if shallow > 0:
		# The thin form is the same liquid wearing a different shape, so it answers to the deep one.
		kinds[shallow] = {"name": String(def.get("name", "")), "range": clampi(int(def.get("range", 7)), 1, 15),
			"falls": bool(def.get("falls", true)), "speed": clampf(float(def.get("speed", 0.25)), 0.05, 10.0),
			"family": block, "shallow": shallow, "shallow_from": int(def.get("shallow_from", 4))}
	kinds[block] = {
		"name": String(def.get("name", "")),
		# How many blocks it travels from its source before it runs out. Water goes further than lava,
		# which is most of what makes lava frightening and water useful.
		"range": clampi(int(def.get("range", 7)), 1, 15),
		"falls": bool(def.get("falls", true)),
		"speed": clampf(float(def.get("speed", 0.25)), 0.05, 10.0),
		"family": block,
		"shallow": shallow,
		"shallow_from": int(def.get("shallow_from", 4)),
	}


## What forms where these two meet. The mod decides; the engine has never heard of obsidian.
func register_meeting(a: int, b: int, result: int) -> void:
	meetings[_pair(a, b)] = result


func is_liquid(block: int) -> bool:
	return kinds.has(block)


## The deep form of whatever liquid this is, so the two forms are one thing everywhere it matters.
func family_of(block: int) -> int:
	return int(kinds.get(block, {}).get("family", 0))


## Which block a flow at this level should be: the thin form once it has travelled far enough.
func _form_for(block: int, level: int) -> int:
	var kind: Dictionary = kinds.get(block, {})
	var shallow := int(kind.get("shallow", 0))
	var from := int(kind.get("shallow_from", 0))
	if shallow > 0 and from > 0 and level >= from:
		return shallow
	return int(kind.get("family", block))


static func _pair(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## A block was placed or broken: whatever was flowing near it may now have somewhere to go, or nothing
## holding it up.
func block_changed(pos: Vector3i, old: int, block: int) -> void:
	if old == block:
		return
	_wake(pos)
	for step in SIDES + [Vector3i.UP, Vector3i.DOWN]:
		_wake(pos + step)


## Asks a cell to think again, shortly. Scheduled rather than done now: a chain of water finding its
## way down a cliff would otherwise all happen inside one block placement.
func _wake(pos: Vector3i) -> void:
	var block: int = realm.world.get_block_v(pos)
	if kinds.has(block):
		realm.block_ticks.schedule(pos, float(kinds[block].speed), {"liquid": true})
	elif _can_flow_into(block):
		# An empty cell next to a liquid may be about to be filled, so whatever is beside it should
		# think again.
		for step in SIDES + [Vector3i.UP]:
			var neighbour: int = realm.world.get_block_v(pos + step)
			if kinds.has(neighbour):
				realm.block_ticks.schedule(pos + step, float(kinds[neighbour].speed), {"liquid": true})


func _can_flow_into(block: int) -> bool:
	if block == 0:
		return true
	if block == 255 or not server.registry.is_valid(block):
		return false  # unloaded, or nothing at all: never flow into what we cannot see
	return bool(server.registry.defs[block].get("replaceable", false)) and not kinds.has(block)


## One step for the liquid at `pos`. Called from a scheduled block tick.
func step(pos: Vector3i) -> void:
	var block: int = realm.world.get_block_v(pos)
	var kind: Dictionary = kinds.get(block, {})
	if kind.is_empty():
		return
	var level: int = realm.block_state(pos)

	var mine := family_of(block)
	# Meeting something else it does not mix with turns both into whatever the mod said. Compared by
	# family, or a thin sheet of water would not know it had met lava.
	for step_dir in SIDES + [Vector3i.UP, Vector3i.DOWN]:
		var other: int = realm.world.get_block_v(pos + step_dir)
		if not kinds.has(other) or family_of(other) == mine:
			continue
		var result: int = int(meetings.get(_pair(mine, family_of(other)), -1))
		if result >= 0:
			server.set_block_authoritative(pos, result, false, 0, realm)
			return

	# A flow with nothing feeding it dries up. A source (level 0) never does, which is what makes it a
	# source and why a bucket is worth carrying.
	if level > 0 and not _is_fed(pos, mine, level):
		server.set_block_authoritative(pos, 0, false, 0, realm)
		return

	# Down first, and falling does not weaken it: water off a cliff arrives as strong as it left.
	if bool(kind.falls):
		var below: Vector3i = pos + Vector3i.DOWN
		if below.y >= 0 and _can_flow_into(realm.world.get_block_v(below)):
			# Falling does not weaken it, so what lands below is the deep form however far it has come.
			server.set_block_authoritative(below, _form_for(mine, 1), false, mini(level, 1), realm)
			return
		# Sitting on something solid, water spreads out; falling water does not spread on the way down.
		if not _is_solid_enough(realm.world.get_block_v(below)):
			return

	if level >= int(kind.range):
		return
	for side in SIDES:
		var at: Vector3i = pos + side
		var there: int = realm.world.get_block_v(at)
		if _can_flow_into(there):
			server.set_block_authoritative(at, _form_for(mine, level + 1), false, level + 1, realm)
		elif kinds.has(there) and family_of(there) == mine and realm.block_state(at) > level + 1:
			# A weaker flow beside a stronger one is refreshed rather than left to dry, or a pool would
			# ripple oddly as it settled.
			server.set_block_authoritative(at, _form_for(mine, level + 1), false, level + 1, realm)


## Whether anything is keeping this flow alive: the same liquid above it, or a stronger one beside it.
func _is_fed(pos: Vector3i, mine: int, level: int) -> bool:
	if family_of(realm.world.get_block_v(pos + Vector3i.UP)) == mine:
		return true
	for side in SIDES:
		var at: Vector3i = pos + side
		if family_of(realm.world.get_block_v(at)) == mine and realm.block_state(at) < level:
			return true
	return false


func _is_solid_enough(block: int) -> bool:
	if block == 255 or not server.registry.is_valid(block):
		return true  # unloaded ground holds water up rather than letting it pour into nothing
	return not _can_flow_into(block)
