extends Control
## The crafting-by-hand overlay: draws the minigame the server started (engine/shared/minigame.gd),
## sends inputs with the game time they happened at, and shows the quality the server awarded.
## Space or left click strikes / holds; arrow keys or WASD answer sequence prompts; Esc stops early
## (the item is still made, at the quality reached so far).

signal input_sent(action: String, t: float, arg: int)
signal join_requested(game_id: int)
## Local feedback for sounds: "perfect" | "good" | "miss" | "burnt" | "key_hit" | "key_miss" | "done".
signal feedback(kind: String)

const Minigame = preload("res://engine/shared/minigame.gd")
const W := 600.0
const H := 370.0
const GRADE_COLORS := {"perfect": Color(1.0, 0.84, 0.3), "good": Color(0.55, 0.9, 0.5), "miss": Color(0.45, 0.45, 0.48), "burnt": Color(0.9, 0.3, 0.2)}
const ARROWS := {"up": "↑", "right": "→", "down": "↓", "left": "←"}

var items

var _view := {}
var _game := {}
var _start_msec := 0
var _received_msec := 0
var _role := ""
var _result := {}
var _grades: Array = []
var _holding := false
var _key_flash := {}  # {t, ok}
var _buttons: HBoxContainer
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	add_child(_buttons)


func is_active() -> bool:
	return visible and not _view.is_empty()


func set_view(view: Dictionary) -> void:
	var phase := str(view.get("phase", ""))
	if phase == "done":
		_result = view.get("result", {})
		_view.phase = "done"
		_received_msec = Time.get_ticks_msec()
		_holding = false
		feedback.emit("done")
		_rebuild_buttons()
		visible = true
		return
	_view = view
	_result = {}
	_game = Minigame.new_game(view.get("def", {}), int(view.get("seed", 0)), bool(view.get("assist", false)), float(view.get("bonus", 0.0)), bool(view.get("team", false)))
	_role = str(view.get("role", ""))
	_grades.clear()
	_holding = false
	_received_msec = Time.get_ticks_msec()
	_start_msec = _received_msec + roundi(float(view.get("countdown", 0.0)) * 1000.0)
	visible = true
	_rebuild_buttons()


func close() -> void:
	visible = false
	_view = {}
	_game = {}


## The partner's input (team games).
func partner_event(action: String, t: float, arg: int) -> void:
	if _game.is_empty():
		return
	match action:
		"strike":
			_grades.append(Minigame.rate_strike(_game, _game.strikes.size(), t).grade)
			_game.strikes.append(t)
		"hold":
			_game.holds.append([t, arg != 0])


func game_time() -> float:
	return (Time.get_ticks_msec() - _start_msec) / 1000.0


func _phase() -> String:
	return str(_view.get("phase", ""))


func _process(_delta: float) -> void:
	if not visible:
		return
	if _phase() == "done" and Time.get_ticks_msec() - _received_msec > 4000:
		close()
		return
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or _view.is_empty():
		return
	if event is InputEventMouseMotion:
		return
	if event is InputEventMouseButton and _buttons.get_global_rect().has_point(event.position):
		return  # let the Stop / Close buttons take their clicks
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _phase() == "done":
			close()
		else:
			input_sent.emit("quit", maxf(game_time(), 0.0), 0)
			if _role == "bellows":
				close()
		return
	if _phase() != "playing" or game_time() < 0.0:
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	var t := game_time()
	var type: String = _game.def.type
	var press := false
	var release := false
	if event is InputEventKey and (event.physical_keycode == KEY_SPACE):
		press = event.pressed and not event.echo
		release = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _inside_panel(event.position):
		press = event.pressed
		release = not event.pressed
	if type == "sequence" and event is InputEventKey and event.pressed and not event.echo:
		var dir: int = {KEY_UP: 0, KEY_W: 0, KEY_RIGHT: 1, KEY_D: 1, KEY_DOWN: 2, KEY_S: 2, KEY_LEFT: 3, KEY_A: 3}.get(event.physical_keycode, -1)
		if dir >= 0:
			var progress := Minigame.sequence_progress(_game, t)
			if progress.index < _game.def.rounds:
				var ok: bool = Minigame.prompt(_game, progress.index) == Minigame.KEYS[dir]
				_game.keys.append([t, Minigame.KEYS[dir]])
				_key_flash = {"t": t, "ok": ok}
				feedback.emit("key_hit" if ok else "key_miss")
				input_sent.emit("key", t, dir)
	var holds := _role == "bellows" or (type == "hold" and _role.is_empty())
	if holds:
		if press and not _holding:
			_holding = true
			_game.holds.append([t, true])
			input_sent.emit("hold", t, 1)
		elif release and _holding:
			_holding = false
			_game.holds.append([t, false])
			input_sent.emit("hold", t, 0)
	elif type == "timing" and press and _game.strikes.size() < _game.def.rounds:
		var grade: String = Minigame.rate_strike(_game, _game.strikes.size(), t).grade
		_grades.append(grade)
		_game.strikes.append(t)
		feedback.emit(grade)
		input_sent.emit("strike", t, 0)
	if press or release or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _panel_rect() -> Rect2:
	return Rect2((size - Vector2(W, H)) * 0.5, Vector2(W, H))


func _inside_panel(pos: Vector2) -> bool:
	return _panel_rect().has_point(pos)


func _rebuild_buttons() -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	var add := func(text: String, action: Callable):
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(130, 36)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(action)
		_buttons.add_child(b)
	match _phase():
		"waiting":
			add.call("Start alone", func(): join_requested.emit(0))
			add.call("Cancel", func(): input_sent.emit("quit", 0.0, 0))
		"playing":
			add.call("Stop", func(): input_sent.emit("quit", maxf(game_time(), 0.0), 0))
		"done":
			add.call("Close", close)


func _draw() -> void:
	if _view.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	var r := _panel_rect()
	draw_style_box(_panel_style(), r)
	_buttons.position = r.position + Vector2(W - 20.0, H - 52.0) - Vector2(_buttons.size.x, 0)
	var def: Dictionary = _game.get("def", {})
	var title := str(def.get("title", "Craft by hand"))
	if items != null and int(_view.get("item", 0)) > 0:
		title += ": %s" % items.display_name(int(_view.item))
	_text(r.position + Vector2(24, 40), title, 22, Color(1.0, 0.82, 0.4))
	match _phase():
		"waiting":
			var left := maxf(float(_view.get("wait", 0.0)) - (Time.get_ticks_msec() - _received_msec) / 1000.0, 0.0)
			_text(r.position + Vector2(24, 100), "Waiting for a partner at this station... %d s" % ceili(left), 18, Color.WHITE)
			_text(r.position + Vector2(24, 130), "Others here can join from the co-op panel to work the bellows.", 14, Color(1, 1, 1, 0.6))
			return
		"done":
			_draw_result(r)
			return
	var t := game_time()
	match def.get("type", "timing"):
		"timing":
			_draw_timing(r, t)
		"hold":
			_draw_hold(r, t)
		"sequence":
			_draw_sequence(r, t)
	if t < 0.0:
		_text(r.position + Vector2(W * 0.5 - 20, 250), str(ceili(-t)), 40, Color.WHITE)
	var hint := _hint()
	_text(r.position + Vector2(24, H - 66), hint, 13, Color(1, 1, 1, 0.55))
	if _game.assist:
		_text(r.position + Vector2(24, 64), "Relaxed timing", 12, Color(0.6, 0.85, 1.0))


func _hint() -> String:
	var type: String = _game.def.type
	if _role == "bellows":
		return "Hold Space to pump. Keep the heat in the green band; pump just before each strike."
	if _role == "hammer":
		return "Space or click to strike inside the zone. Your partner keeps the heat up."
	match type:
		"hold":
			return "Hold Space or the mouse to raise the flow; keep it inside the band."
		"sequence":
			return "Press the arrows (or WASD) in order before time runs out."
	return "Space or click to strike while the marker is inside the glowing zone. Esc stops early."


func _draw_timing(r: Rect2, t: float) -> void:
	var i: int = _game.strikes.size()
	var bar := Rect2(r.position + Vector2(30, 120), Vector2(W - 60, 44))
	var heat := Minigame.heat(_game, maxf(t, 0.0))
	var metal := Color(0.35, 0.2, 0.15).lerp(Color(1.0, 0.55, 0.15), heat if not _game.team else clampf(heat * 1.2, 0.0, 1.0))
	draw_rect(bar, metal)
	if i < _game.def.rounds:
		var w := Minigame.zone_width(_game, i, maxf(t, 0.0)) * bar.size.x
		var cx := Minigame.zone_center(_game, i) * bar.size.x
		draw_rect(Rect2(bar.position + Vector2(cx - w * 0.5, 0), Vector2(w, bar.size.y)), Color(1.0, 0.95, 0.6, 0.55))
		draw_rect(Rect2(bar.position + Vector2(cx - w * 0.2, 0), Vector2(w * 0.4, bar.size.y)), Color(1.0, 1.0, 0.85, 0.5))
		var mx := Minigame.marker(_game, maxf(t, 0.0)) * bar.size.x
		draw_rect(Rect2(bar.position + Vector2(mx - 2, -8), Vector2(4, bar.size.y + 16)), Color.WHITE)
	draw_rect(bar, Color(0, 0, 0, 0.6), false, 2.0)
	# Strike pips.
	for k in _game.def.rounds:
		var c := Color(1, 1, 1, 0.15)
		if k < _grades.size():
			c = GRADE_COLORS.get(_grades[k], c)
		draw_circle(r.position + Vector2(40 + k * 30, 196), 10, c)
	var label := "%s %d / %d" % [str(_game.def.verb), mini(i + 1, _game.def.rounds), _game.def.rounds]
	_text(r.position + Vector2(40 + _game.def.rounds * 30 + 10, 202), label, 15, Color.WHITE)
	if _grades.size() > 0:
		var last: String = _grades.back()
		_text(r.position + Vector2(W - 150, 202), last.capitalize() + "!", 18, GRADE_COLORS.get(last, Color.WHITE))
	# Heat gauge.
	var gauge := Rect2(r.position + Vector2(30, 222), Vector2(W - 60, 12))
	draw_rect(gauge, Color(0.15, 0.15, 0.18))
	if _game.team:
		draw_rect(Rect2(gauge.position + Vector2(gauge.size.x * Minigame.HEAT_LOW, 0), Vector2(gauge.size.x * (Minigame.HEAT_HIGH - Minigame.HEAT_LOW), gauge.size.y)), Color(0.3, 0.8, 0.35, 0.5))
		draw_rect(Rect2(gauge.position + Vector2(gauge.size.x * Minigame.HEAT_BURN, 0), Vector2(gauge.size.x * (1.0 - Minigame.HEAT_BURN), gauge.size.y)), Color(0.9, 0.25, 0.2, 0.6))
		draw_rect(Rect2(gauge.position + Vector2(gauge.size.x * heat - 3, -4), Vector2(6, gauge.size.y + 8)), Color.WHITE)
		_text(gauge.position + Vector2(0, 30), "Heat%s" % ("  (pumping)" if _holding else ""), 13, Color(1, 1, 1, 0.7))
	else:
		draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * heat, gauge.size.y)), Color(1.0, 0.5, 0.15))
		_text(gauge.position + Vector2(0, 30), "Heat: the marker speeds up as the metal cools", 13, Color(1, 1, 1, 0.6))
	_draw_projection(r, t)


func _draw_hold(r: Rect2, t: float) -> void:
	var bar := Rect2(r.position + Vector2(30, 110), Vector2(W - 60, 50))
	var ct := clampf(t, 0.0, _game.def.duration)
	draw_rect(bar, Color(0.12, 0.1, 0.2))
	var half := Minigame.band_half(_game) * bar.size.x
	var cx := Minigame.band_center(_game, ct) * bar.size.x
	draw_rect(Rect2(bar.position + Vector2(cx - half, 0), Vector2(half * 2, bar.size.y)), Color(0.6, 0.4, 1.0, 0.45))
	var gx := Minigame.gauge(_game, ct) * bar.size.x
	var inside := absf(Minigame.gauge(_game, ct) - Minigame.band_center(_game, ct)) <= Minigame.band_half(_game)
	draw_rect(Rect2(bar.position + Vector2(gx - 3, -8), Vector2(6, bar.size.y + 16)), Color(0.85, 1.0, 0.85) if inside else Color.WHITE)
	draw_rect(bar, Color(0, 0, 0, 0.6), false, 2.0)
	var progress := Rect2(r.position + Vector2(30, 190), Vector2(W - 60, 10))
	draw_rect(progress, Color(0.15, 0.15, 0.18))
	draw_rect(Rect2(progress.position, Vector2(progress.size.x * ct / _game.def.duration, progress.size.y)), Color(0.6, 0.45, 1.0))
	_text(r.position + Vector2(30, 228), "In the band: %d%%%s" % [roundi(Minigame.hold_fraction(_game, ct) * 100.0 * _game.def.duration / maxf(ct, 0.05)), "  (holding)" if _holding else ""], 15, Color.WHITE)
	_draw_projection(r, t)


func _draw_sequence(r: Rect2, t: float) -> void:
	var progress := Minigame.sequence_progress(_game, maxf(t, 0.0))
	for k in _game.def.rounds:
		var pos := r.position + Vector2(40 + k * 80, 150)
		var current: bool = k == progress.index
		draw_rect(Rect2(pos - Vector2(4, 44), Vector2(64, 64)), Color(0.3, 0.25, 0.45) if current else Color(0.15, 0.15, 0.2))
		var shown: bool = k <= progress.index
		_text(pos + Vector2(10, 4), ARROWS[Minigame.prompt(_game, k)] if shown else "?", 36, Color.WHITE if current else Color(1, 1, 1, 0.4))
	if progress.index < _game.def.rounds and t >= 0.0:
		var left := 1.0 - clampf((t - progress.started) / Minigame.window(_game), 0.0, 1.0)
		var bar := Rect2(r.position + Vector2(36, 196), Vector2(W - 72, 10))
		draw_rect(bar, Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)), Color(0.4, 0.8, 1.0))
	_text(r.position + Vector2(36, 236), "%d / %d stitched" % [progress.hits, _game.def.rounds], 15, Color.WHITE)
	if not _key_flash.is_empty() and t - float(_key_flash.t) < 0.4:
		_text(r.position + Vector2(W - 150, 236), "Nice!" if _key_flash.ok else "Oops", 18, GRADE_COLORS.perfect if _key_flash.ok else GRADE_COLORS.burnt)
	_draw_projection(r, t)


func _draw_projection(r: Rect2, t: float) -> void:
	if t < 0.0:
		return
	var q := Minigame.quality_for(Minigame.score(_game, clampf(t, 0.0, Minigame.time_limit(_game))))
	_text(r.position + Vector2(W - 190, 40), "→ %s" % q.name, 16, Color.html(q.color))


func _draw_result(r: Rect2) -> void:
	var q_color := Color.html(str(_result.get("color", "#ffffff")))
	var quality_name := str(_result.get("name", "Standard"))
	_text(r.position + Vector2(24, 120), quality_name + ("!" if int(_result.get("quality", 0)) > 0 else ""), 40, q_color)
	var data: Dictionary = _result.get("data", {})
	var item_name: String = str(data.get("name", items.display_name(int(_result.get("item", 0))) if items != null else ""))
	_text(r.position + Vector2(24, 170), item_name, 18, Color.WHITE)
	var stars := "★".repeat(int(_result.get("quality", 0))) + "☆".repeat(3 - int(_result.get("quality", 0)))
	_text(r.position + Vector2(24, 210), stars, 26, q_color)
	if int(_result.get("quality", 0)) == 0:
		_text(r.position + Vector2(24, 250), "Standard quality, same as crafting normally. Practice makes perfect!", 14, Color(1, 1, 1, 0.6))


func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, W - 40, font_size, color)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	style.border_color = Color(0.45, 0.35, 0.7, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
