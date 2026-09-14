extends Node3D
## Visual for a replicated entity: interpolates server positions, animates walking (model parts named
## leg_a / leg_b / arm_a / arm_b swing, head bobs), flashes red when hurt, tips over when it dies and
## flies to the collector when an item is picked up.

const INTERPOLATION_DELAY := 0.1
const MAX_BUFFER := 20
const DEATH_SECONDS := 0.7
const PICKUP_SECONDS := 0.18
const HURT_SECONDS := 0.3

var entity_id := 0
var type_def: Dictionary
var item_id := 0
var item_count := 1
var width := 0.6
var height := 1.8
var dying := false

var _buffer: Array = []  # [{time, position, yaw}]
var _root: Node3D  # rotated by yaw
var _parts := {}  # animation key (leg_a, leg_b, arm_a, arm_b, head) -> Array of Node3D pivots
var _meshes: Array[GeometryInstance3D] = []
var _holder: Node3D
var _model_scale := 1.0
var _part_meshes := {}  # lowercased part name -> MeshInstance3D
var _pose := ""  # "" or "sit"
var _walk_phase := 0.0
var _last_position := Vector3.INF
var _hurt_until := 0.0
var _died_at := -1.0
var _pickup_target: Node3D = null
var _pickup_from := Vector3.ZERO
var _pickup_started := 0.0
var _spin := 0.0
var _windup_until := 0.0
var _attack_at := -10.0

static var _windup_overlay: StandardMaterial3D

static var _hurt_overlay: StandardMaterial3D


## `parts`: [{name, mesh, transform}] from ModelLibrary.load_parts, or empty. `sprite`: texture for
## items, projectiles and model-less entities.
func setup(id: int, def: Dictionary, parts: Array, sprite: Texture2D, pos: Vector3, yaw: float) -> void:
	entity_id = id
	type_def = def
	width = float(def.get("width", 0.6))
	height = float(def.get("height", 1.8))
	position = pos
	_root = Node3D.new()
	_root.rotation.y = yaw
	add_child(_root)
	var kind := String(def.get("kind", "mob"))
	var model_scale := float(def.get("scale", 1.0))
	if not parts.is_empty():
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * model_scale
		_holder = holder
		_model_scale = model_scale
		_root.add_child(holder)
		for part in parts:
			var pivot := Node3D.new()
			pivot.transform = part.transform
			holder.add_child(pivot)
			var mesh := MeshInstance3D.new()
			mesh.mesh = part.mesh
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(mesh)
			_meshes.append(mesh)
			var part_name := String(part.name).to_lower()
			_part_meshes[part_name] = mesh
			for key in ["leg_a", "leg_b", "arm_a", "arm_b", "head"]:
				if part_name.begins_with(key):
					if not _parts.has(key):
						_parts[key] = []
					_parts[key].append(pivot)
	elif sprite != null:
		var s := Sprite3D.new()
		s.texture = sprite
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var size := 0.32 if kind == "item" else maxf(width, height)
		s.pixel_size = size / maxf(sprite.get_width(), 1)
		s.position.y = size * 0.5 + (0.12 if kind == "item" else 0.0)
		s.shaded = false
		if def.get("glow", false):
			s.modulate = Color(2.2, 2.2, 2.2)
		_root.add_child(s)
		_meshes.append(s)
	else:
		var box := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(width, height, width)
		box.mesh = box_mesh
		box.position.y = height * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.from_hsv(fmod(hash(def.get("name", "")) * 0.0001, 1.0), 0.5, 0.85)
		box.material_override = material
		_root.add_child(box)
		_meshes.append(box)
	push_state(Time.get_ticks_msec() / 1000.0, pos, yaw)


## {scale, hide: [part prefixes], tint: {part prefix: "#rrggbb"}} from the server (babies, sheared or
## dyed sheep, ...).
func set_look(look: Dictionary) -> void:
	if _holder != null:
		_holder.scale = Vector3.ONE * _model_scale * clampf(float(look.get("scale", 1.0)), 0.05, 10.0)
	elif not _meshes.is_empty() and _meshes[0] is Node3D:
		_root.scale = Vector3.ONE * clampf(float(look.get("scale", 1.0)), 0.05, 10.0)
	_pose = str(look.get("pose", ""))
	var hide: Array = look.get("hide", []) if look.get("hide") is Array else []
	var tint: Dictionary = look.get("tint", {}) if look.get("tint") is Dictionary else {}
	for part_name: String in _part_meshes:
		var mesh: MeshInstance3D = _part_meshes[part_name]
		mesh.visible = not hide.any(func(prefix): return part_name.begins_with(str(prefix).to_lower()))
		var color := Color.WHITE
		for prefix in tint:
			if part_name.begins_with(str(prefix).to_lower()) and Color.html_is_valid(str(tint[prefix])):
				color = Color.html(str(tint[prefix]))
		for s in mesh.mesh.get_surface_count():
			if color == Color.WHITE:
				mesh.set_surface_override_material(s, null)
				continue
			var base := mesh.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null:
				continue
			var tinted := base.duplicate() as StandardMaterial3D
			tinted.albedo_color = base.albedo_color * color
			mesh.set_surface_override_material(s, tinted)


func push_state(time: float, pos: Vector3, yaw: float) -> void:
	_buffer.append({"time": time, "position": pos, "yaw": yaw})
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()


func hurt() -> void:
	_hurt_until = Time.get_ticks_msec() / 1000.0 + HURT_SECONDS
	if _hurt_overlay == null:
		_hurt_overlay = StandardMaterial3D.new()
		_hurt_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hurt_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hurt_overlay.albedo_color = Color(1.0, 0.1, 0.1, 0.45)
	for m in _meshes:
		m.material_overlay = _hurt_overlay


## The mob is about to attack: arms rise and it glows, so players can react.
func windup() -> void:
	_windup_until = Time.get_ticks_msec() / 1000.0 + 0.8
	if _windup_overlay == null:
		_windup_overlay = StandardMaterial3D.new()
		_windup_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_windup_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_windup_overlay.albedo_color = Color(1.0, 0.85, 0.3, 0.35)
	for m in _meshes:
		m.material_overlay = _windup_overlay


func attack() -> void:
	_windup_until = 0.0
	_attack_at = Time.get_ticks_msec() / 1000.0
	for m in _meshes:
		if m.material_overlay == _windup_overlay:
			m.material_overlay = null


func die() -> void:
	dying = true
	_died_at = Time.get_ticks_msec() / 1000.0
	hurt()


## Server despawn: plays out a running death or pickup animation first.
func despawn() -> void:
	if _pickup_target != null or dying:
		var remaining := DEATH_SECONDS if dying else PICKUP_SECONDS
		get_tree().create_timer(remaining).timeout.connect(queue_free)
	else:
		queue_free()


func picked_up_by(target: Node3D) -> void:
	_pickup_target = target
	_pickup_from = position
	_pickup_started = Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _hurt_until > 0.0 and now > _hurt_until and not dying:
		_hurt_until = 0.0
		for m in _meshes:
			m.material_overlay = null
	if _pickup_target != null and is_instance_valid(_pickup_target):
		var t := clampf((now - _pickup_started) / PICKUP_SECONDS, 0.0, 1.0)
		position = _pickup_from.lerp(_pickup_target.global_position + Vector3(0, 0.9, 0), t)
		scale = Vector3.ONE * (1.0 - t * 0.6)
		return
	if dying:
		_root.rotation.z = lerpf(0.0, PI * 0.5, clampf((now - _died_at) / 0.35, 0.0, 1.0))
		return
	if not _buffer.is_empty():
		var render_time := now - INTERPOLATION_DELAY
		while _buffer.size() >= 2 and _buffer[1].time <= render_time:
			_buffer.pop_front()
		var a: Dictionary = _buffer[0]
		if _buffer.size() == 1 or render_time <= a.time:
			position = a.position
			_root.rotation.y = a.yaw
		else:
			var b: Dictionary = _buffer[1]
			var t := clampf((render_time - a.time) / maxf(b.time - a.time, 0.0001), 0.0, 1.0)
			position = a.position.lerp(b.position, t)
			_root.rotation.y = lerp_angle(a.yaw, b.yaw, t)
	if String(type_def.get("kind", "")) == "item":
		_spin += delta
		_root.position.y = sin(_spin * 2.5) * 0.05
		return
	_animate(delta)


func _animate(delta: float) -> void:
	var speed := 0.0
	if _last_position != Vector3.INF and delta > 0.0:
		speed = Vector2(position.x - _last_position.x, position.z - _last_position.z).length() / delta
	_last_position = position
	var swing := clampf(speed / 3.0, 0.0, 1.0)
	_walk_phase += delta * (4.0 + speed * 2.0) * (1.0 if swing > 0.05 else 0.0)
	var angle := sin(_walk_phase) * 0.7 * swing
	var swings := {"leg_a": angle, "leg_b": -angle, "arm_a": -angle * 0.5, "arm_b": angle * 0.5, "head": sin(_walk_phase * 0.5) * 0.08 * swing}
	var now := Time.get_ticks_msec() / 1000.0
	if now < _windup_until:
		swings.arm_a = -2.2  # arms raised
		swings.arm_b = -2.2
	elif now - _attack_at < 0.25:
		var t := (now - _attack_at) / 0.25
		swings.arm_a = lerpf(-2.2, 0.6, t)  # swing down
		swings.arm_b = lerpf(-2.2, 0.6, t)
	if _pose == "sit":
		# Sitting: body tipped back onto folded hind legs, front legs straight.
		swings = {"leg_a": 0.0, "leg_b": 0.0, "arm_a": 0.0, "arm_b": 0.0, "head": -0.25}
		for pivot: Node3D in _parts.get("leg_a", []) + _parts.get("leg_b", []):
			if pivot.position.z > 0.0:
				swings[pivot] = -1.4
	if _holder != null:
		_holder.rotation.x = lerpf(_holder.rotation.x, -0.45 if _pose == "sit" else 0.0, minf(1.0, delta * 10.0))
		_holder.position.y = lerpf(_holder.position.y, -0.12 if _pose == "sit" else 0.0, minf(1.0, delta * 10.0))
	for key in swings:
		if key is Node3D:
			continue
		for pivot: Node3D in _parts.get(key, []):
			pivot.rotation.x = swings.get(pivot, swings[key])


## Hit box for client-side targeting.
func aabb() -> AABB:
	return AABB(position - Vector3(width * 0.5, 0.0, width * 0.5), Vector3(width, height, width))
