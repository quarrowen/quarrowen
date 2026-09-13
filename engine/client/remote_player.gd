extends Node3D
## Visual for another player. Renders slightly in the past, interpolating between server snapshots.

const INTERPOLATION_DELAY := 0.1
const MAX_BUFFER := 20
## Hide players the server stopped replicating (out of interest range).
const STALE_AFTER := 1.0

var peer_id := 0
var _buffer: Array = []  # [{time, position, yaw, pitch}]
var _head: Node3D


func setup(id: int, player_name: String) -> void:
	peer_id = id
	var color := Color.from_hsv(fmod(id * 0.618034, 1.0), 0.55, 0.9)
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = color
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = color.lightened(0.35)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.6, 1.35, 0.35)
	body.mesh = body_mesh
	body.material_override = body_material
	body.position.y = 0.675
	add_child(body)

	_head = Node3D.new()
	_head.position.y = 1.62
	add_child(_head)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = head_mesh
	head.material_override = head_material
	_head.add_child(head)
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.4, 0.12, 0.05)
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 0.05, -0.26)
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.1, 0.1, 0.12)
	visor.material_override = visor_material
	_head.add_child(visor)

	var label := Label3D.new()
	label.text = player_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.15
	label.pixel_size = 0.006
	label.font_size = 40
	label.outline_size = 10
	label.no_depth_test = true
	add_child(label)


func push_state(time: float, pos: Vector3, yaw: float, pitch: float) -> void:
	if _buffer.is_empty():
		position = pos
	_buffer.append({"time": time, "position": pos, "yaw": yaw, "pitch": pitch})
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()


func _process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	visible = now - _buffer.back().time < STALE_AFTER
	if not visible:
		_buffer = [_buffer.back()]
		return
	var render_time := now - INTERPOLATION_DELAY
	while _buffer.size() >= 2 and _buffer[1].time <= render_time:
		_buffer.pop_front()
	var a: Dictionary = _buffer[0]
	if _buffer.size() == 1 or render_time <= a.time:
		_apply(a.position, a.yaw, a.pitch)
		return
	var b: Dictionary = _buffer[1]
	var t := clampf((render_time - a.time) / maxf(b.time - a.time, 0.0001), 0.0, 1.0)
	_apply(a.position.lerp(b.position, t), lerp_angle(a.yaw, b.yaw, t), lerpf(a.pitch, b.pitch, t))


func _apply(pos: Vector3, yaw: float, pitch: float) -> void:
	position = pos
	rotation.y = yaw
	_head.rotation.x = pitch
