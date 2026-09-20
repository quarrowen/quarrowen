extends RefCounted
## Server entity system: spawning, mob brains (engine/server/ai), projectiles, dropped item stacks
## (pickup and merging), natural spawn rules, damage and death, replication to players and
## persistence of persistent entities inside chunk saves.

## Entity updates per unreliable packet (19 bytes each), to stay under the network MTU.
const ENTITIES_PER_PACKET := 60
const SPAWN_SLOTS := 60  # ticks over which every player gets one spawning round
const Entity = preload("res://engine/server/entity.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const MobAttacks = preload("res://engine/server/ai/mob_attacks.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const MobAI = preload("res://engine/server/ai/mob_ai.gd")
const Spawning = preload("res://engine/server/spawning.gd")
const Breeding = preload("res://engine/server/breeding.gd")
const Taming = preload("res://engine/server/taming.gd")

const MAX_ENTITIES := 2000
## Entities are replicated to players within this distance (blocks).
const VIEW_RADIUS := 64.0
## Rounds (snapshot intervals) between recomputing which entities each player can see.
const VISIBILITY_ROUNDS := 5
## Stationary entities are re-sent this often (rounds) so a lost unreliable update self-heals.
const REFRESH_ROUNDS := 20
const DESPAWN_DISTANCE := 96.0
const ITEM_LIFETIME := 300.0
const ITEM_PICKUP_DELAY := 0.6
const ITEM_MAGNET_RANGE := 2.5
const ITEM_PICKUP_RANGE := 1.1
const ITEM_MERGE_RANGE := 1.0
const HURT_INVULNERABLE := 0.45
const KNOCKBACK := 7.0
const SLEEP_AFTER_TICKS := 20
const SLEEPING_STEP_INTERVAL := 15
const PROJECTILE_OWNER_GRACE := 0.25

enum Event { HURT, DEATH, PICKUP, ATTACK, RESPAWN, WINDUP, SWING, DRAW, RELEASE }

var registry := EntityRegistry.new()
var ai: MobAI
## Live projectiles (mobs watch these to dodge).
var projectiles: Array = []
var entities := {}  # id -> Entity
## Natural spawning rules, category caps and despawning.
var spawning
## Feeding, love, babies and growing up (see engine/server/breeding.gd).
var breeding
## Owners, following, sitting and defending (see engine/server/taming.gd).
var taming

## The realm these creatures are in.
var realm
var _server
var _next_id := 1
var _round := 0
var _merge_timer := 0.0
var _spawn_slot := 0
var _removed_ids := PackedInt32Array()


## `home` is the realm these creatures live in. They path through its blocks and no one else's - without
## it every realm's mobs would think their way around the overworld's terrain. (2026-09-19)
func _init(server, home = null) -> void:
	_server = server
	realm = home
	ai = MobAI.new(server, self)
	spawning = Spawning.new(self)
	breeding = Breeding.new(self)
	taming = Taming.new(self)


# --- Spawning & removal -------------------------------------------------------------------------

## options: yaw, velocity (Vector3), data (Dictionary), owner, item (id), count, pickup_delay
func spawn(type_id: int, pos: Vector3, options := {}) -> Entity:
	if not registry.is_valid(type_id) or entities.size() >= MAX_ENTITIES or not is_finite(pos.length_squared()):
		return null
	var e := Entity.new(self, _next_id, registry.defs[type_id])
	_next_id += 1
	e.body.position = pos
	e.body.velocity = options.get("velocity", Vector3.ZERO)
	e.yaw = float(options.get("yaw", randf() * TAU))
	e.data = options.get("data", {}) if options.get("data") is Dictionary else {}
	e.owner = options.get("owner")
	e.think_timer = randf() * 0.5
	if type_id == EntityRegistry.ITEM:
		e.item_id = int(options.get("item", 0))
		e.item_count = int(options.get("count", 1))
		e.pickup_delay = float(options.get("pickup_delay", ITEM_PICKUP_DELAY))
		e.item_data = options.get("item_data", {}) if options.get("item_data") is Dictionary else {}
		if not _server.items.is_valid(e.item_id) or e.item_count <= 0:
			return null
	if e.def.kind == "mob":
		e.brain = ai.attach(e)
	elif e.def.kind == "projectile":
		projectiles.append(e)
	entities[e.id] = e
	_server.emit("entity_spawned", {"entity": e})
	return e


## Drops an item stack at `pos` with a small random toss.
func drop_item(item: int, count: int, pos: Vector3, velocity := Vector3.INF, pickup_delay := ITEM_PICKUP_DELAY, item_data := {}) -> Entity:
	if velocity == Vector3.INF:
		velocity = Vector3(randf_range(-1.5, 1.5), randf_range(3.0, 5.0), randf_range(-1.5, 1.5))
	var max_stack: int = _server.items.max_stack(item)
	var last: Entity = null
	while count > 0:
		var n := mini(count, max_stack)
		last = spawn(EntityRegistry.ITEM, pos, {"item": item, "count": n, "velocity": velocity, "pickup_delay": pickup_delay, "item_data": item_data})
		count -= n
		if last == null:
			break
	return last


func remove(e: Entity) -> void:
	# Anybody aboard is put down first: a rider left attached to an entity that no longer exists keeps
	# their position from a thing that is not there.
	if e.data.get("riders") is Array and not (e.data.riders as Array).is_empty():
		_server.vehicles.empty(e)
	if e.removed:
		return
	e.removed = true
	entities.erase(e.id)
	if e.brain != null:
		ai.detach(e)
	elif e.def.kind == "projectile":
		projectiles.erase(e)
	_removed_ids.append(e.id)
	_server.emit("entity_removed", {"entity": e})


func in_radius(center: Vector3, radius: float, type_id := -1) -> Array:
	var out := []
	var r2 := radius * radius
	for e: Entity in entities.values():
		if (type_id < 0 or e.type == type_id) and e.body.position.distance_squared_to(center) <= r2 and e.is_alive():
			out.append(e)
	return out


# --- Tick ---------------------------------------------------------------------------------------

## Microseconds spent in each part of the last tick (read by the server's --metrics).
var last_sections := {}


func tick(delta: float) -> void:
	var world = realm.world
	var t0 := Time.get_ticks_usec()
	ai.tick(delta)
	var t1 := Time.get_ticks_usec()
	var moving: Array[Entity] = []
	for e: Entity in entities.values():
		if e.removed:
			continue
		e.age += delta
		e.hurt_timer = maxf(e.hurt_timer - delta, 0.0)
		e.attack_timer = maxf(e.attack_timer - delta, 0.0)
		if e.def.lifetime > 0.0 and e.age > e.def.lifetime or e.type == EntityRegistry.ITEM and e.age > ITEM_LIFETIME:
			remove(e)
			continue
		if e.body.position.y < -64.0:
			remove(e)
			continue
		if not world.has_chunk(VoxelWorld.chunk_coord_of(e.body.position)):
			continue  # frozen until its chunk is loaded again
		if e.def.kind == "projectile":
			_step_projectile(e, delta)
			continue
		if _needs_step(e):
			moving.append(e)
	var t2 := Time.get_ticks_usec()
	_step_bodies(moving, delta)
	for e in moving:
		if e.type == EntityRegistry.ITEM and not e.removed:
			_collect(e)
	var t3 := Time.get_ticks_usec()
	_merge_timer += delta
	if _merge_timer >= 1.0:
		_merge_timer = 0.0
		_merge_items()
		breeding.update(1.0)
		_contact_damage()
		taming.update()
	var t4 := Time.get_ticks_usec()
	# Each player's spawning round comes once a second, spread over the ticks (a sixtieth of the players each).
	_spawn_slot = (_spawn_slot + 1) % SPAWN_SLOTS
	var slice := []
	for p in _server.players.values():
		if absi(p.peer_id) % SPAWN_SLOTS == _spawn_slot:
			slice.append(p)
	if not slice.is_empty():
		spawning.run(slice)
	spawning.despawn(_spawn_slot, SPAWN_SLOTS)
	var t5 := Time.get_ticks_usec()
	last_sections = {"ai": t1 - t0, "bookkeeping": t2 - t1, "bodies": t3 - t2, "housekeeping": t4 - t3, "spawning": t5 - t4}


## Resting bodies (on the ground, not moving) only re-check their support every few ticks.
func _needs_step(e: Entity) -> bool:
	var b := e.body
	if b.on_ground and b.velocity.length_squared() < 0.0001 and not b.in_liquid:
		e.sleep_ticks += 1
		return e.sleep_ticks <= SLEEP_AFTER_TICKS or e.sleep_ticks % SLEEPING_STEP_INTERVAL == 0
	e.sleep_ticks = 0
	return true


## Physics for all awake bodies: one native call for the whole batch when the extension is loaded.
func _step_bodies(list: Array[Entity], delta: float) -> void:
	if list.is_empty():
		return
	var world = realm.world
	var before := PackedVector3Array()
	before.resize(list.size())
	if world.native:
		var packed := PackedFloat32Array()
		packed.resize(list.size() * 11)
		for i in list.size():
			var b := list[i].body
			var o := i * 11
			before[i] = b.position
			packed[o] = b.position.x
			packed[o + 1] = b.position.y
			packed[o + 2] = b.position.z
			packed[o + 3] = b.velocity.x
			packed[o + 4] = b.velocity.y
			packed[o + 5] = b.velocity.z
			packed[o + 6] = b.half_width
			packed[o + 7] = b.height
			packed[o + 8] = list[i].def.gravity
			packed[o + 9] = list[i].def.drag
			packed[o + 10] = 1.0 if b.on_ground else 0.0
		var out: PackedFloat32Array = world.native.step_entities(packed, delta)
		for i in list.size():
			var b := list[i].body
			var o := i * 7
			b.position = Vector3(out[o], out[o + 1], out[o + 2])
			b.velocity = Vector3(out[o + 3], out[o + 4], out[o + 5])
			var flags := int(out[o + 6])
			b.on_ground = flags & 1 != 0
			b.blocked = flags & 2 != 0
			b.in_liquid = flags & 4 != 0
	else:
		var solid: PackedByteArray = _server.registry.solid_lut
		var liquid: PackedByteArray = _server.registry.liquid_lut
		for i in list.size():
			before[i] = list[i].body.position
			EntityPhysics.step(list[i].body, world, solid, liquid, delta, list[i].def.gravity, list[i].def.drag,
				_server.registry.shape_lut)
	for i in list.size():
		var e := list[i]
		var b := e.body
		if e.type == EntityRegistry.ITEM and b.on_ground:
			b.velocity.x *= maxf(0.0, 1.0 - 10.0 * delta)
			b.velocity.z *= maxf(0.0, 1.0 - 10.0 * delta)
		if b.position.distance_squared_to(before[i]) > 0.000001:
			e.dirty = true


# --- Projectiles --------------------------------------------------------------------------------

func _step_projectile(e: Entity, delta: float) -> void:
	var b := e.body
	b.velocity.y -= e.def.gravity * delta
	if e.def.drag > 0.0:
		b.velocity *= maxf(0.0, 1.0 - e.def.drag * delta)
	var motion := b.velocity * delta
	var distance := motion.length()
	e.dirty = true
	if distance < 0.00001:
		return
	var dir := motion / distance
	var from := b.position
	var hit := {"t": INF}
	var ray: Dictionary = VoxelRaycast.cast(realm.world, _server.registry.solid_lut, from, dir, distance)
	if ray.hit:
		var cell := Vector3(ray.position)
		var t := EntityPhysics.segment_hits_box(from, dir, distance + 0.001, cell, cell + Vector3.ONE)
		hit = {"t": maxf(t, 0.0), "kind": "block", "block": ray.position}
	var skip_owner := e.age < PROJECTILE_OWNER_GRACE
	for p in _server.players.values():
		if p.dead or (skip_owner and p == e.owner):
			continue
		var box := AABB(p.state.position - Vector3(PlayerPhysics.HALF_WIDTH, 0, PlayerPhysics.HALF_WIDTH), Vector3(PlayerPhysics.HALF_WIDTH * 2.0, PlayerPhysics.HEIGHT, PlayerPhysics.HALF_WIDTH * 2.0))
		var t := EntityPhysics.segment_hits_box(from, dir, distance, box.position, box.end)
		if t >= 0.0 and t < hit.t:
			hit = {"t": t, "kind": "player", "target": p}
	var owner_brain = e.owner.brain if e.owner != null and e.owner.get("brain") != null else null
	for other: Entity in entities.values():
		if other == e or other.def.kind != "mob" or not other.is_alive() or (skip_owner and other == e.owner):
			continue
		if owner_brain != null and other.brain != null and ai.allied(owner_brain, other.brain):
			continue  # no friendly fire between allied mobs
		var box := other.aabb()
		var t := EntityPhysics.segment_hits_box(from, dir, distance, box.position, box.end)
		if t >= 0.0 and t < hit.t:
			hit = {"t": t, "kind": "entity", "target": other}
	if hit.t == INF:
		b.position += motion
		if motion.length_squared() > 0.0001:
			e.yaw = atan2(-dir.x, -dir.z)
		return
	b.position = from + dir * hit.t
	ai.make_noise(b.position, 8.0, e.owner, hit.kind != "block")
	var ev: Dictionary = _server.emit("projectile_hit", {"entity": e, "owner": e.owner, "hit": hit.kind,
		"target": hit.get("target"), "position": b.position, "block": hit.get("block", Vector3i.ZERO),
		"damage": float(e.data.get("damage", e.def.damage)), "cancelled": false, "keep": false})
	if not ev.cancelled and ev.damage > 0.0 and hit.has("target"):
		if hit.kind == "player":
			_server.damage_player(hit.target, ev.damage, "projectile", e.owner if e.owner != null else e, dir)
		else:
			damage(hit.target, ev.damage, "projectile", e.owner if e.owner != null else e, dir)
		# Anything a projectile was sent out carrying: a mob's venom shot, or a mod's own tipped arrow.
		if e.data.get("condition") is Dictionary:
			MobAttacks.apply_condition(_server, hit.target, e.data.condition)
	if not ev.keep:
		remove(e)


# --- Items --------------------------------------------------------------------------------------

func _collect(e: Entity) -> void:
	if e.age < e.pickup_delay:
		return
	var center := e.body.position + Vector3(0, 0.12, 0)
	for p in _server.players.values():
		if p.dead:
			continue
		var chest: Vector3 = p.state.position + Vector3(0, 0.9, 0)
		var dist := chest.distance_to(center)
		if dist > ITEM_MAGNET_RANGE or p.inventory.space_for(e.item_id, _server.items.max_stack(e.item_id), e.item_data) <= 0:
			continue
		if dist > ITEM_PICKUP_RANGE:
			var pull := (chest - center).normalized() * 9.0
			e.body.velocity = e.body.velocity.lerp(pull, 0.35)
			e.wake()
			return
		var ev: Dictionary = _server.emit("item_pickup", {"player": p, "entity": e, "item": e.item_id, "count": e.item_count, "data": e.item_data, "cancelled": false})
		if ev.cancelled:
			continue
		var left: int = p.inventory.add(e.item_id, e.item_count, _server.items.max_stack(e.item_id), e.item_data)
		p.sync_inventory()
		_server.broadcast_entity_event(e, Event.PICKUP, p.peer_id)
		_server.play_sound_at("engine:pickup", center, 0.6, randf_range(0.9, 1.5))
		if left <= 0:
			remove(e)
		else:
			e.item_count = left
		return


func _merge_items() -> void:
	var items := []
	for e: Entity in entities.values():
		if e.type == EntityRegistry.ITEM and not e.removed and e.body.on_ground:
			items.append(e)
	if items.size() < 2 or items.size() > 400:
		return
	var r2 := ITEM_MERGE_RANGE * ITEM_MERGE_RANGE
	for i in items.size():
		var a: Entity = items[i]
		if a.removed:
			continue
		for j in range(i + 1, items.size()):
			var b: Entity = items[j]
			if b.removed or b.item_id != a.item_id or a.body.position.distance_squared_to(b.body.position) > r2:
				continue
			if a.item_count + b.item_count > _server.items.max_stack(a.item_id) or a.item_data != b.item_data:
				continue
			a.item_count += b.item_count
			a.age = minf(a.age, b.age)
			remove(b)


# --- Damage -------------------------------------------------------------------------------------

## Returns true if damage was applied. `direction` pushes the entity (defaults to away from attacker).
func damage(e: Entity, amount: float, cause: String, attacker = null, direction := Vector3.ZERO) -> bool:
	if not e.is_alive() or e.def.health <= 0.0 or amount <= 0.0 or e.hurt_timer > 0.0:
		return false
	var ev: Dictionary = _server.emit("entity_damage", {"entity": e, "amount": amount, "cause": cause, "attacker": attacker, "cancelled": false})
	if ev.cancelled or float(ev.amount) <= 0.0:
		return false
	e.health -= float(ev.amount)
	e.hurt_timer = HURT_INVULNERABLE
	var source := _attacker_position(attacker)
	if direction == Vector3.ZERO and source != Vector3.INF:
		direction = e.body.position - source
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		var strength: float = KNOCKBACK * (1.0 - e.def.knockback_resistance)
		e.body.velocity = direction.normalized() * strength + Vector3(0, 5.5 * (1.0 - e.def.knockback_resistance), 0)
	e.wake()
	if e.brain != null:
		e.brain.on_hurt(attacker, float(ev.amount))
	_server.broadcast_entity_event(e, Event.HURT, 0)
	play_sound(e, e.def.sounds.get("hurt", ""))
	if e.health <= 0.0:
		kill(e, cause, attacker)
	return true


func kill(e: Entity, cause := "magic", attacker = null) -> void:
	if not e.is_alive():
		return
	# What a mob leaves behind goes through the loot tables, so the same conditions, tuning and rare-find
	# handling apply whether it was a mob, a block or a chest (see engine/server/loot.gd).
	var drops := []
	if not e.data.get("baby", false):
		var killer = attacker if attacker != null and attacker.get("peer_id") != null else null
		drops = _server.loot.roll(_server.loot.table_for_entity(e.def), {
			"cause": "player" if killer != null else cause,
			"player": killer,
			"tool": killer.inventory.selected_item() if killer != null else 0,
			"position": e.body.position,
			"source": "entity",
		})
	var ev: Dictionary = _server.emit("entity_death", {"entity": e, "cause": cause, "attacker": attacker, "drops": drops})
	# Splitters (slimes) break into smaller mobs: split: {entity, count: [min, max]}.
	var split = e.def.get("split")
	if split is Dictionary and registry.ids.has(str(split.get("entity", ""))):
		var range_: Array = split.get("count", [2, 2]) if split.get("count") is Array and split.count.size() == 2 else [2, 2]
		for i in randi_range(int(range_[0]), int(range_[1])):
			var offset := Vector3(randf_range(-0.4, 0.4), 0.1, randf_range(-0.4, 0.4))
			spawn(registry.id_of(str(split.entity)), e.body.position + offset, {"velocity": offset * 6.0 + Vector3(0, 3, 0)})
	e.dying = true
	e.health = 0.0
	_server.broadcast_entity_event(e, Event.DEATH, 0)
	play_sound(e, e.def.sounds.get("death", ""))
	if ev.drops is Array:
		for drop in ev.drops:
			# [item, count] from an older handler, or [item, count, data] from a loot table.
			if drop is Array and drop.size() >= 2 and _server.items.is_valid(int(drop[0])):
				var data: Dictionary = drop[2] if drop.size() > 2 and drop[2] is Dictionary else {}
				drop_item(int(drop[0]), int(drop[1]), e.body.position + Vector3(0, 0.5, 0), Vector3.INF, ITEM_PICKUP_DELAY, data)
	remove(e)


static func _attacker_position(attacker) -> Vector3:
	if attacker == null:
		return Vector3.INF
	if attacker.get("state") != null:
		return attacker.state.position
	if attacker.get("body") != null:
		return attacker.body.position
	return Vector3.INF


func play_sound(e: Entity, sound_name: String) -> void:
	if not sound_name.is_empty():
		_server.play_sound_at(sound_name, e.body.position + Vector3(0, e.def.height * 0.5, 0))


# --- Natural spawning ---------------------------------------------------------------------------

## See engine/server/spawning.gd for rule keys.
func add_spawn_rule(rule: Dictionary) -> void:
	spawning.add_rule(rule)


# --- Replication --------------------------------------------------------------------------------

## Called every snapshot interval. Sends spawns/despawns for entities entering or leaving each
## player's view, and compact position updates for visible entities that moved.
func replicate(players: Array) -> void:
	_round += 1
	var removed := _removed_ids
	_removed_ids = PackedInt32Array()
	var r2 := VIEW_RADIUS * VIEW_RADIUS
	for p in players:
		var known: Dictionary = p.known_entities
		var gone := PackedInt32Array()
		for id in removed:
			if known.erase(id):
				gone.append(id)
		var spawns := []
		# Who sees what is recomputed for a fifth of the players each round (staggered by peer), not all at once.
		if (_round + absi(p.peer_id)) % VISIBILITY_ROUNDS == 0 or p.known_entities_stale:
			p.known_entities_stale = false
			for e: Entity in entities.values():
				var inside: bool = e.body.position.distance_squared_to(p.state.position) <= r2
				if inside and not known.has(e.id):
					known[e.id] = true
					spawns.append([e.id, e.type, e.body.position, e.yaw, e.item_id, e.item_count, e.data.get("look", {})])
				elif not inside and known.has(e.id):
					known.erase(e.id)
					gone.append(e.id)
		if not gone.is_empty():
			Net.s_entity_despawn.rpc_id(p.peer_id, gone)
		if not spawns.is_empty():
			Net.s_entity_spawn.rpc_id(p.peer_id, spawns)
		# Every entity's position is resent now and then (for lost updates), also staggered by peer.
		var refresh := (_round + absi(p.peer_id)) % REFRESH_ROUNDS == 0
		var buf := StreamPeerBuffer.new()
		buf.put_u16(0)
		var count := 0
		for id: int in known:
			var e: Entity = entities.get(id)
			if e == null or not (e.dirty or refresh):
				continue
			if count >= ENTITIES_PER_PACKET:
				# Unreliable packets above the MTU get fragmented and lost far more often: send what fits.
				buf.seek(0)
				buf.put_u16(count)
				Net.s_entities.rpc_id(p.peer_id, _server.tick, buf.data_array)
				buf = StreamPeerBuffer.new()
				buf.put_u16(0)
				count = 0
			buf.put_u32(e.id)
			buf.put_float(e.body.position.x)
			buf.put_float(e.body.position.y)
			buf.put_float(e.body.position.z)
			buf.put_u16(int(wrapf(e.yaw, 0.0, TAU) / TAU * 65535.0))
			buf.put_u8((1 if e.body.on_ground else 0) | (2 if e.item_count > 1 else 0))
			count += 1
		if count > 0:
			buf.seek(0)
			buf.put_u16(count)
			Net.s_entities.rpc_id(p.peer_id, _server.tick, buf.data_array)
	for e: Entity in entities.values():
		e.dirty = false


## Once a second: mobs inside blocks with contact_damage (lava) get hurt.
func _contact_damage() -> void:
	var registry_blocks = _server.registry
	for e: Entity in entities.values():
		if e.def.kind != "mob" or not e.is_alive():
			continue
		var p := e.body.position
		var block: int = realm.world.get_block(floori(p.x), floori(p.y + 0.3), floori(p.z))
		if registry_blocks.is_valid(block) and registry_blocks.defs[block].get("contact_damage") is Dictionary:
			var c: Dictionary = registry_blocks.defs[block].contact_damage
			damage(e, float(c.get("amount", 2.0)) / maxf(float(c.get("interval", 0.5)), 0.1), str(c.get("cause", "contact")))


## An entity's look changed (Entity.set_look): tell players who can see it.
func look_changed(e: Entity) -> void:
	for p in _server.players.values():
		if p.known_entities.has(e.id) and p._online():
			Net.s_entity_look.rpc_id(p.peer_id, e.id, e.data.get("look", {}))


# --- Persistence --------------------------------------------------------------------------------

## Persistent entities standing in `coord` as JSON-safe dictionaries.
func serialize_chunk(coord: Vector2i) -> Array:
	var out := []
	for e: Entity in entities.values():
		if e.def.persistent and e.is_alive() and VoxelWorld.chunk_coord_of(e.body.position) == coord:
			var p := e.body.position
			out.append({"type": e.def.name, "position": [p.x, p.y, p.z], "yaw": e.yaw, "health": e.health, "data": e.data})
	return out


## Removes every entity in the chunk (called when it unloads). Returns the persistent ones' records.
func unload_chunk(coord: Vector2i) -> Array:
	var saved := serialize_chunk(coord)
	for e: Entity in entities.values():
		if VoxelWorld.chunk_coord_of(e.body.position) == coord:
			remove(e)
	return saved


func load_chunk(records) -> void:
	if not (records is Array):
		return
	for r in records:
		if not (r is Dictionary) or not (r.get("position") is Array) or r.position.size() != 3:
			continue
		var type_id := registry.id_of(String(r.get("type", "")))
		if type_id < 0:
			continue  # entity type from a removed mod
		var e := spawn(type_id, Vector3(float(r.position[0]), float(r.position[1]), float(r.position[2])),
			{"yaw": float(r.get("yaw", 0.0)), "data": r.get("data", {})})
		if e != null and r.has("health"):
			e.health = clampf(float(r.health), 1.0, maxf(e.def.health, 1.0))
