extends MeshInstance3D
## A fading ribbon drawn between an item's grip and tip while it swings (item `trail`: {color, width,
## seconds}). Points are kept in the local space of `space` (the camera for first person) or in world
## space, so the ribbon stays where the blade passed.

var _grip: Node3D
var _tip: Node3D
var _space: Node3D
var _color := Color.WHITE
var _width := 1.0
var _seconds := 0.18
var _record_until := 0.0
var _samples: Array = []  # [time, grip position, tip position]
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = material


## Records the ribbon for `swing_seconds`. `space` null means world space. `subtle` (first person, where
## the blade sweeps right past the camera) draws a thinner, fainter, shorter ribbon.
func start(grip: Node3D, tip: Node3D, trail: Dictionary, swing_seconds: float, space: Node3D = null, subtle := false) -> void:
	if grip == null or tip == null or trail.is_empty():
		return
	if space != _space:
		_samples.clear()
	_grip = grip
	_tip = tip
	_space = space
	top_level = space == null
	if top_level:
		global_transform = Transform3D.IDENTITY
	_color = Color.html(String(trail.get("color", "#ffffffb0")))
	_width = clampf(float(trail.get("width", 0.5)), 0.1, 1.0) * (0.4 if subtle else 1.0)
	_seconds = float(trail.get("seconds", 0.18)) * (0.5 if subtle else 1.0)
	if subtle:
		_color.a *= 0.45
	_record_until = _now() + swing_seconds


func _process(_delta: float) -> void:
	var now := _now()
	if now < _record_until and is_instance_valid(_grip) and is_instance_valid(_tip) and _grip.is_inside_tree():
		var tip_pos := _tip.global_position
		var grip_pos := tip_pos.lerp(_grip.global_position, _width)
		if _space != null:
			tip_pos = _space.to_local(tip_pos)
			grip_pos = _space.to_local(grip_pos)
		_samples.append([now, grip_pos, tip_pos])
	while not _samples.is_empty() and now - float(_samples[0][0]) > _seconds:
		_samples.pop_front()
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample in _samples:
		var fade := clampf(1.0 - (now - float(sample[0])) / _seconds, 0.0, 1.0)
		var c := Color(_color.r, _color.g, _color.b, _color.a * fade)
		_mesh.surface_set_color(Color(c.r, c.g, c.b, 0.0))
		_mesh.surface_add_vertex(sample[1])
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(sample[2])
	_mesh.surface_end()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
