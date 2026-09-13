extends Node3D
## First-person view: your right arm (skin and armor sleeve) and the held item in the lower right of
## the screen. Bobs while walking, swings on attacks and mining, dips when you switch items, and
## tilts slightly with mouse movement so the hand feels attached to the body.

const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Avatar = preload("res://engine/client/avatar/avatar.gd")

## Laid out at body scale (the arm is as long as on the avatar), then shrunk towards the camera so the
## arm and item stay closer than any wall the player can stand against.
const SCALE := 0.35
const REST := Vector3(0.72, -0.62, -0.38)  # shoulder, below the right edge of the screen
const SWING_SECONDS := 0.25
const EQUIP_SECONDS := 0.2

var _arm: Node3D
var _hand: Node3D
var _item_root: Node3D
var _skin_mesh: MeshInstance3D
var _armor_mesh: MeshInstance3D
var _skin_material := StandardMaterial3D.new()
var _armor_material := StandardMaterial3D.new()
var _held: Node3D
var _held_id := -1
var _swing_at := -10.0
var _equip_at := -10.0
var _bob := 0.0
var _sway := Vector2.ZERO


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


func set_skin(texture: Texture2D) -> void:
	_skin_material.albedo_texture = texture


func set_armor(texture: Texture2D) -> void:
	_armor_material.albedo_texture = texture
	_armor_mesh.visible = texture != null


## `node` shows the held item; `id` lets the arm dip and come back up when the item changes.
func set_held(id: int, node: Node3D) -> void:
	if _held != null:
		_held.queue_free()
	_held = node
	if node != null:
		_item_root.add_child(node)
	if id != _held_id:
		_equip_at = Time.get_ticks_msec() / 1000.0
	_held_id = id


func swing() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _swing_at > SWING_SECONDS * 0.6:
		_swing_at = now


## `speed`: horizontal speed in blocks/s; `look_delta`: mouse movement this frame (pixels).
func animate(delta: float, speed: float, on_ground: bool, look_delta: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if on_ground and speed > 0.5:
		_bob += delta * speed * 2.1
	var bob := Vector3(cos(_bob) * 0.012, -absf(sin(_bob)) * 0.02, 0) * clampf(speed / 4.3, 0.0, 1.3)
	_sway = _sway.lerp(look_delta * 0.0004, minf(1.0, delta * 12.0))
	var offset := REST + bob + Vector3(-_sway.x, _sway.y, 0)
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
