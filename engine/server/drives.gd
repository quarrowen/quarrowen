extends RefCounted
## A value driven through the graph with nothing stored anywhere: rotation, and whatever else a mod
## means by "this end turns, so that end turns".
##
## **Why this is not the other kind of network.** A quantity is stored and conserved - it buffers,
## fills and runs out, and two generators on one grid add up. Rotation is not that shape at all. It is
## a speed and a direction; it arrives the instant the shaft turns; nothing accumulates in the gearbox;
## and two sources driving one line of shafts do not add, they **fight**.
##
## So the rules here are deliberately different from flows:
##
## - A source drives a value. Everything connected to it is driven at that value, undiminished by
##   distance, because a shaft does not get tired half way along.
## - **Two sources that disagree jam the whole line.** The engine does not invent an average, because
##   an average is a made-up answer to a question with a real one: somebody has connected a windmill to
##   a water wheel turning the other way, and the interesting thing to do is stop and say so.
## - Nothing is saved. What a shaft is doing follows from where the sources are, and those are blocks.
##
## Gearing is not here either. A gearbox is a block that reads one line and drives another at a
## different speed, which a mod writes in about six lines - and the engine then has no opinion about
## what gear ratios exist.

const Links = preload("res://engine/server/links.gd")

const MAX_NETWORK := 2048
## Two speeds this close count as the same: floating point, and a mod computing a ratio should not jam
## its own machine by a rounding error.
const SAME := 0.001

var server

var units := {}
var _sources := {}  # unit -> node key -> value
var _driven := {}  # unit -> node key -> value (0 when jammed or unpowered)
var _jammed := {}  # unit -> node key -> true
var _nodes := {}
var _handlers := {}
var _dirty := {}


func _init(game_server) -> void:
	server = game_server


func register_unit(unit: String, owner := "engine") -> bool:
	if unit.is_empty() or units.has(unit):
		push_error("Invalid or duplicate drive '%s'" % unit)
		return false
	units[unit] = {"name": unit, "owner": owner}
	_sources[unit] = {}
	_driven[unit] = {}
	_jammed[unit] = {}
	_dirty[unit] = {}
	return true


## Told when what a face is driven at changes: {realm, position, face, unit, value, jammed}.
func on_changed(unit: String, handler: Callable) -> void:
	_handlers[unit] = handler


## This face drives at `value` - a speed, and a sign for which way round. 0 stops driving.
func set_source(unit: String, node: Dictionary, value: float) -> void:
	if not units.has(unit):
		push_error("No such drive '%s'" % unit)
		return
	var key := _key(node)
	if is_equal_approx(float(_sources[unit].get(key, 0.0)), value):
		return
	if absf(value) > SAME:
		_sources[unit][key] = value
		_nodes[key] = node.duplicate()
	else:
		_sources[unit].erase(key)
	_dirty[unit][key] = true


## What this face is being driven at. Zero when nothing drives it, and zero when the line is jammed -
## a jammed line does not turn.
func value_at(unit: String, node: Dictionary) -> float:
	return float(_driven.get(unit, {}).get(_key(node), 0.0))


## Whether this face is on a line that two sources are fighting over.
func jammed_at(unit: String, node: Dictionary) -> bool:
	return _jammed.get(unit, {}).has(_key(node))


func link_changed(a: Dictionary, b: Dictionary) -> void:
	for unit: String in units:
		_dirty[unit][_key(a)] = true
		_dirty[unit][_key(b)] = true


func settle() -> void:
	for unit: String in units:
		var pending: Dictionary = _dirty[unit]
		if pending.is_empty():
			continue
		_dirty[unit] = {}
		var done := {}
		for key: String in pending:
			if done.has(key) or not _nodes.has(key):
				continue
			var network: Dictionary = server.links.reachable(_nodes[key], MAX_NETWORK)
			for member: String in network:
				done[member] = true
			_resolve(unit, network)


## One line: find what is driving it, and whether they agree.
func _resolve(unit: String, network: Dictionary) -> void:
	var value := 0.0
	var driving := 0
	var jammed := false
	for key: String in network:
		if not _sources[unit].has(key):
			continue
		var theirs := float(_sources[unit][key])
		driving += 1
		if driving == 1:
			value = theirs
		elif absf(theirs - value) > SAME:
			# Not an average. Two things are fighting and somebody should be told which.
			jammed = true
	if jammed:
		value = 0.0
	for key: String in network:
		var was := float(_driven[unit].get(key, 0.0))
		var was_jammed: bool = _jammed[unit].has(key)
		if is_equal_approx(was, value) and was_jammed == jammed:
			continue
		if absf(value) > SAME:
			_driven[unit][key] = value
		else:
			_driven[unit].erase(key)
		if jammed:
			_jammed[unit][key] = true
		else:
			_jammed[unit].erase(key)
		if not _nodes.has(key):
			continue
		var node: Dictionary = _nodes[key]
		# Whoever is watching sees the wheel change speed. Sent on change rather than per tick: a
		# wheel turns constantly but rarely changes how fast, and the client animates from the number.
		server.drive_changed(node, value)
		var handler: Callable = _handlers.get(unit, Callable())
		if handler.is_valid():
			handler.call({"realm": node.realm, "position": node.position, "face": node.face,
				"unit": unit, "value": value, "jammed": jammed})


func _key(node: Dictionary) -> String:
	return Links.node_key(String(node.get("realm", "")), node.get("position", Vector3i.ZERO), int(node.get("face", 0)))
