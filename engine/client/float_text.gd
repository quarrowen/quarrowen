extends Node3D
## A word that floats in the world for a moment and then goes: the damage off a hit, "+3" over a chest,
## a name over a thing.
##
## A `Label3D` rather than a Control positioned by projecting 3D to 2D, because a Label3D already faces
## the camera, already sorts against the world, and already shrinks with distance - all three of which
## are fiddly to redo and easy to get subtly wrong.
##
## It is drawn **through** walls on purpose (`NO_DEPTH_TEST`). A damage number that vanishes because the
## thing you hit stepped behind a post is a number you cannot read, and the whole value of it is being
## readable at a glance.

const RISE_CURVE := 0.55

var _seconds := 1.2
var _rise := 1.0
var _elapsed := 0.0
var _start := Vector3.ZERO
## What it sticks to, if anything: a node whose position it tracks so a number follows the thing it
## came off rather than hanging where the blow landed.
var _follow: Node3D = null
var _label: Label3D


func setup(text: String, at: Vector3, options: Dictionary) -> void:
	_start = at
	position = at
	_seconds = clampf(float(options.get("seconds", 1.2)), 0.1, 10.0)
	_rise = clampf(float(options.get("rise", 1.0)), -4.0, 8.0)
	_label = Label3D.new()
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true  # the same size on screen however far away, so it stays readable
	_label.font_size = 48
	_label.pixel_size = 0.0006 * clampf(float(options.get("size", 1.0)), 0.3, 4.0)
	_label.outline_size = 16
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.modulate = Color.html(String(options.get("color", "#ffffff")))
	add_child(_label)


## Sticks it to something that moves. The offset is kept so a number that appeared at chest height
## stays at chest height rather than snapping to the thing's feet.
func follow(node: Node3D) -> void:
	_follow = node
	_start = position - node.position


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _seconds:
		queue_free()
		return
	var t := _elapsed / _seconds
	if _follow != null:
		if not is_instance_valid(_follow):
			_follow = null
		else:
			position = _follow.position + _start
	# Most of the drift happens early, so it reads as the number being knocked loose rather than
	# floating away at a constant speed.
	var climbed := pow(t, RISE_CURVE) * _rise
	position.y = (_follow.position.y + _start.y if _follow != null and is_instance_valid(_follow) else _start.y) + climbed
	_label.modulate.a = 1.0 if t < 0.65 else 1.0 - (t - 0.65) / 0.35
