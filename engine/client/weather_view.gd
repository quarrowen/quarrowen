extends Node3D
## Draws whatever the sky is doing: particles overhead, a tint on the sky, the light pulled down, and a
## sound that loops while it falls.
##
## The particles are parked above the camera and follow it, rather than filling the world. A player only
## ever sees the weather within a few blocks of themselves, so simulating it anywhere else is spending a
## thousand particles to be right about somewhere nobody is looking.
##
## Nothing here decides anything. The server says which weather and how hard; this draws that, and
## crossfades when it changes so a storm arrives rather than appears.

const WeatherRegistry = preload("res://engine/shared/weather_registry.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")

const FADE := 2.5  # seconds for weather to arrive or leave

var registry := WeatherRegistry.new()
## Set by the client: the EffectPlayer (it knows how to build an emitter) and the camera to follow.
var effects
var camera: Camera3D
## Read by tests: which weather is drawn and how strongly it has faded in.
var current := -1
var shown := 0.0

var _wanted := -1
var _target := 0.0
var _particles: CPUParticles3D = null
var _voice: AudioStreamPlayer = null
var _sounds


func _ready() -> void:
	set_process(true)


## The server's instruction. -1 is a clear sky. Not called show(): Node3D already has one.
func apply(weather_id: int, intensity: float) -> void:
	_wanted = weather_id if registry.is_valid(weather_id) else -1
	_target = clampf(intensity, 0.0, 1.0) if _wanted >= 0 else 0.0
	if _wanted >= 0 and current != _wanted:
		_build(_wanted)


func _build(weather_id: int) -> void:
	_clear()
	current = weather_id
	var def: Dictionary = registry.defs[weather_id]
	if effects != null and def.emitter is Dictionary and not (def.emitter as Dictionary).is_empty():
		# The same builder effects use, so a mod writes one emitter vocabulary and not two. -1 seconds
		# because weather does not end on a timer; it ends when the server says so.
		_particles = effects._emitter(def.emitter, 1.0, Color.WHITE, -1.0)
		if _particles != null:
			add_child(_particles)
			_particles.emitting = true
	var sound_name := String(def.sound)
	if not sound_name.is_empty() and _sounds != null:
		var stream: AudioStream = _sounds.stream_named(sound_name)
		if stream != null:
			_voice = AudioStreamPlayer.new()
			_voice.bus = ClientSettings.BUS_WORLD
			_voice.stream = stream
			if stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			elif stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			add_child(_voice)
			_voice.play()


func _clear() -> void:
	for node in [_particles, _voice]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_particles = null
	_voice = null


func _process(delta: float) -> void:
	# Fade towards what the server asked for. Weather that snapped on would read as a bug.
	shown = move_toward(shown, _target, delta / FADE)
	if shown <= 0.001 and _wanted < 0 and current >= 0:
		_clear()
		current = -1
	if camera != null and _particles != null:
		# Above and slightly ahead: rain you fly into rather than rain that follows you about.
		global_position = camera.global_position + Vector3(0, 6, 0) - camera.global_basis.z * 3.0
		_particles.amount_ratio = shown
	if _voice != null:
		_voice.volume_db = linear_to_db(maxf(shown * 0.6, 0.0001))


## How much this weather is dimming the world, for whoever owns the light: 1.0 is untouched.
func light_scale() -> float:
	if current < 0 or shown <= 0.0:
		return 1.0
	return lerpf(1.0, float(registry.defs[current].light_scale), shown)


## The colour the sky is being pulled towards, and how far. Returns {} when nothing is happening.
func sky_tint() -> Dictionary:
	if current < 0 or shown <= 0.0:
		return {}
	var tint := String(registry.defs[current].sky_tint)
	if tint.is_empty() or not tint.is_valid_html_color():
		return {}
	return {"color": Color(tint), "amount": shown}
