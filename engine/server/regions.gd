extends RefCounted
## A box in the world that tells a mod when somebody walks into it and when they walk out again.
##
##     var id := api.add_region("answer_a", Vector3(10, 64, 10), Vector3(13, 67, 13), {"data": {"letter": "a"}})
##     api.on("region_entered", func(ev): ...)   # {player, region, id, data}
##     api.on("region_left", func(ev): ...)
##
## **Why a box and not a field.** `fields` is the nearest thing that existed and it is the wrong shape
## three ways: it is a *circle*, it must do something (damage, healing, a condition - a field that only
## watches is refused), and it must be visible, because an invisible thing on the floor that hurts a
## child is a trick rather than a hazard. A region does nothing and shows nothing; its whole job is to
## say *who is inside*. Checkpoints, goal lines, safe zones, the pad by a lobby door and the answer
## platforms of a word game are all boxes, and none of them wants a puff of smoke. (2026-09-28)
##
## **Entered and left, not "is inside".** A mod that had to poll would ask every tick for every player,
## which is the loop this file exists to write once - and would still miss somebody who crossed a
## corner between two ticks. The events fire on the *change*, so a handler runs when something actually
## happened.
##
## What stays the mod's: what a region means. The engine knows a box, who is in it, and when that
## changed.

const ServerPlayer = preload("res://engine/server/server_player.gd")

## Enough for a lobby full of doors and a quiz floor of answers; few enough that the sweep below stays
## a rounding error. Matches `fields`, for the same reason and with the same arithmetic behind it.
const MAX_REGIONS := 256
## A box may not be larger than this on a side. Not a performance limit - the check is six compares
## whatever the size - but a region the size of a world is almost always a mistake, and one that
## presents as "everybody is always inside it".
const MAX_SIDE := 512.0

var server
## id -> {id, name, owner, realm, lo: Vector3, hi: Vector3, data: Dictionary, inside: {player_id: true}}
var regions := {}
var _next_id := 1


func _init(game_server) -> void:
	server = game_server


## Adds a box. Returns its id, or 0 if there was no room or the box was refused.
func add(region_name: String, from: Vector3, to: Vector3, options := {}, owner := "engine") -> int:
	if regions.size() >= MAX_REGIONS:
		push_warning("[regions] %d regions already; '%s' was not added" % [MAX_REGIONS, region_name])
		return 0
	var lo := Vector3(minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z))
	var hi := Vector3(maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z))
	var side := hi - lo
	if side.x > MAX_SIDE or side.y > MAX_SIDE or side.z > MAX_SIDE:
		push_warning("[regions] '%s' is larger than %d on a side" % [region_name, int(MAX_SIDE)])
		return 0
	var id := _next_id
	_next_id += 1
	regions[id] = {"id": id, "name": region_name, "owner": owner,
		"realm": String(options.get("realm", "")), "lo": lo, "hi": hi,
		"data": options.get("data", {}) if options.get("data") is Dictionary else {},
		"inside": {}}
	return id


## Removes one. Anybody standing in it is told they left first, because a mod that opened a door on
## `region_entered` has to be able to close it - and "the region went away" is not a thing it can see.
func remove(id: int) -> bool:
	var region: Dictionary = regions.get(id, {})
	if region.is_empty():
		return false
	for player_id: String in (region.inside as Dictionary).keys():
		var p = _player_by_id(player_id)
		if p != null:
			_emit(region, p, false)
	regions.erase(id)
	return true


## Every region a point is inside, as their ids.
func at(position: Vector3, realm_id := "") -> Array:
	var out := []
	for id: int in regions:
		var region: Dictionary = regions[id]
		if String(region.realm) == realm_id and _holds(region, position):
			out.append(id)
	return out


## Who is standing in one right now, as players.
func players_in(id: int) -> Array:
	var region: Dictionary = regions.get(id, {})
	if region.is_empty():
		return []
	var out := []
	for player_id: String in region.inside:
		var p = _player_by_id(player_id)
		if p != null:
			out.append(p)
	return out


## Drops everything a mod added, for a reload.
func forget(owner: String) -> void:
	for id: int in regions.keys():
		if String(regions[id].owner) == owner:
			regions.erase(id)


## One sweep: every player against every box, firing on the change.
##
## **Called from the server tick and deliberately not budgeted.** A box test is six float compares, so
## the whole sweep is players times regions - sixty players in a lobby of two hundred boxes is twelve
## thousand compares, which is less work than one chunk mesh and far less than the machinery it would
## take to be clever about it. If that stops being true the answer is a grid, not a time slice: a
## region that is only checked *sometimes* misses people, and missing people is the one failure this
## capability cannot have.
func tick() -> void:
	if regions.is_empty():
		return
	for p: ServerPlayer in server.players.values():
		var realm_id: String = server.realm_of(p).id
		var here := p.state.position
		for id: int in regions:
			var region: Dictionary = regions[id]
			if String(region.realm) != realm_id:
				# Somewhere else entirely. If they were in it, they have left it - walking through a
				# portal is leaving every box in the world you came from.
				if (region.inside as Dictionary).has(p.player_id):
					(region.inside as Dictionary).erase(p.player_id)
					_emit(region, p, false)
				continue
			var was: bool = (region.inside as Dictionary).has(p.player_id)
			var now := _holds(region, here)
			if now == was:
				continue
			if now:
				(region.inside as Dictionary)[p.player_id] = true
			else:
				(region.inside as Dictionary).erase(p.player_id)
			_emit(region, p, now)


## Someone has gone for good: forget them, without telling anybody they left. A player who logs out is
## not a player who walked out, and a mod that opened a gate for them has nothing left to close.
func drop_player(player) -> void:
	if player == null:
		return
	for id: int in regions:
		(regions[id].inside as Dictionary).erase(player.player_id)


func _holds(region: Dictionary, position: Vector3) -> bool:
	var lo: Vector3 = region.lo
	var hi: Vector3 = region.hi
	return position.x >= lo.x and position.x <= hi.x \
		and position.y >= lo.y and position.y <= hi.y \
		and position.z >= lo.z and position.z <= hi.z


func _emit(region: Dictionary, player, entered: bool) -> void:
	server.emit("region_entered" if entered else "region_left",
		{"player": player, "region": String(region.name), "id": int(region.id), "data": region.data})


func _player_by_id(player_id: String):
	for p: ServerPlayer in server.players.values():
		if p.player_id == player_id:
			return p
	return null
