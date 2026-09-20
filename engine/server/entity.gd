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
var item_data := {}

## Mobs: the AI brain (engine/server/ai/mob_brain.gd); null for other kinds.
var brain = null

# Engine bookkeeping.
var pickup_delay := 0.0
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


## How clients draw this entity: {scale (1 = normal, babies are smaller), hide: [model part name
## prefixes to hide, e.g. "wool" once sheared], tint: {part prefix: "#rrggbb"}, pose: "" | "sit"}. Merged into the current
## look and saved in data.look.
func set_look(values: Dictionary) -> void:
	var look: Dictionary = data.get("look", {}).duplicate() if data.get("look") is Dictionary else {}
	if values.has("pose"):
		look.pose = str(values.pose).left(16)
	if values.has("scale"):
		look.scale = clampf(float(values.scale), 0.05, 10.0)
	if values.get("hide") is Array:
		look.hide = (values.hide as Array).slice(0, 16).map(func(h): return str(h).left(32))
	if values.get("tint") is Dictionary:
		var tint := {}
		for key in values.tint:
			if Color.html_is_valid(str(values.tint[key])):
				tint[str(key).left(32)] = str(values.tint[key])
		look.tint = tint
	if look == data.get("look"):
		return
	data.look = look
	_manager.look_changed(self)


## False once the entity died or was removed.
func is_alive() -> bool:
	return not removed and not dying


## Removes the entity from the world (no death, no drops).
func remove() -> void:
	_manager.remove(self)


## Deals damage as if from `attacker` (a ServerPlayer, entity or null). Returns true if it applied.
##
## `cause` comes before `attacker` to match ServerPlayer.damage and EntityManager.damage. It used to be
## the other way round on this one object alone, which meant `target.damage(5, "poison")` filed the
## cause as the attacker on a creature and as the cause on a player - no error either way, because an
## attacker is untyped. Conditions had to tell the two apart rather than just calling it. (2026-09-20)
func damage(amount: float, cause := "magic", attacker = null) -> bool:
	return _manager.damage(self, amount, cause, attacker)


## Kills it outright, with drops and a death, as opposed to `remove()` which takes it away as though it
## had never been there. Player has had `kill` all along; this is the same verb for a creature.
func kill(cause := "magic") -> void:
	if not is_alive():
		return
	# Past the hurt cooldown on purpose. A kill that quietly did nothing because the creature was hit a
	# moment ago is the sort of thing a mod author debugs for an hour. (2026-09-20)
	hurt_timer = 0.0
	_manager.damage(self, health + 1000.0, cause, null)


## Puts it somewhere, stopping it dead. The same spelling as ServerPlayer.teleport, so code that moves
## "a thing" does not have to know which kind of thing it has.
func teleport(pos: Vector3) -> void:
	position = pos


## Gives back health, up to the type's maximum.
func heal(amount: float) -> void:
	if def.health > 0.0 and is_alive():
		health = minf(health + amount, def.health)


## Makes a mob walk to `pos`, overriding its behaviour until it arrives; Vector3.INF clears it.
func set_goal(pos: Vector3) -> void:
	if brain != null:
		brain.scripted_goal = pos
	wake()


## Mobs: the current enemy (a player or entity), or null.
func get_target():
	return brain.target if brain != null else null


## Mobs: attack this player or entity now (null forgets the current target).
func set_target(new_target) -> void:
	if brain != null:
		brain.set_target(new_target)


## Mobs: makes `source` more (or less) hated; the highest threat becomes the target.
func add_threat(source, amount: float) -> void:
	if brain != null:
		brain.add_threat(source, amount)


## Mobs: overrides AI settings for this mob only (see engine/server/ai/mob_config.gd).
func tune(values: Dictionary) -> void:
	if brain != null:
		brain.tune(values)


## Mobs: investigate a position as if it heard something there.
func alert(pos: Vector3) -> void:
	if brain != null:
		brain.alert(pos)


## Mobs: the home it returns to when it strays beyond its leash.
func set_home(pos: Vector3, leash := -1.0) -> void:
	if brain != null:
		brain.home = pos
		if leash >= 0.0:
			brain.tune({"leash": leash})


## Mobs: starts the named attack against the current target right away (ignores range and cooldown).
func perform_attack(attack_name: String) -> bool:
	if brain == null or brain.target == null or not brain.attack.is_empty():
		return false
	for a in brain.config.attacks:
		if a.name == attack_name:
			brain.Attacks.begin(brain, a, brain.target)
			return true
	return false


## Mobs: name of the running behaviour ("wander", "engage", "flee", ...).
func get_behavior() -> String:
	return brain.behavior if brain != null else ""


## Adds velocity (e.g. knockback, launch pads).
func push(impulse: Vector3) -> void:
	body.velocity += impulse
	wake()


## Makes a resting entity simulate again right away (after moving it from a mod).
func wake() -> void:
	sleep_ticks = 0
	dirty = true


## Box enclosing the entity, for hit tests.
func aabb() -> AABB:
	return AABB(body.position - Vector3(body.half_width, 0.0, body.half_width), Vector3(body.half_width * 2.0, body.height, body.half_width * 2.0))
