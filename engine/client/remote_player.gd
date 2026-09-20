extends Node3D
## Another player. Renders slightly in the past, interpolating between server snapshots, and drives an
## Avatar with the movement it sees (walking, jumping, looking around).

const NameplateScene = preload("res://engine/client/nameplate.gd")

const Avatar = preload("res://engine/client/avatar/avatar.gd")

const INTERPOLATION_DELAY := 0.1
const MAX_BUFFER := 20
## Hide players the server stopped replicating (out of interest range).
const STALE_AFTER := 1.0

var peer_id := 0
var player_name := ""
var plate = null  # Nameplate
var avatar := Avatar.new()
var _buffer: Array = []  # [{time, position, yaw, pitch}]
var _last_position := Vector3.INF
var _velocity := Vector3.ZERO
var _pitch := 0.0


func setup(id: int, name_text: String, rig: Dictionary) -> void:
	peer_id = id
	player_name = name_text
	add_child(avatar)
	avatar.build(rig)
	# The same plate creatures get, rather than a second hand-rolled label: a player with a health bar
	# and a mod's extra line should look like everything else with one. (2026-09-20)
	plate = NameplateScene.new()
	add_child(plate)
	plate.setup(float(rig.get("height", 1.8)))
	plate.apply({"name": name_text, "show_health": false})


func hurt() -> void:
	avatar.hurt()


func set_dead(dead: bool) -> void:
	avatar.set_dead(dead)


func swing() -> void:
	avatar.swing()


func push_state(time: float, pos: Vector3, yaw: float, pitch: float) -> void:
	if _buffer.is_empty():
		position = pos
	_buffer.append({"time": time, "position": pos, "yaw": yaw, "pitch": pitch})
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()


func _process(delta: float) -> void:
	if _buffer.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	visible = now - _buffer.back().time < STALE_AFTER
	if not visible:
		_buffer = [_buffer.back()]
		_last_position = Vector3.INF
		return
	var render_time := now - INTERPOLATION_DELAY
	while _buffer.size() >= 2 and _buffer[1].time <= render_time:
		_buffer.pop_front()
	var a: Dictionary = _buffer[0]
	if _buffer.size() == 1 or render_time <= a.time:
		_apply(a.position, a.yaw, a.pitch)
	else:
		var b: Dictionary = _buffer[1]
		var t := clampf((render_time - a.time) / maxf(b.time - a.time, 0.0001), 0.0, 1.0)
		_apply(a.position.lerp(b.position, t), lerp_angle(a.yaw, b.yaw, t), lerpf(a.pitch, b.pitch, t))
	if _last_position != Vector3.INF and delta > 0.0:
		_velocity = _velocity.lerp((position - _last_position) / delta, minf(1.0, delta * 12.0))
	_last_position = position
	avatar.animate(delta, _velocity, absf(_velocity.y) < 0.6, _pitch)


func _apply(pos: Vector3, yaw: float, pitch: float) -> void:
	position = pos
	rotation.y = avatar.sleep_yaw if avatar.sleep_yaw != null else yaw
	_pitch = pitch
