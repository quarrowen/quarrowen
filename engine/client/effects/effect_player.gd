extends Node3D
## Renders effects (see EffectRegistry) from data: CPU particle emitters, light flashes, camera shake
## and sounds. Also block-break debris. Everything is freed when it finishes.

const EffectRegistry = preload("res://engine/shared/effect_registry.gd")

const MAX_LIVE := 160  # effects alive at once; the oldest one-shots are dropped beyond this

var registry := EffectRegistry.new()
## Asset name -> Texture2D (mod emitter textures).
var textures := {}
## Plays a sound by name at a position: Callable(name, position).
var play_sound: Callable
## Scales particle counts (graphics presets).
var quality := 1.0
## Current camera shake as an offset to add to the camera, decaying over time.
var shake_offset := Vector3.ZERO
## Accessibility: 0..1 multipliers for camera shake and light flashes.
var shake_scale := 1.0
var flash_scale := 1.0

var _shakes: Array[Dictionary] = []  # {strength, ends, seconds}
var _builtin_textures := {}
var _materials := {}
var _live: Array[Node3D] = []


func _process(delta: float) -> void:
	var now := _now()
	var strength := 0.0
	for i in range(_shakes.size() - 1, -1, -1):
		var s: Dictionary = _shakes[i]
		if now >= s.ends:
			_shakes.remove_at(i)
			continue
		strength = maxf(strength, s.strength * (s.ends - now) / s.seconds)
	strength *= shake_scale
	shake_offset = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * strength * 0.12 if strength > 0.0 else Vector3.ZERO
	for i in range(_live.size() - 1, -1, -1):
		if not is_instance_valid(_live[i]):
			_live.remove_at(i)


## Plays effect `id` at a world position. `parent` (optional) makes it follow a node; `listener`
## (camera position) decides whether shake reaches this player. Returns the effect's root node.
func play(id: int, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D:
	if not registry.is_valid(id):
		return null
	return play_def(registry.defs[id], position, options, parent, listener)


## Plays an effect from its definition rather than its id, for effects that were never registered.
##
## Oldest effects are freed once `MAX_LIVE` are running: a mod that fires one per tick should slow the
## room down, not fill memory.
func play_def(def: Dictionary, position: Vector3, options := {}, parent: Node3D = null, listener := Vector3.INF) -> Node3D:
	while _live.size() >= MAX_LIVE:
		var oldest: Node3D = _live.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var scale_factor := float(options.get("scale", 1.0))
	var tint := Color.html(String(options.get("color", "#ffffff")))
	var duration := float(options.get("duration", def.duration))
	var root := Node3D.new()
	root.name = "effect_" + String(def.name).replace(":", "_")
	(parent if parent != null else self).add_child(root)
	if parent == null:
		root.global_position = position
	var direction: Vector3 = options.get("direction", Vector3.ZERO)
	if direction.length() > 0.01:
		# Emitter directions are authored with +Y as "forward"; turn them towards `direction`.
		var up := direction.normalized()
		var axis := Vector3.UP.cross(up)
		if axis.length() > 0.001:
			root.basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
		elif up.y < 0.0:
			root.basis = Basis(Vector3.RIGHT, PI)
	var longest := 0.0
	for e in def.emitters:
		var particles := _emitter(e, scale_factor, tint, duration)
		root.add_child(particles)
		longest = maxf(longest, float(e.lifetime))
	if not def.light.is_empty() and flash_scale > 0.0:
		var light := OmniLight3D.new()
		light.light_color = Color.html(def.light.color) * tint
		light.light_energy = def.light.energy * flash_scale
		light.omni_range = def.light.range * scale_factor
		light.shadow_enabled = false
		root.add_child(light)
		var tween := light.create_tween()
		tween.tween_property(light, "light_energy", 0.0, def.light.seconds)
		longest = maxf(longest, def.light.seconds)
	if not def.shake.is_empty() and (listener == Vector3.INF or listener.distance_to(position) <= def.shake.radius):
		var falloff: float = 1.0 if listener == Vector3.INF else 1.0 - 0.7 * listener.distance_to(position) / def.shake.radius
		_shakes.append({"strength": def.shake.strength * falloff, "seconds": def.shake.seconds, "ends": _now() + def.shake.seconds})
	if not String(def.sound).is_empty() and play_sound.is_valid():
		play_sound.call(def.sound, position)
	if duration >= 0.0:
		var timer := get_tree().create_timer(maxf(duration, 0.0) + longest + 0.1)
		timer.timeout.connect(func():
			if is_instance_valid(root):
				root.queue_free())
		if duration > 0.0:
			get_tree().create_timer(duration).timeout.connect(func():
				if is_instance_valid(root):
					for child in root.get_children():
						if child is CPUParticles3D:
							child.emitting = false)
		_live.append(root)
	return root


## Chunks of a block flying apart: `atlas_texture` with the block face's `uv` rectangle.
func block_break(position: Vector3, atlas_texture: Texture2D, uv: Rect2, brightness := 1.0) -> void:
	if atlas_texture == null:
		return
	var root := Node3D.new()
	add_child(root)
	root.global_position = position
	for i in 3:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = maxi(1, int(5 * quality))
		p.lifetime = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.3, 0.3, 0.3)
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 1.5
		p.initial_velocity_max = 3.5
		p.gravity = Vector3(0, -16, 0)
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.2
		p.angle_min = 0.0
		p.angle_max = 360.0
		# Each emitter shows a different 4x4 patch of the block texture.
		var patch := Rect2(uv.position + uv.size * Vector2(randf_range(0.0, 0.75), randf_range(0.0, 0.75)), uv.size * 0.25)
		p.mesh = _patch_quad(0.1, patch)
		var material := StandardMaterial3D.new()
		material.albedo_texture = atlas_texture
		material.albedo_color = Color(brightness, brightness, brightness)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		p.material_override = material
		p.emitting = true
		root.add_child(p)
	get_tree().create_timer(1.1).timeout.connect(root.queue_free)
	_live.append(root)


func _emitter(e: Dictionary, scale_factor: float, tint: Color, duration: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var burst: bool = e.burst or duration == 0.0
	p.one_shot = burst
	p.explosiveness = 1.0 if burst else 0.0
	p.amount = maxi(1, int(e.amount * quality))
	p.lifetime = e.lifetime
	p.local_coords = false
	p.direction = Vector3(e.direction[0], e.direction[1], e.direction[2])
	p.spread = e.spread
	p.initial_velocity_min = e.speed[0] * scale_factor
	p.initial_velocity_max = e.speed[1] * scale_factor
	p.gravity = Vector3(0, -e.gravity * scale_factor, 0)
	p.damping_min = e.drag
	p.damping_max = e.drag
	match e.shape:
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = e.radius * scale_factor
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(e.extents[0], e.extents[1], e.extents[2]) * scale_factor
	var biggest := maxf(maxf(e.size[0], e.size[1]), 0.001)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * biggest * scale_factor
	p.mesh = quad
	var curve := Curve.new()
	curve.add_point(Vector2(0, e.size[0] / biggest))
	curve.add_point(Vector2(1, e.size[1] / biggest))
	p.scale_amount_curve = curve
	var colors: Array = e.colors if e.colors.size() > 1 else [e.colors[0], e.colors[0]]
	var offsets := PackedFloat32Array()
	var ramp := PackedColorArray()
	for i in colors.size():
		var c := Color.html(colors[i])
		offsets.append(float(i) / (colors.size() - 1))
		ramp.append(Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = ramp
	p.color_ramp = gradient
	p.material_override = _material(String(e.texture), String(e.blend))
	p.emitting = true
	return p


func _material(texture_name: String, blend: String) -> StandardMaterial3D:
	var key := texture_name + "|" + blend
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if blend == "add" else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_texture = textures.get(texture_name, builtin_texture(texture_name))
	if texture_name == "square" or textures.has(texture_name):
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_materials[key] = m
	return m


## Procedural particle sprites: soft (round glow), spark (bright core), star (four points), square.
func builtin_texture(texture_name: String) -> Texture2D:
	if _builtin_textures.has(texture_name):
		return _builtin_textures[texture_name]
	const SIZE := 32
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE - 1, SIZE - 1) * 0.5
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(center) / (SIZE * 0.5)
			var a := 0.0
			match texture_name:
				"spark":
					a = clampf(1.0 - d, 0.0, 1.0)
					a = a * a * a * 1.6
				"star":
					var q := Vector2(absf(x - center.x), absf(y - center.y)) / (SIZE * 0.5)
					a = clampf(1.0 - d * 1.6, 0.0, 1.0) + clampf(1.0 - q.x * 8.0, 0.0, 1.0) * clampf(1.0 - q.y, 0.0, 1.0) \
						+ clampf(1.0 - q.y * 8.0, 0.0, 1.0) * clampf(1.0 - q.x, 0.0, 1.0)
				"square":
					a = 1.0 if maxf(absf(x - center.x), absf(y - center.y)) < SIZE * 0.35 else 0.0
				_:
					a = clampf(1.0 - d, 0.0, 1.0)
					a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	var texture := ImageTexture.create_from_image(img)
	_builtin_textures[texture_name] = texture
	return texture


static func _patch_quad(size: float, uv: Rect2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var corners := [Vector3(-h, h, 0), Vector3(h, h, 0), Vector3(h, -h, 0), Vector3(-h, -h, 0)]
	var uvs := [uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.BACK)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
	return st.commit()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
