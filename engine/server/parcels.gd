extends RefCounted
## Things travelling along the graph: layer three, and deliberately not the same mechanism as layer two.
##
## **Why items are not a quantity.** Power and fluid are fungible - five hundred splits into two lots
## of two hundred and fifty and the halves are indistinguishable. An item is not that. A pickaxe with
## twelve durability left and a name somebody gave it cannot be halved, is not interchangeable with the
## next one, and has to arrive intact and in order. Making items ride the quantity code would end with
## either items losing their data or the quantity code growing special cases until it was two systems
## sharing one name. (Discussed with the user, 2026-09-19.)
##
## What *is* shared is the graph underneath: links, faces, reach, what is still connected. That is the
## whole reason links were built as their own layer.
##
## A face says what it will accept; another face sends something; the engine finds a face that will
## take it, works out how long the journey is, and delivers it. Sorters, filters and round-robin
## splitters are then blocks a mod writes, because what a machine does with what arrives is content.

const Links = preload("res://engine/server/links.gd")

## Parcels in flight at once, across the whole server. Reached only by somebody building something
## enormous or something silly; either way the server says no rather than slowing down for everybody.
const MAX_IN_TRANSIT := 4096
## How far a parcel travels per second when a link kind does not say.
const DEFAULT_SPEED := 4.0

var server

## Node key -> {allow: {name: true}, tags: [String], deny: bool}
var _accepts := {}
## Node key -> {realm, position, face}
var _nodes := {}
## In flight: {to, from, item, count, data, at (seconds remaining)}
var _moving: Array = []
var _on_arrived := Callable()
## Node key -> how many were sent from here, so several destinations share the work rather than the
## first one found taking everything for ever.
var _turn := {}


func _init(game_server) -> void:
	server = game_server


## What a face will take. `items` and `tags` name what is allowed; an empty filter takes anything.
## `deny` turns it inside out, which is how a mod writes "everything except cobblestone".
func set_accepts(node: Dictionary, filter: Dictionary) -> void:
	var key := _key(node)
	var allow := {}
	for entry in (filter.get("items", []) if filter.get("items") is Array else []):
		allow[String(entry)] = true
	var tags := []
	for entry in (filter.get("tags", []) if filter.get("tags") is Array else []):
		tags.append(String(entry))
	_accepts[key] = {"allow": allow, "tags": tags, "deny": bool(filter.get("deny", false))}
	_nodes[key] = node.duplicate()


func stop_accepting(node: Dictionary) -> void:
	var key := _key(node)
	_accepts.erase(key)


func accepts(node: Dictionary, item_name: String) -> bool:
	var filter: Dictionary = _accepts.get(_key(node), {})
	if filter.is_empty():
		return false
	return _matches(filter, item_name)


func on_arrived(handler: Callable) -> void:
	_on_arrived = handler


## Sends something from a face to whichever connected face will take it. Returns true if it is on its
## way; false if nothing would take it, which is the answer a mod needs to decide whether to keep
## holding the thing or to stop trying.
func send(from: Dictionary, item_name: String, count: int, data := {}) -> bool:
	if _moving.size() >= MAX_IN_TRANSIT or count <= 0 or item_name.is_empty():
		return false
	var to := _destination(from, item_name)
	if to.is_empty():
		return false
	_nodes[_key(from)] = from.duplicate()
	var distance := Vector3(from.position - to.position).length() if from.realm == to.realm else 1.0
	_moving.append({"to": to, "from": from.duplicate(), "item": item_name, "count": count,
		"data": data.duplicate(true), "at": maxf(distance, 1.0) / DEFAULT_SPEED})
	return true


## Whether anything connected to this face would take this item, without sending it.
func would_accept(from: Dictionary, item_name: String) -> bool:
	return not _destination(from, item_name, false).is_empty()


## The next face that will take this item. Destinations take turns, so a line of chests fills evenly
## rather than the first one found swallowing everything for ever.
func _destination(from: Dictionary, item_name: String, advance := true) -> Dictionary:
	var reachable: Dictionary = server.links.reachable(from)
	var candidates := []
	for key: String in reachable:
		if key == _key(from) or not _accepts.has(key):
			continue
		if _matches(_accepts[key], item_name) and _nodes.has(key):
			candidates.append(key)
	if candidates.is_empty():
		return {}
	candidates.sort()  # a stable order, so taking turns means something across ticks
	var turn := int(_turn.get(_key(from), 0))
	if advance:
		_turn[_key(from)] = turn + 1
	return _nodes[candidates[turn % candidates.size()]]


func _matches(filter: Dictionary, item_name: String) -> bool:
	var listed: bool = filter.allow.has(item_name)
	if not listed:
		for tag_name in filter.tags:
			if server.tags.has(String(tag_name), item_name):
				listed = true
				break
	# Nothing named at all means "anything", which is what an ordinary pipe end is.
	if filter.allow.is_empty() and (filter.tags as Array).is_empty():
		return not filter.deny
	return listed != bool(filter.deny)


## Moves everything in flight along, and delivers what has arrived.
func update(delta: float) -> void:
	if _moving.is_empty():
		return
	var still_going := []
	for parcel: Dictionary in _moving:
		parcel.at -= delta
		if parcel.at > 0.0:
			still_going.append(parcel)
			continue
		if _on_arrived.is_valid():
			_on_arrived.call({"realm": parcel.to.realm, "position": parcel.to.position, "face": parcel.to.face,
				"item": parcel.item, "count": parcel.count, "data": parcel.data, "from": parcel.from})
	_moving = still_going


## How many parcels are in flight, for the dev tools and for tests.
func in_transit() -> int:
	return _moving.size()


func _key(node: Dictionary) -> String:
	return Links.node_key(String(node.get("realm", "")), node.get("position", Vector3i.ZERO), int(node.get("face", 0)))
