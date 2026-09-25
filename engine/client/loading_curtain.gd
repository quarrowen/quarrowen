extends Control
## The black between the menu and the world: what a player looks at while a server is found, content
## downloads and the ground is built.
##
## **It exists because the old one looked broken.** The world rendered behind a status line from the
## first frame, with the compass, the belt and the health bar drawn over a half-built world - so the
## honest reading was that the game had hung, not that it was working. (the user, 2026-09-25: "it
## makes the player think the game isn't responding or hung... showing the health bar and compass
## during the connecting screen is just wonky")
##
## Three things it has to do, and the third is the one that is easy to skip:
##
## - **Cover everything**, so a half-built world is never on show.
## - **Move**, so the wait reads as work rather than as a freeze. The blocks below fill in sequence
##   whether or not anything is measurable, which matters most in the steps that have no percentage -
##   handshaking and authenticating have no fraction to report and are exactly where a still screen
##   feels hung.
## - **Leave by fading**, handing over to the arrival flight rather than cutting to it. A cut would
##   throw away the one moment the flight exists to create.

## How long the curtain takes to go, and how long a step of the block animation lasts.
const FADE_SECONDS := 0.9
const BLOCK_SECONDS := 0.18
const BLOCKS := 7

var _title: Label
var _status: Label
var _bar: ProgressBar
var _blocks: Array[Panel] = []
var _elapsed := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind this is ready to be clicked on
	var black := ColorRect.new()
	black.color = Color(0.02, 0.025, 0.035)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 22)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = _label(34, Color(0.92, 0.94, 0.98))
	_title.text = "Quarrowen"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# A row of blocks that lights along, in the game's own vocabulary rather than a spinner borrowed
	# from a web page. Cheap: seven panels and one modulate each.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for i in BLOCKS:
		var block := Panel.new()
		block.custom_minimum_size = Vector2(16, 16)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.55, 0.78, 0.45)
		style.set_corner_radius_all(3)
		block.add_theme_stylebox_override("panel", style)
		row.add_child(block)
		_blocks.append(block)

	_status = _label(15, Color(0.72, 0.76, 0.82))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 8)
	_bar.show_percentage = false
	_bar.visible = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.78, 0.45)
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	back.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	column.add_child(_bar)


## The line under the title: "Connecting…", "Downloading…", "Loading terrain…".
func status(text: String) -> void:
	if _status != null:
		_status.text = text


## The bar, or anything negative to hide it. Most of the steps have nothing to measure, which is why
## the blocks above keep moving regardless.
func progress(fraction: float) -> void:
	if _bar == null:
		return
	_bar.visible = fraction >= 0.0
	_bar.value = clampf(fraction, 0.0, 1.0) * 100.0


## The world is ready. Fades out and frees itself; safe to call twice.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	fade.tween_callback(queue_free)


func _process(delta: float) -> void:
	if _leaving or _blocks.is_empty():
		return
	_elapsed += delta
	# One block lit at a time, running along and starting again - a thing that is plainly still going
	# even when nothing can be measured.
	var lit := int(_elapsed / BLOCK_SECONDS) % _blocks.size()
	for i in _blocks.size():
		_blocks[i].modulate.a = 1.0 if i == lit else 0.22


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
