extends RefCounted
## Things you can sit on and steer: a boat, a cart, a horse, a glider.
##
## An entity type with a `vehicle` block becomes rideable:
##
##     api.register_entity("boat", {"kind": "mob", "model": "models/boat.glb", "health": 20,
##         "ai": {"preset": "none"},
##         "vehicle": {"seats": 2, "speed": 6.0, "turn_speed": 3.0, "floats": true, "seat_height": 0.35}})
##
## **The rider stops simulating themselves.** A player on a vehicle is the third case of something the
## server already does twice - a dead player and a sleeping one both drain their input queue and stay
## put - so riding slots in beside them rather than threading a new idea through the physics. Their
## position comes from the vehicle; their input becomes steering.
##
## That also means **the player's own physics never changes**, which matters more than it sounds:
## `player_physics.gd` and `physics.rs` have to agree step for step or the client rubber-bands, and a
## vehicle that avoided touching either is a vehicle that cannot break walking.
##
## **Steering is the input that already exists.** Forward and back on the stick is throttle, the rider's
## own yaw is where the vehicle turns towards, sneak gets off. Nothing new crosses the wire except
## "you are riding that", so the input format is untouched.
##
## What stays the mod's: what vehicles exist, what they look like, how fast, whether they float, and
## whether you need a saddle. The engine knows a seat, a throttle and a heading.

const ServerPlayer = preload("res://engine/server/server_player.gd")

## Per vehicle. More than a few and the seat offsets stop meaning anything.
const MAX_SEATS := 6
## How far a player may be from a vehicle and still get on it.
const REACH := 4.0

var server


func _init(game_server) -> void:
	server = game_server


## The vehicle block of an entity type, or {}.
static func config(def: Dictionary) -> Dictionary:
	var v = def.get("vehicle")
	if not (v is Dictionary):
		return {}
	return {
		"seats": clampi(int(v.get("seats", 1)), 1, MAX_SEATS),
		"speed": clampf(float(v.get("speed", 5.0)), 0.0, 40.0),
		"turn_speed": clampf(float(v.get("turn_speed", 3.0)), 0.1, 20.0),
		# A boat sits on the water instead of sinking through it. Anything else falls normally.
		"floats": bool(v.get("floats", false)),
		"seat_height": clampf(float(v.get("seat_height", 0.4)), -2.0, 4.0),
		# Whether a passenger who is not driving can steer. A cart pulled by somebody else cannot.
		"driver_only": bool(v.get("driver_only", true)),
	}


func config_of(entity) -> Dictionary:
	return config(entity.def) if entity != null else {}


func is_vehicle(entity) -> bool:
	return not config_of(entity).is_empty()


## Who is aboard, as player ids. Kept on the entity so it is saved with it: a boat you left at a jetty
## is empty when you come back, which is right, but the boat is still there.
static func riders_of(entity) -> Array:
	var riders = entity.data.get("riders")
	return riders if riders is Array else []


## Puts a player aboard. Refused when it is full, too far away, or they are already riding something.
func mount(player, entity) -> bool:
	var c := config_of(entity)
	if player == null or c.is_empty() or not entity.is_alive():
		return false
	if player.riding > 0 or player.dead:
		return false
	if player.state.position.distance_to(entity.body.position) > REACH + float(entity.def.width):
		return false
	var riders := riders_of(entity)
	if riders.size() >= int(c.seats):
		return false
	var ev: Dictionary = server.emit("vehicle_mount", {"player": player, "entity": entity, "cancelled": false})
	if ev.cancelled:
		return false
	riders = riders.duplicate()
	riders.append(String(player.player_id))
	entity.data["riders"] = riders
	entity.data["no_despawn"] = true  # a boat that vanished while you sailed it would be quite a thing
	player.riding = int(entity.id)
	player.input_queue.clear()  # anything queued was about walking, not steering
	_seat(player, entity, c)
	server.tell_riding(player)
	return true


## Takes a player off. `to` is where to put them down; by default beside the vehicle rather than inside
## it, because standing inside a boat's own box pushes you through the floor.
func dismount(player, to = null) -> bool:
	if player == null or player.riding <= 0:
		return false
	var entity = server.entities.entities.get(player.riding)
	player.riding = 0
	if entity != null:
		var riders := riders_of(entity).duplicate()
		riders.erase(String(player.player_id))
		entity.data["riders"] = riders
		var side: Vector3 = to if to is Vector3 else entity.body.position + Vector3(cos(entity.yaw), 0.6, -sin(entity.yaw)) * (float(entity.def.width) + 0.6)
		player.state.position = side
		player.state.velocity = Vector3.ZERO
		server.emit("vehicle_dismount", {"player": player, "entity": entity})
	player.input_queue.clear()
	server.tell_riding(player)
	return true


## Everybody off, for a vehicle that is being removed or has died.
func empty(entity) -> void:
	for player_id in riders_of(entity).duplicate():
		var player = server.player_by_id(String(player_id))
		if player != null:
			dismount(player)
	entity.data["riders"] = []


func _seat(player, entity, c: Dictionary) -> void:
	var riders := riders_of(entity)
	var index := maxi(riders.find(String(player.player_id)), 0)
	# Seats run front to back along the vehicle's own heading, so two riders are not inside each other.
	var back := -1.0 * index * 0.8
	var offset := Vector3(-sin(entity.yaw) * back, float(c.seat_height), -cos(entity.yaw) * back)
	player.state.position = entity.body.position + offset
	player.state.velocity = Vector3.ZERO
	player.state.on_ground = true  # they are standing on the thing, so no falling and no fall damage


## The rider's share of a server tick, called instead of walking them. Returns after draining the input
## queue either way, so the client's prediction queue does not stall.
func simulate(player) -> void:
	var entity = server.entities.entities.get(player.riding)
	if entity == null or not entity.is_alive():
		dismount(player)
		return
	var c := config_of(entity)
	var driver: bool = riders_of(entity).find(String(player.player_id)) == 0
	var throttle := 0.0
	var wants_off := false
	for input in player.input_queue:
		wants_off = wants_off or input.sneak
		if driver or not bool(c.driver_only):
			throttle = clampf(input.move.y, -1.0, 1.0)
		player.last_processed_seq = input.seq
	player.input_queue.clear()
	if wants_off:
		dismount(player)
		return
	if driver or not bool(c.driver_only):
		_steer(entity, player, c, throttle)
	_seat(player, entity, c)


## Turns the vehicle towards where the rider is looking and pushes it along its own heading. Steering
## by look rather than by a left/right key because a child already knows how to point.
func _steer(entity, player, c: Dictionary, throttle: float) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var turn := wrapf(float(player.yaw) - entity.yaw, -PI, PI)
	entity.yaw += clampf(turn, -float(c.turn_speed) * dt, float(c.turn_speed) * dt)
	var forward := Vector3(-sin(entity.yaw), 0.0, -cos(entity.yaw))
	var wanted := forward * throttle * float(c.speed)
	entity.body.velocity.x = wanted.x
	entity.body.velocity.z = wanted.z
	if bool(c.floats) and entity.body.in_liquid:
		# Sits on the surface rather than sinking. Only upwards: a boat should still fall off a waterfall.
		entity.body.velocity.y = maxf(entity.body.velocity.y, 0.0)
	entity.wake()
