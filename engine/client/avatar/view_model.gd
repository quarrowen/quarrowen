extends Node3D
## First-person view: your right arm (skin and armor sleeve) and the held item in the lower right of
## the screen. Bobs while walking, swings on attacks and mining, dips when you switch items, and
## tilts slightly with mouse movement so the hand feels attached to the body. While eating, the arm
## brings the food (on a plate, or in hand) up to the mouth bite by bite; drinks are tipped back.

const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Avatar = preload("res://engine/client/avatar/avatar.gd")
const SwingTrail = preload("res://engine/client/effects/swing_trail.gd")
const EatingVisuals = preload("res://engine/client/eating_visuals.gd")

## Laid out at body scale (the arm is as long as on the avatar), then shrunk towards the camera so the
## arm and item stay closer than any wall the player can stand against.
const SCALE := 0.35
const REST := Vector3(0.72, -0.62, -0.38)  # shoulder, below the right edge of the screen
const SWING_SECONDS := 0.25
const EQUIP_SECONDS := 0.2
const EAT_REST := Vector3(0.5, -0.66, -0.46)  # plate held low, a little towards the middle
const DRINK_REST := Vector3(0.36, -0.38, -0.36)  # bottle raised towards the mouth

var _arm: Node3D
var _hand: Node3D
var _item_root: Node3D
var _skin_mesh: MeshInstance3D
var _armor_mesh: MeshInstance3D
var _skin_material := StandardMaterial3D.new()
var _armor_material := StandardMaterial3D.new()
var _held: Node3D
var _held_id := -1
var _held_look := {}
var _trail := SwingTrail.new()
var _swing_at := -10.0
var _equip_at := -10.0
var _bob := 0.0
var _sway := Vector2.ZERO
## The current meal: {style, duration, started, color, meshes: [Mesh per bites 0-2], plate, crumbs: Callable}.
var _meal := {}
var _meal_root: Node3D
var _meal_food: MeshInstance3D
var _meal_bites := 0
var _meal_chomp := -1
var _meal_blend := 0.0
var _meal_style := ""


func _ready() -> void:
	for material in [_skin_material, _armor_material]:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.roughness = 1.0
	_armor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_armor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arm = Node3D.new()
	add_child(_arm)
	var pixel := PlayerRig.PIXEL
	var arm_part := {"box": [-2, -12, -2], "size": [4, 12, 4]}
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * pixel
	holder.rotation_degrees = Vector3(105, 8, 0)  # arm pointing into the screen, slightly up and inwards
	_arm.add_child(holder)
	_skin_mesh = MeshInstance3D.new()
	_skin_mesh.mesh = Avatar.box_mesh(arm_part, PlayerRig.REGIONS.arm_r, [0, 12], 0.0)
	_skin_mesh.material_override = _skin_material
	holder.add_child(_skin_mesh)
	_armor_mesh = MeshInstance3D.new()
	_armor_mesh.mesh = Avatar.box_mesh(arm_part, PlayerRig.REGIONS.arm_r, [0, 12], 1.0)
	_armor_mesh.material_override = _armor_material
	_armor_mesh.visible = false
	holder.add_child(_armor_mesh)
	for mesh in [_skin_mesh, _armor_mesh]:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand = Node3D.new()
	_hand.position = Vector3(0, -11, -1)
	holder.add_child(_hand)
	# Held items hang off the arm in camera orientation (see ItemMesh.node_for first_person) at the fist.
	_item_root = Node3D.new()
	_item_root.position = holder.transform * _hand.position
	_arm.add_child(_item_root)
	scale = Vector3.ONE * SCALE
	position = REST * SCALE
	get_parent().add_child.call_deferred(_trail)  # trail points live in camera space


func set_skin(texture: Texture2D) -> void:
	_skin_material.albedo_texture = texture


func set_armor(texture: Texture2D, glow := {}) -> void:
	_armor_material.albedo_texture = texture
	_armor_mesh.visible = texture != null
	_armor_material.emission_enabled = not glow.is_empty()
	if not glow.is_empty():
		_armor_material.emission = Color.html(String(glow.color))
		_armor_material.emission_energy_multiplier = float(glow.energy)
		_armor_material.emission_texture = texture


## `node` shows the held item; `id` lets the arm dip and come back up when the item changes.
func set_held(id: int, node: Node3D, look := {}) -> void:
	if _held != null:
		_held.queue_free()
	_held = node
	_held_look = look
	if node != null:
		_item_root.add_child(node)
		node.visible = _meal.is_empty()
	if id != _held_id:
		_equip_at = Time.get_ticks_msec() / 1000.0
	_held_id = id


func start_meal(meal: Dictionary) -> void:
	stop_meal()
	_meal = meal
	_meal_style = str(meal.style)
	_meal_bites = 0
	_meal_chomp = -1
	_meal_root = Node3D.new()
	_item_root.add_child(_meal_root)
	if _held != null:
		_held.visible = false
	if _meal_style == "plate" and meal.get("plate") != null:
		var plate := MeshInstance3D.new()
		plate.mesh = meal.plate
		plate.rotation_degrees = Vector3(-62, 0, 0)  # nearly flat, tipped towards you
		plate.position = Vector3(-0.05, 0.08, -0.08)
		plate.scale = Vector3.ONE * 0.62
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meal_root.add_child(plate)
	_meal_food = MeshInstance3D.new()
	_meal_food.mesh = meal.meshes[0]
	_meal_food.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_meal_food.scale = Vector3.ONE * (0.4 if _meal_style == "plate" else 0.6)
	_meal_root.add_child(_meal_food)


func stop_meal() -> void:
	if _meal_root != null:
		_meal_root.queue_free()
		_meal_root = null
	_meal = {}
	if _held != null:
		_held.visible = true


func eating() -> bool:
	return not _meal.is_empty()


func _animate_meal(now: float) -> void:
	var t := float(_meal.freeze) if _meal.has("freeze") else now - float(_meal.started)  # freeze: screenshots
	var duration := float(_meal.duration)
	var food := _meal_food
	if _meal_style == "drink":
		# Tip the bottle back a little more with every gulp.
		var tip := 40.0 + 35.0 * clampf(t / duration, 0.0, 1.0) + 6.0 * EatingVisuals.gulp(t)
		food.position = Vector3(-0.06, 0.13, 0.02)
		food.rotation_degrees = Vector3(tip, 0, 12)
		return
	var lift := EatingVisuals.lift(t)
	var base := Vector3(-0.05, 0.2, -0.08) if _meal_style == "plate" else Vector3(-0.05, 0.1, 0)
	food.position = base + Vector3(-0.1, 0.16, 0.22) * lift
	food.rotation_degrees = Vector3(-18.0 * lift, 0, 0)
	var chomp := floori(t / EatingVisuals.CHOMP)
	var crumbs: Callable = _meal.get("crumbs", Callable())
	if chomp != _meal_chomp and fposmod(t, EatingVisuals.CHOMP) > EatingVisuals.CHOMP * 0.5:
		_meal_chomp = chomp
		if food.visible and crumbs.is_valid():
			crumbs.call(food.global_position, _meal.color, 3, 0.012)
	var bites := EatingVisuals.bites(t, duration)
	if bites != _meal_bites:
		_meal_bites = bites
		if bites >= 3:
			food.visible = false
		else:
			food.mesh = _meal.meshes[bites]
		if crumbs.is_valid():
			crumbs.call(food.global_position, _meal.color, 12 if bites >= 3 else 6, 0.012)


func swing() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _swing_at > SWING_SECONDS * 0.6:
		_swing_at = now
		if _held != null and not _held_look.get("trail", {}).is_empty() and _held.get_child_count() > 0:
			var mesh := _held.get_child(0)
			_trail.start(mesh.get_node_or_null("grip"), mesh.get_node_or_null("tip"), _held_look.trail, SWING_SECONDS, get_parent(), true)


## `speed`: horizontal speed in blocks/s; `look_delta`: mouse movement this frame (pixels).
func animate(delta: float, speed: float, on_ground: bool, look_delta: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if on_ground and speed > 0.5:
		_bob += delta * speed * 2.1
	var bob := Vector3(cos(_bob) * 0.012, -absf(sin(_bob)) * 0.02, 0) * clampf(speed / 4.3, 0.0, 1.3)
	_sway = _sway.lerp(look_delta * 0.0004, minf(1.0, delta * 12.0))
	_meal_blend = move_toward(_meal_blend, 1.0 if not _meal.is_empty() else 0.0, delta * 6.0)
	var rest := REST.lerp(DRINK_REST if _meal_style == "drink" else EAT_REST, ease(_meal_blend, -2.0))
	if not _meal.is_empty() and _meal_root != null:
		_animate_meal(now)
	var offset := rest + bob + Vector3(-_sway.x, _sway.y, 0)
	var rotation_offset := Vector3.ZERO
	var swing_t := (now - _swing_at) / SWING_SECONDS
	if swing_t < 1.0:
		var arc := sin(swing_t * PI)
		offset += Vector3(-0.12 * arc, 0.05 * arc, -0.14 * arc)
		rotation_offset = Vector3(-0.9 * arc, 0.35 * arc, 0.2 * arc)
	var equip_t := (now - _equip_at) / EQUIP_SECONDS
	if equip_t < 1.0:
		offset.y -= 0.35 * (1.0 - equip_t)
	position = offset * SCALE
	_arm.rotation = rotation_offset
