extends Node3D
## A player character built from a rig (PlayerRig) and an appearance: skin texture, armor texture,
## held item and accessories. Animates procedurally from movement: walking and running with bending
## knees and elbows, jumping and falling poses, idle breathing, looking up and down, swinging,
## getting hurt and lying down when dead.

const PlayerRig = preload("res://engine/shared/player_rig.gd")

const OVERLAY_INFLATE := 0.5  # pixels: second skin layer (jackets, hats)
const ARMOR_INFLATE := 1.0  # pixels: armor shell
const SWING_SECONDS := 0.3

## Parts by name (Node3D pivots) and attachment points by name.
var parts := {}
var attachments := {}
var rig: Dictionary

var _scale_root: Node3D
var _base_meshes: Array[MeshInstance3D] = []
var _overlay_meshes: Array[MeshInstance3D] = []
var _armor_meshes: Array[MeshInstance3D] = []
var _skin_material := StandardMaterial3D.new()
var _overlay_material := StandardMaterial3D.new()
var _armor_material := StandardMaterial3D.new()
var _held: Node3D
var _accessories: Array[Node3D] = []
var _phase := 0.0
var _breath := 0.0
var _swing_at := -10.0
var _hurt_until := 0.0
var _dead := false
var _holding := false


func build(rig_def: Dictionary) -> void:
	rig = rig_def
	for child in get_children():
		child.queue_free()
	parts.clear()
	attachments.clear()
	_base_meshes.clear()
	_overlay_meshes.clear()
	_armor_meshes.clear()
	_scale_root = Node3D.new()
	add_child(_scale_root)
	var pixel := PlayerRig.PIXEL * float(rig.get("height", 1.8)) / 1.8
	_scale_root.scale = Vector3.ONE * pixel
	for material in [_skin_material, _overlay_material, _armor_material]:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 1.0
	for material in [_overlay_material, _armor_material]:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for part in rig.parts:
		var pivot := Node3D.new()
		pivot.name = part.name
		pivot.position = _v(part.pivot)
		(parts[part.parent] if part.parent != "" else _scale_root).add_child(pivot)
		parts[part.name] = pivot
		var region = PlayerRig.REGIONS.get(part.region)
		if region == null:
			continue
		var slice: Array = part.get("slice", [0, region[3]])
		_base_meshes.append(_box(pivot, part, region, slice, 0.0, _skin_material))
		var overlay = PlayerRig.REGIONS.get(part.region + "_overlay")
		if overlay != null:
			_overlay_meshes.append(_box(pivot, part, overlay, slice, OVERLAY_INFLATE, _overlay_material))
		_armor_meshes.append(_box(pivot, part, region, slice, ARMOR_INFLATE, _armor_material))
	for key in rig.attachments:
		var a: Dictionary = rig.attachments[key]
		var node := Node3D.new()
		node.name = "attach_" + key
		node.position = _v(a.position)
		node.rotation_degrees = _v(a.rotation)
		node.scale = Vector3.ONE / pixel  # things attached here are sized in blocks, not skin pixels
		parts[a.part].add_child(node)
		attachments[key] = node
	for m in _armor_meshes:
		m.visible = false


func set_skin(texture: Texture2D) -> void:
	_skin_material.albedo_texture = texture
	_overlay_material.albedo_texture = texture


## Armor shell texture in the skin layout, or null to hide armor.
func set_armor(texture: Texture2D) -> void:
	_armor_material.albedo_texture = texture
	for m in _armor_meshes:
		m.visible = texture != null


## Replaces the item in the right hand (null = empty hand).
func set_held(node: Node3D) -> void:
	if _held != null:
		_held.queue_free()
	_held = node
	_holding = node != null
	if node != null and attachments.has("hand_r"):
		attachments.hand_r.add_child(node)


## Adds accessory nodes at attachment points: [{attach, node}]. Replaces previous accessories.
func set_accessories(list: Array) -> void:
	for node in _accessories:
		node.queue_free()
	_accessories.clear()
	for entry in list:
		if attachments.has(entry.attach):
			attachments[entry.attach].add_child(entry.node)
			_accessories.append(entry.node)


func swing() -> void:
	_swing_at = Time.get_ticks_msec() / 1000.0


func hurt() -> void:
	_hurt_until = Time.get_ticks_msec() / 1000.0 + 0.3


func set_dead(dead: bool) -> void:
	_dead = dead


## Poses the body. `velocity` in blocks/s, `pitch` in radians (look up positive). Positive x rotation
## swings a hanging limb forward.
func animate(delta: float, velocity: Vector3, on_ground: bool, pitch: float) -> void:
	if parts.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var speed := Vector2(velocity.x, velocity.z).length()
	var amount := clampf(speed / 4.3, 0.0, 1.4)
	_phase += delta * (2.0 + speed * 2.2) if amount > 0.05 else 0.0
	_breath += delta
	var swing := sin(_phase) * 0.8 * minf(amount, 1.0)
	var pose := {}
	pose.leg_r_upper = Vector3(swing, 0, 0)
	pose.leg_l_upper = Vector3(-swing, 0, 0)
	pose.leg_r_lower = Vector3(-maxf(0.0, -sin(_phase)) * 1.1 * minf(amount, 1.0), 0, 0)
	pose.leg_l_lower = Vector3(-maxf(0.0, sin(_phase)) * 1.1 * minf(amount, 1.0), 0, 0)
	pose.arm_r_upper = Vector3(-swing * 0.8, 0, 0.05)
	pose.arm_l_upper = Vector3(swing * 0.8, 0, -0.05)
	pose.arm_r_lower = Vector3(0.15 + 0.35 * amount, 0, 0)  # elbows bend forward
	pose.arm_l_lower = Vector3(0.15 + 0.35 * amount, 0, 0)
	pose.torso = Vector3(0.12 * maxf(amount - 1.0, 0.0), 0, 0)  # lean into a sprint
	if amount < 0.05:
		var b := sin(_breath * 2.0) * 0.03
		pose.arm_r_upper = Vector3(0, 0, 0.05 + b)
		pose.arm_l_upper = Vector3(0, 0, -0.05 - b)
	if not on_ground:
		var falling := clampf(-velocity.y / 10.0, -1.0, 1.0)
		pose.leg_r_upper = Vector3(-0.5, 0, 0.05)
		pose.leg_l_upper = Vector3(0.2, 0, -0.05)
		pose.leg_r_lower = Vector3(-0.9, 0, 0)
		pose.leg_l_lower = Vector3(-0.3, 0, 0)
		pose.arm_r_upper = Vector3(0.3, 0, 0.35 + 0.3 * falling)
		pose.arm_l_upper = Vector3(0.3, 0, -0.35 - 0.3 * falling)
	if _holding:
		pose.arm_r_upper.x = pose.arm_r_upper.x * 0.4 + 0.3
		pose.arm_r_lower.x = 0.5
	var since_swing := now - _swing_at
	if since_swing < SWING_SECONDS:
		var t := since_swing / SWING_SECONDS
		pose.arm_r_upper = Vector3(lerpf(2.6, 0.4, ease(t, 0.5)), 0, 0.1)  # raised up front, chopping down
		pose.arm_r_lower = Vector3(0.3, 0, 0)
		pose.torso = Vector3(pose.torso.x, lerpf(0.35, -0.2, t), 0)
	for key in pose:
		if parts.has(key):
			parts[key].rotation = pose[key]
	if parts.has("head"):
		parts.head.rotation = Vector3(clampf(pitch, -1.3, 1.3), 0, 0)
	_scale_root.rotation.z = lerpf(_scale_root.rotation.z, PI * 0.5 if _dead else 0.0, minf(1.0, delta * 10.0))
	_scale_root.position.y = 0.15 if _dead else 0.0
	var flash := now < _hurt_until
	var tint := Color(1.0, 0.45, 0.45) if flash else Color.WHITE
	_skin_material.albedo_color = tint
	_armor_material.albedo_color = tint


func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A box part with UVs unfolded from its layout region (see SkinCompositor.unfold).
func _box(pivot: Node3D, part: Dictionary, region: Array, slice: Array, inflate: float, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = box_mesh(part, region, slice, inflate)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mesh)
	return mesh


static func box_mesh(part: Dictionary, region: Array, slice: Array, inflate: float) -> ArrayMesh:
	var lo := Vector3(part.box[0], part.box[1], part.box[2]) - Vector3.ONE * inflate
	var hi := Vector3(part.box[0], part.box[1], part.box[2]) + Vector3(part.size[0], part.size[1], part.size[2]) + Vector3.ONE * inflate
	var u: float = region[0]
	var v: float = region[1]
	var w: float = region[2]
	var h: float = region[3]
	var d: float = region[4]
	var t := 64.0
	var from: float = slice[0]
	var to: float = slice[1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_v0 := v + d + from
	# Corners listed top-left, top-right, bottom-right, bottom-left as seen from outside.
	_quad(st, [Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z)],
		Rect2(u + d, side_v0, w, to - from), t, Vector3.FORWARD)  # front (-Z)
	_quad(st, [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)],
		Rect2(u + 2 * d + w, side_v0, w, to - from), t, Vector3.BACK)  # back (+Z)
	_quad(st, [Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)],
		Rect2(u, side_v0, d, to - from), t, Vector3.RIGHT)  # character's right (+X)
	_quad(st, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z)],
		Rect2(u + d + w, side_v0, d, to - from), t, Vector3.LEFT)  # character's left (-X)
	_quad(st, [Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z)],
		Rect2(u + d, v, w, d), t, Vector3.UP)  # top
	_quad(st, [Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z)],
		Rect2(u + d + w, v, w, d), t, Vector3.DOWN)  # bottom
	return st.commit()


static func _quad(st: SurfaceTool, corners: Array, uv: Rect2, size: float, normal: Vector3) -> void:
	var uvs := [uv.position / size, Vector2(uv.end.x, uv.position.y) / size, uv.end / size, Vector2(uv.position.x, uv.end.y) / size]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
