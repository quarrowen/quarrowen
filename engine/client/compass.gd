extends Control
## The compass strip across the top of the screen: the direction you face, with a tick for everyone
## nearby and for the places you marked (home, your grave, whatever a mod puts on the map).
##
## Bearings are relative to where the camera looks, so a tick sits where that thing actually is on screen.

const WIDTH := 460.0
const HEIGHT := 34.0
## How much of the world the strip covers, left edge to right edge.
const SPAN_DEGREES := 140.0
const LETTERS := {0.0: "N", 90.0: "E", 180.0: "S", 270.0: "W"}

var yaw := 0.0
var origin := Vector3.ZERO

var _players: Array = []
var _markers: Array = []
var _font: Font


func _ready() -> void:
	# Centred at the top of the screen, whatever the window size.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 8.0
	offset_bottom = 8.0 + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


## `state` is what the server sends for the map: {players: [...], markers: [...]}.
func receive(state: Dictionary) -> void:
	_players = state.get("players", [])
	_markers = state.get("markers", [])
	queue_redraw()


func look(new_yaw: float, at: Vector3) -> void:
	if absf(new_yaw - yaw) > 0.002 or at.distance_squared_to(origin) > 0.25:
		yaw = new_yaw
		origin = at
		queue_redraw()


func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.35)
	background.set_corner_radius_all(6)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	# The heading the player faces, as a compass bearing (0 = north, clockwise).
	var facing := fposmod(rad_to_deg(yaw) + 180.0, 360.0)
	for degrees: float in LETTERS:
		var x := _screen_x(degrees - facing)
		if x < 0.0:
			continue
		draw_line(Vector2(x, HEIGHT - 9.0), Vector2(x, HEIGHT - 2.0), Color(1, 1, 1, 0.75), 2.0)
		var text: String = LETTERS[degrees]
		draw_string(_font, Vector2(x - 4.0, HEIGHT - 12.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))
	for tick in range(0, 360, 15):
		if LETTERS.has(float(tick)):
			continue
		var x := _screen_x(tick - facing)
		if x < 0.0:
			continue
		var labelled: bool = tick % 30 == 0
		draw_line(Vector2(x, HEIGHT - (8.0 if labelled else 6.0)), Vector2(x, HEIGHT - 2.0), Color(1, 1, 1, 0.3 if labelled else 0.2), 1.0)
		if labelled:
			var degrees := str(tick)
			draw_string(_font, Vector2(x - degrees.length() * 3.0, HEIGHT - 11.0), degrees, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	for entry in _markers:
		_pin(entry.get("position", Vector3.ZERO), Color.html(str(entry.get("color", "#ffd166"))), facing, true,
			str(entry.get("label", "")))
	for entry in _players:
		if not entry.get("you", false):
			_pin(entry.get("position", Vector3.ZERO), Color(0.42, 0.72, 1.0), facing, false)
	# The centre notch and the heading it points at.
	draw_line(Vector2(WIDTH * 0.5, 0.0), Vector2(WIDTH * 0.5, HEIGHT), Color(1, 1, 1, 0.5), 1.0)
	var heading := "%d°" % roundi(fposmod(facing, 360.0))
	draw_string(_font, Vector2(WIDTH * 0.5 - heading.length() * 3.5, 13.0), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))


## Where a bearing lands on the strip, or -1 when it is behind the player.
func _screen_x(relative_degrees: float) -> float:
	var offset := fposmod(relative_degrees + 180.0, 360.0) - 180.0
	if absf(offset) > SPAN_DEGREES * 0.5:
		return -1.0
	return WIDTH * (0.5 + offset / SPAN_DEGREES)


## Ticks sit just under the heading, above the letters.
## A marker's name rides under its tick, so a countdown the server writes into the label is something
## the player watches without opening the map. Only markers get one: the same text over every nearby
## player would be a crowd of names across the sky. (the user, 2026-09-23)
func _pin(position: Vector3, color: Color, facing: float, diamond: bool, label := "") -> void:
	var to := Vector2(position.x - origin.x, position.z - origin.z)
	if to.length() < 1.0:
		return
	var bearing := rad_to_deg(atan2(to.x, -to.y))  # 0 = north (-z), clockwise
	var x := _screen_x(bearing - facing)
	if x < 0.0:
		return
	var y := 8.0
	if diamond:
		draw_colored_polygon([Vector2(x, y - 5.0), Vector2(x + 4.0, y), Vector2(x, y + 5.0), Vector2(x - 4.0, y)], color)
	else:
		draw_circle(Vector2(x, y), 4.0, color)
	draw_arc(Vector2(x, y), 5.0, 0.0, TAU, 12, Color(0, 0, 0, 0.5), 1.0)
	if label.is_empty():
		return
	# Centred under the tick, and nudged back inside the strip at either end rather than drawn off it.
	var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var text_x := clampf(x - width * 0.5, 1.0, maxf(WIDTH - width - 1.0, 1.0))
	draw_string(_font, Vector2(text_x + 1.0, y + 17.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.7))
	draw_string(_font, Vector2(text_x, y + 16.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
