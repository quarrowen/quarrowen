extends Control
## The on-screen controls: a thumbstick to walk with, a drag area to look with, and the buttons a
## keyboard would otherwise carry. Shown on a touchscreen, or anywhere with `QW_TOUCH=1`.
##
## **It drives the game through the same actions a keyboard does**, with `Input.action_press` and
## `action_release`, rather than through a parallel input path of its own. That is the whole design:
## movement polls `Input.get_vector`, mining polls `is_action_pressed`, and both already handle
## analogue strength, hold-to-repeat, progressive break timers and hold-to-eat. A second implementation
## would have had to grow all of that again and drift from it. The one thing actions cannot express is
## looking, because there is no "look" action - that calls `GameClient.add_look` directly.
##
## The engine's rule applies here too: this is a *capability* (a way to play without a keyboard), not
## content. It names no block and no game.
##
## **A tap already acts as a click**, because Godot's `emulate_mouse_from_touch` defaults to true - which
## is why the backpack, crafting, the palette and the avatar editor need no touch handling of their own
## despite all reading raw mouse buttons. Writing that into `project.godot` to make it a decision rather
## than an accident does not work: Godot drops any setting equal to its own default the next time the
## game saves the file, so the note vanished on the first e2e run. It is recorded here instead, which
## is the only place it survives. (2026-09-27)
##
## Laid out for thumbs rather than for a mouse: everything a hand rests on is at an edge, nothing that
## matters sits in the middle where a finger would cover it, and the two halves of the screen are
## independent so walking and looking can happen at once.

const STICK_RADIUS := 78.0
## How far the thumb must leave the centre before it counts as a direction. Below this a resting thumb
## would twitch the player, which reads as drift rather than as input.
const STICK_DEADZONE := 0.18
## Look sensitivity, as a multiplier on the mouse setting. A finger travels much further than a mouse
## for the same intent, so the same number would make the camera unusable.
const LOOK_SCALE := 0.55
const BUTTON_SIZE := Vector2(64, 64)
const MOVE_ACTIONS := ["move_left", "move_right", "move_back", "move_forward"]

var _client
var _stick_base: Control
var _stick_knob: Control
## The touch currently driving each half, by index: a finger that began on the left drives the stick
## until it lifts, even if it wanders across the middle. Tracking by index rather than by position is
## what lets one thumb walk while the other looks.
var _stick_touch := -1
var _look_touch := -1
var _stick_origin := Vector2.ZERO
var _held: Dictionary = {}  # action -> true, for the buttons being pressed


func _init(client) -> void:
	_client = client
	name = "TouchControls"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The overlay itself must not swallow presses: the two drag halves below are what read them, and
	# everything else on the HUD (the menu button, the hotbar) has to stay reachable through it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_stick()
	_build_buttons()


func _build_stick() -> void:
	# **Anchors and offsets, not `position`.** A control anchored to an edge takes its place from its
	# offsets; assigning `position` as well fights them and the first attempt put the stick half off the
	# bottom of the screen and the buttons through the right edge. Photographed, which is the only
	# reason it was noticed. (2026-09-27)
	_stick_base = Panel.new()
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_stick_base, 0.0, 1.0, Vector2(STICK_RADIUS * 2.0, STICK_RADIUS * 2.0), Vector2(40, -40))
	_stick_base.add_theme_stylebox_override("panel", _round(Color(1, 1, 1, 0.16), STICK_RADIUS))

	_stick_knob = Panel.new()
	_stick_knob.size = Vector2(62, 62)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.add_theme_stylebox_override("panel", _round(Color(1, 1, 1, 0.38), 31.0))
	_stick_base.add_child(_stick_knob)
	_centre_knob()


func _build_buttons() -> void:
	# Bottom right, where the other thumb already rests. Offsets are from that corner, so both are
	# negative and account for the control's own size. Jump is largest: pressed most, and missed most.
	_add_button("jump", "JUMP", Vector2(-40, -40), Vector2(96, 96))
	_add_button("break", "MINE", Vector2(-40, -150), BUTTON_SIZE)
	_add_button("place", "PUT", Vector2(-148, -150), BUTTON_SIZE)
	_add_button("sneak", "DOWN", Vector2(-148, -40), BUTTON_SIZE)
	_add_button("sprint", "RUN", Vector2(-256, -40), BUTTON_SIZE)
	_add_button("inventory", "BAG", Vector2(-256, -150), BUTTON_SIZE)


## One button that holds its action down for as long as it is touched, because `break` and `place` both
## mean something different held than tapped - progressive mining, repeat placing, eating a meal.
func _add_button(action: String, glyph: String, at: Vector2, size: Vector2) -> void:
	var button := Button.new()
	button.text = glyph
	button.focus_mode = Control.FOCUS_NONE
	# Words rather than symbols: these are read by a child who has not met this game before, and "MINE"
	# needs no legend where a pickaxe glyph does.
	button.add_theme_font_size_override("font_size", 15)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.modulate = Color(1, 1, 1, 0.82)
	_anchor(button, 1.0, 1.0, size, at)
	button.button_down.connect(func(): _press(action))
	button.button_up.connect(func(): _release(action))


## Places a control against an edge by its anchors, sizing it explicitly. `ax`/`ay` pick the corner
## (0 = left/top, 1 = right/bottom) and `at` is the offset from it, negative where the anchor is 1.
func _anchor(control: Control, ax: float, ay: float, control_size: Vector2, at: Vector2) -> void:
	control.anchor_left = ax
	control.anchor_right = ax
	control.anchor_top = ay
	control.anchor_bottom = ay
	control.offset_left = at.x - (control_size.x if ax > 0.5 else 0.0)
	control.offset_right = control.offset_left + control_size.x
	control.offset_top = at.y - (control_size.y if ay > 0.5 else 0.0)
	control.offset_bottom = control.offset_top + control_size.y
	add_child(control)


func _press(action: String) -> void:
	# `inventory` is a screen rather than a held state, and pressing it as an action would need a real
	# event to reach the handler in _unhandled_input. Call the client instead.
	if action == "inventory":
		_client.toggle_inventory()
		return
	_held[action] = true
	Input.action_press(action)


func _release(action: String) -> void:
	_held.erase(action)
	Input.action_release(action)


## **A touch that starts on the left walks; one that starts on the right looks.** Split down the middle
## rather than by named zones: a child's thumbs land where the screen is comfortable, not where a
## rectangle was drawn, and the halves are large enough that neither needs aiming for.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_touch(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			_move_stick(event.position)
		elif event.index == _look_touch and _client.has_method("add_look"):
			_client.add_look(event.relative * LOOK_SCALE, event.relative * LOOK_SCALE)


func _begin_touch(index: int, at: Vector2) -> void:
	var left := at.x < size.x * 0.5
	if left and _stick_touch < 0:
		_stick_touch = index
		# The stick appears under the thumb rather than at a fixed spot, so a walk never starts with a
		# reach. The drawn circle moves to meet the finger.
		_stick_origin = at
		_stick_base.global_position = at - _stick_base.size * 0.5
		_move_stick(at)
	elif not left and _look_touch < 0:
		_look_touch = index


func _end_touch(index: int) -> void:
	if index == _stick_touch:
		_stick_touch = -1
		_centre_knob()
		for action in MOVE_ACTIONS:
			Input.action_release(action)
	elif index == _look_touch:
		_look_touch = -1


func _move_stick(at: Vector2) -> void:
	var offset := at - _stick_origin
	var reach := offset.limit_length(STICK_RADIUS)
	_stick_knob.position = _stick_base.size * 0.5 + reach - _stick_knob.size * 0.5
	var pull := reach / STICK_RADIUS
	if pull.length() < STICK_DEADZONE:
		for action in MOVE_ACTIONS:
			Input.action_release(action)
		return
	# Pressed with a strength, so `Input.get_vector` gives the analogue value the movement code already
	# expects - walking slowly is a half-pushed stick, exactly as it is on a gamepad.
	_axis("move_left", "move_right", pull.x)
	_axis("move_back", "move_forward", -pull.y)


func _axis(negative: String, positive: String, value: float) -> void:
	Input.action_release(negative if value > 0.0 else positive)
	if absf(value) < STICK_DEADZONE:
		Input.action_release(negative)
		Input.action_release(positive)
		return
	Input.action_press(positive if value > 0.0 else negative, absf(value))


func _centre_knob() -> void:
	_stick_knob.position = (_stick_base.size - _stick_knob.size) * 0.5


func _round(colour: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(int(radius))
	return box


## Lets go of everything. Called when the world is left or a menu opens, so a finger that was holding
## `break` when a screen appeared does not leave the player mining for ever.
func release_all() -> void:
	for action in _held.keys():
		Input.action_release(action)
	_held.clear()
	for action in MOVE_ACTIONS:
		Input.action_release(action)
	_stick_touch = -1
	_look_touch = -1
	_centre_knob()
