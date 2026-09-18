extends Node3D
## Draws the debug shapes the server sends (boxes, lines, paths, spheres and labels from mods and the
## engine's AI view). Each shape becomes its own small node and frees itself when it expires. Shapes
## draw on top of the world so they stay visible through walls.

const MAX_NODES := 3000

var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 10


func add_shapes(shapes: Array) -> void:
	for s in shapes:
		if get_child_count() >= MAX_NODES:
			return
		if s is Dictionary:
			_add(s)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _add(s: Dictionary) -> void:
	var color := Color.from_string(str(s.get("color", "#ffcc00")), Color(1, 0.8, 0))
	var node: Node3D
	match str(s.get("type", "")):
		"box":
			var lo: Vector3 = s.get("min", s.get("center", Vector3.ZERO) - s.get("size", Vector3.ONE) * 0.5)
			var hi: Vector3 = s.get("max", s.get("center", Vector3.ZERO) + s.get("size", Vector3.ONE) * 0.5)
			var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
				Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
			var pairs := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
			node = _lines(pairs.map(func(i): return c[i]), color)
		"line":
			node = _lines([s.get("from", Vector3.ZERO), s.get("to", Vector3.ZERO)], color)
		"path":
			var pts: Array = s.get("points", [])
			var segs := []
			for i in range(1, pts.size()):
				segs.append(pts[i - 1])
				segs.append(pts[i])
			node = _lines(segs, color) if not segs.is_empty() else null
			for p in pts:
				if node != null:
					var dot := _lines(_cross(p, 0.08), color)
					node.add_child(dot)
		"sphere":
			var center: Vector3 = s.get("center", Vector3.ZERO)
			var r := float(s.get("radius", 0.5))
			var segs := []
			for axis in 3:
				for i in 24:
					var a := TAU * i / 24.0
					var b := TAU * (i + 1) / 24.0
					segs.append(center + _ring(axis, a) * r)
					segs.append(center + _ring(axis, b) * r)
			node = _lines(segs, color)
		"text":
			var label := Label3D.new()
			label.text = str(s.get("text", ""))
			label.position = s.get("position", Vector3.ZERO)
			label.modulate = color
			label.outline_modulate = Color(0, 0, 0, 0.8)
			label.outline_size = 8
			label.font_size = 28
			label.pixel_size = 0.0008
			label.fixed_size = true
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.render_priority = 11
			node = label
	if node == null:
		return
	add_child(node)
	get_tree().create_timer(float(s.get("seconds", 2.0))).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())


static func _ring(axis: int, angle: float) -> Vector3:
	match axis:
		0: return Vector3(cos(angle), sin(angle), 0)
		1: return Vector3(cos(angle), 0, sin(angle))
	return Vector3(0, cos(angle), sin(angle))


static func _cross(p: Vector3, r: float) -> Array:
	return [p - Vector3(r, 0, 0), p + Vector3(r, 0, 0), p - Vector3(0, r, 0), p + Vector3(0, r, 0), p - Vector3(0, 0, r), p + Vector3(0, 0, r)]


func _lines(points: Array, color: Color) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	for p in points:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
