extends Node3D
## Draws the links the server tells us about: cables that sag, pipes that do not.
##
## A cable hangs in a curve. A real one is a catenary (a cosh), and a parabola is within a pixel of it
## over the spans a link is allowed - so it is a parabola, because the difference is invisible and the
## cheap one can be built for every cable on screen without thinking about it.
##
## **The sag is most of why a strung cable reads as a cable**, which is why this exists at all rather
## than a straight line between two points. A pipe is drawn with the same code and no sag, because a
## rigid tube that droops looks broken.
##
## Each link is one small mesh, built once and thrown away when the link goes. Cables do not move, so
## nothing here runs per frame.

## How far a cable dips at its middle, as a fraction of its length. Enough to read as hanging, little
## enough that a cable over a path does not sweep a player's head off.
const SAG := 0.11
## Segments along the curve. Eight is plenty: past that the extra vertices go where nobody looks.
const SEGMENTS := 8
const THICKNESS := 0.045
const PIPE_THICKNESS := 0.16

var _nodes := {}  # link id -> MeshInstance3D
var _materials := {}  # colour string -> StandardMaterial3D


## link: {id, draw ("cable" | "pipe"), a (Vector3), b (Vector3), color}
func add_link(link: Dictionary) -> void:
	var id := int(link.get("id", 0))
	if id == 0 or _nodes.has(id):
		return
	var from: Vector3 = link.get("a", Vector3.ZERO)
	var to: Vector3 = link.get("b", Vector3.ZERO)
	var pipe := String(link.get("draw", "cable")) == "pipe"
	var mesh := MeshInstance3D.new()
	mesh.mesh = _build(from, to, pipe)
	mesh.material_override = _material(String(link.get("color", "#b87333")))
	# The mesh is built in world space, so the node itself stays at the origin: a cable spans two
	# chunks and belongs to neither, and giving it a transform would only invite somebody to move it.
	add_child(mesh)
	_nodes[id] = mesh


func remove_link(id: int) -> void:
	var mesh: MeshInstance3D = _nodes.get(id)
	if mesh != null:
		_nodes.erase(id)
		mesh.queue_free()


func clear() -> void:
	for id in _nodes.keys():
		remove_link(id)


## The curve from one end to the other. A pipe is the same call with no dip.
static func curve(from: Vector3, to: Vector3, pipe: bool) -> PackedVector3Array:
	var points := PackedVector3Array()
	var dip := 0.0 if pipe else from.distance_to(to) * SAG
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var at := from.lerp(to, t)
		at.y -= dip * 4.0 * t * (1.0 - t)  # a parabola: nothing at the ends, deepest in the middle
		points.append(at)
	return points


## Two quads crossed in a plus along the curve. Cheaper than a real tube and indistinguishable on a
## cable this thin, which is the same trick the mesher already uses for plants.
func _build(from: Vector3, to: Vector3, pipe: bool) -> ArrayMesh:
	var points := curve(from, to, pipe)
	var half := (PIPE_THICKNESS if pipe else THICKNESS) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var along := (b - a).normalized()
		# Any two directions across the cable will do, so long as they are square to it and to each
		# other; a vertical-ish reference keeps the cross upright on a level run.
		var side := along.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = along.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := along.cross(side).normalized()
		for axis in [side, up]:
			_quad(st, a - axis * half, a + axis * half, b + axis * half, b - axis * half)
	st.generate_normals()
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
	# And the other way round, so a cable is not invisible from one side.
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)


func _material(color: String) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color) if color.begins_with("#") else Color(0.72, 0.45, 0.20)
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[color] = m
	return m
