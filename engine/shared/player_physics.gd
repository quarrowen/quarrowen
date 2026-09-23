extends RefCounted
## Deterministic player movement shared by the server (authoritative) and the client (prediction).
## Uses axis-separated AABB-vs-voxel collision rather than Godot physics so both sides produce
## identical results from identical inputs. Tunables come from the server's mods via `Rules`.

const BlockShapes = preload("res://engine/shared/block_shapes.gd")

const DT := 1.0 / 60.0
const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62

## Crouching: slower, and the player will not walk off the block they are standing on.
const SNEAK_SPEED := 0.3
const SNEAK_EYE_DROP := 0.25
## Flying (creative): no gravity, jump rises and crouch sinks.
const FLY_SPEED := 10.0
const FLY_SPRINT := 1.8
const FLY_RISE := 8.0

const MAX_SUBSTEP := 0.45
const SKIN := 0.001
const EDGE := 0.0001

## Encoded size of one PlayerInput in bytes.
const INPUT_SIZE := 15


class Rules:
	const TUNABLES := ["walk_speed", "sprint_speed", "gravity", "jump_velocity", "terminal_velocity",
		"ground_accel", "air_accel", "swim_speed", "sink_speed"]

	## Which blocks are not whole cubes (BlockRegistry.shape_lut), so movement matches what is drawn.
	var shape_lut := PackedByteArray()
	var walk_speed := 4.3
	var sprint_speed := 5.6
	var gravity := 32.0
	var jump_velocity := 9.0
	var terminal_velocity := 60.0
	var ground_accel := 60.0
	var air_accel := 12.0
	var swim_speed := 3.0
	var sink_speed := 2.0
	var void_below := false
	## TUNABLES packed in order for the native step.
	var packed := PackedFloat32Array([4.3, 5.6, 32.0, 9.0, 60.0, 60.0, 12.0, 3.0, 2.0])
	## Supplied by the block registry, not sent separately.
	var solid_lut := PackedByteArray()
	var liquid_lut := PackedByteArray()

	func to_dict() -> Dictionary:
		var d := {"void_below": void_below}
		for key in TUNABLES:
			d[key] = get(key)
		return d

	func apply_dict(d: Dictionary) -> void:
		for key in TUNABLES:
			if d.has(key) and (d[key] is float or d[key] is int):
				set(key, clampf(float(d[key]), 0.0, 500.0))
		if d.has("void_below"):
			void_below = bool(d.void_below)
		packed = PackedFloat32Array(TUNABLES.map(func(key): return get(key)))


class State:
	## Feet position (bottom center of the AABB).
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var on_ground := false
	## Set by the server (creative or the "fly" permission); the client predicts with the same flag.
	var flying := false
	## Whether the last input was crouching (lowers the eye, used for reach and the camera).
	var sneaking := false


class PlayerInput:
	var seq := 0
	## x = strafe right, y = forward. Quantized to 1/127 on the wire.
	var move := Vector2.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var jump := false
	var sprint := false
	## Crouch: slower and no stepping off ledges; sinks while flying.
	var sneak := false

	func write(buf: StreamPeerBuffer) -> void:
		buf.put_u32(seq)
		buf.put_8(clampi(roundi(move.x * 127.0), -127, 127))
		buf.put_8(clampi(roundi(move.y * 127.0), -127, 127))
		buf.put_float(yaw)
		buf.put_float(pitch)
		buf.put_u8(int(jump) | (int(sprint) << 1) | (int(sneak) << 2))

	static func read(buf: StreamPeerBuffer) -> PlayerInput:
		var input := PlayerInput.new()
		input.seq = buf.get_u32()
		input.move = Vector2(buf.get_8() / 127.0, buf.get_8() / 127.0)
		input.yaw = buf.get_float()
		input.pitch = buf.get_float()
		var flags := buf.get_u8()
		input.jump = (flags & 1) != 0
		input.sprint = (flags & 2) != 0
		input.sneak = (flags & 4) != 0
		return input


static func eye_position(state: State) -> Vector3:
	return state.position + Vector3(0.0, EYE_HEIGHT - (SNEAK_EYE_DROP if state.sneaking else 0.0), 0.0)


static func look_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## One movement step, run identically by the client (prediction) and the server (authority).
##
## The GDScript twin of this was deleted on 2026-09-23 along with the rest; it was 94 lines that had
## to agree exactly with `native/src/physics.rs` or the symptom was rubber-banding rather than an
## error. The extension is required now, so there is one implementation and nothing to disagree with.
static func step(s: State, input: PlayerInput, world, rules: Rules) -> void:
	s.sneaking = input.sneak
	var flags := int(input.jump) | (int(input.sprint) << 1) | (int(input.sneak) << 2) | (int(s.flying) << 3)
	var out: PackedFloat32Array = world.native.step_player(s.position, s.velocity, s.on_ground, input.move,
		input.yaw, flags, rules.packed)
	s.position = Vector3(out[0], out[1], out[2])
	s.velocity = Vector3(out[3], out[4], out[5])
	s.on_ground = out[6] > 0.5


## True if a player standing at feet position `p` overlaps the unit block at `block`.
static func overlaps_block(p: Vector3, block: Vector3i) -> bool:
	return (p.x - HALF_WIDTH < block.x + 1 and p.x + HALF_WIDTH > block.x
		and p.y < block.y + 1 and p.y + HEIGHT > block.y
		and p.z - HALF_WIDTH < block.z + 1 and p.z + HALF_WIDTH > block.z)
