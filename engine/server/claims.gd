extends RefCounted
## Keeping part of the world awake when nobody is standing in it, and the budget that stops one player
## doing it to everybody else.
##
## A pump in a far-off place feeding a tank back at the base is the ordinary case, and it is one of the
## things that **cannot be caught up afterwards**: what it did depended on the rest of the world while
## it was doing it. So it either runs or it did not happen, and running costs somebody something.
##
## **The budget is measured, not counted** (decided with the user, 2026-09-19). A limit of "four chunks
## each" is generous to the player causing the problem and mean to everybody else: two chunks of
## sorting machine cost more than twenty of wheat. So each claim is charged what its chunks actually
## spend in block tick handlers - which is a measurement, because a block tick knows where it is - and
## the host sets how much of a tick all the claims together may have.
##
## When that is exceeded:
##
## - **The most expensive claim is paused first.** Not the oldest and not the newest. One runaway
##   machine should stop before ten modest ones, and the player who built the expensive thing is the
##   one who can do something about it.
## - **They are told, in plain words, where it is.** A world that silently stops working is a bug
##   report; a world that says "your workshop went to sleep, it was doing too much" is a game telling a
##   child something true.
## - **Nothing is ever deleted.** Pausing stops the ticking; the blocks and everything in them stay
##   exactly as they were. The engine does not get to destroy what somebody built because it was slow.

const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

## How often claims are weighed. Long enough that a brief spike does not pause somebody's base, short
## enough that a runaway does not have a minute to spoil the tick for everyone.
const WEIGH_INTERVAL := 5.0
## Chunks one claim may hold. A ceiling on the shape of a claim, not on its cost - that is the budget's
## job - so that a single claim cannot be the whole world however cheap it looks.
const MAX_CHUNKS := 64

var server
## The share of a tick, in microseconds, that all the claims on this server may have between them.
## Two milliseconds of a sixteen millisecond tick by default: enough for a few real factories, little
## enough that the people actually playing keep the rest.
var budget_usec := 2000

var claims := {}  # id -> {realm, chunks: {Vector2i}, owner, player_id, name, cost, paused}
var _next_id := 1
var _timer := 0.0


func _init(game_server) -> void:
	server = game_server


## Keeps chunks awake around a position. `owner` is the mod; `player_id` is whoever should be told if
## it has to be paused, and `display` is what to call the place when telling them.
func add(realm_id: String, centre: Vector3i, radius: int, options := {}) -> int:
	var chunks := {}
	var middle := VoxelWorld.chunk_coord_at(centre.x, centre.z)
	radius = clampi(radius, 0, 8)
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if chunks.size() < MAX_CHUNKS:
				chunks[middle + Vector2i(x, z)] = true
	var id := _next_id
	_next_id += 1
	claims[id] = {"realm": realm_id, "chunks": chunks, "owner": String(options.get("owner", "engine")),
		"player_id": String(options.get("player_id", "")), "name": String(options.get("name", "a machine")),
		"centre": centre, "cost": 0, "paused": false}
	server.mark_simulation_stale()
	return id


func remove(id: int) -> bool:
	if not claims.erase(id):
		return false
	server.mark_simulation_stale()
	return true


## The chunks a realm is keeping awake on somebody's behalf. Paused claims contribute nothing, which is
## the whole of what pausing means.
func awake_chunks(realm_id: String) -> Dictionary:
	var out := {}
	for id: int in claims:
		var claim: Dictionary = claims[id]
		if claim.paused or claim.realm != realm_id:
			continue
		for coord: Vector2i in claim.chunks:
			out[coord] = true
	return out


## Charges each claim what its chunks actually spent, and pauses the dearest until the total fits.
func update(delta: float) -> void:
	_timer += delta
	if _timer < WEIGH_INTERVAL:
		return
	_timer = 0.0
	var total := 0
	var live := []
	for id: int in claims:
		var claim: Dictionary = claims[id]
		var realm = server.realms.get(claim.realm)
		if realm == null:
			continue
		var spent := 0
		for coord: Vector2i in claim.chunks:
			spent += int(realm.block_ticks.cost_by_chunk.get(coord, 0))
		# Per tick, averaged over the weighing window, which is what the budget is expressed in.
		claim.cost = roundi(float(spent) / (WEIGH_INTERVAL * Engine.physics_ticks_per_second))
		if not claim.paused:
			total += claim.cost
			live.append(id)
	for realm in server.realms.values():
		realm.block_ticks.cost_by_chunk.clear()
	if total <= budget_usec or live.is_empty():
		return
	# Dearest first: one runaway stops before ten modest ones, and whoever built it can see why.
	live.sort_custom(func(a: int, b: int) -> bool: return int(claims[a].cost) > int(claims[b].cost))
	for id in live:
		if total <= budget_usec:
			break
		var claim: Dictionary = claims[id]
		claim.paused = true
		total -= int(claim.cost)
		server.dev_log.add("warn", claim.owner, "Paused a claim at %s: it was using %d us of tick" % [claim.centre, claim.cost])
		_tell(claim)
		server.emit("claim_paused", {"id": id, "realm": claim.realm, "position": claim.centre,
			"name": claim.name, "cost": claim.cost, "owner": claim.owner})
	server.mark_simulation_stale()


## Lets a paused claim run again - a player tidied their machine, or an admin raised the budget.
func resume(id: int) -> bool:
	var claim: Dictionary = claims.get(id, {})
	if claim.is_empty() or not claim.paused:
		return false
	claim.paused = false
	claim.cost = 0
	server.mark_simulation_stale()
	return true


## Plain words, and where. "Something stopped working" is a bug report; this is a game telling a child
## something true about a thing they built.
func _tell(claim: Dictionary) -> void:
	if String(claim.player_id).is_empty():
		return
	for p in server.players.values():
		if p.player_id == claim.player_id:
			p.send_message("Your %s at %d, %d went to sleep - it was doing too much to keep running while you are away. Nothing has been lost."
				% [claim.name, int(claim.centre.x), int(claim.centre.z)])
			return
