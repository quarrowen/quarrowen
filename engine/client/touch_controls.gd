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
## **On the world itself**: a tap breaks, a two-finger tap uses, a still finger mines, and a finger that
## moves turns the view. The buttons do the same things and stay, because a gesture nobody is told about
## is a gesture a child will not find - they are the discoverable route and these are the quick one.
##
## Laid out for thumbs rather than for a mouse: everything a hand rests on is at an edge, nothing that
## matters sits in the middle where a finger would cover it, and the two halves of the screen are
## independent so walking and looking can happen at once.

const STICK_RADIUS := 58.0
## How far the thumb must leave the centre before it counts as a direction. Below this a resting thumb
## would twitch the player, which reads as drift rather than as input.
const STICK_DEADZONE := 0.18
## Baseline look sensitivity, before the player's `controls/touch_sensitivity` multiplies it. Raised
## from 0.55 after the first go on hardware read as sluggish (the user, 2026-09-27) - a finger covers
## several centimetres where a mouse covers a few millimetres, and 0.55 was scaling the wrong way.
const LOOK_SCALE := 1.6
## **Sized for a 590 x 410 interface space, not a 1180 x 820 one.** The window is scaled 2x for HiDPI,
## so the HUD's own coordinates are half the pixels - measured, after a layout built for the larger
## number crowded every button into the top of the screen and pushed the ring off it. The hotbar's slots
## are 58 units in this space, which is the scale everything here is judged against. (2026-09-27)
const BUTTON_SIZE := Vector2(54, 54)
## **How much of the bottom edge the hotbar owns.** Nothing of ours may sit in it. The buttons were
## anchored 40 units up, which clears the belt on a wide screen and lands on top of slots five to nine
## on a squarer one - Godot's content scaling keeps the *height*, so a narrower screen has a narrower
## viewport in these units and anything anchored to opposite edges moves towards the middle. A 1.93:1
## desktop shot showed no overlap; a 1.44:1 tablet had it all along. (the user, 2026-09-27: "the button
## for run is actually overlapping with the action bar")
## **Measured rather than guessed, 30 September 2026.** It was 76, and the belt is 82 tall from the
## bottom of the screen: a touch hotbar slot is 58 (`game_client.gd`), its frame adds a 7-unit content
## margin on each side, and the frame sits 10 up - so 10 + 7 + 58 + 7 = 82. Everything anchored to this
## band was six units too low and clipped the belt it exists to clear.
##
## It is still a literal, which is the actual fragility: this file cannot see any of the three numbers
## it is derived from, so the next change to the hotbar moves the belt and leaves this behind again.
## Having the hotbar publish its own height is the fix and is not this change.
const BELT_BAND := 82.0
## **The ring of things you stop to do.** Crafting, the map, chat, dropping and the creative palette have
## no business as permanent buttons - a child's thumbs cannot cover eleven - and the pause menu is the
## wrong home for them because you pause to *stop* and you craft in the middle of playing. A ring opened
## from a button is reachable by construction, holds all of them, and costs one button's worth of screen.
## (the user, 2026-09-27: "maybe a fly out radial menu ux is worth considering..? ... yes a button opens
## it") Hung off a button rather than a bare gesture, because a child does not discover an invisible one.
const RING_RADIUS := 92.0
const RING_ITEM := Vector2(50, 50)
## **Tapping the world acts on it.** A finger that presses the looking half and does not travel is
## reaching for the block in front of it, not turning the view - so a tap swings, and a press held still
## mines, and only a finger that actually moves turns the camera. The buttons stay, because they are
## what a child finds first and because they work while the other thumb is walking. (the user,
## 2026-09-27: "tap should mine/break/use right?")
##
## How far a finger may wander and still count as a tap rather than a drag. Generous: nobody holds a
## tablet perfectly still, and a tap that turns into a look because a thumb shifted two pixels feels
## broken rather than precise.
const TAP_SLOP := 16.0
## How long a still finger waits before it starts mining rather than waiting to be a tap.
const HOLD_BEGINS := 0.18
## How long a tap holds its action down, so the game sees a press and a release rather than neither.
const TAP_HOLD := 0.12
## **Two fingers use instead of breaking**, which is where a mouse's second button went. One finger on
## the world is the destructive one and two is the careful one - opening a chest, eating, placing - and
## that is the right way round for a child, because the careful action is the one that takes more
## deliberate effort. The PUT button stays, so nobody has to discover this to play. (the user,
## 2026-09-27: "tap is mine/break and tap with two fingers is use/open")
const TWO_FINGER_ACTION := "place"
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")

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
var _look_origin := Vector2.ZERO
var _look_held := 0.0
## True once the finger has travelled far enough to be turning the view, which rules out acting.
var _look_is_drag := false
## True while a still finger is holding `break` down for progressive mining.
var _world_mining := false
## Counts down while a tap's `break` press is still held.
var _tap_release_in := 0.0
## Which action a tap is still holding down, so the right one is released.
var _tap_action := "break"
## Set when a second finger lands on the looking half, so lifting the first does not also swing.
var _two_fingered := false
var _held: Dictionary = {}  # action -> true, for the buttons being pressed
var _ring_items: Array[Button] = []
var _thumb_buttons: Array[Button] = []
var _ring_open := false


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
	_anchor(_stick_base, 0.0, 1.0, Vector2(STICK_RADIUS * 2.0, STICK_RADIUS * 2.0), Vector2(40, -BELT_BAND))
	_stick_base.add_theme_stylebox_override("panel", _round(Color(1, 1, 1, 0.16), STICK_RADIUS))

	_stick_knob = Panel.new()
	_stick_knob.size = Vector2(62, 62)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.add_theme_stylebox_override("panel", _round(Color(1, 1, 1, 0.38), 31.0))
	_stick_base.add_child(_stick_knob)
	_centre_knob()


func _build_buttons() -> void:
	# **Hugging the right edge rather than reaching into the middle.** A thumb pivots from where the
	# hand grips the side, so its comfortable range is an arc along that edge - a block of buttons
	# spreading inward puts the far column at the end of the stretch, which is where `run` and the
	# backpack had ended up. Two short columns instead of three: 184 units from the edge rather than
	# 320, and all of it in the lower half where a thumb rests. (the user, 2026-09-27: "lining the icons
	# up on the sides of the screen would be better for accessibility... easier to reach")
	#
	# Jump is largest and lowest: pressed most, and missed most.
	_add_button("jump", "jump", "Jump", Vector2(-22, -BELT_BAND), Vector2(72, 72))
	_add_button("sneak", "crouch", "Crouch", Vector2(-102, -BELT_BAND), BUTTON_SIZE)
	_add_button("break", "mine", "Mine", Vector2(-22, -BELT_BAND - 80.0), BUTTON_SIZE)
	_add_button("place", "place", "Place", Vector2(-102, -BELT_BAND - 80.0), BUTTON_SIZE)
	_add_button("sprint", "run", "Run", Vector2(-22, -BELT_BAND - 142.0), BUTTON_SIZE)
	# The backpack moves into the ring: it is opened between things rather than during them, and its slot
	# is worth more as the way to everything else.
	_add_button("more", "more", "More", Vector2(-102, -BELT_BAND - 142.0), BUTTON_SIZE)
	_build_ring()


## One button that holds its action down for as long as it is touched, because `break` and `place` both
## mean something different held than tapped - progressive mining, repeat placing, eating a meal.
func _add_button(action: String, icon: String, label: String, at: Vector2, size: Vector2) -> void:
	var button := Button.new()
	button.tooltip_text = label
	button.focus_mode = Control.FOCUS_NONE
	# **A picture rather than a word** (the user, 2026-09-27). The first version spelled them out, on the
	# reasoning that "MINE" needs no legend - but these are pressed by a child who may not read quickly,
	# and a pickaxe is understood before a word is decoded. Glyphs rather than a mod's item textures,
	# because the engine may not reach into content for its own interface.
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.modulate = Color(1, 1, 1, 0.82)
	_anchor(button, 1.0, 1.0, size, at)
	var drawing := Icon.new(icon)
	drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(drawing)
	button.button_down.connect(func(): _press(action))
	button.button_up.connect(func(): _release(action))
	_thumb_buttons.append(button)


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


## The ring: laid out on an arc rather than a full circle, because it opens from a corner and half a
## circle would be off the screen. It fans up and to the left, which is where the screen is.
func _build_ring() -> void:
	# **Anchored from the same corner as every other button, not positioned inside a nested control.**
	# The first version parented them to a tiny Control and set `position` on each, which put the whole
	# ring across the compass - a nested coordinate space that has to be reasoned about is one that gets
	# reasoned about wrongly. Each item is placed by the same `_anchor` the thumb buttons use.
	var centre := Vector2(-102.0 - RING_ITEM.x * 0.5, -(BELT_BAND + 142.0) - BUTTON_SIZE.y * 0.5)
	var items := [["inventory", "bag", "Backpack"], ["crafting", "craft", "Crafting"], ["map", "map", "Map"],
		["chat", "chat", "Chat"], ["drop", "drop", "Drop"], ["palette", "palette", "Blocks"]]
	for i in items.size():
		# A quarter turn, from straight left round to straight up: the only quadrant with screen in it
		# when the opener sits in the bottom right corner.
		# Half a turn - left, up, and round to the right - because six items on a quarter arc at this
		# radius overlap one another. There is room to the right: the opener is not against the edge.
		var angle: float = PI + PI * (float(i) / float(items.size() - 1))
		var at := centre + Vector2(cos(angle), sin(angle)) * RING_RADIUS + RING_ITEM * 0.5
		var button := Button.new()
		button.tooltip_text = String(items[i][2])
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.visible = false
		button.add_theme_stylebox_override("normal", _round(Color(0.08, 0.08, 0.09, 0.82), 12.0))
		button.add_theme_stylebox_override("hover", _round(Color(0.16, 0.16, 0.18, 0.90), 12.0))
		button.add_theme_stylebox_override("pressed", _round(Color(0.24, 0.24, 0.26, 0.94), 12.0))
		_anchor(button, 1.0, 1.0, RING_ITEM, at)
		var action: String = items[i][0]
		button.pressed.connect(func():
			_toggle_ring(false)
			_press(action))
		var drawing := Icon.new(String(items[i][1]))
		drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(drawing)
		_ring_items.append(button)


func _toggle_ring(open: bool) -> void:
	_ring_open = open
	for button in _ring_items:
		button.visible = open
	# **The action buttons go while the ring is up.** The arc reaches across where they sit, and two
	# overlapping sets of round buttons is both ugly and a mis-tap waiting to happen. Hiding them also
	# says plainly that the ring is the thing being answered. The opener stays, so there is a way back.
	for button in _thumb_buttons:
		if button.tooltip_text != "More":
			button.visible = not open
	if open:
		# Anything being held when the ring opens is let go of, or a finger that was mining carries on
		# mining behind a menu.
		for action in _held.keys():
			Input.action_release(action)
		_held.clear()


func _press(action: String) -> void:
	# **These open screens, and a screen opens from an event this cannot send.** Pressing the action
	# would update the polled state and reach nothing, so each calls the client directly.
	match action:
		"more":
			_toggle_ring(not _ring_open)
			return
		"inventory":
			_client.toggle_inventory()
			return
		"crafting":
			_client.open_crafting()
			return
		"map":
			_client.toggle_map()
			return
		"chat":
			_client.open_chat()
			return
		"drop":
			_client.drop_selected()
			return
		"palette":
			_client.open_palette()
			return
	_held[action] = true
	Input.action_press(action)


func _release(action: String) -> void:
	if not _held.has(action):
		return  # a screen opener, not a held action - there is nothing pressed to let go of
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
			if not _look_is_drag and event.position.distance_to(_look_origin) > TAP_SLOP:
				_look_is_drag = true
				_stop_mining()  # it turned out to be a look after all
			if not _look_is_drag:
				return
			# Its own scale, so the mouse setting does not also move the thumb (see GameClient.add_look).
			var turn: float = LOOK_SCALE * float(ClientSettings.shared().get_value("controls/touch_sensitivity"))
			_client.add_look(event.relative, event.relative, turn)


## Which half of the controls a touch landed in. **Both sides of the comparison have to be in the same
## space**, and they were not: `at` is a viewport coordinate and `size` belongs to this node, which sits
## inside `_hud_root` and is inset by the device's safe area. Wherever the landscape left inset is not
## zero - which is every iPhone, and no iPad - the divider sat off-centre by exactly that inset, so a
## band down the middle of the screen walked when it should have looked. Invisible on the only hardware
## it was ever tried on. (2026-09-30)
##
## Static and given its numbers rather than reading them, so the arithmetic can be asserted without a
## viewport, a device or a screenshot.
static func is_left_half(touch_x: float, origin_x: float, width: float) -> bool:
	return touch_x < origin_x + width * 0.5


func _begin_touch(index: int, at: Vector2) -> void:
	var left := is_left_half(at.x, global_position.x, size.x)
	if left and _stick_touch < 0:
		_stick_touch = index
		# The stick appears under the thumb rather than at a fixed spot, so a walk never starts with a
		# reach. The drawn circle moves to meet the finger.
		_stick_origin = at
		_stick_base.global_position = at - _stick_base.size * 0.5
		_move_stick(at)
	elif not left and _look_touch < 0:
		_look_touch = index
		_look_origin = at
		_look_held = 0.0
		_look_is_drag = false
		_two_fingered = false
	elif not left and not _look_is_drag:
		# A second finger on the looking half, before the first became a drag: use rather than break.
		_stop_mining()
		_two_fingered = true
		_pulse(TWO_FINGER_ACTION)


func _end_touch(index: int) -> void:
	if index == _stick_touch:
		_stick_touch = -1
		_centre_knob()
		for action in MOVE_ACTIONS:
			Input.action_release(action)
	elif index == _look_touch:
		_look_touch = -1
		if _world_mining:
			_stop_mining()
		elif not _look_is_drag and not _two_fingered:
			_pulse("break")
		_look_is_drag = false
		_two_fingered = false


## Presses an action and lets go a moment later. **Not press-and-release in one frame**: the game polls
## `is_action_just_pressed`, and a press that has already ended by the time it looks is a press that
## never happened.
func _pulse(action: String) -> void:
	if _tap_release_in > 0.0:
		Input.action_release(_tap_action)
	_tap_action = action
	Input.action_press(action)
	_tap_release_in = TAP_HOLD


func _stop_mining() -> void:
	if _world_mining:
		_world_mining = false
		Input.action_release("break")


func _process(delta: float) -> void:
	if _tap_release_in > 0.0:
		_tap_release_in -= delta
		if _tap_release_in <= 0.0:
			Input.action_release(_tap_action)
	if _look_touch >= 0 and not _look_is_drag and not _world_mining:
		_look_held += delta
		if _look_held >= HOLD_BEGINS:
			_world_mining = true
			Input.action_press("break")


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
	_stop_mining()
	if _tap_release_in > 0.0:
		_tap_release_in = 0.0
		Input.action_release(_tap_action)
	_stick_touch = -1
	_look_touch = -1
	_look_is_drag = false
	_centre_knob()


## **The icons are drawn, not typed.** They were emoji and symbol characters first, which looked right
## on the development machine and arrived on the iPad as six empty squares: the project ships its own
## typeface and that typeface has no pickaxe in it, and iOS does not fall back to a symbol font the way
## macOS quietly did. A glyph is a dependency on whatever font happens to be installed; a few lines and
## polygons are not, and this project already draws its own textures rather than shipping them.
## (the user, 2026-09-27: "the buttons for jump, mine, etc are all empty squares")
class Icon extends Control:
	var kind := ""

	func _init(of: String) -> void:
		kind = of
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ink := Color(0.97, 0.97, 0.94, 0.96)
		var unit: float = minf(size.x, size.y)
		var mid: Vector2 = size * 0.5
		var stroke: float = maxf(unit * 0.09, 2.0)
		match kind:
			"jump": _arrow(mid, unit, ink, -1.0)
			"crouch": _arrow(mid, unit, ink, 1.0)
			"run": _run(mid, unit, ink, stroke)
			"mine": _pick(mid, unit, ink, stroke)
			"place": _block(mid, unit, ink)
			"bag": _bag(mid, unit, ink, stroke)
			"more": _more(mid, unit, ink)
			"craft": _craft(mid, unit, ink, stroke)
			"map": _map(mid, unit, ink, stroke)
			"chat": _chat(mid, unit, ink, stroke)
			"drop": _drop(mid, unit, ink, stroke)
			"palette": _palette(mid, unit, ink)

	## An arrow, point up (-1) or down (+1): a head and a stem, as one polygon each.
	func _arrow(mid: Vector2, unit: float, ink: Color, dir: float) -> void:
		# `dir` is -1 for up and +1 for down, and the head follows it directly. It was negated here as
		# well as in the caller, so jump pointed down and crouch pointed up - which a screenshot showed
		# at once and no amount of reading would have.
		var head := PackedVector2Array([
			mid + Vector2(0.0, dir * 0.32 * unit),
			mid + Vector2(0.26 * unit, dir * 0.04 * unit),
			mid + Vector2(-0.26 * unit, dir * 0.04 * unit)])
		draw_colored_polygon(head, ink)
		draw_rect(Rect2(mid.x - 0.10 * unit, mid.y - (0.30 * unit if dir > 0.0 else 0.04 * unit),
			0.20 * unit, 0.34 * unit), ink)

	## Two chevrons, the way speed is drawn everywhere.
	func _run(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		for i in 2:
			var x: float = mid.x + (-0.20 + float(i) * 0.22) * unit
			draw_polyline(PackedVector2Array([
				Vector2(x, mid.y - 0.22 * unit),
				Vector2(x + 0.16 * unit, mid.y),
				Vector2(x, mid.y + 0.22 * unit)]), ink, stroke)

	## A pickaxe: a shaft, and a shallow arc across the top for the head.
	func _pick(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		draw_line(mid + Vector2(0.10 * unit, -0.14 * unit), mid + Vector2(-0.06 * unit, 0.34 * unit), ink, stroke)
		draw_polyline(PackedVector2Array([
			mid + Vector2(-0.32 * unit, -0.06 * unit),
			mid + Vector2(0.02 * unit, -0.30 * unit),
			mid + Vector2(0.34 * unit, -0.06 * unit)]), ink, stroke)

	## A block, drawn as a cube so it reads as a thing you place rather than a square.
	func _block(mid: Vector2, unit: float, ink: Color) -> void:
		var top := mid + Vector2(0.0, -0.30 * unit)
		var right := mid + Vector2(0.28 * unit, -0.14 * unit)
		var left := mid + Vector2(-0.28 * unit, -0.14 * unit)
		var centre := mid + Vector2(0.0, 0.02 * unit)
		draw_colored_polygon(PackedVector2Array([top, right, centre, left]), ink)
		draw_colored_polygon(PackedVector2Array([left, centre,
			centre + Vector2(0.0, 0.28 * unit), left + Vector2(0.0, 0.28 * unit)]), Color(ink, ink.a * 0.72))
		draw_colored_polygon(PackedVector2Array([right, centre,
			centre + Vector2(0.0, 0.28 * unit), right + Vector2(0.0, 0.28 * unit)]), Color(ink, ink.a * 0.50))

	## Six dots: the universal "and the rest", and the only one here that should not look like a thing.
	func _more(mid: Vector2, unit: float, ink: Color) -> void:
		for row in 2:
			for col in 3:
				draw_circle(mid + Vector2((float(col) - 1.0) * 0.22, (float(row) - 0.5) * 0.24) * unit,
					unit * 0.055, ink)

	## A crafting grid: four squares with a gap, which is what a recipe looks like everywhere.
	func _craft(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		for row in 2:
			for col in 2:
				var at := mid + Vector2(float(col) - 1.0, float(row) - 1.0) * 0.30 * unit + Vector2(0.03, 0.03) * unit
				draw_rect(Rect2(at, Vector2(0.24, 0.24) * unit), ink, false, stroke)

	## A folded map: a rectangle with the two creases that make it read as paper rather than a card.
	func _map(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		draw_rect(Rect2(mid - Vector2(0.32, 0.24) * unit, Vector2(0.64, 0.48) * unit), ink, false, stroke)
		for x in [-0.11, 0.11]:
			draw_line(mid + Vector2(x * unit, -0.24 * unit), mid + Vector2(x * unit, 0.24 * unit), ink, stroke * 0.7)

	## A speech bubble, with the tail that stops it being a rounded rectangle.
	func _chat(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		draw_rect(Rect2(mid - Vector2(0.32, 0.28) * unit, Vector2(0.64, 0.44) * unit), ink, false, stroke)
		draw_polyline(PackedVector2Array([
			mid + Vector2(-0.14, 0.16) * unit, mid + Vector2(-0.20, 0.34) * unit,
			mid + Vector2(-0.02, 0.16) * unit]), ink, stroke)

	## An arrow leaving a hand: a block, and a line away from it downward.
	func _drop(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		draw_rect(Rect2(mid - Vector2(0.20, 0.34) * unit, Vector2(0.40, 0.26) * unit), ink)
		draw_line(mid + Vector2(0.0, 0.0), mid + Vector2(0.0, 0.26 * unit), ink, stroke)
		draw_colored_polygon(PackedVector2Array([
			mid + Vector2(0.0, 0.36 * unit), mid + Vector2(0.16, 0.16) * unit,
			mid + Vector2(-0.16, 0.16) * unit]), ink)

	## A painter's palette, as four squares of different weight - the creative block picker.
	func _palette(mid: Vector2, unit: float, ink: Color) -> void:
		var shades := [1.0, 0.74, 0.52, 0.34]
		for i in 4:
			var at := mid + Vector2(float(i % 2) - 1.0, float(i / 2) - 1.0) * 0.30 * unit + Vector2(0.03, 0.03) * unit
			draw_rect(Rect2(at, Vector2(0.24, 0.24) * unit), Color(ink, ink.a * shades[i]))

	## A backpack: a body with a flap across it, and a small handle. **Not a padlock** - the first
	## version put a round strap over a square body with a dark block in the middle of it, which is a
	## padlock in every particular.
	func _bag(mid: Vector2, unit: float, ink: Color, stroke: float) -> void:
		draw_rect(Rect2(mid.x - 0.28 * unit, mid.y - 0.16 * unit, 0.56 * unit, 0.46 * unit), ink)
		# The flap: a band across the top of the body, darker so it reads as a separate piece.
		draw_rect(Rect2(mid.x - 0.28 * unit, mid.y - 0.16 * unit, 0.56 * unit, 0.16 * unit),
			Color(ink, ink.a * 0.55))
		# A short handle, wider than it is tall, sitting on top rather than arching over the whole bag.
		draw_arc(mid + Vector2(0.0, -0.16 * unit), 0.11 * unit, PI, TAU, 12, ink, stroke)
