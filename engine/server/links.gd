extends RefCounted
## What is joined to what: the graph everything industrial stands on.
##
## A **node** is a *face* of a block, not the block. A machine takes power in one side and pushes items
## out of another, which is how anybody actually builds a factory, and one node per block cannot say
## that. (2026-09-19)
##
## A **link** joins two nodes directly, whatever lies between them. Its **kind** - declared by a mod -
## decides nearly all of its behaviour: how far it may reach, what it costs, whether it needs clear air,
## what it is drawn as, and whether it may leave the world it is in. The engine holds the graph and
## knows none of that, which is what stops it deciding that everything is a wire:
##
## - **cables sag** (electricity strung between poles, and the sag is most of why it reads as a cable)
## - **pipes do not** (a rigid fluid line drawn with a droop looks broken, and wants a shorter reach)
## - **wireless has nothing to draw at all**, and its range is a question for the mod rather than a
##   constant here, because a mod may raise it with an upgrade
##
## **Only a wireless link may cross between worlds.** A cable or a pipe is a physical thing and cannot
## run through the gap between realms; a wireless one may, if its kind says so. That is what lets a
## quarry in the Emberdeep report to a base in the overworld without anybody laying a cable through a
## portal.
##
## Links are **saved**. Unlike a signal level, which follows from where the sources are, a link is a
## record of where somebody *chose* to run a cable and cannot be worked out again from the blocks.

const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

## The six faces a node can be on, in the order their offsets are listed.
enum Face { UP, DOWN, NORTH, SOUTH, WEST, EAST }
const FACE_OFFSETS := [Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK, Vector3i.LEFT, Vector3i.RIGHT]

## Nothing may be stored unboundedly on a player's say-so: these are the ceilings a kind's own limits
## must fit inside, not the limits themselves.
const MAX_SPAN := 64
const MAX_PER_NODE := 16

var server

## Kind name -> definition. See `register_kind`.
var kinds := {}
## Node key -> {link id: true}. The key is "<realm>|x,y,z|face", which is a string on purpose: it is a
## dictionary key in a hot path, and comparing one string beats comparing a realm and a vector and an
## integer every time.
var _by_node := {}
## Link id -> {kind, a: {realm, position, face}, b: {...}, length}
var links := {}
var _next_id := 1


func _init(game_server) -> void:
	server = game_server


## A kind of link a mod can lay.
##
## def: `span` (blocks, capped at MAX_SPAN), `wireless` (nothing is drawn and no clear line is needed),
## `crosses_realms` (wireless only), `needs_air` (refuse if anything solid is in the way; default true
## for anything not wireless), `item` (what a block of it costs to lay), `draw` ("cable" sags, "pipe"
## does not, "" draws nothing).
func register_kind(kind_name: String, def: Dictionary, owner := "engine") -> bool:
	if kind_name.is_empty() or kinds.has(kind_name):
		push_error("Invalid or duplicate link kind '%s'" % kind_name)
		return false
	var wireless := bool(def.get("wireless", false))
	kinds[kind_name] = {
		"name": kind_name,
		"owner": owner,
		"wireless": wireless,
		# A physical thing cannot run through the gap between worlds, whatever a mod asks for.
		"crosses_realms": wireless and bool(def.get("crosses_realms", false)),
		"span": clampi(int(def.get("span", 12)), 1, MAX_SPAN),
		"needs_air": bool(def.get("needs_air", not wireless)),
		"item": String(def.get("item", "")),
		"draw": String(def.get("draw", "" if wireless else "cable")),
		"per_node": clampi(int(def.get("per_node", 6)), 1, MAX_PER_NODE),
	}
	return true


static func node_key(realm_id: String, pos: Vector3i, face: int) -> String:
	return "%s|%d,%d,%d|%d" % [realm_id, pos.x, pos.y, pos.z, face]


## Why these two nodes may not be joined, or "" if they may. Every refusal is a sentence somebody can
## act on, because "cannot place" tells a child nothing.
func why_not(kind_name: String, a: Dictionary, b: Dictionary) -> String:
	var kind: Dictionary = kinds.get(kind_name, {})
	if kind.is_empty():
		return "There is no such connector."
	if a.realm == b.realm and a.position == b.position and a.face == b.face:
		return "That is the same place twice."
	if a.realm != b.realm and not kind.crosses_realms:
		return "This will not reach into another world." if kind.wireless else "A line cannot run between worlds."
	var reach: int = _reach_of(kind_name, a)
	if a.realm == b.realm:
		var distance := Vector3(a.position - b.position).length()
		if distance > float(reach):
			return "Too far apart: %d blocks, and this reaches %d." % [roundi(distance), reach]
	if _count_at(a) >= int(kind.per_node) or _count_at(b) >= int(kind.per_node):
		return "That end has as many connections as it can hold."
	if kind.needs_air and a.realm == b.realm and not _clear_between(a, b):
		return "Something solid is in the way."
	for id: int in _at(a):
		var link: Dictionary = links[id]
		if _same_node(link.b, b) or _same_node(link.a, b):
			return "Those are already joined."
	return ""


## How far this kind reaches from this node. A mod may raise it - an upgrade, a better aerial - so it
## is asked for rather than read off the kind, and the kind's own span is the default and the ceiling.
func _reach_of(kind_name: String, node: Dictionary) -> int:
	var kind: Dictionary = kinds[kind_name]
	var answer: Dictionary = server.emit("link_reach", {"kind": kind_name, "realm": node.realm,
		"position": node.position, "face": node.face, "reach": int(kind.span)})
	return clampi(int(answer.get("reach", kind.span)), 1, MAX_SPAN)


## Joins two nodes. Returns the link id, or 0 with the reason in `problem`.
var problem := ""


func join(kind_name: String, a: Dictionary, b: Dictionary) -> int:
	problem = why_not(kind_name, a, b)
	if not problem.is_empty():
		return 0
	var id := _next_id
	_next_id += 1
	links[id] = {"kind": kind_name, "a": a.duplicate(), "b": b.duplicate(),
		"length": roundi(Vector3(a.position - b.position).length()) if a.realm == b.realm else 0}
	_by_node.get_or_add(_key(a), {})[id] = true
	_by_node.get_or_add(_key(b), {})[id] = true
	server.emit("link_made", {"id": id, "kind": kind_name, "a": a, "b": b})
	return id


## Removes a link and says so. `why` reaches the mod, which is how a player finds out their cable was
## cut by a wall somebody built rather than simply stopping working.
func cut(id: int, why := "removed") -> bool:
	var link: Dictionary = links.get(id, {})
	if link.is_empty():
		return false
	links.erase(id)
	for node in [link.a, link.b]:
		var at: Dictionary = _by_node.get(_key(node), {})
		at.erase(id)
		if at.is_empty():
			_by_node.erase(_key(node))
	server.emit("link_cut", {"id": id, "kind": link.kind, "a": link.a, "b": link.b, "reason": why})
	return true


## Every link touching a block, whichever face. Used when one is mined.
func at_block(realm_id: String, pos: Vector3i) -> Array:
	var out := {}
	for face in FACE_OFFSETS.size():
		for id: int in _by_node.get(node_key(realm_id, pos, face), {}):
			out[id] = true
	return out.keys()


## Everything reachable from a node, as node keys. The graph traversal every layer above this uses.
func reachable(from: Dictionary, limit := 4096) -> Dictionary:
	var seen := {_key(from): true}
	var stack := [from]
	while not stack.is_empty() and seen.size() < limit:
		var node: Dictionary = stack.pop_back()
		for id: int in _at(node):
			var link: Dictionary = links[id]
			var other: Dictionary = link.b if _same_node(link.a, node) else link.a
			if not seen.has(_key(other)):
				seen[_key(other)] = true
				stack.append(other)
	return seen


## A block was placed or broken. Links ending at it go; links *passing through* it are cut too, which
## is the rule that stops a cable quietly running through a wall somebody built after it.
func block_changed(realm_id: String, pos: Vector3i, old: int, block: int) -> void:
	if old == block:
		return
	for id in at_block(realm_id, pos):
		cut(id, "the block it was fixed to is gone")
	if block == 0 or not server.registry.is_valid(block) or server.registry.solid_lut[block] != 1:
		return
	for id: int in links.keys():
		var link: Dictionary = links[id]
		var kind: Dictionary = kinds.get(link.kind, {})
		if kind.is_empty() or not kind.needs_air or link.a.realm != realm_id or link.b.realm != realm_id:
			continue
		if _passes_through(link.a.position, link.b.position, pos):
			cut(id, "something was built through it")


## Whether the straight line between two nodes is clear of solid blocks.
func _clear_between(a: Dictionary, b: Dictionary) -> bool:
	var realm = server.realms.get(a.realm)
	if realm == null:
		return false
	var from := Vector3(a.position) + Vector3(0.5, 0.5, 0.5)
	var to := Vector3(b.position) + Vector3(0.5, 0.5, 0.5)
	var steps := maxi(2, roundi(from.distance_to(to) * 2.0))
	for i in range(1, steps):
		var at := Vector3i((from.lerp(to, float(i) / steps)).floor())
		if at == a.position or at == b.position:
			continue
		var there: int = realm.world.get_block_v(at)
		if server.registry.is_valid(there) and server.registry.solid_lut[there] == 1:
			return false
	return true


## Whether a cell sits on the line between two ends (the same walk as _clear_between, asked the other
## way round).
func _passes_through(from_pos: Vector3i, to_pos: Vector3i, cell: Vector3i) -> bool:
	if cell == from_pos or cell == to_pos:
		return false
	var from := Vector3(from_pos) + Vector3(0.5, 0.5, 0.5)
	var to := Vector3(to_pos) + Vector3(0.5, 0.5, 0.5)
	var steps := maxi(2, roundi(from.distance_to(to) * 2.0))
	for i in range(1, steps):
		if Vector3i((from.lerp(to, float(i) / steps)).floor()) == cell:
			return true
	return false


func _key(node: Dictionary) -> String:
	return node_key(String(node.realm), node.position, int(node.face))


func _at(node: Dictionary) -> Array:
	return _by_node.get(_key(node), {}).keys()


func _count_at(node: Dictionary) -> int:
	return _by_node.get(_key(node), {}).size()


static func _same_node(x: Dictionary, y: Dictionary) -> bool:
	return x.realm == y.realm and x.position == y.position and int(x.face) == int(y.face)


## What to save with the world. Links belong to the world rather than to a chunk: one end may be in a
## chunk that is loaded and the other in one that is not, and a link that vanished because half of it
## was asleep would be a very confusing bug.
func to_saved() -> Array:
	var out := []
	for id: int in links:
		var link: Dictionary = links[id]
		out.append({"kind": link.kind,
			"a": [link.a.realm, link.a.position.x, link.a.position.y, link.a.position.z, link.a.face],
			"b": [link.b.realm, link.b.position.x, link.b.position.y, link.b.position.z, link.b.face]})
	return out


func load_saved(list) -> void:
	links.clear()
	_by_node.clear()
	_next_id = 1
	if not (list is Array):
		return
	for entry in list:
		if not (entry is Dictionary) or not (entry.get("a") is Array) or not (entry.get("b") is Array):
			continue
		var a = entry.a
		var b = entry.b
		if a.size() != 5 or b.size() != 5 or not kinds.has(String(entry.get("kind", ""))):
			continue  # a link from a mod that is no longer here: dropped rather than half-restored
		var id := _next_id
		_next_id += 1
		var node_a := {"realm": String(a[0]), "position": Vector3i(int(a[1]), int(a[2]), int(a[3])), "face": int(a[4])}
		var node_b := {"realm": String(b[0]), "position": Vector3i(int(b[1]), int(b[2]), int(b[3])), "face": int(b[4])}
		links[id] = {"kind": String(entry.kind), "a": node_a, "b": node_b,
			"length": roundi(Vector3(node_a.position - node_b.position).length()) if node_a.realm == node_b.realm else 0}
		_by_node.get_or_add(_key(node_a), {})[id] = true
		_by_node.get_or_add(_key(node_b), {})[id] = true
