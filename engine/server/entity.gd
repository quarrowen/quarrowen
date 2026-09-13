extends RefCounted
## A server-side entity: mob, projectile, dropped item stack or mod object. Mods receive these in
## events and from spawn_entity; members above "Engine bookkeeping" are the supported surface.

const EntityPhysics = preload("res://engine/shared/entity_physics.gd")

var id := 0
## Type id (EntityRegistry index) and its full server-side definition.
var type := 0
var def: Dictionary
var body := EntityPhysics.Body.new()
var yaw := 0.0
var health := 0.0
## Free-form data owned by mods; saved with persistent entities. Namespace your keys.
var data := {}
## Seconds since spawning.
var age := 0.0
var removed := false
## Projectiles: the ServerPlayer or entity that fired it (never persisted).
var owner = null
## Dropped item stacks.
var item_id := 0
var item_count := 0

# Engine bookkeeping.
var pickup_delay := 0.0
var target = null  # ServerPlayer being chased
var goal := Vector3.INF  # mod-assigned walk target
var wander_direction := Vector2.ZERO
var wander_timer := 0.0
var flee_timer := 0.0
var flee_from := Vector3.ZERO
var attack_timer := 0.0
var hurt_timer := 0.0
var think_timer := 0.0
var sleep_ticks := 0
var dirty := true  # moved since the last replication round
var dying := false

var _manager


func _init(manager, entity_id: int, type_def: Dictionary) -> void:
	_manager = manager
	id = entity_id
	def = type_def
	type = type_def.id
	body.half_width = def.width * 0.5
	body.height = def.height
	health = def.health


# --- Mod API ------------------------------------------------------------------------------------

var type_name: String:
	get:
		return def.name

var position: Vector3:
	get:
		return body.position
	set(value):
		body.position = value
		body.velocity = Vector3.ZERO
		wake()

var velocity: Vector3:
	get:
		return body.velocity
	set(value):
		body.velocity = value
		wake()

var max_health: float:
	get:
		return def.health

var on_ground: bool:
	get:
		return body.on_ground


func is_alive() -> bool:
	return not removed and not dying


func remove() -> void:
	_manager.remove(self)


## Deals damage as if from `attacker` (a ServerPlayer, entity or null). Returns true if it applied.
func damage(amount: float, attacker = null, cause := "magic") -> bool:
	return _manager.damage(self, amount, cause, attacker)


func heal(amount: float) -> void:
	if def.health > 0.0 and is_alive():
		health = minf(health + amount, def.health)


## Makes a mob walk toward `pos` (overrides wandering); Vector3.INF clears it.
func set_goal(pos: Vector3) -> void:
	goal = pos
	wake()


## Adds velocity (e.g. knockback, launch pads).
func push(impulse: Vector3) -> void:
	body.velocity += impulse
	wake()


func wake() -> void:
	sleep_ticks = 0
	dirty = true


## Box enclosing the entity, for hit tests.
func aabb() -> AABB:
	return AABB(body.position - Vector3(body.half_width, 0.0, body.half_width), Vector3(body.half_width * 2.0, body.height, body.half_width * 2.0))
