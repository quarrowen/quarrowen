extends RefCounted
## A quantity moving along the graph: power, fluid, gas, mana. Layer two, on top of links.
##
## The engine never learns what any of it *is*. A mod declares a unit by name, says which faces offer
## it and which faces want it, and is told what each face actually got. Whether that means a furnace
## smelts slower or stops dead is the mod's business - a lamp and a smelter should not have to agree.
##
## **Event-driven, not ticked** (decided with the user, 2026-09-19). A network that recomputed every
## tick would cost real time on a homelab with a few hundred machines on it, and almost always to
## produce the answer it produced last tick. So a network works out an *allocation* - a rate per face -
## and that stands until something changes: a machine starts asking, a generator stops, a cable is cut.
## Machines then run at that rate on their own ticks.
##
## **Equal shares when there is not enough**, also decided rather than discovered: everybody gets the
## same fraction of what they asked for, so a grid under load dims everywhere rather than going dark in
## an order nobody can see. A mod that wants priority can ask for less and hold the difference back.
##
## Deliberately not here: storage. A buffer is a number in block data, which the mod already owns, and
## an engine that stored it would be deciding what a battery is.

const Links = preload("res://engine/server/links.gd")

## How many faces one network may have before it is left partly stale rather than stalling a tick.
const MAX_NETWORK := 2048

var server

## Unit name -> {name, owner}. A unit is just a name the engine keeps apart from other names.
var units := {}
## Unit -> node key -> amount offered per second.
var _supply := {}
## Unit -> node key -> amount wanted per second.
var _demand := {}
## Unit -> node key -> amount last granted, so a face is only told when its share actually changes.
var _granted := {}
## Node key -> {realm, position, face}, so a key can be turned back into somewhere to stand.
var _nodes := {}
## Unit -> handler, called when what a face receives changes.
var _handlers := {}
var _dirty := {}  # unit -> {node key: true} networks needing a fresh answer


func _init(game_server) -> void:
	server = game_server


func register_unit(unit: String, owner := "engine") -> bool:
	if unit.is_empty() or units.has(unit):
		push_error("Invalid or duplicate unit '%s'" % unit)
		return false
	units[unit] = {"name": unit, "owner": owner}
	_supply[unit] = {}
	_demand[unit] = {}
	_granted[unit] = {}
	_dirty[unit] = {}
	return true


## Told when what a face receives changes: ctx = {realm, position, face, unit, wanted, got}.
func on_received(unit: String, handler: Callable) -> void:
	_handlers[unit] = handler


## This face offers this much of `unit` per second (0 to stop).
func set_supply(unit: String, node: Dictionary, amount: float) -> void:
	_record(_supply, unit, node, amount)


## This face wants this much per second (0 to stop asking).
func set_demand(unit: String, node: Dictionary, amount: float) -> void:
	_record(_demand, unit, node, amount)


func supply_at(unit: String, node: Dictionary) -> float:
	return float(_supply.get(unit, {}).get(_key(node), 0.0))


func demand_at(unit: String, node: Dictionary) -> float:
	return float(_demand.get(unit, {}).get(_key(node), 0.0))


## What this face is actually receiving.
func received(unit: String, node: Dictionary) -> float:
	return float(_granted.get(unit, {}).get(_key(node), 0.0))


## Not named _set: Object already has a virtual of that name with a different signature, and a
## mismatch there is a parse error in a file that otherwise looks fine. (2026-09-19)
func _record(table: Dictionary, unit: String, node: Dictionary, amount: float) -> void:
	if not units.has(unit):
		push_error("No such unit '%s'" % unit)
		return
	var key := _key(node)
	amount = maxf(amount, 0.0)
	if is_equal_approx(float(table[unit].get(key, 0.0)), amount):
		return
	if amount > 0.0:
		table[unit][key] = amount
		_nodes[key] = node.duplicate()
	else:
		table[unit].erase(key)
	_dirty[unit][key] = true


## A link was made or cut: whatever it touched needs working out again.
func link_changed(a: Dictionary, b: Dictionary) -> void:
	for unit: String in units:
		_dirty[unit][_key(a)] = true
		_dirty[unit][_key(b)] = true


## Works out every network that has changed since last time. Called once a tick from the server, which
## is cheap when nothing changed - the usual case - because the dirty list is empty.
func settle() -> void:
	for unit: String in units:
		var pending: Dictionary = _dirty[unit]
		if pending.is_empty():
			continue
		_dirty[unit] = {}
		var done := {}
		for key: String in pending:
			if done.has(key):
				continue
			var node: Dictionary = _nodes.get(key, {})
			if node.is_empty():
				continue
			var network: Dictionary = server.links.reachable(node, MAX_NETWORK)
			for member: String in network:
				done[member] = true
			_solve(unit, network)


## One network: add up what is offered, add up what is wanted, and hand out shares.
func _solve(unit: String, network: Dictionary) -> void:
	var offered := 0.0
	var wanted := 0.0
	for key: String in network:
		offered += float(_supply[unit].get(key, 0.0))
		wanted += float(_demand[unit].get(key, 0.0))
	# The same fraction for everybody. A grid under load dims all over rather than going dark in an
	# order the player cannot see or predict.
	var share := 1.0 if wanted <= 0.0 or offered >= wanted else offered / wanted
	for key: String in network:
		var asked := float(_demand[unit].get(key, 0.0))
		var got := asked * share
		if is_equal_approx(float(_granted[unit].get(key, 0.0)), got):
			continue
		if got > 0.0:
			_granted[unit][key] = got
		else:
			_granted[unit].erase(key)
		var handler: Callable = _handlers.get(unit, Callable())
		if handler.is_valid() and _nodes.has(key):
			var node: Dictionary = _nodes[key]
			handler.call({"realm": node.realm, "position": node.position, "face": node.face,
				"unit": unit, "wanted": asked, "got": got})


func _key(node: Dictionary) -> String:
	return Links.node_key(String(node.get("realm", "")), node.get("position", Vector3i.ZERO), int(node.get("face", 0)))
