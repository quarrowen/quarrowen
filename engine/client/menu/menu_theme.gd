extends RefCounted
## The main menu's look: dark glassy panels over the live world, rounded buttons with an accent colour,
## readable type. Built in code so it needs no editor resources.
##
## Two faces, both open-licensed and shipped in assets/fonts. Nunito Sans carries everything a player
## reads - it keeps its shape at the twelve pixels an item count lives at. Fredoka is for headings and
## the name: rounded and warm, the face a child recognises across a room, and soft enough at small sizes
## that it is deliberately kept away from body text. They are close cousins, so the pair reads as one
## voice. Before this the game used Godot's default and had no face of its own. (2026-09-18)

const ACCENT := Color(0.36, 0.72, 0.42)
const ACCENT_HOVER := Color(0.44, 0.8, 0.5)
const PANEL := Color(0.06, 0.08, 0.11, 0.82)
const PANEL_LIGHT := Color(1, 1, 1, 0.06)
const PANEL_SELECTED := Color(0.36, 0.72, 0.42, 0.22)
const TEXT := Color(0.94, 0.95, 0.96)
const MUTED := Color(0.94, 0.95, 0.96, 0.6)
const WARN := Color(1.0, 0.72, 0.5)
const GOOD := Color(0.5, 0.86, 0.55)
const BAD := Color(0.95, 0.45, 0.4)
## Error banners: a strong red that stands out over the world.
const ERROR := Color(0.86, 0.2, 0.18)


const BODY_FONT := "res://assets/fonts/NunitoSans.ttf"
const DISPLAY_FONT := "res://assets/fonts/Fredoka.ttf"

## Loaded once and shared: a Font is a resource, and every label asking for its own copy of a 571 KB file
## would be a waste of both memory and loading time.
static var _body: FontFile
static var _display: FontFile


static func body_font() -> FontFile:
	if _body == null and ResourceLoader.exists(BODY_FONT):
		_body = load(BODY_FONT)
	return _body


static func display_font() -> FontFile:
	if _display == null and ResourceLoader.exists(DISPLAY_FONT):
		_display = load(DISPLAY_FONT)
	return _display


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	var body := body_font()
	if body != null:
		theme.default_font = body
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	theme.set_stylebox("normal", "Button", box(Color(1, 1, 1, 0.08), 8, 10, 7))
	theme.set_stylebox("hover", "Button", box(Color(1, 1, 1, 0.16), 8, 10, 7))
	theme.set_stylebox("pressed", "Button", box(Color(1, 1, 1, 0.22), 8, 10, 7))
	theme.set_stylebox("disabled", "Button", box(Color(1, 1, 1, 0.04), 8, 10, 7))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 8, 10, 7, ACCENT))
	theme.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 6, 10, 7))
	theme.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.35), 6, 10, 7, ACCENT))
	theme.set_stylebox("read_only", "LineEdit", box(Color(0, 0, 0, 0.2), 6, 10, 7))
	theme.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.35))
	theme.set_stylebox("normal", "OptionButton", box(Color(1, 1, 1, 0.08), 6, 10, 7))
	theme.set_stylebox("hover", "OptionButton", box(Color(1, 1, 1, 0.16), 6, 10, 7))
	theme.set_stylebox("panel", "PanelContainer", box(PANEL, 14, 18, 16))
	theme.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.1, 0.13, 0.98), 8, 6, 6))
	theme.set_stylebox("panel", "AcceptDialog", box(Color(0.08, 0.1, 0.13, 0.98), 0, 16, 14))
	theme.set_stylebox("embedded_border", "Window", box(Color(0.08, 0.1, 0.13, 0.99), 12, 16, 14))
	# A dialog's own close button: the default icon all but disappears on a dark, busy backdrop.
	theme.set_icon("close", "Window", close_icon(Color(1, 1, 1, 0.75)))
	theme.set_icon("close_pressed", "Window", close_icon(ACCENT))
	theme.set_color("title_color", "Window", Color(1, 1, 1, 0.92))
	theme.set_constant("title_height", "Window", 34)
	theme.set_stylebox("grabber_area", "HSlider", box(ACCENT, 3, 0, 3))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		theme.set_stylebox(state, "CheckBox", box(Color(1, 1, 1, 0.06) if state.begins_with("hover") else Color(0, 0, 0, 0), 6, 6, 5))
	theme.set_icon("unchecked", "CheckBox", check_icon(false))
	theme.set_icon("checked", "CheckBox", check_icon(true))
	theme.set_stylebox("separator", "HSeparator", line())
	theme.set_constant("separation", "HSeparator", 12)
	return theme


static func box(color: Color, radius: int, margin_x: int, margin_y: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin_x
	s.content_margin_right = margin_x
	s.content_margin_top = margin_y
	s.content_margin_bottom = margin_y
	if border.a > 0.0:
		s.set_border_width_all(2)
		s.border_color = border
	return s


static func line() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(1, 1, 1, 0.1)
	s.thickness = 1
	return s


## A primary (accent) button.
static func primary(button: Button) -> Button:
	button.add_theme_stylebox_override("normal", box(ACCENT, 8, 18, 9))
	button.add_theme_stylebox_override("hover", box(ACCENT_HOVER, 8, 18, 9))
	button.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.15), 8, 18, 9))
	button.add_theme_color_override("font_color", Color(0.04, 0.08, 0.05))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.05, 0.03))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.05, 0.03))
	return button


## A sidebar navigation button: flat until selected.
static func nav(button: Button) -> Button:
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), 8, 14, 10))
	button.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.08), 8, 14, 10))
	button.add_theme_stylebox_override("pressed", box(PANEL_SELECTED, 8, 14, 10))
	button.add_theme_stylebox_override("hover_pressed", box(PANEL_SELECTED, 8, 14, 10))
	return button


static func heading(text: String, size := 26) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	var display := display_font()
	if display != null:
		label.add_theme_font_override("font", display)
	return label


static func muted(text: String, size := 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", size)
	return label


## A checkbox mark: a light rounded outline, or an accent square with a tick. Drawn at twice the size
## and scaled down, for smooth edges.
## The ✕ on a dialog's title bar, drawn so it reads on any backdrop.
static func close_icon(color: Color) -> ImageTexture:
	const S := 22
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var a := Vector2(6.5, 6.5)
	var b := Vector2(S - 6.5, S - 6.5)
	var c := Vector2(S - 6.5, 6.5)
	var d := Vector2(6.5, S - 6.5)
	for y in S:
		for x in S:
			var p := Vector2(x + 0.5, y + 0.5)
			var dist := minf(_segment_distance(p, a, b), _segment_distance(p, c, d))
			var stroke := clampf(1.7 - dist, 0.0, 1.0)
			var circle := clampf(0.6 - (p.distance_to(Vector2(S, S) * 0.5) - S * 0.5 + 1.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, maxf(stroke * color.a, circle * 0.18)))
	return ImageTexture.create_from_image(img)


static func check_icon(checked: bool) -> ImageTexture:
	const S := 36
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var r := 7.0
	for y in S:
		for x in S:
			# Distance outside a rounded square (negative inside).
			var qx := maxf(absf(x + 0.5 - S / 2.0) - (S / 2.0 - 2.0 - r), 0.0)
			var qy := maxf(absf(y + 0.5 - S / 2.0) - (S / 2.0 - 2.0 - r), 0.0)
			var d := Vector2(qx, qy).length() - r
			var inside := clampf(0.5 - d, 0.0, 1.0)
			if checked:
				img.set_pixel(x, y, Color(ACCENT, inside))
			else:
				var ring := clampf(0.5 - absf(d + 1.5) + 1.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, maxf(ring * 0.75, inside * 0.08)))
	if checked:
		var points := [Vector2(9, 18), Vector2(15, 24), Vector2(27, 11)]
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5)
				var dist := minf(_segment_distance(p, points[0], points[1]), _segment_distance(p, points[1], points[2]))
				var a := clampf(2.4 - dist, 0.0, 1.0)
				if a > 0.0:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.04, 0.08, 0.05), a))
	img.resize(S / 2, S / 2, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)
