extends Node3D
## A player character built from a rig (PlayerRig) and an appearance: skin texture, armor texture,
## held item and accessories. Animates procedurally from movement: walking and running with bending
## knees and elbows, jumping and falling poses, idle breathing, looking up and down, swinging,
## getting hurt and lying down when dead.

const PlayerRig = preload("res://engine/shared/player_rig.gd")
const SwingTrail = preload("res://engine/client/effects/swing_trail.gd")
const EatingVisuals = preload("res://engine/client/eating_visuals.gd")

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
var _held_look := {}
var _trail: SwingTrail
var _armor_light: OmniLight3D = null  # made only when worn gear asks to light the world
## The current meal (see ViewModel.start_meal): the right hand brings the held food to the mouth, the
## left holds the plate; drinks are tipped back with the head raised.
var _meal := {}
## Yaw (radians) while lying in a bed with the head that way, or null when not sleeping.
var sleep_yaw = null
var _meal_plate: MeshInstance3D
var _meal_food: MeshInstance3D
var _meal_bites := 0


func build(rig_def: Dictionary) -> void:
	rig = rig_def
	for child in get_children():
		remove_child(child)
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
	_trail = SwingTrail.new()
	add_child(_trail)


func set_skin(texture: Texture2D) -> void:
	_skin_material.albedo_texture = texture
	_overlay_material.albedo_texture = texture


## Armor shell texture in the skin layout, or null to hide armor.
func set_armor(texture: Texture2D) -> void:
	_armor_material.albedo_texture = texture
	for m in _armor_meshes:
		m.visible = texture != null


## Replaces the item in the right hand (null = empty hand). `look`: {glow, trail, held} of the stack.
func set_held(node: Node3D, look := {}) -> void:
	if _held != null:
		_held.queue_free()
	_held = node
	_held_look = look
	_holding = node != null
	if node != null and attachments.has("hand_r"):
		attachments.hand_r.add_child(node)
		node.visible = _meal.is_empty() and sleep_yaw == null


## Adds accessory nodes at attachment points: [{attach, node}]. Replaces previous accessories.
func set_accessories(list: Array) -> void:
	for node in _accessories:
		node.queue_free()
	_accessories.clear()
	for entry in list:
		if attachments.has(entry.attach):
			attachments[entry.attach].add_child(entry.node)
			_accessories.append(entry.node)


## Lies down in a bed: `head` is the [x, z] direction from the feet to the pillow, or [] to get up.
func set_sleeping(head: Array) -> void:
	sleep_yaw = atan2(float(head[0]), float(head[1])) if head.size() == 2 else null
	if _held != null:
		_held.visible = sleep_yaw == null and _meal.is_empty()


func start_meal(meal: Dictionary) -> void:
	stop_meal()
	_meal = meal
	_meal_bites = 0
	if str(meal.style) == "plate" and meal.get("plate") != null and attachments.has("hand_l"):
		_meal_plate = MeshInstance3D.new()
		_meal_plate.mesh = meal.plate
		_meal_plate.scale = Vector3.ONE * 0.55
		_meal_plate.position = Vector3(0, 0.03, 0)
		_meal_plate.rotation_degrees = Vector3(90, 0, 0)  # flat on the palm
		_meal_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attachments.hand_l.add_child(_meal_plate)
	# The food (or bottle) itself, independent of the held-item appearance which may lag behind.
	if attachments.has("hand_r"):
		_meal_food = MeshInstance3D.new()
		_meal_food.mesh = meal.meshes[0]
		_meal_food.scale = Vector3.ONE * 0.8
		_meal_food.position = Vector3(0, 0.12, 0)
		_meal_food.rotation_degrees = Vector3(-90, 0, 0)  # face forward, upright in the fist
		_meal_food.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attachments.hand_r.add_child(_meal_food)
	if _held != null:
		_held.visible = false


func stop_meal() -> void:
	for node in [_meal_plate, _meal_food]:
		if node != null:
			node.queue_free()
	_meal_plate = null
	_meal_food = null
	if _held != null:
		_held.visible = true
	_meal = {}


func _meal_pose(pose: Dictionary, now: float) -> float:
	var t := float(_meal.freeze) if _meal.has("freeze") else now - float(_meal.started)
	var head_pitch := 0.0
	if str(_meal.style) == "drink":
		var g := EatingVisuals.gulp(t)
		pose.arm_r_upper = Vector3(2.45 + 0.08 * g, 0, -0.35)
		pose.arm_r_lower = Vector3(1.35, 0, 0)
		head_pitch = 0.35 + 0.05 * g
	else:
		var lift := EatingVisuals.lift(t)
		pose.arm_r_upper = Vector3(lerpf(1.0, 2.2, lift), 0, lerpf(-0.1, -0.45, lift))
		pose.arm_r_lower = Vector3(lerpf(0.6, 1.6, lift), 0, 0)
		if _meal_plate != null:
			pose.arm_l_upper = Vector3(1.05, 0, 0.2)
			pose.arm_l_lower = Vector3(0.55, 0, 0)
		var bites := EatingVisuals.bites(t, float(_meal.duration))
		if _meal_food != null and bites != _meal_bites:
			_meal_bites = bites
			var crumbs: Callable = _meal.get("crumbs", Callable())
			if crumbs.is_valid() and is_inside_tree():
				crumbs.call(_meal_food.global_position, _meal.color, 10 if bites >= 3 else 5, 0.03)
			_meal_food.visible = bites < 3
			if bites < 3:
				_meal_food.mesh = _meal.meshes[bites]
	return head_pitch


func swing(with_trail := true) -> void:
	_swing_at = Time.get_ticks_msec() / 1000.0
	if with_trail and _held != null and not _held_look.get("trail", {}).is_empty() and _held.get_child_count() > 0:
		var mesh := _held.get_child(0)
		_trail.start(mesh.get_node_or_null("grip"), mesh.get_node_or_null("tip"), _held_look.trail, SWING_SECONDS)


## Glowing armor: {color, energy} lights up the armor texture in its own colors, and `light` (a radius
## in blocks) makes it light the world around the wearer too. {} turns both off.
##
## **`light` arrived here for weeks and was thrown away.** The server already computed it from the
## worn stack's data and shipped it in `appearance.armor_glow`; this function read `color` and
## `energy` and dropped the rest on the floor, so armour could look lit and never lit anything. Held
## items have made a real light out of the same field all along (avatar/item_mesh.gd). (2026-09-24)
func set_armor_glow(glow: Dictionary) -> void:
	_armor_material.emission_enabled = not glow.is_empty()
	if not glow.is_empty():
		_armor_material.emission = Color.html(String(glow.color))
		# **The texture's emission is capped where the light's energy is not.** Armour albedo is close
		# to white, so a multiplier much above this saturates every texel and the piece stops looking
		# like armour at all - a glowing chestplate became a featureless white slab at level 3. The
		# light around the wearer still uses the full energy, so a stronger mark reads as a wider,
		# brighter pool rather than as a brighter box. Seen rather than reasoned about. (2026-09-24)
		_armor_material.emission_energy_multiplier = minf(float(glow.energy), 0.5)
		_armor_material.emission_texture = _armor_material.albedo_texture
	var radius := float(glow.get("light", 0.0)) if not glow.is_empty() else 0.0
	if radius <= 0.0:
		# Made only when something actually asks for one, and freed the moment it stops - the same
		# rule nameplates follow, and for the same reason: a room of forty players should not be forty
		# lights nobody asked for.
		if _armor_light != null:
			_armor_light.queue_free()
			_armor_light = null
		return
	if _armor_light == null:
		_armor_light = OmniLight3D.new()
		_armor_light.shadow_enabled = false  # nothing else at runtime casts shadows either
		# On the body rather than a limb, and above the feet, so it reads as the wearer glowing.
		_armor_light.position = Vector3(0.0, 1.0, 0.0)
		add_child(_armor_light)
	_armor_light.light_color = Color.html(String(glow.color))
	_armor_light.light_energy = float(glow.energy)
	_armor_light.omni_range = radius


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
	var head_pitch := 0.0
	if not _meal.is_empty():
		head_pitch = _meal_pose(pose, now)
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
		parts.head.rotation = Vector3(clampf(pitch + head_pitch, -1.3, 1.3), 0, 0)
	_scale_root.rotation.z = lerpf(_scale_root.rotation.z, PI * 0.5 if _dead else 0.0, minf(1.0, delta * 10.0))
	_scale_root.position.y = 0.15 if _dead else 0.0
	if sleep_yaw != null:
		# On your back along +Z (the avatar node is turned towards the pillow), limbs at rest.
		for key in ["leg_r_upper", "leg_l_upper", "leg_r_lower", "leg_l_lower", "arm_r_lower", "arm_l_lower", "torso"]:
			if parts.has(key):
				parts[key].rotation = Vector3.ZERO
		if parts.has("arm_r_upper"):
			parts.arm_r_upper.rotation = Vector3(0, 0, 0.08)
			parts.arm_l_upper.rotation = Vector3(0, 0, -0.08)
		if parts.has("head"):
			parts.head.rotation = Vector3.ZERO
		_scale_root.rotation = Vector3(PI * 0.5, 0, 0)
		_scale_root.position = Vector3(0, -0.36, -0.85)
	elif _scale_root.rotation.x != 0.0:
		_scale_root.rotation.x = 0.0
		_scale_root.position.z = 0.0
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
