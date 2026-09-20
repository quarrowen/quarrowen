extends Node3D
## Lines drawn between two points for a moment: a spell going off, an arc of lightning, a beam holding
## something up.
##
## Emitters cannot say "from here to there" - they say "from here, outwards" - so this is its own small
## thing rather than an effect with a shape bolted on. The geometry is the cable's, because a cable
## already had to be drawn between two arbitrary points and there is no reason to write that twice.

const CableView = preload("res://engine/client/cable_view.gd")

## Beams alive at once. A spell that fires every frame is a mistake somebody will make, and the server
## should not be able to fill a client's scene with them.
const MAX_BEAMS := 64

var _beams: Array = []


## look: {color, width, seconds, sag (0 for a straight beam, >0 for something hanging)}.
func add(from: Vector3, to: Vector3, look: Dictionary) -> void:
	if _beams.size() >= MAX_BEAMS:
		var oldest: Dictionary = _beams.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.queue_free()
	var width := clampf(float(look.get("width", 0.08)), 0.01, 1.0)
	var seconds := clampf(float(look.get("seconds", 0.25)), 0.02, 10.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _build(from, to, width, clampf(float(look.get("sag", 0.0)), 0.0, 1.0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(String(look.get("color", "#ffffff")))
	# Unshaded and additive: a beam is light, and light does not take a shadow from the wall behind it.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	add_child(mesh)
	_beams.append({"node": mesh, "left": seconds, "seconds": seconds, "material": material})


func _process(delta: float) -> void:
	if _beams.is_empty():
		return
	var still_there := []
	for beam: Dictionary in _beams:
		beam.left -= delta
		if beam.left <= 0.0 or not is_instance_valid(beam.node):
			if is_instance_valid(beam.node):
				beam.node.queue_free()
			continue
		# Fading rather than vanishing: a beam that stops dead reads as a dropped frame.
		beam.material.albedo_color.a = clampf(beam.left / beam.seconds, 0.0, 1.0)
		still_there.append(beam)
	_beams = still_there


func clear() -> void:
	for beam: Dictionary in _beams:
		if is_instance_valid(beam.node):
			beam.node.queue_free()
	_beams.clear()


## Crossed quads along the line - the cable's geometry, because a cable already had to be drawn
## between two arbitrary points.
func _build(from: Vector3, to: Vector3, width: float, sag: float) -> ArrayMesh:
	var points := CableView.curve(from, to, sag <= 0.0)
	var half := width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = along.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := along.cross(side).normalized()
		for axis in [side, up]:
			for v in [a - axis * half, a + axis * half, b + axis * half,
					a - axis * half, b + axis * half, b - axis * half]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()
